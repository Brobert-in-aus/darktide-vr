#include "producer/particle_submission_probe.h"
#include "producer/particle_submission_snapshot.h"
#include "producer/guarded_copy.h"
#include "core/fingerprint.h"
#include <MinHook.h>
#include <array>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <string>

namespace darktidevr::producer {
namespace {
// Verified at every direct caller and the callee's stack loads in the exact
// executable: four pointers, stack sort key, stack float; return is unused.
using BuildKernel = void (*)(void*, void*, void*, void*, std::uint64_t, float);
BuildKernel original{};
ParticleEyeReader eye_reader{};
constexpr unsigned limit = 1024;
struct Record {
  ParticleSubmissionSnapshot snapshot{};
  ParticleEyeContext before{}, after{};
  std::uint64_t shader{}, transform{}, sort_key{};
  DWORD thread{};
  LONGLONG begin{}, end{};
};
std::array<Record, limit> records{};
std::atomic<unsigned> admitted{}, completed{};
std::atomic<bool> armed{};
std::atomic<ULONGLONG> next_poll{};
std::wstring flag;
HANDLE output = INVALID_HANDLE_VALUE;
LONGLONG frequency{};

bool write(const char* data, std::size_t bytes) {
  DWORD written{};
  return WriteFile(output, data, static_cast<DWORD>(bytes), &written, nullptr) && written == bytes;
}
void emit() {
  bool ok = true;
  for (unsigned i = 0; i < limit && ok; ++i) {
    const auto& r = records[i];
    const auto& s = r.snapshot;
    std::array<char, 385> constants{};
    constexpr char hex[] = "0123456789abcdef";
    for (std::size_t j = 0; j < s.constants.size(); ++j) {
      constants[j * 2] = hex[s.constants[j] >> 4];
      constants[j * 2 + 1] = hex[s.constants[j] & 15];
    }
    std::array<char, 2048> line{};
    const int n = std::snprintf(line.data(), line.size(),
        "PARTICLE sample=%u thread=%lu begin=%lld end=%lld valid=%u object=%llx resource=%llx "
        "object_tag=%x batch=%x shader=%llx transform=%llx sort=%llx update=%u buffer_serial=%u needed=%u "
        "buffer_a=%llx buffer_b=%llx handle_a=%x handle_b=%x present=%llu eye=%d pose=%llu queued=%llu arms=%llu resets=%llu "
        "after_present=%llu after_eye=%d after_pose=%llu after_queued=%llu after_arms=%llu after_resets=%llu constants=%s\n",
        i, r.thread, r.begin, r.end, s.valid ? 1U : 0U, s.object, s.resource,
        s.object_tag, s.batch_tag, r.shader, r.transform, r.sort_key,
        s.update_serial, s.buffer_serial, unsigned(s.update_needed),
        s.buffer_a, s.buffer_b, s.handle_a, s.handle_b,
        r.before.present, r.before.eye, r.before.pose, r.before.queued, r.before.arms, r.before.resets,
        r.after.present, r.after.eye, r.after.pose, r.after.queued, r.after.arms, r.after.resets, constants.data());
    ok = n > 0 && n < static_cast<int>(line.size()) && write(line.data(), static_cast<std::size_t>(n));
  }
  if (ok) {
    constexpr char footer[] = "PARTICLE_COMPLETE samples=1024\n";
    write(footer, sizeof(footer) - 1);
  }
  CloseHandle(output);
  output = INVALID_HANDLE_VALUE;
}

void hook(void* context, void* shader, void* batch, void* transform, std::uint64_t sort, float depth) {
  if (admitted.load(std::memory_order_relaxed) >= limit) {
    original(context, shader, batch, transform, sort, depth);
    return;
  }
  const DWORD entry_error = GetLastError();
  if (!armed.load(std::memory_order_acquire)) {
    const auto now = GetTickCount64();
    auto due = next_poll.load(std::memory_order_relaxed);
    if (now >= due && next_poll.compare_exchange_strong(due, now + 1000)) {
      if (GetPrivateProfileIntW(L"probe", L"capture", 0, flag.c_str()) == 1)
        armed.store(true, std::memory_order_release);
    }
  }
  const auto index = armed.load(std::memory_order_acquire)
      ? admitted.fetch_add(1, std::memory_order_relaxed) : limit;
  if (index >= limit) {
    SetLastError(entry_error);
    original(context, shader, batch, transform, sort, depth);
    return;
  }
  auto& record = records[index];
  record.thread = GetCurrentThreadId();
  record.shader = reinterpret_cast<std::uintptr_t>(shader);
  record.transform = reinterpret_cast<std::uintptr_t>(transform);
  record.sort_key = sort;
  record.before = eye_reader();
  record.snapshot = snapshot_particle_submission(reinterpret_cast<std::uintptr_t>(context),
      reinterpret_cast<std::uintptr_t>(batch), [](std::uint64_t address, void* to, std::size_t bytes) {
        return safe_copy_bytes(to, reinterpret_cast<const void*>(address), bytes);
      });
  LARGE_INTEGER stamp{};
  QueryPerformanceCounter(&stamp);
  record.begin = stamp.QuadPart;
  SetLastError(entry_error);
  original(context, shader, batch, transform, sort, depth);
  const DWORD exit_error = GetLastError();
  QueryPerformanceCounter(&stamp);
  record.end = stamp.QuadPart;
  record.after = eye_reader();
  // Each slot has one writer. The last completion acquires all earlier writes;
  // disk output is outside every recorded original-call duration.
  if (completed.fetch_add(1, std::memory_order_acq_rel) + 1 == limit) emit();
  SetLastError(exit_error);
}
}

bool install_particle_submission_probe(HMODULE module, ParticleEyeReader reader) {
  std::array<wchar_t, 32768> path{};
  auto size = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) return false;
  flag.assign(path.data(), size);
  const auto separator = flag.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return false;
  flag.resize(separator + 1);
  flag += L"darktidevr_particle_submission.flag";
  if (GetPrivateProfileIntW(L"probe", L"enabled", 0, flag.c_str()) != 1) return true;
  if (!reader) return false;
  size = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) return false;
  try {
    if (fingerprint_build(std::wstring(path.data(), size), std::nullopt).sha256 !=
        "6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3") return false;
  } catch (...) { return false; }
  constexpr std::array<unsigned char, 20> signature{
    0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10,
    0x48,0x89,0x7c,0x24,0x18,0x4c,0x89,0x74,0x24,0x20};
  auto* target = reinterpret_cast<std::byte*>(GetModuleHandleW(nullptr)) + 0x564e80;
  std::array<unsigned char, signature.size()> actual{};
  if (!safe_copy_bytes(actual.data(), target, actual.size()) || actual != signature) return false;
  LARGE_INTEGER value{};
  if (!QueryPerformanceFrequency(&value) || value.QuadPart <= 0) return false;
  frequency = value.QuadPart;
  std::array<wchar_t, MAX_PATH> temporary{};
  size = GetTempPathW(static_cast<DWORD>(temporary.size()), temporary.data());
  if (!size || size >= temporary.size()) return false;
  const auto file = std::wstring(temporary.data()) + L"darktidevr-particle-submission-" +
      std::to_wstring(GetCurrentProcessId()) + L".log";
  output = CreateFileW(file.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (output == INVALID_HANDLE_VALUE) return false;
  char header[256]{};
  const int n = std::snprintf(header, sizeof(header),
      "PARTICLE_BEGIN schema=1 pid=%lu frequency=%lld limit=1024 rva=564e80 eye_attribution_verified=0\n",
      GetCurrentProcessId(), frequency);
  eye_reader = reader;
  if (n <= 0 || n >= static_cast<int>(sizeof(header)) || !write(header, static_cast<std::size_t>(n)) ||
      MH_CreateHook(target, &hook, reinterpret_cast<void**>(&original)) != MH_OK) {
    CloseHandle(output);
    output = INVALID_HANDLE_VALUE;
    return false;
  }
  return true;
}
}
