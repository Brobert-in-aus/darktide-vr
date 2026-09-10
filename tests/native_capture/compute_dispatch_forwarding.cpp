#include "../../src/producer/compute_dispatch_probe.cpp"
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <fstream>

namespace {
using namespace darktidevr::producer::compute_probe;
thread_local std::array<std::byte, 0x300> test_context{};
thread_local std::array<std::byte, 0x100> test_payload{};
std::atomic<unsigned> dispatch_calls{}, bind_calls{};
void check(bool value) { if (!value) throw std::runtime_error("compute forwarding mismatch"); }
bool mock_bind(void* a, void* b, void* c, void* d, bool alternate, bool secondary,
               std::uint32_t stage, void* root) {
  check(a == test_payload.data() && b == test_context.data() && c == a && d == b &&
        alternate && stage == 0xfedcba98 && root == a && GetLastError() == 0x1234);
  ++bind_calls;
  SetLastError(0x2345);
  return secondary;
}
void mock_dispatch(void* context, void* payload, std::uint64_t sort, bool alternate, std::uint32_t flags) {
  check(context == test_context.data() && payload == test_payload.data() &&
        sort == 0xfedcba9876543210ULL && alternate && flags == 0x87654321 && GetLastError() == 0x1234);
  ++dispatch_calls;
  for (bool result : {false, true}) {
    SetLastError(0x1234);
    check(bind_hook(payload, context, payload, context, true, result, 0xfedcba98, payload) == result);
    check(GetLastError() == 0x2345);
  }
  const std::uint64_t root = 789;
  std::memcpy(test_context.data() + 0x278, &root, sizeof(root));
  SetLastError(0x3456);
}
}
int main() {
  using namespace darktidevr::producer::compute_probe;
  dispatch_original = mock_dispatch;
  bind_original = mock_bind;
  present_reader = +[] { return std::uint64_t{77}; };
  next_poll = ~ULONGLONG{};
  const auto invoke = [] {
    SetLastError(0x1234);
    dispatch_hook(test_context.data(), test_payload.data(), 0xfedcba9876543210ULL, true, 0x87654321);
    check(GetLastError() == 0x3456 && current == nullptr && !binding_active);
  };
  invoke();
  check(dispatch_calls == 1 && bind_calls == 2 && admitted == 0);
  armed = true;
  invoke();
  check(dispatch_calls == 2 && bind_calls == 4 && completed == 1);
  const auto& r = records[0];
  check(r.metadata_valid && r.flags_valid && r.root_before_valid && r.root_after_valid &&
      r.root_before == 789 && r.root_after == 789 && r.present == 77 && r.binding_calls == 2 &&
      r.binding_successes == 1 && r.binding_ticks >= 0 && r.end - r.begin >= r.binding_ticks);
  admitted = record_limit;
  invoke();
  check(dispatch_calls == 3 && bind_calls == 6 && completed == 1);
  std::uint32_t value{};
  check(!read_at(reinterpret_cast<void*>(~std::uintptr_t{}), 4, &value, 4));
  check(!read_at(nullptr, 4, &value, 4));
  wchar_t directory[MAX_PATH]{}, file[MAX_PATH]{};
  check(GetTempPathW(MAX_PATH, directory) != 0);
  check(GetTempFileNameW(directory, L"dvc", 0, file) != 0);
  output = CreateFileW(file, GENERIC_WRITE, FILE_SHARE_READ, nullptr,
      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  check(output != INVALID_HANDLE_VALUE);
  admitted = 1;
  std::array<std::thread, 8> workers;
  for (auto& worker : workers) worker = std::thread([&] {
    for (unsigned i = 0; i < 512; ++i) invoke();
  });
  for (auto& worker : workers) worker.join();
  check(dispatch_calls == 4099 && bind_calls == 8198 && completed == record_limit && output == INVALID_HANDLE_VALUE);
  std::ifstream stream(file, std::ios::binary);
  const std::string text((std::istreambuf_iterator<char>(stream)), {});
  stream.close();
  check(DeleteFileW(file) != 0);
  check(text.ends_with("COMPUTE_COMPLETE samples=4096\n"));
  unsigned lines{};
  for (std::size_t pos = 0; (pos = text.find("COMPUTE sample=", pos)) != std::string::npos; ++pos) ++lines;
  check(lines == record_limit);
  std::cout << "PASS forwarding, bool/error preservation, nested timing, concurrent bounds and output\n";
}
