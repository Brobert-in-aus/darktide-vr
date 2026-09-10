#include "producer/engine_preparation_probe.h"
#include "producer/guarded_copy.h"
#include "core/fingerprint.h"
#include <MinHook.h>
#include <array>
#include <atomic>
#include <cstdio>
#include <sstream>
#include <string>

namespace darktidevr::producer {
namespace preparation_probe {
using Dynamic = void (*)(void*, void*, void*);
using Links = void (*)(void*);
Dynamic dynamic_original{};
Links links_original{};
PreparationPresentReader present_reader{};
constexpr std::array<unsigned, 2> limits{4096, 512};
constexpr std::array<std::uintptr_t, 2> targets{0x796370, 0x398870};
struct Record {
  std::uint64_t context{}, payload{}, resource{}, present{};
  LONGLONG begin{}, end{};
  DWORD thread{};
  std::array<std::uint32_t, 6> description{};
  std::uint32_t links_before{}, links_after{};
  bool description_valid{}, before_valid{}, after_valid{};
};
struct Stream {
  std::array<Record, 4096> records{};
  std::atomic<unsigned> admitted{}, completed{};
  HANDLE output{INVALID_HANDLE_VALUE};
};
std::array<Stream, 2> streams;
std::atomic<bool> armed{};
std::atomic<ULONGLONG> next_poll{};
std::wstring flag;
LONGLONG frequency{};
thread_local std::array<bool, 2> observing{};
thread_local unsigned dynamic_position{};

bool read_at(void* base, std::uint64_t offset, void* destination, std::size_t bytes) {
  const auto address = reinterpret_cast<std::uintptr_t>(base);
  constexpr std::uint64_t upper = 0x0000800000000000;
  return address >= 0x10000 && address < upper && offset < upper - address &&
      bytes <= upper - address - offset &&
      safe_copy_bytes(destination, reinterpret_cast<const void*>(address + offset), bytes);
}

void emit(unsigned kind) {
  auto& stream = streams[kind];
  std::ostringstream text;
  for (unsigned i = 0; i < limits[kind]; ++i) {
    const auto& r = stream.records[i];
    text << "PREPARATION sample=" << i << " kind=" << kind << " thread=" << r.thread
         << " present=" << r.present << " begin=" << r.begin << " end=" << r.end
         << " context=" << r.context << " payload=" << r.payload << " resource=" << r.resource
         << " description_valid=" << r.description_valid;
    for (unsigned j = 0; j < r.description.size(); ++j)
      text << " word" << j << '=' << r.description[j];
    text << " before_valid=" << r.before_valid << " links_before=" << r.links_before
         << " after_valid=" << r.after_valid << " links_after=" << r.links_after << '\n';
  }
  text << "PREPARATION_COMPLETE kind=" << kind << " samples=" << limits[kind] << '\n';
  const auto payload = text.str();
  DWORD written{};
  WriteFile(stream.output, payload.data(), static_cast<DWORD>(payload.size()), &written, nullptr);
  CloseHandle(stream.output);
  stream.output = INVALID_HANDLE_VALUE;
}

Record* reserve(unsigned kind) {
  auto& stream = streams[kind];
  if (observing[kind] || stream.admitted.load(std::memory_order_relaxed) >= limits[kind]) return nullptr;
  if (!armed.load(std::memory_order_acquire)) {
    const auto now = GetTickCount64();
    auto poll = next_poll.load(std::memory_order_relaxed);
    if (now >= poll && next_poll.compare_exchange_strong(poll, now + 1000, std::memory_order_relaxed) &&
        GetPrivateProfileIntW(L"probe", L"capture", 0, flag.c_str()) == 1)
      armed.store(true, std::memory_order_release);
    if (!armed.load(std::memory_order_acquire)) return nullptr;
  }
  // Dynamic updates are tiny and numerous. Spread the bounded capture over
  // several frames without adding a shared write to every unsampled call.
  if (kind == 0 && (++dynamic_position & 63U) != 0) return nullptr;
  auto index = stream.admitted.load(std::memory_order_relaxed);
  while (index < limits[kind]) {
    if (stream.admitted.compare_exchange_weak(index, index + 1, std::memory_order_relaxed)) {
      observing[kind] = true;
      auto& r = stream.records[index];
      r.thread = GetCurrentThreadId();
      r.present = present_reader();
      return &r;
    }
  }
  return nullptr;
}

void finish(unsigned kind) {
  observing[kind] = false;
  if (streams[kind].completed.fetch_add(1, std::memory_order_acq_rel) + 1 == limits[kind]) {
    try { emit(kind); }
    catch (...) {
      CloseHandle(streams[kind].output);
      streams[kind].output = INVALID_HANDLE_VALUE;
    }
  }
}

void dynamic_hook(void* context, void* description, void* resource) {
  const auto entry_error = GetLastError();
  auto* record = reserve(0);
  if (!record) {
    SetLastError(entry_error);
    dynamic_original(context, description, resource);
    return;
  }
  record->context = reinterpret_cast<std::uintptr_t>(context);
  record->payload = reinterpret_cast<std::uintptr_t>(description);
  record->resource = reinterpret_cast<std::uintptr_t>(resource);
  record->description_valid = read_at(description, 0, record->description.data(), sizeof(record->description));
  if (!record->description_valid) record->description = {};
  LARGE_INTEGER stamp{};
  QueryPerformanceCounter(&stamp);
  record->begin = stamp.QuadPart;
  SetLastError(entry_error);
  dynamic_original(context, description, resource);
  const auto exit_error = GetLastError();
  QueryPerformanceCounter(&stamp);
  record->end = stamp.QuadPart;
  finish(0);
  SetLastError(exit_error);
}

void links_hook(void* context) {
  const auto entry_error = GetLastError();
  auto* record = reserve(1);
  if (!record) {
    SetLastError(entry_error);
    links_original(context);
    return;
  }
  record->context = reinterpret_cast<std::uintptr_t>(context);
  record->before_valid = read_at(context, 0xd30, &record->links_before, sizeof(record->links_before));
  if (!record->before_valid) record->links_before = 0;
  LARGE_INTEGER stamp{};
  QueryPerformanceCounter(&stamp);
  record->begin = stamp.QuadPart;
  SetLastError(entry_error);
  links_original(context);
  const auto exit_error = GetLastError();
  QueryPerformanceCounter(&stamp);
  record->end = stamp.QuadPart;
  record->after_valid = read_at(context, 0xd30, &record->links_after, sizeof(record->links_after));
  if (!record->after_valid) record->links_after = 0;
  finish(1);
  SetLastError(exit_error);
}
}

bool install_engine_preparation_probe(HMODULE module, PreparationPresentReader reader) {
  using namespace preparation_probe;
  std::array<wchar_t, 32768> path{};
  auto size = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) return false;
  flag.assign(path.data(), size);
  const auto separator = flag.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return false;
  flag.resize(separator + 1);
  flag += L"darktidevr_engine_preparation.flag";
  if (GetPrivateProfileIntW(L"probe", L"enabled", 0, flag.c_str()) != 1) return true;
  if (!reader) return false;
  size = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) return false;
  try {
    if (fingerprint_build(std::wstring(path.data(), size), std::nullopt).sha256 !=
        "6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3") return false;
  } catch (...) { return false; }
  constexpr std::array<std::array<unsigned char, 20>, 2> signatures{{
    {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x48,0x89,0x7c,0x24,0x18,0x55,0x41,0x56,0x41,0x57},
    {0x48,0x8b,0xc4,0x48,0x81,0xec,0xc8,0x01,0x00,0x00,0x48,0x89,0x58,0xf8,0x48,0x8b,0xd9,0x48,0x89,0x68}
  }};
  auto* base = reinterpret_cast<std::byte*>(GetModuleHandleW(nullptr));
  for (unsigned i = 0; i < targets.size(); ++i) {
    std::array<unsigned char, 20> actual{};
    if (!safe_copy_bytes(actual.data(), base + targets[i], actual.size()) || actual != signatures[i]) return false;
  }
  LARGE_INTEGER stamp{};
  if (!QueryPerformanceFrequency(&stamp) || stamp.QuadPart <= 0) return false;
  frequency = stamp.QuadPart;
  std::array<wchar_t, MAX_PATH> temporary{};
  size = GetTempPathW(static_cast<DWORD>(temporary.size()), temporary.data());
  if (!size || size >= temporary.size()) return false;
  const auto close_logs = [] {
    for (auto& stream : streams) if (stream.output != INVALID_HANDLE_VALUE) {
      CloseHandle(stream.output);
      stream.output = INVALID_HANDLE_VALUE;
    }
  };
  for (unsigned i = 0; i < streams.size(); ++i) {
    const auto file = std::wstring(temporary.data()) + L"darktidevr-preparation-" +
        std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(i) + L".log";
    streams[i].output = CreateFileW(file.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    char header[256]{};
    const auto n = std::snprintf(header, sizeof(header),
        "PREPARATION_BEGIN schema=1 pid=%lu kind=%u rva=%llu frequency=%lld limit=%u stride=%u\n",
        GetCurrentProcessId(), i, static_cast<unsigned long long>(targets[i]), frequency, limits[i], i == 0 ? 64U : 1U);
    DWORD written{};
    if (streams[i].output == INVALID_HANDLE_VALUE || n <= 0 || n >= static_cast<int>(sizeof(header)) ||
        !WriteFile(streams[i].output, header, static_cast<DWORD>(n), &written, nullptr) || written != static_cast<DWORD>(n)) {
      close_logs();
      return false;
    }
  }
  present_reader = reader;
  if (MH_CreateHook(base + targets[0], &dynamic_hook, reinterpret_cast<void**>(&dynamic_original)) != MH_OK) {
    close_logs();
    return false;
  }
  if (MH_CreateHook(base + targets[1], &links_hook, reinterpret_cast<void**>(&links_original)) != MH_OK) {
    MH_RemoveHook(base + targets[0]);
    close_logs();
    return false;
  }
  return true;
}
}
