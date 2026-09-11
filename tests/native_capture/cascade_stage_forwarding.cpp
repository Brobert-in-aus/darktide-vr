#include "../../src/producer/cascade_stage_probe.cpp"
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <thread>

namespace {
using namespace darktidevr::producer::cascade_probe;
thread_local std::array<std::uint32_t, 12> settings{1,2,3,4,5,6,7,8,9,10,11,12};
thread_local std::array<std::uint32_t, 3> light{0,0,0x3f800000};
thread_local std::array<std::byte, 0x80> view{};
thread_local bool invalid{}, nested{};
std::atomic<unsigned> calls{};
std::atomic<std::uint64_t> generation{9};
void check(bool value) { if (!value) throw std::runtime_error("cascade forwarding mismatch"); }
void* selected_light() { return invalid ? reinterpret_cast<void*>(1) : light.data(); }
void invoke();
void mock(void* a, void* b, void* c, void* d, void* e, void* f) {
  check(a == settings.data() && b == reinterpret_cast<void*>(0x123456789abcdef0ULL) &&
      c == reinterpret_cast<void*>(0xfedcba9876543210ULL) && d == settings.data() + 4 &&
      e == selected_light() && f == view.data() && GetLastError() == 0x1234);
  ++calls;
  if (nested) { nested = false; invoke(); }
  SetLastError(0x3456);
}
void invoke() {
  SetLastError(0x1234);
  hook(settings.data(), reinterpret_cast<void*>(0x123456789abcdef0ULL),
      reinterpret_cast<void*>(0xfedcba9876543210ULL), settings.data() + 4,
      selected_light(), view.data());
  check(GetLastError() == 0x3456);
}
}

int main(int argc, char** argv) {
  using namespace darktidevr::producer::cascade_probe;
  original = mock;
  context_reader = +[](std::uint64_t* p, std::uint64_t* g) { *p = 77; *g = generation; };
  next_poll = ~ULONGLONG{};
  invoke(); check(admitted == 0 && completed == 0);
  armed = true; generation = 0;
  invoke(); check(admitted == 0 && completed == 0);
  generation = 9;
  LARGE_INTEGER qpc{}; check(QueryPerformanceFrequency(&qpc) != 0); frequency = qpc.QuadPart;
  wchar_t directory[MAX_PATH]{}, file[MAX_PATH]{};
  check(GetTempPathW(MAX_PATH, directory) != 0 && GetTempFileNameW(directory, L"dcs", 0, file) != 0);
  output = CreateFileW(file, GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  check(write_header());
  nested = true; invoke();
  check(admitted == 1 && completed == 1 && !observing && calls == 4);
  check(records[0].settings_valid && records[0].settings == settings &&
      records[0].light_valid && records[0].light == light && records[0].view_valid);
  invalid = true; invoke(); invalid = false;
  check(admitted == 2 && !records[1].light_valid && records[1].light == std::array<std::uint32_t, 3>{});
  std::uint32_t value{};
  check(!read_at(nullptr, 0, &value, sizeof(value)) &&
      !read_at(reinterpret_cast<void*>(~std::uintptr_t{}), 0x50, &value, sizeof(value)));
  std::array<std::thread, 8> workers;
  for (auto& worker : workers) worker = std::thread([] { for (unsigned i = 0; i < 64; ++i) invoke(); });
  for (auto& worker : workers) worker.join();
  check(admitted == limit && completed == limit && output == INVALID_HANDLE_VALUE && calls == 517);
  for (unsigned i = 0; i < limit; ++i) {
    const auto& r = records[i];
    check(r.thread && r.present == 77 && r.generation == 9 && r.begin > 0 && r.end >= r.begin);
    check(r.settings_valid && r.view_valid && (i == 1 ? !r.light_valid : r.light_valid));
  }
  invoke(); check(calls == 518 && admitted == limit && completed == limit);
  std::ifstream input(file, std::ios::binary);
  const std::string text((std::istreambuf_iterator<char>(input)), {}); input.close();
  check(text.starts_with("CASCADE_BEGIN schema=1 ") && text.ends_with("CASCADE_COMPLETE samples=256\n"));
  if (argc == 2) { std::ofstream copy(argv[1], std::ios::binary); copy << text; check(copy.good()); }
  check(DeleteFileW(file) != 0);
  std::cout << "cascade_forwarding=pass samples=256 calls=518 guards=disabled,world,reentry,invalid,concurrent,exhausted\n";
}
