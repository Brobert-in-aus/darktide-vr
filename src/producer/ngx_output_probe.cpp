#include "producer/ngx_output_probe.h"
#include "producer/ngx_parameter_reader.h"
#include "producer/ngx_capture_window.h"
#include <MinHook.h>
#include <array>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>
#include <winver.h>

namespace darktidevr::producer {
namespace {
using Evaluate = std::uint32_t (*)(void*, const void*, const void*, void*);
Evaluate original{};
HMODULE runtime{};
HANDLE log_file = INVALID_HANDLE_VALUE;
std::mutex log_mutex;
std::atomic<std::uint64_t> calls{};
std::atomic<std::uint32_t> samples{};
std::atomic<bool> probe_installed{};
NgxCaptureWindow capture_window;
constexpr std::uint64_t kCallLimit = 32768;
constexpr std::uint32_t kSampleLimit = 256;

bool readable(const void* address, std::size_t bytes) {
  MEMORY_BASIC_INFORMATION memory{};
  if (!address || VirtualQuery(address, &memory, sizeof(memory)) != sizeof(memory) ||
      memory.State != MEM_COMMIT || (memory.Protect & (PAGE_GUARD | PAGE_NOACCESS)))
    return false;
  const auto protection = memory.Protect & 0xff;
  if (protection != PAGE_READONLY && protection != PAGE_READWRITE &&
      protection != PAGE_WRITECOPY && protection != PAGE_EXECUTE_READ &&
      protection != PAGE_EXECUTE_READWRITE && protection != PAGE_EXECUTE_WRITECOPY)
    return false;
  const auto offset = reinterpret_cast<std::uintptr_t>(address) -
                      reinterpret_cast<std::uintptr_t>(memory.BaseAddress);
  return offset <= memory.RegionSize && bytes <= memory.RegionSize - offset;
}

bool verified_parameters(const void* parameters) {
  if (!readable(parameters, sizeof(void*))) return false;
  const std::byte* table{};
  std::memcpy(&table, parameters, sizeof(table));
  constexpr auto slot = ngx::kGetD3D12ResourceSlot;
  if (!readable(table, (slot + 1) * sizeof(void*))) return false;
  const void* getter{};
  std::memcpy(&getter, table + slot * sizeof(void*), sizeof(getter));
  HMODULE owner{};
  return getter && GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
      GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
      reinterpret_cast<LPCWSTR>(getter), &owner) && owner == runtime;
}

void write_line(const char* line, std::size_t length) {
  std::scoped_lock lock(log_mutex);
  DWORD written{};
  WriteFile(log_file, line, static_cast<DWORD>(length), &written, nullptr);
}

std::uint32_t evaluate_hook(void* commands, const void* feature,
                            const void* parameters, void* callback) {
  const auto call = calls.fetch_add(1, std::memory_order_relaxed) + 1;
  const auto window = capture_window.snapshot(call, kCallLimit);
  std::array<ID3D12Resource*, 5> resources{};
  std::array<std::uint32_t, 5> results{};
  bool captured = false;
  bool abi_verified = false;
  if (window.eligible && samples.load(std::memory_order_relaxed) < kSampleLimit &&
      verified_parameters(parameters)) {
    abi_verified = true;
    results[0] = ngx::read_resource(parameters, "DLSSG.OutputInterpolated", &resources[0]);
    if (results[0] == ngx::kSuccess && resources[0] &&
        samples.fetch_add(1, std::memory_order_relaxed) < kSampleLimit) {
      constexpr std::array<const char*, 4> names{
          "DLSSG.Backbuffer", "DLSSG.Depth", "DLSSG.MVecs", "DLSSG.HUDLess"};
      for (std::size_t i = 0; i < names.size(); ++i)
        results[i + 1] = ngx::read_resource(parameters, names[i], &resources[i + 1]);
      captured = true;
    }
  }
  // The trampoline resumes INSIDE _nvngx.dll. Its internal feature call keeps
  // its real NVIDIA return address; no spoofed return or feature patch is used.
  const auto result = original(commands, feature, parameters, callback);
  if (captured || call <= 4 || (window.eligible &&
      (call-window.first_call <= 4 || call-window.first_call == kCallLimit))) {
    std::array<char, 1024> line{};
    const auto length = std::snprintf(line.data(), line.size(),
        "NGX_EVAL call=%llu tick_ms=%llu thread=%lu commands=%p feature=%p parameters=%p "
        "result=0x%08x captured=%u abi_verified=%u output=%p backbuffer=%p depth=%p motion=%p hudless=%p "
        "get_results=%x,%x,%x,%x,%x window_batch=%llu window_present=%llu window_first_call=%llu "
        "output_complete=0 publication=0\n",
        static_cast<unsigned long long>(call), GetTickCount64(), GetCurrentThreadId(),
        commands, feature, parameters, result, captured ? 1U : 0U, abi_verified ? 1U : 0U,
        static_cast<void*>(resources[0]), static_cast<void*>(resources[1]),
        static_cast<void*>(resources[2]), static_cast<void*>(resources[3]),
        static_cast<void*>(resources[4]), results[0], results[1], results[2], results[3], results[4],
        static_cast<unsigned long long>(window.batch), static_cast<unsigned long long>(window.present),
        static_cast<unsigned long long>(window.first_call));
    if (length > 0 && static_cast<std::size_t>(length) < line.size())
      write_line(line.data(), static_cast<std::size_t>(length));
  }
  // Pointer values are evidence only. Never dereference or retain a resource,
  // insert commands, wait on a queue, or publish generated metadata here.
  return result;
}

bool verified_runtime(const std::wstring& path) {
  DWORD ignored{};
  const auto bytes = GetFileVersionInfoSizeW(path.c_str(), &ignored);
  if (!bytes) return false;
  std::vector<std::byte> data(bytes);
  if (!GetFileVersionInfoW(path.c_str(), 0, bytes, data.data())) return false;
  VS_FIXEDFILEINFO* version{};
  UINT size{};
  return VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&version), &size) &&
      size >= sizeof(*version) && version->dwFileVersionMS == MAKELONG(0, 32) &&
      version->dwFileVersionLS == MAKELONG(1088, 16);
}
}  // namespace

void arm_ngx_output_probe(std::uint64_t batch, std::uint64_t present) {
  if (!probe_installed.load(std::memory_order_acquire)) return;
  capture_window.open(batch, present, calls.load(std::memory_order_relaxed));
}

bool install_ngx_output_probe(HMODULE capture_module) {
  std::array<wchar_t, 32768> path{};
  auto length = GetModuleFileNameW(capture_module, path.data(), static_cast<DWORD>(path.size()));
  if (!length || length >= path.size()) return false;
  std::wstring directory(path.data(), length);
  const auto separator = directory.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return false;
  directory.resize(separator + 1);
  const auto flag = directory + L"..\\darktidevr_ngx_output_probe.flag";
  if (GetFileAttributesW(flag.c_str()) ==
      INVALID_FILE_ATTRIBUTES) return true;
  const bool wait_for_stereo = GetPrivateProfileIntW(L"probe", L"wait_for_stereo", 0, flag.c_str()) != 0;
  capture_window.configure(wait_for_stereo);
  runtime = GetModuleHandleW(L"_nvngx.dll");
  if (!runtime) return false;
  length = GetModuleFileNameW(runtime, path.data(), static_cast<DWORD>(path.size()));
  if (!length || length >= path.size() || !verified_runtime(std::wstring(path.data(), length)))
    return false;
  const auto target = GetProcAddress(runtime, "NVSDK_NGX_D3D12_EvaluateFeature");
  constexpr std::array<unsigned char, 24> prologue{
      0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,
      0x48,0x89,0x74,0x24,0x18,0x57,0x41,0x56,0x41,0x57,
      0x48,0x83,0xec,0x30};
  if (!target || !readable(reinterpret_cast<const void*>(target), prologue.size()) ||
      std::memcmp(reinterpret_cast<const void*>(target), prologue.data(), prologue.size()))
    return false;
  length = GetTempPathW(static_cast<DWORD>(path.size()), path.data());
  if (!length || length >= path.size()) return false;
  const auto output = std::wstring(path.data(), length) + L"darktidevr-ngx-output-" +
                      std::to_wstring(GetCurrentProcessId()) + L".log";
  log_file = CreateFileW(output.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                         CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (log_file == INVALID_HANDLE_VALUE) return false;
  char header[256]{};
  const auto header_length = std::snprintf(header, sizeof(header),
      "ngx_output_probe=armed schema=2 runtime=32.0.16.1088 "
      "resource_get_slot=9 call_limit=32768 sample_limit=256 wait_for_stereo=%u publication=0\n",
      wait_for_stereo ? 1U : 0U);
  if (header_length > 0) write_line(header, static_cast<std::size_t>(header_length));
  if (MH_CreateHook(reinterpret_cast<void*>(target), &evaluate_hook,
                    reinterpret_cast<void**>(&original)) != MH_OK) {
    CloseHandle(log_file);
    log_file = INVALID_HANDLE_VALUE;
    return false;
  }
  probe_installed.store(true, std::memory_order_release);
  return true;
}
}  // namespace darktidevr::producer
