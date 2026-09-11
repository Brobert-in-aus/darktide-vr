#include "producer/cascade_stage_probe.h"
#include "producer/guarded_copy.h"
#include "core/fingerprint.h"
#include <MinHook.h>
#include <array>
#include <atomic>
#include <sstream>
#include <string>

namespace darktidevr::producer {
namespace cascade_probe {
// Verified call at 418156: four pointer registers, two pointer stack arguments.
// The sole observed direct caller discards the result; the callee ends in scope cleanup.
using Original = void (*)(void*, void*, void*, void*, void*, void*);
Original original{};
CascadeContextReader context_reader{};
constexpr unsigned limit = 256;
constexpr std::uintptr_t target = 0x419910;
struct Record {
  std::array<std::uint64_t, 6> args{};
  std::array<std::uint32_t, 12> settings{};
  std::array<std::uint32_t, 3> light{};
  std::array<std::uint32_t, 6> view{};
  std::uint64_t present{}, generation{};
  LONGLONG begin{}, end{};
  DWORD thread{};
  bool settings_valid{}, light_valid{}, view_valid{};
};
std::array<Record, limit> records;
std::atomic<unsigned> admitted{}, completed{};
std::atomic<bool> armed{};
std::atomic<ULONGLONG> next_poll{};
thread_local bool observing{};
std::wstring flag;
HANDLE output{INVALID_HANDLE_VALUE};
LONGLONG frequency{};

bool read_at(void* base, std::uint64_t offset, void* destination, std::size_t bytes) {
  const auto address = reinterpret_cast<std::uintptr_t>(base);
  constexpr std::uint64_t upper = 0x0000800000000000;
  return address >= 0x10000 && address < upper && offset < upper - address &&
      bytes <= upper - address - offset &&
      safe_copy_bytes(destination, reinterpret_cast<const void*>(address + offset), bytes);
}

bool write_text(const std::string& text) {
  DWORD written{};
  return output != INVALID_HANDLE_VALUE &&
      WriteFile(output, text.data(), static_cast<DWORD>(text.size()), &written, nullptr) &&
      written == text.size();
}

bool write_header() {
  return write_text("CASCADE_BEGIN schema=1 pid=" + std::to_string(GetCurrentProcessId()) +
      " rva=" + std::to_string(target) + " frequency=" + std::to_string(frequency) +
      " limit=" + std::to_string(limit) + "\n");
}

void emit() {
  std::ostringstream text;
  for (unsigned i = 0; i < limit; ++i) {
    const auto& r = records[i];
    text << "CASCADE sample=" << i << " thread=" << r.thread << " present=" << r.present
         << " generation=" << r.generation << " begin=" << r.begin << " end=" << r.end;
    for (unsigned j = 0; j < r.args.size(); ++j) text << " arg" << j << '=' << r.args[j];
    text << " settings_valid=" << r.settings_valid << " light_valid=" << r.light_valid
         << " view_valid=" << r.view_valid;
    for (unsigned j = 0; j < r.settings.size(); ++j) text << " settings" << j << '=' << r.settings[j];
    for (unsigned j = 0; j < r.light.size(); ++j) text << " light" << j << '=' << r.light[j];
    for (unsigned j = 0; j < r.view.size(); ++j) text << " view" << j << '=' << r.view[j];
    text << '\n';
  }
  text << "CASCADE_COMPLETE samples=" << limit << '\n';
  (void)write_text(text.str()); // Partial writes remain incomplete to the reader.
}

Record* reserve() {
  if (observing || admitted.load(std::memory_order_relaxed) >= limit) return nullptr;
  if (!armed.load(std::memory_order_acquire)) {
    const auto now = GetTickCount64();
    auto poll = next_poll.load(std::memory_order_relaxed);
    if (now >= poll && next_poll.compare_exchange_strong(poll, now + 1000, std::memory_order_relaxed) &&
        GetPrivateProfileIntW(L"probe", L"capture", 0, flag.c_str()) == 1)
      armed.store(true, std::memory_order_release);
    if (!armed.load(std::memory_order_acquire)) return nullptr;
  }
  std::uint64_t present{}, generation{};
  context_reader(&present, &generation);
  if (!present || !generation) return nullptr;
  auto index = admitted.load(std::memory_order_relaxed);
  while (index < limit) {
    if (admitted.compare_exchange_weak(index, index + 1, std::memory_order_relaxed)) {
      observing = true;
      auto& r = records[index];
      r.present = present; r.generation = generation; r.thread = GetCurrentThreadId();
      return &r;
    }
  }
  return nullptr;
}

void hook(void* a, void* b, void* c, void* d, void* e, void* f) {
  const auto entry_error = GetLastError();
  auto* record = reserve();
  if (!record) {
    SetLastError(entry_error);
    original(a, b, c, d, e, f);
    return;
  }
  record->args = {reinterpret_cast<std::uintptr_t>(a), reinterpret_cast<std::uintptr_t>(b),
      reinterpret_cast<std::uintptr_t>(c), reinterpret_cast<std::uintptr_t>(d),
      reinterpret_cast<std::uintptr_t>(e), reinterpret_cast<std::uintptr_t>(f)};
  record->settings_valid = read_at(a, 0, record->settings.data(), sizeof(record->settings));
  record->light_valid = read_at(e, 0, record->light.data(), sizeof(record->light));
  record->view_valid = read_at(f, 0x50, record->view.data(), sizeof(record->view));
  if (!record->settings_valid) record->settings = {};
  if (!record->light_valid) record->light = {};
  if (!record->view_valid) record->view = {};
  LARGE_INTEGER stamp{};
  QueryPerformanceCounter(&stamp); record->begin = stamp.QuadPart;
  SetLastError(entry_error);
  original(a, b, c, d, e, f);
  const auto exit_error = GetLastError();
  QueryPerformanceCounter(&stamp); record->end = stamp.QuadPart;
  observing = false;
  if (completed.fetch_add(1, std::memory_order_acq_rel) + 1 == limit) {
    try { emit(); } catch (...) { /* An incomplete log is never accepted. */ }
    CloseHandle(output); output = INVALID_HANDLE_VALUE;
  }
  SetLastError(exit_error);
}
}

bool install_cascade_stage_probe(HMODULE module, CascadeContextReader reader) {
  using namespace cascade_probe;
  std::array<wchar_t, 32768> path{};
  auto size = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) return false;
  flag.assign(path.data(), size);
  const auto separator = flag.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return false;
  flag.resize(separator + 1);
  flag += L"darktidevr_cascade_stage.flag";
  if (GetPrivateProfileIntW(L"probe", L"enabled", 0, flag.c_str()) != 1) return true;
  if (!reader) return false;
  size = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) return false;
  try {
    if (fingerprint_build(std::wstring(path.data(), size), std::nullopt).sha256 !=
        "6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3") return false;
  } catch (...) { return false; }
  constexpr std::array<unsigned char, 20> signature{
      0x4c,0x89,0x4c,0x24,0x20,0x4c,0x89,0x44,0x24,0x18,
      0x48,0x89,0x54,0x24,0x10,0x48,0x89,0x4c,0x24,0x08};
  auto* entry = reinterpret_cast<std::byte*>(GetModuleHandleW(nullptr)) + target;
  std::array<unsigned char, 20> actual{};
  if (!safe_copy_bytes(actual.data(), entry, actual.size()) || actual != signature) return false;
  LARGE_INTEGER stamp{};
  if (!QueryPerformanceFrequency(&stamp) || stamp.QuadPart <= 0) return false;
  frequency = stamp.QuadPart;
  std::array<wchar_t, MAX_PATH> temporary{};
  size = GetTempPathW(static_cast<DWORD>(temporary.size()), temporary.data());
  if (!size || size >= temporary.size()) return false;
  const auto file = std::wstring(temporary.data()) + L"darktidevr-cascade-stage-" +
      std::to_wstring(GetCurrentProcessId()) + L".log";
  output = CreateFileW(file.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (!write_header() || MH_CreateHook(entry, &hook, reinterpret_cast<void**>(&original)) != MH_OK) {
    if (output != INVALID_HANDLE_VALUE) CloseHandle(output);
    output = INVALID_HANDLE_VALUE;
    return false;
  }
  context_reader = reader;
  return true;
}
}
