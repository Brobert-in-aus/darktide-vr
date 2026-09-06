#include "producer/ngx_output_probe.h"
#include "producer/ngx_parameter_reader.h"
#include "producer/ngx_capture_window.h"
#include "producer/ngx_feature_registry.h"
#include "producer/ngx_command_observations.h"
#include "producer/ngx_output_state.h"
#include "producer/ngx_output_pair_state.h"
#include "producer/ngx_output_copy_probe.h"
#include <MinHook.h>
#include <d3d12.h>
#include <wrl/client.h>
#include <array>
#include <algorithm>
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
using Create = std::uint32_t (*)(void*, std::uint32_t, const void*, void**);
using Release = std::uint32_t (*)(const void*);
Create original_create{};
Release original_release{};
NgxFeatureRegistry feature_registry;
HMODULE runtime{};
HANDLE log_file = INVALID_HANDLE_VALUE;
HANDLE queue_log = INVALID_HANDLE_VALUE;
std::mutex command_mutex;
NgxCommandObservations command_observations;
NgxOutputPairState output_pair_state;
std::atomic<bool> pending_output_pair{};
std::atomic<unsigned> pending_commands{};
struct CompletionGroup {
  std::vector<std::uint64_t> calls;
  Microsoft::WRL::ComPtr<ID3D12Fence> fence;
  bool signaled{};
};
std::array<CompletionGroup, 256> completion_groups;
std::size_t completion_group_count{};
std::atomic<unsigned> pending_fences{};
struct ActiveEvaluationState {
  void* commands{};
  ID3D12Resource* output{};
  NgxOutputState observation;
  bool single_subresource{};
  struct Barrier {
    unsigned type{}, flags{}, subresource{}, before{}, after{};
    void* alias_before{};
    void* alias_after{};
  };
  std::array<Barrier, 32> barriers{};
  unsigned barrier_count{};
  bool truncated{};
  std::uint64_t seed_call{};
  NgxOutputState pair_observation;
};
thread_local ActiveEvaluationState* active_evaluation{};
std::mutex log_mutex;
std::atomic<std::uint64_t> calls{};
std::atomic<std::uint32_t> samples{};
std::atomic<unsigned> timing_samples{};
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

bool verified_parameters(const void* parameters, std::size_t slot) {
  if (!readable(parameters, sizeof(void*))) return false;
  const std::byte* table{};
  std::memcpy(&table, parameters, sizeof(table));
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

void record_slow_call(const char* operation, std::uint32_t kind,
                      std::uint64_t began) {
  const auto ended = GetTickCount64();
  if (ended - began < 50 || timing_samples.fetch_add(1) >= 256) return;
  std::scoped_lock lock(log_mutex);
  static HANDLE timing_file = INVALID_HANDLE_VALUE;
  if (timing_file == INVALID_HANDLE_VALUE) {
    std::array<wchar_t, MAX_PATH> directory{};
    const auto length = GetTempPathW(static_cast<DWORD>(directory.size()), directory.data());
    if (!length || length >= directory.size()) return;
    const auto path = std::wstring(directory.data(), length) + L"darktidevr-ngx-timing-" +
        std::to_wstring(GetCurrentProcessId()) + L".log";
    timing_file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  }
  if (timing_file == INVALID_HANDLE_VALUE) return;
  std::array<char, 256> line{};
  const auto length = std::snprintf(line.data(), line.size(),
      "NGX_TIMING operation=%s feature_kind=%u begin_ms=%llu end_ms=%llu duration_ms=%llu\n",
      operation, kind, began, ended, ended - began);
  DWORD written{};
  if (length > 0 && static_cast<std::size_t>(length) < line.size())
    WriteFile(timing_file, line.data(), static_cast<DWORD>(length), &written, nullptr);
}

void record_output_barriers(std::uint64_t call, const ActiveEvaluationState& state) {
  // Buffer inside the callback and write after Evaluate returns. This trace
  // establishes exact split/alias transitions without changing resource state.
  std::scoped_lock lock(log_mutex);
  static HANDLE state_file = INVALID_HANDLE_VALUE;
  if (state_file == INVALID_HANDLE_VALUE) {
    std::array<wchar_t, MAX_PATH> directory{};
    const auto length = GetTempPathW(static_cast<DWORD>(directory.size()), directory.data());
    if (!length || length >= directory.size()) return;
    const auto path = std::wstring(directory.data(), length) + L"darktidevr-ngx-state-" +
        std::to_wstring(GetCurrentProcessId()) + L".log";
    state_file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                             CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  }
  if (state_file == INVALID_HANDLE_VALUE) return;
  char line[512]{};
  DWORD written{};
  auto length = std::snprintf(line, sizeof(line),
      "NGX_STATE call=%llu commands=%p output=%p barriers=%u truncated=%u single_subresource=%u\n",
      call, state.commands, state.output, state.barrier_count,
      state.truncated ? 1U : 0U, state.single_subresource ? 1U : 0U);
  if (length > 0 && length < sizeof(line)) WriteFile(state_file, line, length, &written, nullptr);
  if (state.seed_call) {
    length = std::snprintf(line, sizeof(line),
        "NGX_PAIR call=%llu left_call=%llu commands=%p output=%p known=%u state=%u ambiguous=%u transitions=%u publication=0\n",
        call, state.seed_call, state.commands, state.output,
        state.pair_observation.known ? 1U : 0U, state.pair_observation.state,
        state.pair_observation.ambiguous ? 1U : 0U, state.pair_observation.transitions);
    if (length > 0 && length < sizeof(line)) WriteFile(state_file, line, length, &written, nullptr);
  }
  for (unsigned i = 0; i < state.barrier_count; ++i) {
    const auto& barrier = state.barriers[i];
    length = std::snprintf(line, sizeof(line),
        "NGX_BARRIER call=%llu index=%u type=%u flags=%u subresource=%u before=%u after=%u alias_before=%p alias_after=%p\n",
        call, i, barrier.type, barrier.flags, barrier.subresource, barrier.before,
        barrier.after, barrier.alias_before, barrier.alias_after);
    if (length > 0 && length < sizeof(line)) WriteFile(state_file, line, length, &written, nullptr);
  }
}

std::uint32_t create_hook(void* commands, std::uint32_t kind,
                           const void* parameters, void** handle) {
  const auto began = GetTickCount64();
  const auto result = original_create(commands, kind, parameters, handle);
  record_slow_call("create", kind, began);
  if (result == ngx::kSuccess && readable(handle, sizeof(void*)))
    feature_registry.created(*handle, kind, result);
  return result;
}
std::uint32_t release_hook(const void* handle) {
  feature_registry.releasing(handle);
  return original_release(handle);
}

std::uint32_t evaluate_hook(void* commands, const void* feature,
                            const void* parameters, void* callback) {
  const auto call = calls.fetch_add(1, std::memory_order_relaxed) + 1;
  const auto window = capture_window.snapshot(call, kCallLimit);
  const auto identity = feature_registry.lookup(feature);
  std::array<ID3D12Resource*, 5> resources{};
  std::array<std::uint32_t, 5> results{};
  D3D12_RESOURCE_DESC output_description{};
  std::array<unsigned int, 4> region{};
  std::array<std::uint32_t, 4> region_results{};
  std::array<unsigned int, 4> legacy_region{};
  std::array<std::uint32_t, 4> legacy_results{};
  bool captured = false;
  bool abi_verified = false;
  if (identity.kind == 11 && identity.lifetime != 0 && window.eligible &&
      samples.load(std::memory_order_relaxed) < kSampleLimit &&
      verified_parameters(parameters, ngx::kGetD3D12ResourceSlot) &&
      verified_parameters(parameters, ngx::kGetUnsignedSlot)) {
    abi_verified = true;
    results[0] = ngx::read_resource(parameters, "DLSSG.OutputInterpolated", &resources[0]);
    if (results[0] == ngx::kSuccess && resources[0] &&
        samples.fetch_add(1, std::memory_order_relaxed) < kSampleLimit) {
      constexpr std::array<const char*, 4> names{
          "DLSSG.Backbuffer", "DLSSG.Depth", "DLSSG.MVecs", "DLSSG.HUDLess"};
      for (std::size_t i = 0; i < names.size(); ++i)
        results[i + 1] = ngx::read_resource(parameters, names[i], &resources[i + 1]);
      // Inspect only during the live callback; retain no resource or parameter.
      output_description = resources[0]->GetDesc();
      constexpr std::array<const char*, 4> region_names{
          "DLSSG.OutputInterpolatedSubrectBaseX", "DLSSG.OutputInterpolatedSubrectBaseY",
          "DLSSG.OutputInterpolatedSubrectWidth", "DLSSG.OutputInterpolatedSubrectHeight"};
      for (std::size_t i = 0; i < region_names.size(); ++i)
        region_results[i] = ngx::read_unsigned(parameters, region_names[i], &region[i]);
      constexpr std::array<const char*, 4> legacy_names{
          "DLSSG.BackbufferSubrectBaseX", "DLSSG.BackbufferSubrectBaseY",
          "DLSSG.BackbufferSubrectWidth", "DLSSG.BackbufferSubrectHeight"};
      for (std::size_t i = 0; i < legacy_names.size(); ++i)
        legacy_results[i] = ngx::read_unsigned(parameters, legacy_names[i], &legacy_region[i]);
      captured = true;
    }
  }
  // The trampoline resumes INSIDE _nvngx.dll. Its internal feature call keeps
  // its real NVIDIA return address; no spoofed return or feature patch is used.
  ActiveEvaluationState output_state{commands, resources[0], {}};
  output_state.single_subresource = output_description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
      output_description.MipLevels == 1 && output_description.DepthOrArraySize == 1 &&
      output_description.Format == DXGI_FORMAT_R8G8B8A8_UNORM;
  const auto complete = captured && output_state.single_subresource &&
      output_description.Width == legacy_region[2] * 2ULL &&
      output_description.Height == legacy_region[3] && legacy_region[1] == 0 &&
      legacy_region[2] && legacy_region[3] &&
      std::all_of(results.begin(), results.end(), [](auto value) { return value == ngx::kSuccess; }) &&
      std::all_of(resources.begin(), resources.end(), [](auto value) { return value != nullptr; }) &&
      std::all_of(legacy_results.begin(), legacy_results.end(), [](auto value) { return value == ngx::kSuccess; });
  const NgxOutputPairState::Key pair_key{call, identity.lifetime, window.batch, window.present,
      reinterpret_cast<std::uintptr_t>(commands), reinterpret_cast<std::uintptr_t>(resources[0]),
      GetCurrentThreadId(), legacy_region[2], legacy_region[3]};
  {
    std::scoped_lock lock(command_mutex);
    if (complete && legacy_region[0] == legacy_region[2]) {
      if (const auto seed = output_pair_state.right(pair_key)) {
        output_state.seed_call = seed->key.call;
        output_state.pair_observation = seed->state;
      }
    } else output_pair_state.clear();
    pending_output_pair.store(false, std::memory_order_release);
  }
  const auto previous_evaluation = active_evaluation;
  if (captured) active_evaluation = &output_state;
  const auto began = GetTickCount64();
  const auto result = original(commands, feature, parameters, callback);
  active_evaluation = previous_evaluation;
  if (complete && result == ngx::kSuccess && output_state.seed_call &&
      output_state.pair_observation.known && !output_state.pair_observation.ambiguous &&
      output_state.pair_observation.state == D3D12_RESOURCE_STATE_UNORDERED_ACCESS &&
      std::none_of(resources.begin() + 1, resources.end(), [&](auto resource) { return resource == resources[0]; })) {
    stage_ngx_output_copy(static_cast<ID3D12GraphicsCommandList*>(commands), resources[0],
                          output_state.seed_call, call);
  }
  if (captured) record_output_barriers(call, output_state);
  record_slow_call("evaluate", identity.kind, began);
  if (captured && result == ngx::kSuccess) {
    std::scoped_lock lock(command_mutex);
    if (command_observations.add(reinterpret_cast<std::uintptr_t>(commands), call))
      pending_commands.fetch_add(1, std::memory_order_release);
    if (complete && legacy_region[0] == 0) {
      output_pair_state.left(pair_key, output_state.observation);
      pending_output_pair.store(output_state.observation.known, std::memory_order_release);
    }
  }
  if (captured || call <= 4 || (window.eligible &&
      (call-window.first_call <= 4 || call-window.first_call == kCallLimit))) {
    std::array<char, 1536> line{};
    const auto length = std::snprintf(line.data(), line.size(),
        "NGX_EVAL call=%llu tick_ms=%llu thread=%lu commands=%p feature=%p parameters=%p "
        "result=0x%08x captured=%u abi_verified=%u feature_kind=%u feature_lifetime=%llu "
        "output=%p backbuffer=%p depth=%p motion=%p hudless=%p "
        "get_results=%x,%x,%x,%x,%x window_batch=%llu window_present=%llu window_first_call=%llu "
        "output_width=%llu output_height=%u output_format=%u "
        "region_x=%u region_y=%u region_width=%u region_height=%u region_results=%x,%x,%x,%x "
        "legacy_x=%u legacy_y=%u legacy_width=%u legacy_height=%u legacy_results=%x,%x,%x,%x "
        "state_known=%u state_value=%u state_transitions=%u state_ambiguous=%u "
        "output_complete=0 publication=0\n",
        static_cast<unsigned long long>(call), GetTickCount64(), GetCurrentThreadId(),
        commands, feature, parameters, result, captured ? 1U : 0U, abi_verified ? 1U : 0U,
        identity.kind, static_cast<unsigned long long>(identity.lifetime),
        static_cast<void*>(resources[0]), static_cast<void*>(resources[1]),
        static_cast<void*>(resources[2]), static_cast<void*>(resources[3]),
        static_cast<void*>(resources[4]), results[0], results[1], results[2], results[3], results[4],
        static_cast<unsigned long long>(window.batch), static_cast<unsigned long long>(window.present),
        static_cast<unsigned long long>(window.first_call),
        static_cast<unsigned long long>(output_description.Width), output_description.Height,
        static_cast<unsigned>(output_description.Format), region[0], region[1], region[2], region[3],
        region_results[0], region_results[1], region_results[2], region_results[3],
        legacy_region[0], legacy_region[1], legacy_region[2], legacy_region[3],
        legacy_results[0], legacy_results[1], legacy_results[2], legacy_results[3],
        output_state.observation.known ? 1U : 0U, output_state.observation.state,
        output_state.observation.transitions, output_state.observation.ambiguous ? 1U : 0U);
    if (length > 0 && static_cast<std::size_t>(length) < line.size())
      write_line(line.data(), static_cast<std::size_t>(length));
  }
  // Descriptions and parameter values are evidence only. No retained resource,
  // inserted commands, queue waits or generated publication.
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

void observe_ngx_output_barriers(void* commands, unsigned count,
                                 const D3D12_RESOURCE_BARRIER* barriers) {
  const auto active = active_evaluation;
  if (pending_output_pair.load(std::memory_order_acquire)) {
    std::scoped_lock lock(command_mutex);
    output_pair_state.observe(reinterpret_cast<std::uintptr_t>(commands), [&](auto& pending) {
      auto* output = reinterpret_cast<ID3D12Resource*>(pending.key.output);
      for (unsigned i = 0; i < count; ++i) {
        const auto& barrier = barriers[i];
        if (barrier.Type == D3D12_RESOURCE_BARRIER_TYPE_TRANSITION && barrier.Transition.pResource == output)
          pending.state.transition(barrier.Flags, barrier.Transition.Subresource, barrier.Transition.StateAfter, true);
        else if (barrier.Type == D3D12_RESOURCE_BARRIER_TYPE_ALIASING &&
            (!barrier.Aliasing.pResourceBefore || !barrier.Aliasing.pResourceAfter ||
             barrier.Aliasing.pResourceBefore == output || barrier.Aliasing.pResourceAfter == output))
          pending.state.alias();
      }
    });
  }
  if (!active || active->commands != commands) return;
  for (unsigned i = 0; i < count; ++i) {
    const auto& barrier = barriers[i];
    if (barrier.Type == D3D12_RESOURCE_BARRIER_TYPE_TRANSITION &&
        barrier.Transition.pResource == active->output) {
      if (active->barrier_count < active->barriers.size()) {
        active->barriers[active->barrier_count++] = {
            static_cast<unsigned>(barrier.Type), static_cast<unsigned>(barrier.Flags),
            barrier.Transition.Subresource, static_cast<unsigned>(barrier.Transition.StateBefore),
            static_cast<unsigned>(barrier.Transition.StateAfter)};
      } else active->truncated = true;
      active->observation.transition(barrier.Flags, barrier.Transition.Subresource,
                                     barrier.Transition.StateAfter, active->single_subresource);
      if (active->seed_call) active->pair_observation.transition(barrier.Flags,
          barrier.Transition.Subresource, barrier.Transition.StateAfter, active->single_subresource);
    } else if (barrier.Type == D3D12_RESOURCE_BARRIER_TYPE_ALIASING &&
               (!barrier.Aliasing.pResourceBefore || !barrier.Aliasing.pResourceAfter ||
                barrier.Aliasing.pResourceBefore == active->output ||
                barrier.Aliasing.pResourceAfter == active->output)) {
      if (active->barrier_count < active->barriers.size()) {
        active->barriers[active->barrier_count++] = {
            static_cast<unsigned>(barrier.Type), static_cast<unsigned>(barrier.Flags), 0, 0, 0,
            barrier.Aliasing.pResourceBefore, barrier.Aliasing.pResourceAfter};
      } else active->truncated = true;
      active->observation.alias();
      if (active->seed_call) active->pair_observation.alias();
    }
  }
}

void observe_ngx_command_reset(void* commands) {
  if (!probe_installed.load(std::memory_order_acquire) ||
      !pending_commands.load(std::memory_order_acquire)) return;
  std::scoped_lock lock(command_mutex);
  output_pair_state.invalidate(reinterpret_cast<std::uintptr_t>(commands));
  command_observations.consume(reinterpret_cast<std::uintptr_t>(commands), [&](std::uint64_t call) {
    pending_commands.fetch_sub(1, std::memory_order_relaxed);
    char line[160]{};
    const auto length = std::snprintf(line, sizeof(line),
        "NGX_RESET call=%llu commands=%p submitted=0\n",
        static_cast<unsigned long long>(call), commands);
    DWORD written{};
    if (length > 0 && length < sizeof(line)) WriteFile(queue_log, line, length, &written, nullptr);
  });
}

std::uint64_t observe_ngx_queue_submit(ID3D12CommandQueue* queue, unsigned count,
                              ID3D12CommandList* const* commands) {
  if (!probe_installed.load(std::memory_order_acquire) ||
      !pending_commands.load(std::memory_order_acquire)) return 0;
  std::scoped_lock lock(command_mutex);
  std::uint64_t ticket{};
  for (unsigned i = 0; i < count; ++i) {
    output_pair_state.invalidate(reinterpret_cast<std::uintptr_t>(commands[i]));
    command_observations.consume(reinterpret_cast<std::uintptr_t>(commands[i]), [&](std::uint64_t call) {
      pending_commands.fetch_sub(1, std::memory_order_relaxed);
      if (!ticket && completion_group_count < completion_groups.size())
        ticket = ++completion_group_count;
      if (ticket) completion_groups[ticket - 1].calls.push_back(call);
      char line[256]{};
      const auto length = std::snprintf(line, sizeof(line),
          "NGX_SUBMIT call=%llu commands=%p queue=%p queue_type=%u tick_ms=%llu thread=%lu gpu_complete=0\n",
          static_cast<unsigned long long>(call), commands[i], queue,
          static_cast<unsigned>(queue->GetDesc().Type), GetTickCount64(), GetCurrentThreadId());
      DWORD written{};
      if (length > 0 && length < sizeof(line)) WriteFile(queue_log, line, length, &written, nullptr);
    });
  }
  return ticket;
}

void signal_ngx_queue_completion(ID3D12CommandQueue* queue, std::uint64_t ticket) {
  if (!ticket) return;
  Microsoft::WRL::ComPtr<ID3D12Device> device;
  Microsoft::WRL::ComPtr<ID3D12Fence> fence;
  auto result = queue->GetDevice(IID_PPV_ARGS(&device));
  if (SUCCEEDED(result)) result = device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence));
  if (SUCCEEDED(result)) result = queue->Signal(fence.Get(), 1);
  std::scoped_lock lock(command_mutex);
  auto& group = completion_groups[ticket - 1];
  group.fence = fence;
  group.signaled = SUCCEEDED(result);
  if (group.signaled) pending_fences.fetch_add(1, std::memory_order_release);
  for (const auto call : group.calls) {
    char line[192]{};
    const auto length = std::snprintf(line, sizeof(line),
        "NGX_FENCE call=%llu ticket=%llu queue=%p fence=%p value=1 result=0x%08x gpu_complete=0\n",
        static_cast<unsigned long long>(call), static_cast<unsigned long long>(ticket),
        queue, fence.Get(), static_cast<unsigned>(result));
    DWORD written{};
    if (length > 0 && length < sizeof(line)) WriteFile(queue_log, line, length, &written, nullptr);
  }
}

void poll_ngx_queue_completion() {
  if (!probe_installed.load(std::memory_order_acquire) ||
      !pending_fences.load(std::memory_order_acquire)) return;
  std::scoped_lock lock(command_mutex);
  for (std::size_t index = 0; index < completion_group_count; ++index) {
    auto& group = completion_groups[index];
    if (!group.signaled || !group.fence) continue;
    const auto value = group.fence->GetCompletedValue();
    if (value == 0) continue;
    for (const auto call : group.calls) {
      if (value != UINT64_MAX) complete_ngx_output_copy(call);
      char line[192]{};
      const auto length = std::snprintf(line, sizeof(line),
          "NGX_COMPLETE call=%llu ticket=%llu fence=%p completed=%llu gpu_complete=%u publication=0\n",
          static_cast<unsigned long long>(call), static_cast<unsigned long long>(index + 1),
          group.fence.Get(), static_cast<unsigned long long>(value), value == UINT64_MAX ? 0U : 1U);
      DWORD written{};
      if (length > 0 && length < sizeof(line)) WriteFile(queue_log, line, length, &written, nullptr);
    }
    group.signaled = false;
    pending_fences.fetch_sub(1, std::memory_order_relaxed);
    group.fence.Reset();
  }
}

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
  configure_ngx_output_copy(wait_for_stereo &&
      GetPrivateProfileIntW(L"probe", L"copy_output", 0, flag.c_str()) != 0);
  capture_window.configure(wait_for_stereo);
  runtime = GetModuleHandleW(L"_nvngx.dll");
  if (!runtime) return false;
  length = GetModuleFileNameW(runtime, path.data(), static_cast<DWORD>(path.size()));
  if (!length || length >= path.size() || !verified_runtime(std::wstring(path.data(), length)))
    return false;
  const auto target = GetProcAddress(runtime, "NVSDK_NGX_D3D12_EvaluateFeature");
  const auto create_target = GetProcAddress(runtime, "NVSDK_NGX_D3D12_CreateFeature");
  const auto release_target = GetProcAddress(runtime, "NVSDK_NGX_D3D12_ReleaseFeature");
  constexpr std::array<unsigned char, 24> prologue{
      0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,
      0x48,0x89,0x74,0x24,0x18,0x57,0x41,0x56,0x41,0x57,
      0x48,0x83,0xec,0x30};
  if (!target || !readable(reinterpret_cast<const void*>(target), prologue.size()) ||
      std::memcmp(reinterpret_cast<const void*>(target), prologue.data(), prologue.size()))
    return false;
  constexpr std::array<unsigned char,14> create_prologue{
      0x48,0x89,0x6c,0x24,0x20,0x57,0x41,0x56,0x41,0x57,0x48,0x83,0xec,0x40};
  constexpr std::array<unsigned char,6> release_prologue{0x40,0x57,0x48,0x83,0xec,0x20};
  if (!create_target || !release_target ||
      !readable(reinterpret_cast<const void*>(create_target), create_prologue.size()) ||
      !readable(reinterpret_cast<const void*>(release_target), release_prologue.size()) ||
      std::memcmp(reinterpret_cast<const void*>(create_target), create_prologue.data(), create_prologue.size()) ||
      std::memcmp(reinterpret_cast<const void*>(release_target), release_prologue.data(), release_prologue.size()))
    return false;
  length = GetTempPathW(static_cast<DWORD>(path.size()), path.data());
  if (!length || length >= path.size()) return false;
  const auto output = std::wstring(path.data(), length) + L"darktidevr-ngx-output-" +
                      std::to_wstring(GetCurrentProcessId()) + L".log";
  log_file = CreateFileW(output.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                         CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (log_file == INVALID_HANDLE_VALUE) return false;
  const auto queue_output = std::wstring(path.data(), length) + L"darktidevr-ngx-queue-" +
      std::to_wstring(GetCurrentProcessId()) + L".log";
  queue_log = CreateFileW(queue_output.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                          CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (queue_log == INVALID_HANDLE_VALUE) {
    CloseHandle(log_file);
    log_file = INVALID_HANDLE_VALUE;
    return false;
  }
  char header[256]{};
  const auto header_length = std::snprintf(header, sizeof(header),
      "ngx_output_probe=armed schema=6 runtime=32.0.16.1088 "
      "resource_get_slot=9 call_limit=32768 sample_limit=256 wait_for_stereo=%u publication=0\n",
      wait_for_stereo ? 1U : 0U);
  if (header_length > 0) write_line(header, static_cast<std::size_t>(header_length));
  if (MH_CreateHook(reinterpret_cast<void*>(target), &evaluate_hook,
                    reinterpret_cast<void**>(&original)) != MH_OK ||
      MH_CreateHook(reinterpret_cast<void*>(create_target), &create_hook,
                    reinterpret_cast<void**>(&original_create)) != MH_OK ||
      MH_CreateHook(reinterpret_cast<void*>(release_target), &release_hook,
                    reinterpret_cast<void**>(&original_release)) != MH_OK) {
    CloseHandle(log_file);
    CloseHandle(queue_log);
    queue_log = INVALID_HANDLE_VALUE;
    log_file = INVALID_HANDLE_VALUE;
    return false;
  }
  probe_installed.store(true, std::memory_order_release);
  return true;
}
}  // namespace darktidevr::producer
