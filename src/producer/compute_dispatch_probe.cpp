#include "producer/compute_dispatch_probe.h"
#include "producer/guarded_copy.h"
#include "core/fingerprint.h"
#include <MinHook.h>
#include <array>
#include <atomic>
#include <cstdio>
#include <sstream>
#include <string>

namespace darktidevr::producer {
namespace compute_probe {
using Dispatch = void (*)(void*, void*, std::uint64_t, bool, std::uint32_t);
using Bind = bool (*)(void*, void*, void*, void*, bool, bool, std::uint32_t, void*);
Dispatch dispatch_original{};
Bind bind_original{};
ComputePresentReader present_reader{};
constexpr unsigned record_limit = 4096;
struct Metadata {
  std::uint64_t resource{};
  std::uint32_t object{}, batch{}, ignored[3]{}, handle{};
};
static_assert(sizeof(Metadata) == 32);
struct Record {
  Metadata metadata{};
  std::uint64_t context{}, present{}, sort{}, root_before{}, root_after{};
  LONGLONG begin{}, end{}, binding_ticks{};
  DWORD thread{};
  std::uint32_t flags{}, caller_flags{}, binding_calls{}, binding_successes{};
  bool metadata_valid{}, flags_valid{}, root_before_valid{}, root_after_valid{}, alternate_queue{};
};
std::array<Record, record_limit> records{};
std::atomic<unsigned> admitted{}, completed{};
std::atomic<bool> armed{};
std::atomic<ULONGLONG> next_poll{};
thread_local Record* current{};
thread_local bool binding_active{};
std::wstring flag;
HANDLE output = INVALID_HANDLE_VALUE;
LONGLONG frequency{};

bool read_at(void* base, std::uint64_t offset, void* destination, std::size_t bytes) {
  const auto address = reinterpret_cast<std::uintptr_t>(base);
  constexpr std::uint64_t upper = 0x0000800000000000;
  return address >= 0x10000 && address < upper && offset < upper - address &&
      bytes <= upper - address - offset &&
      safe_copy_bytes(destination, reinterpret_cast<const void*>(address + offset), bytes);
}
void emit() {
  std::ostringstream text;
  for (unsigned i = 0; i < record_limit; ++i) {
    const auto& r = records[i];
    text << "COMPUTE sample=" << i << " thread=" << r.thread
         << " present=" << r.present << " begin=" << r.begin << " end=" << r.end
         << " binding_ticks=" << r.binding_ticks << " binding_calls=" << r.binding_calls
         << " binding_successes=" << r.binding_successes << " metadata_valid=" << r.metadata_valid
         << " flags_valid=" << r.flags_valid << " root_before_valid=" << r.root_before_valid
         << " root_after_valid=" << r.root_after_valid << " alternate_queue=" << r.alternate_queue
         << " context=" << std::hex << r.context << " resource=" << r.metadata.resource
         << " object=" << r.metadata.object << " batch=" << r.metadata.batch
         << " handle=" << r.metadata.handle << " sort=" << r.sort << " flags=" << r.flags
         << " caller_flags=" << r.caller_flags << " root_before=" << r.root_before
         << " root_after=" << r.root_after << std::dec << '\n';
  }
  text << "COMPUTE_COMPLETE samples=4096\n";
  const auto bytes = text.str();
  DWORD written{};
  WriteFile(output, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr);
  CloseHandle(output);
  output = INVALID_HANDLE_VALUE;
}

bool bind_hook(void* layout, void* context, void* resources, void* parameters,
               bool alternate, bool secondary, std::uint32_t stage, void* root) {
  auto* record = current;
  if (!record || binding_active) return bind_original(layout, context, resources, parameters, alternate, secondary, stage, root);
  struct BindingScope {
    BindingScope() { binding_active = true; }
    ~BindingScope() { binding_active = false; }
  } binding_scope;
  const DWORD entry_error = GetLastError();
  LARGE_INTEGER begin{}, end{};
  QueryPerformanceCounter(&begin);
  SetLastError(entry_error);
  const bool result = bind_original(layout, context, resources, parameters, alternate, secondary, stage, root);
  const DWORD exit_error = GetLastError();
  QueryPerformanceCounter(&end);
  record->binding_ticks += end.QuadPart - begin.QuadPart;
  ++record->binding_calls;
  record->binding_successes += result ? 1U : 0U;
  SetLastError(exit_error);
  return result;
}

void dispatch_hook(void* context, void* payload, std::uint64_t sort, bool alternate, std::uint32_t caller_flags) {
  if (admitted.load(std::memory_order_relaxed) >= record_limit || current) {
    dispatch_original(context, payload, sort, alternate, caller_flags);
    return;
  }
  const DWORD entry_error = GetLastError();
  if (!armed.load(std::memory_order_acquire)) {
    const auto now = GetTickCount64();
    auto due = next_poll.load(std::memory_order_relaxed);
    if (now >= due && next_poll.compare_exchange_strong(due, now + 1000) &&
        GetPrivateProfileIntW(L"probe", L"capture", 0, flag.c_str()) == 1)
      armed.store(true, std::memory_order_release);
  }
  const auto index = armed.load(std::memory_order_acquire)
      ? admitted.fetch_add(1, std::memory_order_relaxed) : record_limit;
  if (index >= record_limit) {
    SetLastError(entry_error);
    dispatch_original(context, payload, sort, alternate, caller_flags);
    return;
  }
  auto& r = records[index];
  r.context = reinterpret_cast<std::uintptr_t>(context);
  r.present = present_reader();
  r.thread = GetCurrentThreadId();
  r.sort = sort;
  r.caller_flags = caller_flags;
  r.alternate_queue = alternate;
  r.metadata_valid = read_at(payload, 0x58, &r.metadata, sizeof(r.metadata));
  if (!r.metadata_valid) r.metadata = {};
  r.flags_valid = read_at(payload, 0x1c, &r.flags, sizeof(r.flags));
  if (!r.flags_valid) r.flags = 0;
  r.root_before_valid = read_at(context, 0x278, &r.root_before, sizeof(r.root_before));
  if (!r.root_before_valid) r.root_before = 0;
  struct Scope {
    explicit Scope(Record* record) { current = record; }
    ~Scope() { current = nullptr; }
  } scope(&r);
  LARGE_INTEGER stamp{};
  QueryPerformanceCounter(&stamp);
  r.begin = stamp.QuadPart;
  SetLastError(entry_error);
  dispatch_original(context, payload, sort, alternate, caller_flags);
  const DWORD exit_error = GetLastError();
  QueryPerformanceCounter(&stamp);
  r.end = stamp.QuadPart;
  current = nullptr;
  r.root_after_valid = read_at(context, 0x278, &r.root_after, sizeof(r.root_after));
  if (!r.root_after_valid) r.root_after = 0;
  if (completed.fetch_add(1, std::memory_order_acq_rel) + 1 == record_limit) {
    try { emit(); }
    catch (...) { CloseHandle(output); output = INVALID_HANDLE_VALUE; }
  }
  SetLastError(exit_error);
}
}

bool install_compute_dispatch_probe(HMODULE module, ComputePresentReader reader) {
  using namespace compute_probe;
  std::array<wchar_t, 32768> path{};
  auto size = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) return false;
  flag.assign(path.data(), size);
  const auto separator = flag.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return false;
  flag.resize(separator + 1);
  flag += L"darktidevr_compute_dispatch.flag";
  if (GetPrivateProfileIntW(L"probe", L"enabled", 0, flag.c_str()) != 1) return true;
  if (!reader) return false;
  size = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) return false;
  try {
    if (fingerprint_build(std::wstring(path.data(), size), std::nullopt).sha256 !=
        "6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3") return false;
  } catch (...) { return false; }
  constexpr std::array<unsigned char, 20> dispatch_signature{
    0x48,0x89,0x5c,0x24,0x18,0x55,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57,0x48,0x83,0xec,0x70};
  constexpr std::array<unsigned char, 20> bind_signature{
    0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x41,0x54,0x41,0x55};
  auto* base = reinterpret_cast<std::byte*>(GetModuleHandleW(nullptr));
  std::array<unsigned char, 20> actual{};
  if (!safe_copy_bytes(actual.data(), base + 0x7c8410, actual.size()) || actual != dispatch_signature ||
      !safe_copy_bytes(actual.data(), base + 0x7e21b0, actual.size()) || actual != bind_signature) return false;
  LARGE_INTEGER value{};
  if (!QueryPerformanceFrequency(&value) || value.QuadPart <= 0) return false;
  frequency = value.QuadPart;
  std::array<wchar_t, MAX_PATH> temporary{};
  size = GetTempPathW(static_cast<DWORD>(temporary.size()), temporary.data());
  if (!size || size >= temporary.size()) return false;
  const auto file = std::wstring(temporary.data()) + L"darktidevr-compute-dispatch-" +
      std::to_wstring(GetCurrentProcessId()) + L".log";
  output = CreateFileW(file.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (output == INVALID_HANDLE_VALUE) return false;
  char header[256]{};
  const auto n = std::snprintf(header, sizeof(header),
      "COMPUTE_BEGIN schema=1 pid=%lu frequency=%lld limit=4096 dispatch_rva=7c8410 binding_rva=7e21b0 gpu_timing=0\n",
      GetCurrentProcessId(), frequency);
  DWORD written{};
  present_reader = reader;
  if (n <= 0 || n >= static_cast<int>(sizeof(header)) ||
      !WriteFile(output, header, static_cast<DWORD>(n), &written, nullptr) || written != static_cast<DWORD>(n) ||
      MH_CreateHook(base + 0x7c8410, &dispatch_hook, reinterpret_cast<void**>(&dispatch_original)) != MH_OK ||
      MH_CreateHook(base + 0x7e21b0, &bind_hook, reinterpret_cast<void**>(&bind_original)) != MH_OK) {
    CloseHandle(output);
    output = INVALID_HANDLE_VALUE;
    return false;
  }
  return true;
}
}
