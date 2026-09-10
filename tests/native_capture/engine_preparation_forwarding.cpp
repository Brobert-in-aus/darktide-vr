#include "../../src/producer/engine_preparation_probe.cpp"
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <thread>

namespace {
using namespace darktidevr::producer::preparation_probe;
thread_local std::array<std::byte, 0xd40> context{};
thread_local std::array<std::uint32_t, 6> descriptor{10, 0xfedcba98, 1024, 7, 4, 8};
std::atomic<unsigned> dynamic_calls{}, link_calls{};
void check(bool value) { if (!value) throw std::runtime_error("preparation forwarding mismatch"); }
void mock_dynamic(void* a, void* b, void* c) {
  check(a == context.data() && b == descriptor.data() &&
      c == reinterpret_cast<void*>(0xaabbccdd11223344ULL) && GetLastError() == 0x1234);
  ++dynamic_calls;
  SetLastError(0x3456);
}
void mock_links(void* a) {
  check(a == context.data() && GetLastError() == 0x1234);
  std::uint32_t count{};
  std::memcpy(&count, context.data() + 0xd30, sizeof(count));
  ++count;
  std::memcpy(context.data() + 0xd30, &count, sizeof(count));
  ++link_calls;
  SetLastError(0x3456);
}
void invoke_dynamic() {
  SetLastError(0x1234);
  dynamic_hook(context.data(), descriptor.data(), reinterpret_cast<void*>(0xaabbccdd11223344ULL));
  check(GetLastError() == 0x3456 && !observing[0]);
}
void invoke_links() {
  SetLastError(0x1234);
  links_hook(context.data());
  check(GetLastError() == 0x3456 && !observing[1]);
}
}

int main() {
  using namespace darktidevr::producer::preparation_probe;
  dynamic_original = mock_dynamic;
  links_original = mock_links;
  present_reader = +[] { return std::uint64_t{77}; };
  next_poll = ~ULONGLONG{};
  invoke_dynamic(); invoke_links();
  check(streams[0].admitted == 0 && streams[1].admitted == 0);
  armed = true;
  invoke_dynamic(); invoke_links();
  check(streams[0].completed == 1 && streams[1].completed == 1);
  check(streams[0].records[0].description_valid && streams[0].records[0].description == descriptor);
  check(streams[1].records[0].before_valid && streams[1].records[0].after_valid &&
      streams[1].records[0].links_before == 1 && streams[1].records[0].links_after == 2);
  for (unsigned kind = 0; kind < 2; ++kind) streams[kind].admitted = limits[kind];
  invoke_dynamic(); invoke_links();
  check(streams[0].completed == 1 && streams[1].completed == 1);
  std::uint32_t value{};
  check(!read_at(nullptr, 0, &value, sizeof(value)));
  check(!read_at(reinterpret_cast<void*>(~std::uintptr_t{}), 0xd30, &value, sizeof(value)));
  wchar_t directory[MAX_PATH]{};
  std::array<std::array<wchar_t, MAX_PATH>, 2> files{};
  check(GetTempPathW(MAX_PATH, directory) != 0);
  for (unsigned kind = 0; kind < 2; ++kind) {
    check(GetTempFileNameW(directory, L"dvp", 0, files[kind].data()) != 0);
    streams[kind].output = CreateFileW(files[kind].data(), GENERIC_WRITE, FILE_SHARE_READ,
        nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    check(streams[kind].output != INVALID_HANDLE_VALUE);
    streams[kind].admitted = 1;
  }
  std::array<std::thread, 8> workers;
  for (auto& worker : workers) worker = std::thread([] {
    for (unsigned i = 0; i < 512; ++i) {
      invoke_dynamic();
      if (i < 64) invoke_links();
    }
  });
  for (auto& worker : workers) worker.join();
  check(dynamic_calls == 4099 && link_calls == 515);
  for (unsigned kind = 0; kind < 2; ++kind) {
    const auto& stream = streams[kind];
    check(stream.admitted == limits[kind] && stream.completed == limits[kind] && stream.output == INVALID_HANDLE_VALUE);
    for (unsigned i = 0; i < limits[kind]; ++i) {
      const auto& r = stream.records[i];
      check(r.thread && r.context && r.present == 77 && r.begin > 0 && r.end >= r.begin);
      check(kind ? r.before_valid && r.after_valid && r.links_after == r.links_before + 1 : r.description_valid);
    }
    std::ifstream input(files[kind].data(), std::ios::binary);
    const std::string text((std::istreambuf_iterator<char>(input)), {});
    input.close();
    check(DeleteFileW(files[kind].data()) != 0);
    check(text.ends_with("PREPARATION_COMPLETE kind=" + std::to_string(kind) +
        " samples=" + std::to_string(limits[kind]) + "\n"));
  }
  std::cout << "preparation_forwarding=pass dynamic=4096 links=512\n";
}
