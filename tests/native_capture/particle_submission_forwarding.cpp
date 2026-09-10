// Same translation unit permits testing the actual hook's bounded forwarding
// without patching an engine or exposing production-only test entry points.
#include "../../src/producer/particle_submission_probe.cpp"
#include <bit>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <fstream>

namespace {
std::atomic<unsigned> calls{};
void check(bool value) { if (!value) throw std::runtime_error("particle forwarding mismatch"); }
void target(void* context, void* shader, void* batch, void* transform,
            std::uint64_t sort, float depth) {
  check(context == reinterpret_cast<void*>(0x101) && shader == reinterpret_cast<void*>(0x202) &&
      batch == reinterpret_cast<void*>(0x303) && transform == reinterpret_cast<void*>(0x404));
  check(sort == 0xfedcba9876543210ULL && std::bit_cast<std::uint32_t>(depth) == 0x7fc12345);
  check(GetLastError() == 0x1357);
  ++calls;
  SetLastError(0x2468);
}
}
int main() {
  using namespace darktidevr::producer;
  original = target;
  eye_reader = +[] { SetLastError(0xbad); return ParticleEyeContext{77, 88, 1, 99, 0, 1}; };
  // Prevent configuration polling in the initially unarmed branch.
  next_poll = ~ULONGLONG{};
  const auto invoke = [] {
    SetLastError(0x1357);
    hook(reinterpret_cast<void*>(0x101), reinterpret_cast<void*>(0x202),
         reinterpret_cast<void*>(0x303), reinterpret_cast<void*>(0x404),
         0xfedcba9876543210ULL, std::bit_cast<float>(std::uint32_t{0x7fc12345}));
    check(GetLastError() == 0x2468);
  };
  invoke();
  check(calls == 1 && admitted == 0 && completed == 0);
  armed = true;
  invoke();
  check(calls == 2 && admitted == 1 && completed == 1 && !records[0].snapshot.valid &&
      records[0].before.eye == 1 && records[0].after.pose == 88 &&
      records[0].end >= records[0].begin);
  // Test the exhausted branch without emitting a diagnostic file.
  admitted = limit;
  invoke();
  check(calls == 3 && completed == 1);
  wchar_t directory[MAX_PATH]{}, file[MAX_PATH]{};
  check(GetTempPathW(MAX_PATH, directory) != 0);
  check(GetTempFileNameW(directory, L"dvp", 0, file) != 0);
  output = CreateFileW(file, GENERIC_WRITE, FILE_SHARE_READ, nullptr,
      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  check(output != INVALID_HANDLE_VALUE);
  admitted = 1;
  std::array<std::thread, 8> workers;
  for (auto& worker : workers) worker = std::thread([&] {
    for (unsigned i = 0; i < 128; ++i) invoke();
  });
  for (auto& worker : workers) worker.join();
  check(calls == 1027 && completed == limit && output == INVALID_HANDLE_VALUE);
  std::ifstream stream(file, std::ios::binary);
  const std::string text((std::istreambuf_iterator<char>(stream)), {});
  stream.close();
  check(DeleteFileW(file) != 0);
  check(text.ends_with("PARTICLE_COMPLETE samples=1024\n"));
  unsigned lines{};
  for (std::size_t pos = 0; (pos = text.find("PARTICLE sample=", pos)) != std::string::npos; ++pos) ++lines;
  check(lines == limit);
  std::cout << "PASS forwarding, float bits, LastError, concurrent bounds and complete output\n";
}
