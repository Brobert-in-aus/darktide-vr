#include "producer/buffer_registry.h"
#include "producer/pipeline_identity.h"
#include "producer/diagnostic_append_log.h"
#include "producer/shader_pair_snapshot.h"
#include "producer/resource_handle_trace.h"
#include "producer/ngx_output_probe.h"
#include "producer/ngx_gpu_timing.h"
#include "producer/ui_capture_blend.h"
#include "producer/stereo_ui_readback.h"
#include "producer/billboard_draw_readback.h"
#include "producer/billboard_resource_state.h"
#include <filesystem>
#include <fstream>
#include <thread>
#include <sstream>
#include "core/shared_object_name.h"
#include <Windows.h>
#include <d3d12.h>
#include <d3d12shader.h>
#include <dxcapi.h>
#include <dxgi1_6.h>
#include <winver.h>
#include <wrl/client.h>
#include <intrin.h>

#include <MinHook.h>

#include "core/gameplay_input.h"
#include "core/shared_head_pose.h"
#include "core/shared_controller_state.h"
#include "core/shared_gameplay_aim_state.h"
#include "core/shared_generated_frame_state.h"
#include "core/shared_menu_pointer_state.h"
#include "core/shared_presentation_state.h"
#include "core/shared_surface_policy.h"
#include "core/streamline_stereo_inputs.h"
#include "core/streamline_render_extent.h"
#include "core/streamline_present_binding.h"
#include "core/two_bone_ik.h"
#include "streamline_abi_2_7_30.h"
#include "producer/streamline_submission.h"
#include "producer/streamline_continuous_submission.h"
#include "producer/generated_stereo.h"
#include "producer/engine_eye_backbuffers.h"
#include "producer/desktop_mirror_blit.h"
#include <memory>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdarg>
#include <cstring>
#include <cstdio>
#include <deque>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#pragma comment(lib, "version.lib")

using Microsoft::WRL::ComPtr;

extern "C" __declspec(dllexport) int dtvr_set_focused_trace_phase(int phase);
extern "C" __declspec(dllexport) int dtvr_enable_marker_log();
extern "C" __declspec(dllexport) int dtvr_enable_cluster_trace();
extern "C" __declspec(dllexport) int
dtvr_set_cluster_light_visibility_fix(int enabled);
extern "C" __declspec(dllexport) int
dtvr_cluster_light_visibility_fix_active();

namespace {

using StingrayUploadFlushFn = void (*)(void* allocator);
using SlGetFeatureFunctionFn = int (*)(std::uint32_t, const char*, void**);
using SlGetNewFrameTokenFn = int (*)(void**, const std::uint32_t*);
using SlSetConstantsFn = int (*)(const void*, const void*, const void*);
using SlSetTagFn = int (*)(const void*, const void*, std::uint32_t, void*);
using SlSetTagForFrameFn = int (*)(const void*, const void*, const void*,
                                   std::uint32_t, void*);
using SlDlssGGetStateFn = int (*)(const void*, void*, const void*);
using SlDlssGSetOptionsFn = int (*)(const void*, const void*);

HMODULE native_capture_module{};
INIT_ONCE dxc_reflection_once = INIT_ONCE_STATIC_INIT;
HMODULE dxcompiler_module{};
DxcCreateInstanceProc dxc_create_instance{};
SlGetFeatureFunctionFn original_sl_get_feature_function{};
SlGetNewFrameTokenFn original_sl_get_new_frame_token{};
SlSetConstantsFn original_sl_set_constants{};
SlSetTagFn original_sl_set_tag{};
SlSetTagForFrameFn original_sl_set_tag_for_frame{};
std::atomic<SlDlssGGetStateFn> original_sl_dlssg_get_state{};
// DLSS-G feature calls are not thread-safe. Coordinate the game's calls and
// the bounded Present-thread completion observation through one lock.
std::mutex streamline_feature_api_mutex;
std::atomic<SlDlssGSetOptionsFn> original_sl_dlssg_set_options{};
void* streamline_feature_resolver_target{};
void* streamline_get_new_frame_token_target{};
void* streamline_set_constants_target{};
void* streamline_set_tag_target{};
void* streamline_set_tag_for_frame_target{};
void* streamline_native_present_target{};
std::atomic<std::uint64_t> streamline_feature_resolve_count{};
std::atomic<std::uint64_t> streamline_dlssg_state_count{};
std::atomic<std::uint64_t> streamline_dlssg_options_count{};
std::atomic<std::uint64_t> streamline_native_present_count{};
std::atomic<bool> streamline_copy_probe_requested{};
std::atomic<bool> streamline_transport_probe_requested{};
std::atomic<bool> streamline_input_snapshot_probe_requested{};
std::atomic<bool> streamline_target_token_probe_requested{};
std::atomic<bool> streamline_stereo_swapchain_probe_requested{};
std::atomic<bool> streamline_eye_target_probe_requested{};
std::atomic<bool> streamline_stereo_stage_probe_requested{};
std::atomic<bool> streamline_stereo_submit_probe_requested{};
std::atomic<DWORD> streamline_outer_present_thread{};
std::atomic<std::uint64_t> streamline_outer_present_active_frame{};
std::atomic<std::uint64_t> streamline_stereo_submission_present{};
std::atomic<std::uint64_t> streamline_submission_trace_start{};
std::atomic<std::uint64_t> streamline_native_burst_until_call{};
std::atomic<std::uint64_t> streamline_frame_token_call_count{};
std::atomic<std::uint64_t> streamline_set_constants_call_count{};
std::atomic<std::uint64_t> streamline_set_tag_call_count{};
std::atomic<std::uint32_t> streamline_tagging_api_modes{};
std::recursive_mutex streamline_tagging_api_mutex;
std::atomic<void*> streamline_latest_frame_token{};
std::atomic<std::uint64_t> streamline_latest_frame_token_call{};
std::atomic<std::uint32_t> streamline_latest_frame_index{UINT_MAX};
constexpr std::size_t kStreamlineFrameTokenHistorySize = 16;
std::array<std::atomic<void*>, kStreamlineFrameTokenHistorySize>
    streamline_frame_token_history_tokens{};
std::array<std::atomic<std::uint64_t>, kStreamlineFrameTokenHistorySize>
    streamline_frame_token_history_calls{};
std::array<std::atomic<std::uint32_t>, kStreamlineFrameTokenHistorySize>
    streamline_frame_token_history_indices{};
std::atomic<std::uint64_t> streamline_execute_count{};
std::atomic<std::int64_t> streamline_last_execute_qpc{};
std::atomic<std::uint64_t> streamline_last_execute_outer_frame{};
std::atomic<ID3D12CommandQueue*> streamline_last_execute_queue{};
std::atomic<DWORD> streamline_last_execute_thread{};
std::atomic<UINT> streamline_last_execute_list_count{};
std::atomic<UINT> streamline_last_execute_queue_type{};

constexpr std::size_t kStreamlineInputCount = 5;
constexpr UINT kStreamlineInputSampleWidth = 64;
constexpr UINT kStreamlineInputSampleHeight = 64;
constexpr UINT kStreamlineInputSampleRowPitch = 256;
constexpr std::uint64_t kStreamlineInputSampleBytes =
    static_cast<std::uint64_t>(kStreamlineInputSampleRowPitch) *
    kStreamlineInputSampleHeight;
constexpr std::array<const char*, kStreamlineInputCount>
    kStreamlineInputNames{"depth", "motion_vectors", "hudless_color",
                          "scaling_input_color", "scaling_output_color"};
constexpr std::array<darktidevr::core::StreamlineStereoResource,
                     kStreamlineInputCount>
    kStreamlinePolicyResources{
        darktidevr::core::StreamlineStereoResource::depth,
        darktidevr::core::StreamlineStereoResource::motion_vectors,
        darktidevr::core::StreamlineStereoResource::hudless_color,
        darktidevr::core::StreamlineStereoResource::scaling_input_color,
        darktidevr::core::StreamlineStereoResource::scaling_output_color};

struct StreamlineTaggedInput {
  ComPtr<ID3D12Resource> resource;
  D3D12_RESOURCE_STATES state{D3D12_RESOURCE_STATE_COMMON};
  std::uint64_t present_frame{};
  std::uint64_t pose_sequence{};
};

struct StreamlineConstantsObservation {
  bool valid{};
  darktidevr::producer::streamline_2_7_30::Constants constants{};
  void* frame_token{};
  std::uint64_t frame_token_call{};
  std::uint64_t constants_call{};
  std::uint64_t present_frame{};
  std::uint64_t pose_sequence{};
  std::uint32_t frame_index{UINT_MAX};
  std::uint32_t viewport{};
};

struct StreamlineOptionsObservation {
  std::uint32_t viewport{};
  std::uint32_t mode{};
  std::uint64_t present_frame{};
  bool valid{};
};
// Guarded by streamline_input_snapshot_mutex; no borrowed API pointers.
std::array<StreamlineOptionsObservation, 16> streamline_options_observations{};

struct StreamlineInputSnapshotState {
  darktidevr::producer::StreamlineSubmission submission;
  darktidevr::producer::StreamlineStereoTags::Inputs submission_inputs{};
  std::uint64_t submission_id{1};
  std::uint64_t submission_stage_fence{5};
  std::uint64_t submission_cleanup_fence{6};
  std::uint32_t submission_limit{1};
  bool submission_prepared{};
  std::uint32_t submission_context_samples{};
  bool submission_attempted{};
  bool submission_presented{};
  bool submission_cleanup_pending{};
  bool submission_cleanup_attempted{};
  bool submission_retired{};
  bool submission_refresh_armed{};
  std::uint32_t submission_refresh_mask{};
  std::array<StreamlineConstantsObservation, 2> submission_refresh_constants;
  std::array<ComPtr<ID3D12CommandAllocator>, 2> submission_refresh_allocators;
  std::array<ComPtr<ID3D12GraphicsCommandList>, 2> submission_refresh_commands;
  std::array<ComPtr<ID3D12Fence>, 2> submission_refresh_fences;
  bool completion_observation_started{};
  std::array<ComPtr<ID3D12Fence>, 2> input_completion_fences;
  std::array<std::uint64_t, 2> input_completion_values{};
  int next_eye{};
  bool pending{};
  bool complete{};
  bool failed{};
  bool readback_pending{};
  bool readback_complete{};
  bool stereo_backbuffer_pending{};
  bool stereo_backbuffer_complete{};
  bool transport_slot_reserved{};
  bool target_token_allocated{};
  bool present_target_observed{};
  bool present_stage_pending{};
  bool present_stage_complete{};
  std::size_t transport_slot_index{};
  void* target_frame_token{};
  std::uint32_t target_frame_index{UINT_MAX};
  std::uint64_t present_frame{};
  std::uint64_t pose_sequence{};
  std::uint64_t fence_value{};
  std::uint64_t readback_bytes{};
  std::array<std::array<ComPtr<ID3D12Resource>, kStreamlineInputCount>, 2>
      sources;
  std::array<std::array<ComPtr<ID3D12Resource>, kStreamlineInputCount>, 2>
      snapshots;
  std::array<StreamlineConstantsObservation, 2> constants;
  std::array<ComPtr<ID3D12CommandAllocator>, 2> allocators;
  std::array<ComPtr<ID3D12GraphicsCommandList>, 2> commands;
  ComPtr<ID3D12CommandAllocator> readback_allocator;
  ComPtr<ID3D12GraphicsCommandList> readback_commands;
  ComPtr<ID3D12Resource> readback;
  std::array<std::array<D3D12_PLACED_SUBRESOURCE_FOOTPRINT,
                        kStreamlineInputCount>,
             2>
      readback_footprints;
  ComPtr<ID3D12CommandAllocator> stereo_backbuffer_allocator;
  ComPtr<ID3D12GraphicsCommandList> stereo_backbuffer_commands;
  ComPtr<ID3D12Resource> stereo_backbuffer;
  ComPtr<ID3D12Fence> fence;
  ComPtr<ID3D12CommandAllocator> present_stage_allocator;
  ComPtr<ID3D12GraphicsCommandList> present_stage_commands;
  ComPtr<ID3D12CommandAllocator> submission_cleanup_allocator;
  ComPtr<ID3D12GraphicsCommandList> submission_cleanup_commands;
};

std::mutex streamline_input_snapshot_mutex;
std::array<std::array<StreamlineTaggedInput, kStreamlineInputCount>, 2>
    streamline_tagged_inputs;
std::array<StreamlineConstantsObservation, 2>
    streamline_constants_observations;
StreamlineInputSnapshotState streamline_input_snapshot_state;
std::atomic<bool> streamline_continuous_requested{};
std::atomic<bool> streamline_persistent_requested{};
std::atomic<bool> streamline_packed_mirror_active{};
darktidevr::producer::StreamlineContinuousSubmission streamline_continuous;

bool game_process_foreground() {
  DWORD foreground_process{};
  GetWindowThreadProcessId(GetForegroundWindow(), &foreground_process);
  return foreground_process == GetCurrentProcessId();
}

// Caller holds streamline_input_snapshot_mutex.
std::array<darktidevr::core::StreamlinePresentEyeBinding, 2>
streamline_present_bindings() {
  std::array<darktidevr::core::StreamlinePresentEyeBinding, 2> result{};
  for (std::size_t eye = 0; eye < 2; ++eye) {
    const auto& current = streamline_constants_observations[eye];
    auto& binding = result[eye];
    binding = {current.valid, reinterpret_cast<std::uintptr_t>(current.frame_token),
               current.frame_token_call, current.frame_index,
               current.present_frame, current.pose_sequence, current.viewport};
    for (const auto& options : streamline_options_observations) {
      if (options.valid && options.viewport == current.viewport) {
        binding.options_valid = true;
        binding.mode = options.mode;
        binding.options_present = options.present_frame;
        break;
      }
    }
  }
  return result;
}

struct StreamlineExecuteSnapshot {
  std::atomic<std::uint64_t> call{};
  std::atomic<std::int64_t> qpc{};
  std::atomic<std::uint64_t> outer_frame{};
  std::atomic<ID3D12CommandQueue*> queue{};
  std::atomic<DWORD> thread{};
  std::atomic<UINT> list_count{};
  std::atomic<UINT> queue_type{};
  std::atomic<bool> present_transition{};
};

constexpr std::size_t kStreamlineExecuteHistory = 64;
std::array<StreamlineExecuteSnapshot, kStreamlineExecuteHistory>
    streamline_execute_history;

struct StreamlineCopyProbeState {
  bool attempted{};
  bool pending{};
  bool complete{};
  std::uint64_t native_call{};
  std::uint64_t outer_frame{};
  UINT source_x{};
  UINT source_y{};
  ComPtr<ID3D12CommandAllocator> allocator;
  ComPtr<ID3D12GraphicsCommandList> commands;
  ComPtr<ID3D12Resource> readback;
  ComPtr<ID3D12Fence> fence;
};

std::mutex streamline_copy_probe_mutex;
StreamlineCopyProbeState streamline_copy_probe_state;

struct StreamlineTransportSlot {
  bool pending{};
  bool reserved{};
  std::uint64_t sequence{};
  std::uint64_t native_call{};
  std::uint32_t frame_index{UINT_MAX};
  ComPtr<ID3D12CommandAllocator> allocator;
  ComPtr<ID3D12GraphicsCommandList> commands;
  ComPtr<ID3D12Resource> surface;
};

constexpr std::size_t kStreamlineTransportSlotCount =
    darktidevr::core::kSharedGeneratedFrameSlotCount;
constexpr std::uint64_t kStreamlineTransportSubmissionLimit = 120;
std::mutex streamline_transport_mutex;
std::array<StreamlineTransportSlot, kStreamlineTransportSlotCount>
    streamline_transport_slots;
std::uint64_t streamline_transport_submitted{};
std::uint64_t streamline_transport_completed{};
std::uint64_t streamline_transport_dropped{};
ComPtr<ID3D12Fence> streamline_transport_ready_fence;
ComPtr<ID3D12Fence> streamline_transport_consumed_fence;
std::array<HANDLE, kStreamlineTransportSlotCount>
    streamline_transport_surface_handles{};
HANDLE streamline_transport_ready_handle{};
HANDLE streamline_transport_consumed_handle{};

bool ensure_streamline_transport_resources(
    ID3D12Device* device, const D3D12_RESOURCE_DESC& source);
constexpr std::array<const wchar_t*, kStreamlineTransportSlotCount>
    kStreamlineTransportSurfaceNames{
        L"Local\\DarktideVR-generated-frame-0",
        L"Local\\DarktideVR-generated-frame-1",
        L"Local\\DarktideVR-generated-frame-2"};
constexpr wchar_t kStreamlineTransportReadyFenceName[] =
    L"Local\\DarktideVR-generated-frame-ready";
constexpr wchar_t kStreamlineTransportConsumedFenceName[] =
    L"Local\\DarktideVR-generated-frame-consumed";

BOOL CALLBACK initialize_dxc_reflection(PINIT_ONCE, PVOID, PVOID*) {
  std::array<wchar_t, 32768> module_path{};
  const auto length = GetModuleFileNameW(
      native_capture_module, module_path.data(),
      static_cast<DWORD>(module_path.size()));
  if (length == 0 || length >= module_path.size()) {
    return FALSE;
  }
  std::wstring path(module_path.data(), length);
  const auto separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return FALSE;
  }
  path.resize(separator + 1);
  path += L"dxcompiler.dll";
  dxcompiler_module = LoadLibraryExW(
      path.c_str(), nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!dxcompiler_module) {
    return FALSE;
  }
  dxc_create_instance = reinterpret_cast<DxcCreateInstanceProc>(
      GetProcAddress(dxcompiler_module, "DxcCreateInstance"));
  return dxc_create_instance ? TRUE : FALSE;
}

using ExecuteCommandListsFn = void(STDMETHODCALLTYPE*)(
    ID3D12CommandQueue*, UINT, ID3D12CommandList* const*);
using PresentFn = HRESULT(STDMETHODCALLTYPE*)(IDXGISwapChain*, UINT, UINT);
using SwapchainGetBufferFn = HRESULT(STDMETHODCALLTYPE*)(IDXGISwapChain*, UINT, REFIID, void**);
using SwapchainGetDescFn = HRESULT(STDMETHODCALLTYPE*)(IDXGISwapChain*, DXGI_SWAP_CHAIN_DESC*);
using SwapchainGetDesc1Fn = HRESULT(STDMETHODCALLTYPE*)(IDXGISwapChain1*, DXGI_SWAP_CHAIN_DESC1*);
using GetClientRectFn = BOOL(WINAPI*)(HWND, LPRECT);
using DispatchMessageWFn = LRESULT(WINAPI*)(const MSG*);
using ResizeBuffersFn = HRESULT(STDMETHODCALLTYPE*)(
    IDXGISwapChain*, UINT, UINT, UINT, DXGI_FORMAT, UINT);
using ResizeBuffers1Fn = HRESULT(STDMETHODCALLTYPE*)(
    IDXGISwapChain3*, UINT, UINT, UINT, DXGI_FORMAT, UINT, const UINT*,
    IUnknown* const*);
using MarkerEventFn = void(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*, UINT,
                                               const void*, UINT);
using EndEventFn = void(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*);
using CloseFn = HRESULT(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*);
using ResetFn = HRESULT(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*,
                                            ID3D12CommandAllocator*,
                                            ID3D12PipelineState*);
using ExecuteBundleFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, ID3D12GraphicsCommandList*);
using BeginRenderPassFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList4*, UINT,
    const D3D12_RENDER_PASS_RENDER_TARGET_DESC*,
    const D3D12_RENDER_PASS_DEPTH_STENCIL_DESC*, D3D12_RENDER_PASS_FLAGS);
using EndRenderPassFn = void(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList4*);
using DrawInstancedFn = void(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*,
                                                 UINT, UINT, UINT, UINT);
using DrawIndexedInstancedFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, UINT, UINT, UINT, INT, UINT);
using DispatchFn = void(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*, UINT,
                                            UINT, UINT);
using CopyBufferRegionFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, ID3D12Resource*, UINT64, ID3D12Resource*,
    UINT64, UINT64);
using CopyTextureRegionFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, const D3D12_TEXTURE_COPY_LOCATION*, UINT, UINT,
    UINT, const D3D12_TEXTURE_COPY_LOCATION*, const D3D12_BOX*);
using CopyResourceFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, ID3D12Resource*, ID3D12Resource*);
using ResolveSubresourceFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, ID3D12Resource*, UINT, ID3D12Resource*, UINT,
    DXGI_FORMAT);
using ExecuteIndirectFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, ID3D12CommandSignature*, UINT,
    ID3D12Resource*, UINT64, ID3D12Resource*, UINT64);
using RSSetViewportsFn = void(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*,
                                                  UINT,
                                                  const D3D12_VIEWPORT*);
using RSSetScissorRectsFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, UINT, const D3D12_RECT*);
using IASetPrimitiveTopologyFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, D3D12_PRIMITIVE_TOPOLOGY);
using SetPipelineStateFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, ID3D12PipelineState*);
using SetDescriptorHeapsFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, UINT, ID3D12DescriptorHeap* const*);
using SetGraphicsRootSignatureFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, ID3D12RootSignature*);
using SetComputeRootSignatureFn = SetGraphicsRootSignatureFn;
using SetGraphicsRootDescriptorTableFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, UINT, D3D12_GPU_DESCRIPTOR_HANDLE);
using SetComputeRootDescriptorTableFn = SetGraphicsRootDescriptorTableFn;
using SetGraphicsRoot32BitConstantFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, UINT, UINT, UINT);
using SetComputeRoot32BitConstantFn = SetGraphicsRoot32BitConstantFn;
using SetGraphicsRoot32BitConstantsFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, UINT, UINT, const void*, UINT);
using SetComputeRoot32BitConstantsFn = SetGraphicsRoot32BitConstantsFn;
using SetGraphicsRootGpuAddressFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, UINT, D3D12_GPU_VIRTUAL_ADDRESS);
using SetComputeRootGpuAddressFn = SetGraphicsRootGpuAddressFn;
using IASetIndexBufferFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, const D3D12_INDEX_BUFFER_VIEW*);
using IASetVertexBuffersFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, UINT, UINT, const D3D12_VERTEX_BUFFER_VIEW*);
using OMSetRenderTargetsFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, UINT, const D3D12_CPU_DESCRIPTOR_HANDLE*, BOOL,
    const D3D12_CPU_DESCRIPTOR_HANDLE*);
using CreateGraphicsPipelineStateFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12Device*, const D3D12_GRAPHICS_PIPELINE_STATE_DESC*, REFIID, void**);
using CreateComputePipelineStateFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12Device*, const D3D12_COMPUTE_PIPELINE_STATE_DESC*, REFIID, void**);
using CreateCommandSignatureFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12Device*, const D3D12_COMMAND_SIGNATURE_DESC*, ID3D12RootSignature*,
    REFIID, void**);
using CreateDescriptorHeapFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12Device*, const D3D12_DESCRIPTOR_HEAP_DESC*, REFIID, void**);
using CreateConstantBufferViewFn = void(STDMETHODCALLTYPE*)(
    ID3D12Device*, const D3D12_CONSTANT_BUFFER_VIEW_DESC*,
    D3D12_CPU_DESCRIPTOR_HANDLE);
using CreateShaderResourceViewFn = void(STDMETHODCALLTYPE*)(
    ID3D12Device*, ID3D12Resource*, const D3D12_SHADER_RESOURCE_VIEW_DESC*,
    D3D12_CPU_DESCRIPTOR_HANDLE);
using CreateUnorderedAccessViewFn = void(STDMETHODCALLTYPE*)(
    ID3D12Device*, ID3D12Resource*, ID3D12Resource*,
    const D3D12_UNORDERED_ACCESS_VIEW_DESC*, D3D12_CPU_DESCRIPTOR_HANDLE);
using CreateRenderTargetViewFn = void(STDMETHODCALLTYPE*)(
    ID3D12Device*, ID3D12Resource*, const D3D12_RENDER_TARGET_VIEW_DESC*,
    D3D12_CPU_DESCRIPTOR_HANDLE);
using CreateDepthStencilViewFn = void(STDMETHODCALLTYPE*)(
    ID3D12Device*, ID3D12Resource*, const D3D12_DEPTH_STENCIL_VIEW_DESC*,
    D3D12_CPU_DESCRIPTOR_HANDLE);
using CreateCommittedResourceFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12Device*, const D3D12_HEAP_PROPERTIES*, D3D12_HEAP_FLAGS,
    const D3D12_RESOURCE_DESC*, D3D12_RESOURCE_STATES,
    const D3D12_CLEAR_VALUE*, REFIID, void**);
using CreatePlacedResourceFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12Device*, ID3D12Heap*, UINT64, const D3D12_RESOURCE_DESC*,
    D3D12_RESOURCE_STATES, const D3D12_CLEAR_VALUE*, REFIID, void**);
using ResourceMapFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12Resource*, UINT, const D3D12_RANGE*, void**);
using ResourceUnmapFn = void(STDMETHODCALLTYPE*)(
    ID3D12Resource*, UINT, const D3D12_RANGE*);
using CopyDescriptorsSimpleFn = void(STDMETHODCALLTYPE*)(
    ID3D12Device*, UINT, D3D12_CPU_DESCRIPTOR_HANDLE,
    D3D12_CPU_DESCRIPTOR_HANDLE, D3D12_DESCRIPTOR_HEAP_TYPE);
using CopyDescriptorsFn = void(STDMETHODCALLTYPE*)(
    ID3D12Device*, UINT, const D3D12_CPU_DESCRIPTOR_HANDLE*, const UINT*, UINT,
    const D3D12_CPU_DESCRIPTOR_HANDLE*, const UINT*,
    D3D12_DESCRIPTOR_HEAP_TYPE);
using CreateRootSignatureFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12Device*, UINT, const void*, SIZE_T, REFIID, void**);
using CreatePipelineStateStreamFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12Device2*, const D3D12_PIPELINE_STATE_STREAM_DESC*, REFIID, void**);
using LoadGraphicsPipelineFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12PipelineLibrary*, LPCWSTR,
    const D3D12_GRAPHICS_PIPELINE_STATE_DESC*, REFIID, void**);
using LoadComputePipelineFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12PipelineLibrary*, LPCWSTR,
    const D3D12_COMPUTE_PIPELINE_STATE_DESC*, REFIID, void**);
using LoadPipelineFn = HRESULT(STDMETHODCALLTYPE*)(
    ID3D12PipelineLibrary1*, LPCWSTR,
    const D3D12_PIPELINE_STATE_STREAM_DESC*, REFIID, void**);
using ClearRenderTargetViewFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, D3D12_CPU_DESCRIPTOR_HANDLE, const FLOAT[4],
    UINT, const D3D12_RECT*);
using ClearDepthStencilViewFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, D3D12_CPU_DESCRIPTOR_HANDLE,
    D3D12_CLEAR_FLAGS, FLOAT, UINT8, UINT, const D3D12_RECT*);
using ResourceBarrierFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, UINT, const D3D12_RESOURCE_BARRIER*);
using EnhancedBarrierFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList7*, UINT32, const D3D12_BARRIER_GROUP*);

ExecuteCommandListsFn original_execute_command_lists{};
PresentFn original_present{};
SwapchainGetBufferFn original_swapchain_get_buffer{};
SwapchainGetDescFn original_swapchain_get_desc{};
SwapchainGetDesc1Fn original_swapchain_get_desc1{};
darktidevr::producer::EngineEyeBackbuffers engine_eye_backbuffers;
PresentFn original_streamline_native_present{};
GetClientRectFn original_get_client_rect{};
DispatchMessageWFn original_dispatch_message_w{};
ResizeBuffersFn original_resize_buffers{};
ResizeBuffers1Fn original_resize_buffers1{};
MarkerEventFn original_set_marker{};
MarkerEventFn original_begin_event{};
EndEventFn original_end_event{};
CloseFn original_close{};
ResetFn original_reset{};
ExecuteBundleFn original_execute_bundle{};
BeginRenderPassFn original_begin_render_pass{};
EndRenderPassFn original_end_render_pass{};
DrawInstancedFn original_draw_instanced{};
DrawIndexedInstancedFn original_draw_indexed_instanced{};
DispatchFn original_dispatch{};
CopyBufferRegionFn original_copy_buffer_region{};
CopyTextureRegionFn original_copy_texture_region{};
CopyResourceFn original_copy_resource{};
ResolveSubresourceFn original_resolve_subresource{};
ExecuteIndirectFn original_execute_indirect{};
RSSetViewportsFn original_rs_set_viewports{};
RSSetScissorRectsFn original_rs_set_scissor_rects{};
IASetPrimitiveTopologyFn original_ia_set_primitive_topology{};
SetPipelineStateFn original_set_pipeline_state{};
SetDescriptorHeapsFn original_set_descriptor_heaps{};
SetGraphicsRootSignatureFn original_set_graphics_root_signature{};
SetComputeRootSignatureFn original_set_compute_root_signature{};
SetGraphicsRootDescriptorTableFn original_set_graphics_root_descriptor_table{};
SetComputeRootDescriptorTableFn original_set_compute_root_descriptor_table{};
SetGraphicsRoot32BitConstantFn original_set_graphics_root_32bit_constant{};
SetComputeRoot32BitConstantFn original_set_compute_root_32bit_constant{};
SetGraphicsRoot32BitConstantsFn original_set_graphics_root_32bit_constants{};
SetComputeRoot32BitConstantsFn original_set_compute_root_32bit_constants{};
SetGraphicsRootGpuAddressFn original_set_graphics_root_constant_buffer_view{};
SetGraphicsRootGpuAddressFn original_set_graphics_root_shader_resource_view{};
SetGraphicsRootGpuAddressFn original_set_graphics_root_unordered_access_view{};
SetComputeRootGpuAddressFn original_set_compute_root_constant_buffer_view{};
SetComputeRootGpuAddressFn original_set_compute_root_shader_resource_view{};
SetComputeRootGpuAddressFn original_set_compute_root_unordered_access_view{};
IASetIndexBufferFn original_ia_set_index_buffer{};
IASetVertexBuffersFn original_ia_set_vertex_buffers{};
OMSetRenderTargetsFn original_om_set_render_targets{};
CreateGraphicsPipelineStateFn original_create_graphics_pipeline_state{};
CreateComputePipelineStateFn original_create_compute_pipeline_state{};
CreateCommandSignatureFn original_create_command_signature{};
CreateDescriptorHeapFn original_create_descriptor_heap{};
CreateConstantBufferViewFn original_create_constant_buffer_view{};
CreateShaderResourceViewFn original_create_shader_resource_view{};
CreateUnorderedAccessViewFn original_create_unordered_access_view{};
CreateRenderTargetViewFn original_create_render_target_view{};
CreateDepthStencilViewFn original_create_depth_stencil_view{};
CreateCommittedResourceFn original_create_committed_resource{};
CreatePlacedResourceFn original_create_placed_resource{};
ResourceMapFn original_resource_map{};
ResourceUnmapFn original_resource_unmap{};
StingrayUploadFlushFn original_stingray_upload_flush{};
CopyDescriptorsSimpleFn original_copy_descriptors_simple{};
CopyDescriptorsFn original_copy_descriptors{};
CreateRootSignatureFn original_create_root_signature{};
CreatePipelineStateStreamFn original_create_pipeline_state_stream{};
LoadGraphicsPipelineFn original_load_graphics_pipeline{};
LoadComputePipelineFn original_load_compute_pipeline{};
LoadPipelineFn original_load_pipeline{};
ClearRenderTargetViewFn original_clear_render_target_view{};
ClearDepthStencilViewFn original_clear_depth_stencil_view{};
ResourceBarrierFn original_resource_barrier{};
EnhancedBarrierFn original_enhanced_barrier{};
std::mutex state_mutex;
ComPtr<ID3D12CommandQueue> game_queue;
std::atomic<bool> game_queue_initialized{};
std::atomic<ID3D12CommandQueue*> game_queue_identity{};
// The first direct queue observed is suitable for the eye capture work, but it
// is not necessarily the queue DXGI's game swapchain is presented from.
// Injecting the desktop mirror on a different direct queue races Present and
// can expose a horizontal mixture of two eye frames.  Learn the authoritative
// queue from the command list that transitions a known swapchain buffer to
// PRESENT and use it exclusively for backbuffer injection.
ComPtr<ID3D12CommandQueue> swapchain_present_queue;
ComPtr<IDXGISwapChain3> game_swapchain;
// The swapchain identity and its back-buffer metadata are stable between
// successful ResizeBuffers calls. Keep a lock-free validity gate so Present
// does not QueryInterface/GetDesc/GetBuffer and rebuild the same set every
// frame merely to service the capture hooks.
std::atomic<IDXGISwapChain*> game_swapchain_identity{};
std::atomic<bool> game_swapchain_metadata_ready{};
std::array<ComPtr<ID3D12Resource>, 2> eye_surfaces;
ComPtr<ID3D12Resource> desktop_mirror_surface;
ComPtr<ID3D12Fence> desktop_mirror_fence;
std::uint64_t desktop_mirror_fence_value{};
std::atomic<bool> desktop_mirror_ready{};
std::atomic<std::uint64_t> desktop_mirror_error_count{};
ComPtr<ID3D12Fence> ready_fence;
ComPtr<ID3D12Fence> consumed_fence;
std::array<HANDLE, 2> eye_handles{};
HANDLE ready_fence_handle{};
HANDLE consumed_fence_handle{};
std::uint64_t ready_value{};
ComPtr<ID3D12Resource> menu_surface;
ComPtr<ID3D12DescriptorHeap> menu_rtv_heap;
D3D12_CPU_DESCRIPTOR_HANDLE menu_rtv{};
DXGI_FORMAT menu_rtv_format{DXGI_FORMAT_UNKNOWN};
ComPtr<ID3D12Fence> menu_ready_fence;
ComPtr<ID3D12Fence> menu_consumed_fence;
HANDLE menu_surface_handle{};
HANDLE menu_ready_fence_handle{};
HANDLE menu_consumed_fence_handle{};
std::atomic<HANDLE> projection_active_event{};
std::uint64_t menu_ready_value{};
// The stock pause/options renderer does not traverse the Lua SystemView hooks
// used by the earlier menu experiment. Detect its stable native UI shader
// instead, then copy the completed desktop UI buffer into the additive shared
// menu transport while the independent stereo eye path keeps running.
struct StockMenuShaderPair {
  std::uint64_t vertex_shader;
  std::uint64_t pixel_shader;
};

// A focused pre-menu/menu trace isolated one 28-draw, blended, depth-free
// batch on the 2112x2304 UI target. These seven pairs are the complete batch:
// panels, glyphs/icons and the remaining composited UI primitives. Keeping the
// measured set explicit avoids capturing unrelated full-screen blur/world
// passes merely because they also happen to be blended and depth-free.
constexpr std::array<StockMenuShaderPair, 7> kStockMenuShaderPairs{{
    {11843877247297039714ULL, 4205274772372006678ULL},
    {8136461109370980353ULL, 13875852906623432269ULL},
    {17803674457127970886ULL, 1391568350240996673ULL},
    {18107421411819155702ULL, 15477392111526461263ULL},
    {15208956507440652316ULL, 13151585653704074219ULL},
    {4066249119808695432ULL, 160970739098383160ULL},
    {8136461109370980353ULL, 18078296809113235737ULL},
}};

// The crafting view adds one retained GUI batch not used by the Escape menu.
// A hub/crafting state diff isolated this 180-vertex, 76-byte-stride draw from
// a separate 12-vertex, 48-byte-stride compositor pass.  Redirect only the GUI
// batch; redirecting both made the opaque compositor cover the shared menu and
// eventually hung the device.
constexpr StockMenuShaderPair kVendorMenuWidgetShaderPair{
    15643064314087379227ULL, 12642582357042194823ULL};
constexpr StockMenuShaderPair kOptionsWidgetShaderPair{
    8136461109370980353ULL, 13875852906623432269ULL};
// The completed swapchain contains an opaque copy of the world as well as the
// menu.  Feeding that texture to OpenXR necessarily produces the observed
// mono/flicker regression.  The stock UI draw redirect below instead builds a
// transparent menu-only surface while the stereo world remains untouched.
constexpr bool kStockMenuSwapchainCaptureEnabled = false;
constexpr bool kStockMenuDirectRenderEnabled = true;
constexpr bool kNamedMenuResourceCaptureEnabled = false;
constexpr bool kMenuLayerConsumerProbeEnabled = false;
std::atomic<unsigned int> current_presentation_mode{
    static_cast<unsigned int>(
        darktidevr::core::SharedPresentationMode::stereo_world)};
std::atomic<unsigned int> current_presentation_source_width{1};
std::atomic<unsigned int> current_presentation_source_height{1};
std::atomic<std::uint64_t> current_gameplay_generation{};
std::atomic<bool> vendor_menu_widget_capture_enabled{false};
// Menu shaders are reused by several retained UI scenes.  Redirecting them
// while no world-space menu is active can retain an old title/character-select
// target and replay it during later world Presents.  Lua enables this only for
// an explicitly classified interactive-menu presentation.
std::atomic<bool> menu_direct_capture_enabled{false};
thread_local unsigned int menu_draw_scope_depth{};
std::atomic<std::uint64_t> menu_draw_scope_redirect_count{};
std::atomic<std::uint64_t> stock_menu_draw_frame{
    (std::numeric_limits<std::uint64_t>::max)()};
std::atomic<std::uint64_t> direct_menu_render_frame{
    (std::numeric_limits<std::uint64_t>::max)()};
std::uint64_t direct_menu_clear_frame{
    (std::numeric_limits<std::uint64_t>::max)()};
std::unordered_map<ID3D12GraphicsCommandList*, ComPtr<ID3D12Resource>>
    direct_menu_render_lists;
std::uint64_t direct_menu_ui_stream_frame{
    (std::numeric_limits<std::uint64_t>::max)()};
std::array<std::atomic<ID3D12Resource*>, 2> options_layer_resources{};
// This count is a lock-free hint for the command-list hooks. The map remains
// authoritative under state_mutex, but ordinary gameplay should not serialize
// Close and Reset on an empty menu-redirection map.
std::atomic<std::uint64_t> direct_menu_render_list_count{};
std::atomic<bool> hooks_installed{};
std::atomic<std::uint64_t> execute_call_count{};
std::atomic<std::uint64_t> present_count{};
// OptionsView builds its settings pane in a retained typeless render target and
// only samples that completed target later in the UI command stream. Lua arms
// this for the current Present from _draw_grid; unlike the retired
// thread-local scope, the atomic survives the engine's asynchronous render
// recording thread.
std::atomic<std::uint64_t> options_menu_capture_armed_frame{
    (std::numeric_limits<std::uint64_t>::max)()};
std::atomic<std::uint64_t> marker_count{};
std::atomic<std::uint64_t> marker_sequence{};
std::atomic<std::uint64_t> command_recording_generation{};
std::atomic<int> capture_stage{};
std::atomic<bool> present_capture_enabled{};
std::atomic<bool> alternating_full_capture_enabled{};
std::atomic<bool> top_bottom_capture_enabled{};
std::atomic<int> alternating_present_eye{-1};
std::atomic<unsigned> alternating_seen_eyes{};
std::array<std::atomic<std::uint64_t>, 2> alternating_eye_copy_counts{};
std::atomic<std::uint64_t> alternating_eye_tag_count{};
std::atomic<int> alternating_last_capture_result{};
std::atomic<bool> table4_alias_eye0_to_eye1{};
std::atomic<std::uint64_t> table4_alias_count{};
std::atomic<std::uint64_t> table4_exact_match_count{};
std::atomic<std::uint64_t> table4_exact_ambiguous_count{};
std::atomic<bool> candidate_instance_clamp_enabled{};
std::atomic<std::uint64_t> candidate_instance_clamp_count{};
std::atomic<bool> candidate_table4_alias_enabled{};
std::atomic<std::uint64_t> candidate_table4_alias_count{};
std::atomic<std::uint64_t> candidate_table4_match_count{};
std::atomic<std::uint64_t> candidate_table4_ambiguous_count{};
std::atomic<bool> rich_center_sbs_remap_enabled{};
HANDLE marker_log{INVALID_HANDLE_VALUE};
HANDLE menu_resource_log{INVALID_HANDLE_VALUE};
std::mutex menu_resource_log_mutex;
std::atomic<std::uint64_t> menu_resource_log_count{};
HANDLE resize_diagnostic_log{INVALID_HANDLE_VALUE};
std::mutex resize_diagnostic_log_mutex;
std::atomic<std::uint64_t> resize_diagnostic_log_count{};
std::atomic<std::uint64_t> resize_diagnostic_generation{};
std::atomic<std::uint64_t> resize_diagnostic_burst_until_present{};
HANDLE streamline_probe_log{INVALID_HANDLE_VALUE};
std::mutex streamline_probe_log_mutex;
std::atomic<std::uint64_t> streamline_probe_log_count{};
std::atomic<std::uint64_t> streamline_probe_background_log_count{};
std::atomic<unsigned int> streamline_loaded_module_mask{};
HANDLE enhanced_barrier_log{INVALID_HANDLE_VALUE};
std::atomic<std::uint64_t> enhanced_barrier_log_count{};
std::atomic<int> focused_trace_phase{};
std::atomic<std::uint64_t> focused_trace_count{};
HANDLE focused_trace_log{INVALID_HANDLE_VALUE};
std::mutex focused_trace_mutex;
HANDLE cluster_trace_log{INVALID_HANDLE_VALUE};
std::mutex cluster_trace_mutex;
std::atomic<std::uint64_t> cluster_trace_count{};
std::atomic<bool> cluster_trace_saw_flat_presentation{};
constexpr std::uint64_t kClusterGridComputeShader = 0x356241c9944b66e7ULL;
constexpr std::uint64_t kClusterListWriterComputeShader =
    0x68d5ef81edcce164ULL;
constexpr std::uint64_t kClusterLightRasterVertexShader =
    0x5c6cd369626f261aULL;
constexpr std::uint64_t kClusterLightRasterPixelShader =
    0xbe559cb63c32aa02ULL;
std::atomic<std::uintptr_t> cluster_linked_list_resource{};
std::atomic<std::uint64_t> cluster_linked_list_learned_frame{};
std::atomic<std::uint64_t> cluster_generic_dispatch_log_count{};
std::atomic<std::uint64_t> cluster_target_dispatch_log_count{};
std::atomic<std::uint64_t> cluster_barrier_log_count{};
std::atomic<std::uint64_t> cluster_raster_binding_log_count{};
std::atomic<std::uint64_t> cluster_constant_copy_log_count{};
std::atomic<std::uint64_t> cluster_upload_flush_log_count{};
std::atomic<bool> cluster_light_visibility_fix_requested{};
std::atomic<bool> cluster_light_visibility_fix_active{};
std::atomic<std::uint64_t> cluster_light_visibility_fix_candidate_count{};
std::atomic<std::uint64_t> cluster_light_visibility_fix_patch_count{};
std::atomic<std::uint64_t> cluster_light_visibility_fix_reject_count{};
std::atomic<std::uint64_t> cluster_light_visibility_fix_target_draw_count{};
std::atomic<std::uint64_t> cluster_light_visibility_fix_root_missing_count{};
std::atomic<std::uint64_t> cluster_light_visibility_fix_resource_missing_count{};
struct ClusterConstantBufferCopy {
  ID3D12Resource* destination{};
  std::uint64_t destination_offset{};
  ID3D12Resource* source{};
  std::uint64_t source_offset{};
  std::uint64_t bytes{};
};
struct ClusterPendingConstantSample {
  ID3D12Resource* resource{};
  std::uint64_t resource_offset{};
  std::uint64_t gpu_address{};
  std::uint64_t frame{};
  ID3D12GraphicsCommandList* commands{};
  UINT root{};
  bool captured{};
};
struct ClusterPendingTransformSample {
  ID3D12Resource* resource{};
  std::uint64_t resource_offset{};
  std::uint64_t frame{};
  ID3D12GraphicsCommandList* commands{};
  std::uint64_t first_element{};
  std::uint32_t element_count{};
  std::uint32_t stride{};
  bool captured{};
};
struct ClusterPendingFovPatch {
  ID3D12Resource* resource{};
  std::uint64_t resource_offset{};
  std::uint64_t frame{};
  bool valid{};
};
std::mutex cluster_constant_copy_mutex;
std::unordered_set<ID3D12Resource*> cluster_constant_ring_resources;
std::array<ClusterConstantBufferCopy, 256> cluster_constant_copies{};
std::uint64_t cluster_constant_copy_count{};
std::array<ClusterPendingConstantSample, 64>
    cluster_pending_constant_samples{};
std::uint64_t cluster_pending_constant_count{};
std::array<ClusterPendingTransformSample, 32>
    cluster_pending_transform_samples{};
std::uint64_t cluster_pending_transform_count{};
std::mutex cluster_light_visibility_fix_mutex;
std::array<ClusterPendingFovPatch, 128>
    cluster_pending_fov_patches{};
std::uint64_t cluster_pending_fov_patch_cursor{};
struct ClusterGraphicsSubmission {
  std::uint64_t sequence{};
  std::uintptr_t pso{};
  const char* submission{};
  std::array<std::uint64_t, 5> arguments{};
};
struct ClusterSubmissionRing {
  std::array<ClusterGraphicsSubmission, 64> entries{};
  std::uint64_t write_count{};
};
std::mutex cluster_submission_mutex;
std::unordered_map<ID3D12GraphicsCommandList*, ClusterSubmissionRing>
    cluster_submission_rings;
HANDLE boundary_census_log{INVALID_HANDLE_VALUE};
std::mutex boundary_census_log_mutex;
std::atomic<std::uint64_t> boundary_census_log_count{};
std::atomic<bool> boundary_census_requested{};

struct PassKey {
  std::uintptr_t pso{};
  std::uintptr_t root_signature{};
  std::uint64_t render_target{};
  std::uint64_t depth_target{};
  UINT render_target_count{};
  UINT viewport_x{};
  UINT viewport_y{};
  UINT viewport_width{};
  UINT viewport_height{};
  int eye{-1};

  bool operator==(const PassKey& other) const {
    return pso == other.pso && root_signature == other.root_signature &&
           render_target == other.render_target &&
           depth_target == other.depth_target &&
           render_target_count == other.render_target_count &&
           viewport_x == other.viewport_x && viewport_y == other.viewport_y &&
           viewport_width == other.viewport_width &&
           viewport_height == other.viewport_height && eye == other.eye;
  }
};

struct PassKeyHash {
  std::size_t operator()(const PassKey& key) const {
    auto value = static_cast<std::size_t>(key.pso);
    value ^= static_cast<std::size_t>(key.root_signature +
                                      0x9e3779b97f4a7c15ULL +
                                      (value << 6) + (value >> 2));
    value ^= static_cast<std::size_t>(key.render_target +
                                      0x9e3779b97f4a7c15ULL +
                                      (value << 6) + (value >> 2));
    value ^= static_cast<std::size_t>(key.depth_target +
                                      0x9e3779b97f4a7c15ULL +
                                      (value << 6) + (value >> 2));
    value ^= static_cast<std::size_t>(key.render_target_count) * 0x85ebca6bU;
    value ^= static_cast<std::size_t>(key.viewport_x) * 0xc2b2ae35U;
    value ^= static_cast<std::size_t>(key.viewport_y) * 0x27d4eb2fU;
    value ^= static_cast<std::size_t>(key.viewport_width) * 0x165667b1U;
    value ^= static_cast<std::size_t>(key.viewport_height) * 0xd3a2646cU;
    value ^= static_cast<std::size_t>(key.eye + 2) * 0x9e3779b9U;
    return value;
  }
};

struct DescriptorInfo {
  char kind{'?'};
  std::uintptr_t resource{};
  std::uint64_t gpu_address{};
  UINT dimension{};
  std::uint64_t width{};
  UINT height{};
  UINT depth_or_array_size{};
  UINT mip_levels{};
  UINT format{};
  std::uint64_t first_element{};
  UINT element_count{};
  UINT structure_stride{};
};

DescriptorInfo descriptor_snapshot(std::uint64_t handle);

struct DescriptorHeapInfo {
  D3D12_DESCRIPTOR_HEAP_TYPE type{};
  UINT descriptor_count{};
  UINT increment{};
  std::uint64_t cpu_start{};
  std::uint64_t gpu_start{};
};

using darktidevr::producer::BufferResourceInfo;

struct TableProvenance {
  std::array<DescriptorInfo, 2> descriptors{};
  UINT descriptor_count{};
  std::uint64_t resource_hash{};
  std::uint64_t layout_hash{};
};

struct PassCounts {
  std::uint64_t draw{};
  std::uint64_t draw_indexed{};
  std::uint64_t dispatch{};
  std::uint64_t binding_hash{1469598103934665603ULL};
  std::uint64_t table_hash{1469598103934665603ULL};
  std::uint64_t constant_hash{1469598103934665603ULL};
  std::uint64_t cbv_hash{1469598103934665603ULL};
  std::uint64_t srv_hash{1469598103934665603ULL};
  std::uint64_t uav_hash{1469598103934665603ULL};
  std::array<std::uint64_t, 16> table_slot_hashes{};
  std::array<std::uint64_t, 16> cbv_slot_hashes{};
  std::array<std::uint64_t, 16> table_resource_hashes{};
  std::array<std::uint64_t, 16> table_layout_hashes{};
  std::array<DescriptorInfo, 2> table4_descriptors{};
  std::array<DescriptorInfo, 2> table7_descriptors{};
  bool table4_descriptors_captured{};
  bool table7_descriptors_captured{};
  std::uint64_t binding_samples{};
};

constexpr std::size_t kRootSlotCount = 32;

struct CommandTrace {
  bool render_pass_active{};
  std::uint64_t recording_generation{};
  std::uint64_t draw_count{};
  std::uint64_t indexed_draw_count{};
  std::uint64_t dispatch_count{};
  std::uint64_t indirect_count{};
  std::uint64_t copy_count{};
  std::uint64_t resolve_count{};
  std::uint64_t barrier_count{};
  std::uint64_t render_pass_count{};
  int eye{-1};
  std::uintptr_t pso{};
  bool cluster_light_raster{};
  std::uintptr_t root_signature{};
  std::uint64_t render_target{};
  std::uint64_t depth_target{};
  UINT render_target_count{};
  UINT viewport_x{};
  UINT viewport_y{};
  UINT viewport_width{};
  UINT viewport_height{};
  D3D12_RECT scissor{};
  D3D12_PRIMITIVE_TOPOLOGY primitive_topology{};
  D3D12_INDEX_BUFFER_VIEW index_buffer{};
  std::array<D3D12_VERTEX_BUFFER_VIEW, 8> vertex_buffers{};
  std::array<std::uint64_t, kRootSlotCount> graphics_tables{};
  std::array<std::uint64_t, kRootSlotCount> graphics_constants{};
  std::array<std::uint64_t, kRootSlotCount> graphics_cbvs{};
  std::array<std::uint64_t, kRootSlotCount> graphics_srvs{};
  std::array<std::uint64_t, kRootSlotCount> graphics_uavs{};
  ID3D12DescriptorHeap* graphics_resource_heap{};
  ID3D12DescriptorHeap* graphics_sampler_heap{};
  std::uintptr_t compute_root_signature{};
  std::array<std::uint64_t, kRootSlotCount> compute_tables{};
  std::array<std::uint64_t, kRootSlotCount> compute_constants{};
  std::array<std::uint64_t, kRootSlotCount> compute_cbvs{};
  std::array<std::uint64_t, kRootSlotCount> compute_srvs{};
  std::array<std::uint64_t, kRootSlotCount> compute_uavs{};
  std::unordered_map<PassKey, PassCounts, PassKeyHash> passes;
};

std::mutex trace_mutex;
std::unordered_map<ID3D12GraphicsCommandList*, CommandTrace> command_traces;
std::unordered_map<ID3D12GraphicsCommandList*, darktidevr::producer::BillboardResourceState>
    billboard_resource_states;
std::atomic<darktidevr::producer::BillboardDrawReadback*> billboard_readback{};
std::atomic<bool> billboard_readback_accepting{};
std::mutex billboard_readback_start_mutex;

struct ViewportRemapState {
  bool active{};
  LONG scissor_delta{};
  LONG logical_left{};
  LONG logical_right{};
};

std::mutex viewport_remap_mutex;
std::unordered_map<ID3D12GraphicsCommandList*, ViewportRemapState>
    viewport_remap_states;
struct AliasCandidate {
  std::uint64_t table{};
  bool ambiguous{};
};
std::unordered_map<std::uint64_t, AliasCandidate> frame_eye0_table4_draws;
AliasCandidate candidate_frame_eye0_table4{};
UINT candidate_frame_eye0_instance_count{};

struct RootParameterMetadata {
  UINT type{UINT_MAX};
  UINT visibility{};
  UINT shader_register{UINT_MAX};
  UINT register_space{UINT_MAX};
  std::uint64_t cbv_count{};
  std::uint64_t cbv_register_mask{};
  std::array<UINT, 64> cbv_descriptor_offsets = [] {
    std::array<UINT, 64> offsets{};
    offsets.fill(UINT_MAX);
    return offsets;
  }();
  UINT descriptor_table_span{};
  std::uint64_t srv_count{};
  std::uint64_t uav_count{};
  std::uint64_t sampler_count{};
  bool contains_cbv_b2{};
  std::uint64_t layout_hash{1469598103934665603ULL};
};

struct RootSignatureMetadata {
  UINT parameter_count{};
  UINT flags{};
  std::array<RootParameterMetadata, kRootSlotCount> parameters{};
};

std::mutex root_signature_mutex;
std::unordered_map<std::uintptr_t, RootSignatureMetadata>
    root_signature_metadata;
std::unordered_set<std::uintptr_t> logged_root_signatures;

std::mutex descriptor_mutex;
std::unordered_map<std::uintptr_t, DescriptorHeapInfo> descriptor_heaps;
std::unordered_map<std::uint64_t, DescriptorInfo> descriptor_metadata;
const auto buffer_registry = std::make_shared<darktidevr::producer::BufferRegistry>();
auto& buffer_resource_mutex = buffer_registry->mutex;
auto& buffer_resources = buffer_registry->resources;

std::unordered_set<std::uint64_t> billboard_tested_cbvs;
std::unordered_set<std::uint64_t> billboard_staging_tested_cbvs;
std::mutex billboard_cbv_log_mutex;
bool billboard_cbv_log_initialized{};
bool billboard_staging_log_initialized{};
std::atomic<std::uint64_t> billboard_cbv_log_count{};
std::atomic<std::uint64_t> billboard_staging_log_count{};
std::atomic<std::uint64_t> billboard_target_cbv_last_frame{UINT64_MAX};
std::atomic<std::uint64_t> billboard_target_cbv_log_count{};
std::atomic<std::uint64_t> billboard_target_cbv_attempt_count{};

struct PsoMetadata {
  char kind{'U'};
  std::uint64_t vertex_shader{};
  // Keep the source identity explicitly when a replacement VS is installed.
  // Pipeline-library and stream creation may expose the effective bytecode at
  // different points, and the reconstructed shader intentionally does not
  // retain the stock c_billboard symbol used by reflection.
  std::uint64_t substituted_vertex_shader{};
  std::uint64_t pixel_shader{};
  std::uint64_t compute_shader{};
  std::uint64_t cached_blob{};
  bool billboard_shader{};
  UINT billboard_register{UINT_MAX};
  UINT render_target_count{};
  DXGI_FORMAT render_target_format{DXGI_FORMAT_UNKNOWN};
  DXGI_FORMAT depth_format{DXGI_FORMAT_UNKNOWN};
  bool blend_enabled{};
  bool depth_enabled{};
  bool stencil_enabled{};
  bool alpha_to_coverage{};
  D3D12_RENDER_TARGET_BLEND_DESC ui_blend{};
  ComPtr<ID3D12PipelineState> ui_alpha_pipeline;
  std::size_t ui_blend_stream_offset{SIZE_MAX};
  std::size_t ui_cached_stream_offset{SIZE_MAX};
};
bool world_ui_capture_requested();

constexpr std::uint64_t kBillboardTargetVertexShader =
    0x42e436fb1ef1b392ULL;
constexpr std::uint64_t kBillboardPerObjectByteSize = 24ULL * 16ULL;

void preserve_billboard_substitution(PsoMetadata& metadata,
                                     std::uint64_t original_vertex_shader,
                                     bool substituted) {
  if (!substituted || original_vertex_shader == 0) {
    return;
  }
  metadata.substituted_vertex_shader = original_vertex_shader;
  metadata.billboard_shader = true;
  if (metadata.billboard_register == UINT_MAX) {
    metadata.billboard_register = 2;
  }
}

bool is_stock_menu_shader_pair(const PsoMetadata& metadata) {
  return std::any_of(kStockMenuShaderPairs.begin(),
                     kStockMenuShaderPairs.end(), [&](const auto& pair) {
                       return metadata.vertex_shader == pair.vertex_shader &&
                              metadata.pixel_shader == pair.pixel_shader;
                     });
}

std::mutex pso_mutex;
std::unordered_map<std::uintptr_t, PsoMetadata> pso_metadata;
std::mutex command_signature_mutex;
std::unordered_map<std::uintptr_t, bool> command_signature_draws;
// PSO metadata can be revisited by pipeline-library/cache paths after creation.
// Keep successful target substitutions on the COM object itself so
// a later descriptive metadata refresh cannot erase the fact that this PSO is
// executing the reconstructed target shader.

std::unordered_set<std::uintptr_t> logged_billboard_bound_psos;

struct PendingCapture {
  ComPtr<ID3D12CommandAllocator> allocator;
  ComPtr<ID3D12GraphicsCommandList> commands;
  std::uint64_t fence_value{};
  std::shared_ptr<darktidevr::producer::DesktopMirrorBlit> mirror_blit;
};

std::deque<PendingCapture> pending_captures;
std::deque<PendingCapture> available_captures;
std::deque<PendingCapture> menu_pending_captures;
std::deque<PendingCapture> menu_available_captures;
std::deque<PendingCapture> desktop_mirror_pending;
std::deque<PendingCapture> desktop_mirror_available;
PendingCapture staged_eye0_capture;
bool staged_eye0_capture_valid{};
bool staged_pair_dropped{};

std::mutex boundary_capture_mutex;
struct ArmedEyeCapture {
  int eye{};
  std::uint64_t pose_sequence{};
  float vertical_fov_radians{};
  float aspect_ratio{};
};
std::deque<ArmedEyeCapture> armed_eye_captures;
std::unordered_set<ID3D12Resource*> swapchain_back_buffers;
std::unordered_map<ID3D12Resource*, D3D12_RESOURCE_STATES>
    swapchain_back_buffer_states;
std::unordered_map<ID3D12GraphicsCommandList*, ComPtr<ID3D12Resource>>
    present_transition_resources;
std::unordered_map<ID3D12GraphicsCommandList*, ComPtr<ID3D12Resource>>
    camera_output_resources;
std::unordered_map<ID3D12GraphicsCommandList*, D3D12_RESOURCE_STATES>
    camera_output_source_states;
std::unordered_map<ID3D12GraphicsCommandList*, std::uint64_t>
    command_recording_generations;
std::unordered_map<ID3D12GraphicsCommandList*, ComPtr<ID3D12Resource>>
    menu_output_resources;
std::unordered_map<ID3D12GraphicsCommandList*, D3D12_RESOURCE_STATES>
    menu_output_source_states;
std::unordered_set<ID3D12Resource*> known_camera_output_resources;
std::array<ID3D12Resource*, 2> named_camera_output_resources{};
bool named_camera_outputs_ready{};
// Lock-free hint for OMSetRenderTargets. Once both explicit eye finals are
// learned, production capture no longer needs to resolve every ordinary RTV
// binding merely to discover an implicit swapchain promotion.
std::atomic<bool> named_camera_outputs_ready_hint{};
bool camera_output_realign_pending{};
// Diagnostic selector for completed 1920x2160 RGBA8 outputs seen on a command
// list. -1 preserves the production behavior (the last completed candidate).
std::atomic<int> camera_output_candidate_index{-1};
struct CameraOutputCandidate {
  ComPtr<ID3D12Resource> resource;
  std::uint64_t transition_ordinal{};
  std::string marker;
};
std::unordered_map<ID3D12GraphicsCommandList*,
                   std::vector<CameraOutputCandidate>>
    camera_output_candidates;
std::unordered_map<ID3D12GraphicsCommandList*, std::uint64_t>
    command_transition_ordinals;
std::unordered_map<ID3D12GraphicsCommandList*, std::vector<std::string>>
    command_marker_stacks;
std::uint64_t camera_output_width{};
UINT camera_output_height{};
DXGI_FORMAT camera_output_format{DXGI_FORMAT_UNKNOWN};
std::atomic<UINT> camera_input_width{1920};
std::atomic<UINT> camera_input_height{2160};
std::atomic<bool> swapchain_render_extent_enabled{};
// Engine-facing extent stays per-eye; only DXGI allocation uses packed width.
std::atomic<UINT> swapchain_present_width{1920};
std::atomic<UINT> swapchain_render_width{1920};
std::atomic<UINT> swapchain_render_height{2160};
std::atomic<bool> swapchain_resize_nudge_pending{};
std::atomic<bool> swapchain_client_extent_locked{};
std::atomic<bool> virtual_client_extent_enabled{};
std::atomic<bool> virtual_size_message_enabled{};
std::atomic<HWND> game_output_window{};
std::mutex virtual_window_proc_mutex;
HWND virtual_window_proc_window{};
WNDPROC original_game_window_proc{};
std::atomic<int> swapchain_resize_nudge_phase{};
RECT swapchain_resize_nudge_original_window{};

bool camera_capture_extent_matches(std::uint64_t width, UINT height) noexcept {
  const auto input_width = camera_input_width.load(std::memory_order_relaxed);
  const auto input_height = camera_input_height.load(std::memory_order_relaxed);
  return (width == input_width && height == input_height) ||
         (width == camera_output_width && height == camera_output_height);
}

std::atomic<UINT> mirror_client_width{};
std::atomic<UINT> mirror_client_height{};
std::atomic<std::uint64_t> boundary_arm_count{};
std::atomic<std::uint64_t> boundary_transition_count{};
std::array<std::atomic<std::uint64_t>, 2> boundary_eye_capture_counts{};
std::array<std::atomic<std::uint64_t>, 2> boundary_eye_pose_sequences{};
std::atomic<std::uint64_t> boundary_published_pair_pose{};
std::atomic<std::uint64_t> boundary_tag_reset_count{};
std::atomic<std::uint64_t> boundary_staged_eye0_pose_sequence{};
std::atomic<float> boundary_staged_eye0_vertical_fov{};
std::atomic<float> boundary_staged_eye0_aspect_ratio{};
std::atomic<float> render_vertical_fov_radians{};
std::atomic<float> render_aspect_ratio{};

darktidevr::core::SharedHeadPoseReader& shared_head_pose_reader() {
  static darktidevr::core::SharedHeadPoseReader reader;
  return reader;
}

HANDLE shared_projection_active_event() {
  auto event = projection_active_event.load(std::memory_order_acquire);
  if (event) {
    return event;
  }
  const auto created = CreateEventW(
      nullptr, TRUE, FALSE, darktidevr::core::shared_object_name(
          L"Local\\DarktideVR-projection-active-v1").c_str());
  if (!created) {
    return nullptr;
  }
  // A bridge can keep the named event object alive across a producer restart.
  // Start each new producer generation in the fail-closed flat state instead
  // of inheriting the previous process's last signalled value.
  if (!ResetEvent(created)) {
    CloseHandle(created);
    return nullptr;
  }
  HANDLE expected{};
  if (!projection_active_event.compare_exchange_strong(
          expected, created, std::memory_order_release,
          std::memory_order_acquire)) {
    CloseHandle(created);
    return expected;
  }
  return created;
}
darktidevr::core::SharedControllerStateReader& shared_controller_state_reader() {
  static darktidevr::core::SharedControllerStateReader reader;
  return reader;
}

darktidevr::core::SharedMenuPointerStateReader&
shared_menu_pointer_state_reader() {
  static darktidevr::core::SharedMenuPointerStateReader reader;
  return reader;
}
darktidevr::core::GameplayInputMapper& gameplay_input_mapper() {
  static darktidevr::core::GameplayInputMapper mapper;
  return mapper;
}
std::atomic<int> boundary_last_capture_result{};

constexpr std::size_t kGpuProfileSlotCount = 512;
constexpr UINT kGpuProfileBaseQueryCount = 3;
constexpr UINT kGpuPassTraceBatchCapacity = 64;
constexpr UINT kGpuProfileQueriesPerSlot =
    kGpuProfileBaseQueryCount + kGpuPassTraceBatchCapacity * 2U;
struct GpuPassTraceList {
  std::uintptr_t commands{};
  std::uint64_t generation{};
  std::uint64_t draws{};
  std::uint64_t indexed_draws{};
  std::uint64_t dispatches{};
  std::uint64_t indirects{};
  std::uint64_t copies{};
  std::uint64_t resolves{};
  std::uint64_t barriers{};
  std::uint64_t passes{};
};
struct GpuPassTraceBatch {
  UINT list_offset{};
  UINT list_count{};
  bool terminal{};
  int terminal_eye{-1};
};
struct GpuPassTraceMarker {
  ComPtr<ID3D12CommandAllocator> allocator;
  ComPtr<ID3D12GraphicsCommandList> commands;
};
struct GpuProfileSample {
  int eye{-1};
  UINT slot{};
  std::uint64_t fence_value{};
  bool internal_target_seen{};
  bool stage_boundary_recorded{};
  bool pass_trace_enabled{};
  int pass_trace_phase{};
  std::uint64_t pass_trace_frame{};
  UINT pass_trace_batch_count{};
  std::array<GpuPassTraceBatch, kGpuPassTraceBatchCapacity>
      pass_trace_batches{};
  std::vector<GpuPassTraceList> pass_trace_lists;
  std::vector<GpuPassTraceMarker> pass_trace_markers;
  ComPtr<ID3D12CommandAllocator> start_allocator;
  ComPtr<ID3D12GraphicsCommandList> start_commands;
  ComPtr<ID3D12CommandAllocator> end_allocator;
  ComPtr<ID3D12GraphicsCommandList> end_commands;
};

std::mutex gpu_profile_mutex;
ComPtr<ID3D12QueryHeap> gpu_profile_query_heap;
ComPtr<ID3D12Resource> gpu_profile_readback;
ComPtr<ID3D12Fence> gpu_profile_fence;
std::uint64_t* gpu_profile_ticks{};
std::uint64_t gpu_profile_frequency{};
std::uint64_t gpu_profile_next_fence{};
UINT gpu_profile_next_slot{};
std::array<std::uint64_t, kGpuProfileSlotCount> gpu_profile_slot_fences{};
std::array<std::optional<GpuProfileSample>, 2> gpu_profile_active;
std::deque<GpuProfileSample> gpu_profile_pending;
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_sample_counts{};
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_total_ticks{};
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_max_ticks{};
std::array<std::vector<std::uint64_t>, 2> gpu_profile_duration_ticks{};
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_stage_sample_counts{};
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_world_total_ticks{};
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_world_max_ticks{};
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_output_total_ticks{};
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_output_max_ticks{};
std::array<std::atomic<bool>, 2> gpu_profile_pass_trace_claimed{};
std::atomic<bool> gpu_profile_enabled{};
// Per-draw/root/PSO/descriptor hooks are useful for bounded renderer
// investigations but impose thousands of detours per stereo pair. Production
// capture needs only resource-boundary, queue, swapchain and reset hooks. The
// mode must be selected before dtvr_install() because MinHook cannot safely add
// this interdependent hook set after renderer threads are live.
std::atomic<bool> kInstallDiagnosticRenderHooks{};
std::atomic<bool> vertex_shader_dump_requested{};
// Unlike the retired per-draw constant-buffer experiments, shader replacement
// only needs the three PSO construction hooks. Keep it independently
// selectable so production XR does not pay for the diagnostic draw hooks.
std::atomic<bool> billboard_shader_substitution_requested{};
std::atomic<bool> billboard_pixel_shader_probe_requested{};
std::atomic<std::uint64_t> billboard_pixel_shader_probe_attempt_count{};
std::atomic<std::uint64_t> billboard_pixel_shader_probe_validation_reject_count{};
std::atomic<std::uint64_t> billboard_pixel_shader_probe_applied_count{};
std::atomic<std::uint64_t> billboard_pixel_shader_probe_creation_reject_count{};
std::atomic<std::uint64_t> billboard_shader_substitution_count{};
std::atomic<std::uint64_t> billboard_shader_substitution_reject_count{};
constexpr std::array<std::uint64_t, 14> kBillboardVertexShaderHashes{
    0x6e5fa4d1f1e2cd16ULL, 0x25920ba45ba58e76ULL,
    0xaf848a96a230342aULL, 0x903cb53d8ac05f28ULL,
    0x13e04962148fc216ULL, 0x42f73c7d12e99db7ULL,
    0xc403cfbf17d9fc49ULL, 0x30408e39c8028272ULL,
    0xe18a274cd89282e8ULL, 0xf0c85040e349f799ULL,
    0xfe64037664924d52ULL, 0x9edf5361a4db2da1ULL,
    0x6a0153ef1f6c56fdULL, 0x42e436fb1ef1b392ULL};
constexpr std::array<std::uint64_t, 9> kBillboardPixelShaderHashes{
    0x40063d327b1294edULL, 0xcb7e4e5d3e01d5bdULL,
    0x2b7d8f695f0d55beULL, 0x0e35f00186a2af32ULL,
    0x4277b248ec882f15ULL, 0x7c035f0ca3365a04ULL,
    0xc89d9f1dae60baf9ULL, 0xe977841939553e76ULL,
    0x0bf86872f2c6ca5dULL};
std::array<std::atomic<std::uint64_t>, kBillboardVertexShaderHashes.size()>
    billboard_shader_substitution_attempt_counts{};
std::array<std::atomic<std::uint64_t>, kBillboardVertexShaderHashes.size()>
    billboard_shader_substitution_applied_counts{};
std::array<std::atomic<std::uint64_t>, kBillboardVertexShaderHashes.size()>
    billboard_shader_substitution_validation_reject_counts{};
std::array<std::atomic<std::uint64_t>, kBillboardVertexShaderHashes.size()>
    billboard_shader_substitution_creation_reject_counts{};
std::mutex billboard_shader_replacement_mutex;
std::unordered_map<std::uint64_t, std::vector<std::uint8_t>>
    billboard_shader_replacements;
std::atomic<std::uint64_t> billboard_target_replacement_hash{};

void write_billboard_pso_identity(const char* event, std::uintptr_t key,
                                  const PsoMetadata& metadata) {
  if (!billboard_shader_substitution_requested.load(
          std::memory_order_relaxed)) {
    return;
  }
  std::array<wchar_t, MAX_PATH> temporary_path{};
  if (GetTempPathW(static_cast<DWORD>(temporary_path.size()),
                   temporary_path.data()) == 0) {
    return;
  }
  const auto path = std::wstring(temporary_path.data()) +
                    L"darktidevr-billboard-pso-identity.tsv";
  char line[512]{};
  const auto length = std::snprintf(
      line, sizeof(line),
      "event=%s\tpso=%p\tvs=%016llx\tsub_vs=%016llx\tps=%016llx"
      "\tbillboard=%u\tb=%u\r\n",
      event, reinterpret_cast<void*>(key),
      static_cast<unsigned long long>(metadata.vertex_shader),
      static_cast<unsigned long long>(metadata.substituted_vertex_shader),
      static_cast<unsigned long long>(metadata.pixel_shader),
      metadata.billboard_shader ? 1U : 0U, metadata.billboard_register);
  if (length > 0 && static_cast<std::size_t>(length) < sizeof(line) &&
      !darktidevr::producer::append_diagnostic_record(
          path.c_str(), {line, static_cast<std::size_t>(length)})) {
    // A disk/access failure is different from a capture containing no match.
    // Report it once without flooding the renderer's debug stream.
    static std::atomic_flag reported = ATOMIC_FLAG_INIT;
    if (!reported.test_and_set(std::memory_order_relaxed)) {
      OutputDebugStringA("DARKTIDEVR billboard identity log write failed\n");
    }
  }
}
std::array<std::atomic<float>, 6> billboard_view_basis{};
std::atomic<bool> billboard_horizon_lock_enabled{};
std::atomic<bool> billboard_staging_write_enabled{};
std::atomic<bool> billboard_direct_write_enabled{};
// The shadow-heap/descriptor-table rewrite was useful to prove the reflected
// c_billboard binding, but mutating a draw's live descriptor topology is not a
// production-safe write path. Keep its bounded observation counters available
// while making the write mode impossible to arm. The replacement path writes
// only the proven persistent Stingray CPU staging allocation, behind a separate
// fingerprinted API and exact reflected billboard draw identity.
constexpr bool kAllowRetiredBillboardDescriptorWrites = false;
std::atomic<bool> billboard_basis_write_enabled{};
std::atomic<std::uint64_t> billboard_exact_shader_draw_count{};
std::atomic<std::uint64_t> billboard_exact_pso_draw_count{};
std::array<std::atomic<std::uint64_t>, kRootSlotCount>
    billboard_exact_pso_cbv_slot_counts{};
std::array<std::atomic<std::uint64_t>, kRootSlotCount>
    billboard_exact_pso_table_slot_counts{};
std::array<std::atomic<std::uint64_t>, 64>
    billboard_exact_register_counts{};
std::array<std::atomic<std::uint64_t>, kRootSlotCount>
    billboard_exact_vertex_table_slot_counts{};
std::array<std::atomic<std::uint64_t>, 64>
    billboard_exact_descriptor_offset_counts{};
std::array<std::atomic<std::uint64_t>, 64>
    billboard_exact_table_span_counts{};
std::atomic<std::uint64_t> billboard_exact_cbv_descriptor_count{};
std::atomic<std::uint64_t> billboard_exact_buffer_resource_count{};
std::array<std::atomic<std::uint64_t>, 5> billboard_exact_heap_type_counts{};
std::atomic<std::uint64_t> billboard_exact_map_success_count{};
std::atomic<std::uint64_t> billboard_exact_map_failure_count{};
std::atomic<std::uint64_t> billboard_resource_map_count{};
std::atomic<std::uint64_t> billboard_resource_map_match_count{};
std::atomic<std::uint64_t> billboard_resource_unmap_count{};
std::atomic<std::uint64_t> billboard_selected_map_stack_count{};
std::atomic<std::uint64_t> billboard_upload_flush_count{};
std::atomic<std::uint64_t> billboard_direct_patch_count{};
std::atomic<int> billboard_upload_flush_hook_state{};
std::atomic<std::uintptr_t> billboard_selected_cpu_address{};
std::atomic<std::uint64_t> billboard_selected_gpu_address{};
std::atomic<std::uint64_t> billboard_selected_size{};

constexpr UINT kBillboardShadowConstantCapacity = 131072;
constexpr UINT kBillboardShadowDescriptorCapacity = 524288;
std::mutex billboard_shadow_mutex;
ComPtr<ID3D12Device> billboard_shadow_device;
ComPtr<ID3D12DescriptorHeap> billboard_shadow_heap;
ComPtr<ID3D12Resource> billboard_shadow_constants;
std::byte* billboard_shadow_mapped{};
UINT billboard_shadow_descriptor_increment{};
std::atomic<UINT> billboard_shadow_constant_cursor{};
std::atomic<UINT> billboard_shadow_descriptor_cursor{};
std::array<std::atomic<std::uint64_t>, 16>
    billboard_shadow_stage_counts{};
std::array<std::atomic<std::uint64_t>, 8>
    billboard_exact_command_list_type_counts{};
std::atomic<std::uint64_t> billboard_exact_root_mapping_count{};
std::atomic<std::uint64_t> billboard_root_metadata_draw_count{};
std::atomic<std::uint64_t> billboard_table_b2_draw_count{};
std::atomic<std::uint64_t> billboard_bound_table_b2_draw_count{};
std::atomic<std::uint64_t> billboard_observed_draw_count{};
std::atomic<std::uint64_t> billboard_direct_draw_hook_count{};
std::atomic<std::uint64_t> diagnostic_root_signature_create_count{};
std::atomic<std::uint64_t> diagnostic_graphics_pso_create_count{};
std::atomic<std::uint64_t> diagnostic_compute_pso_create_count{};
std::atomic<std::uint64_t> diagnostic_stream_pso_create_count{};
std::atomic<std::uint64_t> diagnostic_graphics_pipeline_load_count{};
std::atomic<std::uint64_t> diagnostic_compute_pipeline_load_count{};
std::atomic<std::uint64_t> diagnostic_stream_pipeline_load_count{};
std::atomic<std::uint64_t> billboard_root_b2_candidate_draw_count{};
std::mutex billboard_candidate_shader_mutex;
std::unordered_map<std::uint64_t, std::uint64_t>
    billboard_candidate_shader_counts;
std::map<std::pair<std::uint64_t, std::uint64_t>, std::uint64_t>
    billboard_candidate_shader_pair_counts;
constexpr std::size_t kBillboardObservedStrideCount = 257;
std::array<std::array<std::atomic<std::uint64_t>,
                      kBillboardObservedStrideCount>,
           2>
    billboard_observed_stride_counts{};
std::atomic<std::uint64_t> billboard_stride_candidate_count{};
std::atomic<std::uint64_t> billboard_b1_bound_count{};
std::atomic<std::uint64_t> billboard_b2_bound_count{};
std::atomic<std::uint64_t> billboard_basis_patch_count{};
std::mutex vertex_shader_dump_mutex;
std::unordered_set<std::uint64_t> dumped_vertex_shaders;
std::unordered_set<std::uint64_t> dumped_cluster_compute_shaders;
std::unordered_set<std::uint64_t> dumped_cluster_graphics_shader_pairs;
std::unordered_set<std::uint64_t> dumped_billboard_pixel_shaders;
std::unordered_set<std::uint64_t> dumped_blended_pixel_shaders;
std::unordered_set<std::uint64_t> dumped_blended_pso_pairs;
std::unordered_set<std::uint64_t> dumped_pipeline_blobs;
std::unordered_set<std::uint64_t> dumped_pso_shader_mappings;

int capture_present_halves(IDXGISwapChain3* swapchain,
                           ID3D12CommandQueue* queue);
int capture_eye_from_resource(int eye, ID3D12CommandQueue* queue,
                              ID3D12Resource* back_buffer,
                              bool bypass_execute_hook,
                              D3D12_RESOURCE_STATES source_state);
void write_focused_log(const char* format, ...);

void write_cluster_trace_log(const char* format, ...) {
  if (cluster_trace_log == INVALID_HANDLE_VALUE ||
      cluster_trace_count.fetch_add(1, std::memory_order_relaxed) >= 20000) {
    return;
  }
  std::array<char, 4096> line{};
  va_list arguments;
  va_start(arguments, format);
  const auto length = vsnprintf_s(line.data(), line.size(), _TRUNCATE, format,
                                  arguments);
  va_end(arguments);
  if (length <= 0) {
    return;
  }
  std::scoped_lock lock(cluster_trace_mutex);
  if (cluster_trace_log != INVALID_HANDLE_VALUE) {
    DWORD written{};
    WriteFile(cluster_trace_log, line.data(), static_cast<DWORD>(length),
              &written, nullptr);
  }
}

void update_atomic_max(std::atomic<std::uint64_t>& destination,
                       std::uint64_t value) {
  auto current = destination.load(std::memory_order_relaxed);
  while (current < value &&
         !destination.compare_exchange_weak(current, value,
                                            std::memory_order_relaxed)) {
  }
}

void reset_gpu_profiler_resources() {
  gpu_profile_active = {};
  gpu_profile_pending.clear();
  if (gpu_profile_readback && gpu_profile_ticks) {
    gpu_profile_readback->Unmap(0, nullptr);
  }
  gpu_profile_ticks = nullptr;
  gpu_profile_query_heap.Reset();
  gpu_profile_readback.Reset();
  gpu_profile_fence.Reset();
  gpu_profile_frequency = 0;
  gpu_profile_next_fence = 0;
  gpu_profile_next_slot = 0;
  gpu_profile_slot_fences.fill(0);
  for (auto& claimed : gpu_profile_pass_trace_claimed) {
    claimed.store(false, std::memory_order_relaxed);
  }
}

bool ensure_gpu_profiler(ID3D12CommandQueue* queue) {
  if (gpu_profile_query_heap && gpu_profile_readback && gpu_profile_fence &&
      gpu_profile_ticks && gpu_profile_frequency != 0) {
    return true;
  }
  if (!queue || !original_execute_command_lists) {
    return false;
  }
  ComPtr<ID3D12Device> device;
  if (FAILED(queue->GetDevice(IID_PPV_ARGS(&device))) ||
      FAILED(queue->GetTimestampFrequency(&gpu_profile_frequency)) ||
      gpu_profile_frequency == 0) {
    return false;
  }
  D3D12_QUERY_HEAP_DESC query_description{};
  query_description.Type = D3D12_QUERY_HEAP_TYPE_TIMESTAMP;
  query_description.Count =
      static_cast<UINT>(kGpuProfileSlotCount * kGpuProfileQueriesPerSlot);
  if (FAILED(device->CreateQueryHeap(&query_description,
                                     IID_PPV_ARGS(&gpu_profile_query_heap)))) {
    return false;
  }
  D3D12_HEAP_PROPERTIES heap_properties{};
  heap_properties.Type = D3D12_HEAP_TYPE_READBACK;
  heap_properties.CreationNodeMask = 1;
  heap_properties.VisibleNodeMask = 1;
  D3D12_RESOURCE_DESC resource_description{};
  resource_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
  resource_description.Width =
      kGpuProfileSlotCount * kGpuProfileQueriesPerSlot *
      sizeof(std::uint64_t);
  resource_description.Height = 1;
  resource_description.DepthOrArraySize = 1;
  resource_description.MipLevels = 1;
  resource_description.SampleDesc.Count = 1;
  resource_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  if (FAILED(device->CreateCommittedResource(
          &heap_properties, D3D12_HEAP_FLAG_NONE, &resource_description,
          D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
          IID_PPV_ARGS(&gpu_profile_readback))) ||
      FAILED(gpu_profile_readback->Map(
          0, nullptr, reinterpret_cast<void**>(&gpu_profile_ticks))) ||
      FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                 IID_PPV_ARGS(&gpu_profile_fence)))) {
    reset_gpu_profiler_resources();
    return false;
  }
  return true;
}

bool harvest_gpu_profile_samples() {
  if (!gpu_profile_fence || !gpu_profile_ticks) {
    return false;
  }
  const auto completed = gpu_profile_fence->GetCompletedValue();
  if (completed == UINT64_MAX) {
    reset_gpu_profiler_resources();
    return false;
  }
  while (!gpu_profile_pending.empty() &&
         gpu_profile_pending.front().fence_value <= completed) {
    const auto& sample = gpu_profile_pending.front();
    const auto query_start = sample.slot * kGpuProfileQueriesPerSlot;
    const auto start = gpu_profile_ticks[query_start];
    const auto boundary = gpu_profile_ticks[query_start + 1U];
    const auto end = gpu_profile_ticks[query_start + 2U];
    if (sample.eye >= 0 && sample.eye <= 1 && end >= start) {
      const auto duration = end - start;
      const auto index = static_cast<std::size_t>(sample.eye);
      gpu_profile_sample_counts[index].fetch_add(1,
                                                  std::memory_order_relaxed);
      gpu_profile_total_ticks[index].fetch_add(duration,
                                                std::memory_order_relaxed);
      update_atomic_max(gpu_profile_max_ticks[index], duration);
      gpu_profile_duration_ticks[index].push_back(duration);
      if (sample.stage_boundary_recorded && boundary >= start &&
          end >= boundary) {
        const auto world_duration = boundary - start;
        const auto output_duration = end - boundary;
        gpu_profile_stage_sample_counts[index].fetch_add(
            1, std::memory_order_relaxed);
        gpu_profile_world_total_ticks[index].fetch_add(
            world_duration, std::memory_order_relaxed);
        gpu_profile_output_total_ticks[index].fetch_add(
            output_duration, std::memory_order_relaxed);
        update_atomic_max(gpu_profile_world_max_ticks[index], world_duration);
        update_atomic_max(gpu_profile_output_max_ticks[index], output_duration);
      }
      if (sample.pass_trace_enabled && sample.pass_trace_batch_count > 0 &&
          gpu_profile_frequency != 0) {
        for (UINT batch_index = 0;
             batch_index < sample.pass_trace_batch_count; ++batch_index) {
          const auto batch_start =
              gpu_profile_ticks[query_start + kGpuProfileBaseQueryCount +
                                batch_index * 2U];
          const auto batch_end =
              gpu_profile_ticks[query_start + kGpuProfileBaseQueryCount +
                                batch_index * 2U + 1U];
          if (batch_end < batch_start) {
            continue;
          }
          const auto& batch = sample.pass_trace_batches[batch_index];
          write_focused_log(
              "phase=%d\tframe=%llu\tGPU_BATCH\teye=%d\tordinal=%u"
              "\tduration_ms=%.6f\tlists=%u\tterminal=%u"
              "\tterminal_eye=%d\r\n",
              sample.pass_trace_phase,
              static_cast<unsigned long long>(sample.pass_trace_frame),
              sample.eye, batch_index,
              static_cast<double>(batch_end - batch_start) * 1000.0 /
                  static_cast<double>(gpu_profile_frequency),
              batch.list_count, batch.terminal ? 1U : 0U,
              batch.terminal_eye);
          for (UINT list_index = 0; list_index < batch.list_count;
               ++list_index) {
            const auto& list = sample.pass_trace_lists[
                batch.list_offset + list_index];
            write_focused_log(
                "phase=%d\tframe=%llu\tGPU_BATCH_LIST\teye=%d"
                "\tbatch=%u\tlist_index=%u\tCL=%p\tgen=%llu"
                "\tdraws=%llu\tindexed=%llu\tdispatches=%llu"
                "\tindirects=%llu\tcopies=%llu\tresolves=%llu"
                "\tbarriers=%llu\tpasses=%llu\r\n",
                sample.pass_trace_phase,
                static_cast<unsigned long long>(sample.pass_trace_frame),
                sample.eye, batch_index, list_index,
                reinterpret_cast<void*>(list.commands),
                static_cast<unsigned long long>(list.generation),
                static_cast<unsigned long long>(list.draws),
                static_cast<unsigned long long>(list.indexed_draws),
                static_cast<unsigned long long>(list.dispatches),
                static_cast<unsigned long long>(list.indirects),
                static_cast<unsigned long long>(list.copies),
                static_cast<unsigned long long>(list.resolves),
                static_cast<unsigned long long>(list.barriers),
                static_cast<unsigned long long>(list.passes));
          }
        }
        write_focused_log(
            "phase=%d\tframe=%llu\tGPU_BATCH_COMPLETE\teye=%d"
            "\tbatches=%u\ttruncated=%u\r\n",
            sample.pass_trace_phase,
            static_cast<unsigned long long>(sample.pass_trace_frame),
            sample.eye, sample.pass_trace_batch_count,
            sample.pass_trace_batch_count == kGpuPassTraceBatchCapacity
                ? 1U
                : 0U);
      }
    }
    gpu_profile_pending.pop_front();
  }
  return true;
}

void begin_gpu_eye_profile(int eye) {
  if (!gpu_profile_enabled.load(std::memory_order_relaxed) || eye < 0 ||
      eye > 1) {
    return;
  }
  ComPtr<ID3D12CommandQueue> queue;
  {
    std::scoped_lock state_lock(state_mutex);
    queue = game_queue;
  }
  std::scoped_lock lock(gpu_profile_mutex);
  const auto eye_index = static_cast<std::size_t>(eye);
  if (!ensure_gpu_profiler(queue.Get()) || gpu_profile_active[eye_index]) {
    return;
  }
  if (!harvest_gpu_profile_samples()) {
    return;
  }
  const auto completed = gpu_profile_fence->GetCompletedValue();
  const auto slot = gpu_profile_next_slot;
  if (gpu_profile_slot_fences[slot] > completed) {
    return;
  }
  GpuProfileSample sample{};
  sample.eye = eye;
  sample.slot = slot;
  const auto focused_phase =
      focused_trace_phase.load(std::memory_order_relaxed);
  if (focused_phase != 0 &&
      !gpu_profile_pass_trace_claimed[eye_index].exchange(
          true, std::memory_order_relaxed)) {
    sample.pass_trace_enabled = true;
    sample.pass_trace_phase = focused_phase;
    sample.pass_trace_frame =
        present_count.load(std::memory_order_relaxed);
  }
  ComPtr<ID3D12Device> device;
  if (FAILED(queue->GetDevice(IID_PPV_ARGS(&device))) ||
      FAILED(device->CreateCommandAllocator(
          D3D12_COMMAND_LIST_TYPE_DIRECT,
          IID_PPV_ARGS(&sample.start_allocator))) ||
      FAILED(device->CreateCommandList(
          0, D3D12_COMMAND_LIST_TYPE_DIRECT, sample.start_allocator.Get(),
          nullptr, IID_PPV_ARGS(&sample.start_commands)))) {
    return;
  }
  sample.start_commands->EndQuery(gpu_profile_query_heap.Get(),
                                  D3D12_QUERY_TYPE_TIMESTAMP,
                                  slot * kGpuProfileQueriesPerSlot);
  if (FAILED(sample.start_commands->Close())) {
    return;
  }
  ID3D12CommandList* lists[]{sample.start_commands.Get()};
  original_execute_command_lists(queue.Get(), 1, lists);
  gpu_profile_next_slot =
      static_cast<UINT>((slot + 1U) % kGpuProfileSlotCount);
  gpu_profile_active[eye_index] = std::move(sample);
}

void end_gpu_eye_profile(int eye, ID3D12CommandQueue* queue) {
  std::scoped_lock lock(gpu_profile_mutex);
  if (eye < 0 || eye > 1) {
    return;
  }
  const auto eye_index = static_cast<std::size_t>(eye);
  auto& active = gpu_profile_active[eye_index];
  if (!active || active->eye != eye || !queue ||
      !gpu_profile_query_heap || !gpu_profile_readback || !gpu_profile_fence) {
    return;
  }
  auto sample = std::move(*active);
  active.reset();
  ComPtr<ID3D12Device> device;
  if (FAILED(queue->GetDevice(IID_PPV_ARGS(&device))) ||
      FAILED(device->CreateCommandAllocator(
          D3D12_COMMAND_LIST_TYPE_DIRECT,
          IID_PPV_ARGS(&sample.end_allocator))) ||
      FAILED(device->CreateCommandList(
          0, D3D12_COMMAND_LIST_TYPE_DIRECT, sample.end_allocator.Get(),
          nullptr, IID_PPV_ARGS(&sample.end_commands)))) {
    return;
  }
  const auto query_start = sample.slot * kGpuProfileQueriesPerSlot;
  sample.end_commands->EndQuery(gpu_profile_query_heap.Get(),
                                D3D12_QUERY_TYPE_TIMESTAMP,
                                query_start + 2U);
  sample.end_commands->ResolveQueryData(
      gpu_profile_query_heap.Get(), D3D12_QUERY_TYPE_TIMESTAMP, query_start,
      kGpuProfileBaseQueryCount + sample.pass_trace_batch_count * 2U,
      gpu_profile_readback.Get(),
      static_cast<UINT64>(query_start) * sizeof(std::uint64_t));
  if (FAILED(sample.end_commands->Close())) {
    return;
  }
  ID3D12CommandList* lists[]{sample.end_commands.Get()};
  original_execute_command_lists(queue, 1, lists);
  sample.fence_value = ++gpu_profile_next_fence;
  if (FAILED(queue->Signal(gpu_profile_fence.Get(), sample.fence_value))) {
    reset_gpu_profiler_resources();
    return;
  }
  gpu_profile_slot_fences[sample.slot] = sample.fence_value;
  gpu_profile_pending.push_back(std::move(sample));
}

struct GpuPassTraceToken {
  int eye{-1};
  UINT batch{};
};

bool submit_gpu_pass_trace_marker_locked(GpuProfileSample& sample,
                                         ID3D12CommandQueue* queue,
                                         UINT query_index) {
  ComPtr<ID3D12Device> device;
  GpuPassTraceMarker marker{};
  if (!queue || !original_execute_command_lists ||
      FAILED(queue->GetDevice(IID_PPV_ARGS(&device))) ||
      FAILED(device->CreateCommandAllocator(
          D3D12_COMMAND_LIST_TYPE_DIRECT,
          IID_PPV_ARGS(&marker.allocator))) ||
      FAILED(device->CreateCommandList(
          0, D3D12_COMMAND_LIST_TYPE_DIRECT, marker.allocator.Get(), nullptr,
          IID_PPV_ARGS(&marker.commands)))) {
    return false;
  }
  marker.commands->EndQuery(gpu_profile_query_heap.Get(),
                            D3D12_QUERY_TYPE_TIMESTAMP, query_index);
  if (FAILED(marker.commands->Close())) {
    return false;
  }
  ID3D12CommandList* marker_lists[]{marker.commands.Get()};
  original_execute_command_lists(queue, 1, marker_lists);
  sample.pass_trace_markers.push_back(std::move(marker));
  return true;
}

GpuPassTraceToken begin_gpu_pass_trace_batch_locked(
    ID3D12CommandQueue* queue, UINT count, ID3D12CommandList* const* lists,
    int terminal_eye) {
  for (std::size_t eye_index = 0; eye_index < gpu_profile_active.size();
       ++eye_index) {
    auto& active = gpu_profile_active[eye_index];
    if (!active || !active->pass_trace_enabled ||
        active->pass_trace_batch_count >= kGpuPassTraceBatchCapacity) {
      continue;
    }
    const auto batch_index = active->pass_trace_batch_count;
    const auto query_start = active->slot * kGpuProfileQueriesPerSlot;
    if (!submit_gpu_pass_trace_marker_locked(
            *active, queue,
            query_start + kGpuProfileBaseQueryCount + batch_index * 2U)) {
      return {};
    }
    auto& batch = active->pass_trace_batches[batch_index];
    batch.list_offset =
        static_cast<UINT>(active->pass_trace_lists.size());
    batch.list_count = count;
    batch.terminal = terminal_eye >= 0;
    batch.terminal_eye = terminal_eye;
    {
      std::scoped_lock trace_lock(trace_mutex);
      for (UINT list_index = 0; list_index < count; ++list_index) {
        auto* commands = static_cast<ID3D12GraphicsCommandList*>(
            lists[list_index]);
        GpuPassTraceList snapshot{
            reinterpret_cast<std::uintptr_t>(commands)};
        const auto trace = command_traces.find(commands);
        if (trace != command_traces.end()) {
          snapshot.generation = trace->second.recording_generation;
          snapshot.draws = trace->second.draw_count;
          snapshot.indexed_draws = trace->second.indexed_draw_count;
          snapshot.dispatches = trace->second.dispatch_count;
          snapshot.indirects = trace->second.indirect_count;
          snapshot.copies = trace->second.copy_count;
          snapshot.resolves = trace->second.resolve_count;
          snapshot.barriers = trace->second.barrier_count;
          snapshot.passes = trace->second.render_pass_count;
        }
        active->pass_trace_lists.push_back(snapshot);
      }
    }
    return {static_cast<int>(eye_index), batch_index};
  }
  return {};
}

void end_gpu_pass_trace_batch_locked(ID3D12CommandQueue* queue,
                                     const GpuPassTraceToken& token) {
  if (token.eye < 0 || token.eye > 1) {
    return;
  }
  auto& active = gpu_profile_active[static_cast<std::size_t>(token.eye)];
  if (!active || !active->pass_trace_enabled ||
      token.batch != active->pass_trace_batch_count) {
    return;
  }
  const auto query_start = active->slot * kGpuProfileQueriesPerSlot;
  if (submit_gpu_pass_trace_marker_locked(
          *active, queue,
          query_start + kGpuProfileBaseQueryCount + token.batch * 2U + 1U)) {
    active->pass_trace_batch_count = token.batch + 1U;
  } else {
    const auto& batch = active->pass_trace_batches[token.batch];
    active->pass_trace_lists.resize(batch.list_offset);
  }
}

constexpr wchar_t kLeftEyeName[] = L"Local\\DarktideVR-eye-left";
constexpr wchar_t kRightEyeName[] = L"Local\\DarktideVR-eye-right";
constexpr wchar_t kReadyFenceName[] = L"Local\\DarktideVR-eye-ready";
constexpr wchar_t kConsumedFenceName[] = L"Local\\DarktideVR-eye-consumed";
constexpr wchar_t kMenuSurfaceName[] = L"Local\\DarktideVR-menu-ui";
constexpr wchar_t kMenuReadyFenceName[] = L"Local\\DarktideVR-menu-ui-ready";
constexpr wchar_t kMenuConsumedFenceName[] =
    L"Local\\DarktideVR-menu-ui-consumed";

int capture_menu_from_resource(ID3D12CommandQueue* queue,
                               ID3D12Resource* source,
                               D3D12_RESOURCE_STATES source_state,
                               std::uint64_t capture_width = 0,
                               UINT capture_height = 0);
int ensure_menu_surface(ID3D12Device* device,
                        const D3D12_RESOURCE_DESC& source_description,
                        DXGI_FORMAT render_target_format = DXGI_FORMAT_UNKNOWN);

struct MenuDrawRedirect {
  bool active{};
  D3D12_CPU_DESCRIPTOR_HANDLE original_target{};
  D3D12_CPU_DESCRIPTOR_HANDLE capture_target{};
  ComPtr<ID3D12Resource> original_resource;
  ComPtr<ID3D12Resource> capture_resource;
  std::uint64_t diagnostic_id{};
};

MenuDrawRedirect begin_stock_menu_draw_redirect(
    ID3D12GraphicsCommandList* commands, const PsoMetadata& metadata,
    UINT vertex_count, UINT instance_count);
void end_stock_menu_draw_redirect(ID3D12GraphicsCommandList* commands,
                                  const MenuDrawRedirect& redirect);
int present_desktop_eye_mirror(IDXGISwapChain3* swapchain,
                               ID3D12CommandQueue* queue, bool engine_source = false);

void write_marker_log(const char* format, ...) {
  if (marker_log == INVALID_HANDLE_VALUE ||
      marker_count.fetch_add(1, std::memory_order_relaxed) >= 100000) {
    return;
  }
  char line[1600]{};
  va_list arguments;
  va_start(arguments, format);
  const auto length = std::vsnprintf(line, sizeof(line), format, arguments);
  va_end(arguments);
  if (length <= 0) {
    return;
  }
  DWORD written{};
  std::scoped_lock lock(state_mutex);
  WriteFile(marker_log, line,
            static_cast<DWORD>((std::min)(
                length, static_cast<int>(sizeof(line) - 1))),
            &written, nullptr);
}

void write_boundary_census_log(const char* format, ...) {
  if (boundary_census_log == INVALID_HANDLE_VALUE ||
      boundary_census_log_count.fetch_add(1, std::memory_order_relaxed) >=
          10000) {
    return;
  }
  char line[1600]{};
  va_list arguments;
  va_start(arguments, format);
  const auto length = std::vsnprintf(line, sizeof(line), format, arguments);
  va_end(arguments);
  if (length <= 0) {
    return;
  }
  DWORD written{};
  std::scoped_lock lock(boundary_census_log_mutex);
  if (boundary_census_log != INVALID_HANDLE_VALUE) {
    WriteFile(boundary_census_log, line,
              static_cast<DWORD>((std::min)(
                  length, static_cast<int>(sizeof(line) - 1))),
              &written, nullptr);
  }
}

void write_menu_resource_log(const char* format, ...) {
  if (menu_resource_log_count.fetch_add(1, std::memory_order_relaxed) >=
      4096) {
    return;
  }
  std::scoped_lock lock(menu_resource_log_mutex);
  if (menu_resource_log == INVALID_HANDLE_VALUE) {
    wchar_t temporary_path[MAX_PATH]{};
    if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
      return;
    }
    const std::wstring path =
        std::wstring(temporary_path) + L"darktidevr-menu-resources.log";
    menu_resource_log =
        CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  }
  if (menu_resource_log == INVALID_HANDLE_VALUE) {
    return;
  }
  char line[800]{};
  va_list arguments;
  va_start(arguments, format);
  const auto length = std::vsnprintf(line, sizeof(line), format, arguments);
  va_end(arguments);
  if (length <= 0) {
    return;
  }
  DWORD written{};
  WriteFile(menu_resource_log, line,
            static_cast<DWORD>((std::min)(
                length, static_cast<int>(sizeof(line) - 1))),
            &written, nullptr);
}

bool trace_streamline_submission_images();

void write_streamline_probe_log(const char* format, ...) {
  // Startup can remain in character selection indefinitely. Reserve half the
  // bounded log for the one-shot input/submission transaction so periodic
  // Present telemetry cannot erase its eventual result.
  const bool transaction_record =
      std::strncmp(format, "UI_ALPHA_", 9) == 0 ||
      std::strncmp(format, "STEREO_", 7) == 0 ||
      std::strncmp(format, "INPUT_SNAPSHOT", 14) == 0 ||
      std::strncmp(format, "HEAD_POSE_READ", 14) == 0 ||
      (trace_streamline_submission_images() &&
       (std::strncmp(format, "EYE_OUTPUT_BOUNDARY", 19) == 0 ||
        std::strncmp(format, "SET_CONSTANTS", 13) == 0)) ||
      std::strncmp(format, "ISOLATED_EYE_CAPTURE", sizeof("ISOLATED_EYE_CAPTURE") - 1) == 0;
  if (!transaction_record &&
      streamline_probe_background_log_count.fetch_add(
          1, std::memory_order_relaxed) >= 8192) return;
  const bool terminal_submission_record=std::strncmp(format,"UI_ALPHA_",9)==0 ||
      (std::strncmp(format,"STEREO_CONTINUOUS",17)==0 &&
      (std::strstr(format,"phase=failed") || std::strstr(format,"phase=stopped") ||
       std::strstr(format,"phase=paused") || std::strstr(format,"phase=resumed") ||
       std::strstr(format,"phase=binding_rejection") || std::strstr(format,"phase=timing")));
  if (streamline_probe_log == INVALID_HANDLE_VALUE ||
      (!terminal_submission_record && streamline_probe_log_count.fetch_add(1, std::memory_order_relaxed) >=
          16384)) {
    return;
  }
  char line[1600]{};
  va_list arguments;
  va_start(arguments, format);
  const auto length = std::vsnprintf(line, sizeof(line), format, arguments);
  va_end(arguments);
  if (length <= 0) {
    return;
  }
  DWORD written{};
  std::scoped_lock lock(streamline_probe_log_mutex);
  if (streamline_probe_log != INVALID_HANDLE_VALUE) {
    WriteFile(streamline_probe_log, line,
              static_cast<DWORD>((std::min)(
                  length, static_cast<int>(sizeof(line) - 1))),
              &written, nullptr);
  }
}

int sl_get_new_frame_token_hook(void** token,
                                const std::uint32_t* frame_index) {
  const auto requested_index = frame_index ? *frame_index : UINT_MAX;
  const auto result = original_sl_get_new_frame_token
                          ? original_sl_get_new_frame_token(token, frame_index)
                          : 36;
  const auto call = streamline_frame_token_call_count.fetch_add(
                        1, std::memory_order_relaxed) +
                    1;
  const auto resolved_token = token ? *token : nullptr;
  if (result == 0 && resolved_token) {
    streamline_latest_frame_token.store(resolved_token,
                                        std::memory_order_relaxed);
    streamline_latest_frame_index.store(requested_index,
                                        std::memory_order_relaxed);
    streamline_latest_frame_token_call.store(call, std::memory_order_release);
    const auto history_slot = call % kStreamlineFrameTokenHistorySize;
    streamline_frame_token_history_calls[history_slot].store(
        0, std::memory_order_release);
    streamline_frame_token_history_tokens[history_slot].store(
        resolved_token, std::memory_order_relaxed);
    streamline_frame_token_history_indices[history_slot].store(
        requested_index, std::memory_order_relaxed);
    streamline_frame_token_history_calls[history_slot].store(
        call, std::memory_order_release);
  }
  const auto burst_until =
      streamline_native_burst_until_call.load(std::memory_order_acquire);
  if (call <= 100 ||
      (burst_until != 0 &&
       streamline_native_present_count.load(std::memory_order_relaxed) <=
           burst_until)) {
    LARGE_INTEGER qpc{};
    QueryPerformanceCounter(&qpc);
    write_streamline_probe_log(
        "FRAME_TOKEN\tcall=%llu\tpresent_frame=%llu\tthread=%lu"
        "\tqpc=%lld\tresult=%d\ttoken=%p\trequested_index=%u\r\n",
        static_cast<unsigned long long>(call),
        static_cast<unsigned long long>(
            present_count.load(std::memory_order_relaxed)),
        GetCurrentThreadId(), qpc.QuadPart, result, resolved_token,
        requested_index);
  }
  return result;
}

int sl_set_constants_hook(const void* constants, const void* frame,
                          const void* viewport) {
  const auto result = original_sl_set_constants
                          ? original_sl_set_constants(constants, frame, viewport)
                          : 36;
  const auto call = streamline_set_constants_call_count.fetch_add(
                        1, std::memory_order_relaxed) +
                    1;
  const auto burst_until =
      streamline_native_burst_until_call.load(std::memory_order_acquire);
  if (streamline_input_snapshot_probe_requested.load(
          std::memory_order_acquire) ||
      call <= 100 ||
      (burst_until != 0 &&
       streamline_native_present_count.load(std::memory_order_relaxed) <=
           burst_until)) {
    using namespace darktidevr::producer::streamline_2_7_30;
    const auto* constants_state = static_cast<const Constants*>(constants);
    const auto* viewport_state = static_cast<const
        ViewportHandle*>(viewport);
    LARGE_INTEGER qpc{};
    QueryPerformanceCounter(&qpc);
    std::uint64_t frame_token_call{};
    std::uint32_t frame_index{UINT_MAX};
    for (std::size_t slot = 0; slot < kStreamlineFrameTokenHistorySize;
         ++slot) {
      const auto first_call = streamline_frame_token_history_calls[slot].load(
          std::memory_order_acquire);
      if (first_call == 0 || first_call <= frame_token_call) {
        continue;
      }
      const auto candidate = streamline_frame_token_history_tokens[slot].load(
          std::memory_order_relaxed);
      const auto candidate_index =
          streamline_frame_token_history_indices[slot].load(
              std::memory_order_relaxed);
      const auto second_call = streamline_frame_token_history_calls[slot].load(
          std::memory_order_acquire);
      if (first_call == second_call && candidate == frame) {
        frame_token_call = first_call;
        frame_index = candidate_index;
      }
    }
    int armed_eye = -1;
    std::uint64_t armed_pose{};
    std::size_t armed_count{};
    {
      // These observations now own live FG inputs. Contention must not silently
      // drop the eye/pose association as it could for diagnostic-only logging.
      std::scoped_lock lock(boundary_capture_mutex);
      {
        armed_count = armed_eye_captures.size();
        if (!armed_eye_captures.empty()) {
          armed_eye = armed_eye_captures.front().eye;
          armed_pose = armed_eye_captures.front().pose_sequence;
        }
      }
    }
    write_streamline_probe_log(
        "SET_CONSTANTS\tcall=%llu\tpresent_frame=%llu\tthread=%lu"
        "\tqpc=%lld\tresult=%d\ttoken=%p\tframe_token_call=%llu"
        "\tframe_index=%u\tviewport=%u\tconstants=%p"
        "\tversion=%zu\tjitter=%.9g,%.9g\tmvec_scale=%.9g,%.9g"
        "\tpinhole=%.9g,%.9g\tcamera_pos=%.9g,%.9g,%.9g"
        "\tcamera_up=%.9g,%.9g,%.9g\tcamera_right=%.9g,%.9g,%.9g"
        "\tcamera_fwd=%.9g,%.9g,%.9g\tnear=%.9g\tfar=%.9g"
        "\tfov=%.9g\taspect=%.9g\tmvec_invalid=%.9g"
        "\tdepth_inverted=%d\tcamera_motion_included=%d\tmvec_3d=%d"
        "\treset=%d\torthographic=%d\tmvec_dilated=%d\tmvec_jittered=%d"
        "\tmin_relative_depth_separation=%.9g\tarmed_eye=%d"
        "\tarmed_pose=%llu\tarmed_count=%zu\r\n",
        static_cast<unsigned long long>(call),
        static_cast<unsigned long long>(
            present_count.load(std::memory_order_relaxed)),
        GetCurrentThreadId(), qpc.QuadPart, result, frame,
        static_cast<unsigned long long>(frame_token_call),
        frame_index,
        viewport_state ? viewport_state->value : 0, constants_state,
        constants_state ? constants_state->base.struct_version : 0,
        constants_state ? constants_state->jitter_offset.x : 0.0f,
        constants_state ? constants_state->jitter_offset.y : 0.0f,
        constants_state ? constants_state->motion_vector_scale.x : 0.0f,
        constants_state ? constants_state->motion_vector_scale.y : 0.0f,
        constants_state ? constants_state->camera_pinhole_offset.x : 0.0f,
        constants_state ? constants_state->camera_pinhole_offset.y : 0.0f,
        constants_state ? constants_state->camera_position.x : 0.0f,
        constants_state ? constants_state->camera_position.y : 0.0f,
        constants_state ? constants_state->camera_position.z : 0.0f,
        constants_state ? constants_state->camera_up.x : 0.0f,
        constants_state ? constants_state->camera_up.y : 0.0f,
        constants_state ? constants_state->camera_up.z : 0.0f,
        constants_state ? constants_state->camera_right.x : 0.0f,
        constants_state ? constants_state->camera_right.y : 0.0f,
        constants_state ? constants_state->camera_right.z : 0.0f,
        constants_state ? constants_state->camera_forward.x : 0.0f,
        constants_state ? constants_state->camera_forward.y : 0.0f,
        constants_state ? constants_state->camera_forward.z : 0.0f,
        constants_state ? constants_state->camera_near : 0.0f,
        constants_state ? constants_state->camera_far : 0.0f,
        constants_state ? constants_state->camera_fov : 0.0f,
        constants_state ? constants_state->camera_aspect_ratio : 0.0f,
        constants_state ? constants_state->motion_vectors_invalid_value : 0.0f,
        constants_state ? static_cast<int>(constants_state->depth_inverted) : -1,
        constants_state
            ? static_cast<int>(constants_state->camera_motion_included)
            : -1,
        constants_state ? static_cast<int>(constants_state->motion_vectors_3d)
                        : -1,
        constants_state ? static_cast<int>(constants_state->reset) : -1,
        constants_state
            ? static_cast<int>(constants_state->orthographic_projection)
            : -1,
        constants_state
            ? static_cast<int>(constants_state->motion_vectors_dilated)
            : -1,
        constants_state
            ? static_cast<int>(constants_state->motion_vectors_jittered)
            : -1,
        constants_state
            ? constants_state->min_relative_linear_depth_object_separation
            : 0.0f,
        armed_eye, static_cast<unsigned long long>(armed_pose), armed_count);
    if (constants_state && armed_eye >= 0) {
      {
        std::scoped_lock lock(streamline_input_snapshot_mutex);
        auto& observation = streamline_constants_observations[
            static_cast<std::size_t>(armed_eye)];
        observation.valid = result == 0 && frame_token_call != 0 &&
                            frame_index != UINT_MAX && viewport_state;
        observation.constants = *constants_state;
        observation.frame_token = const_cast<void*>(frame);
        observation.frame_token_call = frame_token_call;
        observation.constants_call = call;
        observation.present_frame =
            present_count.load(std::memory_order_relaxed);
        observation.pose_sequence = armed_pose;
        observation.frame_index = frame_index;
        observation.viewport = viewport_state ? viewport_state->value : 0;
      }
      const auto log_matrix = [&](const char* name, const Float4x4& matrix) {
        write_streamline_probe_log(
            "SET_CONSTANTS_MATRIX\tcall=%llu\tviewport=%u\ttoken=%p"
            "\tname=%s\tvalues=%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,"
            "%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g"
            "\tarmed_eye=%d\tarmed_pose=%llu\r\n",
            static_cast<unsigned long long>(call),
            viewport_state ? viewport_state->value : 0, frame, name,
            matrix.row[0].x, matrix.row[0].y, matrix.row[0].z,
            matrix.row[0].w, matrix.row[1].x, matrix.row[1].y,
            matrix.row[1].z, matrix.row[1].w, matrix.row[2].x,
            matrix.row[2].y, matrix.row[2].z, matrix.row[2].w,
            matrix.row[3].x, matrix.row[3].y, matrix.row[3].z,
            matrix.row[3].w, armed_eye,
            static_cast<unsigned long long>(armed_pose));
      };
      log_matrix("camera_view_to_clip", constants_state->camera_view_to_clip);
      log_matrix("clip_to_camera_view", constants_state->clip_to_camera_view);
      log_matrix("clip_to_lens_clip", constants_state->clip_to_lens_clip);
      log_matrix("clip_to_prev_clip", constants_state->clip_to_prev_clip);
      log_matrix("prev_clip_to_clip", constants_state->prev_clip_to_clip);
    }
  }
  return result;
}

const char* streamline_buffer_type_name(std::uint32_t type) {
  switch (type) {
    case 0:
      return "depth";
    case 1:
      return "motion_vectors";
    case 2:
      return "hudless_color";
    case 3:
      return "scaling_input_color";
    case 4:
      return "scaling_output_color";
    case 23:
      return "ui_color_alpha";
    case 34:
      return "alpha";
    case 35:
      return "opaque_color";
    case 48:
      return "high_resolution_depth";
    case 49:
      return "linear_depth";
    case 53:
      return "backbuffer";
    case 54:
      return "no_warp_mask";
    case 67:
      return "scaling_output_alpha";
    default:
      return "other";
  }
}

void log_streamline_resource_tags(
    const char* api, std::uint64_t call, int result, const void* frame,
    const void* viewport, const void* tags, std::uint32_t count,
    void* command_buffer) {
  using namespace darktidevr::producer::streamline_2_7_30;
  const auto* viewport_state = static_cast<const ViewportHandle*>(viewport);
  const auto* resource_tags = static_cast<const ResourceTag*>(tags);
  const auto logged_count = (std::min)(count, 32U);
  LARGE_INTEGER qpc{};
  QueryPerformanceCounter(&qpc);
  const auto present_frame = present_count.load(std::memory_order_relaxed);
  int armed_eye = -1;
  std::uint64_t armed_pose{};
  std::size_t armed_count{};
  {
    std::scoped_lock lock(boundary_capture_mutex);
    {
      armed_count = armed_eye_captures.size();
      if (!armed_eye_captures.empty()) {
        armed_eye = armed_eye_captures.front().eye;
        armed_pose = armed_eye_captures.front().pose_sequence;
      }
    }
  }
  if (!resource_tags || logged_count == 0) {
    write_streamline_probe_log(
        "RESOURCE_TAG_CALL\tapi=%s\tcall=%llu\tthread=%lu\tresult=%d"
        "\tframe=%p\tviewport=%u\ttags=%u\tcommand_buffer=%p"
        "\tqpc=%lld\tpresent_frame=%llu\tarmed_eye=%d\tarmed_pose=%llu"
        "\tarmed_count=%zu\r\n",
        api, static_cast<unsigned long long>(call), GetCurrentThreadId(),
        result, frame, viewport_state ? viewport_state->value : 0, count,
        command_buffer, qpc.QuadPart,
        static_cast<unsigned long long>(present_frame), armed_eye,
        static_cast<unsigned long long>(armed_pose), armed_count);
    return;
  }
  for (std::uint32_t index = 0; index < logged_count; ++index) {
    const auto& tag = resource_tags[index];
    const auto* resource = tag.resource;
    D3D12_RESOURCE_DESC description{};
    bool d3d12_resource{};
    if (resource && resource->type == ResourceType::texture_2d &&
        resource->native) {
      ComPtr<ID3D12Resource> texture;
      if (SUCCEEDED(static_cast<IUnknown*>(resource->native)
                        ->QueryInterface(IID_PPV_ARGS(&texture)))) {
        description = texture->GetDesc();
        d3d12_resource = true;
        if (streamline_input_snapshot_probe_requested.load(
                std::memory_order_acquire) &&
            result == 0 && tag.type < kStreamlineInputCount &&
            armed_eye >= 0 && armed_eye <= 1) {
          std::scoped_lock lock(streamline_input_snapshot_mutex);
          auto& observed =
              streamline_tagged_inputs[static_cast<std::size_t>(armed_eye)]
                                      [static_cast<std::size_t>(tag.type)];
          observed.resource = texture;
          observed.state =
              static_cast<D3D12_RESOURCE_STATES>(resource->state);
          observed.present_frame = present_frame;
          observed.pose_sequence = armed_pose;
        }
      }
    }
    write_streamline_probe_log(
        "RESOURCE_TAG\tapi=%s\tcall=%llu\tthread=%lu\tresult=%d"
        "\tframe=%p\tviewport=%u\tindex=%u\tcount=%u\ttype=%u"
        "\ttype_name=%s\tlifecycle=%u\textent=%u,%u,%u,%u"
        "\tresource=%p\tnative=%p\tresource_type=%d\tstate=%u"
        "\tabi_extent=%ux%u\tabi_format=%u\td3d12=%u"
        "\td3d12_extent=%llux%u\td3d12_format=%u\td3d12_flags=%u"
        "\tcommand_buffer=%p\tqpc=%lld\tpresent_frame=%llu"
        "\tarmed_eye=%d\tarmed_pose=%llu\tarmed_count=%zu\r\n",
        api, static_cast<unsigned long long>(call), GetCurrentThreadId(),
        result, frame, viewport_state ? viewport_state->value : 0, index,
        count, tag.type, streamline_buffer_type_name(tag.type), tag.lifecycle,
        tag.extent.left, tag.extent.top, tag.extent.width, tag.extent.height,
        resource, resource ? resource->native : nullptr,
        resource ? static_cast<int>(resource->type) : -1,
        resource ? resource->state : 0,
        resource ? resource->width : 0, resource ? resource->height : 0,
        resource ? resource->native_format : 0, d3d12_resource ? 1U : 0U,
        static_cast<unsigned long long>(description.Width), description.Height,
        static_cast<unsigned>(description.Format),
        static_cast<unsigned>(description.Flags), command_buffer,
        qpc.QuadPart, static_cast<unsigned long long>(present_frame), armed_eye,
        static_cast<unsigned long long>(armed_pose), armed_count);
  }
}

int sl_set_tag_hook(const void* viewport, const void* tags,
                    std::uint32_t count, void* command_buffer) {
  int result{};
  {
    std::scoped_lock lock(streamline_tagging_api_mutex);
    result = original_sl_set_tag
                          ? original_sl_set_tag(viewport, tags, count,
                                                command_buffer)
                          : 36;
  }
  if (result == 0) streamline_tagging_api_modes.fetch_or(1, std::memory_order_relaxed);
  const auto call = streamline_set_tag_call_count.fetch_add(
                        1, std::memory_order_relaxed) +
                    1;
  const auto burst_until =
      streamline_native_burst_until_call.load(std::memory_order_acquire);
  if (streamline_input_snapshot_probe_requested.load(std::memory_order_acquire) || call <= 50 ||
      (burst_until != 0 &&
       streamline_native_present_count.load(std::memory_order_relaxed) <=
           burst_until)) {
    log_streamline_resource_tags("slSetTag", call, result, nullptr, viewport,
                                 tags, count, command_buffer);
  }
  return result;
}

int sl_set_tag_for_frame_hook(const void* frame, const void* viewport,
                              const void* tags, std::uint32_t count,
                              void* command_buffer) {
  int result{};
  {
    std::scoped_lock lock(streamline_tagging_api_mutex);
    result = original_sl_set_tag_for_frame
                          ? original_sl_set_tag_for_frame(
                                frame, viewport, tags, count, command_buffer)
                          : 36;
  }
  if (result == 0) streamline_tagging_api_modes.fetch_or(2, std::memory_order_relaxed);
  const auto call = streamline_set_tag_call_count.fetch_add(
                        1, std::memory_order_relaxed) +
                    1;
  const auto burst_until =
      streamline_native_burst_until_call.load(std::memory_order_acquire);
  if (streamline_input_snapshot_probe_requested.load(std::memory_order_acquire) || call <= 50 ||
      (burst_until != 0 &&
       streamline_native_present_count.load(std::memory_order_relaxed) <=
           burst_until)) {
    log_streamline_resource_tags("slSetTagForFrame", call, result, frame,
                                 viewport, tags, count, command_buffer);
  }
  return result;
}

std::wstring module_path(HMODULE module) {
  std::array<wchar_t, 32768> path{};
  const auto length = GetModuleFileNameW(
      module, path.data(), static_cast<DWORD>(path.size()));
  return length != 0 && length < path.size()
             ? std::wstring(path.data(), length)
             : std::wstring{};
}

std::string module_file_version(const std::wstring& path) {
  DWORD ignored{};
  const auto bytes = GetFileVersionInfoSizeW(path.c_str(), &ignored);
  if (bytes == 0) {
    return "unknown";
  }
  std::vector<std::byte> data(bytes);
  if (!GetFileVersionInfoW(path.c_str(), 0, bytes, data.data())) {
    return "unknown";
  }
  VS_FIXEDFILEINFO* fixed{};
  UINT fixed_bytes{};
  if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&fixed),
                      &fixed_bytes) ||
      !fixed || fixed_bytes < sizeof(*fixed)) {
    return "unknown";
  }
  char version[64]{};
  std::snprintf(version, sizeof(version), "%u.%u.%u.%u",
                HIWORD(fixed->dwFileVersionMS), LOWORD(fixed->dwFileVersionMS),
                HIWORD(fixed->dwFileVersionLS), LOWORD(fixed->dwFileVersionLS));
  return version;
}

void log_streamline_modules(bool log_missing) {
  constexpr std::array<const wchar_t*, 4> names{
      L"sl.interposer.dll", L"sl.common.dll", L"sl.dlss_g.dll",
      L"nvngx_dlssg.dll"};
  for (std::size_t index = 0; index < names.size(); ++index) {
    const auto module = GetModuleHandleW(names[index]);
    const auto bit = 1U << index;
    if (!module) {
      if (log_missing) {
        write_streamline_probe_log("MODULE\tname=%ls\tloaded=0\r\n",
                                   names[index]);
      }
      continue;
    }
    if ((streamline_loaded_module_mask.fetch_or(bit,
                                                std::memory_order_relaxed) &
         bit) != 0) {
      continue;
    }
    const auto path = module_path(module);
    const auto version = module_file_version(path);
    write_streamline_probe_log(
        "MODULE\tname=%ls\tloaded=1\tbase=%p\tversion=%s\tpath=%ls"
        "\tslGetFeatureFunction=%p\tslGetFeatureRequirements=%p"
        "\tslGetFeatureVersion=%p\tslIsFeatureLoaded=%p"
        "\tslGetNativeInterface=%p\tslGetPluginFunction=%p\r\n",
        names[index], module, version.c_str(), path.c_str(),
        GetProcAddress(module, "slGetFeatureFunction"),
        GetProcAddress(module, "slGetFeatureRequirements"),
        GetProcAddress(module, "slGetFeatureVersion"),
        GetProcAddress(module, "slIsFeatureLoaded"),
        GetProcAddress(module, "slGetNativeInterface"),
        GetProcAddress(module, "slGetPluginFunction"));
  }
}

int sl_dlssg_get_state_hook(const void* viewport, void* state,
                            const void* options) {
  const auto original =
      original_sl_dlssg_get_state.load(std::memory_order_acquire);
  if (!original) {
    return 36;
  }
  int result{};
  {
    std::scoped_lock api_lock(streamline_feature_api_mutex);
    result = original(viewport, state, options);
  }
  const auto call = streamline_dlssg_state_count.fetch_add(
                        1, std::memory_order_relaxed) +
                    1;
  if (call <= 30 || call % 120 == 0) {
    const auto* viewport_state = static_cast<const
        darktidevr::producer::streamline_2_7_30::ViewportHandle*>(viewport);
    const auto* dlssg_state = static_cast<const
        darktidevr::producer::streamline_2_7_30::DlssGState*>(state);
    const auto version = dlssg_state ? dlssg_state->base.struct_version : 0;
    const auto generated_max =
        dlssg_state && version >= 2
            ? dlssg_state->num_frames_to_generate_max
            : 0;
    const auto completion_fence =
        dlssg_state && version >= 3
            ? dlssg_state->inputs_processing_completion_fence
            : nullptr;
    const auto completion_value =
        dlssg_state && version >= 3
            ? dlssg_state
                  ->last_present_inputs_processing_completion_fence_value
            : 0;
    LARGE_INTEGER qpc{};
    QueryPerformanceCounter(&qpc);
    write_streamline_probe_log(
        "DLSSG_STATE\tcall=%llu\tpresent_frame=%llu\tthread=%lu"
        "\tqpc=%lld\tresult=%d\tviewport=%u\tstate_version=%llu"
        "\tstatus=%u\tmin_dimension=%u\tframes_presented=%u"
        "\tframes_to_generate_max=%u\tvsync_support=%u"
        "\tinputs_fence=%p\tinputs_fence_value=%llu\r\n",
        static_cast<unsigned long long>(call),
        static_cast<unsigned long long>(
            present_count.load(std::memory_order_relaxed)),
        GetCurrentThreadId(), qpc.QuadPart, result,
        viewport_state ? viewport_state->value : 0,
        static_cast<unsigned long long>(version),
        dlssg_state ? dlssg_state->status : 0,
        dlssg_state ? dlssg_state->min_width_or_height : 0,
        dlssg_state ? dlssg_state->num_frames_actually_presented : 0,
        generated_max,
        dlssg_state && version >= 2
            ? static_cast<unsigned>(dlssg_state->vsync_support_available)
            : 0,
        completion_fence,
        static_cast<unsigned long long>(completion_value));
  }
  return result;
}

int sl_dlssg_set_options_hook(const void* viewport, const void* options) {
  const auto original =
      original_sl_dlssg_set_options.load(std::memory_order_acquire);
  if (!original) {
    return 36;
  }
  const auto* viewport_state = static_cast<const
      darktidevr::producer::streamline_2_7_30::ViewportHandle*>(viewport);
  const auto* dlssg_options = static_cast<const
      darktidevr::producer::streamline_2_7_30::DlssGOptions*>(options);
  int result{};
  {
    std::scoped_lock api_lock(streamline_feature_api_mutex);
    result = original(viewport, options);
  }
  const auto call = streamline_dlssg_options_count.fetch_add(
                        1, std::memory_order_relaxed) +
                    1;
  if (result == 0 && viewport_state && dlssg_options &&
      dlssg_options->base.struct_version >= 1) {
    std::scoped_lock lock(streamline_input_snapshot_mutex);
    auto* destination = static_cast<StreamlineOptionsObservation*>(nullptr);
    for (auto& observation : streamline_options_observations) {
      if (observation.valid && observation.viewport == viewport_state->value) {
        destination = &observation;
        break;
      }
      if (!destination && !observation.valid) destination = &observation;
    }
    if (destination) {
      *destination = {viewport_state->value, dlssg_options->mode,
                     present_count.load(std::memory_order_relaxed), true};
    }
  }
  if (call <= 100 || call % 120 == 0) {
    LARGE_INTEGER qpc{};
    QueryPerformanceCounter(&qpc);
    write_streamline_probe_log(
        "DLSSG_OPTIONS\tcall=%llu\tpresent_frame=%llu\tthread=%lu"
        "\tqpc=%lld\tresult=%d\tviewport=%u\toptions_version=%llu"
        "\tmode=%u\tframes_to_generate=%u\tflags=%u"
        "\tback_buffers=%u\tmotion_depth=%ux%u\tcolor=%ux%u"
        "\tcolor_format=%u\tmotion_format=%u\tdepth_format=%u"
        "\thudless_format=%u\tui_format=%u\tqueue_mode=%u\r\n",
        static_cast<unsigned long long>(call),
        static_cast<unsigned long long>(
            present_count.load(std::memory_order_relaxed)),
        GetCurrentThreadId(), qpc.QuadPart, result,
        viewport_state ? viewport_state->value : 0,
        dlssg_options
            ? static_cast<unsigned long long>(
                  dlssg_options->base.struct_version)
            : 0,
        dlssg_options ? dlssg_options->mode : 0,
        dlssg_options ? dlssg_options->num_frames_to_generate : 0,
        dlssg_options ? dlssg_options->flags : 0,
        dlssg_options ? dlssg_options->num_back_buffers : 0,
        dlssg_options ? dlssg_options->motion_depth_width : 0,
        dlssg_options ? dlssg_options->motion_depth_height : 0,
        dlssg_options ? dlssg_options->color_width : 0,
        dlssg_options ? dlssg_options->color_height : 0,
        dlssg_options ? dlssg_options->color_buffer_format : 0,
        dlssg_options ? dlssg_options->motion_buffer_format : 0,
        dlssg_options ? dlssg_options->depth_buffer_format : 0,
        dlssg_options ? dlssg_options->hudless_buffer_format : 0,
        dlssg_options ? dlssg_options->ui_buffer_format : 0,
        dlssg_options && dlssg_options->base.struct_version >= 3
            ? dlssg_options->queue_parallelism_mode
            : 0);
  }
  return result;
}

int sl_get_feature_function_hook(std::uint32_t feature, const char* name,
                                 void** function) {
  const auto result = original_sl_get_feature_function
                          ? original_sl_get_feature_function(feature, name,
                                                             function)
                          : 36;
  const auto resolved = function ? *function : nullptr;
  bool wrapped{};
  if (result == 0 && feature ==
                         darktidevr::producer::streamline_2_7_30::kFeatureDlssG &&
      name && std::strcmp(name, "slDLSSGGetState") == 0 && resolved &&
      resolved != reinterpret_cast<void*>(&sl_dlssg_get_state_hook)) {
    original_sl_dlssg_get_state.store(
        reinterpret_cast<SlDlssGGetStateFn>(resolved),
        std::memory_order_release);
    *function = reinterpret_cast<void*>(&sl_dlssg_get_state_hook);
    wrapped = true;
  } else if (result == 0 &&
             feature == darktidevr::producer::streamline_2_7_30::kFeatureDlssG &&
             name && std::strcmp(name, "slDLSSGSetOptions") == 0 && resolved &&
             resolved != reinterpret_cast<void*>(&sl_dlssg_set_options_hook)) {
    original_sl_dlssg_set_options.store(
        reinterpret_cast<SlDlssGSetOptionsFn>(resolved),
        std::memory_order_release);
    *function = reinterpret_cast<void*>(&sl_dlssg_set_options_hook);
    wrapped = true;
  }
  const auto call = streamline_feature_resolve_count.fetch_add(
                        1, std::memory_order_relaxed) +
                    1;
  if (call <= 100 || wrapped) {
    write_streamline_probe_log(
        "FEATURE_RESOLVE\tcall=%llu\tthread=%lu\tfeature=%u"
        "\tname=%s\tresult=%d\tresolved=%p\twrapped=%u\r\n",
        static_cast<unsigned long long>(call), GetCurrentThreadId(), feature,
        name ? name : "(null)", result, resolved, wrapped ? 1U : 0U);
  }
  return result;
}

void initialize_streamline_probe(void* present_target,
                                 void* native_present_target) {
  auto flag_path = module_path(native_capture_module);
  const auto separator = flag_path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return;
  }
  flag_path.resize(separator + 1);
  const auto flag_directory = flag_path;
  flag_path += L"..\\darktidevr_streamline_probe.flag";
  if (GetFileAttributesW(flag_path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return;
  }
  wchar_t temporary_path[MAX_PATH]{};
  if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
    return;
  }
  const auto path = std::wstring(temporary_path) +
                    L"darktidevr-streamline-probe.tsv";
  streamline_probe_log =
      CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                  CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (streamline_probe_log == INVALID_HANDLE_VALUE) {
    return;
  }
  const auto eye_target_flag_path =
      flag_directory + L"..\\darktidevr_streamline_eye_target_probe.flag";
  streamline_eye_target_probe_requested.store(
      GetFileAttributesW(eye_target_flag_path.c_str()) != INVALID_FILE_ATTRIBUTES,
      std::memory_order_release);
  if (streamline_eye_target_probe_requested.load(std::memory_order_acquire)) {
    write_streamline_probe_log("ISOLATED_EYE_POLICY\tenabled=1\r\n");
  }
  const auto copy_flag_path =
      flag_directory + L"..\\darktidevr_streamline_copy_probe.flag";
  streamline_copy_probe_requested.store(
      GetFileAttributesW(copy_flag_path.c_str()) != INVALID_FILE_ATTRIBUTES,
      std::memory_order_release);
  const auto transport_flag_path =
      flag_directory + L"..\\darktidevr_streamline_transport_probe.flag";
  streamline_transport_probe_requested.store(
      GetFileAttributesW(transport_flag_path.c_str()) !=
          INVALID_FILE_ATTRIBUTES,
      std::memory_order_release);
  const auto input_snapshot_flag_path =
      flag_directory + L"..\\darktidevr_streamline_input_snapshot_probe.flag";
  streamline_input_snapshot_probe_requested.store(
      GetFileAttributesW(input_snapshot_flag_path.c_str()) !=
          INVALID_FILE_ATTRIBUTES,
      std::memory_order_release);
  const auto target_token_flag_path =
      flag_directory + L"..\\darktidevr_streamline_target_token_probe.flag";
  streamline_target_token_probe_requested.store(
      GetFileAttributesW(target_token_flag_path.c_str()) !=
          INVALID_FILE_ATTRIBUTES,
      std::memory_order_release);
  const auto stereo_swapchain_flag_path =
      flag_directory + L"..\\darktidevr_streamline_stereo_swapchain_probe.flag";
  streamline_stereo_swapchain_probe_requested.store(
      GetFileAttributesW(stereo_swapchain_flag_path.c_str()) !=
          INVALID_FILE_ATTRIBUTES,
      std::memory_order_release);
  const auto stereo_stage_flag_path =
      flag_directory + L"..\\darktidevr_streamline_stereo_stage_probe.flag";
  streamline_stereo_stage_probe_requested.store(
      GetFileAttributesW(stereo_stage_flag_path.c_str()) !=
          INVALID_FILE_ATTRIBUTES,
      std::memory_order_release);
  const auto interposer = GetModuleHandleW(L"sl.interposer.dll");
  const auto stereo_submit_flag_path =
      flag_directory + L"..\\darktidevr_streamline_stereo_submit_probe.flag";
  streamline_stereo_submit_probe_requested.store(
      GetFileAttributesW(stereo_submit_flag_path.c_str()) != INVALID_FILE_ATTRIBUTES,
      std::memory_order_release);
  const auto submission_limit = GetPrivateProfileIntW(
      L"probe", L"frames", 1, stereo_submit_flag_path.c_str());
  streamline_input_snapshot_state.submission_limit =
      submission_limit >= 1 && submission_limit <= 8 ? submission_limit : 1;
  streamline_continuous_requested.store(
      GetPrivateProfileIntW(L"probe", L"continuous", 0, stereo_submit_flag_path.c_str()) == 1 &&
      submission_limit >= 2 && submission_limit <= 8 &&
      streamline_stereo_submit_probe_requested.load(std::memory_order_relaxed),
      std::memory_order_release);
  streamline_persistent_requested.store(
      GetPrivateProfileIntW(L"probe",L"persistent",0,stereo_submit_flag_path.c_str()) == 1);
  write_streamline_probe_log("STEREO_SUBMISSION_PROBE\tenabled=%u\tframes=%u\r\n",
      streamline_stereo_submit_probe_requested.load(std::memory_order_relaxed) ? 1U : 0U,
      streamline_input_snapshot_state.submission_limit);
  streamline_feature_resolver_target =
      interposer ? GetProcAddress(interposer, "slGetFeatureFunction") : nullptr;
  streamline_get_new_frame_token_target =
      interposer ? GetProcAddress(interposer, "slGetNewFrameToken") : nullptr;
  streamline_set_constants_target =
      interposer ? GetProcAddress(interposer, "slSetConstants") : nullptr;
  streamline_set_tag_target =
      interposer ? GetProcAddress(interposer, "slSetTag") : nullptr;
  streamline_set_tag_for_frame_target =
      interposer ? GetProcAddress(interposer, "slSetTagForFrame") : nullptr;
  streamline_native_present_target = native_present_target;
  HMODULE owner{};
  if (present_target) {
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(present_target), &owner);
  }
  const auto owner_path = module_path(owner);
  write_streamline_probe_log(
      "PROBE\tmode=%s\tsdk_abi=2.7.30"
      "\tdlssg_state_query=existing_calls_plus_bounded_present_probe"
      "\tindependent_state_call_budget=%u\tcopy_probe=%u\ttransport_probe=%u"
      "\tinput_snapshot_probe=%u\ttarget_token_probe=%u"
      "\tstereo_swapchain_probe=%u\tstereo_stage_probe=%u\r\n",
      streamline_stereo_submit_probe_requested.load(std::memory_order_relaxed)
          ? "one_shot_submit" : "observe_only",
      streamline_input_snapshot_probe_requested.load(std::memory_order_relaxed) ? 2U : 0U,
      streamline_copy_probe_requested.load(std::memory_order_relaxed) ? 1U
                                                                     : 0U,
      streamline_transport_probe_requested.load(std::memory_order_relaxed)
          ? 1U
          : 0U,
      streamline_input_snapshot_probe_requested.load(
          std::memory_order_relaxed)
          ? 1U
          : 0U,
      streamline_target_token_probe_requested.load(std::memory_order_relaxed)
          ? 1U
          : 0U,
      streamline_stereo_swapchain_probe_requested.load(
          std::memory_order_relaxed)
          ? 1U
          : 0U,
      streamline_stereo_stage_probe_requested.load(std::memory_order_relaxed)
          ? 1U
          : 0U);
  write_streamline_probe_log(
      "PRESENT_TARGET\taddress=%p\tmodule=%p\tversion=%s\tpath=%ls\r\n",
      present_target, owner, module_file_version(owner_path).c_str(),
      owner_path.c_str());
  HMODULE native_owner{};
  if (native_present_target) {
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(native_present_target),
                       &native_owner);
  }
  const auto native_owner_path = module_path(native_owner);
  write_streamline_probe_log(
      "NATIVE_PRESENT_TARGET\taddress=%p\tmodule=%p\tversion=%s"
      "\tpath=%ls\r\n",
      native_present_target, native_owner,
      module_file_version(native_owner_path).c_str(),
      native_owner_path.c_str());
  log_streamline_modules(true);
}

void write_resize_diagnostic_log(const char* format, ...) {
  if (resize_diagnostic_log_count.fetch_add(1, std::memory_order_relaxed) >=
      10000) {
    return;
  }
  std::scoped_lock lock(resize_diagnostic_log_mutex);
  if (resize_diagnostic_log == INVALID_HANDLE_VALUE) {
    wchar_t temporary_path[MAX_PATH]{};
    if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
      return;
    }
    const std::wstring path = std::wstring(temporary_path) +
                              L"darktidevr-resize-diagnostic.log";
    resize_diagnostic_log =
        CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  }
  if (resize_diagnostic_log == INVALID_HANDLE_VALUE) {
    return;
  }
  char line[1200]{};
  va_list arguments;
  va_start(arguments, format);
  const auto length = std::vsnprintf(line, sizeof(line), format, arguments);
  va_end(arguments);
  if (length <= 0) {
    return;
  }
  DWORD written{};
  WriteFile(resize_diagnostic_log, line,
            static_cast<DWORD>((std::min)(
                length, static_cast<int>(sizeof(line) - 1))),
            &written, nullptr);
}

std::string boundary_marker_label(UINT metadata, const void* data, UINT size) {
  if (!data || size == 0) {
    return {};
  }
  if (metadata == 1) {
    const auto length = (std::min)(size, 120U);
    return std::string(static_cast<const char*>(data), length);
  }
  if (metadata == 0 && size >= sizeof(wchar_t)) {
    const auto* source = static_cast<const wchar_t*>(data);
    const auto count = (std::min)(size / static_cast<UINT>(sizeof(wchar_t)),
                                  120U);
    std::string result;
    result.reserve(count);
    for (UINT index = 0; index < count && source[index] != L'\0'; ++index) {
      result.push_back(source[index] >= 32 && source[index] <= 126
                           ? static_cast<char>(source[index])
                           : '?');
    }
    return result;
  }
  return "metadata-" + std::to_string(metadata);
}

void write_enhanced_barrier_log(const char* format, ...) {
  if (enhanced_barrier_log == INVALID_HANDLE_VALUE ||
      enhanced_barrier_log_count.fetch_add(1, std::memory_order_relaxed) >=
          250000) {
    return;
  }
  char line[800]{};
  va_list arguments;
  va_start(arguments, format);
  const auto length = std::vsnprintf(line, sizeof(line), format, arguments);
  va_end(arguments);
  if (length <= 0) {
    return;
  }
  DWORD written{};
  WriteFile(enhanced_barrier_log, line,
            static_cast<DWORD>((std::min)(
                length, static_cast<int>(sizeof(line) - 1))),
            &written, nullptr);
}

void write_focused_log(const char* format, ...) {
  if (focused_trace_phase.load(std::memory_order_relaxed) == 0 ||
      focused_trace_log == INVALID_HANDLE_VALUE ||
      focused_trace_count.fetch_add(1, std::memory_order_relaxed) >= 250000) {
    return;
  }
  char line[2400]{};
  va_list arguments;
  va_start(arguments, format);
  const auto length = std::vsnprintf(line, sizeof(line), format, arguments);
  va_end(arguments);
  if (length <= 0) {
    return;
  }
  DWORD written{};
  std::scoped_lock lock(focused_trace_mutex);
  if (focused_trace_log != INVALID_HANDLE_VALUE) {
    WriteFile(focused_trace_log, line,
              static_cast<DWORD>((std::min)(
                  length, static_cast<int>(sizeof(line) - 1))),
              &written, nullptr);
  }
}

void log_marker_event(const char* kind, ID3D12GraphicsCommandList* commands,
                      UINT metadata, const void* data, UINT size) {
  const auto sequence = marker_sequence.fetch_add(1, std::memory_order_relaxed);
  if (metadata == 1 && data && size > 0) {
    write_marker_log("%llu\t%lu\tCL=%p\t%s\tA\t%.*s\r\n", sequence,
                     GetCurrentThreadId(), commands, kind,
                     static_cast<int>(size), static_cast<const char*>(data));
  } else if (metadata == 0 && data && size >= sizeof(wchar_t)) {
    const auto characters = static_cast<int>(size / sizeof(wchar_t));
    write_marker_log("%llu\t%lu\tCL=%p\t%s\tW\t%.*ls\r\n", sequence,
                     GetCurrentThreadId(), commands, kind, characters,
                     static_cast<const wchar_t*>(data));
  } else {
    write_marker_log("%llu\t%lu\tCL=%p\t%s\tM%u\tbytes=%u\r\n", sequence,
                     GetCurrentThreadId(), commands, kind, metadata, size);
  }
}

void log_focused_marker_event(const char* kind,
                              ID3D12GraphicsCommandList* commands,
                              UINT metadata, const void* data, UINT size) {
  const auto phase = focused_trace_phase.load(std::memory_order_relaxed);
  if (phase == 0) {
    return;
  }
  const auto frame = present_count.load(std::memory_order_relaxed);
  if (metadata == 1 && data && size > 0) {
    write_focused_log("phase=%d\tframe=%llu\tCL=%p\t%s\tA\t%.*s\r\n",
                      phase, frame, commands, kind, static_cast<int>(size),
                      static_cast<const char*>(data));
  } else if (metadata == 0 && data && size >= sizeof(wchar_t)) {
    const auto characters = static_cast<int>(size / sizeof(wchar_t));
    write_focused_log("phase=%d\tframe=%llu\tCL=%p\t%s\tW\t%.*ls\r\n",
                      phase, frame, commands, kind, characters,
                      static_cast<const wchar_t*>(data));
  } else {
    write_focused_log(
        "phase=%d\tframe=%llu\tCL=%p\t%s\tM%u\tbytes=%u\r\n", phase,
        frame, commands, kind, metadata, size);
  }
}

PassCounts& current_pass(ID3D12GraphicsCommandList* commands) {
  auto& trace = command_traces[commands];
  return trace.passes[PassKey{trace.pso, trace.root_signature,
                              trace.render_target,
                              trace.depth_target, trace.render_target_count,
                              trace.viewport_x, trace.viewport_y,
                              trace.viewport_width, trace.viewport_height,
                              trace.eye}];
}

std::uint64_t hash_bytes(const void* data, std::size_t size) {
  constexpr std::uint64_t offset = 1469598103934665603ULL;
  constexpr std::uint64_t prime = 1099511628211ULL;
  auto hash = offset;
  const auto* bytes = static_cast<const std::uint8_t*>(data);
  for (std::size_t i = 0; bytes && i < size; ++i) {
    hash ^= bytes[i];
    hash *= prime;
  }
  return hash;
}

bool is_billboard_vertex_shader(std::uint64_t hash) {
  return std::find(kBillboardVertexShaderHashes.begin(),
                   kBillboardVertexShaderHashes.end(), hash) !=
         kBillboardVertexShaderHashes.end();
}

std::optional<std::size_t> billboard_vertex_shader_index(
    std::uint64_t hash) {
  const auto found = std::find(kBillboardVertexShaderHashes.begin(),
                               kBillboardVertexShaderHashes.end(), hash);
  return found == kBillboardVertexShaderHashes.end()
             ? std::nullopt
             : std::optional<std::size_t>(
                   found - kBillboardVertexShaderHashes.begin());
}

bool compatible_shader_interfaces(const D3D12_SHADER_BYTECODE& original,
                                  const D3D12_SHADER_BYTECODE& replacement);
bool compatible_pixel_shader_signatures(
    const D3D12_SHADER_BYTECODE& original,
    const D3D12_SHADER_BYTECODE& replacement);

std::wstring native_capture_directory() {
  std::array<wchar_t, 32768> module_path{};
  const auto length = GetModuleFileNameW(
      native_capture_module, module_path.data(),
      static_cast<DWORD>(module_path.size()));
  if (length == 0 || length >= module_path.size()) {
    return {};
  }
  std::wstring result(module_path.data(), length);
  const auto separator = result.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return {};
  }
  result.resize(separator + 1);
  return result;
}

std::vector<std::uint8_t> read_binary_file(const std::wstring& path) {
  const auto file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                                nullptr, OPEN_EXISTING,
                                FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return {};
  }
  LARGE_INTEGER length{};
  std::vector<std::uint8_t> result;
  if (GetFileSizeEx(file, &length) && length.QuadPart > 0 &&
      length.QuadPart <= static_cast<LONGLONG>(64 * 1024 * 1024)) {
    result.resize(static_cast<std::size_t>(length.QuadPart));
    DWORD read{};
    if (!ReadFile(file, result.data(), static_cast<DWORD>(result.size()),
                  &read, nullptr) || read != result.size()) {
      result.clear();
    }
  }
  CloseHandle(file);
  return result;
}

void load_billboard_shader_replacements() {
  const auto directory = native_capture_directory();
  std::scoped_lock lock(billboard_shader_replacement_mutex);
  billboard_shader_replacements.clear();
  billboard_target_replacement_hash.store(0, std::memory_order_relaxed);
  for (const auto hash : kBillboardVertexShaderHashes) {
    wchar_t name[96]{};
    swprintf_s(name, L"billboard_shaders\\vs-%016llx.dxil",
               static_cast<unsigned long long>(hash));
    auto bytes = read_binary_file(directory + name);
    if (!bytes.empty()) {
      if (hash == kBillboardTargetVertexShader) {
        billboard_target_replacement_hash.store(
            hash_bytes(bytes.data(), bytes.size()),
            std::memory_order_relaxed);
      }
      billboard_shader_replacements.emplace(hash, std::move(bytes));
    }
  }
  for (const auto hash : kBillboardPixelShaderHashes) {
    wchar_t name[96]{};
    swprintf_s(name, L"billboard_shaders\\ps-%016llx.dxil",
               static_cast<unsigned long long>(hash));
    auto bytes = read_binary_file(directory + name);
    if (!bytes.empty()) {
      billboard_shader_replacements.emplace(hash, std::move(bytes));
    }
  }
  const auto pixel_pattern = directory + L"billboard_shaders\\ps-*.dxil";
  WIN32_FIND_DATAW entry{};
  const auto search = FindFirstFileW(pixel_pattern.c_str(), &entry);
  if (search != INVALID_HANDLE_VALUE) {
    do {
      const std::wstring name(entry.cFileName);
      if (name.size() != 24 || name.rfind(L"ps-", 0) != 0 ||
          name.substr(19) != L".dxil") {
        continue;
      }
      wchar_t* end{};
      const auto hash = _wcstoui64(name.c_str() + 3, &end, 16);
      if (end != name.c_str() + 19) {
        continue;
      }
      auto bytes = read_binary_file(directory + L"billboard_shaders\\" + name);
      if (!bytes.empty()) {
        billboard_shader_replacements[hash] = std::move(bytes);
      }
    } while (FindNextFileW(search, &entry));
    FindClose(search);
  }
}

bool select_billboard_shader_replacement(
    const D3D12_SHADER_BYTECODE& original,
    D3D12_SHADER_BYTECODE& replacement) {
  replacement = original;
  if (!billboard_shader_substitution_requested.load(
          std::memory_order_relaxed) ||
      !original.pShaderBytecode || original.BytecodeLength == 0) {
    return false;
  }
  const auto original_hash = hash_bytes(original.pShaderBytecode,
                                        original.BytecodeLength);
  const auto shader_index = billboard_vertex_shader_index(original_hash);
  if (!shader_index) {
    return false;
  }
  billboard_shader_substitution_attempt_counts[*shader_index].fetch_add(
      1, std::memory_order_relaxed);
  std::scoped_lock lock(billboard_shader_replacement_mutex);
  const auto found = billboard_shader_replacements.find(original_hash);
  if (found == billboard_shader_replacements.end() || found->second.empty()) {
    billboard_shader_substitution_reject_count.fetch_add(
        1, std::memory_order_relaxed);
    billboard_shader_substitution_validation_reject_counts[*shader_index]
        .fetch_add(1, std::memory_order_relaxed);
    return false;
  }
  D3D12_SHADER_BYTECODE candidate{found->second.data(), found->second.size()};
  if (!compatible_shader_interfaces(original, candidate)) {
    billboard_shader_substitution_reject_count.fetch_add(
        1, std::memory_order_relaxed);
    billboard_shader_substitution_validation_reject_counts[*shader_index]
        .fetch_add(1, std::memory_order_relaxed);
    return false;
  }
  replacement = candidate;
  return true;
}

bool select_billboard_pixel_shader_replacement(
    const D3D12_SHADER_BYTECODE& original,
    D3D12_SHADER_BYTECODE& replacement) {
  replacement = original;
  if (!(billboard_pixel_shader_probe_requested.load(
            std::memory_order_relaxed) ||
        billboard_shader_substitution_requested.load(
            std::memory_order_relaxed)) ||
      !original.pShaderBytecode || original.BytecodeLength == 0) {
    return false;
  }
  const auto original_hash =
      hash_bytes(original.pShaderBytecode, original.BytecodeLength);
  std::scoped_lock lock(billboard_shader_replacement_mutex);
  const auto found = billboard_shader_replacements.find(original_hash);
  if (found == billboard_shader_replacements.end()) {
    return false;
  }
  billboard_pixel_shader_probe_attempt_count.fetch_add(
      1, std::memory_order_relaxed);
  if (found->second.empty()) {
    billboard_pixel_shader_probe_validation_reject_count.fetch_add(
        1, std::memory_order_relaxed);
    return false;
  }
  D3D12_SHADER_BYTECODE candidate{found->second.data(), found->second.size()};
  if (!compatible_pixel_shader_signatures(original, candidate)) {
    billboard_pixel_shader_probe_validation_reject_count.fetch_add(
        1, std::memory_order_relaxed);
    return false;
  }
  replacement = candidate;
  return true;
}

void record_billboard_shader_creation_result(std::uint64_t original_hash,
                                             bool applied) {
  const auto shader_index = billboard_vertex_shader_index(original_hash);
  if (!shader_index) {
    return;
  }
  if (applied) {
    billboard_shader_substitution_count.fetch_add(1,
                                                  std::memory_order_relaxed);
    billboard_shader_substitution_applied_counts[*shader_index].fetch_add(
        1, std::memory_order_relaxed);
  } else {
    billboard_shader_substitution_reject_count.fetch_add(
        1, std::memory_order_relaxed);
    billboard_shader_substitution_creation_reject_counts[*shader_index]
        .fetch_add(1, std::memory_order_relaxed);
  }
}

bool cached_blob_contains_billboard_shader(const void* data,
                                           std::size_t size) {
  const auto* bytes = static_cast<const std::uint8_t*>(data);
  if (!bytes || size < 32) {
    return false;
  }
  constexpr std::array<std::uint8_t, 4> magic{'D', 'X', 'B', 'C'};
  auto read_u32 = [](const std::uint8_t* source) {
    std::uint32_t value{};
    std::memcpy(&value, source, sizeof(value));
    return value;
  };
  const auto* cursor = bytes;
  const auto* end = bytes + size;
  while (cursor + 32 <= end) {
    cursor = std::search(cursor, end, magic.begin(), magic.end());
    if (cursor + 32 > end) {
      break;
    }
    const auto total_size = read_u32(cursor + 24);
    const auto chunk_count = read_u32(cursor + 28);
    const auto remaining = static_cast<std::size_t>(end - cursor);
    bool valid = chunk_count <= 128 &&
                 total_size >= 32ULL + static_cast<std::uint64_t>(chunk_count) * 4 &&
                 total_size <= remaining;
    for (std::uint32_t index = 0; valid && index < chunk_count; ++index) {
      const auto chunk_offset = read_u32(cursor + 32 + index * 4);
      if (chunk_offset > total_size || total_size - chunk_offset < 8) {
        valid = false;
        break;
      }
      const auto chunk_size = read_u32(cursor + chunk_offset + 4);
      if (chunk_size > total_size - chunk_offset - 8) {
        valid = false;
      }
    }
    if (valid &&
        is_billboard_vertex_shader(hash_bytes(cursor, total_size))) {
      return true;
    }
    cursor += 4;
  }
  return false;
}

std::uint64_t mix_u64(std::uint64_t hash, std::uint64_t value) {
  constexpr std::uint64_t prime = 1099511628211ULL;
  for (unsigned shift = 0; shift < 64; shift += 8) {
    hash ^= (value >> shift) & 0xffU;
    hash *= prime;
  }
  return hash;
}

void add_descriptor_range(RootParameterMetadata& parameter,
                          D3D12_DESCRIPTOR_RANGE_TYPE type,
                          UINT descriptor_count, UINT shader_register,
                          UINT register_space, UINT offset, UINT flags,
                          UINT& append_offset) {
  const auto resolved_offset =
      offset == D3D12_DESCRIPTOR_RANGE_OFFSET_APPEND ? append_offset : offset;
  append_offset = resolved_offset + descriptor_count;
  parameter.descriptor_table_span =
      (std::max)(parameter.descriptor_table_span, append_offset);
  switch (type) {
    case D3D12_DESCRIPTOR_RANGE_TYPE_CBV:
      parameter.cbv_count += descriptor_count;
      if (register_space == 0 && shader_register < 64) {
        const auto bounded_count =
            std::min<UINT>(descriptor_count, 64U - shader_register);
        for (UINT index = 0; index < bounded_count; ++index) {
          parameter.cbv_register_mask |=
              1ULL << static_cast<unsigned>(shader_register + index);
          parameter.cbv_descriptor_offsets[shader_register + index] =
              resolved_offset + index;
        }
      }
      if (register_space == 0 && shader_register <= 2 &&
          descriptor_count > 2 - shader_register) {
        parameter.contains_cbv_b2 = true;
      }
      break;
    case D3D12_DESCRIPTOR_RANGE_TYPE_SRV:
      parameter.srv_count += descriptor_count;
      break;
    case D3D12_DESCRIPTOR_RANGE_TYPE_UAV:
      parameter.uav_count += descriptor_count;
      break;
    case D3D12_DESCRIPTOR_RANGE_TYPE_SAMPLER:
      parameter.sampler_count += descriptor_count;
      break;
    default:
      break;
  }
  parameter.layout_hash = mix_u64(parameter.layout_hash, type);
  parameter.layout_hash = mix_u64(parameter.layout_hash, descriptor_count);
  parameter.layout_hash = mix_u64(parameter.layout_hash, shader_register);
  parameter.layout_hash = mix_u64(parameter.layout_hash, register_space);
  parameter.layout_hash = mix_u64(parameter.layout_hash, offset);
  parameter.layout_hash = mix_u64(parameter.layout_hash, flags);
}

RootSignatureMetadata inspect_root_signature(const void* data,
                                             std::size_t size) {
  RootSignatureMetadata metadata{};
  ComPtr<ID3D12VersionedRootSignatureDeserializer> deserializer;
  if (!data || size == 0 ||
      FAILED(D3D12CreateVersionedRootSignatureDeserializer(
          data, size, IID_PPV_ARGS(&deserializer)))) {
    return metadata;
  }
  const auto* description = deserializer->GetUnconvertedRootSignatureDesc();
  if (!description) {
    return metadata;
  }

  if (description->Version == D3D_ROOT_SIGNATURE_VERSION_1_0) {
    const auto& root = description->Desc_1_0;
    metadata.parameter_count =
        (std::min)(root.NumParameters, static_cast<UINT>(kRootSlotCount));
    metadata.flags = root.Flags;
    for (UINT i = 0; i < metadata.parameter_count; ++i) {
      const auto& source = root.pParameters[i];
      auto& target = metadata.parameters[i];
      target.type = source.ParameterType;
      target.visibility = source.ShaderVisibility;
      target.layout_hash = mix_u64(target.layout_hash, source.ParameterType);
      target.layout_hash = mix_u64(target.layout_hash, source.ShaderVisibility);
      if (source.ParameterType == D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE) {
        UINT append_offset{};
        for (UINT range = 0; range < source.DescriptorTable.NumDescriptorRanges;
             ++range) {
          const auto& descriptor =
              source.DescriptorTable.pDescriptorRanges[range];
          add_descriptor_range(target, descriptor.RangeType,
                               descriptor.NumDescriptors,
                               descriptor.BaseShaderRegister,
                               descriptor.RegisterSpace,
                               descriptor.OffsetInDescriptorsFromTableStart, 0,
                               append_offset);
        }
      } else if (source.ParameterType ==
                 D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS) {
        target.shader_register = source.Constants.ShaderRegister;
        target.register_space = source.Constants.RegisterSpace;
        target.layout_hash = mix_u64(target.layout_hash,
                                     source.Constants.Num32BitValues);
        target.layout_hash = mix_u64(target.layout_hash,
                                     source.Constants.ShaderRegister);
        target.layout_hash = mix_u64(target.layout_hash,
                                     source.Constants.RegisterSpace);
      } else {
        target.shader_register = source.Descriptor.ShaderRegister;
        target.register_space = source.Descriptor.RegisterSpace;
        target.layout_hash = mix_u64(target.layout_hash,
                                     source.Descriptor.ShaderRegister);
        target.layout_hash = mix_u64(target.layout_hash,
                                     source.Descriptor.RegisterSpace);
      }
    }
  } else if (description->Version == D3D_ROOT_SIGNATURE_VERSION_1_1) {
    const auto& root = description->Desc_1_1;
    metadata.parameter_count =
        (std::min)(root.NumParameters, static_cast<UINT>(kRootSlotCount));
    metadata.flags = root.Flags;
    for (UINT i = 0; i < metadata.parameter_count; ++i) {
      const auto& source = root.pParameters[i];
      auto& target = metadata.parameters[i];
      target.type = source.ParameterType;
      target.visibility = source.ShaderVisibility;
      target.layout_hash = mix_u64(target.layout_hash, source.ParameterType);
      target.layout_hash = mix_u64(target.layout_hash, source.ShaderVisibility);
      if (source.ParameterType == D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE) {
        UINT append_offset{};
        for (UINT range = 0; range < source.DescriptorTable.NumDescriptorRanges;
             ++range) {
          const auto& descriptor =
              source.DescriptorTable.pDescriptorRanges[range];
          add_descriptor_range(
              target, descriptor.RangeType, descriptor.NumDescriptors,
              descriptor.BaseShaderRegister, descriptor.RegisterSpace,
              descriptor.OffsetInDescriptorsFromTableStart, descriptor.Flags,
              append_offset);
        }
      } else if (source.ParameterType ==
                 D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS) {
        target.shader_register = source.Constants.ShaderRegister;
        target.register_space = source.Constants.RegisterSpace;
        target.layout_hash = mix_u64(target.layout_hash,
                                     source.Constants.Num32BitValues);
        target.layout_hash = mix_u64(target.layout_hash,
                                     source.Constants.ShaderRegister);
        target.layout_hash = mix_u64(target.layout_hash,
                                     source.Constants.RegisterSpace);
      } else {
        target.shader_register = source.Descriptor.ShaderRegister;
        target.register_space = source.Descriptor.RegisterSpace;
        target.layout_hash = mix_u64(target.layout_hash,
                                     source.Descriptor.ShaderRegister);
        target.layout_hash = mix_u64(target.layout_hash,
                                     source.Descriptor.RegisterSpace);
        target.layout_hash = mix_u64(target.layout_hash,
                                     source.Descriptor.Flags);
      }
    }
  }
  return metadata;
}

std::uint64_t descriptor_hash(const DescriptorInfo& descriptor,
                              bool include_resource) {
  auto hash = 1469598103934665603ULL;
  hash = mix_u64(hash, static_cast<unsigned char>(descriptor.kind));
  if (include_resource) {
    hash = mix_u64(hash, descriptor.resource);
    hash = mix_u64(hash, descriptor.gpu_address);
  }
  hash = mix_u64(hash, descriptor.dimension);
  hash = mix_u64(hash, descriptor.width);
  hash = mix_u64(hash, descriptor.height);
  hash = mix_u64(hash, descriptor.depth_or_array_size);
  hash = mix_u64(hash, descriptor.mip_levels);
  hash = mix_u64(hash, descriptor.format);
  hash = mix_u64(hash, descriptor.first_element);
  hash = mix_u64(hash, descriptor.element_count);
  hash = mix_u64(hash, descriptor.structure_stride);
  return hash;
}

TableProvenance resolve_table_provenance(std::uintptr_t signature,
                                         UINT root_index,
                                         std::uint64_t gpu_handle) {
  TableProvenance provenance{};
  if (gpu_handle == 0) {
    return provenance;
  }

  std::uint64_t expected_count = provenance.descriptors.size();
  {
    std::scoped_lock lock(root_signature_mutex);
    const auto found = root_signature_metadata.find(signature);
    if (found != root_signature_metadata.end() &&
        root_index < found->second.parameter_count) {
      const auto& parameter = found->second.parameters[root_index];
      expected_count = parameter.cbv_count + parameter.srv_count +
                       parameter.uav_count + parameter.sampler_count;
    }
  }
  expected_count = (std::min)(
      expected_count,
      static_cast<std::uint64_t>(provenance.descriptors.size()));
  if (expected_count == 0) {
    return provenance;
  }

  std::scoped_lock lock(descriptor_mutex);
  for (const auto& [_, heap] : descriptor_heaps) {
    if (heap.gpu_start == 0 || heap.increment == 0 ||
        gpu_handle < heap.gpu_start) {
      continue;
    }
    const auto byte_offset = gpu_handle - heap.gpu_start;
    const auto heap_size = static_cast<std::uint64_t>(heap.descriptor_count) *
                           heap.increment;
    if (byte_offset >= heap_size || byte_offset % heap.increment != 0) {
      continue;
    }
    const auto first_index = byte_offset / heap.increment;
    for (std::uint64_t i = 0;
         i < expected_count && first_index + i < heap.descriptor_count; ++i) {
      const auto cpu_handle = heap.cpu_start +
                              (first_index + i) * heap.increment;
      const auto descriptor = descriptor_metadata.find(cpu_handle);
      if (descriptor == descriptor_metadata.end()) {
        continue;
      }
      provenance.descriptors[static_cast<std::size_t>(i)] =
          descriptor->second;
      provenance.resource_hash =
          mix_u64(provenance.resource_hash,
                  descriptor_hash(descriptor->second, true));
      provenance.layout_hash =
          mix_u64(provenance.layout_hash,
                  descriptor_hash(descriptor->second, false));
      ++provenance.descriptor_count;
    }
    break;
  }
  return provenance;
}

bool is_vendor_menu_widget_shader_pair(const PsoMetadata& metadata) {
  return metadata.vertex_shader == kVendorMenuWidgetShaderPair.vertex_shader &&
         metadata.pixel_shader == kVendorMenuWidgetShaderPair.pixel_shader;
}


std::uint64_t graphics_binding_state_hash(const CommandTrace& trace) {
  auto hash = 1469598103934665603ULL;
  for (std::size_t slot = 0; slot < kRootSlotCount; ++slot) {
    hash = mix_u64(hash, slot);
    hash = mix_u64(hash, trace.graphics_tables[slot]);
    hash = mix_u64(hash, trace.graphics_constants[slot]);
    hash = mix_u64(hash, trace.graphics_cbvs[slot]);
    hash = mix_u64(hash, trace.graphics_srvs[slot]);
    hash = mix_u64(hash, trace.graphics_uavs[slot]);
  }
  return hash;
}

std::uint64_t root_array_hash(
    const std::array<std::uint64_t, kRootSlotCount>& values) {
  auto hash = 1469598103934665603ULL;
  for (std::size_t slot = 0; slot < kRootSlotCount; ++slot) {
    hash = mix_u64(hash, slot);
    hash = mix_u64(hash, values[slot]);
  }
  return hash;
}

void sample_graphics_bindings(ID3D12GraphicsCommandList* commands) {
  auto& trace = command_traces[commands];
  auto& pass = current_pass(commands);
  pass.binding_hash =
      mix_u64(pass.binding_hash, graphics_binding_state_hash(trace));
  pass.table_hash = mix_u64(pass.table_hash,
                            root_array_hash(trace.graphics_tables));
  pass.constant_hash = mix_u64(pass.constant_hash,
                               root_array_hash(trace.graphics_constants));
  pass.cbv_hash = mix_u64(pass.cbv_hash,
                          root_array_hash(trace.graphics_cbvs));
  pass.srv_hash = mix_u64(pass.srv_hash,
                          root_array_hash(trace.graphics_srvs));
  pass.uav_hash = mix_u64(pass.uav_hash,
                          root_array_hash(trace.graphics_uavs));
  for (std::size_t slot = 0; slot < pass.table_slot_hashes.size(); ++slot) {
    pass.table_slot_hashes[slot] =
        mix_u64(pass.table_slot_hashes[slot], trace.graphics_tables[slot]);
    pass.cbv_slot_hashes[slot] =
        mix_u64(pass.cbv_slot_hashes[slot], trace.graphics_cbvs[slot]);
    const auto provenance = resolve_table_provenance(
        trace.root_signature, static_cast<UINT>(slot),
        trace.graphics_tables[slot]);
    pass.table_resource_hashes[slot] = mix_u64(
        pass.table_resource_hashes[slot], provenance.resource_hash);
    pass.table_layout_hashes[slot] = mix_u64(
        pass.table_layout_hashes[slot], provenance.layout_hash);
    if (slot == 4 && provenance.descriptor_count > 0 &&
        !pass.table4_descriptors_captured) {
      pass.table4_descriptors = provenance.descriptors;
      pass.table4_descriptors_captured = true;
    }
    if (slot == 7 && provenance.descriptor_count > 0 &&
        !pass.table7_descriptors_captured) {
      pass.table7_descriptors = provenance.descriptors;
      pass.table7_descriptors_captured = true;
    }
  }
  ++pass.binding_samples;
}

std::uint64_t draw_identity_hash(const CommandTrace& trace,
                                 std::uint64_t draw_kind,
                                 std::uint64_t argument0,
                                 std::uint64_t argument1,
                                 std::uint64_t argument2,
                                 std::uint64_t argument3,
                                 std::uint64_t argument4) {
  auto hash = 1469598103934665603ULL;
  hash = mix_u64(hash, trace.pso);
  hash = mix_u64(hash, trace.root_signature);
  hash = mix_u64(hash, draw_kind);
  hash = mix_u64(hash, argument0);
  hash = mix_u64(hash, argument1);
  hash = mix_u64(hash, argument2);
  hash = mix_u64(hash, argument3);
  hash = mix_u64(hash, argument4);
  hash = mix_u64(hash, trace.primitive_topology);
  hash = mix_u64(hash, trace.index_buffer.BufferLocation);
  hash = mix_u64(hash, trace.index_buffer.SizeInBytes);
  hash = mix_u64(hash, trace.index_buffer.Format);
  for (std::size_t slot = 0; slot < trace.vertex_buffers.size(); ++slot) {
    const auto& buffer = trace.vertex_buffers[slot];
    hash = mix_u64(hash, slot);
    hash = mix_u64(hash, buffer.BufferLocation);
    hash = mix_u64(hash, buffer.SizeInBytes);
    hash = mix_u64(hash, buffer.StrideInBytes);
  }
  return hash;
}

void observe_table4_draw(ID3D12GraphicsCommandList* commands,
                         std::uint64_t draw_kind,
                         std::uint64_t argument0,
                         std::uint64_t argument1,
                         std::uint64_t argument2,
                         std::uint64_t argument3,
                         std::uint64_t argument4) {
  auto& trace = command_traces[commands];
  if (trace.viewport_y != 0 || trace.viewport_width != 960 ||
      trace.viewport_height != 1080 || trace.graphics_tables[4] == 0) {
    return;
  }
  const auto key = draw_identity_hash(trace, draw_kind, argument0, argument1,
                                      argument2, argument3, argument4);
  if (trace.eye == 0 && trace.viewport_x == 0) {
    auto [candidate, inserted] = frame_eye0_table4_draws.emplace(
        key, AliasCandidate{trace.graphics_tables[4], false});
    if (!inserted && candidate->second.table != trace.graphics_tables[4] &&
        !candidate->second.ambiguous) {
      candidate->second.ambiguous = true;
      table4_exact_ambiguous_count.fetch_add(1, std::memory_order_relaxed);
    }
    return;
  }
  if (trace.eye != 1 || trace.viewport_x != 960) {
    return;
  }
  const auto found = frame_eye0_table4_draws.find(key);
  if (found == frame_eye0_table4_draws.end() || found->second.ambiguous ||
      found->second.table == 0) {
    return;
  }
  table4_exact_match_count.fetch_add(1, std::memory_order_relaxed);
  if (!table4_alias_eye0_to_eye1.load(std::memory_order_relaxed)) {
    return;
  }
  D3D12_GPU_DESCRIPTOR_HANDLE alias{};
  alias.ptr = found->second.table;
  original_set_graphics_root_descriptor_table(commands, 4, alias);
  trace.graphics_tables[4] = alias.ptr;
  table4_alias_count.fetch_add(1, std::memory_order_relaxed);
}

void log_focused_draw(ID3D12GraphicsCommandList* commands,
                      std::uint64_t draw_kind,
                      std::uint64_t argument0,
                      std::uint64_t argument1,
                      std::uint64_t argument2,
                      std::uint64_t argument3,
                      std::uint64_t argument4) {
  const auto phase = focused_trace_phase.load(std::memory_order_relaxed);
  if (phase == 0) {
    return;
  }
  const auto& trace = command_traces[commands];
  auto coarse = 1469598103934665603ULL;
  coarse = mix_u64(coarse, trace.pso);
  coarse = mix_u64(coarse, trace.root_signature);
  coarse = mix_u64(coarse, draw_kind);
  coarse = mix_u64(coarse, argument0);
  coarse = mix_u64(coarse, argument1);
  coarse = mix_u64(coarse, argument2);
  coarse = mix_u64(coarse, argument3);
  coarse = mix_u64(coarse, argument4);
  coarse = mix_u64(coarse, trace.primitive_topology);
  const auto exact = draw_identity_hash(trace, draw_kind, argument0, argument1,
                                        argument2, argument3, argument4);
  const auto table4 = resolve_table_provenance(
      trace.root_signature, 4, trace.graphics_tables[4]);
  const auto table7 = resolve_table_provenance(
      trace.root_signature, 7, trace.graphics_tables[7]);
  const auto& s4a = table4.descriptors[0];
  const auto& s4b = table4.descriptors[1];
  const auto& vb0 = trace.vertex_buffers[0];
  const auto& vb1 = trace.vertex_buffers[1];
  PsoMetadata metadata{};
  {
    std::scoped_lock lock(pso_mutex);
    const auto found = pso_metadata.find(trace.pso);
    if (found != pso_metadata.end()) {
      metadata = found->second;
    }
  }
  auto target_is_swapchain = false;
  {
    const auto target = descriptor_snapshot(trace.render_target);
    auto* resource = reinterpret_cast<ID3D12Resource*>(target.resource);
    std::scoped_lock lock(boundary_capture_mutex);
    target_is_swapchain = resource &&
                          swapchain_back_buffers.find(resource) !=
                              swapchain_back_buffers.end();
  }
  write_focused_log(
      "phase=%d\tframe=%llu\tCL=%p\tgen=%llu\tDRAW\teye=%d\tvpx=%u\tvpy=%u\tvpw=%u\tvph=%u\tsc=%ld,%ld,%ld,%ld\tkind=%llu\ta=%llu,%llu,%llu,%llu,%llu\tcoarse=%llu\texact=%llu\tpso=%p\tvs=%llu\tps=%llu\tblend=%u\tdepth=%u\tsig=%p\ttopo=%u\trtv=%llu\tswapchain=%u\tdsv=%llu\tib=%llu,%u,%u\tvb0=%llu,%u,%u\tvb1=%llu,%u,%u\tbind=%llu\ttables=%llu\tconstants=%llu\tcbvs=%llu\tt4=%llu\tt7=%llu\tcbv1=%llu\ts4=%u,%llu,%llu,%u,%p,%llu,%u,%u,%p\ts7=%u,%llu,%llu\r\n",
      phase, present_count.load(std::memory_order_relaxed), commands,
      static_cast<unsigned long long>(trace.recording_generation), trace.eye,
      trace.viewport_x, trace.viewport_y, trace.viewport_width,
      trace.viewport_height, trace.scissor.left, trace.scissor.top,
      trace.scissor.right, trace.scissor.bottom, draw_kind, argument0,
      argument1, argument2, argument3, argument4, coarse, exact,
      reinterpret_cast<void*>(trace.pso),
      static_cast<unsigned long long>(metadata.vertex_shader),
      static_cast<unsigned long long>(metadata.pixel_shader),
      metadata.blend_enabled ? 1U : 0U, metadata.depth_enabled ? 1U : 0U,
      reinterpret_cast<void*>(trace.root_signature),
      static_cast<UINT>(trace.primitive_topology), trace.render_target,
      target_is_swapchain ? 1U : 0U, trace.depth_target,
      trace.index_buffer.BufferLocation,
      trace.index_buffer.SizeInBytes, static_cast<UINT>(trace.index_buffer.Format),
      vb0.BufferLocation, vb0.SizeInBytes, vb0.StrideInBytes,
      vb1.BufferLocation, vb1.SizeInBytes, vb1.StrideInBytes,
      graphics_binding_state_hash(trace), root_array_hash(trace.graphics_tables),
      root_array_hash(trace.graphics_constants), root_array_hash(trace.graphics_cbvs),
      trace.graphics_tables[4], trace.graphics_tables[7],
      trace.graphics_cbvs[1], table4.descriptor_count,
      table4.resource_hash, table4.layout_hash, s4a.structure_stride,
      reinterpret_cast<void*>(s4a.resource), s4a.first_element,
      s4a.element_count, s4b.structure_stride,
      reinterpret_cast<void*>(s4b.resource), table7.descriptor_count,
      table7.resource_hash, table7.layout_hash);
}

UINT apply_candidate_batch_probe(ID3D12GraphicsCommandList* commands,
                                 UINT index_count, UINT instance_count,
                                 UINT start_index, INT base_vertex,
                                 UINT start_instance) {
  constexpr std::uint64_t candidate_cached_blob = 6427276088126068298ULL;
  if ((!candidate_instance_clamp_enabled.load(std::memory_order_relaxed) &&
       !candidate_table4_alias_enabled.load(std::memory_order_relaxed)) ||
      index_count != 6 || start_index != 0 || base_vertex != 0 ||
      start_instance != 0) {
    return instance_count;
  }
  const auto& trace = command_traces[commands];
  if (trace.viewport_y != 0 || trace.viewport_width != 960 ||
      trace.viewport_height != 1080 || trace.graphics_tables[4] == 0) {
    return instance_count;
  }
  bool candidate{};
  {
    std::scoped_lock lock(pso_mutex);
    const auto found = pso_metadata.find(trace.pso);
    candidate = found != pso_metadata.end() &&
                found->second.cached_blob == candidate_cached_blob;
  }
  if (!candidate) {
    return instance_count;
  }
  if (trace.eye == 0 && trace.viewport_x == 0) {
    if (candidate_frame_eye0_table4.table == 0) {
      candidate_frame_eye0_table4.table = trace.graphics_tables[4];
      candidate_frame_eye0_instance_count = instance_count;
    } else if ((candidate_frame_eye0_table4.table != trace.graphics_tables[4] ||
                candidate_frame_eye0_instance_count != instance_count) &&
               !candidate_frame_eye0_table4.ambiguous) {
      candidate_frame_eye0_table4.ambiguous = true;
      candidate_table4_ambiguous_count.fetch_add(1, std::memory_order_relaxed);
    }
    return instance_count;
  }
  if (trace.eye != 1 || trace.viewport_x != 960) {
    return instance_count;
  }
  if (candidate_table4_alias_enabled.load(std::memory_order_relaxed) &&
      candidate_frame_eye0_table4.table != 0 &&
      !candidate_frame_eye0_table4.ambiguous) {
    const auto left = resolve_table_provenance(
        trace.root_signature, 4, candidate_frame_eye0_table4.table);
    const auto right = resolve_table_provenance(
        trace.root_signature, 4, trace.graphics_tables[4]);
    if (left.descriptor_count == right.descriptor_count &&
        left.layout_hash == right.layout_hash) {
      candidate_table4_match_count.fetch_add(1, std::memory_order_relaxed);
      D3D12_GPU_DESCRIPTOR_HANDLE alias{};
      alias.ptr = candidate_frame_eye0_table4.table;
      original_set_graphics_root_descriptor_table(commands, 4, alias);
      command_traces[commands].graphics_tables[4] = alias.ptr;
      candidate_table4_alias_count.fetch_add(1, std::memory_order_relaxed);
    }
  }
  if (candidate_instance_clamp_enabled.load(std::memory_order_relaxed) &&
      candidate_frame_eye0_instance_count != 0 &&
      instance_count != candidate_frame_eye0_instance_count) {
    candidate_instance_clamp_count.fetch_add(1, std::memory_order_relaxed);
    return candidate_frame_eye0_instance_count;
  }
  return instance_count;
}

std::uint64_t hash_bytecode(const D3D12_SHADER_BYTECODE& bytecode) {
  return hash_bytes(bytecode.pShaderBytecode, bytecode.BytecodeLength);
}

ComPtr<ID3D12ShaderReflection> reflect_shader(
    const D3D12_SHADER_BYTECODE& bytecode) {
  ComPtr<ID3D12ShaderReflection> reflection;
  if (!bytecode.pShaderBytecode || bytecode.BytecodeLength == 0 ||
      !InitOnceExecuteOnce(&dxc_reflection_once, initialize_dxc_reflection,
                           nullptr, nullptr)) {
    return reflection;
  }
  ComPtr<IDxcLibrary> library;
  ComPtr<IDxcContainerReflection> container;
  ComPtr<IDxcBlobEncoding> blob;
  UINT32 part_index{};
  if (FAILED(dxc_create_instance(CLSID_DxcLibrary,
                                 IID_PPV_ARGS(&library))) ||
      FAILED(dxc_create_instance(CLSID_DxcContainerReflection,
                                 IID_PPV_ARGS(&container))) ||
      FAILED(library->CreateBlobWithEncodingFromPinned(
          const_cast<void*>(bytecode.pShaderBytecode),
          static_cast<UINT32>(bytecode.BytecodeLength), CP_ACP, &blob)) ||
      FAILED(container->Load(blob.Get())) ||
      FAILED(container->FindFirstPartKind(DXC_PART_DXIL, &part_index)) ||
      FAILED(container->GetPartReflection(part_index,
                                          IID_PPV_ARGS(&reflection)))) {
    reflection.Reset();
  }
  return reflection;
}

bool compatible_signature_parameter(
    const D3D12_SIGNATURE_PARAMETER_DESC& left,
    const D3D12_SIGNATURE_PARAMETER_DESC& right) {
  return left.SemanticName && right.SemanticName &&
         _stricmp(left.SemanticName, right.SemanticName) == 0 &&
         left.SemanticIndex == right.SemanticIndex &&
         left.Register == right.Register &&
         left.SystemValueType == right.SystemValueType &&
         left.ComponentType == right.ComponentType && left.Mask == right.Mask &&
         left.ReadWriteMask == right.ReadWriteMask &&
         left.Stream == right.Stream &&
         left.MinPrecision == right.MinPrecision;
}

bool compatible_output_signature_parameter(
    const D3D12_SIGNATURE_PARAMETER_DESC& left,
    const D3D12_SIGNATURE_PARAMETER_DESC& right) {
  // Inter-stage linkage is the register/component ABI. Reconstructed HLSL
  // cannot express Stingray's packing of differently named varyings into the
  // same register, so SPIRV-Cross gives the packed components a shared
  // temporary semantic. Keep system-value identity exact and otherwise accept
  // only an exact register, component mask/type, stream and precision match.
  const auto system_semantic_matches =
      left.SystemValueType == D3D_NAME_UNDEFINED ||
      (left.SemanticName && right.SemanticName &&
       _stricmp(left.SemanticName, right.SemanticName) == 0 &&
       left.SemanticIndex == right.SemanticIndex);
  return system_semantic_matches && left.Register == right.Register &&
         left.SystemValueType == right.SystemValueType &&
         left.ComponentType == right.ComponentType && left.Mask == right.Mask &&
         left.ReadWriteMask == right.ReadWriteMask &&
         left.Stream == right.Stream &&
         left.MinPrecision == right.MinPrecision;
}

bool compatible_pixel_input_signature_parameter(
    const D3D12_SIGNATURE_PARAMETER_DESC& left,
    const D3D12_SIGNATURE_PARAMETER_DESC& right) {
  // ReadWriteMask describes which interpolants this particular shader body
  // consumes; it is not part of pixel-stage linkage. A constant-color
  // ownership probe deliberately consumes none of them.
  return left.SemanticName && right.SemanticName &&
         _stricmp(left.SemanticName, right.SemanticName) == 0 &&
         left.SemanticIndex == right.SemanticIndex &&
         left.Register == right.Register &&
         left.SystemValueType == right.SystemValueType &&
         left.ComponentType == right.ComponentType && left.Mask == right.Mask &&
         left.Stream == right.Stream &&
         left.MinPrecision == right.MinPrecision;
}

bool compatible_resource_binding(const D3D12_SHADER_INPUT_BIND_DESC& left,
                                 const D3D12_SHADER_INPUT_BIND_DESC& right) {
  // Resource names are reflection/debug labels. Root-signature compatibility
  // is determined by the type, register range, space and resource shape.
  return left.Type == right.Type && left.BindPoint == right.BindPoint &&
         left.BindCount == right.BindCount &&
         left.ReturnType == right.ReturnType &&
         left.Dimension == right.Dimension &&
         left.NumSamples == right.NumSamples && left.Space == right.Space;
}

bool compatible_shader_interfaces(const D3D12_SHADER_BYTECODE& original,
                                  const D3D12_SHADER_BYTECODE& replacement) {
  const auto left = reflect_shader(original);
  const auto right = reflect_shader(replacement);
  if (!left || !right) {
    return false;
  }
  D3D12_SHADER_DESC left_desc{};
  D3D12_SHADER_DESC right_desc{};
  if (FAILED(left->GetDesc(&left_desc)) || FAILED(right->GetDesc(&right_desc)) ||
      D3D12_SHVER_GET_TYPE(left_desc.Version) !=
          D3D12_SHVER_GET_TYPE(right_desc.Version) ||
      left_desc.InputParameters != right_desc.InputParameters ||
      left_desc.OutputParameters != right_desc.OutputParameters ||
      left_desc.PatchConstantParameters != right_desc.PatchConstantParameters ||
      left_desc.BoundResources != right_desc.BoundResources ||
      left_desc.ConstantBuffers != right_desc.ConstantBuffers) {
    return false;
  }
  for (UINT index = 0; index < left_desc.InputParameters; ++index) {
    D3D12_SIGNATURE_PARAMETER_DESC a{};
    D3D12_SIGNATURE_PARAMETER_DESC b{};
    if (FAILED(left->GetInputParameterDesc(index, &a)) ||
        FAILED(right->GetInputParameterDesc(index, &b)) ||
        !compatible_signature_parameter(a, b)) {
      return false;
    }
  }
  for (UINT index = 0; index < left_desc.OutputParameters; ++index) {
    D3D12_SIGNATURE_PARAMETER_DESC a{};
    if (FAILED(left->GetOutputParameterDesc(index, &a))) {
      return false;
    }
    bool matched{};
    for (UINT candidate = 0; candidate < right_desc.OutputParameters;
         ++candidate) {
      D3D12_SIGNATURE_PARAMETER_DESC b{};
      if (SUCCEEDED(right->GetOutputParameterDesc(candidate, &b)) &&
          compatible_output_signature_parameter(a, b)) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      return false;
    }
  }
  for (UINT index = 0; index < left_desc.BoundResources; ++index) {
    D3D12_SHADER_INPUT_BIND_DESC a{};
    if (FAILED(left->GetResourceBindingDesc(index, &a))) {
      return false;
    }
    bool matched{};
    for (UINT candidate = 0; candidate < right_desc.BoundResources;
         ++candidate) {
      D3D12_SHADER_INPUT_BIND_DESC b{};
      if (SUCCEEDED(right->GetResourceBindingDesc(candidate, &b)) &&
          compatible_resource_binding(a, b)) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      return false;
    }
  }
  for (UINT index = 0; index < left_desc.ConstantBuffers; ++index) {
    auto* left_buffer = left->GetConstantBufferByIndex(index);
    D3D12_SHADER_BUFFER_DESC left_buffer_desc{};
    if (!left_buffer || FAILED(left_buffer->GetDesc(&left_buffer_desc))) {
      return false;
    }
    bool matched{};
    for (UINT candidate = 0; candidate < right_desc.ConstantBuffers;
         ++candidate) {
      auto* right_buffer = right->GetConstantBufferByIndex(candidate);
      D3D12_SHADER_BUFFER_DESC right_buffer_desc{};
      // DXC rounds a reconstructed final partial register up to 16 bytes,
      // while the original Stingray DXIL reflection reports its exact used
      // byte count. D3D12 CBVs are 256-byte aligned, so this padding does not
      // alter the binding or permit the replacement to address another CBV.
      // Accept only that single-register reflection difference.
      const auto aligned_left_size =
          (left_buffer_desc.Size + 15U) & ~15U;
      if (right_buffer && SUCCEEDED(right_buffer->GetDesc(&right_buffer_desc)) &&
          (left_buffer_desc.Size == right_buffer_desc.Size ||
           aligned_left_size == right_buffer_desc.Size) &&
          left_buffer_desc.Type == right_buffer_desc.Type) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      return false;
    }
  }
  return true;
}

bool compatible_pixel_shader_signatures(
    const D3D12_SHADER_BYTECODE& original,
    const D3D12_SHADER_BYTECODE& replacement) {
  const auto left = reflect_shader(original);
  const auto right = reflect_shader(replacement);
  if (!left || !right) {
    return false;
  }
  D3D12_SHADER_DESC left_desc{};
  D3D12_SHADER_DESC right_desc{};
  if (FAILED(left->GetDesc(&left_desc)) || FAILED(right->GetDesc(&right_desc)) ||
      D3D12_SHVER_GET_TYPE(left_desc.Version) != D3D12_SHVER_PIXEL_SHADER ||
      D3D12_SHVER_GET_TYPE(right_desc.Version) != D3D12_SHVER_PIXEL_SHADER ||
      left_desc.InputParameters != right_desc.InputParameters ||
      left_desc.OutputParameters != right_desc.OutputParameters) {
    return false;
  }
  for (UINT index = 0; index < left_desc.InputParameters; ++index) {
    D3D12_SIGNATURE_PARAMETER_DESC a{};
    D3D12_SIGNATURE_PARAMETER_DESC b{};
    if (FAILED(left->GetInputParameterDesc(index, &a)) ||
        FAILED(right->GetInputParameterDesc(index, &b)) ||
        !compatible_pixel_input_signature_parameter(a, b)) {
      return false;
    }
  }
  for (UINT index = 0; index < left_desc.OutputParameters; ++index) {
    D3D12_SIGNATURE_PARAMETER_DESC a{};
    D3D12_SIGNATURE_PARAMETER_DESC b{};
    if (FAILED(left->GetOutputParameterDesc(index, &a)) ||
        FAILED(right->GetOutputParameterDesc(index, &b)) ||
        !compatible_signature_parameter(a, b)) {
      return false;
    }
  }
  return true;
}

std::optional<UINT> reflect_billboard_register(
    const D3D12_SHADER_BYTECODE& bytecode) {
  if (!bytecode.pShaderBytecode || bytecode.BytecodeLength == 0) {
    return std::nullopt;
  }
  static std::mutex reflection_cache_mutex;
  static std::unordered_map<std::uint64_t, UINT> reflection_cache;
  const auto shader_hash = hash_bytecode(bytecode);
  std::scoped_lock cache_lock(reflection_cache_mutex);
  const auto cached = reflection_cache.find(shader_hash);
  if (cached != reflection_cache.end()) {
    return cached->second == UINT_MAX
               ? std::nullopt
               : std::optional<UINT>(cached->second);
  }
  if (!InitOnceExecuteOnce(&dxc_reflection_once, initialize_dxc_reflection,
                           nullptr, nullptr)) {
    reflection_cache.emplace(shader_hash, UINT_MAX);
    return std::nullopt;
  }
  ComPtr<IDxcLibrary> library;
  ComPtr<IDxcContainerReflection> container;
  if (FAILED(dxc_create_instance(CLSID_DxcLibrary,
                                 IID_PPV_ARGS(&library))) ||
      FAILED(dxc_create_instance(CLSID_DxcContainerReflection,
                                 IID_PPV_ARGS(&container)))) {
    reflection_cache.emplace(shader_hash, UINT_MAX);
    return std::nullopt;
  }
  ComPtr<IDxcBlobEncoding> blob;
  if (FAILED(library->CreateBlobWithEncodingFromPinned(
          const_cast<void*>(bytecode.pShaderBytecode),
          static_cast<UINT32>(bytecode.BytecodeLength), CP_ACP, &blob)) ||
      FAILED(container->Load(blob.Get()))) {
    reflection_cache.emplace(shader_hash, UINT_MAX);
    return std::nullopt;
  }
  UINT32 part_index{};
  ComPtr<ID3D12ShaderReflection> reflection;
  if (FAILED(container->FindFirstPartKind(DXC_PART_DXIL, &part_index)) ||
      FAILED(container->GetPartReflection(part_index,
                                          IID_PPV_ARGS(&reflection)))) {
    reflection_cache.emplace(shader_hash, UINT_MAX);
    return std::nullopt;
  }
  D3D12_SHADER_INPUT_BIND_DESC binding{};
  if (FAILED(
          reflection->GetResourceBindingDescByName("c_billboard", &binding)) ||
      binding.Type != D3D_SIT_CBUFFER) {
    reflection_cache.emplace(shader_hash, UINT_MAX);
    return std::nullopt;
  }
  reflection_cache.emplace(shader_hash, binding.BindPoint);
  return binding.BindPoint;
}

void dump_vertex_shader_if_requested(
    const D3D12_SHADER_BYTECODE& bytecode,
    const D3D12_INPUT_LAYOUT_DESC* input_layout = nullptr) {
  if (!bytecode.pShaderBytecode || bytecode.BytecodeLength == 0) {
    return;
  }
  wchar_t enabled[2]{};
  const auto environment_enabled =
      GetEnvironmentVariableW(L"DARKTIDEVR_DUMP_VERTEX_SHADERS", enabled,
                              static_cast<DWORD>(std::size(enabled))) == 1 &&
      enabled[0] == L'1';
  if (!vertex_shader_dump_requested.load(std::memory_order_relaxed) &&
      !environment_enabled) {
    return;
  }

  const auto hash = hash_bytecode(bytecode);
  std::scoped_lock lock(vertex_shader_dump_mutex);
  if (!dumped_vertex_shaders.insert(hash).second) {
    return;
  }

  wchar_t temporary_path[MAX_PATH]{};
  if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
    return;
  }
  const std::wstring directory =
      std::wstring(temporary_path) + L"darktidevr-vertex-shaders";
  CreateDirectoryW(directory.c_str(), nullptr);

  wchar_t file_name[96]{};
  swprintf_s(file_name, L"\\vs-%016llx.bin",
             static_cast<unsigned long long>(hash));
  const auto shader_path = directory + file_name;
  const auto shader_file =
      CreateFileW(shader_path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                  CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (shader_file != INVALID_HANDLE_VALUE) {
    DWORD written{};
    WriteFile(shader_file, bytecode.pShaderBytecode,
              static_cast<DWORD>(bytecode.BytecodeLength), &written, nullptr);
    CloseHandle(shader_file);
  }

  std::string semantics;
  if (input_layout && input_layout->pInputElementDescs) {
    for (UINT i = 0; i < input_layout->NumElements; ++i) {
      const auto& element = input_layout->pInputElementDescs[i];
      if (!semantics.empty()) {
        semantics += ',';
      }
      semantics += element.SemanticName ? element.SemanticName : "?";
      semantics += std::to_string(element.SemanticIndex);
      semantics += ':';
      semantics += std::to_string(static_cast<unsigned>(element.Format));
      semantics += '@';
      semantics += std::to_string(element.InputSlot);
    }
  }
  const auto manifest_path = directory + L"\\manifest.tsv";
  const auto manifest =
      CreateFileW(manifest_path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                  nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (manifest != INVALID_HANDLE_VALUE) {
    char line[4096]{};
    const auto length = snprintf(
        line, sizeof(line), "%016llx\t%llu\t%s\r\n",
        static_cast<unsigned long long>(hash),
        static_cast<unsigned long long>(bytecode.BytecodeLength),
        semantics.c_str());
    if (length > 0) {
      DWORD written{};
      WriteFile(manifest, line,
                static_cast<DWORD>((std::min)(length,
                                              static_cast<int>(sizeof(line)))),
                &written, nullptr);
    }
    CloseHandle(manifest);
  }
}

void dump_cluster_compute_shader_if_target(
    const D3D12_SHADER_BYTECODE& bytecode) {
  if (cluster_trace_log == INVALID_HANDLE_VALUE || !bytecode.pShaderBytecode ||
      bytecode.BytecodeLength == 0) {
    return;
  }
  // Measured in the hub trace: the grid shader dispatches twice per stereo
  // frame at ceil(30/4) x ceil(17/4) x (64/4), and the list writer is the
  // immediately preceding dispatch in all eight bounded command-order
  // samples. Keep dumping scoped to those evidence-backed identities rather
  // than collecting every compute shader in the game.
  const auto hash = hash_bytecode(bytecode);
  if (hash != kClusterGridComputeShader &&
      hash != kClusterListWriterComputeShader) {
    return;
  }
  std::scoped_lock lock(vertex_shader_dump_mutex);
  if (!dumped_cluster_compute_shaders.insert(hash).second) {
    return;
  }
  wchar_t temporary_path[MAX_PATH]{};
  if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
    return;
  }
  const std::wstring directory =
      std::wstring(temporary_path) + L"darktidevr-cluster-shaders";
  CreateDirectoryW(directory.c_str(), nullptr);
  wchar_t file_name[96]{};
  swprintf_s(file_name, L"\\cs-%016llx.bin",
             static_cast<unsigned long long>(hash));
  const auto shader_file = CreateFileW(
      (directory + file_name).c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (shader_file == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written{};
  WriteFile(shader_file, bytecode.pShaderBytecode,
            static_cast<DWORD>(bytecode.BytecodeLength), &written, nullptr);
  CloseHandle(shader_file);
}

void dump_cluster_graphics_shaders_if_target(
    const D3D12_SHADER_BYTECODE& vertex_shader,
    const D3D12_SHADER_BYTECODE& pixel_shader) {
  if (cluster_trace_log == INVALID_HANDLE_VALUE ||
      hash_bytecode(vertex_shader) != kClusterLightRasterVertexShader ||
      hash_bytecode(pixel_shader) != kClusterLightRasterPixelShader) {
    return;
  }
  const auto pair_hash = mix_u64(kClusterLightRasterVertexShader,
                                 kClusterLightRasterPixelShader);
  std::scoped_lock lock(vertex_shader_dump_mutex);
  if (!dumped_cluster_graphics_shader_pairs.insert(pair_hash).second) {
    return;
  }
  wchar_t temporary_path[MAX_PATH]{};
  if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
    return;
  }
  const std::wstring directory =
      std::wstring(temporary_path) + L"darktidevr-cluster-shaders";
  CreateDirectoryW(directory.c_str(), nullptr);
  const auto write_shader = [&](const wchar_t* stage, std::uint64_t hash,
                                const D3D12_SHADER_BYTECODE& bytecode) {
    wchar_t file_name[96]{};
    swprintf_s(file_name, L"\\%s-%016llx.bin", stage,
               static_cast<unsigned long long>(hash));
    const auto file = CreateFileW(
        (directory + file_name).c_str(), GENERIC_WRITE, FILE_SHARE_READ,
        nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
      return;
    }
    DWORD written{};
    WriteFile(file, bytecode.pShaderBytecode,
              static_cast<DWORD>(bytecode.BytecodeLength), &written, nullptr);
    CloseHandle(file);
  };
  write_shader(L"vs", kClusterLightRasterVertexShader, vertex_shader);
  write_shader(L"ps", kClusterLightRasterPixelShader, pixel_shader);
}

void dump_billboard_pixel_shader(const D3D12_SHADER_BYTECODE& vertex_shader,
                                 const D3D12_SHADER_BYTECODE& pixel_shader) {
  if (!pixel_shader.pShaderBytecode || pixel_shader.BytecodeLength == 0) {
    return;
  }
  const auto hash = hash_bytecode(pixel_shader);
  const auto known_pixel_shader =
      std::find(kBillboardPixelShaderHashes.begin(),
                kBillboardPixelShaderHashes.end(), hash) !=
      kBillboardPixelShaderHashes.end();
  const auto vertex_shader_hash = hash_bytecode(vertex_shader);
  if (!is_billboard_vertex_shader(vertex_shader_hash) &&
      !reflect_billboard_register(vertex_shader).has_value() &&
      !known_pixel_shader) {
    return;
  }
  std::scoped_lock lock(vertex_shader_dump_mutex);
  if (!dumped_billboard_pixel_shaders.insert(hash).second) {
    return;
  }
  const auto module_directory = native_capture_directory();
  if (module_directory.empty()) {
    return;
  }
  const std::wstring directory =
      module_directory + L"billboard_pixel_shaders";
  CreateDirectoryW(directory.c_str(), nullptr);
  wchar_t file_name[96]{};
  swprintf_s(file_name, L"\\ps-%016llx.bin",
             static_cast<unsigned long long>(hash));
  const auto path = directory + file_name;
  const auto file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                                nullptr, CREATE_ALWAYS,
                                FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    DWORD written{};
    WriteFile(file, pixel_shader.pShaderBytecode,
              static_cast<DWORD>(pixel_shader.BytecodeLength), &written,
              nullptr);
    CloseHandle(file);
  }
}

void dump_blended_pixel_shader(const D3D12_SHADER_BYTECODE& pixel_shader) {
  if (!pixel_shader.pShaderBytecode || pixel_shader.BytecodeLength == 0) {
    return;
  }
  const auto hash = hash_bytecode(pixel_shader);
  std::scoped_lock lock(vertex_shader_dump_mutex);
  if (!dumped_blended_pixel_shaders.insert(hash).second) {
    return;
  }
  const auto module_directory = native_capture_directory();
  if (module_directory.empty()) {
    return;
  }
  const std::wstring directory =
      module_directory + L"blended_pixel_shaders";
  CreateDirectoryW(directory.c_str(), nullptr);
  wchar_t file_name[96]{};
  swprintf_s(file_name, L"\\ps-%016llx.bin",
             static_cast<unsigned long long>(hash));
  const auto path = directory + file_name;
  const auto file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                                nullptr, CREATE_ALWAYS,
                                FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    DWORD written{};
    WriteFile(file, pixel_shader.pShaderBytecode,
              static_cast<DWORD>(pixel_shader.BytecodeLength), &written,
              nullptr);
    CloseHandle(file);
  }
}

void dump_substituted_blended_pso(
    const D3D12_GRAPHICS_PIPELINE_STATE_DESC& description) {
  if (!description.VS.pShaderBytecode || description.VS.BytecodeLength == 0 ||
      !description.PS.pShaderBytecode || description.PS.BytecodeLength == 0) {
    return;
  }
  const auto vertex_hash = hash_bytecode(description.VS);
  const auto pixel_hash = hash_bytecode(description.PS);
  auto pair_hash = mix_u64(vertex_hash, pixel_hash);
  pair_hash = mix_u64(pair_hash, description.PrimitiveTopologyType);
  const auto& blend = description.BlendState.RenderTarget[0];
  pair_hash = mix_u64(pair_hash, blend.BlendEnable ? 1ULL : 0ULL);
  pair_hash = mix_u64(pair_hash, static_cast<std::uint64_t>(blend.SrcBlend));
  pair_hash = mix_u64(pair_hash, static_cast<std::uint64_t>(blend.DestBlend));
  pair_hash = mix_u64(pair_hash,
                      static_cast<std::uint64_t>(description.DepthStencilState.DepthWriteMask));

  std::scoped_lock lock(vertex_shader_dump_mutex);
  if (!dumped_blended_pso_pairs.insert(pair_hash).second) {
    return;
  }
  const auto module_directory = native_capture_directory();
  if (module_directory.empty()) {
    return;
  }
  const std::wstring directory = module_directory + L"blended_pso_diagnostics";
  CreateDirectoryW(directory.c_str(), nullptr);

  wchar_t vertex_name[96]{};
  swprintf_s(vertex_name, L"\\vs-%016llx.bin",
             static_cast<unsigned long long>(vertex_hash));
  const auto vertex_path = directory + vertex_name;
  const auto vertex_file =
      CreateFileW(vertex_path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                  CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (vertex_file != INVALID_HANDLE_VALUE) {
    DWORD written{};
    WriteFile(vertex_file, description.VS.pShaderBytecode,
              static_cast<DWORD>(description.VS.BytecodeLength), &written,
              nullptr);
    CloseHandle(vertex_file);
  }

  std::string semantics;
  for (UINT i = 0; i < description.InputLayout.NumElements; ++i) {
    const auto& element = description.InputLayout.pInputElementDescs[i];
    if (!semantics.empty()) {
      semantics += ',';
    }
    semantics += element.SemanticName ? element.SemanticName : "?";
    semantics += std::to_string(element.SemanticIndex);
    semantics += ':';
    semantics += std::to_string(static_cast<unsigned>(element.Format));
    semantics += '@';
    semantics += std::to_string(element.InputSlot);
    semantics += element.InputSlotClass == D3D12_INPUT_CLASSIFICATION_PER_INSTANCE_DATA
                     ? "i"
                     : "v";
    semantics += std::to_string(element.InstanceDataStepRate);
  }

  const auto manifest_path = directory + L"\\manifest.tsv";
  const auto manifest =
      CreateFileW(manifest_path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                  nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (manifest != INVALID_HANDLE_VALUE) {
    char line[4096]{};
    const auto length = snprintf(
        line, sizeof(line),
        "%016llx\t%016llx\ttopology=%u\tblend=%u,%u,%u,%u,%u,%u,%u\twrite=%u\tdepth=%u,%u,%u\tcull=%u\trt=%u\tdsv=%u\tinputs=%s\r\n",
        static_cast<unsigned long long>(vertex_hash),
        static_cast<unsigned long long>(pixel_hash),
        static_cast<unsigned>(description.PrimitiveTopologyType),
        blend.BlendEnable ? 1U : 0U, static_cast<unsigned>(blend.SrcBlend),
        static_cast<unsigned>(blend.DestBlend),
        static_cast<unsigned>(blend.BlendOp),
        static_cast<unsigned>(blend.SrcBlendAlpha),
        static_cast<unsigned>(blend.DestBlendAlpha),
        static_cast<unsigned>(blend.BlendOpAlpha),
        static_cast<unsigned>(blend.RenderTargetWriteMask),
        description.DepthStencilState.DepthEnable ? 1U : 0U,
        static_cast<unsigned>(description.DepthStencilState.DepthWriteMask),
        static_cast<unsigned>(description.DepthStencilState.DepthFunc),
        static_cast<unsigned>(description.RasterizerState.CullMode),
        description.NumRenderTargets > 0
            ? static_cast<unsigned>(description.RTVFormats[0])
            : 0U,
        static_cast<unsigned>(description.DSVFormat), semantics.c_str());
    if (length > 0) {
      DWORD written{};
      WriteFile(manifest, line,
                static_cast<DWORD>((std::min)(length,
                                              static_cast<int>(sizeof(line)))),
                &written, nullptr);
    }
    CloseHandle(manifest);
  }
}

void dump_pipeline_blob_if_requested(ID3D12PipelineState* state) {
  wchar_t enabled[2]{};
  const auto requested =
      GetEnvironmentVariableW(L"DARKTIDEVR_DUMP_PSO_BLOBS", enabled,
                              static_cast<DWORD>(std::size(enabled))) == 1 &&
      enabled[0] == L'1';
  if (!state || !requested) {
    return;
  }
  ComPtr<ID3DBlob> blob;
  if (FAILED(state->GetCachedBlob(&blob)) || !blob ||
      blob->GetBufferSize() == 0) {
    return;
  }
  const auto hash = hash_bytes(blob->GetBufferPointer(), blob->GetBufferSize());
  std::scoped_lock lock(vertex_shader_dump_mutex);
  if (!dumped_pipeline_blobs.insert(hash).second) {
    return;
  }
  wchar_t temporary_path[MAX_PATH]{};
  if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
    return;
  }
  const std::wstring directory =
      std::wstring(temporary_path) + L"darktidevr-vertex-shaders";
  CreateDirectoryW(directory.c_str(), nullptr);
  wchar_t file_name[96]{};
  swprintf_s(file_name, L"\\pso-%016llx.bin",
             static_cast<unsigned long long>(hash));
  const auto path = directory + file_name;
  const auto file =
      CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                  CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    DWORD written{};
    WriteFile(file, blob->GetBufferPointer(),
              static_cast<DWORD>(blob->GetBufferSize()), &written, nullptr);
    CloseHandle(file);
  }
}

void record_pso_shader_mapping_if_requested(ID3D12PipelineState* state,
                                            PsoMetadata& metadata) {
  if (!state || metadata.vertex_shader == 0 ||
      !vertex_shader_dump_requested.load(std::memory_order_relaxed)) {
    return;
  }
  ComPtr<ID3DBlob> blob;
  if (FAILED(state->GetCachedBlob(&blob)) || !blob ||
      blob->GetBufferSize() == 0) {
    return;
  }
  metadata.cached_blob =
      hash_bytes(blob->GetBufferPointer(), blob->GetBufferSize());
  const auto pair_hash = mix_u64(metadata.vertex_shader, metadata.cached_blob);
  std::scoped_lock lock(vertex_shader_dump_mutex);
  if (!dumped_pso_shader_mappings.insert(pair_hash).second) {
    return;
  }
  wchar_t temporary_path[MAX_PATH]{};
  if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
    return;
  }
  const std::wstring directory =
      std::wstring(temporary_path) + L"darktidevr-vertex-shaders";
  CreateDirectoryW(directory.c_str(), nullptr);
  const auto path = directory + L"\\pso-shader-map.tsv";
  const auto file =
      CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                  OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    char line[160]{};
    const auto length = snprintf(
        line, sizeof(line), "%016llx\t%016llx\r\n",
        static_cast<unsigned long long>(metadata.vertex_shader),
        static_cast<unsigned long long>(metadata.cached_blob));
    if (length > 0) {
      DWORD written{};
      WriteFile(file, line, static_cast<DWORD>(length), &written, nullptr);
    }
    CloseHandle(file);
  }
}

template <typename T>
bool read_stream_subobject(const std::uint8_t* stream, std::size_t size,
                           std::size_t& offset, T& value,
                           std::size_t* value_offset = nullptr) {
  const auto data_offset =
      (offset + sizeof(D3D12_PIPELINE_STATE_SUBOBJECT_TYPE) + alignof(T) - 1) &
      ~(alignof(T) - 1);
  if (data_offset + sizeof(T) > size) {
    return false;
  }
  if (value_offset) {
    *value_offset = data_offset;
  }
  std::memcpy(&value, stream + data_offset, sizeof(T));
  offset = (data_offset + sizeof(T) + alignof(void*) - 1) &
           ~(alignof(void*) - 1);
  return true;
}

PsoMetadata inspect_pipeline_stream(
    const D3D12_PIPELINE_STATE_STREAM_DESC& description,
    std::vector<std::uint8_t>* replacement_stream = nullptr,
    bool* substituted = nullptr, bool* pixel_substituted = nullptr) {
  PsoMetadata metadata{};
  const auto* stream = static_cast<const std::uint8_t*>(
      description.pPipelineStateSubobjectStream);
  D3D12_SHADER_BYTECODE vertex_shader_bytecode{};
  D3D12_SHADER_BYTECODE pixel_shader_bytecode{};
  std::size_t offset{};
  while (stream && offset + sizeof(D3D12_PIPELINE_STATE_SUBOBJECT_TYPE) <=
                       description.SizeInBytes) {
    D3D12_PIPELINE_STATE_SUBOBJECT_TYPE type{};
    std::memcpy(&type, stream + offset, sizeof(type));
    bool read{};
    switch (type) {
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_VS: {
        D3D12_SHADER_BYTECODE value{};
        std::size_t value_offset{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value, &value_offset);
        metadata.vertex_shader = read ? hash_bytecode(value) : 0;
        if (read) {
          vertex_shader_bytecode = value;
        }
        if (read && replacement_stream &&
            replacement_stream->size() == description.SizeInBytes) {
          D3D12_SHADER_BYTECODE replacement{};
          if (select_billboard_shader_replacement(value, replacement)) {
            std::memcpy(replacement_stream->data() + value_offset,
                        &replacement, sizeof(replacement));
            if (substituted) {
              *substituted = true;
            }
          }
        }
        if (read) {
          const auto billboard_register = reflect_billboard_register(value);
          metadata.billboard_shader = billboard_register.has_value();
          metadata.billboard_register =
              billboard_register.value_or(UINT_MAX);
        }
        if (read) {
          dump_vertex_shader_if_requested(value);
        }
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_PS: {
        D3D12_SHADER_BYTECODE value{};
        std::size_t value_offset{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value, &value_offset);
        metadata.pixel_shader = read ? hash_bytecode(value) : 0;
        if (read) {
          pixel_shader_bytecode = value;
        }
        if (read && replacement_stream &&
            replacement_stream->size() == description.SizeInBytes) {
          D3D12_SHADER_BYTECODE replacement{};
          if (select_billboard_pixel_shader_replacement(value, replacement)) {
            std::memcpy(replacement_stream->data() + value_offset,
                        &replacement, sizeof(replacement));
            if (pixel_substituted) {
              *pixel_substituted = true;
            }
          }
        }
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_CS: {
        D3D12_SHADER_BYTECODE value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        metadata.compute_shader = read ? hash_bytecode(value) : 0;
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_RENDER_TARGET_FORMATS: {
        D3D12_RT_FORMAT_ARRAY value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        if (read) {
          metadata.render_target_count = value.NumRenderTargets;
          metadata.render_target_format = value.NumRenderTargets > 0
                                              ? value.RTFormats[0]
                                              : DXGI_FORMAT_UNKNOWN;
        }
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DEPTH_STENCIL_FORMAT: {
        DXGI_FORMAT value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        metadata.depth_format = read ? value : DXGI_FORMAT_UNKNOWN;
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_BLEND: {
        D3D12_BLEND_DESC value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value, &metadata.ui_blend_stream_offset);
        metadata.blend_enabled = read && value.RenderTarget[0].BlendEnable;
        if (read) {
          metadata.ui_blend = value.RenderTarget[0];
          metadata.alpha_to_coverage = value.AlphaToCoverageEnable;
        }
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DEPTH_STENCIL: {
        D3D12_DEPTH_STENCIL_DESC value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        metadata.depth_enabled = read && value.DepthEnable;
        metadata.stencil_enabled = read && value.StencilEnable;
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DEPTH_STENCIL1: {
        D3D12_DEPTH_STENCIL_DESC1 value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        metadata.depth_enabled = read && value.DepthEnable;
        metadata.stencil_enabled = read && value.StencilEnable;
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_ROOT_SIGNATURE: {
        ID3D12RootSignature* value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DS:
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_HS:
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_GS: {
        D3D12_SHADER_BYTECODE value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_STREAM_OUTPUT: {
        D3D12_STREAM_OUTPUT_DESC value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_SAMPLE_MASK:
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_NODE_MASK: {
        UINT value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_RASTERIZER: {
        D3D12_RASTERIZER_DESC value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_INPUT_LAYOUT: {
        D3D12_INPUT_LAYOUT_DESC value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_IB_STRIP_CUT_VALUE: {
        D3D12_INDEX_BUFFER_STRIP_CUT_VALUE value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_PRIMITIVE_TOPOLOGY: {
        D3D12_PRIMITIVE_TOPOLOGY_TYPE value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_SAMPLE_DESC: {
        DXGI_SAMPLE_DESC value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_CACHED_PSO: {
        D3D12_CACHED_PIPELINE_STATE value{};
        std::size_t value_offset{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value, &value_offset);
        if (read) metadata.ui_cached_stream_offset = value_offset;
        if (read && replacement_stream &&
            replacement_stream->size() == description.SizeInBytes) {
          const D3D12_CACHED_PIPELINE_STATE empty{};
          std::memcpy(replacement_stream->data() + value_offset, &empty,
                      sizeof(empty));
        }
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_FLAGS: {
        D3D12_PIPELINE_STATE_FLAGS value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        break;
      }
      default:
        read = false;
        break;
    }
    if (!read) {
      break;
    }
  }
  metadata.kind = metadata.compute_shader != 0 && metadata.vertex_shader == 0
                      ? 'C'
                      : 'G';
  dump_cluster_graphics_shaders_if_target(vertex_shader_bytecode,
                                           pixel_shader_bytecode);
  dump_billboard_pixel_shader(vertex_shader_bytecode, pixel_shader_bytecode);
  if (metadata.blend_enabled) {
    dump_blended_pixel_shader(pixel_shader_bytecode);
  }
  return metadata;
}

bool needs_world_ui_alpha_pipeline(const PsoMetadata& metadata) {
  return world_ui_capture_requested() && is_stock_menu_shader_pair(metadata) &&
      metadata.render_target_count == 1 && metadata.render_target_format == DXGI_FORMAT_R8G8B8A8_UNORM &&
      !metadata.depth_enabled && !metadata.stencil_enabled &&
      darktidevr::producer::ui_capture_blend_needs_alpha_fix(metadata.ui_blend, metadata.alpha_to_coverage);
}
void prepare_world_ui_alpha_pipeline(ID3D12Device* device,
    const D3D12_GRAPHICS_PIPELINE_STATE_DESC& description, PsoMetadata& metadata) {
  if (!device || !original_create_graphics_pipeline_state || !needs_world_ui_alpha_pipeline(metadata)) return;
  auto replay = description;
  replay.CachedPSO = {};
  replay.BlendState.RenderTarget[0].SrcBlendAlpha = D3D12_BLEND_ONE;
  original_create_graphics_pipeline_state(device, &replay, IID_PPV_ARGS(&metadata.ui_alpha_pipeline));
}
void prepare_world_ui_alpha_pipeline(ID3D12Device2* device,
    const D3D12_PIPELINE_STATE_STREAM_DESC& description, PsoMetadata& metadata) {
  if (!device || !original_create_pipeline_state_stream || !needs_world_ui_alpha_pipeline(metadata) ||
      metadata.ui_blend_stream_offset > description.SizeInBytes ||
      sizeof(D3D12_BLEND_DESC) > description.SizeInBytes - metadata.ui_blend_stream_offset) return;
  const auto* bytes = static_cast<const std::uint8_t*>(description.pPipelineStateSubobjectStream);
  std::vector<std::uint8_t> stream(bytes, bytes + description.SizeInBytes);
  D3D12_BLEND_DESC blend{};
  std::memcpy(&blend, stream.data() + metadata.ui_blend_stream_offset, sizeof(blend));
  blend.RenderTarget[0].SrcBlendAlpha = D3D12_BLEND_ONE;
  std::memcpy(stream.data() + metadata.ui_blend_stream_offset, &blend, sizeof(blend));
  if (metadata.ui_cached_stream_offset != SIZE_MAX) {
    if (metadata.ui_cached_stream_offset > stream.size() ||
        sizeof(D3D12_CACHED_PIPELINE_STATE) > stream.size() - metadata.ui_cached_stream_offset) return;
    const D3D12_CACHED_PIPELINE_STATE empty{};
    std::memcpy(stream.data() + metadata.ui_cached_stream_offset, &empty, sizeof(empty));
  }
  const D3D12_PIPELINE_STATE_STREAM_DESC replay{stream.size(), stream.data()};
  original_create_pipeline_state_stream(device, &replay, IID_PPV_ARGS(&metadata.ui_alpha_pipeline));
}

HRESULT STDMETHODCALLTYPE create_pipeline_state_stream_hook(
    ID3D12Device2* device, const D3D12_PIPELINE_STATE_STREAM_DESC* description,
    REFIID iid, void** output) {
  diagnostic_stream_pso_create_count.fetch_add(1, std::memory_order_relaxed);
  std::vector<std::uint8_t> replacement_stream;
  D3D12_PIPELINE_STATE_STREAM_DESC replacement_description{};
  bool substituted{};
  bool pixel_substituted{};
  std::uint64_t original_vertex_shader{};
  const auto* effective_description = description;
  if (description && description->pPipelineStateSubobjectStream &&
      description->SizeInBytes > 0) {
    const auto* bytes = static_cast<const std::uint8_t*>(
        description->pPipelineStateSubobjectStream);
    replacement_stream.assign(bytes, bytes + description->SizeInBytes);
    original_vertex_shader =
        inspect_pipeline_stream(*description, &replacement_stream,
                                &substituted, &pixel_substituted)
            .vertex_shader;
    if (substituted || pixel_substituted) {
      replacement_description = *description;
      replacement_description.pPipelineStateSubobjectStream =
          replacement_stream.data();
      effective_description = &replacement_description;
    }
  }
  auto result = original_create_pipeline_state_stream(
      device, effective_description, iid, output);
  if (FAILED(result) && (substituted || pixel_substituted)) {
    if (substituted) {
      record_billboard_shader_creation_result(original_vertex_shader, false);
    }
    if (pixel_substituted) {
      billboard_pixel_shader_probe_creation_reject_count.fetch_add(
          1, std::memory_order_relaxed);
    }
    result = original_create_pipeline_state_stream(device, description, iid,
                                                   output);
    substituted = false;
    pixel_substituted = false;
  }
  if (SUCCEEDED(result) && substituted) {
    record_billboard_shader_creation_result(original_vertex_shader, true);
  }
  if (SUCCEEDED(result) && pixel_substituted) {
    billboard_pixel_shader_probe_applied_count.fetch_add(
        1, std::memory_order_relaxed);
  }
  if (SUCCEEDED(result) && description && output && *output) {
    auto metadata = inspect_pipeline_stream(*description);
    preserve_billboard_substitution(metadata, original_vertex_shader,
                                    substituted);
    prepare_world_ui_alpha_pipeline(device,
        (substituted || pixel_substituted) ? *effective_description : *description, metadata);
    record_pso_shader_mapping_if_requested(
        reinterpret_cast<ID3D12PipelineState*>(*output), metadata);
    std::scoped_lock lock(pso_mutex);
    const auto key = reinterpret_cast<std::uintptr_t>(*output);
    pso_metadata[key] = metadata;
    if (metadata.substituted_vertex_shader == kBillboardTargetVertexShader) {
      (void)darktidevr::producer::mark_billboard_pipeline(
          reinterpret_cast<ID3D12PipelineState*>(*output));
      write_billboard_pso_identity("target-create-stream", key, metadata);
    }
  }
  return result;
}

HRESULT STDMETHODCALLTYPE create_root_signature_hook(
    ID3D12Device* device, UINT node_mask, const void* data, SIZE_T size,
    REFIID iid, void** output) {
  diagnostic_root_signature_create_count.fetch_add(1,
                                                   std::memory_order_relaxed);
  const auto result =
      original_create_root_signature(device, node_mask, data, size, iid, output);
  if (SUCCEEDED(result) && output && *output) {
    const auto metadata = inspect_root_signature(data, size);
    std::scoped_lock lock(root_signature_mutex);
    root_signature_metadata[reinterpret_cast<std::uintptr_t>(*output)] =
        metadata;
  }
  return result;
}

DescriptorInfo describe_resource(char kind, ID3D12Resource* resource) {
  DescriptorInfo info{};
  info.kind = kind;
  info.resource = reinterpret_cast<std::uintptr_t>(resource);
  if (resource) {
    const auto description = resource->GetDesc();
    info.dimension = description.Dimension;
    info.width = description.Width;
    info.height = description.Height;
    info.depth_or_array_size = description.DepthOrArraySize;
    info.mip_levels = description.MipLevels;
    info.format = description.Format;
    info.gpu_address = resource->GetGPUVirtualAddress();
  }
  return info;
}

std::string resource_debug_name(ID3D12Resource* resource) {
  if (!resource) {
    return {};
  }

  UINT wide_size = 0;
  if (SUCCEEDED(resource->GetPrivateData(WKPDID_D3DDebugObjectNameW,
                                         &wide_size, nullptr)) &&
      wide_size >= sizeof(wchar_t)) {
    std::vector<wchar_t> wide_name(
        (wide_size + sizeof(wchar_t) - 1) / sizeof(wchar_t) + 1, L'\0');
    if (SUCCEEDED(resource->GetPrivateData(WKPDID_D3DDebugObjectNameW,
                                           &wide_size, wide_name.data()))) {
      const auto required = WideCharToMultiByte(
          CP_UTF8, 0, wide_name.data(), -1, nullptr, 0, nullptr, nullptr);
      if (required > 1) {
        std::string name(static_cast<std::size_t>(required), '\0');
        WideCharToMultiByte(CP_UTF8, 0, wide_name.data(), -1, name.data(),
                            required, nullptr, nullptr);
        name.pop_back();
        return name;
      }
    }
  }

  UINT narrow_size = 0;
  if (SUCCEEDED(resource->GetPrivateData(WKPDID_D3DDebugObjectName,
                                         &narrow_size, nullptr)) &&
      narrow_size > 0) {
    std::string name(static_cast<std::size_t>(narrow_size), '\0');
    if (SUCCEEDED(resource->GetPrivateData(WKPDID_D3DDebugObjectName,
                                           &narrow_size, name.data()))) {
      while (!name.empty() && name.back() == '\0') {
        name.pop_back();
      }
      return name;
    }
  }
  return {};
}

bool is_named_eye_final_resource(ID3D12Resource* resource) {
  const auto name = resource_debug_name(resource);
  return name == "0xf91259166b1933b1" || // darktidevr_left_eye_final
         name == "0x95d78df07ef0d850";   // darktidevr_right_eye_final
}

int named_eye_final_index(ID3D12Resource* resource) {
  const auto name = resource_debug_name(resource);
  if (name == "0xf91259166b1933b1") {  // darktidevr_left_eye_final
    return 0;
  }
  if (name == "0x95d78df07ef0d850") {  // darktidevr_right_eye_final
    return 1;
  }
  return -1;
}

bool is_named_eye_output_resource(ID3D12Resource* resource) {
  const auto name = resource_debug_name(resource);
  return name == "0x388e18bf99514d34" || // darktidevr_left_eye_output
         name == "0x81442e111aacc90e";   // darktidevr_right_eye_output
}

bool is_named_menu_ui_resource(ID3D12Resource* resource) {
  // Stingray exposes resource names as MurmurHash64A IDs. This is the exact
  // hash of the mod-authored `darktidevr_menu_ui` render target; matching the
  // name rather than dimensions prevents a fullscreen vendor UI or an eye
  // intermediate from being admitted to the menu transport.
  return resource_debug_name(resource) == "0xaf0f1409769cf92b";
}

void record_descriptor_heap(ID3D12Device* device,
                            ID3D12DescriptorHeap* heap) {
  if (!device || !heap) {
    return;
  }
  const auto description = heap->GetDesc();
  DescriptorHeapInfo info{};
  info.type = description.Type;
  info.descriptor_count = description.NumDescriptors;
  info.increment =
      device->GetDescriptorHandleIncrementSize(description.Type);
  info.cpu_start = heap->GetCPUDescriptorHandleForHeapStart().ptr;
  if ((description.Flags & D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE) != 0) {
    info.gpu_start = heap->GetGPUDescriptorHandleForHeapStart().ptr;
  }
  std::scoped_lock lock(descriptor_mutex);
  descriptor_heaps[reinterpret_cast<std::uintptr_t>(heap)] = info;
}

HRESULT STDMETHODCALLTYPE create_descriptor_heap_hook(
    ID3D12Device* device, const D3D12_DESCRIPTOR_HEAP_DESC* description,
    REFIID iid, void** output) {
  const auto result =
      original_create_descriptor_heap(device, description, iid, output);
  if (SUCCEEDED(result) && description && output && *output) {
    auto* heap = reinterpret_cast<ID3D12DescriptorHeap*>(*output);
    record_descriptor_heap(device, heap);
  }
  return result;
}

void STDMETHODCALLTYPE create_constant_buffer_view_hook(
    ID3D12Device* device, const D3D12_CONSTANT_BUFFER_VIEW_DESC* description,
    D3D12_CPU_DESCRIPTOR_HANDLE destination) {
  original_create_constant_buffer_view(device, description, destination);
  DescriptorInfo info{};
  info.kind = 'C';
  if (description) {
    info.gpu_address = description->BufferLocation;
    info.width = description->SizeInBytes;
    info.dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
  }
  std::scoped_lock lock(descriptor_mutex);
  descriptor_metadata[destination.ptr] = info;
}

void STDMETHODCALLTYPE create_shader_resource_view_hook(
    ID3D12Device* device, ID3D12Resource* resource,
    const D3D12_SHADER_RESOURCE_VIEW_DESC* description,
    D3D12_CPU_DESCRIPTOR_HANDLE destination) {
  original_create_shader_resource_view(device, resource, description,
                                       destination);
  auto info = describe_resource('S', resource);
  if (description) {
    info.dimension = description->ViewDimension;
    info.format = description->Format;
    if (description->ViewDimension == D3D12_SRV_DIMENSION_BUFFER) {
      info.first_element = description->Buffer.FirstElement;
      info.element_count = description->Buffer.NumElements;
      info.structure_stride = description->Buffer.StructureByteStride;
    }
  }
  std::scoped_lock lock(descriptor_mutex);
  descriptor_metadata[destination.ptr] = info;
}

void STDMETHODCALLTYPE create_unordered_access_view_hook(
    ID3D12Device* device, ID3D12Resource* resource,
    ID3D12Resource* counter_resource,
    const D3D12_UNORDERED_ACCESS_VIEW_DESC* description,
    D3D12_CPU_DESCRIPTOR_HANDLE destination) {
  original_create_unordered_access_view(device, resource, counter_resource,
                                        description, destination);
  auto info = describe_resource('U', resource);
  if (description) {
    info.dimension = description->ViewDimension;
    info.format = description->Format;
    if (description->ViewDimension == D3D12_UAV_DIMENSION_BUFFER) {
      info.first_element = description->Buffer.FirstElement;
      info.element_count = description->Buffer.NumElements;
      info.structure_stride = description->Buffer.StructureByteStride;
    }
  }
  std::scoped_lock lock(descriptor_mutex);
  descriptor_metadata[destination.ptr] = info;
}

void STDMETHODCALLTYPE create_render_target_view_hook(
    ID3D12Device* device, ID3D12Resource* resource,
    const D3D12_RENDER_TARGET_VIEW_DESC* description,
    D3D12_CPU_DESCRIPTOR_HANDLE destination) {
  original_create_render_target_view(device, resource, description,
                                     destination);
  auto info = describe_resource('R', resource);
  if (description) {
    info.dimension = description->ViewDimension;
    info.format = description->Format;
  }
  {
    std::scoped_lock lock(descriptor_mutex);
    descriptor_metadata[destination.ptr] = info;
  }
  write_focused_log(
      "phase=%d\tframe=%llu\tCREATE_RTV\thandle=%llu\tresource=%p\tformat=%u"
      "\tdimension=%u\twidth=%llu\theight=%u\tarray=%u\tmips=%u\r\n",
      focused_trace_phase.load(std::memory_order_relaxed),
      present_count.load(std::memory_order_relaxed), destination.ptr, resource,
      info.format, info.dimension, info.width, info.height,
      info.depth_or_array_size, info.mip_levels);
}

void STDMETHODCALLTYPE create_depth_stencil_view_hook(
    ID3D12Device* device, ID3D12Resource* resource,
    const D3D12_DEPTH_STENCIL_VIEW_DESC* description,
    D3D12_CPU_DESCRIPTOR_HANDLE destination) {
  original_create_depth_stencil_view(device, resource, description,
                                     destination);
  auto info = describe_resource('D', resource);
  if (description) {
    info.dimension = description->ViewDimension;
    info.format = description->Format;
  }
  {
    std::scoped_lock lock(descriptor_mutex);
    descriptor_metadata[destination.ptr] = info;
  }
  write_focused_log(
      "phase=%d\tframe=%llu\tCREATE_DSV\thandle=%llu\tresource=%p\tformat=%u"
      "\tdimension=%u\twidth=%llu\theight=%u\tarray=%u\tmips=%u\r\n",
      focused_trace_phase.load(std::memory_order_relaxed),
      present_count.load(std::memory_order_relaxed), destination.ptr, resource,
      info.format, info.dimension, info.width, info.height,
      info.depth_or_array_size, info.mip_levels);
}

void log_texture_allocation(const char* allocation, const void* object,
                            const D3D12_RESOURCE_DESC* description,
                            D3D12_RESOURCE_STATES initial_state,
                            D3D12_HEAP_TYPE heap_type, D3D12_HEAP_FLAGS flags,
                            const void* heap, UINT64 heap_offset,
                            HRESULT result) {
  if (boundary_census_log == INVALID_HANDLE_VALUE || !description ||
      description->Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
      (description->Width < 640 && description->Height < 640)) {
    return;
  }
  write_boundary_census_log(
      "frame=%llu\tALLOC_%s\tresult=%ld\tobject=%p\theap=%p\toffset=%llu"
      "\theap_type=%u\theap_flags=%u\twidth=%llu\theight=%u\tformat=%u"
      "\tarray=%u\tmips=%u\tsamples=%u\tlayout=%u\tresource_flags=%u"
      "\tinitial_state=%u\r\n",
      present_count.load(std::memory_order_relaxed), allocation, result,
      object, heap, static_cast<unsigned long long>(heap_offset),
      static_cast<unsigned>(heap_type), static_cast<unsigned>(flags),
      static_cast<unsigned long long>(description->Width), description->Height,
      static_cast<unsigned>(description->Format),
      description->DepthOrArraySize, description->MipLevels,
      description->SampleDesc.Count, static_cast<unsigned>(description->Layout),
      static_cast<unsigned>(description->Flags),
      static_cast<unsigned>(initial_state));
}

HRESULT STDMETHODCALLTYPE create_committed_resource_hook(
    ID3D12Device* device, const D3D12_HEAP_PROPERTIES* properties,
    D3D12_HEAP_FLAGS heap_flags, const D3D12_RESOURCE_DESC* description,
    D3D12_RESOURCE_STATES initial_state, const D3D12_CLEAR_VALUE* clear_value,
    REFIID iid, void** output) {
  const auto result = original_create_committed_resource(
      device, properties, heap_flags, description, initial_state, clear_value,
      iid, output);
  log_texture_allocation(
      "COMMITTED", SUCCEEDED(result) && output ? *output : nullptr,
      description, initial_state,
      properties ? properties->Type : D3D12_HEAP_TYPE_CUSTOM, heap_flags,
      nullptr, 0, result);
  if (SUCCEEDED(result) && output && *output && description &&
      description->Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
    auto* resource = reinterpret_cast<ID3D12Resource*>(*output);
    const auto gpu_start = resource->GetGPUVirtualAddress();
    if (gpu_start != 0) {
      buffer_registry->track(resource, gpu_start, description->Width,
          properties ? properties->Type : D3D12_HEAP_TYPE_CUSTOM);
    }
  }
  return result;
}

HRESULT STDMETHODCALLTYPE create_placed_resource_hook(
    ID3D12Device* device, ID3D12Heap* heap, UINT64 heap_offset,
    const D3D12_RESOURCE_DESC* description,
    D3D12_RESOURCE_STATES initial_state, const D3D12_CLEAR_VALUE* clear_value,
    REFIID iid, void** output) {
  const auto result = original_create_placed_resource(
      device, heap, heap_offset, description, initial_state, clear_value, iid,
      output);
  D3D12_HEAP_DESC heap_description{};
  if (heap) {
    heap_description = heap->GetDesc();
  }
  log_texture_allocation(
      "PLACED", SUCCEEDED(result) && output ? *output : nullptr, description,
      initial_state, heap_description.Properties.Type, heap_description.Flags,
      heap, heap_offset, result);
  if (SUCCEEDED(result) && output && *output && description &&
      description->Dimension == D3D12_RESOURCE_DIMENSION_BUFFER) {
    auto* resource = reinterpret_cast<ID3D12Resource*>(*output);
    const auto gpu_start = resource->GetGPUVirtualAddress();
    if (gpu_start != 0) {
      buffer_registry->track(resource, gpu_start, description->Width,
          heap_description.Properties.Type);
    }
  }
  return result;
}

HRESULT STDMETHODCALLTYPE resource_map_hook(ID3D12Resource* resource,
                                             UINT subresource,
                                             const D3D12_RANGE* read_range,
                                             void** data) {
  const auto result =
      original_resource_map(resource, subresource, read_range, data);
  if (FAILED(result) || !data || !*data) {
    return result;
  }

  billboard_resource_map_count.fetch_add(1, std::memory_order_relaxed);
  std::array<void*, 16> map_stack{};
  const auto map_stack_count = CaptureStackBackTrace(
      1, static_cast<DWORD>(map_stack.size()), map_stack.data(), nullptr);
  std::scoped_lock lock(buffer_resource_mutex);
  for (auto it = buffer_resources.rbegin(); it != buffer_resources.rend(); ++it) {
    if (it->resource != resource) {
      continue;
    }
    it->mapped_base = static_cast<std::byte*>(*data);
    it->mapped_subresource = subresource;
    it->mapped = true;
    it->last_map_stack = map_stack;
    it->last_map_stack_count = map_stack_count;
    billboard_resource_map_match_count.fetch_add(1,
                                                  std::memory_order_relaxed);
    break;
  }
  return result;
}

void STDMETHODCALLTYPE resource_unmap_hook(ID3D12Resource* resource,
                                           UINT subresource,
                                           const D3D12_RANGE* written_range) {
  {
    std::scoped_lock lock(buffer_resource_mutex);
    for (auto it = buffer_resources.rbegin(); it != buffer_resources.rend();
         ++it) {
      if (it->resource != resource || !it->mapped ||
          it->mapped_subresource != subresource) {
        continue;
      }
      it->mapped_base = nullptr;
      it->mapped = false;
      billboard_resource_unmap_count.fetch_add(1,
                                                std::memory_order_relaxed);
      break;
    }
  }
  original_resource_unmap(resource, subresource, written_range);
}

struct StingrayUploadSnapshot {
  ID3D12Resource* resource{};
  std::byte* staging_base{};
  std::uint64_t staging_size{};
};

bool take_stingray_upload_snapshot(void* allocator,
                                   StingrayUploadSnapshot* snapshot) {
  __try {
    const auto* bytes = static_cast<const std::byte*>(allocator);
    const auto ring_index = *reinterpret_cast<const UINT*>(bytes + 0xa8);
    const auto ring_entries =
        *reinterpret_cast<std::byte* const*>(bytes + 0xc0);
    if (ring_index >= 64 || !ring_entries) {
      return false;
    }
    const auto* entry =
        ring_entries + static_cast<std::size_t>(ring_index) * 40;
    const auto end_offset =
        *reinterpret_cast<const std::uint64_t*>(entry);
    const auto begin_offset =
        *reinterpret_cast<const std::uint64_t*>(entry + 0x20);
    snapshot->resource =
        *reinterpret_cast<ID3D12Resource* const*>(entry + 0x10);
    snapshot->staging_base =
        *reinterpret_cast<std::byte* const*>(entry + 0x18);
    snapshot->staging_size = end_offset;
    return snapshot->resource && snapshot->staging_base &&
           end_offset >= begin_offset &&
           end_offset - begin_offset <= (1ULL << 32);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    // This is a version-gated diagnostic hook. An unexpected layout fails
    // closed and the original Stingray upload path still runs unchanged.
    return false;
  }
}

bool safe_copy_bytes(void* destination, const void* source,
                     std::size_t size) {
  __try {
    std::memcpy(destination, source, size);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

void stingray_upload_flush_hook(void* allocator) {
  StingrayUploadSnapshot snapshot{};
  bool target_ring_known = false;
  bool matched_target_ring = false;
  bool matched_tracked_resource = false;
  if (allocator && take_stingray_upload_snapshot(allocator, &snapshot)) {
    {
      std::scoped_lock lock(cluster_constant_copy_mutex);
      target_ring_known = !cluster_constant_ring_resources.empty();
      matched_target_ring =
          cluster_constant_ring_resources.contains(snapshot.resource);
    }
    std::scoped_lock lock(buffer_resource_mutex);
    for (auto it = buffer_resources.rbegin(); it != buffer_resources.rend();
         ++it) {
      if (it->resource == snapshot.resource) {
        it->staging_base = snapshot.staging_base;
        it->staging_size = snapshot.staging_size;
        matched_tracked_resource = true;
        billboard_upload_flush_count.fetch_add(1,
                                                std::memory_order_relaxed);
        break;
      }
    }
  }
  if (cluster_trace_log != INVALID_HANDLE_VALUE && target_ring_known &&
      snapshot.resource &&
      cluster_upload_flush_log_count.fetch_add(
          1, std::memory_order_relaxed) < 512) {
    write_cluster_trace_log(
        "frame=%llu\tCLUSTER_UPLOAD_FLUSH\tresource=%p\tstaging=%p"
        "\tstaging_size=%llu\ttarget=%u\ttracked=%u\r\n",
        static_cast<unsigned long long>(
            present_count.load(std::memory_order_relaxed)),
        snapshot.resource, snapshot.staging_base,
        static_cast<unsigned long long>(snapshot.staging_size),
        matched_target_ring ? 1u : 0u,
        matched_tracked_resource ? 1u : 0u);
  }
  if (cluster_trace_log != INVALID_HANDLE_VALUE && matched_target_ring &&
      snapshot.staging_base) {
    constexpr std::size_t kRasterConstantBytes = 84;
    std::scoped_lock lock(cluster_constant_copy_mutex);
    const auto pending_count = (std::min<std::uint64_t>)(
        cluster_pending_constant_count,
        cluster_pending_constant_samples.size());
    for (std::uint64_t i = 0; i < pending_count; ++i) {
      auto& pending = cluster_pending_constant_samples[i];
      if (pending.captured || pending.resource != snapshot.resource ||
          pending.resource_offset + kRasterConstantBytes >
              snapshot.staging_size) {
        continue;
      }
      float staged_fov{};
      const auto* staged_fov_source = snapshot.staging_base +
                                      pending.resource_offset + 72;
      safe_copy_bytes(&staged_fov, staged_fov_source, sizeof(staged_fov));
      const auto corrected_fov =
          render_vertical_fov_radians.load(std::memory_order_relaxed);
      // Cluster tracing is observational. The separately gated production
      // correction below owns the write so enabling a trace cannot silently
      // change renderer behaviour.
      const auto fov_patched = false;
      std::array<std::byte, kRasterConstantBytes> bytes{};
      if (!safe_copy_bytes(bytes.data(),
                           snapshot.staging_base + pending.resource_offset,
                           bytes.size())) {
        continue;
      }
      pending.captured = true;
      std::array<float, 16> projection{};
      std::uint32_t render_target_offset{};
      float aspect{};
      float fov{};
      std::uint32_t vb_offset{};
      std::uint32_t ib_offset{};
      std::memcpy(projection.data(), bytes.data(), sizeof(projection));
      std::memcpy(&render_target_offset, bytes.data() + 64,
                  sizeof(render_target_offset));
      std::memcpy(&aspect, bytes.data() + 68, sizeof(aspect));
      std::memcpy(&fov, bytes.data() + 72, sizeof(fov));
      std::memcpy(&vb_offset, bytes.data() + 76, sizeof(vb_offset));
      std::memcpy(&ib_offset, bytes.data() + 80, sizeof(ib_offset));
      write_cluster_trace_log(
          "frame=%llu\tCLUSTER_RASTER_C0_DEFERRED\trecorded_frame=%llu"
          "\tCL=%p\troot=%u\tgpu=%llu\tresource=%p\toffset=%llu"
          "\tstaging_size=%llu\tstaged_fov=%g\tcorrected_fov=%g"
          "\tfov_patched=%u"
          "\tproj=%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g"
          "\trt_offset=%u\taspect=%g\tfov=%g\tvb_offset=%u"
          "\tib_offset=%u\r\n",
          static_cast<unsigned long long>(
              present_count.load(std::memory_order_relaxed)),
          static_cast<unsigned long long>(pending.frame), pending.commands,
          pending.root,
          static_cast<unsigned long long>(pending.gpu_address),
          pending.resource,
          static_cast<unsigned long long>(pending.resource_offset),
          static_cast<unsigned long long>(snapshot.staging_size),
          staged_fov, corrected_fov, fov_patched ? 1u : 0u,
          projection[0], projection[1], projection[2], projection[3],
          projection[4], projection[5], projection[6], projection[7],
          projection[8], projection[9], projection[10], projection[11],
          projection[12], projection[13], projection[14], projection[15],
          render_target_offset, aspect, fov, vb_offset, ib_offset);
    }
    const auto transform_count = (std::min<std::uint64_t>)(
        cluster_pending_transform_count,
        cluster_pending_transform_samples.size());
    for (std::uint64_t i = 0; i < transform_count; ++i) {
      auto& pending = cluster_pending_transform_samples[i];
      const auto byte_count = static_cast<std::uint64_t>(
          pending.element_count) * pending.stride;
      if (pending.captured || pending.resource != snapshot.resource ||
          pending.stride < 64 || pending.element_count == 0 ||
          pending.resource_offset + byte_count > snapshot.staging_size) {
        continue;
      }
      pending.captured = true;
      write_cluster_trace_log(
          "frame=%llu\tCLUSTER_LIGHT_TRANSFORMS\trecorded_frame=%llu"
          "\tCL=%p\tresource=%p\tfirst=%llu\tcount=%u\tstride=%u\r\n",
          static_cast<unsigned long long>(
              present_count.load(std::memory_order_relaxed)),
          static_cast<unsigned long long>(pending.frame), pending.commands,
          pending.resource,
          static_cast<unsigned long long>(pending.first_element),
          pending.element_count,
          pending.stride);
      for (std::uint32_t element = 0; element < pending.element_count;
           ++element) {
        std::array<float, 16> matrix{};
        const auto* source = snapshot.staging_base +
                             pending.resource_offset +
                             static_cast<std::uint64_t>(element) *
                                 pending.stride;
        if (!safe_copy_bytes(matrix.data(), source, sizeof(matrix))) {
          continue;
        }
        write_cluster_trace_log(
            "frame=%llu\tCLUSTER_LIGHT_TRANSFORM\trecorded_frame=%llu"
            "\tCL=%p\tfirst=%llu\tcount=%u\telement=%u"
            "\tm=%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g"
            "\r\n",
            static_cast<unsigned long long>(
                present_count.load(std::memory_order_relaxed)),
            static_cast<unsigned long long>(pending.frame), pending.commands,
            static_cast<unsigned long long>(pending.first_element),
            pending.element_count, element, matrix[0],
            matrix[1], matrix[2], matrix[3], matrix[4], matrix[5], matrix[6],
            matrix[7], matrix[8], matrix[9], matrix[10], matrix[11], matrix[12],
            matrix[13], matrix[14], matrix[15]);
      }
    }
  }
  if (cluster_light_visibility_fix_active.load(std::memory_order_relaxed) &&
      snapshot.resource && snapshot.staging_base) {
    constexpr std::size_t kRasterConstantBytes = 84;
    constexpr std::size_t kRasterFovOffset = 72;
    constexpr float kPi = 3.14159265F;
    const auto corrected_fov =
        render_vertical_fov_radians.load(std::memory_order_relaxed);
    const auto current_frame = present_count.load(std::memory_order_relaxed);
    std::scoped_lock lock(cluster_light_visibility_fix_mutex);
    for (auto& pending : cluster_pending_fov_patches) {
      if (!pending.valid) {
        continue;
      }
      if (current_frame > pending.frame + 8) {
        pending.valid = false;
        cluster_light_visibility_fix_reject_count.fetch_add(
            1, std::memory_order_relaxed);
        continue;
      }
      if (pending.resource != snapshot.resource ||
          pending.resource_offset + kRasterConstantBytes >
              snapshot.staging_size) {
        continue;
      }
      float staged_fov{};
      auto* staged_fov_address = snapshot.staging_base +
                                 pending.resource_offset + kRasterFovOffset;
      const auto staged_fov_read = safe_copy_bytes(
          &staged_fov, staged_fov_address, sizeof(staged_fov));
      const auto valid_values = staged_fov_read && staged_fov > 0.0F &&
                                staged_fov < kPi && corrected_fov > 0.0F &&
                                corrected_fov < kPi;
      if (!valid_values) {
        pending.valid = false;
        cluster_light_visibility_fix_reject_count.fetch_add(
            1, std::memory_order_relaxed);
        continue;
      }
      if (std::abs(staged_fov - corrected_fov) > 0.0001F) {
        if (safe_copy_bytes(staged_fov_address, &corrected_fov,
                            sizeof(corrected_fov))) {
          cluster_light_visibility_fix_patch_count.fetch_add(
              1, std::memory_order_relaxed);
        } else {
          cluster_light_visibility_fix_reject_count.fetch_add(
              1, std::memory_order_relaxed);
        }
      }
      pending.valid = false;
    }
  }
  original_stingray_upload_flush(allocator);
}

void STDMETHODCALLTYPE copy_descriptors_simple_hook(
    ID3D12Device* device, UINT descriptor_count,
    D3D12_CPU_DESCRIPTOR_HANDLE destination,
    D3D12_CPU_DESCRIPTOR_HANDLE source, D3D12_DESCRIPTOR_HEAP_TYPE type) {
  original_copy_descriptors_simple(device, descriptor_count, destination,
                                   source, type);
  const auto increment = device->GetDescriptorHandleIncrementSize(type);
  std::scoped_lock lock(descriptor_mutex);
  for (UINT i = 0; i < descriptor_count; ++i) {
    const auto source_handle = source.ptr +
                               static_cast<std::uint64_t>(i) * increment;
    const auto destination_handle =
        destination.ptr + static_cast<std::uint64_t>(i) * increment;
    const auto found = descriptor_metadata.find(source_handle);
    if (found != descriptor_metadata.end()) {
      descriptor_metadata[destination_handle] = found->second;
    } else {
      descriptor_metadata.erase(destination_handle);
    }
  }
}

void STDMETHODCALLTYPE copy_descriptors_hook(
    ID3D12Device* device, UINT destination_range_count,
    const D3D12_CPU_DESCRIPTOR_HANDLE* destination_range_starts,
    const UINT* destination_range_sizes, UINT source_range_count,
    const D3D12_CPU_DESCRIPTOR_HANDLE* source_range_starts,
    const UINT* source_range_sizes, D3D12_DESCRIPTOR_HEAP_TYPE type) {
  original_copy_descriptors(
      device, destination_range_count, destination_range_starts,
      destination_range_sizes, source_range_count, source_range_starts,
      source_range_sizes, type);
  if (!destination_range_starts || !source_range_starts) {
    return;
  }
  const auto increment = device->GetDescriptorHandleIncrementSize(type);
  UINT destination_range{};
  UINT source_range{};
  UINT destination_offset{};
  UINT source_offset{};
  std::scoped_lock lock(descriptor_mutex);
  while (destination_range < destination_range_count &&
         source_range < source_range_count) {
    const auto destination_size = destination_range_sizes
                                      ? destination_range_sizes[destination_range]
                                      : 1U;
    const auto source_size =
        source_range_sizes ? source_range_sizes[source_range] : 1U;
    const auto copy_count =
        (std::min)(destination_size - destination_offset,
                   source_size - source_offset);
    for (UINT i = 0; i < copy_count; ++i) {
      const auto source_handle =
          source_range_starts[source_range].ptr +
          static_cast<std::uint64_t>(source_offset + i) * increment;
      const auto destination_handle =
          destination_range_starts[destination_range].ptr +
          static_cast<std::uint64_t>(destination_offset + i) * increment;
      const auto found = descriptor_metadata.find(source_handle);
      if (found != descriptor_metadata.end()) {
        descriptor_metadata[destination_handle] = found->second;
      } else {
        descriptor_metadata.erase(destination_handle);
      }
    }
    destination_offset += copy_count;
    source_offset += copy_count;
    if (destination_offset == destination_size) {
      ++destination_range;
      destination_offset = 0;
    }
    if (source_offset == source_size) {
      ++source_range;
      source_offset = 0;
    }
  }
}

HRESULT STDMETHODCALLTYPE create_graphics_pipeline_state_hook(
    ID3D12Device* device, const D3D12_GRAPHICS_PIPELINE_STATE_DESC* description,
    REFIID iid, void** output) {
  diagnostic_graphics_pso_create_count.fetch_add(1,
                                                 std::memory_order_relaxed);
  if (description) {
    dump_cluster_graphics_shaders_if_target(description->VS,
                                             description->PS);
    dump_vertex_shader_if_requested(description->VS,
                                    &description->InputLayout);
    dump_billboard_pixel_shader(description->VS, description->PS);
    if (description->NumRenderTargets > 0 &&
        description->BlendState.RenderTarget[0].BlendEnable) {
      dump_blended_pixel_shader(description->PS);
    }
  }
  D3D12_GRAPHICS_PIPELINE_STATE_DESC replacement_description{};
  D3D12_SHADER_BYTECODE replacement_shader{};
  D3D12_SHADER_BYTECODE replacement_pixel_shader{};
  bool substituted{};
  bool pixel_substituted{};
  bool description_replaced{};
  const auto* effective_description = description;
  if (description && select_billboard_pixel_shader_replacement(
                         description->PS, replacement_pixel_shader)) {
    dump_substituted_blended_pso(*description);
    replacement_description = *description;
    replacement_description.PS = replacement_pixel_shader;
    replacement_description.CachedPSO = {};
    effective_description = &replacement_description;
    pixel_substituted = true;
    description_replaced = true;
  }
  if (description && select_billboard_shader_replacement(
                         description->VS, replacement_shader)) {
    if (!description_replaced) {
      replacement_description = *description;
    }
    replacement_description.VS = replacement_shader;
    // Cached PSO data describes the original shader and must not be offered to
    // D3D12 after changing the VS.
    replacement_description.CachedPSO = {};
    effective_description = &replacement_description;
    substituted = true;
  }
  auto result = original_create_graphics_pipeline_state(
      device, effective_description, iid, output);
  if (FAILED(result) && (substituted || pixel_substituted)) {
    if (substituted) {
      record_billboard_shader_creation_result(hash_bytecode(description->VS),
                                              false);
    }
    if (pixel_substituted) {
      billboard_pixel_shader_probe_creation_reject_count.fetch_add(
          1, std::memory_order_relaxed);
    }
    result = original_create_graphics_pipeline_state(device, description, iid,
                                                     output);
    substituted = false;
    pixel_substituted = false;
  }
  if (SUCCEEDED(result) && substituted) {
    record_billboard_shader_creation_result(hash_bytecode(description->VS),
                                            true);
  }
  if (SUCCEEDED(result) && pixel_substituted) {
    billboard_pixel_shader_probe_applied_count.fetch_add(
        1, std::memory_order_relaxed);
  }
  if (SUCCEEDED(result) && description && output && *output) {
    PsoMetadata metadata{};
    metadata.kind = 'G';
    metadata.vertex_shader = hash_bytecode(description->VS);
    const auto billboard_register = reflect_billboard_register(description->VS);
    metadata.billboard_shader = billboard_register.has_value();
    metadata.billboard_register = billboard_register.value_or(UINT_MAX);
    metadata.pixel_shader = hash_bytecode(description->PS);
    metadata.render_target_count = description->NumRenderTargets;
    metadata.render_target_format = description->NumRenderTargets > 0
                                        ? description->RTVFormats[0]
                                        : DXGI_FORMAT_UNKNOWN;
    metadata.depth_format = description->DSVFormat;
    metadata.blend_enabled = description->NumRenderTargets > 0 &&
                             description->BlendState.RenderTarget[0].BlendEnable;
    metadata.depth_enabled = description->DepthStencilState.DepthEnable;
    metadata.stencil_enabled = description->DepthStencilState.StencilEnable;
    metadata.alpha_to_coverage = description->BlendState.AlphaToCoverageEnable;
    metadata.ui_blend = description->BlendState.RenderTarget[0];
    preserve_billboard_substitution(metadata, hash_bytecode(description->VS),
                                    substituted);
    prepare_world_ui_alpha_pipeline(device,
        (substituted || pixel_substituted) ? *effective_description : *description, metadata);
    record_pso_shader_mapping_if_requested(
        reinterpret_cast<ID3D12PipelineState*>(*output), metadata);
    std::scoped_lock lock(pso_mutex);
    const auto key = reinterpret_cast<std::uintptr_t>(*output);
    pso_metadata[key] = metadata;
    if (metadata.substituted_vertex_shader == kBillboardTargetVertexShader) {
      (void)darktidevr::producer::mark_billboard_pipeline(
          reinterpret_cast<ID3D12PipelineState*>(*output));
      write_billboard_pso_identity("target-create-graphics", key, metadata);
    }
  }
  return result;
}

HRESULT STDMETHODCALLTYPE create_compute_pipeline_state_hook(
    ID3D12Device* device, const D3D12_COMPUTE_PIPELINE_STATE_DESC* description,
    REFIID iid, void** output) {
  diagnostic_compute_pso_create_count.fetch_add(1,
                                                std::memory_order_relaxed);
  if (description) {
    dump_cluster_compute_shader_if_target(description->CS);
  }
  const auto result = original_create_compute_pipeline_state(
      device, description, iid, output);
  if (SUCCEEDED(result) && description && output && *output) {
    PsoMetadata metadata{};
    metadata.kind = 'C';
    metadata.compute_shader = hash_bytecode(description->CS);
    std::scoped_lock lock(pso_mutex);
    const auto key = reinterpret_cast<std::uintptr_t>(*output);
    pso_metadata[key] = metadata;
    if (metadata.substituted_vertex_shader == kBillboardTargetVertexShader) {
      (void)darktidevr::producer::mark_billboard_pipeline(
          reinterpret_cast<ID3D12PipelineState*>(*output));
      write_billboard_pso_identity("target-load-graphics", key, metadata);
    }
  }
  return result;
}

HRESULT STDMETHODCALLTYPE create_command_signature_hook(
    ID3D12Device* device, const D3D12_COMMAND_SIGNATURE_DESC* description,
    ID3D12RootSignature* root_signature, REFIID iid, void** output) {
  const auto result = original_create_command_signature(
      device, description, root_signature, iid, output);
  if (SUCCEEDED(result) && description != nullptr && output != nullptr &&
      *output != nullptr) {
    bool submits_graphics_draw{};
    for (UINT index = 0; index < description->NumArgumentDescs; ++index) {
      const auto type = description->pArgumentDescs[index].Type;
      if (type == D3D12_INDIRECT_ARGUMENT_TYPE_DRAW ||
          type == D3D12_INDIRECT_ARGUMENT_TYPE_DRAW_INDEXED) {
        submits_graphics_draw = true;
        break;
      }
    }
    std::scoped_lock lock(command_signature_mutex);
    command_signature_draws[reinterpret_cast<std::uintptr_t>(*output)] =
        submits_graphics_draw;
  }
  return result;
}

HRESULT STDMETHODCALLTYPE load_graphics_pipeline_hook(
    ID3D12PipelineLibrary* library, LPCWSTR name,
    const D3D12_GRAPHICS_PIPELINE_STATE_DESC* description, REFIID iid,
    void** output) {
  diagnostic_graphics_pipeline_load_count.fetch_add(
      1, std::memory_order_relaxed);
  if (description) {
    dump_cluster_graphics_shaders_if_target(description->VS,
                                             description->PS);
    dump_vertex_shader_if_requested(description->VS,
                                    &description->InputLayout);
    dump_billboard_pixel_shader(description->VS, description->PS);
    if (description->NumRenderTargets > 0 &&
        description->BlendState.RenderTarget[0].BlendEnable) {
      dump_blended_pixel_shader(description->PS);
    }
  }
  D3D12_GRAPHICS_PIPELINE_STATE_DESC replacement_description{};
  D3D12_SHADER_BYTECODE replacement_shader{};
  D3D12_SHADER_BYTECODE replacement_pixel_shader{};
  bool substituted{};
  bool pixel_substituted{};
  bool description_replaced{};
  const auto* effective_description = description;
  if (description && select_billboard_pixel_shader_replacement(
                         description->PS, replacement_pixel_shader)) {
    dump_substituted_blended_pso(*description);
    replacement_description = *description;
    replacement_description.PS = replacement_pixel_shader;
    replacement_description.CachedPSO = {};
    effective_description = &replacement_description;
    pixel_substituted = true;
    description_replaced = true;
  }
  if (description && select_billboard_shader_replacement(
                         description->VS, replacement_shader)) {
    if (!description_replaced) {
      replacement_description = *description;
    }
    replacement_description.VS = replacement_shader;
    replacement_description.CachedPSO = {};
    effective_description = &replacement_description;
    substituted = true;
  }
  HRESULT result{};
  if (substituted || pixel_substituted) {
    ComPtr<ID3D12Device> device;
    result = FAILED(library->GetDevice(IID_PPV_ARGS(&device)))
                 ? E_NOINTERFACE
                 : original_create_graphics_pipeline_state(
                       device.Get(), effective_description, iid, output);
  } else {
    result = original_load_graphics_pipeline(
        library, name, effective_description, iid, output);
  }
  if (FAILED(result) && (substituted || pixel_substituted)) {
    if (substituted) {
      record_billboard_shader_creation_result(hash_bytecode(description->VS),
                                              false);
    }
    if (pixel_substituted) {
      billboard_pixel_shader_probe_creation_reject_count.fetch_add(
          1, std::memory_order_relaxed);
    }
    result = original_load_graphics_pipeline(library, name, description, iid,
                                             output);
    substituted = false;
    pixel_substituted = false;
  }
  if (SUCCEEDED(result) && substituted) {
    record_billboard_shader_creation_result(hash_bytecode(description->VS),
                                            true);
  }
  if (SUCCEEDED(result) && pixel_substituted) {
    billboard_pixel_shader_probe_applied_count.fetch_add(
        1, std::memory_order_relaxed);
  }
  if (SUCCEEDED(result) && description && output && *output) {
    PsoMetadata metadata{};
    metadata.kind = 'G';
    metadata.vertex_shader = hash_bytecode(description->VS);
    const auto billboard_register = reflect_billboard_register(description->VS);
    metadata.billboard_shader = billboard_register.has_value();
    metadata.billboard_register = billboard_register.value_or(UINT_MAX);
    metadata.pixel_shader = hash_bytecode(description->PS);
    metadata.render_target_count = description->NumRenderTargets;
    metadata.render_target_format = description->NumRenderTargets > 0
                                        ? description->RTVFormats[0]
                                        : DXGI_FORMAT_UNKNOWN;
    metadata.depth_format = description->DSVFormat;
    metadata.blend_enabled = description->NumRenderTargets > 0 &&
                             description->BlendState.RenderTarget[0].BlendEnable;
    metadata.depth_enabled = description->DepthStencilState.DepthEnable;
    metadata.stencil_enabled = description->DepthStencilState.StencilEnable;
    metadata.alpha_to_coverage = description->BlendState.AlphaToCoverageEnable;
    metadata.ui_blend = description->BlendState.RenderTarget[0];
    preserve_billboard_substitution(metadata, hash_bytecode(description->VS),
                                    substituted);
    ComPtr<ID3D12Device> ui_device;
    if (needs_world_ui_alpha_pipeline(metadata) && SUCCEEDED(library->GetDevice(IID_PPV_ARGS(&ui_device))))
      prepare_world_ui_alpha_pipeline(ui_device.Get(),
          (substituted || pixel_substituted) ? *effective_description : *description, metadata);
    record_pso_shader_mapping_if_requested(
        reinterpret_cast<ID3D12PipelineState*>(*output), metadata);
    std::scoped_lock lock(pso_mutex);
    const auto key = reinterpret_cast<std::uintptr_t>(*output);
    pso_metadata[key] = metadata;
    if (metadata.substituted_vertex_shader == kBillboardTargetVertexShader) {
      (void)darktidevr::producer::mark_billboard_pipeline(
          reinterpret_cast<ID3D12PipelineState*>(*output));
      write_billboard_pso_identity("target-load-stream", key, metadata);
    }
  }
  return result;
}

HRESULT STDMETHODCALLTYPE load_compute_pipeline_hook(
    ID3D12PipelineLibrary* library, LPCWSTR name,
    const D3D12_COMPUTE_PIPELINE_STATE_DESC* description, REFIID iid,
    void** output) {
  diagnostic_compute_pipeline_load_count.fetch_add(1,
                                                   std::memory_order_relaxed);
  if (description) {
    dump_cluster_compute_shader_if_target(description->CS);
  }
  const auto result = original_load_compute_pipeline(library, name,
                                                      description, iid,
                                                      output);
  if (SUCCEEDED(result) && description && output && *output) {
    PsoMetadata metadata{};
    metadata.kind = 'C';
    metadata.compute_shader = hash_bytecode(description->CS);
    std::scoped_lock lock(pso_mutex);
    pso_metadata[reinterpret_cast<std::uintptr_t>(*output)] = metadata;
  }
  return result;
}

HRESULT STDMETHODCALLTYPE load_pipeline_hook(
    ID3D12PipelineLibrary1* library, LPCWSTR name,
    const D3D12_PIPELINE_STATE_STREAM_DESC* description, REFIID iid,
    void** output) {
  diagnostic_stream_pipeline_load_count.fetch_add(1,
                                                  std::memory_order_relaxed);
  std::vector<std::uint8_t> replacement_stream;
  D3D12_PIPELINE_STATE_STREAM_DESC replacement_description{};
  bool substituted{};
  bool pixel_substituted{};
  std::uint64_t original_vertex_shader{};
  const auto* effective_description = description;
  if (description && description->pPipelineStateSubobjectStream &&
      description->SizeInBytes > 0) {
    const auto* bytes = static_cast<const std::uint8_t*>(
        description->pPipelineStateSubobjectStream);
    replacement_stream.assign(bytes, bytes + description->SizeInBytes);
    original_vertex_shader =
        inspect_pipeline_stream(*description, &replacement_stream,
                                &substituted, &pixel_substituted)
            .vertex_shader;
    if (substituted || pixel_substituted) {
      replacement_description = *description;
      replacement_description.pPipelineStateSubobjectStream =
          replacement_stream.data();
      effective_description = &replacement_description;
    }
  }
  HRESULT result{};
  if (substituted || pixel_substituted) {
    ComPtr<ID3D12Device2> device;
    result = FAILED(library->GetDevice(IID_PPV_ARGS(&device)))
                 ? E_NOINTERFACE
                 : original_create_pipeline_state_stream(
                       device.Get(), effective_description, iid, output);
  } else {
    result = original_load_pipeline(library, name, effective_description, iid,
                                    output);
  }
  if (FAILED(result) && (substituted || pixel_substituted)) {
    if (substituted) {
      record_billboard_shader_creation_result(original_vertex_shader, false);
    }
    if (pixel_substituted) {
      billboard_pixel_shader_probe_creation_reject_count.fetch_add(
          1, std::memory_order_relaxed);
    }
    result = original_load_pipeline(library, name, description, iid, output);
    substituted = false;
    pixel_substituted = false;
  }
  if (SUCCEEDED(result) && substituted) {
    record_billboard_shader_creation_result(original_vertex_shader, true);
  }
  if (SUCCEEDED(result) && pixel_substituted) {
    billboard_pixel_shader_probe_applied_count.fetch_add(
        1, std::memory_order_relaxed);
  }
  if (SUCCEEDED(result) && description && output && *output) {
    auto metadata = inspect_pipeline_stream(*description);
    preserve_billboard_substitution(metadata, original_vertex_shader,
                                    substituted);
    ComPtr<ID3D12Device2> ui_device;
    if (needs_world_ui_alpha_pipeline(metadata) && SUCCEEDED(library->GetDevice(IID_PPV_ARGS(&ui_device))))
      prepare_world_ui_alpha_pipeline(ui_device.Get(),
          (substituted || pixel_substituted) ? *effective_description : *description, metadata);
    record_pso_shader_mapping_if_requested(
        reinterpret_cast<ID3D12PipelineState*>(*output), metadata);
    std::scoped_lock lock(pso_mutex);
    pso_metadata[reinterpret_cast<std::uintptr_t>(*output)] = metadata;
    if (metadata.substituted_vertex_shader == kBillboardTargetVertexShader) {
      (void)darktidevr::producer::mark_billboard_pipeline(
          reinterpret_cast<ID3D12PipelineState*>(*output));
    }
  }
  return result;
}

HRESULT STDMETHODCALLTYPE close_hook(ID3D12GraphicsCommandList* commands) {
  if (marker_log != INVALID_HANDLE_VALUE ||
      focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    const auto found = command_traces.find(commands);
    if (found != command_traces.end()) {
      for (const auto& [key, counts] : found->second.passes) {
        PsoMetadata metadata{};
        {
          std::scoped_lock pso_lock(pso_mutex);
          const auto pso_found = pso_metadata.find(key.pso);
          if (pso_found != pso_metadata.end()) {
            metadata = pso_found->second;
          }
        }
        write_marker_log(
            "%llu\t%lu\tCL=%p\tPASS\teye=%d\tvpx=%u\tvpy=%u\tvpw=%u\tvph=%u\tpso=%p\tsig=%p\trtcount=%u\trtv=%llu\tdsvh=%llu\tdraw=%llu\tindexed=%llu\tdispatch=%llu\tbind=%llu\ttables=%llu\tconstants=%llu\tcbvs=%llu\tsrvs=%llu\tuavs=%llu\tbindsamples=%llu\tkind=%c\tvs=%llu\tps=%llu\tcs=%llu\tblob=%llu\tnumrt=%u\trtfmt=%u\tdsv=%u\tblend=%u\tdepth=%u\r\n",
            marker_sequence.fetch_add(1, std::memory_order_relaxed),
            GetCurrentThreadId(), static_cast<void*>(commands), key.eye,
            key.viewport_x, key.viewport_y, key.viewport_width,
            key.viewport_height,
            reinterpret_cast<void*>(key.pso),
            reinterpret_cast<void*>(key.root_signature),
            key.render_target_count,
            key.render_target, key.depth_target, counts.draw,
            counts.draw_indexed, counts.dispatch, counts.binding_hash,
            counts.table_hash, counts.constant_hash, counts.cbv_hash,
            counts.srv_hash, counts.uav_hash, counts.binding_samples,
            metadata.kind,
            metadata.vertex_shader, metadata.pixel_shader,
            metadata.compute_shader, metadata.cached_blob,
            metadata.render_target_count,
            static_cast<unsigned>(metadata.render_target_format),
            static_cast<unsigned>(metadata.depth_format),
            metadata.blend_enabled ? 1U : 0U,
            metadata.depth_enabled ? 1U : 0U);
        write_marker_log(
            "%llu\t%lu\tCL=%p\tBINDROOTS\teye=%d\tvpx=%u\tvpy=%u\tvpw=%u\tvph=%u\tpso=%p\tsig=%p\tt0=%llu\tt1=%llu\tt2=%llu\tt3=%llu\tt4=%llu\tt5=%llu\tt6=%llu\tt7=%llu\tt8=%llu\tt9=%llu\tt10=%llu\tt11=%llu\tt12=%llu\tt13=%llu\tt14=%llu\tt15=%llu\tc0=%llu\tc1=%llu\tc2=%llu\tc3=%llu\tc4=%llu\tc5=%llu\tc6=%llu\tc7=%llu\tc8=%llu\tc9=%llu\tc10=%llu\tc11=%llu\tc12=%llu\tc13=%llu\tc14=%llu\tc15=%llu\r\n",
            marker_sequence.fetch_add(1, std::memory_order_relaxed),
            GetCurrentThreadId(), static_cast<void*>(commands), key.eye,
            key.viewport_x, key.viewport_y, key.viewport_width,
            key.viewport_height, reinterpret_cast<void*>(key.pso),
            reinterpret_cast<void*>(key.root_signature),
            counts.table_slot_hashes[0], counts.table_slot_hashes[1],
            counts.table_slot_hashes[2], counts.table_slot_hashes[3],
            counts.table_slot_hashes[4], counts.table_slot_hashes[5],
            counts.table_slot_hashes[6], counts.table_slot_hashes[7],
            counts.table_slot_hashes[8], counts.table_slot_hashes[9],
            counts.table_slot_hashes[10], counts.table_slot_hashes[11],
            counts.table_slot_hashes[12], counts.table_slot_hashes[13],
            counts.table_slot_hashes[14], counts.table_slot_hashes[15],
            counts.cbv_slot_hashes[0], counts.cbv_slot_hashes[1],
            counts.cbv_slot_hashes[2], counts.cbv_slot_hashes[3],
            counts.cbv_slot_hashes[4], counts.cbv_slot_hashes[5],
            counts.cbv_slot_hashes[6], counts.cbv_slot_hashes[7],
            counts.cbv_slot_hashes[8], counts.cbv_slot_hashes[9],
            counts.cbv_slot_hashes[10], counts.cbv_slot_hashes[11],
            counts.cbv_slot_hashes[12], counts.cbv_slot_hashes[13],
            counts.cbv_slot_hashes[14], counts.cbv_slot_hashes[15]);
        write_marker_log(
            "%llu\t%lu\tCL=%p\tBINDRES\teye=%d\tvpx=%u\tvpy=%u\tvpw=%u\tvph=%u\tpso=%p\tsig=%p\tr0=%llu\tr1=%llu\tr2=%llu\tr3=%llu\tr4=%llu\tr5=%llu\tr6=%llu\tr7=%llu\tr8=%llu\tr9=%llu\tr10=%llu\tr11=%llu\tr12=%llu\tr13=%llu\tr14=%llu\tr15=%llu\tl0=%llu\tl1=%llu\tl2=%llu\tl3=%llu\tl4=%llu\tl5=%llu\tl6=%llu\tl7=%llu\tl8=%llu\tl9=%llu\tl10=%llu\tl11=%llu\tl12=%llu\tl13=%llu\tl14=%llu\tl15=%llu\r\n",
            marker_sequence.fetch_add(1, std::memory_order_relaxed),
            GetCurrentThreadId(), static_cast<void*>(commands), key.eye,
            key.viewport_x, key.viewport_y, key.viewport_width,
            key.viewport_height, reinterpret_cast<void*>(key.pso),
            reinterpret_cast<void*>(key.root_signature),
            counts.table_resource_hashes[0], counts.table_resource_hashes[1],
            counts.table_resource_hashes[2], counts.table_resource_hashes[3],
            counts.table_resource_hashes[4], counts.table_resource_hashes[5],
            counts.table_resource_hashes[6], counts.table_resource_hashes[7],
            counts.table_resource_hashes[8], counts.table_resource_hashes[9],
            counts.table_resource_hashes[10], counts.table_resource_hashes[11],
            counts.table_resource_hashes[12], counts.table_resource_hashes[13],
            counts.table_resource_hashes[14], counts.table_resource_hashes[15],
            counts.table_layout_hashes[0], counts.table_layout_hashes[1],
            counts.table_layout_hashes[2], counts.table_layout_hashes[3],
            counts.table_layout_hashes[4], counts.table_layout_hashes[5],
            counts.table_layout_hashes[6], counts.table_layout_hashes[7],
            counts.table_layout_hashes[8], counts.table_layout_hashes[9],
            counts.table_layout_hashes[10], counts.table_layout_hashes[11],
            counts.table_layout_hashes[12], counts.table_layout_hashes[13],
            counts.table_layout_hashes[14], counts.table_layout_hashes[15]);
        const auto& s4a = counts.table4_descriptors[0];
        const auto& s4b = counts.table4_descriptors[1];
        const auto& s7a = counts.table7_descriptors[0];
        write_marker_log(
            "%llu\t%lu\tCL=%p\tBINDDESC\teye=%d\tvpx=%u\tvpy=%u\tvpw=%u\tvph=%u\tpso=%p\tsig=%p\ts4ok=%u\ts4a=%c,%p,%llu,%u,%llu,%u,%u,%llu,%u,%u\ts4b=%c,%p,%llu,%u,%llu,%u,%u,%llu,%u,%u\ts7ok=%u\ts7a=%c,%p,%llu,%u,%llu,%u,%u,%llu,%u,%u\r\n",
            marker_sequence.fetch_add(1, std::memory_order_relaxed),
            GetCurrentThreadId(), static_cast<void*>(commands), key.eye,
            key.viewport_x, key.viewport_y, key.viewport_width,
            key.viewport_height, reinterpret_cast<void*>(key.pso),
            reinterpret_cast<void*>(key.root_signature),
            counts.table4_descriptors_captured ? 1U : 0U, s4a.kind,
            reinterpret_cast<void*>(s4a.resource), s4a.gpu_address,
            s4a.dimension, s4a.width, s4a.height, s4a.format,
            s4a.first_element, s4a.element_count, s4a.structure_stride,
            s4b.kind, reinterpret_cast<void*>(s4b.resource), s4b.gpu_address,
            s4b.dimension, s4b.width, s4b.height, s4b.format,
            s4b.first_element, s4b.element_count, s4b.structure_stride,
            counts.table7_descriptors_captured ? 1U : 0U, s7a.kind,
            reinterpret_cast<void*>(s7a.resource), s7a.gpu_address,
            s7a.dimension, s7a.width, s7a.height, s7a.format,
            s7a.first_element, s7a.element_count, s7a.structure_stride);
      }
    }
  }
  if (direct_menu_render_list_count.load(std::memory_order_acquire) != 0) {
    std::scoped_lock lock(state_mutex);
    const auto found = direct_menu_render_lists.find(commands);
    if (found != direct_menu_render_lists.end() && found->second) {
      D3D12_RESOURCE_BARRIER barrier{};
      barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      barrier.Transition.pResource = found->second.Get();
      barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
      barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COMMON;
      barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
      commands->ResourceBarrier(1, &barrier);
    }
  }
  return original_close(commands);
}

HRESULT STDMETHODCALLTYPE reset_hook(ID3D12GraphicsCommandList* commands,
                                     ID3D12CommandAllocator* allocator,
                                     ID3D12PipelineState* initial_state) {
  const auto reset_result = original_reset(commands, allocator, initial_state);
  if (FAILED(reset_result)) {
    // The old recording is still owned by D3D12. Retain every resource and
    // trace associated with it until a later Reset actually succeeds.
    return reset_result;
  }
  if (auto* readback = billboard_readback.load(std::memory_order_acquire)) {
    readback->retired(commands);
    std::scoped_lock lock(trace_mutex);
    billboard_resource_states.erase(commands);
  }
  const auto focused =
      focused_trace_phase.load(std::memory_order_relaxed) != 0;
  darktidevr::producer::observe_ngx_command_reset(commands);
  darktidevr::producer::reset_generated_stereo(commands);
  const auto recording_generation =
      focused ? command_recording_generation.fetch_add(
                    1, std::memory_order_relaxed) + 1
              : 0;
  if (world_ui_capture_requested() || marker_log != INVALID_HANDLE_VALUE ||
      menu_direct_capture_enabled.load(std::memory_order_relaxed) ||
      billboard_horizon_lock_enabled.load(std::memory_order_relaxed) ||
      cluster_light_visibility_fix_requested.load(std::memory_order_relaxed) ||
      focused) {
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    trace = {};
    trace.recording_generation = recording_generation;
    trace.pso = reinterpret_cast<std::uintptr_t>(initial_state);
  }
  if (rich_center_sbs_remap_enabled.load(std::memory_order_relaxed)) {
    std::scoped_lock lock(viewport_remap_mutex);
    viewport_remap_states.erase(commands);
  }
  {
    std::scoped_lock lock(boundary_capture_mutex);
    present_transition_resources.erase(commands);
    camera_output_resources.erase(commands);
    camera_output_source_states.erase(commands);
    // Menu completion belongs to the command-list recording just retired by
    // this successful Reset.  A list can be reset without ever being executed;
    // retaining these entries would make a later unrelated recording publish
    // the old menu resource and keep its COM reference alive across resize.
    menu_output_resources.erase(commands);
    menu_output_source_states.erase(commands);
    if (focused) {
      command_recording_generations[commands] = recording_generation;
    } else {
      command_recording_generations.erase(commands);
    }
    const auto candidates = camera_output_candidates.find(commands);
    if (candidates != camera_output_candidates.end()) {
      candidates->second.clear();
    }
    command_transition_ordinals.erase(commands);
    command_marker_stacks.erase(commands);
  }
  if (direct_menu_render_list_count.load(std::memory_order_acquire) != 0) {
    std::scoped_lock lock(state_mutex);
    if (direct_menu_render_lists.erase(commands) != 0) {
      direct_menu_render_list_count.fetch_sub(1, std::memory_order_acq_rel);
    }
  }
  return reset_result;
}

void STDMETHODCALLTYPE execute_bundle_hook(
    ID3D12GraphicsCommandList* commands,
    ID3D12GraphicsCommandList* bundle_commands) {
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    const auto& parent = command_traces[commands];
    const auto& bundle = command_traces[bundle_commands];
    write_focused_log(
        "phase=%d\tframe=%llu\tCL=%p\tBUNDLE_EXEC\tbundle=%p\t"
        "parent_rtv=%llu\tparent_dsv=%llu\tparent_rt_count=%u\t"
        "parent_vp=%u,%u,%u,%u\tparent_sc=%ld,%ld,%ld,%ld\t"
        "bundle_pso=%p\tbundle_sig=%p\tbundle_vp=%u,%u,%u,%u\t"
        "bundle_sc=%ld,%ld,%ld,%ld\r\n",
        focused_trace_phase.load(std::memory_order_relaxed),
        present_count.load(std::memory_order_relaxed), commands,
        bundle_commands, parent.render_target, parent.depth_target,
        parent.render_target_count, parent.viewport_x, parent.viewport_y,
        parent.viewport_width, parent.viewport_height, parent.scissor.left,
        parent.scissor.top, parent.scissor.right, parent.scissor.bottom,
        reinterpret_cast<void*>(bundle.pso),
        reinterpret_cast<void*>(bundle.root_signature), bundle.viewport_x,
        bundle.viewport_y, bundle.viewport_width, bundle.viewport_height,
        bundle.scissor.left, bundle.scissor.top, bundle.scissor.right,
        bundle.scissor.bottom);
  }
  original_execute_bundle(commands, bundle_commands);
}

void STDMETHODCALLTYPE begin_render_pass_hook(
    ID3D12GraphicsCommandList4* commands, UINT render_target_count,
    const D3D12_RENDER_PASS_RENDER_TARGET_DESC* render_targets,
    const D3D12_RENDER_PASS_DEPTH_STENCIL_DESC* depth_stencil,
    D3D12_RENDER_PASS_FLAGS flags) {
  if (billboard_readback_accepting.load(std::memory_order_relaxed) ||
      world_ui_capture_requested() || marker_log != INVALID_HANDLE_VALUE ||
      menu_direct_capture_enabled.load(std::memory_order_relaxed) ||
      focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    trace.render_pass_active = true;
    if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
      trace.render_pass_count++;
    }
    trace.render_target_count = render_target_count;
    trace.render_target = render_target_count > 0 && render_targets
                              ? render_targets[0].cpuDescriptor.ptr
                              : 0;
    trace.depth_target = depth_stencil ? depth_stencil->cpuDescriptor.ptr : 0;
    if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
      write_focused_log(
          "phase=%d\tframe=%llu\tCL=%p\tBEGIN_RENDER_PASS\t"
          "rtv_count=%u\trtv=%llu\tdsv=%llu\tflags=%u\t"
          "vp=%u,%u,%u,%u\tsc=%ld,%ld,%ld,%ld\r\n",
          focused_trace_phase.load(std::memory_order_relaxed),
          present_count.load(std::memory_order_relaxed), commands,
          render_target_count, trace.render_target, trace.depth_target,
          static_cast<unsigned>(flags), trace.viewport_x, trace.viewport_y,
          trace.viewport_width, trace.viewport_height, trace.scissor.left,
          trace.scissor.top, trace.scissor.right, trace.scissor.bottom);
    }
  }
  original_begin_render_pass(commands, render_target_count, render_targets,
                             depth_stencil, flags);
}

void STDMETHODCALLTYPE end_render_pass_hook(ID3D12GraphicsCommandList4* commands) {
  original_end_render_pass(commands);
  if (billboard_readback_accepting.load(std::memory_order_relaxed) ||
      world_ui_capture_requested() || marker_log != INVALID_HANDLE_VALUE ||
      menu_direct_capture_enabled.load(std::memory_order_relaxed) ||
      focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    trace.render_pass_active = false;
    if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
      write_focused_log(
          "phase=%d\tframe=%llu\tCL=%p\tEND_RENDER_PASS\t"
          "rtv=%llu\tdsv=%llu\r\n",
          focused_trace_phase.load(std::memory_order_relaxed),
          present_count.load(std::memory_order_relaxed), commands,
          trace.render_target, trace.depth_target);
    }
    trace.render_target = 0;
    trace.depth_target = 0;
    trace.render_target_count = 0;
  }
}

DescriptorInfo descriptor_snapshot(std::uint64_t handle);

std::optional<BufferResourceInfo> resolve_buffer_resource(
    std::uint64_t gpu_address) {
  std::scoped_lock lock(buffer_resource_mutex);
  for (auto it = buffer_resources.rbegin(); it != buffer_resources.rend(); ++it) {
    if (gpu_address >= it->gpu_start &&
        gpu_address - it->gpu_start < it->size) {
      return *it;
    }
  }
  return std::nullopt;
}

bool safe_copy_bytes(void* destination, const void* source,
                     std::size_t size);

bool copy_tracked_buffer_bytes(std::uint64_t gpu_address,
                               std::byte* destination,
                               std::size_t byte_count,
                               BufferResourceInfo* resource_snapshot,
                               bool* used_persistent_mapping,
                               bool* used_staging_mapping) {
  std::scoped_lock lock(buffer_resource_mutex);
  for (auto it = buffer_resources.rbegin(); it != buffer_resources.rend();
       ++it) {
    if (gpu_address < it->gpu_start ||
        gpu_address - it->gpu_start + byte_count > it->size) {
      continue;
    }
    if (resource_snapshot) {
      *resource_snapshot = *it;
    }
    const auto offset = gpu_address - it->gpu_start;
    const std::byte* source{};
    if (it->mapped && it->mapped_base) {
      source = it->mapped_base + offset;
      if (used_persistent_mapping) {
        *used_persistent_mapping = true;
      }
    } else if (it->staging_base &&
               offset + byte_count <= it->staging_size) {
      source = it->staging_base + offset;
      if (used_staging_mapping) {
        *used_staging_mapping = true;
      }
    }
    return source &&
           safe_copy_bytes(destination, source, byte_count);
  }
  return false;
}

std::optional<ClusterConstantBufferCopy> resolve_cluster_constant_copy(
    ID3D12Resource* destination, std::uint64_t destination_offset,
    std::size_t byte_count) {
  std::scoped_lock lock(cluster_constant_copy_mutex);
  const auto available = (std::min<std::uint64_t>)(
      cluster_constant_copy_count, cluster_constant_copies.size());
  for (std::uint64_t distance = 0; distance < available; ++distance) {
    const auto sequence = cluster_constant_copy_count - distance - 1;
    const auto& copy =
        cluster_constant_copies[sequence % cluster_constant_copies.size()];
    if (copy.destination == destination &&
        destination_offset >= copy.destination_offset &&
        destination_offset - copy.destination_offset + byte_count <=
            copy.bytes) {
      return copy;
    }
  }
  return std::nullopt;
}

void observe_billboard_cbv(const DescriptorInfo& descriptor) {
  if (descriptor.kind != 'C' || descriptor.gpu_address == 0) {
    return;
  }
  billboard_exact_cbv_descriptor_count.fetch_add(1,
                                                   std::memory_order_relaxed);
  const auto resource = resolve_buffer_resource(descriptor.gpu_address);
  if (!resource || !resource->resource) {
    return;
  }
  billboard_exact_buffer_resource_count.fetch_add(1,
                                                   std::memory_order_relaxed);
  const auto heap_index = static_cast<std::size_t>(resource->heap_type);
  if (heap_index < billboard_exact_heap_type_counts.size()) {
    billboard_exact_heap_type_counts[heap_index].fetch_add(
        1, std::memory_order_relaxed);
  }

  const auto resource_offset = descriptor.gpu_address - resource->gpu_start;
  const auto readable_size = (std::min<std::uint64_t>)(
      descriptor.width == 0 ? 132 : descriptor.width,
      resource->size - resource_offset);
  const bool used_staging_mapping =
      resource->staging_base &&
      resource_offset + readable_size <= resource->size;
  if (billboard_direct_write_enabled.load(std::memory_order_relaxed) &&
      resource->heap_type == D3D12_HEAP_TYPE_UPLOAD && readable_size >= 8 &&
      original_resource_map && original_resource_unmap) {
    void* direct_mapping{};
    const D3D12_RANGE no_reads{0, 0};
    if (SUCCEEDED(original_resource_map(resource->resource, 0, &no_reads,
                                        &direct_mapping)) &&
        direct_mapping) {
      auto* values = reinterpret_cast<float*>(
          static_cast<std::byte*>(direct_mapping) + resource_offset);
      std::atomic_ref<float>(values[0]).store(
          billboard_view_basis[0].load(std::memory_order_relaxed),
          std::memory_order_relaxed);
      std::atomic_ref<float>(values[1]).store(
          billboard_view_basis[1].load(std::memory_order_relaxed),
          std::memory_order_relaxed);
      const D3D12_RANGE written{
          static_cast<SIZE_T>(resource_offset),
          static_cast<SIZE_T>(resource_offset + 2 * sizeof(float))};
      original_resource_unmap(resource->resource, 0, &written);
      billboard_direct_patch_count.fetch_add(1, std::memory_order_relaxed);
      billboard_basis_patch_count.fetch_add(1, std::memory_order_relaxed);
    }
  }
  bool first_observation{};
  {
    std::scoped_lock lock(buffer_resource_mutex);
    first_observation =
        (used_staging_mapping ? billboard_staging_tested_cbvs
                              : billboard_tested_cbvs)
            .insert(descriptor.gpu_address)
            .second;
  }
  if (!first_observation) {
    return;
  }
  void* mapped = used_staging_mapping
                     ? resource->staging_base
                     : resource->mapped && resource->mapped_subresource == 0
                           ? resource->mapped_base
                           : nullptr;
  const bool used_tracked_mapping = !used_staging_mapping && mapped != nullptr;
  bool mapped_for_observation{};
  const D3D12_RANGE cpu_read_range{
      static_cast<SIZE_T>(resource_offset),
      static_cast<SIZE_T>(resource_offset + readable_size)};
  if (used_staging_mapping || used_tracked_mapping ||
      (SUCCEEDED(resource->resource->Map(0, &cpu_read_range, &mapped)) &&
       mapped && (mapped_for_observation = true))) {
    billboard_exact_map_success_count.fetch_add(1,
                                                 std::memory_order_relaxed);
    billboard_selected_gpu_address.store(descriptor.gpu_address,
                                          std::memory_order_relaxed);
    billboard_selected_size.store(readable_size, std::memory_order_relaxed);
    billboard_selected_cpu_address.store(
        used_staging_mapping
            ? reinterpret_cast<std::uintptr_t>(resource->staging_base +
                                               resource_offset)
            : used_tracked_mapping
            ? reinterpret_cast<std::uintptr_t>(
                  static_cast<std::byte*>(mapped) + resource_offset)
            : 0,
        std::memory_order_release);
    const auto sample_index =
        (used_staging_mapping ? billboard_staging_log_count
                              : billboard_cbv_log_count)
            .fetch_add(1, std::memory_order_relaxed);
    if (sample_index < 32 && readable_size >= sizeof(float)) {
      std::scoped_lock log_lock(billboard_cbv_log_mutex);
      std::array<wchar_t, MAX_PATH> temp{};
      if (GetTempPathW(static_cast<DWORD>(temp.size()), temp.data()) != 0) {
        std::wstring path(temp.data());
        path += used_staging_mapping ? L"darktidevr-billboard-staging.tsv"
                                     : L"darktidevr-billboard-cbv.tsv";
        const DWORD disposition =
            (used_staging_mapping ? billboard_staging_log_initialized
                                  : billboard_cbv_log_initialized)
                ? OPEN_ALWAYS
                : CREATE_ALWAYS;
        HANDLE log = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                                 nullptr, disposition, FILE_ATTRIBUTE_NORMAL,
                                 nullptr);
        if (log != INVALID_HANDLE_VALUE) {
          if (used_staging_mapping) {
            billboard_staging_log_initialized = true;
          } else {
            billboard_cbv_log_initialized = true;
          }
          std::array<char, 8192> line{};
          int length = std::snprintf(
              line.data(), line.size(),
              "%llu\tgpu=%llu\tbase=%llu\toffset=%llu\tcbv_size=%llu\theap=%u"
              "\ttracked=%u\tstaging=%u\tcpu=%p",
              static_cast<unsigned long long>(sample_index),
              static_cast<unsigned long long>(descriptor.gpu_address),
              static_cast<unsigned long long>(resource->gpu_start),
              static_cast<unsigned long long>(resource_offset),
              static_cast<unsigned long long>(descriptor.width),
              static_cast<unsigned>(resource->heap_type),
              used_tracked_mapping ? 1U : 0U,
              used_staging_mapping ? 1U : 0U,
              used_staging_mapping
                  ? static_cast<void*>(resource->staging_base + resource_offset)
                  : used_tracked_mapping
                  ? static_cast<void*>(static_cast<std::byte*>(mapped) +
                                       resource_offset)
                  : nullptr);
          if (resource->last_map_stack_count > 0) {
            billboard_selected_map_stack_count.fetch_add(
                1, std::memory_order_relaxed);
          }
          for (USHORT stack_index = 0;
               stack_index < resource->last_map_stack_count && length > 0 &&
               static_cast<std::size_t>(length) < line.size();
               ++stack_index) {
            const auto frame = resource->last_map_stack[stack_index];
            HMODULE module{};
            std::array<wchar_t, 32768> module_path{};
            const char* module_label = "unknown";
            std::array<char, MAX_PATH> module_name{};
            std::uintptr_t module_offset =
                reinterpret_cast<std::uintptr_t>(frame);
            if (GetModuleHandleExW(
                    GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                        GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                    reinterpret_cast<LPCWSTR>(frame), &module)) {
              const auto path_length = GetModuleFileNameW(
                  module, module_path.data(),
                  static_cast<DWORD>(module_path.size()));
              if (path_length > 0 && path_length < module_path.size()) {
                const auto* base_name = module_path.data();
                for (const auto* cursor = module_path.data(); *cursor; ++cursor) {
                  if (*cursor == L'\\' || *cursor == L'/') {
                    base_name = cursor + 1;
                  }
                }
                const auto converted = WideCharToMultiByte(
                    CP_UTF8, 0, base_name, -1, module_name.data(),
                    static_cast<int>(module_name.size()), nullptr, nullptr);
                if (converted > 0) {
                  module_label = module_name.data();
                }
              }
              module_offset -= reinterpret_cast<std::uintptr_t>(module);
            }
            length += std::snprintf(
                line.data() + length, line.size() - length,
                "\tstack%u=%s+0x%llx", static_cast<unsigned>(stack_index),
                module_label, static_cast<unsigned long long>(module_offset));
          }
          const auto float_count = (std::min<std::size_t>)(
              readable_size / sizeof(float), 33);
          const auto* values = reinterpret_cast<const float*>(
              static_cast<const std::byte*>(mapped) + resource_offset);
          for (std::size_t i = 0; i < float_count && length > 0 &&
                                  static_cast<std::size_t>(length) < line.size();
               ++i) {
            length += std::snprintf(line.data() + length, line.size() - length,
                                    "\tf%zu=%.9g", i, values[i]);
          }
          if (length > 0 && static_cast<std::size_t>(length + 2) < line.size()) {
            line[length++] = '\r';
            line[length++] = '\n';
            DWORD written{};
            WriteFile(log, line.data(), static_cast<DWORD>(length), &written,
                      nullptr);
          }
          CloseHandle(log);
        }
      }
    }
    if (mapped_for_observation) {
      const D3D12_RANGE no_cpu_writes{0, 0};
      resource->resource->Unmap(0, &no_cpu_writes);
    }
  } else {
    billboard_exact_map_failure_count.fetch_add(1,
                                                 std::memory_order_relaxed);
  }
}

void log_target_billboard_cbv(const DescriptorInfo& descriptor) {
  const auto attempt = billboard_target_cbv_attempt_count.fetch_add(
      1, std::memory_order_relaxed);
  if (attempt < 2048) {
    std::array<wchar_t, MAX_PATH> temporary_path{};
    if (GetTempPathW(static_cast<DWORD>(temporary_path.size()),
                     temporary_path.data()) != 0) {
      const auto path = std::wstring(temporary_path.data()) +
                        L"darktidevr-billboard-target-attempts.tsv";
      HANDLE log = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                               nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                               nullptr);
      if (log != INVALID_HANDLE_VALUE) {
        char line[384]{};
        const auto length = std::snprintf(
            line, sizeof(line),
            "attempt=%llu\tframe=%llu\tkind=%c\tgpu=%llu\twidth=%llu\r\n",
            static_cast<unsigned long long>(attempt),
            static_cast<unsigned long long>(
                present_count.load(std::memory_order_relaxed)),
            descriptor.kind, static_cast<unsigned long long>(
                                 descriptor.gpu_address),
            static_cast<unsigned long long>(descriptor.width));
        if (length > 0) {
          DWORD written{};
          WriteFile(log, line, static_cast<DWORD>(length), &written, nullptr);
        }
        CloseHandle(log);
      }
    }
  }
  if (descriptor.kind != 'C' || descriptor.gpu_address == 0) {
    return;
  }
  const auto frame = present_count.load(std::memory_order_relaxed);
  const auto resource = resolve_buffer_resource(descriptor.gpu_address);
  if (!resource || !resource->resource) {
    return;
  }
  const auto resource_offset = descriptor.gpu_address - resource->gpu_start;
  if (resource_offset >= resource->size) {
    return;
  }
  const auto readable_size = (std::min<std::uint64_t>)(
      descriptor.width == 0 ? 512 : descriptor.width,
      resource->size - resource_offset);
  void* mapped = resource->staging_base
                     ? resource->staging_base
                     : resource->mapped && resource->mapped_subresource == 0
                           ? resource->mapped_base
                           : nullptr;
  bool mapped_for_observation{};
  const D3D12_RANGE read_range{
      static_cast<SIZE_T>(resource_offset),
      static_cast<SIZE_T>(resource_offset + readable_size)};
  if (!mapped &&
      !(SUCCEEDED(resource->resource->Map(0, &read_range, &mapped)) && mapped &&
        (mapped_for_observation = true))) {
    return;
  }
  if (billboard_target_cbv_last_frame.exchange(frame,
                                                std::memory_order_relaxed) ==
      frame) {
    if (mapped_for_observation) {
      const D3D12_RANGE no_cpu_writes{0, 0};
      resource->resource->Unmap(0, &no_cpu_writes);
    }
    return;
  }
  const auto sample = billboard_target_cbv_log_count.fetch_add(
      1, std::memory_order_relaxed);
  if (sample >= 2048) {
    if (mapped_for_observation) {
      const D3D12_RANGE no_cpu_writes{0, 0};
      resource->resource->Unmap(0, &no_cpu_writes);
    }
    return;
  }
  const auto* bytes = resource->staging_base
                          ? resource->staging_base + resource_offset
                          : static_cast<const std::byte*>(mapped) +
                                resource_offset;
  std::array<wchar_t, MAX_PATH> temporary_path{};
  if (GetTempPathW(static_cast<DWORD>(temporary_path.size()),
                   temporary_path.data()) != 0) {
    const auto path = std::wstring(temporary_path.data()) +
                      L"darktidevr-billboard-target-cbv.tsv";
    HANDLE log = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                             nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                             nullptr);
    if (log != INVALID_HANDLE_VALUE) {
      std::array<char, 16384> line{};
      darktidevr::core::SharedHeadPoseSample head_pose{};
      const bool has_head_pose = shared_head_pose_reader().read(head_pose);
      int length = std::snprintf(
          line.data(), line.size(),
          "frame=%llu\tsample=%llu\tgpu=%llu\toffset=%llu\tcbv_size=%llu"
          "\tpose_valid=%u\tpose_sequence=%llu"
          "\tqx=%.9g\tqy=%.9g\tqz=%.9g\tqw=%.9g",
          static_cast<unsigned long long>(frame),
          static_cast<unsigned long long>(sample),
          static_cast<unsigned long long>(descriptor.gpu_address),
          static_cast<unsigned long long>(resource_offset),
          static_cast<unsigned long long>(descriptor.width),
          has_head_pose ? 1U : 0U,
          static_cast<unsigned long long>(head_pose.sequence),
          head_pose.pose.orientation.x, head_pose.pose.orientation.y,
          head_pose.pose.orientation.z, head_pose.pose.orientation.w);
      const auto float_count = (std::min<std::size_t>)(
          readable_size / sizeof(float), 128);
      const auto* values = reinterpret_cast<const float*>(bytes);
      for (std::size_t i = 0; i < float_count && length > 0 &&
                              static_cast<std::size_t>(length) < line.size();
           ++i) {
        length += std::snprintf(line.data() + length, line.size() - length,
                                "\tf%zu=%.9g", i, values[i]);
      }
      if (length > 0 && static_cast<std::size_t>(length + 2) < line.size()) {
        line[length++] = '\r';
        line[length++] = '\n';
        DWORD written{};
        WriteFile(log, line.data(), static_cast<DWORD>(length), &written,
                  nullptr);
      }
      CloseHandle(log);
    }
  }
  if (mapped_for_observation) {
    const D3D12_RANGE no_writes{0, 0};
    resource->resource->Unmap(0, &no_writes);
  }
}

std::optional<D3D12_CPU_DESCRIPTOR_HANDLE> descriptor_cpu_handle(
    ID3D12DescriptorHeap* heap, std::uint64_t gpu_handle) {
  if (!heap || gpu_handle == 0) {
    return std::nullopt;
  }
  std::scoped_lock lock(descriptor_mutex);
  const auto found =
      descriptor_heaps.find(reinterpret_cast<std::uintptr_t>(heap));
  if (found == descriptor_heaps.end() || found->second.gpu_start == 0 ||
      found->second.increment == 0 || gpu_handle < found->second.gpu_start) {
    return std::nullopt;
  }
  const auto byte_offset = gpu_handle - found->second.gpu_start;
  if (byte_offset % found->second.increment != 0 ||
      byte_offset >= static_cast<std::uint64_t>(found->second.descriptor_count) *
                         found->second.increment) {
    return std::nullopt;
  }
  return D3D12_CPU_DESCRIPTOR_HANDLE{found->second.cpu_start + byte_offset};
}

bool ensure_billboard_shadow_resources(ID3D12Device* device) {
  std::scoped_lock lock(billboard_shadow_mutex);
  if (billboard_shadow_device) {
    return billboard_shadow_device.Get() == device && billboard_shadow_heap &&
           billboard_shadow_constants && billboard_shadow_mapped;
  }
  if (!device) {
    return false;
  }

  D3D12_DESCRIPTOR_HEAP_DESC heap_description{};
  heap_description.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
  heap_description.NumDescriptors = kBillboardShadowDescriptorCapacity;
  heap_description.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
  ComPtr<ID3D12DescriptorHeap> heap;
  if (FAILED(device->CreateDescriptorHeap(&heap_description,
                                           IID_PPV_ARGS(&heap)))) {
    return false;
  }

  D3D12_HEAP_PROPERTIES properties{};
  properties.Type = D3D12_HEAP_TYPE_UPLOAD;
  D3D12_RESOURCE_DESC resource_description{};
  resource_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
  resource_description.Width =
      static_cast<UINT64>(kBillboardShadowConstantCapacity) * 256;
  resource_description.Height = 1;
  resource_description.DepthOrArraySize = 1;
  resource_description.MipLevels = 1;
  resource_description.SampleDesc.Count = 1;
  resource_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  ComPtr<ID3D12Resource> constants;
  if (FAILED(device->CreateCommittedResource(
          &properties, D3D12_HEAP_FLAG_NONE, &resource_description,
          D3D12_RESOURCE_STATE_GENERIC_READ, nullptr,
          IID_PPV_ARGS(&constants)))) {
    return false;
  }
  void* mapped{};
  const D3D12_RANGE no_cpu_reads{0, 0};
  if (FAILED(constants->Map(0, &no_cpu_reads, &mapped)) || !mapped) {
    return false;
  }

  billboard_shadow_device = device;
  billboard_shadow_heap = std::move(heap);
  billboard_shadow_constants = std::move(constants);
  billboard_shadow_mapped = static_cast<std::byte*>(mapped);
  billboard_shadow_descriptor_increment = device->GetDescriptorHandleIncrementSize(
      D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
  return billboard_shadow_descriptor_increment != 0;
}

struct BillboardBindingOverride {
  bool active{};
  ID3D12DescriptorHeap* original_resource_heap{};
  ID3D12DescriptorHeap* original_sampler_heap{};
  struct Table {
    UINT root_index{};
    D3D12_GPU_DESCRIPTOR_HANDLE original{};
    D3D12_GPU_DESCRIPTOR_HANDLE replacement{};
  };
  std::array<Table, kRootSlotCount> tables{};
  UINT table_count{};
};

BillboardBindingOverride begin_billboard_binding_override(
    ID3D12GraphicsCommandList* commands, std::uintptr_t root_signature,
    UINT billboard_table_index, UINT billboard_table_offset,
    const DescriptorInfo& source_descriptor,
    const std::array<std::uint64_t, kRootSlotCount>& graphics_tables,
    ID3D12DescriptorHeap* original_resource_heap,
    ID3D12DescriptorHeap* original_sampler_heap) {
  BillboardBindingOverride result{};
  billboard_shadow_stage_counts[0].fetch_add(1, std::memory_order_relaxed);
  const auto fail = [&](std::size_t stage) {
    billboard_shadow_stage_counts[stage].fetch_add(1,
                                                   std::memory_order_relaxed);
    return result;
  };
  if (!commands || !original_resource_heap || source_descriptor.kind != 'C' ||
      source_descriptor.gpu_address == 0) {
    return fail(1);
  }

  RootSignatureMetadata metadata{};
  {
    std::scoped_lock lock(root_signature_mutex);
    const auto found = root_signature_metadata.find(root_signature);
    if (found == root_signature_metadata.end()) {
      return fail(2);
    }
    metadata = found->second;
  }

  UINT descriptor_count{};
  for (UINT i = 0; i < metadata.parameter_count; ++i) {
    const auto& parameter = metadata.parameters[i];
    if (parameter.type != D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE ||
        graphics_tables[i] == 0) {
      continue;
    }
    if (parameter.sampler_count != 0) {
      // A descriptor table cannot mix sampler and resource ranges. Preserve it
      // on the original sampler heap while replacing only the resource heap.
      if (parameter.cbv_count != 0 || parameter.srv_count != 0 ||
          parameter.uav_count != 0 || !original_sampler_heap) {
        return fail(3);
      }
      continue;
    }
    if (parameter.descriptor_table_span == 0) {
      return fail(3);
    }
    descriptor_count += parameter.descriptor_table_span;
  }
  if (descriptor_count == 0) {
    return fail(4);
  }

  ComPtr<ID3D12Device> device;
  if (FAILED(commands->GetDevice(IID_PPV_ARGS(&device))) ||
      !ensure_billboard_shadow_resources(device.Get())) {
    return fail(5);
  }
  const UINT constant_index =
      billboard_shadow_constant_cursor.fetch_add(1, std::memory_order_relaxed);
  const UINT descriptor_start = billboard_shadow_descriptor_cursor.fetch_add(
      descriptor_count, std::memory_order_relaxed);
  if (constant_index >= kBillboardShadowConstantCapacity ||
      descriptor_start > kBillboardShadowDescriptorCapacity - descriptor_count) {
    return fail(6);
  }

  const auto source_resource =
      resolve_buffer_resource(source_descriptor.gpu_address);
  if (!source_resource || !source_resource->resource) {
    return fail(7);
  }
  const auto source_offset =
      source_descriptor.gpu_address - source_resource->gpu_start;
  if (source_offset > source_resource->size ||
      source_resource->size - source_offset < 132) {
    return fail(8);
  }
  void* source_mapped{};
  const D3D12_RANGE source_read{
      static_cast<SIZE_T>(source_offset),
      static_cast<SIZE_T>(source_offset +
                          (std::min<std::uint64_t>)(256,
                              source_resource->size - source_offset))};
  if (FAILED(source_resource->resource->Map(0, &source_read, &source_mapped)) ||
      !source_mapped) {
    return fail(9);
  }
  auto* shadow = billboard_shadow_mapped +
                 static_cast<std::size_t>(constant_index) * 256;
  const auto copy_size = (std::min<std::uint64_t>)(
      256, source_resource->size - source_offset);
  std::memset(shadow, 0, 256);
  std::memcpy(shadow, static_cast<const std::byte*>(source_mapped) + source_offset,
              static_cast<std::size_t>(copy_size));
  const D3D12_RANGE no_cpu_writes{0, 0};
  source_resource->resource->Unmap(0, &no_cpu_writes);

  constexpr std::array<std::size_t, 6> float_indices{0, 1, 2, 8, 9, 10};
  auto* shadow_floats = reinterpret_cast<float*>(shadow);
  for (std::size_t i = 0; i < float_indices.size(); ++i) {
    shadow_floats[float_indices[i]] =
        billboard_view_basis[i].load(std::memory_order_relaxed);
  }

  const auto private_cpu_start =
      billboard_shadow_heap->GetCPUDescriptorHandleForHeapStart();
  const auto private_gpu_start =
      billboard_shadow_heap->GetGPUDescriptorHandleForHeapStart();
  UINT destination_offset = descriptor_start;
  D3D12_CPU_DESCRIPTOR_HANDLE billboard_cpu{};
  for (UINT i = 0; i < metadata.parameter_count; ++i) {
    const auto& parameter = metadata.parameters[i];
    if (parameter.type != D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE ||
        graphics_tables[i] == 0) {
      continue;
    }
    if (parameter.sampler_count != 0) {
      const D3D12_GPU_DESCRIPTOR_HANDLE original{graphics_tables[i]};
      result.tables[result.table_count++] = BillboardBindingOverride::Table{
          i, original, original};
      continue;
    }
    const auto source_cpu = descriptor_cpu_handle(
        original_resource_heap, graphics_tables[i]);
    if (!source_cpu) {
      return fail(10);
    }
    D3D12_CPU_DESCRIPTOR_HANDLE destination_cpu{
        private_cpu_start.ptr + static_cast<std::uint64_t>(destination_offset) *
                                    billboard_shadow_descriptor_increment};
    device->CopyDescriptorsSimple(
        parameter.descriptor_table_span, destination_cpu, *source_cpu,
        D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
    if (i == billboard_table_index) {
      billboard_cpu.ptr =
          destination_cpu.ptr +
          static_cast<std::uint64_t>(billboard_table_offset) *
              billboard_shadow_descriptor_increment;
    }
    const D3D12_GPU_DESCRIPTOR_HANDLE original{graphics_tables[i]};
    const D3D12_GPU_DESCRIPTOR_HANDLE replacement{
        private_gpu_start.ptr +
        static_cast<std::uint64_t>(destination_offset) *
            billboard_shadow_descriptor_increment};
    result.tables[result.table_count++] = BillboardBindingOverride::Table{
        i, original, replacement};
    destination_offset += parameter.descriptor_table_span;
  }
  if (billboard_cpu.ptr == 0) {
    return fail(11);
  }
  D3D12_CONSTANT_BUFFER_VIEW_DESC shadow_cbv{};
  shadow_cbv.BufferLocation = billboard_shadow_constants->GetGPUVirtualAddress() +
                              static_cast<UINT64>(constant_index) * 256;
  shadow_cbv.SizeInBytes = 256;
  device->CreateConstantBufferView(&shadow_cbv, billboard_cpu);

  std::array<ID3D12DescriptorHeap*, 2> replacement_heaps{
      billboard_shadow_heap.Get(), original_sampler_heap};
  original_set_descriptor_heaps(commands, original_sampler_heap ? 2U : 1U,
                                replacement_heaps.data());
  for (UINT i = 0; i < result.table_count; ++i) {
    original_set_graphics_root_descriptor_table(
        commands, result.tables[i].root_index, result.tables[i].replacement);
  }
  result.active = true;
  result.original_resource_heap = original_resource_heap;
  result.original_sampler_heap = original_sampler_heap;
  billboard_basis_patch_count.fetch_add(1, std::memory_order_relaxed);
  billboard_shadow_stage_counts[12].fetch_add(1, std::memory_order_relaxed);
  return result;
}

void end_billboard_binding_override(ID3D12GraphicsCommandList* commands,
                                    const BillboardBindingOverride& state) {
  if (!state.active) {
    return;
  }
  std::array<ID3D12DescriptorHeap*, 2> original_heaps{
      state.original_resource_heap, state.original_sampler_heap};
  original_set_descriptor_heaps(commands,
                                state.original_sampler_heap ? 2U : 1U,
                                original_heaps.data());
  for (UINT i = 0; i < state.table_count; ++i) {
    original_set_graphics_root_descriptor_table(
        commands, state.tables[i].root_index, state.tables[i].original);
  }
}

bool apply_billboard_in_place_descriptor_override(
    ID3D12GraphicsCommandList* commands, UINT billboard_table_offset,
    const DescriptorInfo& source_descriptor, std::uint64_t table_gpu_handle,
    ID3D12DescriptorHeap* original_resource_heap) {
  billboard_shadow_stage_counts[0].fetch_add(1, std::memory_order_relaxed);
  const auto fail = [](std::size_t stage) {
    billboard_shadow_stage_counts[stage].fetch_add(1,
                                                   std::memory_order_relaxed);
    return false;
  };
  if (!commands || !original_resource_heap || table_gpu_handle == 0 ||
      source_descriptor.kind != 'C' || source_descriptor.gpu_address == 0) {
    return fail(1);
  }
  ComPtr<ID3D12Device> device;
  if (FAILED(commands->GetDevice(IID_PPV_ARGS(&device))) ||
      !ensure_billboard_shadow_resources(device.Get())) {
    return fail(5);
  }
  const UINT constant_index =
      billboard_shadow_constant_cursor.fetch_add(1, std::memory_order_relaxed);
  if (constant_index >= kBillboardShadowConstantCapacity) {
    return fail(6);
  }
  const auto source_resource =
      resolve_buffer_resource(source_descriptor.gpu_address);
  if (!source_resource || !source_resource->resource) {
    return fail(7);
  }
  const auto source_offset =
      source_descriptor.gpu_address - source_resource->gpu_start;
  if (source_offset > source_resource->size ||
      source_resource->size - source_offset < 132) {
    return fail(8);
  }
  void* source_mapped{};
  const D3D12_RANGE source_read{
      static_cast<SIZE_T>(source_offset),
      static_cast<SIZE_T>(source_offset +
                          (std::min<std::uint64_t>)(256,
                              source_resource->size - source_offset))};
  if (FAILED(source_resource->resource->Map(0, &source_read, &source_mapped)) ||
      !source_mapped) {
    return fail(9);
  }
  auto* shadow = billboard_shadow_mapped +
                 static_cast<std::size_t>(constant_index) * 256;
  const auto copy_size = (std::min<std::uint64_t>)(
      256, source_resource->size - source_offset);
  std::memset(shadow, 0, 256);
  std::memcpy(shadow, static_cast<const std::byte*>(source_mapped) + source_offset,
              static_cast<std::size_t>(copy_size));
  const D3D12_RANGE no_cpu_writes{0, 0};
  source_resource->resource->Unmap(0, &no_cpu_writes);

  constexpr std::array<std::size_t, 6> float_indices{0, 1, 2, 8, 9, 10};
  auto* shadow_floats = reinterpret_cast<float*>(shadow);
  for (std::size_t i = 0; i < float_indices.size(); ++i) {
    shadow_floats[float_indices[i]] =
        billboard_view_basis[i].load(std::memory_order_relaxed);
  }

  auto destination_cpu =
      descriptor_cpu_handle(original_resource_heap, table_gpu_handle);
  if (!destination_cpu) {
    return fail(10);
  }
  const UINT increment = device->GetDescriptorHandleIncrementSize(
      D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
  destination_cpu->ptr +=
      static_cast<std::uint64_t>(billboard_table_offset) * increment;
  D3D12_CONSTANT_BUFFER_VIEW_DESC shadow_cbv{};
  shadow_cbv.BufferLocation = billboard_shadow_constants->GetGPUVirtualAddress() +
                              static_cast<UINT64>(constant_index) * 256;
  shadow_cbv.SizeInBytes = 256;
  device->CreateConstantBufferView(&shadow_cbv, *destination_cpu);
  billboard_basis_patch_count.fetch_add(1, std::memory_order_relaxed);
  billboard_shadow_stage_counts[13].fetch_add(1, std::memory_order_relaxed);
  return true;
}

BillboardBindingOverride apply_billboard_view_basis(
    ID3D12GraphicsCommandList* commands) {
  BillboardBindingOverride override_state{};
  if (!billboard_horizon_lock_enabled.load(std::memory_order_relaxed)) {
    return override_state;
  }
  std::uintptr_t pipeline{};
  std::uintptr_t root_signature{};
  std::array<std::uint64_t, kRootSlotCount> graphics_tables{};
  std::array<std::uint64_t, kRootSlotCount> graphics_cbvs{};
  std::array<D3D12_VERTEX_BUFFER_VIEW, 8> vertex_buffers{};
  ID3D12DescriptorHeap* graphics_resource_heap{};
  ID3D12DescriptorHeap* graphics_sampler_heap{};
  {
    std::scoped_lock lock(trace_mutex);
    const auto found = command_traces.find(commands);
    if (found == command_traces.end()) {
      return override_state;
    }
    pipeline = found->second.pso;
    root_signature = found->second.root_signature;
    graphics_tables = found->second.graphics_tables;
    graphics_cbvs = found->second.graphics_cbvs;
    vertex_buffers = found->second.vertex_buffers;
    graphics_resource_heap = found->second.graphics_resource_heap;
    graphics_sampler_heap = found->second.graphics_sampler_heap;
  }
  billboard_observed_draw_count.fetch_add(1, std::memory_order_relaxed);
  for (std::size_t slot = 0; slot < billboard_observed_stride_counts.size();
       ++slot) {
    const auto stride = vertex_buffers[slot].StrideInBytes;
    if (stride < kBillboardObservedStrideCount) {
      billboard_observed_stride_counts[slot][stride].fetch_add(
          1, std::memory_order_relaxed);
    }
  }
  // The old particle-layout selector is retained only as a census. Shader
  // reflection proved that billboard permutations use several input layouts,
  // so layout must not gate the exact c_billboard PSO classifier.
  if (vertex_buffers[0].StrideInBytes == 8 &&
      (vertex_buffers[1].StrideInBytes == 4 ||
       vertex_buffers[1].StrideInBytes == 8)) {
    billboard_exact_shader_draw_count.fetch_add(1, std::memory_order_relaxed);
  }

  bool billboard_pso{};
  bool target_billboard_pso{};
  std::uint64_t billboard_vertex_shader{};
  std::uint64_t billboard_substituted_vertex_shader{};
  std::uint64_t billboard_pixel_shader{};
  UINT billboard_register = UINT_MAX;
  {
    std::scoped_lock lock(pso_mutex);
    target_billboard_pso = darktidevr::producer::is_billboard_pipeline(
        reinterpret_cast<ID3D12PipelineState*>(pipeline));
    const auto found = pso_metadata.find(pipeline);
    if (found != pso_metadata.end()) {
      billboard_pso = target_billboard_pso || found->second.billboard_shader ||
                      is_billboard_vertex_shader(found->second.vertex_shader);
      billboard_vertex_shader = found->second.vertex_shader;
      billboard_substituted_vertex_shader =
          found->second.substituted_vertex_shader;
      billboard_pixel_shader = found->second.pixel_shader;
      billboard_register = found->second.billboard_register;
      if (billboard_register == UINT_MAX &&
          is_billboard_vertex_shader(found->second.vertex_shader)) {
        billboard_register = 2;
      }
    }
    if (target_billboard_pso) {
      billboard_pso = true;
      billboard_substituted_vertex_shader = kBillboardTargetVertexShader;
      if (billboard_register == UINT_MAX) {
        billboard_register = 2;
      }
    }
  }
  if (!billboard_pso || billboard_register == UINT_MAX) {
    return override_state;
  }
  if (billboard_vertex_shader != 0) {
    std::scoped_lock lock(billboard_candidate_shader_mutex);
    ++billboard_candidate_shader_counts[billboard_vertex_shader];
    ++billboard_candidate_shader_pair_counts[
        {billboard_vertex_shader, billboard_pixel_shader}];
  }
  billboard_exact_pso_draw_count.fetch_add(1, std::memory_order_relaxed);
  const auto command_list_type = static_cast<std::size_t>(commands->GetType());
  if (command_list_type < billboard_exact_command_list_type_counts.size()) {
    billboard_exact_command_list_type_counts[command_list_type].fetch_add(
        1, std::memory_order_relaxed);
  }
  if (billboard_register < billboard_exact_register_counts.size()) {
    billboard_exact_register_counts[billboard_register].fetch_add(
        1, std::memory_order_relaxed);
  }
  for (std::size_t slot = 0; slot < kRootSlotCount; ++slot) {
    if (graphics_cbvs[slot] != 0) {
      billboard_exact_pso_cbv_slot_counts[slot].fetch_add(
          1, std::memory_order_relaxed);
    }
    if (graphics_tables[slot] != 0) {
      billboard_exact_pso_table_slot_counts[slot].fetch_add(
          1, std::memory_order_relaxed);
    }
  }

  UINT billboard_root_index = UINT_MAX;
  UINT billboard_table_index = UINT_MAX;
  UINT billboard_table_offset = UINT_MAX;
  UINT billboard_table_span = UINT_MAX;
  UINT billboard_table_visibility_score{};
  {
    std::scoped_lock lock(root_signature_mutex);
    const auto found = root_signature_metadata.find(root_signature);
    if (found == root_signature_metadata.end()) {
      return override_state;
    }
    billboard_root_metadata_draw_count.fetch_add(1,
                                                  std::memory_order_relaxed);
    const auto& metadata = found->second;
    for (UINT i = 0; i < metadata.parameter_count; ++i) {
      const auto& parameter = metadata.parameters[i];
      if (parameter.type == D3D12_ROOT_PARAMETER_TYPE_CBV &&
          parameter.shader_register == billboard_register &&
          parameter.register_space == 0) {
        billboard_root_index = i;
        break;
      }
      if (parameter.type == D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE &&
          billboard_register < 64 &&
          (parameter.cbv_register_mask &
            (1ULL << static_cast<unsigned>(billboard_register))) != 0) {
        // c_billboard is reflected from the vertex shader. Registers are
        // stage-local, so a pixel-visible table containing the same b-register
        // is not the same binding. Prefer vertex-only visibility, then ALL.
        const UINT visibility_score =
            parameter.visibility == D3D12_SHADER_VISIBILITY_VERTEX
                ? 2U
                : (parameter.visibility == D3D12_SHADER_VISIBILITY_ALL ? 1U
                                                                       : 0U);
        if (visibility_score > billboard_table_visibility_score) {
          billboard_table_visibility_score = visibility_score;
          billboard_table_index = i;
          billboard_table_offset =
              parameter.cbv_descriptor_offsets[billboard_register];
          billboard_table_span = parameter.descriptor_table_span;
        }
      }
    }
  }
  DescriptorInfo billboard_descriptor{};
  if (billboard_table_index != UINT_MAX) {
    billboard_table_b2_draw_count.fetch_add(1, std::memory_order_relaxed);
    billboard_exact_vertex_table_slot_counts[billboard_table_index].fetch_add(
        1, std::memory_order_relaxed);
    if (billboard_table_offset <
        billboard_exact_descriptor_offset_counts.size()) {
      billboard_exact_descriptor_offset_counts[billboard_table_offset].fetch_add(
          1, std::memory_order_relaxed);
    }
    if (billboard_table_span < billboard_exact_table_span_counts.size()) {
      billboard_exact_table_span_counts[billboard_table_span].fetch_add(
          1, std::memory_order_relaxed);
    }
    if (graphics_tables[billboard_table_index] != 0) {
      billboard_bound_table_b2_draw_count.fetch_add(
          1, std::memory_order_relaxed);
      const auto provenance = resolve_table_provenance(
          root_signature, billboard_table_index,
          graphics_tables[billboard_table_index]);
      if (billboard_table_offset < provenance.descriptors.size()) {
        billboard_descriptor = provenance.descriptors[billboard_table_offset];
        observe_billboard_cbv(billboard_descriptor);
        if (target_billboard_pso ||
            billboard_vertex_shader == kBillboardTargetVertexShader ||
            billboard_substituted_vertex_shader ==
                kBillboardTargetVertexShader ||
            billboard_vertex_shader == billboard_target_replacement_hash.load(
                                           std::memory_order_relaxed)) {
          // c_per_object is reflected as 24 float4 values (384 bytes). Smaller
          // CBVs observed while this graphics PSO is stale belong to indirect
          // dispatch work and cannot be this vertex binding.
          if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed) &&
              billboard_descriptor.width >= kBillboardPerObjectByteSize) {
            log_target_billboard_cbv(billboard_descriptor);
          }
        }
      }
    }
  }
  if (!billboard_basis_write_enabled.load(std::memory_order_relaxed)) {
    return override_state;
  }
  if (billboard_table_index != UINT_MAX && billboard_descriptor.kind == 'C' &&
      billboard_descriptor.width >= kBillboardPerObjectByteSize) {
    apply_billboard_in_place_descriptor_override(
        commands, billboard_table_offset, billboard_descriptor,
        graphics_tables[billboard_table_index], graphics_resource_heap);
    return override_state;
  }
  if (billboard_root_index != UINT_MAX &&
      graphics_cbvs[billboard_root_index] != 0) {
    // A direct-root CBV can use the same shadow allocation with a temporary
    // SetGraphicsRootConstantBufferView override. No live c_billboard draw uses
    // this path yet, so keep it fail-closed until observed and tested.
    billboard_exact_root_mapping_count.fetch_add(1,
                                                   std::memory_order_relaxed);
  }
  return override_state;
}

void log_cluster_light_raster_bindings(
    ID3D12GraphicsCommandList* commands, const CommandTrace& trace) {
  if (cluster_raster_binding_log_count.fetch_add(
          1, std::memory_order_relaxed) >= 16) {
    return;
  }
  RootSignatureMetadata metadata{};
  {
    std::scoped_lock lock(root_signature_mutex);
    const auto found = root_signature_metadata.find(trace.root_signature);
    if (found != root_signature_metadata.end()) {
      metadata = found->second;
    }
  }
  write_cluster_trace_log(
      "frame=%llu\tCLUSTER_RASTER_BINDINGS\tCL=%p\tpso=%p\tsig=%p"
      "\tparameters=%u\r\n",
      static_cast<unsigned long long>(
          present_count.load(std::memory_order_relaxed)),
      commands, reinterpret_cast<void*>(trace.pso),
      reinterpret_cast<void*>(trace.root_signature), metadata.parameter_count);
  for (UINT root = 0; root < metadata.parameter_count; ++root) {
    const auto& parameter = metadata.parameters[root];
    const auto provenance = resolve_table_provenance(
        trace.root_signature, root, trace.graphics_tables[root]);
    write_cluster_trace_log(
        "frame=%llu\tCLUSTER_RASTER_ROOT\tCL=%p\troot=%u\ttype=%u"
        "\tvisibility=%u\tregister=%u\tspace=%u\tspan=%u"
        "\tcounts=%llu,%llu,%llu,%llu\ttable=%llu"
        "\tcbv=%llu\tsrv=%llu\tuav=%llu"
        "\tprov=%u,%c,%p,%llu,%llu,%u,%u,%c,%p,%llu,%llu,%u,%u\r\n",
        static_cast<unsigned long long>(
            present_count.load(std::memory_order_relaxed)),
        commands, root, parameter.type, parameter.visibility,
        parameter.shader_register, parameter.register_space,
        parameter.descriptor_table_span,
        static_cast<unsigned long long>(parameter.cbv_count),
        static_cast<unsigned long long>(parameter.srv_count),
        static_cast<unsigned long long>(parameter.uav_count),
        static_cast<unsigned long long>(parameter.sampler_count),
        static_cast<unsigned long long>(trace.graphics_tables[root]),
        static_cast<unsigned long long>(trace.graphics_cbvs[root]),
        static_cast<unsigned long long>(trace.graphics_srvs[root]),
        static_cast<unsigned long long>(trace.graphics_uavs[root]),
        provenance.descriptor_count, provenance.descriptors[0].kind,
        reinterpret_cast<void*>(provenance.descriptors[0].resource),
        static_cast<unsigned long long>(
            provenance.descriptors[0].gpu_address),
        static_cast<unsigned long long>(
            provenance.descriptors[0].first_element),
        provenance.descriptors[0].element_count,
        provenance.descriptors[0].structure_stride,
        provenance.descriptors[1].kind,
        reinterpret_cast<void*>(provenance.descriptors[1].resource),
        static_cast<unsigned long long>(
            provenance.descriptors[1].gpu_address),
        static_cast<unsigned long long>(
            provenance.descriptors[1].first_element),
        provenance.descriptors[1].element_count,
        provenance.descriptors[1].structure_stride);

    if (root == 3 && provenance.descriptors[0].kind == 'S' &&
        provenance.descriptors[0].resource &&
        provenance.descriptors[0].structure_stride >= 64 &&
        provenance.descriptors[0].element_count > 0 &&
        provenance.descriptors[0].element_count <= 32) {
      std::scoped_lock lock(cluster_constant_copy_mutex);
      cluster_constant_ring_resources.insert(
          reinterpret_cast<ID3D12Resource*>(
              provenance.descriptors[0].resource));
      if (cluster_pending_transform_count <
          cluster_pending_transform_samples.size()) {
        auto& pending = cluster_pending_transform_samples[
            cluster_pending_transform_count++];
        pending = ClusterPendingTransformSample{
            reinterpret_cast<ID3D12Resource*>(
                provenance.descriptors[0].resource),
            static_cast<std::uint64_t>(
                provenance.descriptors[0].first_element) *
                provenance.descriptors[0].structure_stride,
            present_count.load(std::memory_order_relaxed), commands,
            provenance.descriptors[0].first_element,
            provenance.descriptors[0].element_count,
            provenance.descriptors[0].structure_stride, false};
      }
    }

    if ((root == 0 || root == 2) && trace.graphics_cbvs[root] != 0) {
      constexpr std::size_t kRasterConstantBytes = 84;
      std::array<std::byte, kRasterConstantBytes> bytes{};
      const auto gpu_address = trace.graphics_cbvs[root];
      const auto resource = resolve_buffer_resource(gpu_address);
      bool copied = false;
      bool used_persistent_mapping = false;
      bool used_staging_mapping = false;
      bool used_buffer_copy = false;
      std::uint64_t copy_source_gpu{};
      if (resource && resource->resource) {
        {
          std::scoped_lock lock(cluster_constant_copy_mutex);
          cluster_constant_ring_resources.insert(resource->resource);
          if (cluster_pending_constant_count <
              cluster_pending_constant_samples.size()) {
            auto& pending = cluster_pending_constant_samples[
                cluster_pending_constant_count++];
            pending = ClusterPendingConstantSample{
                resource->resource, gpu_address - resource->gpu_start,
                gpu_address,
                present_count.load(std::memory_order_relaxed), commands, root,
                false};
          }
        }
        BufferResourceInfo direct_snapshot{};
        copied = copy_tracked_buffer_bytes(
            gpu_address, bytes.data(), bytes.size(), &direct_snapshot,
            &used_persistent_mapping, &used_staging_mapping);
        if (!copied) {
          const auto destination_offset =
              gpu_address - resource->gpu_start;
          const auto copy = resolve_cluster_constant_copy(
              resource->resource, destination_offset, bytes.size());
          if (copy && copy->source) {
            copy_source_gpu = copy->source->GetGPUVirtualAddress() +
                              copy->source_offset +
                              (destination_offset - copy->destination_offset);
            BufferResourceInfo source_snapshot{};
            copied = copy_tracked_buffer_bytes(
                copy_source_gpu, bytes.data(), bytes.size(), &source_snapshot,
                &used_persistent_mapping, &used_staging_mapping);
            used_buffer_copy = copied;
          }
        }
      }

      std::array<float, 16> projection{};
      std::uint32_t render_target_offset{};
      float aspect{};
      float fov{};
      std::uint32_t vb_offset{};
      std::uint32_t ib_offset{};
      if (copied) {
        std::memcpy(projection.data(), bytes.data(), sizeof(projection));
        std::memcpy(&render_target_offset, bytes.data() + 64,
                    sizeof(render_target_offset));
        std::memcpy(&aspect, bytes.data() + 68, sizeof(aspect));
        std::memcpy(&fov, bytes.data() + 72, sizeof(fov));
        std::memcpy(&vb_offset, bytes.data() + 76, sizeof(vb_offset));
        std::memcpy(&ib_offset, bytes.data() + 80, sizeof(ib_offset));
      }
      write_cluster_trace_log(
          "frame=%llu\tCLUSTER_RASTER_C0\tCL=%p\troot=%u\tgpu=%llu"
          "\tresource=%p\tgpu_start=%llu\tsize=%llu\theap=%u"
          "\toffset=%llu\tresource_mapped=%u\tstaging_base=%p"
          "\tstaging_size=%llu\tmapped=%u\tstaging=%u\tbuffer_copy=%u"
          "\tcopy_source_gpu=%llu\tcopied=%u"
          "\tproj=%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g"
          "\trt_offset=%u\taspect=%g\tfov=%g\tvb_offset=%u"
          "\tib_offset=%u\r\n",
          static_cast<unsigned long long>(
              present_count.load(std::memory_order_relaxed)),
          commands, root, static_cast<unsigned long long>(gpu_address),
          resource ? resource->resource : nullptr,
          static_cast<unsigned long long>(resource ? resource->gpu_start : 0),
          static_cast<unsigned long long>(resource ? resource->size : 0),
          static_cast<unsigned>(resource ? resource->heap_type
                                         : D3D12_HEAP_TYPE_CUSTOM),
          static_cast<unsigned long long>(
              resource ? gpu_address - resource->gpu_start : 0),
          resource && resource->mapped ? 1u : 0u,
          resource ? resource->staging_base : nullptr,
          static_cast<unsigned long long>(
              resource ? resource->staging_size : 0),
          used_persistent_mapping ? 1u : 0u,
          used_staging_mapping ? 1u : 0u, used_buffer_copy ? 1u : 0u,
          static_cast<unsigned long long>(copy_source_gpu),
          copied ? 1u : 0u, projection[0],
          projection[1], projection[2], projection[3], projection[4],
          projection[5], projection[6], projection[7], projection[8],
          projection[9], projection[10], projection[11], projection[12],
          projection[13], projection[14], projection[15],
          render_target_offset, aspect, fov, vb_offset, ib_offset);
    }
  }
}

void queue_cluster_light_visibility_fov_patches(
    ID3D12GraphicsCommandList* commands) {
  if (!cluster_light_visibility_fix_active.load(std::memory_order_relaxed) ||
      current_presentation_mode.load(std::memory_order_relaxed) !=
          static_cast<unsigned int>(
              darktidevr::core::SharedPresentationMode::stereo_world)) {
    return;
  }
  const auto corrected_fov =
      render_vertical_fov_radians.load(std::memory_order_relaxed);
  if (!(corrected_fov > 0.0F && corrected_fov < 3.14159265F)) {
    return;
  }
  CommandTrace trace{};
  {
    std::scoped_lock lock(trace_mutex);
    const auto found = command_traces.find(commands);
    if (found == command_traces.end() ||
        !found->second.cluster_light_raster) {
      return;
    }
    trace = found->second;
  }
  cluster_light_visibility_fix_target_draw_count.fetch_add(
      1, std::memory_order_relaxed);
  for (const UINT root : {0U, 2U}) {
    const auto gpu_address = trace.graphics_cbvs[root];
    if (gpu_address == 0) {
      cluster_light_visibility_fix_root_missing_count.fetch_add(
          1, std::memory_order_relaxed);
      cluster_light_visibility_fix_reject_count.fetch_add(
          1, std::memory_order_relaxed);
      continue;
    }
    const auto resource = resolve_buffer_resource(gpu_address);
    if (!resource || !resource->resource) {
      cluster_light_visibility_fix_resource_missing_count.fetch_add(
          1, std::memory_order_relaxed);
      cluster_light_visibility_fix_reject_count.fetch_add(
          1, std::memory_order_relaxed);
      continue;
    }
    cluster_light_visibility_fix_candidate_count.fetch_add(
        1, std::memory_order_relaxed);
    const auto resource_offset = gpu_address - resource->gpu_start;
    std::scoped_lock lock(cluster_light_visibility_fix_mutex);
    const auto duplicate = std::find_if(
        cluster_pending_fov_patches.begin(),
        cluster_pending_fov_patches.end(),
        [resource_pointer = resource->resource,
         resource_offset](const ClusterPendingFovPatch& pending) {
          return pending.valid && pending.resource == resource_pointer &&
                 pending.resource_offset == resource_offset;
        });
    if (duplicate != cluster_pending_fov_patches.end()) {
      continue;
    }
    auto& pending = cluster_pending_fov_patches[
        cluster_pending_fov_patch_cursor++ %
        cluster_pending_fov_patches.size()];
    if (pending.valid) {
      cluster_light_visibility_fix_reject_count.fetch_add(
          1, std::memory_order_relaxed);
    }
    pending = ClusterPendingFovPatch{
        resource->resource, resource_offset,
        present_count.load(std::memory_order_relaxed), true};
  }
}

void record_cluster_submission(
    ID3D12GraphicsCommandList* commands, const char* submission,
    std::uint64_t argument0, std::uint64_t argument1,
    std::uint64_t argument2, std::uint64_t argument3,
    std::uint64_t argument4) {
  if (cluster_trace_log == INVALID_HANDLE_VALUE ||
      !cluster_trace_saw_flat_presentation.load(std::memory_order_relaxed) ||
      current_presentation_mode.load(std::memory_order_relaxed) !=
          static_cast<unsigned int>(
              darktidevr::core::SharedPresentationMode::stereo_world)) {
    return;
  }
  CommandTrace trace{};
  {
    std::scoped_lock lock(trace_mutex);
    const auto found = command_traces.find(commands);
    if (found == command_traces.end()) {
      return;
    }
    trace = found->second;
  }
  if (trace.cluster_light_raster) {
    log_cluster_light_raster_bindings(commands, trace);
  }
  std::scoped_lock lock(cluster_submission_mutex);
  auto& ring = cluster_submission_rings[commands];
  const auto sequence = ring.write_count++;
  auto& entry = ring.entries[sequence % ring.entries.size()];
  entry.sequence = sequence;
  entry.pso = trace.pso;
  entry.submission = submission;
  entry.arguments = {argument0, argument1, argument2, argument3, argument4};
}

void log_cluster_predecessor_ring(ID3D12GraphicsCommandList* commands) {
  ClusterSubmissionRing ring{};
  {
    std::scoped_lock lock(cluster_submission_mutex);
    const auto found = cluster_submission_rings.find(commands);
    if (found == cluster_submission_rings.end()) {
      return;
    }
    ring = found->second;
  }
  const auto count = (std::min<std::uint64_t>)(ring.write_count,
                                               ring.entries.size());
  if (count == 0) {
    return;
  }
  const auto first = ring.write_count > ring.entries.size()
                         ? ring.write_count % ring.entries.size()
                         : 0;
  for (std::uint64_t offset = 0; offset < count; ++offset) {
    const auto& entry = ring.entries[(first + offset) % ring.entries.size()];
    PsoMetadata metadata{};
    {
      std::scoped_lock lock(pso_mutex);
      const auto found = pso_metadata.find(entry.pso);
      if (found != pso_metadata.end()) {
        metadata = found->second;
      }
    }
    write_cluster_trace_log(
        "frame=%llu\tCLUSTER_PREDECESSOR\tCL=%p\tsequence=%llu"
        "\tdistance=%llu\tsubmit=%s\tpso=%p\tvs=%016llx\tps=%016llx"
        "\tcs=%016llx"
        "\targs=%llu,%llu,%llu,%llu,%llu\r\n",
        static_cast<unsigned long long>(
            present_count.load(std::memory_order_relaxed)),
        commands, static_cast<unsigned long long>(entry.sequence),
        static_cast<unsigned long long>(count - offset), entry.submission,
        reinterpret_cast<void*>(entry.pso),
        static_cast<unsigned long long>(metadata.vertex_shader),
        static_cast<unsigned long long>(metadata.pixel_shader),
        static_cast<unsigned long long>(metadata.compute_shader),
        static_cast<unsigned long long>(entry.arguments[0]),
        static_cast<unsigned long long>(entry.arguments[1]),
        static_cast<unsigned long long>(entry.arguments[2]),
        static_cast<unsigned long long>(entry.arguments[3]),
        static_cast<unsigned long long>(entry.arguments[4]));
  }
}

// Experimental transparent replay is opt-in until paired readbacks establish
// coverage of both the panel and world markers. Never infer GUI from blending
// alone: lighting and particle passes also use source-over.
struct WorldUiCaptureEye {
  ComPtr<ID3D12Resource> texture;
  ComPtr<ID3D12DescriptorHeap> rtv;
  std::uint64_t pose{};
  unsigned draws{}, rejected{};
};
std::mutex world_ui_capture_mutex;
std::array<WorldUiCaptureEye, 2> world_ui_capture_eyes;
std::array<std::atomic<std::uint64_t>, 8> world_ui_capture_stages{};
std::atomic<bool> world_ui_capture_rejected{};
// A resolution change must not release a texture still referenced by a GPU
// command list. This bounded experiment retains its earlier allocations.
std::vector<WorldUiCaptureEye> world_ui_capture_retired;
bool world_ui_submission_requested() {
  // Separate opt-in from one-shot readback: submitting UI requires capture to
  // continue after diagnostic images have been exported.
  static const bool enabled = [] {
    wchar_t value[2]{};
    if (GetEnvironmentVariableW(L"DARKTIDEVR_STREAMLINE_UI_ALPHA", value, 2) == 1 && value[0] == L'1') return true;
    wchar_t directory[MAX_PATH]{};
    const auto length = GetTempPathW(MAX_PATH, directory);
    return length && length < MAX_PATH && GetFileAttributesW(
        (std::wstring(directory) + L"darktidevr-streamline-ui-alpha.enabled").c_str()) != INVALID_FILE_ATTRIBUTES;
  }();
  return enabled;
}
bool world_ui_capture_requested() {
  return world_ui_submission_requested() ||
      darktidevr::producer::stereo_ui_overlay_capture_requested();
}
struct WorldUiDrawRedirect {
  std::unique_lock<std::mutex> lock;
  D3D12_CPU_DESCRIPTOR_HANDLE original{};
  ID3D12PipelineState* original_pipeline{};
  bool active{};
};
WorldUiDrawRedirect begin_world_ui_draw(ID3D12GraphicsCommandList* commands,
                                       const PsoMetadata& metadata) {
  WorldUiDrawRedirect redirect;
  if (!world_ui_capture_requested() || current_presentation_mode.load() != 1) return redirect;
  // Target redirection bypasses tracing, so it requires the installed hook.
  if (!original_om_set_render_targets) return redirect;
  ++world_ui_capture_stages[0];
  if (!metadata.blend_enabled || metadata.render_target_count != 1 ||
      metadata.render_target_format != DXGI_FORMAT_R8G8B8A8_UNORM)
    return redirect;
  ++world_ui_capture_stages[1];
  CommandTrace trace{};
  {
    std::scoped_lock lock(trace_mutex);
    const auto found = command_traces.find(commands);
    if (found == command_traces.end()) return redirect;
    trace = found->second;
  }
  if (!trace.render_target || trace.render_target_count != 1 || trace.render_pass_active) return redirect;
  ++world_ui_capture_stages[2];
  const auto width = camera_input_width.load();
  const auto height = camera_input_height.load();
  if (!width || !height || trace.render_pass_active || trace.render_target_count != 1 || !trace.render_target ||
      trace.viewport_x || trace.viewport_y || trace.viewport_width != width ||
      trace.viewport_height != height) return redirect;
  ++world_ui_capture_stages[3];
  const auto target = descriptor_snapshot(trace.render_target);
  if (target.width != width || target.height != height ||
      target.format != DXGI_FORMAT_R8G8B8A8_UNORM || !target.resource) return redirect;
  const auto source_description = reinterpret_cast<ID3D12Resource*>(target.resource)->GetDesc();
  if (source_description.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
      source_description.SampleDesc.Count != 1 || source_description.DepthOrArraySize != 1 ||
      source_description.MipLevels != 1) return redirect;
  ++world_ui_capture_stages[4];
  int eye = -1;
  std::uint64_t pose{};
  {
    std::scoped_lock lock(state_mutex);
    if (!armed_eye_captures.empty()) {
      eye = armed_eye_captures.front().eye;
      pose = armed_eye_captures.front().pose_sequence;
    }
  }
  if (eye < 0 || eye > 1 || !pose) return redirect;
  ++world_ui_capture_stages[5];
  redirect.lock = std::unique_lock(world_ui_capture_mutex);
  static std::unordered_set<std::uint64_t> candidates;
  const auto identity = mix_u64(metadata.vertex_shader, metadata.pixel_shader);
  if (candidates.size() < 96 && candidates.insert(identity).second) {
    const auto& blend = metadata.ui_blend;
    write_streamline_probe_log(
        "UI_ALPHA_CANDIDATE\tvs=%llu\tps=%llu\tknown_gui=%u\tdepth=%u\tstencil=%u"
        "\tcolour_blend=%u,%u,%u\talpha_blend=%u,%u,%u\twrite_mask=%u\talpha_to_coverage=%u\r\n",
        static_cast<unsigned long long>(metadata.vertex_shader),
        static_cast<unsigned long long>(metadata.pixel_shader),
        is_stock_menu_shader_pair(metadata) ? 1U : 0U,
        metadata.depth_enabled ? 1U : 0U, metadata.stencil_enabled ? 1U : 0U,
        static_cast<unsigned>(blend.SrcBlend), static_cast<unsigned>(blend.DestBlend),
        static_cast<unsigned>(blend.BlendOp), static_cast<unsigned>(blend.SrcBlendAlpha),
        static_cast<unsigned>(blend.DestBlendAlpha), static_cast<unsigned>(blend.BlendOpAlpha),
        static_cast<unsigned>(blend.RenderTargetWriteMask), metadata.alpha_to_coverage ? 1U : 0U);
  }
  // The world HUD's item-container material is separate from stock GUI draws.
  // Paired readback verified this panel plus stock markers reproduce the final
  // colour over HUDless input with valid transparent alpha in both eyes.
  // Do not include the other full-eye census pair: it copies the opaque world.
  const bool panel_candidate =
      (metadata.vertex_shader == 634962454189541227ULL &&
       metadata.pixel_shader == 4439945837785333492ULL);
  if (!is_stock_menu_shader_pair(metadata) && !panel_candidate) return redirect;
  ++world_ui_capture_stages[6];
  auto& capture = world_ui_capture_eyes[eye];
  if (capture.texture && (capture.texture->GetDesc().Width != width ||
                          capture.texture->GetDesc().Height != height)) {
    if (world_ui_capture_retired.size() >= 8) return redirect;
    world_ui_capture_retired.push_back(std::move(capture));
    capture = {};
  }
  if (!capture.texture) {
    ComPtr<ID3D12Device> device;
    if (FAILED(commands->GetDevice(IID_PPV_ARGS(&device)))) return redirect;
    D3D12_RESOURCE_DESC description{};
    description.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    description.Width = width; description.Height = height;
    description.DepthOrArraySize = description.MipLevels = 1;
    description.SampleDesc.Count = 1;
    description.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    description.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    D3D12_HEAP_PROPERTIES heap{}; heap.Type = D3D12_HEAP_TYPE_DEFAULT;
    D3D12_DESCRIPTOR_HEAP_DESC rtv{};
    rtv.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV; rtv.NumDescriptors = 1;
    if (FAILED(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE,
        &description, D3D12_RESOURCE_STATE_RENDER_TARGET, nullptr,
        IID_PPV_ARGS(&capture.texture))) ||
        FAILED(device->CreateDescriptorHeap(&rtv, IID_PPV_ARGS(&capture.rtv)))) {
      capture.texture.Reset(); return redirect;
    }
    device->CreateRenderTargetView(capture.texture.Get(), nullptr,
                                   capture.rtv->GetCPUDescriptorHandleForHeapStart());
  }
  if (capture.pose != pose) {
    capture.pose = pose; capture.draws = capture.rejected = 0;
    const float transparent[4]{};
    // ClearRTV interception is diagnostic-only. Call the COM method so capture
    // also works when that hook (and its trampoline) was never installed.
    commands->ClearRenderTargetView(
        capture.rtv->GetCPUDescriptorHandleForHeapStart(), transparent, 0, nullptr);
  }
  if (metadata.depth_enabled || metadata.stencil_enabled || trace.depth_target ||
      (!metadata.ui_alpha_pipeline &&
       !darktidevr::producer::ui_capture_blend_supported(metadata.ui_blend, metadata.alpha_to_coverage))) {
    ++capture.rejected;
    if (world_ui_submission_requested()) world_ui_capture_rejected.store(true);
    static unsigned rejection_reports{};
    if (rejection_reports++ < 32)
      write_streamline_probe_log(
          "UI_ALPHA_REJECT\teye=%d\tpose=%llu\tvs=%llu\tps=%llu\tdepth=%u\tstencil=%u\tdsv=%llu\talpha_blend=%u,%u,%u\r\n",
          eye, static_cast<unsigned long long>(pose),
          static_cast<unsigned long long>(metadata.vertex_shader),
          static_cast<unsigned long long>(metadata.pixel_shader),
          metadata.depth_enabled ? 1U : 0U, metadata.stencil_enabled ? 1U : 0U,
          static_cast<unsigned long long>(trace.depth_target),
          static_cast<unsigned>(metadata.ui_blend.SrcBlendAlpha),
          static_cast<unsigned>(metadata.ui_blend.DestBlendAlpha),
          static_cast<unsigned>(metadata.ui_blend.BlendOpAlpha));
    return redirect;
  }
  redirect.original = {trace.render_target};
  if (metadata.ui_alpha_pipeline) {
    if (!original_set_pipeline_state || !trace.pso) return redirect;
    redirect.original_pipeline = reinterpret_cast<ID3D12PipelineState*>(trace.pso);
    original_set_pipeline_state(commands, metadata.ui_alpha_pipeline.Get());
  }
  const auto output = capture.rtv->GetCPUDescriptorHandleForHeapStart();
  original_om_set_render_targets(commands, 1, &output, FALSE, nullptr);
  ++capture.draws;
  ++world_ui_capture_stages[7];
  redirect.active = true;
  return redirect;
}
void end_world_ui_draw(ID3D12GraphicsCommandList* commands, WorldUiDrawRedirect& redirect) {
  if (redirect.original_pipeline) original_set_pipeline_state(commands, redirect.original_pipeline);
  if (redirect.active)
    original_om_set_render_targets(commands, 1, &redirect.original, FALSE, nullptr);
}

std::uint64_t begin_billboard_draw_readback(ID3D12GraphicsCommandList* commands) {
  if (!billboard_readback_accepting.load(std::memory_order_acquire) ||
      commands->GetType() != D3D12_COMMAND_LIST_TYPE_DIRECT) return 0;
  auto* readback = billboard_readback.load(std::memory_order_acquire);
  if (!readback) return 0;
  std::uintptr_t pipeline{};
  std::uint64_t target{};
  {
    std::scoped_lock lock(trace_mutex);
    const auto trace = command_traces.find(commands);
    if (trace == command_traces.end() || trace->second.render_pass_active ||
        trace->second.render_target_count != 1) return 0;
    pipeline = trace->second.pso;
    target = trace->second.render_target;
  }
  std::uint64_t vs{}, ps{};
  {
    std::scoped_lock lock(pso_mutex);
    const auto found = pso_metadata.find(pipeline);
    if (found == pso_metadata.end() || found->second.substituted_vertex_shader ||
        found->second.render_target_count != 1) return 0;
    vs = found->second.vertex_shader;
    ps = found->second.pixel_shader;
  }
  if (!((vs == 0xc403cfbf17d9fc49ULL && ps == 0xcb7e4e5d3e01d5bdULL) ||
        (vs == 0xe18a274cd89282e8ULL && ps == 0x0e35f00186a2af32ULL) ||
        (vs == 0xfe64037664924d52ULL && ps == 0x7c035f0ca3365a04ULL))) return 0;
  const auto descriptor = descriptor_snapshot(target);
  if (descriptor.kind != 'R' || !descriptor.resource || descriptor.mip_levels != 1 ||
      descriptor.depth_or_array_size != 1 || descriptor.width < 512 || descriptor.height < 512)
    return 0;
  auto* resource = reinterpret_cast<ID3D12Resource*>(descriptor.resource);
  {
    std::scoped_lock lock(trace_mutex);
    const auto proof = billboard_resource_states.find(commands);
    if (proof == billboard_resource_states.end() ||
        !proof->second.known_render_target(resource)) return 0;
  }
  // Do not hold the trace mutex across copies: our state-restoring barriers
  // traverse the same hook and update this recording's state evidence.
  return readback->begin(commands, resource, vs, ps, present_count.load(std::memory_order_relaxed));
}

void end_billboard_draw_readback(std::uint64_t id, ID3D12GraphicsCommandList* commands) {
  if (id) if (auto* readback = billboard_readback.load(std::memory_order_acquire))
    readback->end(id, commands);
}

void STDMETHODCALLTYPE draw_instanced_hook(ID3D12GraphicsCommandList* commands,
                                           UINT vertex_count,
                                           UINT instance_count,
                                           UINT start_vertex,
                                           UINT start_instance) {
  record_cluster_submission(commands, "draw", vertex_count, instance_count,
                            start_vertex, start_instance, 0);
  if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed) ||
      billboard_horizon_lock_enabled.load(std::memory_order_relaxed)) {
    billboard_direct_draw_hook_count.fetch_add(1, std::memory_order_relaxed);
  }
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].draw_count++;
  }
  if (marker_log != INVALID_HANDLE_VALUE) {
    std::scoped_lock lock(trace_mutex);
    observe_table4_draw(commands, 0, vertex_count, instance_count,
                        start_vertex, start_instance, 0);
    log_focused_draw(commands, 0, vertex_count, instance_count, start_vertex,
                     start_instance, 0);
    sample_graphics_bindings(commands);
    current_pass(commands).draw++;

    // The final fullscreen triangle is required: suppressing it made the eye
    // entirely black, proving that it copies the already-composited upstream
    // source. Enumerate that draw's bound descriptors so the source can be
    // captured before the upper-left output_target inset is added.
    const auto& trace = command_traces[commands];
    if (vertex_count == 3 && instance_count == 1 &&
        camera_capture_extent_matches(trace.viewport_width,
                                      trace.viewport_height) &&
        trace.render_target != 0) {
      const auto target = descriptor_snapshot(trace.render_target);
      auto* resource = reinterpret_cast<ID3D12Resource*>(target.resource);
      if (resource != nullptr && is_named_eye_final_resource(resource)) {
        static std::atomic_uint64_t traced_count{};
        const auto count = traced_count.fetch_add(1) + 1;
        if (count <= 4) {
          for (UINT slot = 0; slot < kRootSlotCount; ++slot) {
            const auto provenance = resolve_table_provenance(
                trace.root_signature, slot,
                trace.graphics_tables[slot]);
            for (UINT descriptor_index = 0;
                 descriptor_index < provenance.descriptor_count &&
                 descriptor_index < provenance.descriptors.size();
                 ++descriptor_index) {
              const auto& descriptor = provenance.descriptors[descriptor_index];
              auto* source = reinterpret_cast<ID3D12Resource*>(
                  descriptor.resource);
              write_boundary_census_log(
                  "frame=%llu\tFINAL_TRIANGLE_SOURCE\tCL=%p"
                  "\ttarget=%p\tslot=%u\tdescriptor=%u\tkind=%c"
                  "\tresource=%p\twidth=%llu\theight=%u\tformat=%u"
                  "\tname=%s\r\n",
                  present_count.load(std::memory_order_relaxed), commands,
                  resource, slot, descriptor_index, descriptor.kind, source,
                  static_cast<unsigned long long>(descriptor.width),
                  descriptor.height, descriptor.format,
                  source ? resource_debug_name(source).c_str() : "");
            }
          }
        }
      }
    }
  }
  PsoMetadata draw_metadata{};
  const auto direct_menu_capture =
      menu_direct_capture_enabled.load(std::memory_order_relaxed);
  if (direct_menu_capture || world_ui_capture_requested()) {
    std::uintptr_t pipeline{};
    {
      std::scoped_lock lock(trace_mutex);
      pipeline = command_traces[commands].pso;
    }
    {
      std::scoped_lock lock(pso_mutex);
      const auto found = pso_metadata.find(pipeline);
      if (found != pso_metadata.end()) {
        draw_metadata = found->second;
      }
    }
  }
  const auto stock_menu_draw =
      direct_menu_capture && is_stock_menu_shader_pair(draw_metadata);
  const auto vendor_menu_widget_draw =
      direct_menu_capture &&
      vendor_menu_widget_capture_enabled.load(std::memory_order_relaxed) &&
      vertex_count == 180 && instance_count == 1 &&
      is_vendor_menu_widget_shader_pair(draw_metadata);
  const auto scoped_menu_draw = direct_menu_capture &&
                                menu_draw_scope_depth != 0;
  if (stock_menu_draw) {
    stock_menu_draw_frame.store(present_count.load(std::memory_order_relaxed),
                                std::memory_order_relaxed);
  }
  const auto menu_redirect =
      (stock_menu_draw || vendor_menu_widget_draw)
          ? begin_stock_menu_draw_redirect(commands, draw_metadata,
                                            vertex_count, instance_count)
          : MenuDrawRedirect{};
  if (scoped_menu_draw && menu_redirect.active) {
    menu_draw_scope_redirect_count.fetch_add(1, std::memory_order_relaxed);
  }
  // Some Options passes update a retained target which the same pass then
  // samples while composing the visible pane. Record the native draw first,
  // then capture it, so the shared copy sees the completed retained content.
  // The redirect helper has already performed the shared-surface transition
  // and clear; only the render-target binding is changed here.
  if (menu_redirect.active && stock_menu_draw) {
    end_stock_menu_draw_redirect(commands, menu_redirect);
    original_draw_instanced(commands, vertex_count, instance_count,
                            start_vertex, start_instance);
    original_om_set_render_targets(commands, 1,
                                   &menu_redirect.capture_target, FALSE,
                                   nullptr);
  }
  if (direct_menu_capture && kMenuLayerConsumerProbeEnabled &&
      current_presentation_mode.load(std::memory_order_relaxed) ==
          static_cast<unsigned int>(
              darktidevr::core::SharedPresentationMode::world_anchored_menu)) {
    const auto alias_layer =
        options_layer_resources[0].load(std::memory_order_acquire);
    const auto typed_layer =
        options_layer_resources[1].load(std::memory_order_acquire);
    if (alias_layer || typed_layer) {
      CommandTrace routing_trace{};
      {
        std::scoped_lock lock(trace_mutex);
        const auto found = command_traces.find(commands);
        if (found != command_traces.end()) {
          routing_trace = found->second;
        }
      }
      ID3D12Resource* sampled_layer{};
      UINT sampled_root = UINT_MAX;
      UINT sampled_descriptor = UINT_MAX;
      for (UINT root = 0; root < kRootSlotCount && !sampled_layer; ++root) {
        const auto provenance = resolve_table_provenance(
            routing_trace.root_signature, root,
            routing_trace.graphics_tables[root]);
        for (UINT descriptor = 0;
             descriptor < provenance.descriptor_count &&
             descriptor < provenance.descriptors.size();
             ++descriptor) {
          auto* resource = reinterpret_cast<ID3D12Resource*>(
              provenance.descriptors[descriptor].resource);
          if (resource == alias_layer || resource == typed_layer) {
            sampled_layer = resource;
            sampled_root = root;
            sampled_descriptor = descriptor;
            break;
          }
        }
      }
      if (sampled_layer) {
        static std::atomic<std::uint64_t> consumer_log_count{};
        const auto consumer_id =
            consumer_log_count.fetch_add(1, std::memory_order_relaxed) + 1;
        if (consumer_id <= 1024) {
          const auto output = descriptor_snapshot(routing_trace.render_target);
          write_menu_resource_log(
              "MENU_LAYER_CONSUMER\tid=%llu\tframe=%llu\tcommands=%p"
              "\tsampled=%s\tresource=%p\troot=%u\tdescriptor=%u"
              "\toutput=%p\toutput_width=%llu\toutput_height=%u"
              "\toutput_format=%u\tvs=%llu\tps=%llu"
              "\tvertices=%u\tinstances=%u\r\n",
              static_cast<unsigned long long>(consumer_id),
              static_cast<unsigned long long>(
                  present_count.load(std::memory_order_relaxed)),
              commands, sampled_layer == alias_layer ? "alias" : "typed",
              sampled_layer, sampled_root, sampled_descriptor,
              reinterpret_cast<void*>(output.resource),
              static_cast<unsigned long long>(output.width), output.height,
              output.format,
              static_cast<unsigned long long>(draw_metadata.vertex_shader),
              static_cast<unsigned long long>(draw_metadata.pixel_shader),
              vertex_count, instance_count);
        }
      }
    }
  }
  const auto billboard_override = apply_billboard_view_basis(commands);
  if (menu_redirect.diagnostic_id != 0 &&
      menu_redirect.diagnostic_id <= 2) {
    write_menu_resource_log(
        "MENU_REDIRECT_STAGE\tid=%llu\tstage=before_draw\r\n",
        static_cast<unsigned long long>(menu_redirect.diagnostic_id));
  }
  const auto readback_id = vertex_count && instance_count ? begin_billboard_draw_readback(commands) : 0;
  original_draw_instanced(commands, vertex_count, instance_count,
                          start_vertex, start_instance);
  end_billboard_draw_readback(readback_id, commands);
  if (menu_redirect.diagnostic_id != 0 &&
      menu_redirect.diagnostic_id <= 2) {
    write_menu_resource_log(
        "MENU_REDIRECT_STAGE\tid=%llu\tstage=after_draw\r\n",
        static_cast<unsigned long long>(menu_redirect.diagnostic_id));
  }
  end_stock_menu_draw_redirect(commands, menu_redirect);
  {
    auto ui = begin_world_ui_draw(commands, draw_metadata);
    if (ui.active)
      original_draw_instanced(commands, vertex_count, instance_count, start_vertex, start_instance);
    end_world_ui_draw(commands, ui);
  }
  // Replay must use the same corrected eye/billboard bindings as the draw.
  end_billboard_binding_override(commands, billboard_override);
  if (menu_redirect.diagnostic_id != 0 &&
      menu_redirect.diagnostic_id <= 2) {
    write_menu_resource_log(
        "MENU_REDIRECT_STAGE\tid=%llu\tstage=target_restored\r\n",
        static_cast<unsigned long long>(menu_redirect.diagnostic_id));
  }
}

void STDMETHODCALLTYPE draw_indexed_instanced_hook(
    ID3D12GraphicsCommandList* commands, UINT index_count, UINT instance_count,
    UINT start_index, INT base_vertex, UINT start_instance) {
  queue_cluster_light_visibility_fov_patches(commands);
  record_cluster_submission(
      commands, "draw_indexed", index_count, instance_count, start_index,
      static_cast<std::uint64_t>(static_cast<std::int64_t>(base_vertex)),
      start_instance);
  if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed) ||
      billboard_horizon_lock_enabled.load(std::memory_order_relaxed)) {
    billboard_direct_draw_hook_count.fetch_add(1, std::memory_order_relaxed);
  }
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].indexed_draw_count++;
  }
  auto submitted_instance_count = instance_count;
  if (marker_log != INVALID_HANDLE_VALUE) {
    std::scoped_lock lock(trace_mutex);
    observe_table4_draw(
        commands, 1, index_count, instance_count, start_index,
        static_cast<std::uint64_t>(static_cast<std::int64_t>(base_vertex)),
        start_instance);
    log_focused_draw(
        commands, 1, index_count, instance_count, start_index,
        static_cast<std::uint64_t>(static_cast<std::int64_t>(base_vertex)),
        start_instance);
    sample_graphics_bindings(commands);
    current_pass(commands).draw_indexed++;
    submitted_instance_count = apply_candidate_batch_probe(
        commands, index_count, instance_count, start_index, base_vertex,
        start_instance);
  }
  const auto billboard_override = apply_billboard_view_basis(commands);
  const auto readback_id = index_count && submitted_instance_count ? begin_billboard_draw_readback(commands) : 0;
  original_draw_indexed_instanced(commands, index_count,
                                  submitted_instance_count, start_index,
                                  base_vertex, start_instance);
  end_billboard_draw_readback(readback_id, commands);
  if (world_ui_capture_requested()) {
    std::uintptr_t pipeline{};
    { std::scoped_lock lock(trace_mutex); pipeline = command_traces[commands].pso; }
    PsoMetadata metadata{};
    {
      std::scoped_lock lock(pso_mutex);
      const auto found = pso_metadata.find(pipeline);
      if (found != pso_metadata.end()) metadata = found->second;
    }
    auto ui = begin_world_ui_draw(commands, metadata);
    if (ui.active)
      original_draw_indexed_instanced(commands, index_count, submitted_instance_count,
                                      start_index, base_vertex, start_instance);
    end_world_ui_draw(commands, ui);
  }
  end_billboard_binding_override(commands, billboard_override);
}

void STDMETHODCALLTYPE execute_indirect_hook(
    ID3D12GraphicsCommandList* commands,
    ID3D12CommandSignature* command_signature, UINT max_command_count,
    ID3D12Resource* argument_buffer, UINT64 argument_buffer_offset,
    ID3D12Resource* count_buffer, UINT64 count_buffer_offset) {
  record_cluster_submission(
      commands, "execute_indirect", max_command_count,
      reinterpret_cast<std::uintptr_t>(argument_buffer),
      argument_buffer_offset, reinterpret_cast<std::uintptr_t>(count_buffer),
      count_buffer_offset);
  // Darktide's production particle renderer submits the exact c_billboard
  // pipeline through ExecuteIndirect. Resolve/log (and, when enabled,
  // override) the binding at the submission boundary so the descriptor-table
  // state is the one actually consumed by this draw rather than an earlier
  // table update made while the same PSO happened to remain bound.
  // Stingray's generated particle sequence is not described as a legacy
  // DRAW/DRAW_INDEXED signature on this build. The exact substituted graphics
  // PSO and the reflected 384-byte c_per_object minimum are therefore the
  // authoritative fail-closed classifiers inside apply_billboard_view_basis.
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].indirect_count++;
  }
  const auto billboard_override = apply_billboard_view_basis(commands);
  original_execute_indirect(commands, command_signature, max_command_count,
                            argument_buffer, argument_buffer_offset,
                            count_buffer, count_buffer_offset);
  end_billboard_binding_override(commands, billboard_override);
}

void record_copy_work(ID3D12GraphicsCommandList* commands) {
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].copy_count++;
  }
}

void STDMETHODCALLTYPE copy_buffer_region_hook(
    ID3D12GraphicsCommandList* commands, ID3D12Resource* destination,
    UINT64 destination_offset, ID3D12Resource* source, UINT64 source_offset,
    UINT64 bytes) {
  record_copy_work(commands);
  bool cluster_constant_ring = false;
  if (cluster_trace_log != INVALID_HANDLE_VALUE && destination && source) {
    std::scoped_lock lock(cluster_constant_copy_mutex);
    cluster_constant_ring =
        cluster_constant_ring_resources.contains(destination);
    if (cluster_constant_ring) {
      auto& copy = cluster_constant_copies[
          cluster_constant_copy_count % cluster_constant_copies.size()];
      copy = ClusterConstantBufferCopy{destination, destination_offset, source,
                                       source_offset, bytes};
      ++cluster_constant_copy_count;
    }
  }
  if (cluster_constant_ring &&
      cluster_constant_copy_log_count.fetch_add(
          1, std::memory_order_relaxed) < 256) {
    const auto source_gpu = source->GetGPUVirtualAddress() + source_offset;
    const auto source_info = resolve_buffer_resource(source_gpu);
    write_cluster_trace_log(
        "frame=%llu\tCLUSTER_C0_COPY\tCL=%p\tdestination=%p"
        "\tdestination_offset=%llu\tsource=%p\tsource_offset=%llu"
        "\tbytes=%llu\tsource_gpu=%llu\tsource_heap=%u"
        "\tsource_mapped=%u\r\n",
        static_cast<unsigned long long>(
            present_count.load(std::memory_order_relaxed)),
        commands, destination,
        static_cast<unsigned long long>(destination_offset), source,
        static_cast<unsigned long long>(source_offset),
        static_cast<unsigned long long>(bytes),
        static_cast<unsigned long long>(source_gpu),
        static_cast<unsigned>(source_info ? source_info->heap_type
                                          : D3D12_HEAP_TYPE_CUSTOM),
        source_info && source_info->mapped ? 1u : 0u);
  }
  original_copy_buffer_region(commands, destination, destination_offset,
                              source, source_offset, bytes);
}

void STDMETHODCALLTYPE copy_texture_region_hook(
    ID3D12GraphicsCommandList* commands,
    const D3D12_TEXTURE_COPY_LOCATION* destination, UINT destination_x,
    UINT destination_y, UINT destination_z,
    const D3D12_TEXTURE_COPY_LOCATION* source, const D3D12_BOX* source_box) {
  record_copy_work(commands);
  original_copy_texture_region(commands, destination, destination_x,
                               destination_y, destination_z, source,
                               source_box);
}

void STDMETHODCALLTYPE copy_resource_hook(ID3D12GraphicsCommandList* commands,
                                          ID3D12Resource* destination,
                                          ID3D12Resource* source) {
  record_copy_work(commands);
  original_copy_resource(commands, destination, source);
}

void STDMETHODCALLTYPE resolve_subresource_hook(
    ID3D12GraphicsCommandList* commands, ID3D12Resource* destination,
    UINT destination_subresource, ID3D12Resource* source,
    UINT source_subresource, DXGI_FORMAT format) {
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].resolve_count++;
  }
  original_resolve_subresource(commands, destination, destination_subresource,
                               source, source_subresource, format);
}

void STDMETHODCALLTYPE dispatch_hook(ID3D12GraphicsCommandList* commands,
                                     UINT x, UINT y, UINT z) {
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].dispatch_count++;
  }
  if (marker_log != INVALID_HANDLE_VALUE) {
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    current_pass(commands).dispatch++;
    if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
      const auto table1 = resolve_table_provenance(
          trace.compute_root_signature, 1, trace.compute_tables[1]);
      const auto table2 = resolve_table_provenance(
          trace.compute_root_signature, 2, trace.compute_tables[2]);
      const auto& t1a = table1.descriptors[0];
      const auto& t1b = table1.descriptors[1];
      const auto& t2a = table2.descriptors[0];
      const auto& t2b = table2.descriptors[1];
      write_focused_log(
          "phase=%d\tframe=%llu\tCL=%p\tDISPATCH\tgroups=%u,%u,%u\t"
          "vpx=%u\tvpy=%u\tvpw=%u\tvph=%u\tsc=%ld,%ld,%ld,%ld\t"
          "pso=%p\tsig=%p\trtv=%llu\tdsv=%llu\t"
          "tables=%llu\tconstants=%llu\tcbvs=%llu\tsrvs=%llu\tuavs=%llu\t"
          "t0=%llu\tt1=%llu\tt2=%llu\tt3=%llu\tcbv0=%llu\tcbv1=%llu\t"
          "t1prov=%u,%llu,%llu,%c,%p,%llu,%c,%p,%llu\t"
          "t2prov=%u,%llu,%llu,%c,%p,%llu,%c,%p,%llu\r\n",
          focused_trace_phase.load(std::memory_order_relaxed),
          present_count.load(std::memory_order_relaxed), commands, x, y, z,
          trace.viewport_x, trace.viewport_y, trace.viewport_width,
          trace.viewport_height, trace.scissor.left, trace.scissor.top,
          trace.scissor.right, trace.scissor.bottom,
          reinterpret_cast<void*>(trace.pso),
          reinterpret_cast<void*>(trace.compute_root_signature),
          trace.render_target, trace.depth_target,
          root_array_hash(trace.compute_tables),
          root_array_hash(trace.compute_constants),
          root_array_hash(trace.compute_cbvs),
          root_array_hash(trace.compute_srvs),
          root_array_hash(trace.compute_uavs), trace.compute_tables[0],
          trace.compute_tables[1], trace.compute_tables[2],
          trace.compute_tables[3], trace.compute_cbvs[0],
          trace.compute_cbvs[1], table1.descriptor_count,
          table1.resource_hash, table1.layout_hash, t1a.kind,
          reinterpret_cast<void*>(t1a.resource), t1a.gpu_address, t1b.kind,
          reinterpret_cast<void*>(t1b.resource), t1b.gpu_address,
          table2.descriptor_count, table2.resource_hash, table2.layout_hash,
          t2a.kind, reinterpret_cast<void*>(t2a.resource), t2a.gpu_address,
          t2b.kind, reinterpret_cast<void*>(t2b.resource), t2b.gpu_address);
    }
  }
  if (cluster_trace_log != INVALID_HANDLE_VALUE) {
    const auto presentation_mode = static_cast<
        darktidevr::core::SharedPresentationMode>(
        current_presentation_mode.load(std::memory_order_relaxed));
    if (presentation_mode !=
        darktidevr::core::SharedPresentationMode::stereo_world) {
      cluster_trace_saw_flat_presentation.store(true,
                                                std::memory_order_relaxed);
    }
    CommandTrace trace{};
    std::string marker{"<none>"};
    {
      std::scoped_lock lock(trace_mutex);
      const auto trace_found = command_traces.find(commands);
      if (trace_found != command_traces.end()) {
        trace = trace_found->second;
      }
    }
    {
      std::scoped_lock lock(boundary_capture_mutex);
      const auto marker_found = command_marker_stacks.find(commands);
      if (marker_found != command_marker_stacks.end() &&
          !marker_found->second.empty()) {
        marker = marker_found->second.back();
      }
    }
    // Startup and flat presentation execute many unrelated compute passes. A
    // bounded all-dispatch capture would otherwise exhaust itself before the
    // first hub frame. The title/loading transition provides an observed,
    // deterministic arm: record only after a non-stereo mode has been seen and
    // the producer has returned to the stereo-world mode.
    if (presentation_mode ==
            darktidevr::core::SharedPresentationMode::stereo_world &&
        cluster_trace_saw_flat_presentation.load(std::memory_order_relaxed)) {
      std::uint64_t compute_shader{};
      {
        std::scoped_lock lock(pso_mutex);
        const auto pso_found = pso_metadata.find(trace.pso);
        if (pso_found != pso_metadata.end()) {
          compute_shader = pso_found->second.compute_shader;
        }
      }
      std::uintptr_t linked_list_resource{};
      TableProvenance target_table1{};
      TableProvenance target_table2{};
      if (compute_shader == kClusterGridComputeShader) {
        target_table1 = resolve_table_provenance(
            trace.compute_root_signature, 1, trace.compute_tables[1]);
        target_table2 = resolve_table_provenance(
            trace.compute_root_signature, 2, trace.compute_tables[2]);
        // DXC reflection identifies cluster_linked_list as t0. The live
        // descriptor confirms that root table 1 descriptor 0 is an SRV with
        // 4,194,304 elements backed by a 16,777,216-byte resource. Match the
        // reflected binding and measured element count; renderer.json's
        // "width" is an element capacity, not the D3D12 byte width.
        const auto& info = target_table1.descriptors[0];
        if (target_table1.descriptor_count > 0 && info.kind == 'S' &&
            info.element_count == 4194304 && info.resource != 0) {
          linked_list_resource = info.resource;
          cluster_linked_list_resource.store(info.resource,
                                             std::memory_order_relaxed);
          cluster_linked_list_learned_frame.store(
              present_count.load(std::memory_order_relaxed),
              std::memory_order_relaxed);
        }
        if (cluster_target_dispatch_log_count.fetch_add(
                1, std::memory_order_relaxed) < 8) {
          log_cluster_predecessor_ring(commands);
        }
      }
      const auto log_generic = compute_shader != kClusterGridComputeShader &&
          cluster_generic_dispatch_log_count.fetch_add(
              1, std::memory_order_relaxed) < 512;
      if (compute_shader == kClusterGridComputeShader || log_generic) {
        write_cluster_trace_log(
          "frame=%llu\tCL=%p\tmarker=%s\tgroups=%u,%u,%u\t"
          "pso=%p\tcs=%016llx\tsig=%p\tlinked=%p\t"
          "tables=%llu,%llu,%llu,%llu\tcbvs=%llu,%llu,%llu,%llu\t"
          "constants=%llu,%llu,%llu,%llu\t"
          "t1=%u,%c,%p,%llu,%u,%u,%c,%p,%llu,%u,%u\t"
          "t2=%u,%c,%p,%llu,%u,%u,%c,%p,%llu,%u,%u\r\n",
          static_cast<unsigned long long>(
              present_count.load(std::memory_order_relaxed)),
          commands, marker.c_str(), x, y, z,
          reinterpret_cast<void*>(trace.pso),
          static_cast<unsigned long long>(compute_shader),
          reinterpret_cast<void*>(trace.compute_root_signature),
          reinterpret_cast<void*>(linked_list_resource),
          static_cast<unsigned long long>(trace.compute_tables[0]),
          static_cast<unsigned long long>(trace.compute_tables[1]),
          static_cast<unsigned long long>(trace.compute_tables[2]),
          static_cast<unsigned long long>(trace.compute_tables[3]),
          static_cast<unsigned long long>(trace.compute_cbvs[0]),
          static_cast<unsigned long long>(trace.compute_cbvs[1]),
          static_cast<unsigned long long>(trace.compute_cbvs[2]),
          static_cast<unsigned long long>(trace.compute_cbvs[3]),
          static_cast<unsigned long long>(trace.compute_constants[0]),
          static_cast<unsigned long long>(trace.compute_constants[1]),
          static_cast<unsigned long long>(trace.compute_constants[2]),
          static_cast<unsigned long long>(trace.compute_constants[3]),
          target_table1.descriptor_count,
          target_table1.descriptors[0].kind,
          reinterpret_cast<void*>(target_table1.descriptors[0].resource),
          static_cast<unsigned long long>(target_table1.descriptors[0].width),
          target_table1.descriptors[0].element_count,
          target_table1.descriptors[0].structure_stride,
          target_table1.descriptors[1].kind,
          reinterpret_cast<void*>(target_table1.descriptors[1].resource),
          static_cast<unsigned long long>(target_table1.descriptors[1].width),
          target_table1.descriptors[1].element_count,
          target_table1.descriptors[1].structure_stride,
          target_table2.descriptor_count,
          target_table2.descriptors[0].kind,
          reinterpret_cast<void*>(target_table2.descriptors[0].resource),
          static_cast<unsigned long long>(target_table2.descriptors[0].width),
          target_table2.descriptors[0].element_count,
          target_table2.descriptors[0].structure_stride,
          target_table2.descriptors[1].kind,
          reinterpret_cast<void*>(target_table2.descriptors[1].resource),
          static_cast<unsigned long long>(target_table2.descriptors[1].width),
          target_table2.descriptors[1].element_count,
          target_table2.descriptors[1].structure_stride);
      }
    }
  }
  record_cluster_submission(commands, "dispatch", x, y, z, 0, 0);
  original_dispatch(commands, x, y, z);
}

void STDMETHODCALLTYPE rs_set_viewports_hook(ID3D12GraphicsCommandList* commands,
                                             UINT count,
                                             const D3D12_VIEWPORT* viewports) {
  if ((world_ui_capture_requested() || marker_log != INVALID_HANDLE_VALUE) && count > 0 && viewports) {
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    trace.eye = viewports[0].TopLeftX > 1.0F ? 1 : 0;
    trace.viewport_x = static_cast<UINT>(viewports[0].TopLeftX + 0.5F);
    trace.viewport_y = static_cast<UINT>(viewports[0].TopLeftY + 0.5F);
    trace.viewport_width = static_cast<UINT>(viewports[0].Width + 0.5F);
    trace.viewport_height = static_cast<UINT>(viewports[0].Height + 0.5F);
    if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
      write_focused_log(
          "phase=%d\tframe=%llu\tCL=%p\tVIEWPORT\tcount=%u\t"
          "x=%.3f\ty=%.3f\tw=%.3f\th=%.3f\tdepth=%.6f,%.6f\r\n",
          focused_trace_phase.load(std::memory_order_relaxed),
          present_count.load(std::memory_order_relaxed), commands, count,
          viewports[0].TopLeftX, viewports[0].TopLeftY, viewports[0].Width,
          viewports[0].Height, viewports[0].MinDepth, viewports[0].MaxDepth);
    }
  }

  const D3D12_VIEWPORT* submitted_viewports = viewports;
  D3D12_VIEWPORT remapped_viewport{};
  ViewportRemapState remap_state{};
  if (rich_center_sbs_remap_enabled.load(std::memory_order_relaxed) &&
      count == 1 && viewports && viewports[0].Width >= 16.0F) {
    const auto& source = viewports[0];
    const float horizontal_ratio = source.TopLeftX / source.Width;

    // The Lua probe tags two otherwise equivalent rich-center half-width
    // viewports with x/width ratios 0.996 (left eye) and 1.0 (right eye).
    // Stingray therefore evaluates both at the known-rich screen center.  At
    // command recording time, move their raster output back to true SBS.
    if (horizontal_ratio >= 0.99F && horizontal_ratio <= 1.01F) {
      const int eye = horizontal_ratio < 0.998F ? 0 : 1;
      remapped_viewport = source;
      remapped_viewport.TopLeftX = eye == 0 ? 0.0F : source.Width;
      submitted_viewports = &remapped_viewport;
      remap_state.active = true;
      remap_state.scissor_delta = static_cast<LONG>(
          remapped_viewport.TopLeftX - source.TopLeftX);
      remap_state.logical_left = static_cast<LONG>(source.TopLeftX + 0.5F);
      remap_state.logical_right =
          static_cast<LONG>(source.TopLeftX + source.Width + 0.5F);
    }
  }
  if (rich_center_sbs_remap_enabled.load(std::memory_order_relaxed)) {
    std::scoped_lock lock(viewport_remap_mutex);
    viewport_remap_states[commands] = remap_state;
  }
  original_rs_set_viewports(commands, count, submitted_viewports);
}

void STDMETHODCALLTYPE rs_set_scissor_rects_hook(
    ID3D12GraphicsCommandList* commands, UINT count,
    const D3D12_RECT* rectangles) {
  if (marker_log != INVALID_HANDLE_VALUE && count > 0 && rectangles) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].scissor = rectangles[0];
    if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
      write_focused_log(
          "phase=%d\tframe=%llu\tCL=%p\tSCISSOR\tcount=%u\t"
          "rect=%ld,%ld,%ld,%ld\r\n",
          focused_trace_phase.load(std::memory_order_relaxed),
          present_count.load(std::memory_order_relaxed), commands, count,
          rectangles[0].left, rectangles[0].top, rectangles[0].right,
          rectangles[0].bottom);
    }
  }

  const D3D12_RECT* submitted_rectangles = rectangles;
  D3D12_RECT remapped_rectangle{};
  if (rich_center_sbs_remap_enabled.load(std::memory_order_relaxed) &&
      count == 1 && rectangles) {
    ViewportRemapState state{};
    {
      std::scoped_lock lock(viewport_remap_mutex);
      const auto found = viewport_remap_states.find(commands);
      if (found != viewport_remap_states.end()) {
        state = found->second;
      }
    }
    const auto& source = rectangles[0];
    if (state.active && source.left >= state.logical_left - 2 &&
        source.right <= state.logical_right + 2) {
      remapped_rectangle = source;
      remapped_rectangle.left =
          (std::max)(0L, source.left + state.scissor_delta);
      remapped_rectangle.right =
          (std::max)(remapped_rectangle.left,
                     source.right + state.scissor_delta);
      submitted_rectangles = &remapped_rectangle;
    }
  }
  original_rs_set_scissor_rects(commands, count, submitted_rectangles);
}

void STDMETHODCALLTYPE ia_set_primitive_topology_hook(
    ID3D12GraphicsCommandList* commands,
    D3D12_PRIMITIVE_TOPOLOGY topology) {
  if (marker_log != INVALID_HANDLE_VALUE) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].primitive_topology = topology;
  }
  original_ia_set_primitive_topology(commands, topology);
}

void STDMETHODCALLTYPE ia_set_index_buffer_hook(
    ID3D12GraphicsCommandList* commands,
    const D3D12_INDEX_BUFFER_VIEW* view) {
  if (marker_log != INVALID_HANDLE_VALUE) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].index_buffer = view ? *view
                                                  : D3D12_INDEX_BUFFER_VIEW{};
  }
  original_ia_set_index_buffer(commands, view);
}

void STDMETHODCALLTYPE ia_set_vertex_buffers_hook(
    ID3D12GraphicsCommandList* commands, UINT start_slot, UINT count,
    const D3D12_VERTEX_BUFFER_VIEW* views) {
  if ((marker_log != INVALID_HANDLE_VALUE ||
       billboard_horizon_lock_enabled.load(std::memory_order_relaxed)) &&
      start_slot < 8) {
    std::scoped_lock lock(trace_mutex);
    auto& buffers = command_traces[commands].vertex_buffers;
    const auto end_slot = (std::min)(start_slot + count, 8U);
    for (UINT slot = start_slot; slot < end_slot; ++slot) {
      buffers[slot] = views ? views[slot - start_slot]
                            : D3D12_VERTEX_BUFFER_VIEW{};
    }
  }
  original_ia_set_vertex_buffers(commands, start_slot, count, views);
}

void STDMETHODCALLTYPE set_pipeline_state_hook(
    ID3D12GraphicsCommandList* commands, ID3D12PipelineState* state) {
  dump_pipeline_blob_if_requested(state);
  PsoMetadata first_bound_metadata{};
  bool log_first_billboard_bind{};
  // A full first-bind census is diagnostic data. Production shader
  // substitution already records the small set of replacement PSOs at
  // creation time and must not take pso_mutex on every pipeline bind.
  if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed) &&
      billboard_shader_substitution_requested.load(std::memory_order_relaxed) &&
      state) {
    const auto key = reinterpret_cast<std::uintptr_t>(state);
    std::scoped_lock lock(pso_mutex);
    if (logged_billboard_bound_psos.size() < 4096 &&
        logged_billboard_bound_psos.insert(key).second) {
      const auto found = pso_metadata.find(key);
      if (found != pso_metadata.end()) {
        first_bound_metadata = found->second;
      }
      log_first_billboard_bind = true;
    }
  }
  if (log_first_billboard_bind) {
    write_billboard_pso_identity(
        "first-bind", reinterpret_cast<std::uintptr_t>(state),
        first_bound_metadata);
  }
  const auto focused =
      focused_trace_phase.load(std::memory_order_relaxed) != 0;
  if (world_ui_capture_requested() || marker_log != INVALID_HANDLE_VALUE ||
      cluster_trace_log != INVALID_HANDLE_VALUE ||
      cluster_light_visibility_fix_active.load(std::memory_order_relaxed) ||
      kStockMenuSwapchainCaptureEnabled ||
      menu_direct_capture_enabled.load(std::memory_order_relaxed) ||
      billboard_horizon_lock_enabled.load(std::memory_order_relaxed) ||
      focused) {
    bool metadata_missing{};
    bool cluster_light_raster{};
    {
      std::scoped_lock lock(pso_mutex);
      const auto found = state
                             ? pso_metadata.find(
                                   reinterpret_cast<std::uintptr_t>(state))
                             : pso_metadata.end();
      metadata_missing = state && found == pso_metadata.end();
      cluster_light_raster =
          found != pso_metadata.end() &&
          found->second.vertex_shader == kClusterLightRasterVertexShader &&
          found->second.pixel_shader == kClusterLightRasterPixelShader;
    }
    if (metadata_missing) {
      ComPtr<ID3DBlob> blob;
      PsoMetadata metadata{};
      if (SUCCEEDED(state->GetCachedBlob(&blob)) && blob) {
        metadata.cached_blob =
            hash_bytes(blob->GetBufferPointer(), blob->GetBufferSize());
        metadata.billboard_shader = cached_blob_contains_billboard_shader(
            blob->GetBufferPointer(), blob->GetBufferSize());
      }
      std::scoped_lock lock(pso_mutex);
      pso_metadata.emplace(reinterpret_cast<std::uintptr_t>(state), metadata);
    }
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    trace.pso = reinterpret_cast<std::uintptr_t>(state);
    trace.cluster_light_raster = cluster_light_raster;
    if (focused) {
      write_focused_log("phase=%d\tframe=%llu\tCL=%p\tPSO\tgen=%llu\tpso=%p\r\n",
                        focused_trace_phase.load(std::memory_order_relaxed),
                        present_count.load(std::memory_order_relaxed), commands,
                        static_cast<unsigned long long>(
                            trace.recording_generation),
                        state);
    }
  }
  original_set_pipeline_state(commands, state);
}

void STDMETHODCALLTYPE set_descriptor_heaps_hook(
    ID3D12GraphicsCommandList* commands, UINT heap_count,
    ID3D12DescriptorHeap* const* heaps) {
  // This hook exists only in the diagnostic renderer set. Stingray can bind a
  // long-lived heap before Lua enables a particular probe, so provenance must
  // be retained from the first intercepted SetDescriptorHeaps call.
  {
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    for (UINT i = 0; heaps && i < heap_count; ++i) {
      if (!heaps[i]) {
        continue;
      }
      const auto description = heaps[i]->GetDesc();
      if (description.Type == D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV) {
        trace.graphics_resource_heap = heaps[i];
      } else if (description.Type == D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER) {
        trace.graphics_sampler_heap = heaps[i];
      }
    }
  }
  for (UINT i = 0; heaps && i < heap_count; ++i) {
    ComPtr<ID3D12Device> device;
    if (heaps[i] &&
        SUCCEEDED(heaps[i]->GetDevice(IID_PPV_ARGS(&device)))) {
      record_descriptor_heap(device.Get(), heaps[i]);
    }
  }
  original_set_descriptor_heaps(commands, heap_count, heaps);
}

void STDMETHODCALLTYPE set_graphics_root_signature_hook(
    ID3D12GraphicsCommandList* commands, ID3D12RootSignature* signature) {
  const auto signature_address = reinterpret_cast<std::uintptr_t>(signature);
  if (marker_log != INVALID_HANDLE_VALUE ||
      cluster_trace_log != INVALID_HANDLE_VALUE ||
      billboard_horizon_lock_enabled.load(std::memory_order_relaxed)) {
    {
      std::scoped_lock lock(trace_mutex);
      auto& trace = command_traces[commands];
      trace.root_signature = signature_address;
      trace.graphics_tables = {};
      trace.graphics_constants = {};
      trace.graphics_cbvs = {};
      trace.graphics_srvs = {};
      trace.graphics_uavs = {};
    }
    RootSignatureMetadata metadata{};
    bool should_log{};
    {
      std::scoped_lock lock(root_signature_mutex);
      const auto found = root_signature_metadata.find(signature_address);
      if (found != root_signature_metadata.end()) {
        metadata = found->second;
      }
      should_log = logged_root_signatures.insert(signature_address).second;
    }
    if (should_log && marker_log != INVALID_HANDLE_VALUE) {
      write_marker_log("%llu\t%lu\tROOTSIG\tsig=%p\tparams=%u\tflags=%u\r\n",
                       marker_sequence.fetch_add(1, std::memory_order_relaxed),
                       GetCurrentThreadId(), signature,
                       metadata.parameter_count, metadata.flags);
      for (UINT i = 0; i < metadata.parameter_count; ++i) {
        const auto& parameter = metadata.parameters[i];
        write_marker_log(
            "%llu\t%lu\tROOTPARAM\tsig=%p\tslot=%u\ttype=%u\tvis=%u\tcbv=%llu\tsrv=%llu\tuav=%llu\tsampler=%llu\tlayout=%llu\r\n",
            marker_sequence.fetch_add(1, std::memory_order_relaxed),
            GetCurrentThreadId(), signature, i, parameter.type,
            parameter.visibility, parameter.cbv_count, parameter.srv_count,
            parameter.uav_count, parameter.sampler_count,
            parameter.layout_hash);
      }
    }
  }
  original_set_graphics_root_signature(commands, signature);
}

void STDMETHODCALLTYPE set_compute_root_signature_hook(
    ID3D12GraphicsCommandList* commands, ID3D12RootSignature* signature) {
  if (marker_log != INVALID_HANDLE_VALUE ||
      cluster_trace_log != INVALID_HANDLE_VALUE ||
      focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    trace.compute_root_signature = reinterpret_cast<std::uintptr_t>(signature);
    trace.compute_tables = {};
    trace.compute_constants = {};
    trace.compute_cbvs = {};
    trace.compute_srvs = {};
    trace.compute_uavs = {};
  }
  original_set_compute_root_signature(commands, signature);
}

void STDMETHODCALLTYPE set_graphics_root_descriptor_table_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index,
    D3D12_GPU_DESCRIPTOR_HANDLE table) {
  if ((marker_log != INVALID_HANDLE_VALUE ||
       cluster_trace_log != INVALID_HANDLE_VALUE ||
       billboard_horizon_lock_enabled.load(std::memory_order_relaxed)) &&
      root_index < kRootSlotCount) {
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    trace.graphics_tables[root_index] = table.ptr;
  }
  // Do not sample the billboard CBV here. A target PSO can remain bound while
  // the engine stages several unrelated descriptor tables, so a table update
  // is not evidence that the descriptor will be consumed by the particle
  // draw. The ExecuteIndirect hook samples the complete bound state at the
  // actual submission boundary.
  original_set_graphics_root_descriptor_table(commands, root_index, table);
}

void STDMETHODCALLTYPE set_compute_root_descriptor_table_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index,
    D3D12_GPU_DESCRIPTOR_HANDLE table) {
  if ((marker_log != INVALID_HANDLE_VALUE ||
       cluster_trace_log != INVALID_HANDLE_VALUE) &&
      root_index < kRootSlotCount) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].compute_tables[root_index] = table.ptr;
  }
  original_set_compute_root_descriptor_table(commands, root_index, table);
}

void STDMETHODCALLTYPE set_graphics_root_32bit_constant_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index, UINT value,
    UINT destination_offset) {
  if (marker_log != INVALID_HANDLE_VALUE && root_index < kRootSlotCount) {
    std::scoped_lock lock(trace_mutex);
    auto& state = command_traces[commands].graphics_constants[root_index];
    state = mix_u64(state, destination_offset);
    state = mix_u64(state, value);
  }
  original_set_graphics_root_32bit_constant(commands, root_index, value,
                                             destination_offset);
}

void STDMETHODCALLTYPE set_compute_root_32bit_constant_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index, UINT value,
    UINT destination_offset) {
  if ((marker_log != INVALID_HANDLE_VALUE ||
       cluster_trace_log != INVALID_HANDLE_VALUE) &&
      root_index < kRootSlotCount) {
    std::scoped_lock lock(trace_mutex);
    auto& state = command_traces[commands].compute_constants[root_index];
    state = mix_u64(state, destination_offset);
    state = mix_u64(state, value);
  }
  original_set_compute_root_32bit_constant(commands, root_index, value,
                                            destination_offset);
}

void STDMETHODCALLTYPE set_graphics_root_32bit_constants_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index, UINT value_count,
    const void* values, UINT destination_offset) {
  if (marker_log != INVALID_HANDLE_VALUE && root_index < kRootSlotCount) {
    std::scoped_lock lock(trace_mutex);
    auto& state = command_traces[commands].graphics_constants[root_index];
    state = mix_u64(state, destination_offset);
    state = mix_u64(state, value_count);
    state = mix_u64(
        state, hash_bytes(values, static_cast<std::size_t>(value_count) *
                                     sizeof(UINT)));
  }
  original_set_graphics_root_32bit_constants(
      commands, root_index, value_count, values, destination_offset);
}

void STDMETHODCALLTYPE set_compute_root_32bit_constants_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index, UINT value_count,
    const void* values, UINT destination_offset) {
  if ((marker_log != INVALID_HANDLE_VALUE ||
       cluster_trace_log != INVALID_HANDLE_VALUE) &&
      root_index < kRootSlotCount) {
    std::scoped_lock lock(trace_mutex);
    auto& state = command_traces[commands].compute_constants[root_index];
    state = mix_u64(state, destination_offset);
    state = mix_u64(state, value_count);
    state = mix_u64(
        state, hash_bytes(values, static_cast<std::size_t>(value_count) *
                                     sizeof(UINT)));
  }
  original_set_compute_root_32bit_constants(
      commands, root_index, value_count, values, destination_offset);
}

void set_graphics_root_gpu_address(
    ID3D12GraphicsCommandList* commands, UINT root_index,
    D3D12_GPU_VIRTUAL_ADDRESS address,
    std::array<std::uint64_t, kRootSlotCount> CommandTrace::*member) {
  if ((marker_log != INVALID_HANDLE_VALUE ||
       cluster_trace_log != INVALID_HANDLE_VALUE ||
       cluster_light_visibility_fix_active.load(std::memory_order_relaxed) ||
       billboard_horizon_lock_enabled.load(std::memory_order_relaxed)) &&
      root_index < kRootSlotCount) {
    std::scoped_lock lock(trace_mutex);
    (command_traces[commands].*member)[root_index] = address;
  }
}

void set_compute_root_gpu_address(
    ID3D12GraphicsCommandList* commands, UINT root_index,
    D3D12_GPU_VIRTUAL_ADDRESS address,
    std::array<std::uint64_t, kRootSlotCount> CommandTrace::*member) {
  if ((marker_log != INVALID_HANDLE_VALUE ||
       cluster_trace_log != INVALID_HANDLE_VALUE) &&
      root_index < kRootSlotCount) {
    std::scoped_lock lock(trace_mutex);
    (command_traces[commands].*member)[root_index] = address;
  }
}

void STDMETHODCALLTYPE set_graphics_root_constant_buffer_view_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index,
    D3D12_GPU_VIRTUAL_ADDRESS address) {
  set_graphics_root_gpu_address(commands, root_index, address,
                                &CommandTrace::graphics_cbvs);
  original_set_graphics_root_constant_buffer_view(commands, root_index,
                                                   address);
}

void STDMETHODCALLTYPE set_graphics_root_shader_resource_view_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index,
    D3D12_GPU_VIRTUAL_ADDRESS address) {
  set_graphics_root_gpu_address(commands, root_index, address,
                                &CommandTrace::graphics_srvs);
  original_set_graphics_root_shader_resource_view(commands, root_index,
                                                   address);
}

void STDMETHODCALLTYPE set_graphics_root_unordered_access_view_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index,
    D3D12_GPU_VIRTUAL_ADDRESS address) {
  set_graphics_root_gpu_address(commands, root_index, address,
                                &CommandTrace::graphics_uavs);
  original_set_graphics_root_unordered_access_view(commands, root_index,
                                                    address);
}

void STDMETHODCALLTYPE set_compute_root_constant_buffer_view_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index,
    D3D12_GPU_VIRTUAL_ADDRESS address) {
  set_compute_root_gpu_address(commands, root_index, address,
                               &CommandTrace::compute_cbvs);
  original_set_compute_root_constant_buffer_view(commands, root_index, address);
}

void STDMETHODCALLTYPE set_compute_root_shader_resource_view_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index,
    D3D12_GPU_VIRTUAL_ADDRESS address) {
  set_compute_root_gpu_address(commands, root_index, address,
                               &CommandTrace::compute_srvs);
  original_set_compute_root_shader_resource_view(commands, root_index, address);
}

void STDMETHODCALLTYPE set_compute_root_unordered_access_view_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index,
    D3D12_GPU_VIRTUAL_ADDRESS address) {
  set_compute_root_gpu_address(commands, root_index, address,
                               &CommandTrace::compute_uavs);
  original_set_compute_root_unordered_access_view(commands, root_index, address);
}

DescriptorInfo descriptor_snapshot(std::uint64_t handle) {
  std::scoped_lock lock(descriptor_mutex);
  const auto found = descriptor_metadata.find(handle);
  return found == descriptor_metadata.end() ? DescriptorInfo{} : found->second;
}

void record_gpu_stage_boundary(ID3D12GraphicsCommandList* commands,
                               const DescriptorInfo& target) {
  if (!gpu_profile_enabled.load(std::memory_order_relaxed) || !commands ||
      !gpu_profile_query_heap || target.width == 0 || target.height == 0) {
    return;
  }
  const auto output_width =
      swapchain_render_width.load(std::memory_order_relaxed);
  const auto output_height =
      swapchain_render_height.load(std::memory_order_relaxed);
  if (output_width == 0 || output_height == 0) {
    return;
  }

  std::scoped_lock lock(gpu_profile_mutex);
  for (auto& active : gpu_profile_active) {
    if (!active || active->stage_boundary_recorded) {
      continue;
    }
    if (target.width < output_width && target.height < output_height) {
      active->internal_target_seen = true;
      continue;
    }
    // This is a structural resolution transition, not a semantic pass marker.
    // Stingray interleaves internal- and output-sized resources, so consumers
    // must not label the two intervals as "world" and "post processing".
    if (active->internal_target_seen && target.width == output_width &&
        target.height == output_height) {
      commands->EndQuery(gpu_profile_query_heap.Get(),
                         D3D12_QUERY_TYPE_TIMESTAMP,
                         active->slot * kGpuProfileQueriesPerSlot + 1U);
      active->stage_boundary_recorded = true;
    }
  }
}

void log_output_descriptor(const char* event, UINT slot,
                           std::uint64_t handle) {
  const auto info = descriptor_snapshot(handle);
  write_focused_log(
      "phase=%d\tframe=%llu\t%s\tslot=%u\thandle=%llu\tkind=%c"
      "\tresource=%p\tformat=%u\tdimension=%u\twidth=%llu\theight=%u"
      "\tarray=%u\tmips=%u\r\n",
      focused_trace_phase.load(std::memory_order_relaxed),
      present_count.load(std::memory_order_relaxed), event, slot, handle,
      info.kind, reinterpret_cast<void*>(info.resource), info.format,
      info.dimension, info.width, info.height, info.depth_or_array_size,
      info.mip_levels);
}

void STDMETHODCALLTYPE om_set_render_targets_hook(
    ID3D12GraphicsCommandList* commands, UINT count,
    const D3D12_CPU_DESCRIPTOR_HANDLE* targets, BOOL single_range,
    const D3D12_CPU_DESCRIPTOR_HANDLE* depth) {
  const bool inspect_bound_target =
      gpu_profile_enabled.load(std::memory_order_relaxed) ||
      !named_camera_outputs_ready_hint.load(std::memory_order_acquire);
  if (inspect_bound_target && count > 0 && targets) {
    const auto target = descriptor_snapshot(targets[0].ptr);
    record_gpu_stage_boundary(commands, target);
    auto* resource = reinterpret_cast<ID3D12Resource*>(target.resource);
    if (resource) {
      std::scoped_lock lock(boundary_capture_mutex);
      if (swapchain_back_buffers.find(resource) !=
          swapchain_back_buffers.end()) {
        swapchain_back_buffer_states[resource] =
            D3D12_RESOURCE_STATE_RENDER_TARGET;
        if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed)) {
          boundary_transition_count.fetch_add(1, std::memory_order_relaxed);
        }
      }
    }
  }
  const auto focused =
      focused_trace_phase.load(std::memory_order_relaxed) != 0;
  if (billboard_readback_accepting.load(std::memory_order_relaxed) ||
      world_ui_capture_requested() || marker_log != INVALID_HANDLE_VALUE ||
      menu_direct_capture_enabled.load(std::memory_order_relaxed) || focused) {
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    trace.render_target_count = count;
    trace.render_target =
        count > 0 && targets ? static_cast<std::uint64_t>(targets[0].ptr) : 0;
    trace.depth_target =
        depth ? static_cast<std::uint64_t>(depth->ptr) : 0;
    if (focused) {
      write_focused_log(
          "phase=%d\tframe=%llu\tCL=%p\tRTV\tcount=%u\trtv=%llu\tdsv=%llu"
          "\tsingle_range=%u\r\n",
          focused_trace_phase.load(std::memory_order_relaxed),
          present_count.load(std::memory_order_relaxed), commands, count,
          trace.render_target, trace.depth_target, single_range);
    }
  }
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    const auto logged_count = (std::min)(count, 8U);
    if (targets) {
      if (!single_range) {
        for (UINT i = 0; i < logged_count; ++i) {
          log_output_descriptor("RTV_RESOURCE", i, targets[i].ptr);
        }
      } else {
        log_output_descriptor("RTV_RESOURCE", 0, targets[0].ptr);
      }
    }
    if (depth) {
      log_output_descriptor("DSV_RESOURCE", 0, depth->ptr);
    }
  }
  original_om_set_render_targets(commands, count, targets, single_range, depth);
}

void STDMETHODCALLTYPE clear_render_target_view_hook(
    ID3D12GraphicsCommandList* commands,
    D3D12_CPU_DESCRIPTOR_HANDLE target, const FLOAT color[4], UINT rect_count,
    const D3D12_RECT* rects) {
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    log_output_descriptor("CLEAR_RTV", 0, target.ptr);
    write_focused_log(
        "phase=%d\tframe=%llu\tCL=%p\tCLEAR_RTV_COLOR\thandle=%llu"
        "\trgba=%.6f,%.6f,%.6f,%.6f\trects=%u\r\n",
        focused_trace_phase.load(std::memory_order_relaxed),
        present_count.load(std::memory_order_relaxed), commands, target.ptr,
        color ? color[0] : 0.0f, color ? color[1] : 0.0f,
        color ? color[2] : 0.0f, color ? color[3] : 0.0f, rect_count);
  }
  original_clear_render_target_view(commands, target, color, rect_count, rects);
}

void STDMETHODCALLTYPE clear_depth_stencil_view_hook(
    ID3D12GraphicsCommandList* commands,
    D3D12_CPU_DESCRIPTOR_HANDLE depth, D3D12_CLEAR_FLAGS flags,
    FLOAT depth_value, UINT8 stencil, UINT rect_count,
    const D3D12_RECT* rects) {
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    log_output_descriptor("CLEAR_DSV", 0, depth.ptr);
    write_focused_log(
        "phase=%d\tframe=%llu\tCL=%p\tCLEAR_DSV_VALUE\thandle=%llu"
        "\tflags=%u\tdepth=%.6f\tstencil=%u\trects=%u\r\n",
        focused_trace_phase.load(std::memory_order_relaxed),
        present_count.load(std::memory_order_relaxed), commands, depth.ptr,
        flags, depth_value, stencil, rect_count);
  }
  original_clear_depth_stencil_view(commands, depth, flags, depth_value,
                                    stencil, rect_count, rects);
}

void STDMETHODCALLTYPE resource_barrier_hook(
    ID3D12GraphicsCommandList* commands, UINT barrier_count,
    const D3D12_RESOURCE_BARRIER* barriers) {
  if (billboard_readback_accepting.load(std::memory_order_relaxed)) {
    std::scoped_lock lock(trace_mutex);
    billboard_resource_states[commands].observe(barrier_count, barriers);
  }
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].barrier_count += barrier_count;
  }
  const auto cluster_resource = reinterpret_cast<ID3D12Resource*>(
      cluster_linked_list_resource.load(std::memory_order_relaxed));
  if (cluster_trace_log != INVALID_HANDLE_VALUE && cluster_resource &&
      barriers) {
    std::uintptr_t pso{};
    {
      std::scoped_lock lock(trace_mutex);
      const auto found = command_traces.find(commands);
      if (found != command_traces.end()) {
        pso = found->second.pso;
      }
    }
    for (UINT index = 0; index < barrier_count; ++index) {
      const auto& barrier = barriers[index];
      if (barrier.Type == D3D12_RESOURCE_BARRIER_TYPE_TRANSITION &&
          barrier.Transition.pResource == cluster_resource &&
          cluster_barrier_log_count.fetch_add(
              1, std::memory_order_relaxed) < 256) {
        write_cluster_trace_log(
            "frame=%llu\tCLUSTER_BARRIER\tCL=%p\tpso=%p\ttype=transition"
            "\tindex=%u\tflags=%u\tbefore=%u\tafter=%u\tsubresource=%u\r\n",
            static_cast<unsigned long long>(
                present_count.load(std::memory_order_relaxed)),
            commands, reinterpret_cast<void*>(pso), index,
            static_cast<unsigned>(barrier.Flags),
            static_cast<unsigned>(barrier.Transition.StateBefore),
            static_cast<unsigned>(barrier.Transition.StateAfter),
            barrier.Transition.Subresource);
      } else if (barrier.Type == D3D12_RESOURCE_BARRIER_TYPE_UAV &&
                 barrier.UAV.pResource == cluster_resource &&
                 cluster_barrier_log_count.fetch_add(
                     1, std::memory_order_relaxed) < 256) {
        write_cluster_trace_log(
            "frame=%llu\tCLUSTER_BARRIER\tCL=%p\tpso=%p\ttype=uav"
            "\tindex=%u\tflags=%u\r\n",
            static_cast<unsigned long long>(
                present_count.load(std::memory_order_relaxed)),
            commands, reinterpret_cast<void*>(pso), index,
            static_cast<unsigned>(barrier.Flags));
      }
    }
  }
  const bool census_enabled = boundary_census_log != INVALID_HANDLE_VALUE;
  const bool enhanced_log_enabled =
      enhanced_barrier_log != INVALID_HANDLE_VALUE;
  const bool collect_candidates =
      census_enabled ||
      camera_output_candidate_index.load(std::memory_order_relaxed) >= 0;
  bool has_transition_barrier{};
  if (barriers) {
    for (UINT index = 0; index < barrier_count; ++index) {
      if (barriers[index].Type == D3D12_RESOURCE_BARRIER_TYPE_TRANSITION) {
        has_transition_barrier = true;
        break;
      }
    }
  }
  if (has_transition_barrier) {
    std::scoped_lock lock(boundary_capture_mutex);
    for (UINT index = 0; index < barrier_count; ++index) {
      const auto& barrier = barriers[index];
      if (barrier.Type == D3D12_RESOURCE_BARRIER_TYPE_TRANSITION &&
          barrier.Transition.pResource) {
        const auto shader_resource_state =
            D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE |
            D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE;
        const bool is_output_reuse_begin =
            barrier.Flags == D3D12_RESOURCE_BARRIER_FLAG_NONE &&
            barrier.Transition.StateBefore == shader_resource_state &&
            barrier.Transition.StateAfter ==
                D3D12_RESOURCE_STATE_RENDER_TARGET;
        const bool is_output_completion =
            barrier.Flags == D3D12_RESOURCE_BARRIER_FLAG_NONE &&
            barrier.Transition.StateBefore ==
                D3D12_RESOURCE_STATE_RENDER_TARGET &&
            barrier.Transition.StateAfter == shader_resource_state;
        const bool is_swapchain_resource =
            swapchain_back_buffers.find(barrier.Transition.pResource) !=
            swapchain_back_buffers.end();
        const bool is_named_menu_completion =
            kNamedMenuResourceCaptureEnabled &&
            barrier.Flags == D3D12_RESOURCE_BARRIER_FLAG_NONE &&
            barrier.Transition.StateBefore ==
                D3D12_RESOURCE_STATE_RENDER_TARGET &&
            barrier.Transition.StateAfter !=
                D3D12_RESOURCE_STATE_RENDER_TARGET &&
            is_named_menu_ui_resource(barrier.Transition.pResource);
        const auto frame = present_count.load(std::memory_order_relaxed);
        const auto options_armed_frame =
            options_menu_capture_armed_frame.load(std::memory_order_relaxed);
        const bool options_capture_armed =
            options_armed_frame !=
                (std::numeric_limits<std::uint64_t>::max)() &&
            frame >= options_armed_frame &&
            frame - options_armed_frame <= 2;
        const bool is_options_retained_target_completion =
            options_capture_armed && is_output_completion &&
            barrier.Transition.pResource ==
                options_layer_resources[0].load(std::memory_order_acquire);
        if (is_named_menu_completion ||
            is_options_retained_target_completion) {
          menu_output_resources[commands] = barrier.Transition.pResource;
          menu_output_source_states[commands] =
              barrier.Transition.StateAfter;
          const auto menu_description =
              barrier.Transition.pResource->GetDesc();
          write_menu_resource_log(
              "MENU_MATCH\tframe=%llu\tCL=%p\tresource=%p\tstate=%u"
              "\twidth=%llu\theight=%u\tformat=%u\tsource=%s\r\n",
              frame, commands, barrier.Transition.pResource,
              static_cast<unsigned>(barrier.Transition.StateAfter),
              static_cast<unsigned long long>(menu_description.Width),
              menu_description.Height,
              static_cast<unsigned>(menu_description.Format),
              is_options_retained_target_completion ? "options_retained"
                                                    : "named");
        }
        if (is_swapchain_resource &&
            barrier.Flags != D3D12_RESOURCE_BARRIER_FLAG_BEGIN_ONLY) {
          swapchain_back_buffer_states[barrier.Transition.pResource] =
              barrier.Transition.StateAfter;
        }
        if (is_swapchain_resource &&
            barrier.Flags != D3D12_RESOURCE_BARRIER_FLAG_BEGIN_ONLY &&
            barrier.Transition.StateAfter == D3D12_RESOURCE_STATE_PRESENT) {
          present_transition_resources[commands] =
              barrier.Transition.pResource;
          if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed)) {
            boundary_transition_count.fetch_add(1, std::memory_order_relaxed);
          }
        }
        if (!census_enabled && !enhanced_log_enabled &&
            !is_output_reuse_begin && !is_output_completion &&
            !gpu_profile_enabled.load(std::memory_order_relaxed)) {
          continue;
        }
        const auto transition_ordinal = collect_candidates
                                            ? ++command_transition_ordinals[commands]
                                            : 0;
        const auto description = barrier.Transition.pResource->GetDesc();
        if (description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
            description.Width == 2112 && description.Height == 1188) {
          write_menu_resource_log(
              "MENU_RESOURCE\tframe=%llu\tCL=%p\tresource=%p"
              "\tbefore=%u\tafter=%u\tflags=%u\tformat=%u\tname=%s\r\n",
              present_count.load(std::memory_order_relaxed), commands,
              barrier.Transition.pResource,
              static_cast<unsigned>(barrier.Transition.StateBefore),
              static_cast<unsigned>(barrier.Transition.StateAfter),
              static_cast<unsigned>(barrier.Flags),
              static_cast<unsigned>(description.Format),
              resource_debug_name(barrier.Transition.pResource).c_str());
        }
        DescriptorInfo stage_target{};
        stage_target.width = description.Width;
        stage_target.height = description.Height;
        record_gpu_stage_boundary(commands, stage_target);
        if (census_enabled &&
            description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
            camera_capture_extent_matches(description.Width,
                                          description.Height) &&
            is_named_eye_output_resource(barrier.Transition.pResource)) {
          write_boundary_census_log(
              "frame=%llu\tEYE_OUTPUT_TRANSITION\tCL=%p\tresource=%p"
              "\tordinal=%llu\tbefore=%u\tafter=%u\tflags=%u\tformat=%u"
              "\tname=%s\r\n",
              present_count.load(std::memory_order_relaxed), commands,
              barrier.Transition.pResource,
              static_cast<unsigned long long>(transition_ordinal),
              static_cast<unsigned>(barrier.Transition.StateBefore),
              static_cast<unsigned>(barrier.Transition.StateAfter),
              static_cast<unsigned>(barrier.Flags),
              static_cast<unsigned>(description.Format),
              resource_debug_name(barrier.Transition.pResource).c_str());
        }
        if (enhanced_log_enabled &&
            description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
            description.Width >= 1920 && description.Height >= 1080) {
          write_enhanced_barrier_log(
              "frame=%llu\tthread=%lu\tCL=%p\tresource=%p\twidth=%llu"
              "\theight=%u\tformat=%u\tlegacy_before=%u"
              "\tlegacy_after=%u\tflags=%u\r\n",
              present_count.load(std::memory_order_relaxed),
              GetCurrentThreadId(), commands, barrier.Transition.pResource,
              description.Width, description.Height,
              static_cast<unsigned>(description.Format),
              static_cast<unsigned>(barrier.Transition.StateBefore),
              static_cast<unsigned>(barrier.Transition.StateAfter),
              static_cast<unsigned>(barrier.Flags));
        }
        if (census_enabled &&
            description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
            camera_capture_extent_matches(description.Width,
                                          description.Height) &&
            barrier.Transition.StateAfter ==
                D3D12_RESOURCE_STATE_RENDER_TARGET &&
            barrier.Flags == D3D12_RESOURCE_BARRIER_FLAG_NONE) {
          const auto debug_name =
              resource_debug_name(barrier.Transition.pResource);
          const auto marker_found = command_marker_stacks.find(commands);
          const auto marker = marker_found != command_marker_stacks.end() &&
                                      !marker_found->second.empty()
                                  ? marker_found->second.back()
                                  : std::string{};
          write_boundary_census_log(
              "frame=%llu\tDIM_RT\tCL=%p\tresource=%p\tordinal=%llu"
              "\tbefore=%u\tformat=%u\tswapchain=%u\tname=%s\tmarker=%s\r\n",
              present_count.load(std::memory_order_relaxed), commands,
              barrier.Transition.pResource,
              static_cast<unsigned long long>(transition_ordinal),
              static_cast<unsigned>(barrier.Transition.StateBefore),
              static_cast<unsigned>(description.Format),
              swapchain_back_buffers.find(barrier.Transition.pResource) !=
                      swapchain_back_buffers.end()
                  ? 1U
                  : 0U,
              debug_name.c_str(),
              marker.c_str());
        }
        auto is_known_output =
            known_camera_output_resources.find(
                barrier.Transition.pResource) !=
            known_camera_output_resources.end();
        const auto named_eye_index =
            !is_known_output &&
                    description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
                    camera_capture_extent_matches(description.Width,
                                                  description.Height)
                ? named_eye_final_index(barrier.Transition.pResource)
                : -1;
        const bool is_named_eye_final = named_eye_index >= 0;
        if (is_named_eye_final && !is_known_output) {
          named_camera_output_resources[static_cast<std::size_t>(
              named_eye_index)] = barrier.Transition.pResource;
          const bool named_pair_ready = named_camera_output_resources[0] &&
                                        named_camera_output_resources[1];
          if (named_pair_ready) {
            // Once both mod-authored finals are identified, they are the
            // complete capture set. Full-size UI worlds (notably NPC shop
            // views) use the same format and transition pattern, so allowing
            // the earlier anonymous fallback to keep learning would admit
            // their output as a false eye and make stereo flicker or go mono.
            known_camera_output_resources.clear();
            known_camera_output_resources.insert(
                named_camera_output_resources[0]);
            known_camera_output_resources.insert(
                named_camera_output_resources[1]);
            named_camera_outputs_ready = true;
            named_camera_outputs_ready_hint.store(true,
                                                  std::memory_order_release);
          } else {
            known_camera_output_resources.insert(barrier.Transition.pResource);
          }
          is_known_output = true;
          if (census_enabled) {
            write_boundary_census_log(
                "frame=%llu\tOUTPUT_LEARN_NAMED\tresource=%p\tname=%s\r\n",
                present_count.load(std::memory_order_relaxed),
                barrier.Transition.pResource,
                resource_debug_name(barrier.Transition.pResource).c_str());
          }
        }
        if (description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
            camera_capture_extent_matches(description.Width,
                                          description.Height) &&
            (description.Format == camera_output_format ||
             is_named_eye_final || is_known_output) &&
            barrier.Transition.StateAfter == D3D12_RESOURCE_STATE_RENDER_TARGET &&
            barrier.Flags == D3D12_RESOURCE_BARRIER_FLAG_NONE &&
            is_output_reuse_begin && !is_known_output &&
            !named_camera_outputs_ready) {
            known_camera_output_resources.insert(barrier.Transition.pResource);
            camera_output_realign_pending = true;
            is_known_output = true;
            write_boundary_census_log(
                "frame=%llu\tOUTPUT_LEARN\tresource=%p\tknown=%llu\r\n",
                present_count.load(std::memory_order_relaxed),
                barrier.Transition.pResource,
                static_cast<unsigned long long>(
                    known_camera_output_resources.size()));
        }
        const auto is_completed_output =
            description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
            camera_capture_extent_matches(description.Width,
                                          description.Height) &&
            (description.Format == camera_output_format ||
             is_named_eye_final || is_known_output) &&
            barrier.Transition.StateBefore ==
                D3D12_RESOURCE_STATE_RENDER_TARGET &&
            barrier.Transition.StateAfter == shader_resource_state &&
            barrier.Flags == D3D12_RESOURCE_BARRIER_FLAG_NONE &&
            is_known_output;
        if (census_enabled &&
            description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
            camera_capture_extent_matches(description.Width,
                                          description.Height) &&
            barrier.Transition.StateBefore ==
                D3D12_RESOURCE_STATE_RENDER_TARGET &&
            barrier.Transition.StateAfter == shader_resource_state &&
            barrier.Flags == D3D12_RESOURCE_BARRIER_FLAG_NONE) {
          const auto debug_name =
              resource_debug_name(barrier.Transition.pResource);
          write_boundary_census_log(
              "frame=%llu\tDIM_END\tCL=%p\tresource=%p\tordinal=%llu"
              "\tformat=%u\tknown=%u\tswapchain=%u\tname=%s\r\n",
              present_count.load(std::memory_order_relaxed), commands,
              barrier.Transition.pResource,
              static_cast<unsigned long long>(transition_ordinal),
              static_cast<unsigned>(description.Format),
              is_known_output ? 1U : 0U,
              swapchain_back_buffers.find(barrier.Transition.pResource) !=
                      swapchain_back_buffers.end()
                  ? 1U
                  : 0U,
              debug_name.c_str());
        }
        if (is_completed_output) {
          camera_output_resources[commands] = barrier.Transition.pResource;
          camera_output_source_states[commands] = shader_resource_state;
          if (collect_candidates) {
            auto& candidates = camera_output_candidates[commands];
            const auto marker_found = command_marker_stacks.find(commands);
            const auto marker = marker_found != command_marker_stacks.end() &&
                                        !marker_found->second.empty()
                                    ? marker_found->second.back()
                                    : std::string{};
            candidates.push_back(
                {barrier.Transition.pResource, transition_ordinal, marker});
            if (census_enabled) {
              const auto debug_name =
                  resource_debug_name(barrier.Transition.pResource);
              write_boundary_census_log(
                  "frame=%llu\tMATCH\tCL=%p\tresource=%p\tordinal=%llu"
                  "\twidth=%llu\theight=%u\tbefore=%u\tafter=%u\tformat=%u"
                  "\tswapchain=%u\tname=%s\tmarker=%s\r\n",
                  present_count.load(std::memory_order_relaxed), commands,
                  barrier.Transition.pResource,
                  static_cast<unsigned long long>(transition_ordinal),
                  description.Width, description.Height,
                  static_cast<unsigned>(barrier.Transition.StateBefore),
                  static_cast<unsigned>(barrier.Transition.StateAfter),
                  static_cast<unsigned>(description.Format),
                  swapchain_back_buffers.find(barrier.Transition.pResource) !=
                          swapchain_back_buffers.end()
                      ? 1U
                      : 0U,
                  debug_name.c_str(), marker.c_str());
            }
          }
        }
      }
    }
  }
  original_resource_barrier(commands, barrier_count, barriers);
  darktidevr::producer::observe_ngx_output_barriers(commands, barrier_count, barriers);
}

void STDMETHODCALLTYPE enhanced_barrier_hook(
    ID3D12GraphicsCommandList7* commands, UINT32 group_count,
    const D3D12_BARRIER_GROUP* groups) {
  if (billboard_readback_accepting.load(std::memory_order_relaxed)) {
    std::scoped_lock lock(trace_mutex);
    billboard_resource_states[commands].unknown();
  }
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0 && groups) {
    std::uint64_t barrier_count{};
    for (UINT32 group_index = 0; group_index < group_count; ++group_index) {
      barrier_count += groups[group_index].NumBarriers;
    }
    std::scoped_lock lock(trace_mutex);
    command_traces[static_cast<ID3D12GraphicsCommandList*>(commands)]
        .barrier_count += barrier_count;
  }
  const auto cluster_resource = reinterpret_cast<ID3D12Resource*>(
      cluster_linked_list_resource.load(std::memory_order_relaxed));
  if (cluster_trace_log != INVALID_HANDLE_VALUE && cluster_resource &&
      groups) {
    for (UINT32 group_index = 0; group_index < group_count; ++group_index) {
      const auto& group = groups[group_index];
      if (group.Type != D3D12_BARRIER_TYPE_BUFFER ||
          !group.pBufferBarriers) {
        continue;
      }
      for (UINT32 barrier_index = 0; barrier_index < group.NumBarriers;
           ++barrier_index) {
        const auto& barrier = group.pBufferBarriers[barrier_index];
        if (barrier.pResource != cluster_resource ||
            cluster_barrier_log_count.fetch_add(
                1, std::memory_order_relaxed) >= 256) {
          continue;
        }
        write_cluster_trace_log(
            "frame=%llu\tCLUSTER_ENHANCED_BARRIER\tCL=%p"
            "\tgroup=%u\tindex=%u\tsync_before=%llu\tsync_after=%llu"
            "\taccess_before=%llu\taccess_after=%llu"
            "\toffset=%llu\tsize=%llu\r\n",
            static_cast<unsigned long long>(
                present_count.load(std::memory_order_relaxed)),
            commands, group_index, barrier_index,
            static_cast<unsigned long long>(barrier.SyncBefore),
            static_cast<unsigned long long>(barrier.SyncAfter),
            static_cast<unsigned long long>(barrier.AccessBefore),
            static_cast<unsigned long long>(barrier.AccessAfter),
            static_cast<unsigned long long>(barrier.Offset),
            static_cast<unsigned long long>(barrier.Size));
      }
    }
  }
  const bool log_resources = boundary_census_log != INVALID_HANDLE_VALUE ||
                             enhanced_barrier_log != INVALID_HANDLE_VALUE;
  bool has_texture_barriers{};
  if (groups) {
    for (UINT32 group_index = 0; group_index < group_count; ++group_index) {
      const auto& group = groups[group_index];
      if (group.Type == D3D12_BARRIER_TYPE_TEXTURE &&
          group.pTextureBarriers && group.NumBarriers != 0) {
        has_texture_barriers = true;
        break;
      }
    }
  }
  if (has_texture_barriers) {
    std::scoped_lock lock(boundary_capture_mutex);
    for (UINT32 group_index = 0; group_index < group_count; ++group_index) {
      const auto& group = groups[group_index];
      if (group.Type != D3D12_BARRIER_TYPE_TEXTURE ||
          !group.pTextureBarriers) {
        continue;
      }
      for (UINT32 barrier_index = 0; barrier_index < group.NumBarriers;
           ++barrier_index) {
        const auto& barrier = group.pTextureBarriers[barrier_index];
        if (barrier.pResource && log_resources) {
          const auto description = barrier.pResource->GetDesc();
          if (description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
              camera_capture_extent_matches(description.Width,
                                            description.Height) &&
              is_named_eye_output_resource(barrier.pResource)) {
            write_boundary_census_log(
                "frame=%llu\tEYE_OUTPUT_ENHANCED\tCL=%p\tresource=%p"
                "\tlayout_before=%u\tlayout_after=%u\taccess_before=%llu"
                "\taccess_after=%llu\tflags=%u\tformat=%u\tname=%s\r\n",
                present_count.load(std::memory_order_relaxed), commands,
                barrier.pResource,
                static_cast<unsigned>(barrier.LayoutBefore),
                static_cast<unsigned>(barrier.LayoutAfter),
                static_cast<unsigned long long>(barrier.AccessBefore),
                static_cast<unsigned long long>(barrier.AccessAfter),
                static_cast<unsigned>(barrier.Flags),
                static_cast<unsigned>(description.Format),
                resource_debug_name(barrier.pResource).c_str());
          }
          if (description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
              description.Width >= 1920 && description.Height >= 1080) {
            write_enhanced_barrier_log(
                "frame=%llu\tthread=%lu\tCL=%p\tresource=%p\twidth=%llu"
                "\theight=%u\tformat=%u\tbefore=%u\tafter=%u"
                "\taccess_before=%llu\taccess_after=%llu\r\n",
                present_count.load(std::memory_order_relaxed),
                GetCurrentThreadId(), commands, barrier.pResource,
                description.Width, description.Height,
                static_cast<unsigned>(description.Format),
                static_cast<unsigned>(barrier.LayoutBefore),
                static_cast<unsigned>(barrier.LayoutAfter),
                static_cast<unsigned long long>(barrier.AccessBefore),
                static_cast<unsigned long long>(barrier.AccessAfter));
          }
        }
        if (barrier.LayoutAfter != D3D12_BARRIER_LAYOUT_PRESENT ||
            swapchain_back_buffers.find(barrier.pResource) ==
                swapchain_back_buffers.end()) {
          continue;
        }
        present_transition_resources[
            static_cast<ID3D12GraphicsCommandList*>(commands)] =
            barrier.pResource;
        if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed)) {
          boundary_transition_count.fetch_add(1, std::memory_order_relaxed);
        }
      }
    }
  }
  original_enhanced_barrier(commands, group_count, groups);
}

// Refresh the already allocated inputs at each eye's final render boundary.
// The initial readback/packing fence has completed before arming this path.
// Separate eye fences avoid assuming both render boundaries use one queue.
// Caller holds streamline_input_snapshot_mutex.
void refresh_streamline_submission_inputs(int eye, std::uint64_t present_frame,
                                         std::uint64_t pose_sequence,
                                         ID3D12CommandQueue* queue) {
  auto& state = streamline_input_snapshot_state;
  const auto index = static_cast<std::size_t>(eye);
  if (state.submission_refresh_mask & (1U << eye)) return;
  if (eye == 1 && state.submission_refresh_mask != 1) return;
  const auto& constants = streamline_constants_observations[index];
  const auto& inputs = streamline_tagged_inputs[index];
  if (!constants.valid || constants.present_frame != present_frame ||
      constants.pose_sequence != pose_sequence ||
      constants.viewport != state.constants[index].viewport) return;
  if (eye == 1 && (state.submission_refresh_constants[0].present_frame != present_frame ||
      state.submission_refresh_constants[0].pose_sequence != pose_sequence)) {
    state.failed = true;
    write_streamline_probe_log("STEREO_REFRESH\tphase=failed\treason=pair_identity\r\n");
    return;
  }
  for (std::size_t type = 0; type < 3; ++type) {
    const auto& input = inputs[type];
    if (!input.resource || input.present_frame != present_frame ||
        input.pose_sequence != pose_sequence ||
        input.state == static_cast<D3D12_RESOURCE_STATES>(UINT_MAX)) return;
    const auto source = input.resource->GetDesc();
    const auto destination = state.snapshots[index][type]->GetDesc();
    if (source.Width != destination.Width || source.Height != destination.Height ||
        source.Format != destination.Format || source.MipLevels != 1 ||
        source.DepthOrArraySize != 1 || source.SampleDesc.Count != 1) {
      state.failed = true;
      write_streamline_probe_log("STEREO_REFRESH\tphase=failed\treason=extent_changed\r\n");
      return;
    }
  }
  ComPtr<ID3D12Device> device;
  HRESULT result = queue->GetDevice(IID_PPV_ARGS(&device));
  if (SUCCEEDED(result)) result = device->CreateCommandAllocator(
      D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&state.submission_refresh_allocators[index]));
  if (SUCCEEDED(result)) result = device->CreateCommandList(
      0, D3D12_COMMAND_LIST_TYPE_DIRECT, state.submission_refresh_allocators[index].Get(),
      nullptr, IID_PPV_ARGS(&state.submission_refresh_commands[index]));
  if (SUCCEEDED(result)) result = device->CreateFence(
      0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&state.submission_refresh_fences[index]));
  if (SUCCEEDED(result)) {
    auto* commands = state.submission_refresh_commands[index].Get();
    for (std::size_t type = 0; type < 3; ++type) {
      D3D12_RESOURCE_BARRIER barrier{};
      barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      barrier.Transition = {inputs[type].resource.Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                            inputs[type].state, D3D12_RESOURCE_STATE_COPY_SOURCE};
      if (barrier.Transition.StateBefore != barrier.Transition.StateAfter)
        commands->ResourceBarrier(1, &barrier);
      commands->CopyResource(state.snapshots[index][type].Get(), inputs[type].resource.Get());
      std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
      if (barrier.Transition.StateBefore != barrier.Transition.StateAfter)
        commands->ResourceBarrier(1, &barrier);
      state.sources[index][type] = inputs[type].resource;
    }
    result = commands->Close();
    if (SUCCEEDED(result)) {
      ID3D12CommandList* lists[]{commands};
      original_execute_command_lists(queue, 1, lists);
      result = queue->Signal(state.submission_refresh_fences[index].Get(), 1);
    }
  }
  if (FAILED(result)) {
    state.failed = true;
    write_streamline_probe_log("STEREO_REFRESH\tphase=failed\treason=gpu_setup\thresult=0x%08x\r\n",
        static_cast<unsigned>(result));
    return;
  }
  state.submission_refresh_constants[index] = constants;
  state.submission_refresh_mask |= 1U << eye;
  write_streamline_probe_log(
      "STEREO_REFRESH\tphase=scheduled\teye=%d\tpresent_frame=%llu\tpose=%llu"
      "\tframe_index=%u\ttoken_call=%llu\tfence_value=1\tbatch=%llu\r\n",
      eye, static_cast<unsigned long long>(present_frame),
      static_cast<unsigned long long>(pose_sequence), constants.frame_index,
      static_cast<unsigned long long>(constants.frame_token_call),
      static_cast<unsigned long long>(state.submission_id));
}

void schedule_streamline_input_snapshot(int eye, std::uint64_t present_frame,
                                        std::uint64_t pose_sequence,
                                        ID3D12CommandQueue* queue,
                                        ID3D12Resource* final_color, D3D12_RESOURCE_STATES final_state) {
  if (eye < 0 || eye > 1 || !queue || !original_execute_command_lists) {
    return;
  }
  ComPtr<ID3D12Resource> ui_source;
  std::array<D3D12_RESOURCE_DESC, 2> ui_descriptions{};
  bool ui_pair_allocated = false;
  if (world_ui_capture_requested()) {
    std::scoped_lock lock(world_ui_capture_mutex);
    const auto& ui = world_ui_capture_eyes[eye];
    if (ui.pose == pose_sequence && ui.draws && !ui.rejected)
      ui_source = ui.texture;
    ui_pair_allocated = world_ui_capture_eyes[0].texture && world_ui_capture_eyes[1].texture;
    if (ui_pair_allocated)
      for (unsigned i = 0; i < 2; ++i)
        ui_descriptions[i] = world_ui_capture_eyes[i].texture->GetDesc();
    static std::uint64_t next_report{};
    static unsigned stage_reports{};
    if (stage_reports < 32 && present_frame >= next_report) {
      ++stage_reports;
      next_report = present_frame + 60;
      write_streamline_probe_log(
          "UI_ALPHA_STAGES\tpresent=%llu\tdraws=%llu\tblended_rgba=%llu\trt_tracked=%llu"
          "\tviewport_matches=%llu\ttarget_matches=%llu\tarmed=%llu\tknown_gui=%llu\treplayed=%llu\r\n",
          static_cast<unsigned long long>(present_frame),
          static_cast<unsigned long long>(world_ui_capture_stages[0].load()),
          static_cast<unsigned long long>(world_ui_capture_stages[1].load()),
          static_cast<unsigned long long>(world_ui_capture_stages[2].load()),
          static_cast<unsigned long long>(world_ui_capture_stages[3].load()),
          static_cast<unsigned long long>(world_ui_capture_stages[4].load()),
          static_cast<unsigned long long>(world_ui_capture_stages[5].load()),
          static_cast<unsigned long long>(world_ui_capture_stages[6].load()),
          static_cast<unsigned long long>(world_ui_capture_stages[7].load()));
    }
    darktidevr::producer::observe_stereo_ui_readback_overlay(
        static_cast<unsigned>(eye), pose_sequence, ui.pose == pose_sequence ? ui.texture.Get() : nullptr);
    static unsigned reports{};
    if (ui.pose == pose_sequence && reports++ < 64)
      write_streamline_probe_log("UI_ALPHA_CAPTURE\teye=%d\tpose=%llu\tmatched=%u\tdraws=%u\trejected=%u\r\n",
          eye, static_cast<unsigned long long>(pose_sequence), ui.pose == pose_sequence ? 1U : 0U,
          ui.draws, ui.rejected);
  }
  std::scoped_lock lock(streamline_input_snapshot_mutex);
  auto& state = streamline_input_snapshot_state;
  if (!state.failed && state.stereo_backbuffer_complete &&
      streamline_continuous_requested.load(std::memory_order_acquire)) {
    if (current_presentation_mode.load() != 1) return;
    if (world_ui_submission_requested() && world_ui_capture_rejected.load()) {
      // An unsupported GUI draw invalidates this experimental UI route for the
      // session. Stay on original stereo rather than repeatedly pausing and
      // restarting interpolation as that widget appears and disappears.
      if (streamline_continuous.initialized())
        streamline_continuous.pause(queue, original_execute_command_lists, "ui_capture_rejected");
      return;
    }
    // Never reuse a previous pose's UI or silently remove tag 23 from an active
    // tag set. The existing incomplete-pair path skips generation for this eye.
    if (world_ui_submission_requested() && (!ui_source || !ui_pair_allocated)) return;
    if (!streamline_continuous.initialized() && !streamline_continuous.finished()) {
      if (world_ui_capture_requested() && (!ui_source || !ui_pair_allocated)) return;
      // Never consume an unattended test while the user is in another app.
      if (!game_process_foreground()) return;
      ComPtr<ID3D12Device> device;
      if (FAILED(queue->GetDevice(IID_PPV_ARGS(&device)))) return;
      std::array<std::array<D3D12_RESOURCE_DESC, 3>, 2> descriptions{};
      for (std::size_t captured_eye = 0; captured_eye < 2; ++captured_eye)
        for (std::size_t role = 0; role < 3; ++role)
          descriptions[captured_eye][role] = state.snapshots[captured_eye][role]->GetDesc();
      darktidevr::producer::configure_ngx_gpu_timing(gpu_profile_enabled.load());
      if (!streamline_continuous.initialize(device.Get(), state.submission_limit,
          {state.constants[0].viewport, state.constants[1].viewport}, descriptions,
          write_streamline_probe_log, streamline_persistent_requested.load(),
          gpu_profile_enabled.load(),
          ui_pair_allocated ? &ui_descriptions : nullptr,world_ui_submission_requested())) return;
      streamline_submission_trace_start.store(present_frame, std::memory_order_relaxed);
    }
    const auto index = static_cast<std::size_t>(eye);
    const auto& constants = streamline_constants_observations[index];
    if (!constants.valid || constants.present_frame != present_frame ||
        constants.pose_sequence != pose_sequence || constants.viewport != state.constants[index].viewport) return;
    if(!final_color) return;
    std::array<darktidevr::producer::StreamlineTagInput, 4> inputs{};
    for (std::size_t role = 0; role < 3; ++role) {
      const auto& source = streamline_tagged_inputs[index][role];
      if (!source.resource || source.present_frame != present_frame || source.pose_sequence != pose_sequence) return;
      const auto description = source.resource->GetDesc();
      inputs[role] = {source.resource.Get(), static_cast<unsigned>(description.Width),
          description.Height, static_cast<unsigned>(source.state), static_cast<unsigned>(description.Format)};
    }
    const auto final_description=final_color->GetDesc();
    inputs[3]={final_color,static_cast<unsigned>(final_description.Width),final_description.Height,
        static_cast<unsigned>(final_state),static_cast<unsigned>(final_description.Format)};
    darktidevr::producer::StreamlineTagInput ui_input{};
    if (ui_source) {
      const auto description = ui_source->GetDesc();
      ui_input = {ui_source.Get(), static_cast<unsigned>(description.Width), description.Height,
          D3D12_RESOURCE_STATE_RENDER_TARGET, static_cast<unsigned>(description.Format)};
    }
    streamline_continuous.capture(static_cast<unsigned>(eye), present_frame, pose_sequence,
        constants.constants, inputs, queue, original_execute_command_lists,
        ui_source ? &ui_input : nullptr);
    return;
  }
  if (!state.failed && state.submission_refresh_armed && !state.submission_attempted) {
    refresh_streamline_submission_inputs(eye, present_frame, pose_sequence, queue);
    return;
  }
  if (state.failed || state.stereo_backbuffer_complete) {
    return;
  }
  if (state.readback_complete && state.stereo_backbuffer_pending) {
    const auto completed = state.fence ? state.fence->GetCompletedValue() : 0;
    if (completed == UINT64_MAX) {
      state.failed = true;
      write_streamline_probe_log(
          "STEREO_BACKBUFFER\tphase=failed\treason=poisoned_fence\r\n");
      return;
    }
    if (completed < state.fence_value) {
      return;
    }
    const auto description = state.stereo_backbuffer->GetDesc();
    ComPtr<ID3D12Device> device;
    std::size_t reserved_slot = streamline_transport_slots.size();
    {
      std::scoped_lock transport_lock(streamline_transport_mutex);
      if (FAILED(state.stereo_backbuffer->GetDevice(IID_PPV_ARGS(&device))) ||
          !ensure_streamline_transport_resources(device.Get(), description)) {
        state.failed = true;
        write_streamline_probe_log(
            "STEREO_TRANSPORT_RESERVATION\tphase=failed"
            "\treason=resource_creation\r\n");
        return;
      }
      for (std::size_t index = 0; index < streamline_transport_slots.size();
           ++index) {
        auto& slot = streamline_transport_slots[index];
        if (!slot.pending && !slot.reserved) {
          slot.reserved = true;
          reserved_slot = index;
          break;
        }
      }
    }
    if (reserved_slot == streamline_transport_slots.size()) {
      state.failed = true;
      write_streamline_probe_log(
          "STEREO_TRANSPORT_RESERVATION\tphase=failed"
          "\treason=ring_full\r\n");
      return;
    }
    state.transport_slot_reserved = true;
    state.transport_slot_index = reserved_slot;
    write_streamline_probe_log(
        "STEREO_TRANSPORT_RESERVATION\tphase=reserved\tslot=%zu"
        "\tresource=%p\twidth=%llu\theight=%u\tformat=%u"
        "\tmetadata_published=0\tready_signaled=0\r\n",
        reserved_slot, streamline_transport_slots[reserved_slot].surface.Get(),
        static_cast<unsigned long long>(description.Width), description.Height,
        static_cast<unsigned>(description.Format));
    if (streamline_target_token_probe_requested.load(
            std::memory_order_acquire)) {
      const auto source_frame_index = (std::max)(
          state.constants[0].frame_index, state.constants[1].frame_index);
      if (!original_sl_get_new_frame_token ||
          source_frame_index >= UINT_MAX - 1) {
        state.failed = true;
        write_streamline_probe_log(
            "STEREO_TARGET_TOKEN\tphase=failed"
            "\treason=unavailable_or_overflow"
            "\tgeneration_present_submitted=0"
            "\tmetadata_published=0\tready_signaled=0\r\n");
        return;
      }
      const std::uint32_t requested_frame_index = source_frame_index + 1;
      void* target_frame_token{};
      const auto result = original_sl_get_new_frame_token(
          &target_frame_token, &requested_frame_index);
      if (result != 0 || !target_frame_token) {
        state.failed = true;
        write_streamline_probe_log(
            "STEREO_TARGET_TOKEN\tphase=failed\treason=api_result"
            "\ttarget_frame_index=%u\tresult=%d"
            "\tgeneration_present_submitted=0"
            "\tmetadata_published=0\tready_signaled=0\r\n",
            requested_frame_index, result);
        return;
      }
      state.target_token_allocated = true;
      state.target_frame_token = target_frame_token;
      state.target_frame_index = requested_frame_index;
      darktidevr::core::StreamlineStereoPresentationTransaction transaction{};
      transaction.snapshot_ready = true;
      transaction.source_frame_indices = {state.constants[0].frame_index,
                                          state.constants[1].frame_index};
      transaction.source_token_calls = {state.constants[0].frame_token_call,
                                        state.constants[1].frame_token_call};
      transaction.source_viewports = {state.constants[0].viewport,
                                      state.constants[1].viewport};
      transaction.target_frame_token = reinterpret_cast<std::uintptr_t>(
          state.target_frame_token);
      transaction.target_frame_index = state.target_frame_index;
      transaction.stereo_backbuffer = reinterpret_cast<std::uintptr_t>(
          state.stereo_backbuffer.Get());
      transaction.stereo_width = description.Width;
      transaction.stereo_height = description.Height;
      transaction.eye_width = description.Width / 2;
      transaction.format = static_cast<std::uint32_t>(description.Format);
      transaction.resource_state = D3D12_RESOURCE_STATE_PRESENT;
      transaction.consumer_slot_reserved = state.transport_slot_reserved;
      const auto policy_status =
          darktidevr::core::evaluate_streamline_stereo_presentation(transaction);
      if (policy_status !=
          darktidevr::core::StreamlineStereoPresentationStatus::ready_to_stage) {
        state.failed = true;
        write_streamline_probe_log(
            "STEREO_TARGET_TOKEN\tphase=failed\treason=policy"
            "\ttarget_frame_index=%u\tresult=%d\tpolicy_status=%u"
            "\tgeneration_present_submitted=0\tmetadata_published=0"
            "\tready_signaled=0\r\n",
            requested_frame_index, result,
            static_cast<unsigned>(policy_status));
        return;
      }
      write_streamline_probe_log(
          "STEREO_TARGET_TOKEN\tphase=allocated\ttarget_token=%p"
          "\ttarget_frame_index=%u\tsource_frame_indices=%u,%u"
          "\tresult=%d\tpolicy_status=%u"
          "\tgeneration_present_submitted=0"
          "\tmetadata_published=0\tready_signaled=0\r\n",
          target_frame_token, requested_frame_index,
          state.constants[0].frame_index, state.constants[1].frame_index,
          result, static_cast<unsigned>(policy_status));
    }
    state.stereo_backbuffer_pending = false;
    state.stereo_backbuffer_complete = true;
    // Prepare against the actual captured textures, never the requested eye
    // dimensions alone. The legacy packing probe may crop wide color inputs;
    // that does not establish matching depth/motion or camera projections.
    darktidevr::producer::StreamlineStereoTags::Inputs submission_inputs{};
    bool supported_submission_layout = description.Width <= UINT_MAX &&
        description.Width % 2 == 0;
    for (std::size_t sample_eye = 0; sample_eye < 2; ++sample_eye) {
      for (std::size_t type = 0; type < 3; ++type) {
        const auto& resource = state.snapshots[sample_eye][type];
        if (!resource) { supported_submission_layout = false; continue; }
        const auto input_description = resource->GetDesc();
        if (input_description.Width > UINT_MAX ||
            input_description.SampleDesc.Count != 1 ||
            input_description.DepthOrArraySize != 1 ||
            input_description.MipLevels != 1) {
          supported_submission_layout = false;
          continue;
        }
        submission_inputs[sample_eye][type] = {
            resource.Get(), static_cast<std::uint32_t>(input_description.Width),
            input_description.Height,
            static_cast<std::uint32_t>(D3D12_RESOURCE_STATE_COPY_DEST),
            static_cast<std::uint32_t>(input_description.Format)};
      }
    }
    if (supported_submission_layout && state.constants[0].valid &&
        state.constants[1].valid && state.target_token_allocated) {
      auto submission_constants = std::array{state.constants[0].constants,
                                             state.constants[1].constants};
      state.submission_prepared = state.submission.prepare(
          state.submission_id,
          static_cast<std::uint32_t>(description.Width / 2), description.Height,
          {state.constants[0].viewport, state.constants[1].viewport},
          submission_constants,
          submission_inputs);
      state.submission_inputs = submission_inputs;
    }
    write_streamline_probe_log(
        "STEREO_SUBMISSION_PREPARE\tready=%u\tlayout_supported=%u"
        "\teye_width=%llu\teye_height=%u\tcolor_widths=%u,%u"
        "\tdepth_widths=%u,%u\tmotion_widths=%u,%u"
        "\ttags_staged=0\tgeneration_present_submitted=0\r\n",
        state.submission_prepared ? 1U : 0U,
        supported_submission_layout ? 1U : 0U,
        static_cast<unsigned long long>(description.Width / 2), description.Height,
        submission_inputs[0][2].width, submission_inputs[1][2].width,
        submission_inputs[0][0].width, submission_inputs[1][0].width,
        submission_inputs[0][1].width, submission_inputs[1][1].width);
    write_streamline_probe_log(
        "STEREO_BACKBUFFER\tphase=complete\tpresent_frame=%llu"
        "\tpose=%llu\tsource_frame_indices=%u,%u"
        "\tsource_frame_tokens=%p,%p"
        "\tfence_value=%llu\tresource=%p\twidth=%llu\theight=%u"
        "\tformat=%u\tstate=%u\teye_width=%llu\r\n",
        static_cast<unsigned long long>(state.present_frame),
        static_cast<unsigned long long>(state.pose_sequence),
        state.constants[0].frame_index, state.constants[1].frame_index,
        state.constants[0].frame_token, state.constants[1].frame_token,
        static_cast<unsigned long long>(state.fence_value),
        state.stereo_backbuffer.Get(),
        static_cast<unsigned long long>(description.Width), description.Height,
        static_cast<unsigned>(description.Format),
        static_cast<unsigned>(D3D12_RESOURCE_STATE_PRESENT),
        static_cast<unsigned long long>(description.Width / 2));
    return;
  }
  if (state.readback_complete) {
    ComPtr<ID3D12Device> device;
    if (FAILED(queue->GetDevice(IID_PPV_ARGS(&device)))) {
      state.failed = true;
      write_streamline_probe_log(
          "STEREO_BACKBUFFER\tphase=failed\treason=get_device\r\n");
      return;
    }
    const auto left_description = state.snapshots[0][2]->GetDesc();
    const auto right_description = state.snapshots[1][2]->GetDesc();
    if (left_description.Width != right_description.Width ||
        left_description.Height != right_description.Height ||
        left_description.Format != right_description.Format ||
        left_description.SampleDesc.Count != right_description.SampleDesc.Count) {
      state.failed = true;
      write_streamline_probe_log(
          "STEREO_BACKBUFFER\tphase=failed\treason=eye_mismatch\r\n");
      return;
    }
    auto stereo_description = left_description;
    const auto requested_eye_width =
        camera_input_width.load(std::memory_order_relaxed);
    const auto extent = darktidevr::core::streamline_render_extent(
        requested_eye_width, camera_input_height.load(std::memory_order_relaxed),
        streamline_stereo_swapchain_probe_requested.load(std::memory_order_acquire));
    if (!extent.accepts_eye(left_description.Width, left_description.Height)) {
      state.failed = true;
      write_streamline_probe_log(
          "STEREO_BACKBUFFER\tphase=failed\treason=engine_extent_changed"
          "\texpected=%ux%u\tobserved=%llux%u\r\n",
          extent.eye_width, extent.height,
          static_cast<unsigned long long>(left_description.Width), left_description.Height);
      return;
    }
    for (std::size_t sample_eye = 0; sample_eye < 2; ++sample_eye) {
      const auto depth = state.snapshots[sample_eye][0]->GetDesc();
      const auto motion = state.snapshots[sample_eye][1]->GetDesc();
      const auto input = state.snapshots[sample_eye][3]->GetDesc();
      const auto output = state.snapshots[sample_eye][4]->GetDesc();
      if (input.Width != depth.Width || input.Height != depth.Height ||
          motion.Width != depth.Width || motion.Height != depth.Height ||
          !extent.accepts_eye(output.Width, output.Height)) {
        state.failed = true;
        write_streamline_probe_log(
            "STEREO_BACKBUFFER\tphase=failed\treason=upscaler_extent_mismatch"
            "\teye=%zu\tdepth=%llux%u\tinput=%llux%u\toutput=%llux%u"
            "\texpected_output=%ux%u\r\n", sample_eye,
            static_cast<unsigned long long>(depth.Width), depth.Height,
            static_cast<unsigned long long>(input.Width), input.Height,
            static_cast<unsigned long long>(output.Width), output.Height,
            extent.eye_width, extent.height);
        return;
      }
    }
    const auto stereo_eye_width = left_description.Width;
    stereo_description.Width = stereo_eye_width * 2;
    stereo_description.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    D3D12_HEAP_PROPERTIES heap{};
    heap.Type = D3D12_HEAP_TYPE_DEFAULT;
    if (FAILED(device->CreateCommittedResource(
            &heap, D3D12_HEAP_FLAG_NONE, &stereo_description,
            D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
            IID_PPV_ARGS(&state.stereo_backbuffer))) ||
        FAILED(device->CreateCommandAllocator(
            D3D12_COMMAND_LIST_TYPE_DIRECT,
            IID_PPV_ARGS(&state.stereo_backbuffer_allocator))) ||
        FAILED(device->CreateCommandList(
            0, D3D12_COMMAND_LIST_TYPE_DIRECT,
            state.stereo_backbuffer_allocator.Get(), nullptr,
            IID_PPV_ARGS(&state.stereo_backbuffer_commands)))) {
      state.failed = true;
      write_streamline_probe_log(
          "STEREO_BACKBUFFER\tphase=failed\treason=create_resources\r\n");
      return;
    }
    for (std::size_t source_eye = 0; source_eye < 2; ++source_eye) {
      const auto& source_resource = state.snapshots[source_eye][2];
      D3D12_RESOURCE_BARRIER barrier{};
      barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      barrier.Transition.pResource = source_resource.Get();
      barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_DEST;
      barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
      barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
      state.stereo_backbuffer_commands->ResourceBarrier(1, &barrier);
      D3D12_TEXTURE_COPY_LOCATION destination{};
      destination.pResource = state.stereo_backbuffer.Get();
      destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
      D3D12_TEXTURE_COPY_LOCATION source{};
      source.pResource = source_resource.Get();
      source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
      state.stereo_backbuffer_commands->CopyTextureRegion(
          &destination,
          static_cast<UINT>(source_eye * stereo_eye_width), 0, 0, &source,
          nullptr);
      std::swap(barrier.Transition.StateBefore,
                barrier.Transition.StateAfter);
      state.stereo_backbuffer_commands->ResourceBarrier(1, &barrier);
    }
    D3D12_RESOURCE_BARRIER ready_barrier{};
    ready_barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    ready_barrier.Transition.pResource = state.stereo_backbuffer.Get();
    ready_barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_DEST;
    ready_barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
    ready_barrier.Transition.Subresource =
        D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    state.stereo_backbuffer_commands->ResourceBarrier(1, &ready_barrier);
    const auto close_result = state.stereo_backbuffer_commands->Close();
    if (FAILED(close_result)) {
      state.failed = true;
      write_streamline_probe_log(
          "STEREO_BACKBUFFER\tphase=failed\treason=close"
          "\thresult=0x%08x\r\n",
          static_cast<unsigned>(close_result));
      return;
    }
    ID3D12CommandList* lists[]{state.stereo_backbuffer_commands.Get()};
    original_execute_command_lists(queue, 1, lists);
    constexpr std::uint64_t fence_value = 4;
    if (FAILED(queue->Signal(state.fence.Get(), fence_value))) {
      state.failed = true;
      write_streamline_probe_log(
          "STEREO_BACKBUFFER\tphase=failed\treason=signal\r\n");
      return;
    }
    state.fence_value = fence_value;
    state.stereo_backbuffer_pending = true;
    write_streamline_probe_log(
        "STEREO_BACKBUFFER\tphase=scheduled\tpresent_frame=%llu"
        "\tpose=%llu\tsource_frame_indices=%u,%u"
        "\tsource_frame_tokens=%p,%p"
        "\tfence_value=%llu\tresource=%p\twidth=%llu\theight=%u"
        "\tformat=%u\teye_width=%llu\r\n",
        static_cast<unsigned long long>(state.present_frame),
        static_cast<unsigned long long>(state.pose_sequence),
        state.constants[0].frame_index, state.constants[1].frame_index,
        state.constants[0].frame_token, state.constants[1].frame_token,
        static_cast<unsigned long long>(state.fence_value),
        state.stereo_backbuffer.Get(),
        static_cast<unsigned long long>(stereo_description.Width),
        stereo_description.Height,
        static_cast<unsigned>(stereo_description.Format),
        static_cast<unsigned long long>(stereo_eye_width));
    return;
  }
  if (state.complete && state.readback_pending) {
    const auto completed = state.fence ? state.fence->GetCompletedValue() : 0;
    if (completed == UINT64_MAX) {
      state.failed = true;
      write_streamline_probe_log(
          "INPUT_SNAPSHOT_READBACK\tphase=failed"
          "\treason=poisoned_fence\r\n");
      return;
    }
    if (completed < state.fence_value) {
      return;
    }
    void* mapped{};
    const D3D12_RANGE read_range{0, state.readback_bytes};
    if (!state.readback ||
        FAILED(state.readback->Map(0, &read_range, &mapped)) || !mapped) {
      state.failed = true;
      write_streamline_probe_log(
          "INPUT_SNAPSHOT_READBACK\tphase=failed\treason=map\r\n");
      return;
    }
    std::array<std::array<std::uint64_t, kStreamlineInputCount>, 2> hashes{};
    const auto* bytes = static_cast<const std::byte*>(mapped);
    for (std::size_t sample_eye = 0; sample_eye < 2; ++sample_eye) {
      for (std::size_t type = 0; type < kStreamlineInputCount; ++type) {
        const auto& footprint = state.readback_footprints[sample_eye][type];
        const auto description = state.snapshots[sample_eye][type]->GetDesc();
        const auto left = type == 0
                              ? static_cast<UINT>((description.Width -
                                                   kStreamlineInputSampleWidth) /
                                                  2)
                              : 0U;
        const auto top = type == 0
                             ? (description.Height -
                                kStreamlineInputSampleHeight) /
                                   2
                             : 0U;
        const auto* sample = bytes + footprint.Offset +
                             top * footprint.Footprint.RowPitch + left * 4;
        constexpr std::uint64_t hash_offset = 1469598103934665603ULL;
        constexpr std::uint64_t hash_prime = 1099511628211ULL;
        auto hash = hash_offset;
        std::uint64_t nonzero_bytes{};
        for (UINT row = 0; row < kStreamlineInputSampleHeight; ++row) {
          const auto* row_bytes = sample + row * footprint.Footprint.RowPitch;
          for (UINT offset = 0; offset < kStreamlineInputSampleRowPitch;
               ++offset) {
            const auto value = static_cast<std::uint8_t>(row_bytes[offset]);
            hash ^= value;
            hash *= hash_prime;
            nonzero_bytes += value != 0 ? 1U : 0U;
          }
        }
        hashes[sample_eye][type] = hash;
        write_streamline_probe_log(
            "INPUT_SNAPSHOT_SAMPLE\tpresent_frame=%llu\tpose=%llu"
            "\teye=%zu\ttype=%zu\ttype_name=%s\thash=%016llx"
            "\tnonzero_bytes=%llu\tbytes=%llu\r\n",
            static_cast<unsigned long long>(state.present_frame),
            static_cast<unsigned long long>(state.pose_sequence), sample_eye,
            type, kStreamlineInputNames[type],
            static_cast<unsigned long long>(hashes[sample_eye][type]),
            static_cast<unsigned long long>(nonzero_bytes),
            static_cast<unsigned long long>(kStreamlineInputSampleBytes));
      }
    }
    const D3D12_RANGE written_range{0, 0};
    state.readback->Unmap(0, &written_range);
    std::uint32_t divergent_mask{};
    for (std::size_t type = 0; type < kStreamlineInputCount; ++type) {
      if (hashes[0][type] != hashes[1][type]) {
        divergent_mask |= 1U << type;
      }
    }
    state.readback_pending = false;
    state.readback_complete = true;
    write_streamline_probe_log(
        "INPUT_SNAPSHOT_READBACK\tphase=complete\tpresent_frame=%llu"
        "\tpose=%llu\tfence_value=%llu\tsample_count=%zu"
        "\tdivergent_mask=%u\r\n",
        static_cast<unsigned long long>(state.present_frame),
        static_cast<unsigned long long>(state.pose_sequence),
        static_cast<unsigned long long>(state.fence_value),
        kStreamlineInputCount * 2, divergent_mask);
    return;
  }
  if (state.complete) {
    ComPtr<ID3D12Device> device;
    if (FAILED(queue->GetDevice(IID_PPV_ARGS(&device)))) {
      state.failed = true;
      write_streamline_probe_log(
          "INPUT_SNAPSHOT_READBACK\tphase=failed\treason=get_device\r\n");
      return;
    }
    D3D12_HEAP_PROPERTIES readback_heap{};
    readback_heap.Type = D3D12_HEAP_TYPE_READBACK;
    D3D12_RESOURCE_DESC readback_description{};
    readback_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    std::uint64_t readback_bytes{};
    for (std::size_t sample_eye = 0; sample_eye < 2; ++sample_eye) {
      for (std::size_t type = 0; type < kStreamlineInputCount; ++type) {
        auto footprint_description =
            state.snapshots[sample_eye][type]->GetDesc();
        footprint_description.Flags = D3D12_RESOURCE_FLAG_NONE;
        footprint_description.DepthOrArraySize = 1;
        footprint_description.MipLevels = 1;
        if (type != 0) {
          footprint_description.Width = kStreamlineInputSampleWidth;
          footprint_description.Height = kStreamlineInputSampleHeight;
        }
        if (footprint_description.Format == DXGI_FORMAT_R32_TYPELESS) {
          footprint_description.Format = DXGI_FORMAT_R32_FLOAT;
        } else if (footprint_description.Format ==
                   DXGI_FORMAT_R16G16_TYPELESS) {
          footprint_description.Format = DXGI_FORMAT_R16G16_FLOAT;
        } else if (footprint_description.Format ==
                   DXGI_FORMAT_R8G8B8A8_TYPELESS) {
          footprint_description.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        }
        UINT64 footprint_bytes{};
        device->GetCopyableFootprints(
            &footprint_description, 0, 1, readback_bytes,
            &state.readback_footprints[sample_eye][type], nullptr, nullptr,
            &footprint_bytes);
        readback_bytes =
            state.readback_footprints[sample_eye][type].Offset +
            footprint_bytes;
      }
    }
    state.readback_bytes = readback_bytes;
    readback_description.Width = state.readback_bytes;
    readback_description.Height = 1;
    readback_description.DepthOrArraySize = 1;
    readback_description.MipLevels = 1;
    readback_description.SampleDesc.Count = 1;
    readback_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    if (FAILED(device->CreateCommittedResource(
            &readback_heap, D3D12_HEAP_FLAG_NONE, &readback_description,
            D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
            IID_PPV_ARGS(&state.readback))) ||
        FAILED(device->CreateCommandAllocator(
            D3D12_COMMAND_LIST_TYPE_DIRECT,
            IID_PPV_ARGS(&state.readback_allocator))) ||
        FAILED(device->CreateCommandList(
            0, D3D12_COMMAND_LIST_TYPE_DIRECT,
            state.readback_allocator.Get(), nullptr,
            IID_PPV_ARGS(&state.readback_commands)))) {
      state.failed = true;
      write_streamline_probe_log(
          "INPUT_SNAPSHOT_READBACK\tphase=failed"
          "\treason=create_resources\r\n");
      return;
    }
    for (std::size_t sample_eye = 0; sample_eye < 2; ++sample_eye) {
      for (std::size_t type = 0; type < kStreamlineInputCount; ++type) {
        const auto& snapshot = state.snapshots[sample_eye][type];
        const auto description = snapshot->GetDesc();
        if (description.Width < kStreamlineInputSampleWidth ||
            description.Height < kStreamlineInputSampleHeight) {
          state.failed = true;
          write_streamline_probe_log(
              "INPUT_SNAPSHOT_READBACK\tphase=failed"
              "\treason=small_resource\teye=%zu\ttype=%zu\r\n",
              sample_eye, type);
          return;
        }
        D3D12_RESOURCE_BARRIER barrier{};
        barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        barrier.Transition.pResource = snapshot.Get();
        barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_DEST;
        barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
        barrier.Transition.Subresource =
            D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        state.readback_commands->ResourceBarrier(1, &barrier);
        D3D12_TEXTURE_COPY_LOCATION destination{};
        destination.pResource = state.readback.Get();
        destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
        destination.PlacedFootprint =
            state.readback_footprints[sample_eye][type];
        D3D12_TEXTURE_COPY_LOCATION source{};
        source.pResource = snapshot.Get();
        source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        const auto left = static_cast<UINT>(
            (description.Width - kStreamlineInputSampleWidth) / 2);
        const auto top =
            (description.Height - kStreamlineInputSampleHeight) / 2;
        const D3D12_BOX box{left, top, 0,
                            left + kStreamlineInputSampleWidth,
                            top + kStreamlineInputSampleHeight, 1};
        state.readback_commands->CopyTextureRegion(
            &destination, 0, 0, 0, &source, type == 0 ? nullptr : &box);
        std::swap(barrier.Transition.StateBefore,
                  barrier.Transition.StateAfter);
        state.readback_commands->ResourceBarrier(1, &barrier);
      }
    }
    const auto close_result = state.readback_commands->Close();
    if (FAILED(close_result)) {
      state.failed = true;
      write_streamline_probe_log(
          "INPUT_SNAPSHOT_READBACK\tphase=failed\treason=close"
          "\thresult=0x%08x\r\n",
          static_cast<unsigned>(close_result));
      return;
    }
    ID3D12CommandList* readback_lists[]{state.readback_commands.Get()};
    original_execute_command_lists(queue, 1, readback_lists);
    const std::uint64_t readback_fence_value = 3;
    if (FAILED(queue->Signal(state.fence.Get(), readback_fence_value))) {
      state.failed = true;
      write_streamline_probe_log(
          "INPUT_SNAPSHOT_READBACK\tphase=failed\treason=signal\r\n");
      return;
    }
    state.fence_value = readback_fence_value;
    state.readback_pending = true;
    write_streamline_probe_log(
        "INPUT_SNAPSHOT_READBACK\tphase=scheduled\tpresent_frame=%llu"
        "\tpose=%llu\tfence_value=%llu\tsample_count=%zu"
        "\tsample_extent=%ux%u\treadback_bytes=%llu\r\n",
        static_cast<unsigned long long>(state.present_frame),
        static_cast<unsigned long long>(state.pose_sequence),
        static_cast<unsigned long long>(state.fence_value),
        kStreamlineInputCount * 2, kStreamlineInputSampleWidth,
        kStreamlineInputSampleHeight,
        static_cast<unsigned long long>(state.readback_bytes));
    return;
  }
  if (state.pending) {
    const auto completed = state.fence ? state.fence->GetCompletedValue() : 0;
    if (completed == UINT64_MAX) {
      state.failed = true;
      write_streamline_probe_log(
          "INPUT_SNAPSHOT\tphase=failed\treason=poisoned_fence\r\n");
    } else if (completed >= state.fence_value) {
      state.pending = false;
      state.complete = true;
      std::uint32_t source_alias_mask{};
      std::uint32_t snapshot_alias_mask{};
      std::unordered_set<ID3D12Resource*> unique_snapshots;
      for (std::size_t type = 0; type < kStreamlineInputCount; ++type) {
        if (state.sources[0][type].Get() == state.sources[1][type].Get()) {
          source_alias_mask |= 1U << type;
        }
        if (state.snapshots[0][type].Get() ==
            state.snapshots[1][type].Get()) {
          snapshot_alias_mask |= 1U << type;
        }
        unique_snapshots.insert(state.snapshots[0][type].Get());
        unique_snapshots.insert(state.snapshots[1][type].Get());
      }
      std::array<darktidevr::core::StreamlineEyeInputSet, 2> policy_inputs;
      for (std::size_t policy_eye = 0; policy_eye < policy_inputs.size();
           ++policy_eye) {
        darktidevr::core::begin_streamline_eye_frame(
            policy_inputs[policy_eye],
            static_cast<std::uint32_t>(state.pose_sequence));
        for (std::size_t type = 0; type < kStreamlineInputCount; ++type) {
          (void)darktidevr::core::observe_streamline_eye_resource(
              policy_inputs[policy_eye], kStreamlinePolicyResources[type],
              reinterpret_cast<std::uintptr_t>(
                  state.snapshots[policy_eye][type].Get()));
        }
      }
      const auto policy = darktidevr::core::evaluate_streamline_stereo_inputs(
          policy_inputs[0], policy_inputs[1]);
      const auto snapshot_ready =
          policy.status ==
          darktidevr::core::StreamlineStereoInputStatus::ready;
      write_streamline_probe_log(
          "INPUT_SNAPSHOT\tphase=complete\tpresent_frame=%llu"
          "\tpose=%llu\tfence_value=%llu\tresource_count=%zu"
          "\tsource_alias_mask=%u\tsnapshot_alias_mask=%u"
          "\tsnapshot_unique_count=%zu\tpolicy_status=%u"
          "\tpolicy_aliased_mask=%u\tsnapshot_ready=%u"
          "\tpair_identity=%u\tsource_frame_indices=%u,%u"
          "\tsource_frame_tokens=%p,%p\r\n",
          static_cast<unsigned long long>(state.present_frame),
          static_cast<unsigned long long>(state.pose_sequence),
          static_cast<unsigned long long>(state.fence_value),
          kStreamlineInputCount * 2, source_alias_mask, snapshot_alias_mask,
          unique_snapshots.size(), static_cast<unsigned>(policy.status),
          policy.aliased_mask, snapshot_ready ? 1U : 0U,
          static_cast<std::uint32_t>(state.pose_sequence),
          state.constants[0].frame_index, state.constants[1].frame_index,
          state.constants[0].frame_token, state.constants[1].frame_token);
    }
    return;
  }
  if (eye != state.next_eye) {
    return;
  }
  const auto index = static_cast<std::size_t>(eye);
  const auto& tagged_inputs = streamline_tagged_inputs[index];
  const auto complete_input_set = std::all_of(
      tagged_inputs.begin(), tagged_inputs.end(), [&](const auto& tagged) {
        return tagged.resource && tagged.present_frame == present_frame &&
               tagged.pose_sequence == pose_sequence &&
               tagged.state != static_cast<D3D12_RESOURCE_STATES>(UINT_MAX);
      });
  if (!complete_input_set) {
    if (eye == 1 && present_frame > state.present_frame) {
      state.failed = true;
      write_streamline_probe_log(
          "INPUT_SNAPSHOT\tphase=failed\treason=pair_mismatch"
          "\tpresent_frame=%llu\tpose=%llu\texpected_frame=%llu"
          "\texpected_pose=%llu\r\n",
          static_cast<unsigned long long>(present_frame),
          static_cast<unsigned long long>(pose_sequence),
          static_cast<unsigned long long>(state.present_frame),
          static_cast<unsigned long long>(state.pose_sequence));
    }
    return;
  }
  const auto& constants = streamline_constants_observations[index];
  if (!constants.valid || constants.present_frame != present_frame ||
      constants.pose_sequence != pose_sequence) {
    return;
  }
  if (eye == 0 && streamline_stereo_submit_probe_requested.load(std::memory_order_acquire)) {
    // Loading transitions expose eye boundaries before the engine's upscaler
    // targets have switched to runtime size. Do not consume the one-shot on
    // those transitional buffers. Later size checks remain authoritative.
    const auto extent = darktidevr::core::streamline_render_extent(
        camera_input_width.load(std::memory_order_relaxed),
        camera_input_height.load(std::memory_order_relaxed), true);
    const auto depth = tagged_inputs[0].resource->GetDesc();
    const auto motion = tagged_inputs[1].resource->GetDesc();
    const auto hudless = tagged_inputs[2].resource->GetDesc();
    const auto input = tagged_inputs[3].resource->GetDesc();
    const auto output = tagged_inputs[4].resource->GetDesc();
    bool enabled = false;
    for (const auto& options : streamline_options_observations)
      enabled = enabled || (options.valid && options.viewport == constants.viewport &&
          options.mode == 1 && options.present_frame == present_frame);
    if (!enabled || !extent.accepts_eye(hudless.Width, hudless.Height) ||
        !extent.accepts_eye(output.Width, output.Height) ||
        depth.Width != motion.Width || depth.Height != motion.Height ||
        depth.Width != input.Width || depth.Height != input.Height) return;
  }
  if (eye == 0) {
    state.present_frame = present_frame;
    state.pose_sequence = pose_sequence;
  } else if (state.pose_sequence != pose_sequence) {
    state.failed = true;
    write_streamline_probe_log(
        "INPUT_SNAPSHOT\tphase=failed\treason=pair_identity"
        "\tpresent_frame=%llu\tpose=%llu\tleft_present_frame=%llu"
        "\texpected_pose=%llu\r\n",
        static_cast<unsigned long long>(present_frame),
        static_cast<unsigned long long>(pose_sequence),
        static_cast<unsigned long long>(state.present_frame),
        static_cast<unsigned long long>(state.pose_sequence));
    return;
  }
  const auto source_indices_coherent =
      eye == 0 || state.constants[0].frame_index == constants.frame_index ||
      state.constants[0].frame_index + 1 == constants.frame_index ||
      constants.frame_index + 1 == state.constants[0].frame_index;
  const auto token_calls_coherent =
      eye == 0 ||
      state.constants[0].frame_token_call == constants.frame_token_call ||
      state.constants[0].frame_token_call + 1 == constants.frame_token_call ||
      constants.frame_token_call + 1 == state.constants[0].frame_token_call;
  if (eye == 1 &&
      (!source_indices_coherent || !token_calls_coherent ||
       state.constants[0].viewport == constants.viewport ||
       state.constants[0].constants_call == constants.constants_call)) {
    state.failed = true;
    write_streamline_probe_log(
        "INPUT_SNAPSHOT\tphase=failed\treason=constants_identity"
        "\tpresent_frame=%llu\tpose=%llu\tleft_token=%p"
        "\tright_token=%p\tleft_frame_index=%u\tright_frame_index=%u"
        "\tleft_viewport=%u\tright_viewport=%u\r\n",
        static_cast<unsigned long long>(present_frame),
        static_cast<unsigned long long>(pose_sequence),
        state.constants[0].frame_token, constants.frame_token,
        state.constants[0].frame_index, constants.frame_index,
        state.constants[0].viewport, constants.viewport);
    return;
  }
  state.constants[index] = constants;
  write_streamline_probe_log(
      "INPUT_SNAPSHOT_BINDING\tpresent_frame=%llu\tpose=%llu\teye=%d"
      "\tframe_token=%p\tframe_token_call=%llu\tframe_index=%u"
      "\tviewport=%u\tconstants_call=%llu\tconstants_version=%zu"
      "\tjitter=%.9g,%.9g\tcamera_pos=%.9g,%.9g,%.9g\r\n",
      static_cast<unsigned long long>(present_frame),
      static_cast<unsigned long long>(pose_sequence), eye,
      constants.frame_token,
      static_cast<unsigned long long>(constants.frame_token_call),
      constants.frame_index, constants.viewport,
      static_cast<unsigned long long>(constants.constants_call),
      constants.constants.base.struct_version,
      constants.constants.jitter_offset.x, constants.constants.jitter_offset.y,
      constants.constants.camera_position.x,
      constants.constants.camera_position.y,
      constants.constants.camera_position.z);

  ComPtr<ID3D12Device> device;
  if (FAILED(queue->GetDevice(IID_PPV_ARGS(&device)))) {
    state.failed = true;
    write_streamline_probe_log(
        "INPUT_SNAPSHOT\tphase=failed\treason=get_device\teye=%d\r\n",
        eye);
    return;
  }
  if (!state.fence &&
      FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                 IID_PPV_ARGS(&state.fence)))) {
    state.failed = true;
    write_streamline_probe_log(
        "INPUT_SNAPSHOT\tphase=failed\treason=create_fence\teye=%d\r\n",
        eye);
    return;
  }
  D3D12_HEAP_PROPERTIES heap{};
  heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  if (FAILED(device->CreateCommandAllocator(
          D3D12_COMMAND_LIST_TYPE_DIRECT,
          IID_PPV_ARGS(&state.allocators[index]))) ||
      FAILED(device->CreateCommandList(
          0, D3D12_COMMAND_LIST_TYPE_DIRECT, state.allocators[index].Get(),
          nullptr, IID_PPV_ARGS(&state.commands[index])))) {
    state.failed = true;
    write_streamline_probe_log(
        "INPUT_SNAPSHOT\tphase=failed\treason=create_commands"
        "\teye=%d\r\n",
        eye);
    return;
  }
  for (std::size_t type = 0; type < kStreamlineInputCount; ++type) {
    const auto& tagged = tagged_inputs[type];
    const auto description = tagged.resource->GetDesc();
    if (FAILED(device->CreateCommittedResource(
            &heap, D3D12_HEAP_FLAG_NONE, &description,
            D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
            IID_PPV_ARGS(&state.snapshots[index][type])))) {
      state.failed = true;
      write_streamline_probe_log(
          "INPUT_SNAPSHOT\tphase=failed\treason=create_resource"
          "\teye=%d\ttype=%zu\ttype_name=%s\twidth=%llu\theight=%u"
          "\tformat=%u\tflags=%u\r\n",
          eye, type, kStreamlineInputNames[type],
          static_cast<unsigned long long>(description.Width),
          description.Height, static_cast<unsigned>(description.Format),
          static_cast<unsigned>(description.Flags));
      return;
    }
    D3D12_RESOURCE_BARRIER barrier{};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = tagged.resource.Get();
    barrier.Transition.StateBefore = tagged.state;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    state.commands[index]->ResourceBarrier(1, &barrier);
    state.commands[index]->CopyResource(state.snapshots[index][type].Get(),
                                        tagged.resource.Get());
    std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
    state.commands[index]->ResourceBarrier(1, &barrier);
    state.sources[index][type] = tagged.resource;
    write_streamline_probe_log(
        "INPUT_SNAPSHOT_RESOURCE\tpresent_frame=%llu\tpose=%llu"
        "\teye=%d\ttype=%zu\ttype_name=%s\tqueue=%p\tsource=%p"
        "\tsnapshot=%p\tstate=%u\twidth=%llu\theight=%u\tformat=%u"
        "\tflags=%u\r\n",
        static_cast<unsigned long long>(present_frame),
        static_cast<unsigned long long>(pose_sequence), eye, type,
        kStreamlineInputNames[type], queue, tagged.resource.Get(),
        state.snapshots[index][type].Get(), static_cast<unsigned>(tagged.state),
        static_cast<unsigned long long>(description.Width), description.Height,
        static_cast<unsigned>(description.Format),
        static_cast<unsigned>(description.Flags));
  }
  if (FAILED(state.commands[index]->Close())) {
    state.failed = true;
    write_streamline_probe_log(
        "INPUT_SNAPSHOT\tphase=failed\treason=close\teye=%d\r\n", eye);
    return;
  }
  ID3D12CommandList* lists[]{state.commands[index].Get()};
  original_execute_command_lists(queue, 1, lists);
  const auto signal_value = static_cast<std::uint64_t>(eye + 1);
  if (FAILED(queue->Signal(state.fence.Get(), signal_value))) {
    state.failed = true;
    write_streamline_probe_log(
        "INPUT_SNAPSHOT\tphase=failed\treason=signal\teye=%d\r\n", eye);
    return;
  }
  state.fence_value = signal_value;
  state.next_eye = eye + 1;
  state.pending = eye == 1;
  write_streamline_probe_log(
      "INPUT_SNAPSHOT\tphase=scheduled\tpresent_frame=%llu\tpose=%llu"
      "\teye=%d\tqueue=%p\tresource_count=%zu\tfence_value=%llu\r\n",
      static_cast<unsigned long long>(present_frame),
      static_cast<unsigned long long>(pose_sequence), eye, queue,
      kStreamlineInputCount,
      static_cast<unsigned long long>(signal_value));
}

// Startup can exhaust the native-Present burst before the diagnostic runs.
// Each bounded batch also traces its refresh and the following 16 Presents.
bool trace_streamline_submission_images() {
  const auto start = streamline_submission_trace_start.load(std::memory_order_acquire);
  const auto current = present_count.load(std::memory_order_relaxed);
  return start != 0 && current >= start && current - start < 16;
}

void STDMETHODCALLTYPE execute_command_lists_hook(
    ID3D12CommandQueue* queue, UINT count, ID3D12CommandList* const* lists) {
  const auto ngx_completion_ticket =
      darktidevr::producer::observe_ngx_queue_submit(queue, count, lists);
  StreamlineExecuteSnapshot* streamline_snapshot{};
  std::uint64_t streamline_execute_call{};
  const auto known_game_queue =
      game_queue_identity.load(std::memory_order_acquire);
  const auto queue_type = queue == known_game_queue
                              ? D3D12_COMMAND_LIST_TYPE_DIRECT
                              : queue->GetDesc().Type;
  if (streamline_probe_log != INVALID_HANDLE_VALUE) {
    LARGE_INTEGER execute_qpc{};
    QueryPerformanceCounter(&execute_qpc);
    streamline_execute_call =
        streamline_execute_count.fetch_add(1, std::memory_order_relaxed) + 1;
    streamline_last_execute_outer_frame.store(
        present_count.load(std::memory_order_relaxed),
        std::memory_order_relaxed);
    streamline_last_execute_queue.store(queue, std::memory_order_relaxed);
    streamline_last_execute_thread.store(GetCurrentThreadId(),
                                         std::memory_order_relaxed);
    streamline_last_execute_list_count.store(count,
                                             std::memory_order_relaxed);
    streamline_last_execute_queue_type.store(
        static_cast<UINT>(queue_type), std::memory_order_relaxed);
    streamline_last_execute_qpc.store(execute_qpc.QuadPart,
                                      std::memory_order_release);
    auto& snapshot = streamline_execute_history[
        streamline_execute_call % kStreamlineExecuteHistory];
    streamline_snapshot = &snapshot;
    snapshot.call.store(0, std::memory_order_release);
    snapshot.qpc.store(execute_qpc.QuadPart, std::memory_order_relaxed);
    snapshot.outer_frame.store(
        present_count.load(std::memory_order_relaxed),
        std::memory_order_relaxed);
    snapshot.queue.store(queue, std::memory_order_relaxed);
    snapshot.thread.store(GetCurrentThreadId(), std::memory_order_relaxed);
    snapshot.list_count.store(count, std::memory_order_relaxed);
    snapshot.queue_type.store(static_cast<UINT>(queue_type),
                              std::memory_order_relaxed);
    snapshot.present_transition.store(false, std::memory_order_relaxed);
    snapshot.call.store(streamline_execute_call, std::memory_order_release);
  }
  if (queue_type == D3D12_COMMAND_LIST_TYPE_DIRECT &&
      !game_queue_initialized.load(std::memory_order_acquire)) {
    std::scoped_lock lock(state_mutex);
    if (!game_queue) {
      game_queue = queue;
      game_queue_identity.store(queue, std::memory_order_release);
      game_queue_initialized.store(true, std::memory_order_release);
    }
  }
  if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed)) {
    execute_call_count.fetch_add(1, std::memory_order_relaxed);
  }
  if (marker_log != INVALID_HANDLE_VALUE) {
    const auto sequence =
        marker_sequence.fetch_add(1, std::memory_order_relaxed);
    write_marker_log("%llu\t%lu\tQ=%p\tEXECUTE\tcount=%u\tfirst=%p\r\n",
                     sequence, GetCurrentThreadId(), queue, count,
                     count > 0 ? lists[0] : nullptr);
  }
  int requested_eye = -1;
  std::uint64_t requested_pose_sequence{};
  float requested_vertical_fov{};
  float requested_aspect_ratio{};
  int completed_named_output_eye = -1;
  ID3D12GraphicsCommandList* completed_output_commands{};
  ComPtr<ID3D12Resource> completed_back_buffer;
  auto completed_source_state = D3D12_RESOURCE_STATE_RENDER_TARGET;
  ComPtr<ID3D12Resource> completed_menu_output;
  bool executed_swapchain_present_transition{};
  auto completed_menu_source_state =
      D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE |
      D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE;
  if (queue_type == D3D12_COMMAND_LIST_TYPE_DIRECT && count > 0) {
    std::scoped_lock lock(boundary_capture_mutex);
    for (UINT index = 0; index < count; ++index) {
      auto* graphics = static_cast<ID3D12GraphicsCommandList*>(lists[index]);
      if (present_transition_resources.find(graphics) !=
          present_transition_resources.end()) {
        executed_swapchain_present_transition = true;
      }
      const auto menu_found = menu_output_resources.find(graphics);
      if (menu_found != menu_output_resources.end()) {
        completed_menu_output = menu_found->second;
        const auto menu_state_found = menu_output_source_states.find(graphics);
        if (menu_state_found != menu_output_source_states.end()) {
          completed_menu_source_state = menu_state_found->second;
        }
        menu_output_resources.erase(menu_found);
        menu_output_source_states.erase(graphics);
      }
      const auto found = camera_output_resources.find(graphics);
      if (found == camera_output_resources.end()) {
        continue;
      }
      const auto candidates_found = camera_output_candidates.find(graphics);
      const auto candidate_count =
          candidates_found == camera_output_candidates.end()
              ? 0U
              : static_cast<unsigned>(candidates_found->second.size());
      write_boundary_census_log(
          "frame=%llu\tEXECUTE_MATCH\tqueue=%p\tCL=%p\tlist_index=%u"
          "\tlists=%u\tqueued_tags=%llu\tfront_eye=%d\tcandidates=%u\r\n",
          present_count.load(std::memory_order_relaxed), queue, graphics, index,
          count, static_cast<unsigned long long>(armed_eye_captures.size()),
          armed_eye_captures.empty() ? -1 : armed_eye_captures.front().eye,
          candidate_count);
      if (candidates_found != camera_output_candidates.end()) {
        unsigned candidate_index{};
        for (const auto& candidate : candidates_found->second) {
          write_boundary_census_log(
              "frame=%llu\tCANDIDATE\tCL=%p\tindex=%u\tresource=%p"
              "\tordinal=%llu\tselected=%u\tmarker=%s\r\n",
              present_count.load(std::memory_order_relaxed), graphics,
              candidate_index++, candidate.resource.Get(),
              static_cast<unsigned long long>(candidate.transition_ordinal),
              candidate.resource.Get() == found->second.Get() ? 1U : 0U,
              candidate.marker.c_str());
        }
      }
      if (requested_eye < 0 && !armed_eye_captures.empty()) {
        requested_eye = armed_eye_captures.front().eye;
        requested_pose_sequence =
            armed_eye_captures.front().pose_sequence;
        requested_vertical_fov =
            armed_eye_captures.front().vertical_fov_radians;
        requested_aspect_ratio = armed_eye_captures.front().aspect_ratio;
        armed_eye_captures.pop_front();
        completed_back_buffer = found->second;
        const auto selected_candidate =
            camera_output_candidate_index.load(std::memory_order_relaxed);
        if (selected_candidate >= 0 &&
            candidates_found != camera_output_candidates.end() &&
            static_cast<std::size_t>(selected_candidate) <
                candidates_found->second.size()) {
          completed_back_buffer =
              candidates_found->second[static_cast<std::size_t>(
                  selected_candidate)]
                  .resource;
          write_boundary_census_log(
              "frame=%llu\tCANDIDATE_OVERRIDE\tCL=%p\tindex=%d"
              "\tresource=%p\r\n",
              present_count.load(std::memory_order_relaxed), graphics,
              selected_candidate, completed_back_buffer.Get());
        }
        if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
          completed_named_output_eye =
              named_eye_final_index(completed_back_buffer.Get());
          completed_output_commands = graphics;
          const auto generation = command_recording_generations.find(graphics);
          write_focused_log(
              "phase=%d\tframe=%llu\tCL=%p\tOUTPUT_IDENTITY"
              "\tgen=%llu\trender_eye=%d\tnamed_output_eye=%d\tpose=%llu\tresource=%p"
              "\tname=%s\r\n",
              focused_trace_phase.load(std::memory_order_relaxed),
              present_count.load(std::memory_order_relaxed), graphics,
              static_cast<unsigned long long>(
                  generation == command_recording_generations.end()
                      ? 0
                      : generation->second),
              requested_eye, completed_named_output_eye,
              static_cast<unsigned long long>(requested_pose_sequence),
              completed_back_buffer.Get(),
              resource_debug_name(completed_back_buffer.Get()).c_str());
        }
        const auto state_found = camera_output_source_states.find(graphics);
        if (state_found != camera_output_source_states.end()) {
          completed_source_state = state_found->second;
        }
        const auto frame = present_count.load(std::memory_order_relaxed);
        const auto burst_until = resize_diagnostic_burst_until_present.load(
            std::memory_order_relaxed);
        if (frame % 120 == 0 || frame <= burst_until) {
          const auto description = completed_back_buffer->GetDesc();
          write_resize_diagnostic_log(
              "frame=%llu\tEYE_SOURCE\tgeneration=%llu\teye=%d"
              "\tresource=%p\twidth=%llu\theight=%u\tformat=%u"
              "\tstate=%u\tnamed_eye=%d\tknown=%llu\tcandidates=%u"
              "\tnamed0=%p\tnamed1=%p\tname=%s\r\n",
              frame,
              static_cast<unsigned long long>(
                  resize_diagnostic_generation.load(std::memory_order_relaxed)),
              requested_eye, completed_back_buffer.Get(), description.Width,
              description.Height, static_cast<unsigned>(description.Format),
              static_cast<unsigned>(completed_source_state),
              named_eye_final_index(completed_back_buffer.Get()),
              static_cast<unsigned long long>(
                  known_camera_output_resources.size()),
              candidate_count, named_camera_output_resources[0],
              named_camera_output_resources[1],
              resource_debug_name(completed_back_buffer.Get()).c_str());
        }
      }
      camera_output_resources.erase(found);
      camera_output_source_states.erase(graphics);
      if (candidates_found != camera_output_candidates.end()) {
        candidates_found->second.clear();
      }
      present_transition_resources.erase(graphics);
    }
    if (requested_eye >= 0 &&
        focused_trace_phase.load(std::memory_order_relaxed) != 0) {
      for (UINT index = 0; index < count; ++index) {
        auto* graphics = static_cast<ID3D12GraphicsCommandList*>(lists[index]);
        const auto generation = command_recording_generations.find(graphics);
        write_focused_log(
            "phase=%d\tframe=%llu\tCL=%p\tOUTPUT_BATCH_IDENTITY"
            "\tgen=%llu\trender_eye=%d\tpose=%llu\tbatch_index=%u\tbatch_count=%u"
            "\tterminal=%u\r\n",
            focused_trace_phase.load(std::memory_order_relaxed),
            present_count.load(std::memory_order_relaxed), graphics,
            static_cast<unsigned long long>(
                generation == command_recording_generations.end()
                    ? 0
                    : generation->second),
            requested_eye,
            static_cast<unsigned long long>(requested_pose_sequence), index,
            count, graphics == completed_output_commands ? 1U : 0U);
      }
    }
  }
  if (streamline_snapshot && executed_swapchain_present_transition &&
      streamline_snapshot->call.load(std::memory_order_acquire) ==
          streamline_execute_call) {
    streamline_snapshot->present_transition.store(true,
                                                   std::memory_order_release);
  }
  if (executed_swapchain_present_transition) {
    bool changed{};
    {
      std::scoped_lock lock(state_mutex);
      changed = swapchain_present_queue.Get() != queue;
      swapchain_present_queue = queue;
    }
    if (changed) {
      write_boundary_census_log(
          "frame=%llu\tSWAPCHAIN_PRESENT_QUEUE\tqueue=%p\r\n",
          present_count.load(std::memory_order_relaxed), queue);
    }
  }
  {
    std::unique_lock<std::mutex> gpu_trace_lock;
    GpuPassTraceToken gpu_trace_token{};
    if (queue_type == D3D12_COMMAND_LIST_TYPE_DIRECT && count > 0 &&
        gpu_profile_enabled.load(std::memory_order_relaxed) &&
        focused_trace_phase.load(std::memory_order_relaxed) != 0) {
      gpu_trace_lock = std::unique_lock<std::mutex>(gpu_profile_mutex);
      gpu_trace_token = begin_gpu_pass_trace_batch_locked(
          queue, count, lists, requested_eye);
    }
    const auto streamline_burst_until =
        streamline_native_burst_until_call.load(std::memory_order_acquire);
    const auto log_streamline_eye_boundary =
        requested_eye >= 0 && streamline_probe_log != INVALID_HANDLE_VALUE &&
        (trace_streamline_submission_images() || (streamline_burst_until != 0 &&
        streamline_native_present_count.load(std::memory_order_relaxed) <=
            streamline_burst_until));
    if (log_streamline_eye_boundary) {
      LARGE_INTEGER boundary_qpc{};
      QueryPerformanceCounter(&boundary_qpc);
      write_streamline_probe_log(
          "EYE_OUTPUT_BOUNDARY\tphase=execute_begin\tpresent_frame=%llu"
          "\texecute_call=%llu\teye=%d\tpose=%llu\tqueue=%p\tresource=%p"
          "\tstate=%u\tqpc=%lld\r\n",
          static_cast<unsigned long long>(
              present_count.load(std::memory_order_relaxed)),
          static_cast<unsigned long long>(streamline_execute_call),
          requested_eye,
          static_cast<unsigned long long>(requested_pose_sequence), queue,
          completed_back_buffer.Get(),
          static_cast<unsigned>(completed_source_state), boundary_qpc.QuadPart);
    }
    auto* readback = billboard_readback.load(std::memory_order_acquire);
    const auto readback_submission = readback ? readback->submitting(queue, count, lists)
        : darktidevr::producer::BillboardDrawReadback::Submission{};
    original_execute_command_lists(queue, count, lists);
    if (readback) readback->submitted(queue, readback_submission);
    darktidevr::producer::signal_ngx_queue_completion(queue, ngx_completion_ticket);
    darktidevr::producer::submit_ngx_gpu_timing(queue, count, lists);
    darktidevr::producer::submit_generated_stereo(queue, count, lists);
    if (log_streamline_eye_boundary) {
      LARGE_INTEGER boundary_qpc{};
      QueryPerformanceCounter(&boundary_qpc);
      write_streamline_probe_log(
          "EYE_OUTPUT_BOUNDARY\tphase=execute_end\tpresent_frame=%llu"
          "\texecute_call=%llu\teye=%d\tpose=%llu\tqueue=%p\tresource=%p"
          "\tstate=%u\tqpc=%lld\r\n",
          static_cast<unsigned long long>(
              present_count.load(std::memory_order_relaxed)),
          static_cast<unsigned long long>(streamline_execute_call),
          requested_eye,
          static_cast<unsigned long long>(requested_pose_sequence), queue,
          completed_back_buffer.Get(),
          static_cast<unsigned>(completed_source_state), boundary_qpc.QuadPart);
    }
    // Snapshot progress must not depend on the short native-Present log burst.
    // Slow startup or opening a menu can exhaust that burst before gameplay.
    if (requested_eye >= 0 &&
        streamline_input_snapshot_probe_requested.load(
            std::memory_order_acquire)) {
      schedule_streamline_input_snapshot(
          requested_eye, present_count.load(std::memory_order_relaxed),
          requested_pose_sequence, queue,completed_back_buffer.Get(),completed_source_state);
    }
    if (gpu_trace_lock.owns_lock()) {
      end_gpu_pass_trace_batch_locked(queue, gpu_trace_token);
    }
  }
  if (completed_menu_output) {
    const auto menu_result = capture_menu_from_resource(
        queue, completed_menu_output.Get(), completed_menu_source_state);
    write_menu_resource_log(
        "MENU_CAPTURE\tframe=%llu\tresource=%p\tstate=%u\tresult=%d"
        "\tready=%llu\r\n",
        present_count.load(std::memory_order_relaxed),
        completed_menu_output.Get(),
        static_cast<unsigned>(completed_menu_source_state), menu_result,
        static_cast<unsigned long long>(menu_ready_value));
  }
  if (requested_eye >= 0 && completed_back_buffer) {
    end_gpu_eye_profile(requested_eye, queue);
    std::uint64_t ready_before{};
    {
      std::scoped_lock lock(state_mutex);
      ready_before = ready_value;
    }
    const auto result = capture_eye_from_resource(
        requested_eye, queue, completed_back_buffer.Get(), true,
        completed_source_state);
    const auto streamline_burst_until =
        streamline_native_burst_until_call.load(std::memory_order_acquire);
    if (streamline_probe_log != INVALID_HANDLE_VALUE &&
        (trace_streamline_submission_images() || (streamline_burst_until != 0 &&
        streamline_native_present_count.load(std::memory_order_relaxed) <=
            streamline_burst_until))) {
      LARGE_INTEGER boundary_qpc{};
      QueryPerformanceCounter(&boundary_qpc);
      const auto source_description = completed_back_buffer->GetDesc();
      write_streamline_probe_log(
          "EYE_OUTPUT_BOUNDARY\tphase=capture_complete\tpresent_frame=%llu"
          "\texecute_call=%llu\teye=%d\tpose=%llu\tqueue=%p\tresource=%p"
          "\tstate=%u\tresult=%d\tqpc=%lld"
          "\twidth=%llu\theight=%u\tfov=%.9g\taspect=%.9g"
          "\tpresentation_mode=%u\tgameplay_generation=%llu\r\n",
          static_cast<unsigned long long>(
              present_count.load(std::memory_order_relaxed)),
          static_cast<unsigned long long>(streamline_execute_call),
          requested_eye,
          static_cast<unsigned long long>(requested_pose_sequence), queue,
          completed_back_buffer.Get(),
          static_cast<unsigned>(completed_source_state), result,
          boundary_qpc.QuadPart,
          static_cast<unsigned long long>(source_description.Width),
          source_description.Height, requested_vertical_fov, requested_aspect_ratio,
          current_presentation_mode.load(std::memory_order_relaxed),
          static_cast<unsigned long long>(current_gameplay_generation.load(std::memory_order_acquire)));
    }
    boundary_last_capture_result.store(result, std::memory_order_relaxed);
    if (result == 0) {
      boundary_eye_capture_counts[static_cast<std::size_t>(requested_eye)]
          .fetch_add(1, std::memory_order_relaxed);
      boundary_eye_pose_sequences[static_cast<std::size_t>(requested_eye)]
          .store(requested_pose_sequence, std::memory_order_relaxed);
      if (requested_eye == 0) {
        boundary_staged_eye0_pose_sequence.store(requested_pose_sequence,
                                                  std::memory_order_relaxed);
        boundary_staged_eye0_vertical_fov.store(requested_vertical_fov,
                                                 std::memory_order_relaxed);
        boundary_staged_eye0_aspect_ratio.store(requested_aspect_ratio,
                                                 std::memory_order_relaxed);
      } else {
        std::uint64_t ready_after{};
        {
          std::scoped_lock lock(state_mutex);
          ready_after = ready_value;
        }
        if (ready_after > ready_before) {
          boundary_published_pair_pose.store(requested_pose_sequence);
          (void)shared_head_pose_reader().publish_rendered_pair(
              {ready_after,
               current_gameplay_generation.load(std::memory_order_acquire),
               {boundary_staged_eye0_pose_sequence.load(
                    std::memory_order_relaxed),
                requested_pose_sequence},
               {boundary_staged_eye0_vertical_fov.load(
                    std::memory_order_relaxed),
                requested_vertical_fov},
               {boundary_staged_eye0_aspect_ratio.load(
                    std::memory_order_relaxed),
                requested_aspect_ratio}});
        }
      }
    }
  }
}

// Bounded evidence of the original allocation before caller-specific routing.
void log_swapchain_extent_query(const char* api, const void* caller,
                               IDXGISwapChain* swapchain, UINT index,
                               std::uint64_t width, UINT height) {
  if (!streamline_stereo_swapchain_probe_requested.load(std::memory_order_acquire)) return;
  static std::mutex query_mutex;
  static std::map<std::pair<const void*, std::uint64_t>, unsigned> samples;
  {
    std::scoped_lock lock(query_mutex);
    const auto key = std::make_pair(caller, width);
    auto found = samples.find(key);
    if (found == samples.end()) {
      if (samples.size() >= 64) return;
      found = samples.emplace(key, 0).first;
    }
    if (found->second++ >= 2) return;
  }
  HMODULE module{};
  wchar_t path[MAX_PATH]{};
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
      GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
      reinterpret_cast<LPCWSTR>(caller), &module);
  if (module) GetModuleFileNameW(module, path, MAX_PATH);
  const auto* leaf = wcsrchr(path, L'\\');
  write_streamline_probe_log(
      "SWAPCHAIN_EXTENT_QUERY\tapi=%s\tcaller=%p\tmodule=%ls\tswapchain=%p"
      "\tindex=%u\textent=%llux%u\tbefore_routing=1\r\n", api, caller,
      leaf ? leaf + 1 : path, swapchain, index,
      static_cast<unsigned long long>(width), height);
}

bool engine_eye_backbuffer_caller(const void* caller) {
  if (!streamline_stereo_swapchain_probe_requested.load(std::memory_order_acquire) ||
      !swapchain_render_extent_enabled.load(std::memory_order_acquire)) return false;
  HMODULE module{};
  wchar_t path[MAX_PATH]{};
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
          GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          reinterpret_cast<LPCWSTR>(caller), &module) ||
      !GetModuleFileNameW(module, path, MAX_PATH)) return false;
  const auto* leaf = wcsrchr(path, L'\\');
  return _wcsicmp(leaf ? leaf + 1 : path,
      L"amd_fidelityfx_framegeneration_dx12.dll") == 0;
}

bool engine_eye_backbuffer_extent(UINT width, UINT height) {
  return width == swapchain_present_width.load(std::memory_order_relaxed) &&
      height == swapchain_render_height.load(std::memory_order_relaxed) &&
      std::uint64_t(width) == 2ULL * camera_input_width.load(std::memory_order_relaxed);
}

HRESULT STDMETHODCALLTYPE swapchain_get_buffer_hook(IDXGISwapChain* swapchain,
                                                    UINT index, REFIID iid, void** object) {
  const auto result = original_swapchain_get_buffer(swapchain, index, iid, object);
  if (SUCCEEDED(result) && object && *object &&
      streamline_stereo_swapchain_probe_requested.load(std::memory_order_acquire)) {
    ComPtr<ID3D12Resource> resource;
    if (SUCCEEDED(static_cast<IUnknown*>(*object)->QueryInterface(IID_PPV_ARGS(&resource)))) {
      const auto description = resource->GetDesc();
      log_swapchain_extent_query("GetBuffer", _ReturnAddress(), swapchain,
                                index, description.Width, description.Height);
      if (description.Width <= UINT_MAX && engine_eye_backbuffer_caller(_ReturnAddress()) &&
          engine_eye_backbuffer_extent(static_cast<UINT>(description.Width), description.Height)) {
        ComPtr<ID3D12Device> device;
        void* replacement{};
        auto hr = resource->GetDevice(IID_PPV_ARGS(&device));
        if (SUCCEEDED(hr)) hr = engine_eye_backbuffers.acquire(device.Get(),
            reinterpret_cast<std::uintptr_t>(swapchain),
            resize_diagnostic_generation.load(std::memory_order_relaxed), index, description,
            camera_input_width.load(std::memory_order_relaxed),
            camera_input_height.load(std::memory_order_relaxed), iid, &replacement);
        static_cast<IUnknown*>(*object)->Release();
        *object = replacement;
        if (SUCCEEDED(hr)) {
          ComPtr<ID3D12Resource> eye_resource;
          if (SUCCEEDED(static_cast<IUnknown*>(replacement)->QueryInterface(IID_PPV_ARGS(&eye_resource)))) {
            std::scoped_lock lock(boundary_capture_mutex);
            swapchain_back_buffers.insert(eye_resource.Get());
          }
        }
        static std::atomic<unsigned> reported{};
        if (reported.fetch_add(1, std::memory_order_relaxed) < 16) {
          write_streamline_probe_log(
              "ENGINE_EYE_BACKBUFFER\tindex=%u\tresult=%ld\tresource=%p"
              "\twidth=%u\theight=%u\tpacked_present_unchanged=1\r\n",
              index, hr, replacement, camera_input_width.load(std::memory_order_relaxed),
              camera_input_height.load(std::memory_order_relaxed));
        }
        return hr;
      }
    }
  }
  return result;
}

HRESULT STDMETHODCALLTYPE swapchain_get_desc_hook(IDXGISwapChain* swapchain,
                                                  DXGI_SWAP_CHAIN_DESC* description) {
  const auto result = original_swapchain_get_desc(swapchain, description);
  if (SUCCEEDED(result) && description) {
    log_swapchain_extent_query("GetDesc", _ReturnAddress(), swapchain, UINT_MAX,
                              description->BufferDesc.Width, description->BufferDesc.Height);
    if (engine_eye_backbuffer_caller(_ReturnAddress()) &&
        engine_eye_backbuffer_extent(description->BufferDesc.Width, description->BufferDesc.Height)) {
      description->BufferDesc.Width = camera_input_width.load(std::memory_order_relaxed);
      description->BufferDesc.Height = camera_input_height.load(std::memory_order_relaxed);
    }
  }
  return result;
}

HRESULT STDMETHODCALLTYPE swapchain_get_desc1_hook(IDXGISwapChain1* swapchain,
                                                   DXGI_SWAP_CHAIN_DESC1* description) {
  const auto result = original_swapchain_get_desc1(swapchain, description);
  if (SUCCEEDED(result) && description && engine_eye_backbuffer_caller(_ReturnAddress()) &&
      engine_eye_backbuffer_extent(description->Width, description->Height)) {
    description->Width = camera_input_width.load(std::memory_order_relaxed);
    description->Height = camera_input_height.load(std::memory_order_relaxed);
  }
  return result;
}

HRESULT STDMETHODCALLTYPE resize_buffers_hook(IDXGISwapChain* swapchain,
                                               UINT buffer_count, UINT width,
                                               UINT height, DXGI_FORMAT format,
                                               UINT flags) {
  const auto requested_width = width;
  const auto requested_height = height;
  if (swapchain_render_extent_enabled.load(std::memory_order_acquire)) {
    width = swapchain_present_width.load(std::memory_order_relaxed);
    height = swapchain_render_height.load(std::memory_order_relaxed);
  }
  const auto frame = present_count.load(std::memory_order_relaxed);
  const auto generation = resize_diagnostic_generation.load(
      std::memory_order_relaxed);
  write_resize_diagnostic_log(
      "frame=%llu\tRESIZE_BEGIN\tapi=ResizeBuffers\tgeneration=%llu"
      "\tswapchain=%p\trequested=%ux%u\tapplied=%ux%u\tbuffers=%u"
      "\tformat=%u\tflags=%u\r\n",
      frame, static_cast<unsigned long long>(generation), swapchain,
      requested_width, requested_height, width, height, buffer_count,
      static_cast<unsigned>(format), flags);
  // These maps can retain COM references to a back buffer. Release them before
  // calling DXGI, as ResizeBuffers is required to fail while such references
  // exist. Regardless of the result, the next Present can reconstruct all raw
  // identities and states from the still-valid or newly-created buffers.
  game_swapchain_metadata_ready.store(false, std::memory_order_release);
  {
    std::scoped_lock lock(boundary_capture_mutex);
    swapchain_back_buffers.clear();
    swapchain_back_buffer_states.clear();
    camera_output_resources.clear();
    camera_output_source_states.clear();
    menu_output_resources.clear();
    menu_output_source_states.clear();
    known_camera_output_resources.clear();
    named_camera_output_resources = {};
    named_camera_outputs_ready = false;
    named_camera_outputs_ready_hint.store(false, std::memory_order_release);
    camera_output_realign_pending = false;
    present_transition_resources.clear();
  }
  const auto result = original_resize_buffers(swapchain, buffer_count, width,
                                              height, format, flags);
  auto next_generation = generation;
  if (SUCCEEDED(result)) {
    next_generation = resize_diagnostic_generation.fetch_add(
                          1, std::memory_order_relaxed) +
                      1;
    resize_diagnostic_burst_until_present.store(frame + 16,
                                                std::memory_order_relaxed);
  }
  write_resize_diagnostic_log(
      "frame=%llu\tRESIZE_END\tapi=ResizeBuffers\tgeneration=%llu"
      "\tresult=%ld\r\n",
      frame, static_cast<unsigned long long>(next_generation), result);
  return result;
}

HRESULT STDMETHODCALLTYPE resize_buffers1_hook(
    IDXGISwapChain3* swapchain, UINT buffer_count, UINT width, UINT height,
    DXGI_FORMAT format, UINT flags, const UINT* creation_node_masks,
    IUnknown* const* present_queues) {
  const auto requested_width = width;
  const auto requested_height = height;
  if (swapchain_render_extent_enabled.load(std::memory_order_acquire)) {
    width = swapchain_present_width.load(std::memory_order_relaxed);
    height = swapchain_render_height.load(std::memory_order_relaxed);
  }
  const auto frame = present_count.load(std::memory_order_relaxed);
  const auto generation = resize_diagnostic_generation.load(
      std::memory_order_relaxed);
  write_resize_diagnostic_log(
      "frame=%llu\tRESIZE_BEGIN\tapi=ResizeBuffers1\tgeneration=%llu"
      "\tswapchain=%p\trequested=%ux%u\tapplied=%ux%u\tbuffers=%u"
      "\tformat=%u\tflags=%u\r\n",
      frame, static_cast<unsigned long long>(generation), swapchain,
      requested_width, requested_height, width, height, buffer_count,
      static_cast<unsigned>(format), flags);
  game_swapchain_metadata_ready.store(false, std::memory_order_release);
  {
    std::scoped_lock lock(boundary_capture_mutex);
    swapchain_back_buffers.clear();
    swapchain_back_buffer_states.clear();
    camera_output_resources.clear();
    camera_output_source_states.clear();
    menu_output_resources.clear();
    menu_output_source_states.clear();
    known_camera_output_resources.clear();
    named_camera_output_resources = {};
    named_camera_outputs_ready = false;
    named_camera_outputs_ready_hint.store(false, std::memory_order_release);
    camera_output_realign_pending = false;
    present_transition_resources.clear();
  }
  const auto result = original_resize_buffers1(
      swapchain, buffer_count, width, height, format, flags,
      creation_node_masks, present_queues);
  auto next_generation = generation;
  if (SUCCEEDED(result)) {
    next_generation = resize_diagnostic_generation.fetch_add(
                          1, std::memory_order_relaxed) +
                      1;
    resize_diagnostic_burst_until_present.store(frame + 16,
                                                std::memory_order_relaxed);
  }
  write_resize_diagnostic_log(
      "frame=%llu\tRESIZE_END\tapi=ResizeBuffers1\tgeneration=%llu"
      "\tresult=%ld\r\n",
      frame, static_cast<unsigned long long>(next_generation), result);
  return result;
}

BOOL WINAPI get_client_rect_hook(HWND window, LPRECT rectangle) {
  const auto result = original_get_client_rect(window, rectangle);
  if (!result || !rectangle ||
      !virtual_client_extent_enabled.load(std::memory_order_acquire) ||
      window != game_output_window.load(std::memory_order_relaxed)) {
    return result;
  }
  HMODULE caller_module{};
  const auto caller = _ReturnAddress();
  if (!GetModuleHandleExW(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          reinterpret_cast<LPCWSTR>(caller), &caller_module) ||
      caller_module != GetModuleHandleW(nullptr)) {
    return result;
  }
  const auto physical_width = rectangle->right - rectangle->left;
  const auto physical_height = rectangle->bottom - rectangle->top;
  rectangle->left = 0;
  rectangle->top = 0;
  rectangle->right = static_cast<LONG>(
      swapchain_render_width.load(std::memory_order_relaxed));
  rectangle->bottom = static_cast<LONG>(
      swapchain_render_height.load(std::memory_order_relaxed));
  write_boundary_census_log(
      "frame=%llu\tVIRTUAL_CLIENT\tcaller_rva=%llu\tphysical=%ldx%ld"
      "\treported=%ldx%ld\r\n",
      present_count.load(std::memory_order_relaxed),
      static_cast<unsigned long long>(
          reinterpret_cast<std::uintptr_t>(caller) -
          reinterpret_cast<std::uintptr_t>(caller_module)),
      physical_width, physical_height, rectangle->right, rectangle->bottom);
  return result;
}

LRESULT WINAPI dispatch_message_w_hook(const MSG* message) {
  const auto game_window = game_output_window.load(std::memory_order_relaxed);
  if (message && message->message == WM_SIZE &&
      message->hwnd == game_window) {
    RECT client{};
    if (original_get_client_rect) {
      original_get_client_rect(message->hwnd, &client);
    }
    write_resize_diagnostic_log(
        "frame=%llu\tWM_SIZE_DISPATCH\twparam=%llu\tlparam=%ux%u"
        "\tclient=%ldx%ld\tvirtual=%u\r\n",
        present_count.load(std::memory_order_relaxed),
        static_cast<unsigned long long>(message->wParam),
        static_cast<unsigned>(LOWORD(message->lParam)),
        static_cast<unsigned>(HIWORD(message->lParam)),
        client.right - client.left, client.bottom - client.top,
        virtual_size_message_enabled.load(std::memory_order_relaxed) ? 1U
                                                                     : 0U);
  }
  if (!message || message->message != WM_SIZE ||
      !virtual_size_message_enabled.load(std::memory_order_acquire) ||
      message->hwnd != game_window) {
    return original_dispatch_message_w(message);
  }
  MSG virtual_message = *message;
  const auto physical_width = LOWORD(message->lParam);
  const auto physical_height = HIWORD(message->lParam);
  const auto width = swapchain_render_width.load(std::memory_order_relaxed);
  const auto height = swapchain_render_height.load(std::memory_order_relaxed);
  virtual_message.lParam = MAKELPARAM(width, height);
  write_boundary_census_log(
      "frame=%llu\tVIRTUAL_WM_SIZE\twparam=%llu\tphysical=%ux%u"
      "\treported=%ux%u\r\n",
      present_count.load(std::memory_order_relaxed),
      static_cast<unsigned long long>(virtual_message.wParam), physical_width,
      physical_height, width, height);
  return original_dispatch_message_w(&virtual_message);
}

LRESULT CALLBACK virtual_game_window_proc(HWND window, UINT message,
                                          WPARAM wparam, LPARAM lparam) {
  WNDPROC original{};
  {
    std::scoped_lock lock(virtual_window_proc_mutex);
    original = original_game_window_proc;
  }
  if (!original) {
    return DefWindowProcW(window, message, wparam, lparam);
  }
  if (message == WM_SIZE &&
      window == game_output_window.load(std::memory_order_relaxed)) {
    RECT client{};
    if (original_get_client_rect) {
      original_get_client_rect(window, &client);
    }
    write_resize_diagnostic_log(
        "frame=%llu\tWM_SIZE_WNDPROC\twparam=%llu\tlparam=%ux%u"
        "\tclient=%ldx%ld\tvirtual=%u\r\n",
        present_count.load(std::memory_order_relaxed),
        static_cast<unsigned long long>(wparam),
        static_cast<unsigned>(LOWORD(lparam)),
        static_cast<unsigned>(HIWORD(lparam)), client.right - client.left,
        client.bottom - client.top,
        virtual_size_message_enabled.load(std::memory_order_relaxed) ? 1U
                                                                     : 0U);
  }
  if (message == WM_SIZE &&
      virtual_size_message_enabled.load(std::memory_order_acquire) &&
      window == game_output_window.load(std::memory_order_relaxed)) {
    const auto physical_width = LOWORD(lparam);
    const auto physical_height = HIWORD(lparam);
    const auto width = swapchain_render_width.load(std::memory_order_relaxed);
    const auto height = swapchain_render_height.load(std::memory_order_relaxed);
    lparam = MAKELPARAM(width, height);
    write_boundary_census_log(
        "frame=%llu\tVIRTUAL_WNDPROC_SIZE\twparam=%llu\tphysical=%ux%u"
        "\treported=%ux%u\r\n",
        present_count.load(std::memory_order_relaxed),
        static_cast<unsigned long long>(wparam), physical_width,
        physical_height, width, height);
  }
  return CallWindowProcW(original, window, message, wparam, lparam);
}

void ensure_virtual_window_proc(HWND window) {
  if (!window ||
      !virtual_size_message_enabled.load(std::memory_order_acquire)) {
    return;
  }
  std::scoped_lock lock(virtual_window_proc_mutex);
  if (virtual_window_proc_window == window && original_game_window_proc) {
    return;
  }
  SetLastError(ERROR_SUCCESS);
  const auto previous = SetWindowLongPtrW(
      window, GWLP_WNDPROC,
      reinterpret_cast<LONG_PTR>(&virtual_game_window_proc));
  if (previous != 0 || GetLastError() == ERROR_SUCCESS) {
    virtual_window_proc_window = window;
    original_game_window_proc = reinterpret_cast<WNDPROC>(previous);
    write_resize_diagnostic_log(
        "frame=%llu\tVIRTUAL_WNDPROC_INSTALLED\twindow=%p"
        "\toriginal=%p\r\n",
        present_count.load(std::memory_order_relaxed), window,
        reinterpret_cast<void*>(previous));
  }
}

void lock_swapchain_client_extent(HWND window) {
  if (!window ||
      !swapchain_client_extent_locked.load(std::memory_order_acquire)) {
    return;
  }
  const auto target_width =
      swapchain_render_width.load(std::memory_order_relaxed);
  const auto target_height =
      swapchain_render_height.load(std::memory_order_relaxed);
  RECT client{};
  if (!GetClientRect(window, &client) ||
      (client.right - client.left == static_cast<LONG>(target_width) &&
       client.bottom - client.top == static_cast<LONG>(target_height))) {
    return;
  }

  RECT outer{0, 0, static_cast<LONG>(target_width),
             static_cast<LONG>(target_height)};
  const auto style = static_cast<DWORD>(GetWindowLongPtrW(window, GWL_STYLE));
  const auto extended_style =
      static_cast<DWORD>(GetWindowLongPtrW(window, GWL_EXSTYLE));
  const auto dpi = GetDpiForWindow(window);
  if (!AdjustWindowRectExForDpi(&outer, style, FALSE, extended_style,
                                dpi ? dpi : USER_DEFAULT_SCREEN_DPI)) {
    return;
  }
  SetWindowPos(window, nullptr, 0, 0, outer.right - outer.left,
               outer.bottom - outer.top,
               SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
}

void nudge_swapchain_client_extent(HWND window, bool requested) {
  if (!window ||
      swapchain_client_extent_locked.load(std::memory_order_acquire)) {
    return;
  }
  auto phase = swapchain_resize_nudge_phase.load(std::memory_order_relaxed);
  if (requested && phase == 0) {
    RECT client{};
    RECT window_rect{};
    if (!GetClientRect(window, &client) || !GetWindowRect(window, &window_rect)) {
      return;
    }
    swapchain_resize_nudge_original_window = window_rect;
    RECT outer{0, 0, client.right - client.left + 1,
               client.bottom - client.top};
    const auto style = static_cast<DWORD>(GetWindowLongPtrW(window, GWL_STYLE));
    const auto extended_style =
        static_cast<DWORD>(GetWindowLongPtrW(window, GWL_EXSTYLE));
    const auto dpi = GetDpiForWindow(window);
    if (!AdjustWindowRectExForDpi(&outer, style, FALSE, extended_style,
                                  dpi ? dpi : USER_DEFAULT_SCREEN_DPI)) {
      return;
    }
    write_resize_diagnostic_log(
        "frame=%llu\tNUDGE_BEGIN\tphase=expand\tclient=%ldx%ld"
        "\twindow=%ldx%ld\ttarget_window=%ldx%ld\r\n",
        present_count.load(std::memory_order_relaxed),
        client.right - client.left, client.bottom - client.top,
        window_rect.right - window_rect.left, window_rect.bottom - window_rect.top,
        outer.right - outer.left, outer.bottom - outer.top);
    const auto positioned =
        SetWindowPos(window, nullptr, 0, 0, outer.right - outer.left,
                     outer.bottom - outer.top,
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    RECT resulting_client{};
    if (original_get_client_rect) {
      original_get_client_rect(window, &resulting_client);
    }
    write_resize_diagnostic_log(
        "frame=%llu\tNUDGE_END\tphase=expand\tresult=%u"
        "\tclient=%ldx%ld\r\n",
        present_count.load(std::memory_order_relaxed), positioned ? 1U : 0U,
        resulting_client.right - resulting_client.left,
        resulting_client.bottom - resulting_client.top);
    if (positioned) {
      swapchain_resize_nudge_phase.store(1, std::memory_order_relaxed);
    }
    return;
  }
  if (phase == 1) {
    const auto& original = swapchain_resize_nudge_original_window;
    LONG restore_width = original.right - original.left;
    LONG restore_height = original.bottom - original.top;
    const auto requested_width =
        mirror_client_width.load(std::memory_order_relaxed);
    const auto requested_height =
        mirror_client_height.load(std::memory_order_relaxed);
    if (requested_width != 0 && requested_height != 0) {
      RECT outer{0, 0, static_cast<LONG>(requested_width),
                 static_cast<LONG>(requested_height)};
      const auto style =
          static_cast<DWORD>(GetWindowLongPtrW(window, GWL_STYLE));
      const auto extended_style =
          static_cast<DWORD>(GetWindowLongPtrW(window, GWL_EXSTYLE));
      const auto dpi = GetDpiForWindow(window);
      if (AdjustWindowRectExForDpi(&outer, style, FALSE, extended_style,
                                   dpi ? dpi : USER_DEFAULT_SCREEN_DPI)) {
        restore_width = outer.right - outer.left;
        restore_height = outer.bottom - outer.top;
      }
    }
    RECT before_restore_client{};
    if (original_get_client_rect) {
      original_get_client_rect(window, &before_restore_client);
    }
    write_resize_diagnostic_log(
        "frame=%llu\tNUDGE_BEGIN\tphase=restore\tclient=%ldx%ld"
        "\ttarget_window=%ldx%ld\r\n",
        present_count.load(std::memory_order_relaxed),
        before_restore_client.right - before_restore_client.left,
        before_restore_client.bottom - before_restore_client.top, restore_width,
        restore_height);
    const auto positioned =
        SetWindowPos(window, nullptr, 0, 0, restore_width, restore_height,
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    RECT resulting_client{};
    if (original_get_client_rect) {
      original_get_client_rect(window, &resulting_client);
    }
    write_resize_diagnostic_log(
        "frame=%llu\tNUDGE_END\tphase=restore\tresult=%u"
        "\tclient=%ldx%ld\r\n",
        present_count.load(std::memory_order_relaxed), positioned ? 1U : 0U,
        resulting_client.right - resulting_client.left,
        resulting_client.bottom - resulting_client.top);
    if (positioned) {
      swapchain_resize_nudge_phase.store(2, std::memory_order_relaxed);
    }
  }
}

void poll_focused_trace_request() {
  wchar_t temporary_path[MAX_PATH]{};
  if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
    return;
  }
  for (const auto phase : {1, 2, 0}) {
    const auto path = std::wstring(temporary_path) +
                      L"darktidevr-focused-phase-" +
                      std::to_wstring(phase) + L".request";
    if (GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
      continue;
    }
    if (DeleteFileW(path.c_str())) {
      if (phase == 1) {
        (void)dtvr_enable_marker_log();
      }
      (void)dtvr_set_focused_trace_phase(phase);
    }
    break;
  }
}

int present_desktop_eye_mirror(IDXGISwapChain3* swapchain,
                               ID3D12CommandQueue* queue, bool engine_source) {
  if (!swapchain || !queue ||
      (!engine_source && !desktop_mirror_ready.load(std::memory_order_acquire))) {
    return 100;
  }
  ComPtr<ID3D12Resource> back_buffer;
  ComPtr<ID3D12Device> device;
  if (FAILED(swapchain->GetBuffer(swapchain->GetCurrentBackBufferIndex(),
                                  IID_PPV_ARGS(&back_buffer))) ||
      FAILED(back_buffer->GetDevice(IID_PPV_ARGS(&device)))) {
    return 101;
  }

  PendingCapture pending;
  ComPtr<ID3D12Resource> mirror;
  ComPtr<ID3D12Fence> fence;
  ComPtr<ID3D12Fence> capture_fence;
  std::uint64_t capture_ready_value{};
  std::uint64_t signal_value{};
  if (engine_source) {
    mirror = engine_eye_backbuffers.find(reinterpret_cast<std::uintptr_t>(swapchain),
        resize_diagnostic_generation.load(std::memory_order_relaxed),
        swapchain->GetCurrentBackBufferIndex());
    if (!mirror) return 102;
  }
  {
    std::unique_lock lock(state_mutex);
    if (!engine_source) mirror = desktop_mirror_surface;
    if (engine_source && !desktop_mirror_fence &&
        FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
            IID_PPV_ARGS(&desktop_mirror_fence)))) return 102;
    fence = desktop_mirror_fence;
    capture_fence = ready_fence;
    capture_ready_value = ready_value;
    if (!mirror || !fence || (!engine_source && (!capture_fence || capture_ready_value == 0))) {
      return 102;
    }
    auto reclaim_completed = [&] {
      const auto completed = fence->GetCompletedValue();
      if (completed == UINT64_MAX) {
        return false;
      }
      while (!desktop_mirror_pending.empty() &&
             desktop_mirror_pending.front().fence_value <= completed) {
        desktop_mirror_pending.front().fence_value = 0;
        desktop_mirror_available.push_back(
            std::move(desktop_mirror_pending.front()));
        desktop_mirror_pending.pop_front();
      }
      return true;
    };
    if ((!engine_source && capture_fence->GetCompletedValue() == UINT64_MAX) ||
        !reclaim_completed()) {
      return 110;
    }
    if (desktop_mirror_pending.size() >= 8) {
      // Every swapchain buffer initially contains the game's own presentation
      // (including a retained splash/loading image). Skipping injection when
      // the asynchronous allocator pool is full lets those stale buffers recur
      // on the desktop. Wait for the oldest already-submitted copy and reuse
      // it instead. This queue is ordered before Present, so a short wait here
      // is both safe and preferable to showing the wrong frame.
      const auto oldest = desktop_mirror_pending.front().fence_value;
      // SetEventOnCompletion retains the supplied handle until the target is
      // reached. Closing a throwaway event after a timeout lets a later fence
      // completion signal a recycled, unrelated Windows handle. Keep one
      // presentation-thread-lifetime event. Present is serialized per thread;
      // a second swapchain thread receives its own event rather than racing it.
      thread_local HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
      if (!event || !ResetEvent(event) ||
          FAILED(fence->SetEventOnCompletion(oldest, event))) {
        return 103;
      }
      lock.unlock();
      const auto wait_result = WaitForSingleObject(event, 1000);
      lock.lock();
      const auto waited_completed = fence->GetCompletedValue();
      if (wait_result != WAIT_OBJECT_0 || waited_completed == UINT64_MAX ||
          waited_completed < oldest) {
        return 108;
      }
      if (!reclaim_completed()) {
        return 110;
      }
    }
    if (!desktop_mirror_available.empty()) {
      pending = std::move(desktop_mirror_available.front());
      desktop_mirror_available.pop_front();
    }
    signal_value = desktop_mirror_fence_value + 1;
  }

  const auto source_description = mirror->GetDesc();
  const auto destination_description = back_buffer->GetDesc();
  const bool stretch_mirror =
      streamline_stereo_swapchain_probe_requested.load(std::memory_order_acquire) &&
      destination_description.Width == source_description.Width * 2 &&
      destination_description.Height == source_description.Height;
  if (source_description.Format != destination_description.Format ||
      (!stretch_mirror && source_description.Width != destination_description.Width) ||
      source_description.Height != destination_description.Height) {
    return 104;
  }
  if (pending.allocator && pending.commands) {
    if (FAILED(pending.allocator->Reset()) ||
        FAILED(pending.commands->Reset(pending.allocator.Get(), nullptr))) {
      return 105;
    }
  } else if (FAILED(device->CreateCommandAllocator(
                 D3D12_COMMAND_LIST_TYPE_DIRECT,
                 IID_PPV_ARGS(&pending.allocator))) ||
             FAILED(device->CreateCommandList(
                 0, D3D12_COMMAND_LIST_TYPE_DIRECT, pending.allocator.Get(),
                 nullptr, IID_PPV_ARGS(&pending.commands)))) {
    return 105;
  }

  if (stretch_mirror) {
    if (!pending.mirror_blit) pending.mirror_blit =
        std::make_shared<darktidevr::producer::DesktopMirrorBlit>();
    if (FAILED(pending.mirror_blit->record(device.Get(), pending.commands.Get(),
                                         mirror.Get(), back_buffer.Get()))) return 104;
  } else {
  std::array<D3D12_RESOURCE_BARRIER, 2> barriers{};
  barriers[0].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barriers[0].Transition.pResource = mirror.Get();
  barriers[0].Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
  barriers[0].Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
  barriers[0].Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  barriers[1].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barriers[1].Transition.pResource = back_buffer.Get();
  barriers[1].Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
  barriers[1].Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_DEST;
  barriers[1].Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  pending.commands->ResourceBarrier(static_cast<UINT>(barriers.size()),
                                    barriers.data());
  pending.commands->CopyResource(back_buffer.Get(), mirror.Get());
  for (auto& barrier : barriers) {
    std::swap(barrier.Transition.StateBefore,
              barrier.Transition.StateAfter);
  }
  pending.commands->ResourceBarrier(static_cast<UINT>(barriers.size()),
                                    barriers.data());
  }
  if (FAILED(pending.commands->Close())) {
    return 106;
  }
  // Eye capture and DXGI Present can be submitted through different direct
  // queues. The mirror resource is populated in the eye-1 capture command
  // list immediately before ready_fence is signalled. Without this GPU-side
  // cross-queue dependency, Present can read that resource while it is still
  // being written and expose a previous or partially updated frame. The XR
  // consumer already waits on this same value; give the desktop mirror the
  // identical completed-pair contract.
  if (fence->GetCompletedValue() == UINT64_MAX ||
      (!engine_source && (capture_fence->GetCompletedValue() == UINT64_MAX ||
      FAILED(queue->Wait(capture_fence.Get(), capture_ready_value))))) {
    return 109;
  }
  ID3D12CommandList* lists[]{pending.commands.Get()};
  original_execute_command_lists(queue, 1, lists);
  if (FAILED(queue->Signal(fence.Get(), signal_value))) {
    return 107;
  }
  pending.fence_value = signal_value;
  {
    std::scoped_lock lock(state_mutex);
    desktop_mirror_fence_value = signal_value;
    desktop_mirror_pending.push_back(std::move(pending));
  }
  return 0;
}

bool is_streamline_generated_present_candidate(
    DWORD present_thread, std::int64_t present_qpc,
    std::int64_t qpc_frequency, ID3D12CommandQueue*& matched_queue,
    std::uint64_t& matched_execute_call,
    std::int64_t& matched_delta_microseconds) {
  if (present_qpc <= 0 || qpc_frequency <= 0) {
    return false;
  }
  const auto execute_total =
      streamline_execute_count.load(std::memory_order_acquire);
  for (std::uint64_t offset = 0;
       offset < kStreamlineExecuteHistory && execute_total > offset;
       ++offset) {
    const auto execute_call = execute_total - offset;
    auto& snapshot = streamline_execute_history[
        execute_call % kStreamlineExecuteHistory];
    if (snapshot.call.load(std::memory_order_acquire) != execute_call ||
        snapshot.thread.load(std::memory_order_relaxed) != present_thread ||
        snapshot.queue_type.load(std::memory_order_relaxed) !=
            static_cast<UINT>(D3D12_COMMAND_LIST_TYPE_DIRECT) ||
        snapshot.list_count.load(std::memory_order_relaxed) != 1) {
      continue;
    }
    const auto execute_qpc = snapshot.qpc.load(std::memory_order_relaxed);
    const auto delta_microseconds =
        execute_qpc > 0 && execute_qpc <= present_qpc
            ? (present_qpc - execute_qpc) * 1000000LL / qpc_frequency
            : -1;
    if (delta_microseconds < 0 || delta_microseconds > 500) {
      continue;
    }
    matched_queue = snapshot.queue.load(std::memory_order_relaxed);
    matched_execute_call = execute_call;
    matched_delta_microseconds = delta_microseconds;
    return true;
  }
  return false;
}

void harvest_streamline_copy_probe() {
  std::scoped_lock lock(streamline_copy_probe_mutex);
  auto& probe = streamline_copy_probe_state;
  if (!probe.pending || !probe.fence ||
      probe.fence->GetCompletedValue() < 1) {
    return;
  }
  constexpr std::size_t kCopyBytes = 64U * 256U;
  D3D12_RANGE read_range{0, kCopyBytes};
  void* mapped{};
  if (FAILED(probe.readback->Map(0, &read_range, &mapped)) || !mapped) {
    probe.pending = false;
    write_streamline_probe_log(
        "GENERATED_COPY_COMPLETE\tresult=map_failed\tnative_call=%llu"
        "\touter_frame=%llu\r\n",
        static_cast<unsigned long long>(probe.native_call),
        static_cast<unsigned long long>(probe.outer_frame));
    return;
  }
  const auto* bytes = static_cast<const std::uint8_t*>(mapped);
  std::uint64_t hash = 1469598103934665603ULL;
  std::uint64_t nonzero{};
  std::uint8_t minimum{255};
  std::uint8_t maximum{};
  for (std::size_t index = 0; index < kCopyBytes; ++index) {
    const auto value = bytes[index];
    hash ^= value;
    hash *= 1099511628211ULL;
    nonzero += value != 0 ? 1U : 0U;
    minimum = (std::min)(minimum, value);
    maximum = (std::max)(maximum, value);
  }
  D3D12_RANGE written_range{};
  probe.readback->Unmap(0, &written_range);
  probe.pending = false;
  probe.complete = true;
  write_streamline_probe_log(
      "GENERATED_COPY_COMPLETE\tresult=success\tnative_call=%llu"
      "\touter_frame=%llu\tx=%u\ty=%u\twidth=64\theight=64"
      "\trow_pitch=256\thash=%016llx\tnonzero_bytes=%llu"
      "\tmin_byte=%u\tmax_byte=%u\r\n",
      static_cast<unsigned long long>(probe.native_call),
      static_cast<unsigned long long>(probe.outer_frame), probe.source_x,
      probe.source_y, static_cast<unsigned long long>(hash),
      static_cast<unsigned long long>(nonzero),
      static_cast<unsigned>(minimum), static_cast<unsigned>(maximum));
}

void schedule_streamline_copy_probe(ID3D12CommandQueue* queue,
                                    ID3D12Resource* back_buffer,
                                    std::uint64_t native_call,
                                    std::uint64_t outer_frame) {
  std::scoped_lock lock(streamline_copy_probe_mutex);
  auto& probe = streamline_copy_probe_state;
  if (probe.attempted || !queue || !back_buffer ||
      !original_execute_command_lists) {
    return;
  }
  probe.attempted = true;
  const auto source = back_buffer->GetDesc();
  if (source.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
      source.Format != DXGI_FORMAT_R8G8B8A8_UNORM || source.Width < 64 ||
      source.Height < 64) {
    write_streamline_probe_log(
        "GENERATED_COPY_SCHEDULE\tresult=unsupported_resource"
        "\tnative_call=%llu\touter_frame=%llu\twidth=%llu\theight=%u"
        "\tformat=%u\r\n",
        static_cast<unsigned long long>(native_call),
        static_cast<unsigned long long>(outer_frame),
        static_cast<unsigned long long>(source.Width), source.Height,
        static_cast<unsigned>(source.Format));
    return;
  }
  ComPtr<ID3D12Device> device;
  ComPtr<ID3D12CommandAllocator> allocator;
  ComPtr<ID3D12GraphicsCommandList> commands;
  ComPtr<ID3D12Resource> readback;
  ComPtr<ID3D12Fence> fence;
  D3D12_HEAP_PROPERTIES heap{};
  heap.Type = D3D12_HEAP_TYPE_READBACK;
  heap.CreationNodeMask = 1;
  heap.VisibleNodeMask = 1;
  D3D12_RESOURCE_DESC buffer{};
  buffer.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
  buffer.Width = 64U * 256U;
  buffer.Height = 1;
  buffer.DepthOrArraySize = 1;
  buffer.MipLevels = 1;
  buffer.SampleDesc.Count = 1;
  buffer.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  if (FAILED(back_buffer->GetDevice(IID_PPV_ARGS(&device))) ||
      FAILED(device->CreateCommandAllocator(
          D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator))) ||
      FAILED(device->CreateCommandList(
          0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator.Get(), nullptr,
          IID_PPV_ARGS(&commands))) ||
      FAILED(device->CreateCommittedResource(
          &heap, D3D12_HEAP_FLAG_NONE, &buffer,
          D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
          IID_PPV_ARGS(&readback))) ||
      FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                 IID_PPV_ARGS(&fence)))) {
    write_streamline_probe_log(
        "GENERATED_COPY_SCHEDULE\tresult=resource_creation_failed"
        "\tnative_call=%llu\touter_frame=%llu\r\n",
        static_cast<unsigned long long>(native_call),
        static_cast<unsigned long long>(outer_frame));
    return;
  }
  D3D12_RESOURCE_BARRIER barrier{};
  barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barrier.Transition.pResource = back_buffer;
  barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
  barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
  commands->ResourceBarrier(1, &barrier);
  D3D12_TEXTURE_COPY_LOCATION destination{};
  destination.pResource = readback.Get();
  destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
  destination.PlacedFootprint.Footprint.Format = source.Format;
  destination.PlacedFootprint.Footprint.Width = 64;
  destination.PlacedFootprint.Footprint.Height = 64;
  destination.PlacedFootprint.Footprint.Depth = 1;
  destination.PlacedFootprint.Footprint.RowPitch = 256;
  D3D12_TEXTURE_COPY_LOCATION source_location{};
  source_location.pResource = back_buffer;
  source_location.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
  const auto source_x = static_cast<UINT>(source.Width / 2U - 32U);
  const auto source_y = source.Height / 2U - 32U;
  D3D12_BOX source_box{source_x, source_y, 0, source_x + 64U,
                       source_y + 64U, 1};
  commands->CopyTextureRegion(&destination, 0, 0, 0, &source_location,
                              &source_box);
  std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
  commands->ResourceBarrier(1, &barrier);
  if (FAILED(commands->Close())) {
    write_streamline_probe_log(
        "GENERATED_COPY_SCHEDULE\tresult=command_close_failed"
        "\tnative_call=%llu\touter_frame=%llu\r\n",
        static_cast<unsigned long long>(native_call),
        static_cast<unsigned long long>(outer_frame));
    return;
  }
  ID3D12CommandList* copy_lists[]{commands.Get()};
  original_execute_command_lists(queue, 1, copy_lists);
  if (FAILED(queue->Signal(fence.Get(), 1))) {
    write_streamline_probe_log(
        "GENERATED_COPY_SCHEDULE\tresult=signal_failed"
        "\tnative_call=%llu\touter_frame=%llu\r\n",
        static_cast<unsigned long long>(native_call),
        static_cast<unsigned long long>(outer_frame));
    return;
  }
  probe.pending = true;
  probe.native_call = native_call;
  probe.outer_frame = outer_frame;
  probe.source_x = source_x;
  probe.source_y = source_y;
  probe.allocator = std::move(allocator);
  probe.commands = std::move(commands);
  probe.readback = std::move(readback);
  probe.fence = std::move(fence);
  write_streamline_probe_log(
      "GENERATED_COPY_SCHEDULE\tresult=submitted\tnative_call=%llu"
      "\touter_frame=%llu\tqueue_source=swapchain_present_transition"
      "\tqueue=%p\tback_buffer=%p"
      "\tx=%u\ty=%u\twidth=64\theight=64\trow_pitch=256\r\n",
      static_cast<unsigned long long>(native_call),
      static_cast<unsigned long long>(outer_frame), queue, back_buffer,
      source_x, source_y);
}

void harvest_streamline_transport_probe() {
  std::scoped_lock lock(streamline_transport_mutex);
  if (!streamline_transport_consumed_fence) {
    return;
  }
  const auto consumed =
      streamline_transport_consumed_fence->GetCompletedValue();
  for (std::size_t index = 0; index < streamline_transport_slots.size();
       ++index) {
    auto& slot = streamline_transport_slots[index];
    if (!slot.pending || consumed < slot.sequence) {
      continue;
    }
    slot.pending = false;
    ++streamline_transport_completed;
    write_streamline_probe_log(
        "GENERATED_TRANSPORT_COMPLETE\tslot=%zu\tnative_call=%llu"
        "\tframe_index=%u\tsequence=%llu\tconsumed=%llu"
        "\tcompleted=%llu\r\n",
        index, static_cast<unsigned long long>(slot.native_call),
        slot.frame_index,
        static_cast<unsigned long long>(slot.sequence),
        static_cast<unsigned long long>(consumed),
        static_cast<unsigned long long>(streamline_transport_completed));
  }
}

void reset_streamline_transport_resources() {
  for (auto& handle : streamline_transport_surface_handles) {
    if (handle) {
      CloseHandle(handle);
      handle = nullptr;
    }
  }
  if (streamline_transport_ready_handle) {
    CloseHandle(streamline_transport_ready_handle);
    streamline_transport_ready_handle = nullptr;
  }
  if (streamline_transport_consumed_handle) {
    CloseHandle(streamline_transport_consumed_handle);
    streamline_transport_consumed_handle = nullptr;
  }
  streamline_transport_ready_fence.Reset();
  streamline_transport_consumed_fence.Reset();
  streamline_transport_slots = {};
}

bool ensure_streamline_transport_resources(
    ID3D12Device* device, const D3D12_RESOURCE_DESC& source) {
  const bool matching = streamline_transport_ready_fence &&
      streamline_transport_consumed_fence &&
      std::all_of(streamline_transport_slots.begin(),
                  streamline_transport_slots.end(), [&](const auto& slot) {
                    if (!slot.surface || !slot.allocator || !slot.commands) {
                      return false;
                    }
                    const auto current = slot.surface->GetDesc();
                    return current.Width == source.Width &&
                           current.Height == source.Height &&
                           current.Format == source.Format;
                  });
  if (matching) {
    return true;
  }
  if (std::any_of(streamline_transport_slots.begin(),
                  streamline_transport_slots.end(),
                  [](const auto& slot) {
                    return slot.pending || slot.reserved;
                  })) {
    return false;
  }
  reset_streamline_transport_resources();
  D3D12_HEAP_PROPERTIES heap{};
  heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  auto destination = source;
  destination.Flags = D3D12_RESOURCE_FLAG_NONE;
  for (std::size_t index = 0; index < streamline_transport_slots.size();
       ++index) {
    auto& slot = streamline_transport_slots[index];
    if (FAILED(device->CreateCommandAllocator(
            D3D12_COMMAND_LIST_TYPE_DIRECT,
            IID_PPV_ARGS(&slot.allocator))) ||
        FAILED(device->CreateCommandList(
            0, D3D12_COMMAND_LIST_TYPE_DIRECT, slot.allocator.Get(), nullptr,
            IID_PPV_ARGS(&slot.commands))) ||
        FAILED(slot.commands->Close()) ||
        FAILED(device->CreateCommittedResource(
            &heap, D3D12_HEAP_FLAG_SHARED, &destination,
            D3D12_RESOURCE_STATE_COMMON, nullptr,
            IID_PPV_ARGS(&slot.surface))) ||
        FAILED(device->CreateSharedHandle(
            slot.surface.Get(), nullptr, GENERIC_ALL,
            kStreamlineTransportSurfaceNames[index],
            &streamline_transport_surface_handles[index]))) {
      reset_streamline_transport_resources();
      return false;
    }
  }
  if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                                 IID_PPV_ARGS(
                                     &streamline_transport_ready_fence))) ||
      FAILED(device->CreateSharedHandle(
          streamline_transport_ready_fence.Get(), nullptr, GENERIC_ALL,
          kStreamlineTransportReadyFenceName,
          &streamline_transport_ready_handle)) ||
      FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                                 IID_PPV_ARGS(
                                     &streamline_transport_consumed_fence))) ||
      FAILED(device->CreateSharedHandle(
          streamline_transport_consumed_fence.Get(), nullptr, GENERIC_ALL,
          kStreamlineTransportConsumedFenceName,
          &streamline_transport_consumed_handle))) {
    reset_streamline_transport_resources();
    return false;
  }
  return true;
}

bool publish_streamline_transport_metadata(
    std::uint64_t sequence, std::uint64_t native_call,
    std::uint32_t frame_index, const D3D12_RESOURCE_DESC& source) {
  try {
    static darktidevr::core::SharedGeneratedFrameStateWriter writer;
    return writer.publish(sequence, native_call, frame_index,
                          static_cast<std::uint32_t>(source.Width),
                          source.Height, static_cast<std::uint32_t>(source.Format));
  } catch (...) {
    return false;
  }
}

void schedule_streamline_transport_probe(ID3D12CommandQueue* queue,
                                         ID3D12Resource* back_buffer,
                                         std::uint64_t native_call,
                                         std::uint32_t frame_index) {
  std::scoped_lock lock(streamline_transport_mutex);
  if (!queue || !back_buffer || !original_execute_command_lists ||
      streamline_transport_submitted >=
          kStreamlineTransportSubmissionLimit) {
    return;
  }
  const auto sequence = streamline_transport_submitted + 1;
  const auto slot_index = darktidevr::core::generated_frame_slot(sequence);
  auto& slot = streamline_transport_slots[slot_index];
  if (slot.pending || slot.reserved) {
    ++streamline_transport_dropped;
    write_streamline_probe_log(
        "GENERATED_TRANSPORT_DROP\treason=ring_full\tnative_call=%llu"
        "\tframe_index=%u\tdropped=%llu\r\n",
        static_cast<unsigned long long>(native_call), frame_index,
        static_cast<unsigned long long>(streamline_transport_dropped));
    return;
  }
  const auto source = back_buffer->GetDesc();
  if (source.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
      source.Format != DXGI_FORMAT_R8G8B8A8_UNORM || source.Width == 0 ||
      source.Height == 0 || source.SampleDesc.Count != 1) {
    write_streamline_probe_log(
        "GENERATED_TRANSPORT_DROP\treason=unsupported_resource"
        "\tnative_call=%llu\tframe_index=%u\twidth=%llu\theight=%u"
        "\tformat=%u\r\n",
        static_cast<unsigned long long>(native_call), frame_index,
        static_cast<unsigned long long>(source.Width), source.Height,
        static_cast<unsigned>(source.Format));
    return;
  }
  ComPtr<ID3D12Device> device;
  if (FAILED(back_buffer->GetDevice(IID_PPV_ARGS(&device)))) {
    return;
  }
  if (!ensure_streamline_transport_resources(device.Get(), source)) {
    write_streamline_probe_log(
        "GENERATED_TRANSPORT_DROP\treason=resource_creation_failed"
        "\tnative_call=%llu\tframe_index=%u\tslot=%zu\r\n",
        static_cast<unsigned long long>(native_call), frame_index,
        slot_index);
    return;
  }
  if (FAILED(slot.allocator->Reset()) ||
             FAILED(slot.commands->Reset(slot.allocator.Get(), nullptr))) {
    write_streamline_probe_log(
        "GENERATED_TRANSPORT_DROP\treason=command_reset_failed"
        "\tnative_call=%llu\tframe_index=%u\tslot=%zu\r\n",
        static_cast<unsigned long long>(native_call), frame_index,
        slot_index);
    return;
  }
  std::array<D3D12_RESOURCE_BARRIER, 2> barriers{};
  barriers[0].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barriers[0].Transition.pResource = back_buffer;
  barriers[0].Transition.Subresource =
      D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  barriers[0].Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
  barriers[0].Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
  barriers[1].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barriers[1].Transition.pResource = slot.surface.Get();
  barriers[1].Transition.Subresource =
      D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  barriers[1].Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
  barriers[1].Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_DEST;
  slot.commands->ResourceBarrier(static_cast<UINT>(barriers.size()),
                                 barriers.data());
  slot.commands->CopyResource(slot.surface.Get(), back_buffer);
  for (auto& barrier : barriers) {
    std::swap(barrier.Transition.StateBefore,
              barrier.Transition.StateAfter);
  }
  slot.commands->ResourceBarrier(static_cast<UINT>(barriers.size()),
                                 barriers.data());
  if (FAILED(slot.commands->Close())) {
    write_streamline_probe_log(
        "GENERATED_TRANSPORT_DROP\treason=command_close_failed"
        "\tnative_call=%llu\tframe_index=%u\tslot=%zu\r\n",
        static_cast<unsigned long long>(native_call), frame_index,
        slot_index);
    return;
  }
  if (!publish_streamline_transport_metadata(sequence, native_call,
                                              frame_index, source)) {
    write_streamline_probe_log(
        "GENERATED_TRANSPORT_DROP\treason=metadata_publish_failed"
        "\tnative_call=%llu\tframe_index=%u\tslot=%zu\r\n",
        static_cast<unsigned long long>(native_call), frame_index,
        slot_index);
    return;
  }
  ID3D12CommandList* lists[]{slot.commands.Get()};
  original_execute_command_lists(queue, 1, lists);
  const auto transport_ready = streamline_transport_ready_fence;
  slot.pending = true;
  slot.sequence = sequence;
  slot.native_call = native_call;
  slot.frame_index = frame_index;
  if (FAILED(queue->Signal(transport_ready.Get(), sequence))) {
    slot.sequence = UINT64_MAX;
    write_streamline_probe_log(
        "GENERATED_TRANSPORT_DROP\treason=signal_failed"
        "\tnative_call=%llu\tframe_index=%u\tslot=%zu\r\n",
        static_cast<unsigned long long>(native_call), frame_index,
        slot_index);
    return;
  }
  ++streamline_transport_submitted;
  write_streamline_probe_log(
      "GENERATED_TRANSPORT_SUBMIT\tslot=%zu\tnative_call=%llu"
      "\tframe_index=%u\tsequence=%llu\twidth=%llu\theight=%u"
      "\tformat=%u\tsubmitted=%llu\r\n",
      slot_index, static_cast<unsigned long long>(native_call), frame_index,
      static_cast<unsigned long long>(sequence),
      static_cast<unsigned long long>(source.Width), source.Height,
      static_cast<unsigned>(source.Format),
      static_cast<unsigned long long>(streamline_transport_submitted));
}

HRESULT STDMETHODCALLTYPE streamline_native_present_hook(
    IDXGISwapChain* swapchain, UINT interval, UINT flags) {
  if (streamline_copy_probe_requested.load(std::memory_order_acquire)) {
    harvest_streamline_copy_probe();
  }
  if (streamline_transport_probe_requested.load(std::memory_order_acquire)) {
    harvest_streamline_transport_probe();
  }
  const auto call = streamline_native_present_count.fetch_add(
                        1, std::memory_order_relaxed) +
                    1;
  const auto current_thread = GetCurrentThreadId();
  const auto outer_thread =
      streamline_outer_present_thread.load(std::memory_order_acquire);
  const bool asynchronous = outer_thread != 0 && current_thread != outer_thread;
  if (asynchronous) {
    std::uint64_t expected{};
    const auto burst_span =
        streamline_transport_probe_requested.load(std::memory_order_relaxed)
            ? 299ULL
            : 239ULL;
    (void)streamline_native_burst_until_call.compare_exchange_strong(
        expected, call + burst_span, std::memory_order_acq_rel,
        std::memory_order_relaxed);
  }
  const auto burst_until =
      streamline_native_burst_until_call.load(std::memory_order_acquire);
  const auto submission_present = streamline_stereo_submission_present.load(std::memory_order_acquire);
  const auto current_outer = present_count.load(std::memory_order_relaxed);
  const bool submission_sample = submission_present != 0 && current_outer >= submission_present &&
      current_outer - submission_present < 8;
  const bool sample = submission_sample || call <= 100 || call % 120 == 0 ||
                      (burst_until != 0 && call <= burst_until);
  const auto active_outer_frame =
      streamline_outer_present_active_frame.load(std::memory_order_acquire);
  const auto latest_frame_token_call =
      streamline_latest_frame_token_call.load(std::memory_order_acquire);
  const auto latest_frame_token =
      streamline_latest_frame_token.load(std::memory_order_relaxed);
  const auto latest_frame_index =
      streamline_latest_frame_index.load(std::memory_order_relaxed);
  LARGE_INTEGER begin{};
  UINT last_present_before{};
  HRESULT last_present_before_result{E_FAIL};
  if (sample) {
    QueryPerformanceCounter(&begin);
    last_present_before_result =
        swapchain->GetLastPresentCount(&last_present_before);
    ComPtr<IDXGISwapChain3> swapchain3;
    ComPtr<ID3D12Resource> back_buffer;
    UINT back_buffer_index{UINT_MAX};
    D3D12_RESOURCE_DESC back_buffer_description{};
    if (SUCCEEDED(swapchain->QueryInterface(IID_PPV_ARGS(&swapchain3)))) {
      back_buffer_index = swapchain3->GetCurrentBackBufferIndex();
      if (SUCCEEDED(swapchain3->GetBuffer(
              back_buffer_index, IID_PPV_ARGS(&back_buffer)))) {
        back_buffer_description = back_buffer->GetDesc();
      }
    }
    const auto last_execute_qpc =
        streamline_last_execute_qpc.load(std::memory_order_acquire);
    LARGE_INTEGER qpc_frequency{};
    QueryPerformanceFrequency(&qpc_frequency);
    const auto execute_delta_microseconds =
        last_execute_qpc > 0 && begin.QuadPart >= last_execute_qpc &&
                qpc_frequency.QuadPart > 0
            ? (begin.QuadPart - last_execute_qpc) * 1000000LL /
                  qpc_frequency.QuadPart
            : -1;
    ComPtr<ID3D12CommandQueue> observed_present_queue;
    if (asynchronous &&
        swapchain_render_extent_enabled.load(std::memory_order_acquire) &&
        back_buffer_description.Width ==
            swapchain_present_width.load(std::memory_order_relaxed) &&
        back_buffer_description.Height ==
            swapchain_render_height.load(std::memory_order_relaxed) &&
        back_buffer_description.Format == DXGI_FORMAT_R8G8B8A8_UNORM) {
      std::scoped_lock lock(state_mutex);
      observed_present_queue = swapchain_present_queue;
    }
    std::uint64_t generator_execute_call{};
    std::int64_t generator_execute_delta_microseconds{-1};
    ID3D12CommandQueue* generator_queue{};
    const bool generated_candidate =
        asynchronous && is_streamline_generated_present_candidate(
                            current_thread, begin.QuadPart,
                            qpc_frequency.QuadPart, generator_queue,
                            generator_execute_call,
                            generator_execute_delta_microseconds);
    if (streamline_copy_probe_requested.load(std::memory_order_acquire) &&
        generated_candidate) {
      schedule_streamline_copy_probe(
          observed_present_queue.Get(), back_buffer.Get(), call,
          present_count.load(std::memory_order_relaxed));
    }
    if (streamline_transport_probe_requested.load(std::memory_order_acquire) &&
        generated_candidate) {
      schedule_streamline_transport_probe(
          observed_present_queue.Get(), back_buffer.Get(), call,
          latest_frame_index);
    }
    if (submission_sample) {
      write_streamline_probe_log(
          "STEREO_NATIVE_TARGET\tsubmission_present=%llu\tnative_call=%llu"
          "\touter_frame=%llu\tactive_outer_frame=%llu\tthread=%lu"
          "\tbackbuffer=%p\twidth=%llu\theight=%u\tformat=%u"
          "\tgenerated_candidate=%u\r\n",
          static_cast<unsigned long long>(submission_present),
          static_cast<unsigned long long>(call), static_cast<unsigned long long>(current_outer),
          static_cast<unsigned long long>(active_outer_frame), GetCurrentThreadId(),
          back_buffer.Get(), static_cast<unsigned long long>(back_buffer_description.Width),
          back_buffer_description.Height, static_cast<unsigned>(back_buffer_description.Format),
          generated_candidate ? 1U : 0U);
    }
    write_streamline_probe_log(
        "NATIVE_PRESENT_BEGIN\tcall=%llu\touter_frame=%llu\tthread=%lu"
        "\tclass=%s\tactive_outer_frame=%llu"
        "\tframe_token_call=%llu\tframe_token=%p\tframe_index=%u"
        "\tgenerated_candidate=%u\tgenerator_execute_call=%llu"
        "\tgenerator_queue=%p\tgenerator_execute_delta_us=%lld"
        "\tqpc=%lld\tswapchain=%p\tinterval=%u\tflags=%u"
        "\tlast_present_result=%ld\tlast_present=%u"
        "\tback_buffer_index=%u\tback_buffer=%p\twidth=%llu"
        "\theight=%u\tformat=%u\tlast_execute_call=%llu"
        "\tlast_execute_outer_frame=%llu\tlast_execute_thread=%lu"
        "\tlast_execute_queue=%p\tlast_execute_queue_type=%u"
        "\tlast_execute_list_count=%u\tlast_execute_delta_us=%lld\r\n",
        static_cast<unsigned long long>(call),
        static_cast<unsigned long long>(
            present_count.load(std::memory_order_relaxed)),
        current_thread, asynchronous ? "asynchronous" : "outer_thread",
        static_cast<unsigned long long>(active_outer_frame),
        static_cast<unsigned long long>(latest_frame_token_call),
        latest_frame_token, latest_frame_index,
        generated_candidate ? 1U : 0U,
        static_cast<unsigned long long>(generator_execute_call),
        generator_queue, generator_execute_delta_microseconds,
        begin.QuadPart, swapchain, interval, flags,
        last_present_before_result, last_present_before, back_buffer_index,
        back_buffer.Get(),
        static_cast<unsigned long long>(back_buffer_description.Width),
        back_buffer_description.Height,
        static_cast<unsigned>(back_buffer_description.Format),
        static_cast<unsigned long long>(
            streamline_execute_count.load(std::memory_order_relaxed)),
        static_cast<unsigned long long>(
            streamline_last_execute_outer_frame.load(
                std::memory_order_relaxed)),
        streamline_last_execute_thread.load(std::memory_order_relaxed),
        streamline_last_execute_queue.load(std::memory_order_relaxed),
        streamline_last_execute_queue_type.load(std::memory_order_relaxed),
        streamline_last_execute_list_count.load(std::memory_order_relaxed),
        execute_delta_microseconds);
    const auto execute_total =
        streamline_execute_count.load(std::memory_order_acquire);
    for (std::uint64_t offset = 0;
         offset < kStreamlineExecuteHistory && execute_total > offset;
         ++offset) {
      const auto execute_call = execute_total - offset;
      auto& snapshot = streamline_execute_history[
          execute_call % kStreamlineExecuteHistory];
      if (snapshot.call.load(std::memory_order_acquire) != execute_call) {
        continue;
      }
      const auto execute_qpc = snapshot.qpc.load(std::memory_order_relaxed);
      if (execute_qpc <= 0 || execute_qpc > begin.QuadPart) {
        continue;
      }
      const auto delta_microseconds =
          qpc_frequency.QuadPart > 0
              ? (begin.QuadPart - execute_qpc) * 1000000LL /
                    qpc_frequency.QuadPart
              : -1;
      if (delta_microseconds < 0 || delta_microseconds > 5000) {
        continue;
      }
      write_streamline_probe_log(
          "EXECUTE_PRECURSOR\tnative_call=%llu\touter_frame=%llu"
          "\toffset=%llu\texecute_call=%llu\texecute_outer_frame=%llu"
          "\tthread=%lu\tqueue=%p\tqueue_type=%u\tlist_count=%u"
          "\tpresent_transition=%u\tdelta_us=%lld\r\n",
          static_cast<unsigned long long>(call),
          static_cast<unsigned long long>(
              present_count.load(std::memory_order_relaxed)),
          static_cast<unsigned long long>(offset),
          static_cast<unsigned long long>(execute_call),
          static_cast<unsigned long long>(
              snapshot.outer_frame.load(std::memory_order_relaxed)),
          snapshot.thread.load(std::memory_order_relaxed),
          snapshot.queue.load(std::memory_order_relaxed),
          snapshot.queue_type.load(std::memory_order_relaxed),
          snapshot.list_count.load(std::memory_order_relaxed),
          snapshot.present_transition.load(std::memory_order_acquire) ? 1U
                                                                     : 0U,
          delta_microseconds);
    }
  }
  if (streamline_persistent_requested.load()) {
    ComPtr<IDXGISwapChain3> mirror_swapchain;
    if (SUCCEEDED(swapchain->QueryInterface(IID_PPV_ARGS(&mirror_swapchain)))) {
      DXGI_SWAP_CHAIN_DESC1 description{};
      if (SUCCEEDED(mirror_swapchain->GetDesc1(&description))) {
        const bool packed_world=streamline_packed_mirror_active.load() && current_presentation_mode.load()==1 &&
            description.Width==swapchain_present_width.load() &&
            description.Width==camera_input_width.load()*2 &&
            description.Height==camera_input_height.load();
        const UINT source_width=packed_world ? description.Width/2 : description.Width;
        UINT previous_width{},previous_height{};
        if (SUCCEEDED(mirror_swapchain->GetSourceSize(&previous_width,&previous_height)) &&
            (previous_width!=source_width || previous_height!=description.Height)) {
          // DXGI selects the desktop region without a GPU write to NVIDIA's
          // private swapchain or changing the packed textures used by FG/XR.
          const auto crop_result=mirror_swapchain->SetSourceSize(source_width,description.Height);
          write_streamline_probe_log("STEREO_DESKTOP_CROP\twidth=%u\theight=%u\tresult=%ld\r\n",
              source_width,description.Height,crop_result);
        }
      }
    }
  }
  const auto result =
      original_streamline_native_present(swapchain, interval, flags);
  if (sample) {
    LARGE_INTEGER end{};
    QueryPerformanceCounter(&end);
    UINT last_present_after{};
    const auto last_present_after_result =
        swapchain->GetLastPresentCount(&last_present_after);
    write_streamline_probe_log(
        "NATIVE_PRESENT_END\tcall=%llu\touter_frame=%llu\tthread=%lu"
        "\tclass=%s\tactive_outer_frame=%llu"
        "\tqpc=%lld\tresult=%ld\tswapchain=%p"
        "\tlast_present_result=%ld\tlast_present=%u\r\n",
        static_cast<unsigned long long>(call),
        static_cast<unsigned long long>(
            present_count.load(std::memory_order_relaxed)),
        current_thread, asynchronous ? "asynchronous" : "outer_thread",
        static_cast<unsigned long long>(active_outer_frame), end.QuadPart,
        result, swapchain,
        last_present_after_result, last_present_after);
  }
  return result;
}

HRESULT STDMETHODCALLTYPE present_hook(IDXGISwapChain* swapchain,
                                       UINT interval, UINT flags) {
  darktidevr::producer::poll_ngx_queue_completion();
  // Legacy resource tags are global. During this explicit one-shot test, keep
  // the game's next tag calls outside our stage/Present/null-tag transaction.
  // Recursive only for same-thread API re-entry; ordinary runs do not hold it.
  std::unique_lock<std::recursive_mutex> tagging_lock(streamline_tagging_api_mutex,
                                                     std::defer_lock);
  if (streamline_stereo_submit_probe_requested.load(std::memory_order_acquire))
    tagging_lock.lock();
  streamline_outer_present_thread.store(GetCurrentThreadId(),
                                        std::memory_order_release);
  if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed)) {
    std::scoped_lock lock(trace_mutex);
    frame_eye0_table4_draws.clear();
    candidate_frame_eye0_table4 = {};
    candidate_frame_eye0_instance_count = 0;
  }
  const auto present = present_count.fetch_add(1, std::memory_order_relaxed) + 1;
  const auto native_burst_until =
      streamline_native_burst_until_call.load(std::memory_order_acquire);
  const bool sample_streamline =
      streamline_probe_log != INVALID_HANDLE_VALUE &&
      (present <= 5 || present % 120 == 0 ||
       (native_burst_until != 0 &&
        streamline_native_present_count.load(std::memory_order_relaxed) <=
            native_burst_until));
  LARGE_INTEGER streamline_begin{};
  if (sample_streamline) {
    QueryPerformanceCounter(&streamline_begin);
    ComPtr<IUnknown> identity;
    (void)swapchain->QueryInterface(IID_PPV_ARGS(&identity));
    ComPtr<ID3D12Fence> capture_ready_fence;
    std::uint64_t capture_ready_value{};
    {
      std::scoped_lock lock(state_mutex);
      capture_ready_fence = ready_fence;
      capture_ready_value = ready_value;
    }
    const auto completed = capture_ready_fence
                               ? capture_ready_fence->GetCompletedValue()
                               : 0;
    write_streamline_probe_log(
        "PRESENT_BEGIN\tframe=%llu\tthread=%lu\tqpc=%lld"
        "\tswapchain=%p\tidentity=%p\tinterval=%u\tflags=%u"
        "\tready_fence=%p\tready_value=%llu\tready_completed=%llu"
        "\tnative_present_count=%llu\r\n",
        present, GetCurrentThreadId(), streamline_begin.QuadPart, swapchain,
        identity.Get(), interval, flags, capture_ready_fence.Get(),
        static_cast<unsigned long long>(capture_ready_value),
        static_cast<unsigned long long>(completed),
        static_cast<unsigned long long>(
            streamline_native_present_count.load(std::memory_order_relaxed)));
    log_streamline_modules(false);
  }
  // Focused tracing is an operator-triggered diagnostic, not frame-critical
  // state. Poll promptly on startup and then at human-scale latency instead of
  // issuing GetTempPath plus three filesystem probes on every Present.
  if (present == 1 || present % 30 == 0) {
    poll_focused_trace_request();
  }
  if (marker_log != INVALID_HANDLE_VALUE) {
    const auto sequence =
        marker_sequence.fetch_add(1, std::memory_order_relaxed);
    write_marker_log("%llu\t%lu\tSC=%p\tPRESENT\tframe=%llu\r\n", sequence,
                     GetCurrentThreadId(), swapchain, present);
  }
  if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
    write_focused_log("phase=%d\tframe=%llu\tSC=%p\tPRESENT\r\n",
                      focused_trace_phase.load(std::memory_order_relaxed),
                      present, swapchain);
  }
  const bool refresh_swapchain_metadata =
      game_swapchain_identity.load(std::memory_order_acquire) != swapchain ||
      !game_swapchain_metadata_ready.load(std::memory_order_acquire);
  ComPtr<IDXGISwapChain3> candidate;
  if (refresh_swapchain_metadata) {
    ComPtr<ID3D12Device> device;
    if (SUCCEEDED(swapchain->GetDevice(IID_PPV_ARGS(&device))) &&
        SUCCEEDED(swapchain->QueryInterface(IID_PPV_ARGS(&candidate)))) {
      {
        std::scoped_lock lock(state_mutex);
        game_swapchain = candidate;
      }
      DXGI_SWAP_CHAIN_DESC description{};
      if (SUCCEEDED(candidate->GetDesc(&description))) {
        game_output_window.store(description.OutputWindow,
                                 std::memory_order_relaxed);
        ensure_virtual_window_proc(description.OutputWindow);
        std::unordered_set<ID3D12Resource*> buffers;
        D3D12_RESOURCE_DESC output_description{};
        for (UINT index = 0; index < description.BufferCount; ++index) {
          ComPtr<ID3D12Resource> buffer;
          if (SUCCEEDED(candidate->GetBuffer(index, IID_PPV_ARGS(&buffer)))) {
            buffers.insert(buffer.Get());
            if (index == 0) {
              output_description = buffer->GetDesc();
            }
          }
        }
        const bool complete_buffer_set =
            description.BufferCount > 0 &&
            buffers.size() == static_cast<std::size_t>(description.BufferCount);
        if (!complete_buffer_set) {
          // Do not bless a partial enumeration. Leaving metadata invalid makes
          // the next Present retry without exposing an incomplete state map.
          candidate.Reset();
        } else {
        {
          std::scoped_lock lock(boundary_capture_mutex);
          swapchain_back_buffers = std::move(buffers);
          swapchain_back_buffer_states.clear();
          for (auto* buffer : swapchain_back_buffers) {
            swapchain_back_buffer_states[buffer] =
                D3D12_RESOURCE_STATE_PRESENT;
          }
          camera_output_width = output_description.Width;
          camera_output_height = output_description.Height;
          camera_output_format = output_description.Format;
          if (present <= 5 || present % 120 == 0) {
            write_boundary_census_log(
                "frame=%llu\tOUTPUT\twidth=%llu\theight=%u\tformat=%u"
                "\tbuffers=%u\r\n",
                present, camera_output_width, camera_output_height,
                static_cast<unsigned>(camera_output_format),
                description.BufferCount);
          }
        }
        game_swapchain_identity.store(swapchain, std::memory_order_release);
        game_swapchain_metadata_ready.store(true, std::memory_order_release);
        }
      }
    }
  }
  const auto diagnostic_burst_until =
      resize_diagnostic_burst_until_present.load(std::memory_order_relaxed);
  if (present % 120 == 0 || present <= diagnostic_burst_until) {
    ComPtr<IDXGISwapChain3> diagnostic_swapchain;
    DXGI_SWAP_CHAIN_DESC diagnostic_description{};
    ComPtr<ID3D12Resource> diagnostic_buffer;
    RECT diagnostic_client{};
    if (SUCCEEDED(swapchain->QueryInterface(
            IID_PPV_ARGS(&diagnostic_swapchain))) &&
        SUCCEEDED(diagnostic_swapchain->GetDesc(&diagnostic_description)) &&
        SUCCEEDED(diagnostic_swapchain->GetBuffer(
            diagnostic_swapchain->GetCurrentBackBufferIndex(),
            IID_PPV_ARGS(&diagnostic_buffer)))) {
      const auto buffer_description = diagnostic_buffer->GetDesc();
      if (diagnostic_description.OutputWindow) {
        if (original_get_client_rect) {
          original_get_client_rect(diagnostic_description.OutputWindow,
                                   &diagnostic_client);
        } else {
          GetClientRect(diagnostic_description.OutputWindow,
                        &diagnostic_client);
        }
      }
      write_resize_diagnostic_log(
          "frame=%llu\tPRESENT_STATE\tgeneration=%llu\tswapchain=%p"
          "\tindex=%u\tbuffer=%p\twidth=%llu\theight=%u\tformat=%u"
          "\tclient=%ldx%ld\tmirror_ready=%u\r\n",
          present,
          static_cast<unsigned long long>(
              resize_diagnostic_generation.load(std::memory_order_relaxed)),
          swapchain, diagnostic_swapchain->GetCurrentBackBufferIndex(),
          diagnostic_buffer.Get(), buffer_description.Width,
          buffer_description.Height,
          static_cast<unsigned>(buffer_description.Format),
          diagnostic_client.right - diagnostic_client.left,
          diagnostic_client.bottom - diagnostic_client.top,
          desktop_mirror_ready.load(std::memory_order_relaxed) ? 1U : 0U);
    }
  }
  HWND client_lock_window{};
  const bool resize_pending = swapchain_resize_nudge_pending.exchange(
      false, std::memory_order_acq_rel);
  const bool resize_restore_pending =
      swapchain_resize_nudge_phase.load(std::memory_order_relaxed) == 1;
  if (resize_pending ||
      resize_restore_pending ||
      (swapchain_client_extent_locked.load(std::memory_order_acquire) &&
       present % 120 == 0)) {
    DXGI_SWAP_CHAIN_DESC description{};
    if (SUCCEEDED(swapchain->GetDesc(&description)) &&
        description.OutputWindow) {
      client_lock_window = description.OutputWindow;
    }
  }
  ComPtr<ID3D12CommandQueue> queue;
  ComPtr<ID3D12CommandQueue> present_queue;
  {
    std::scoped_lock lock(state_mutex);
    queue = game_queue;
    present_queue = swapchain_present_queue ? swapchain_present_queue
                                             : game_queue;
    if (!candidate &&
        game_swapchain_identity.load(std::memory_order_relaxed) == swapchain) {
      candidate = game_swapchain;
    }
  }
  const auto menu_draw_frame =
      stock_menu_draw_frame.load(std::memory_order_relaxed);
  const auto presentation_mode = static_cast<
      darktidevr::core::SharedPresentationMode>(
      current_presentation_mode.load(std::memory_order_relaxed));
  const auto interactive_menu_active =
      presentation_mode ==
          darktidevr::core::SharedPresentationMode::flat_menu ||
      presentation_mode ==
          darktidevr::core::SharedPresentationMode::world_anchored_menu;
  // A stock menu frame is recorded across several command lists.  Publish the
  // transparent surface only once the game's direct queue has received every
  // list for that frame; signaling from ExecuteCommandLists exposed whichever
  // partial list happened to finish first.
  const auto direct_menu_frame =
      direct_menu_render_frame.load(std::memory_order_relaxed);
  if constexpr (kStockMenuDirectRenderEnabled) {
    if (interactive_menu_active && queue &&
        direct_menu_frame != (std::numeric_limits<std::uint64_t>::max)() &&
        direct_menu_frame + 1 == present) {
      ComPtr<ID3D12Fence> menu_publish_fence;
      std::uint64_t menu_publish_value{};
      {
        std::scoped_lock lock(state_mutex);
        const auto consumed =
            menu_consumed_fence ? menu_consumed_fence->GetCompletedValue()
                                : UINT64_MAX;
        if (menu_ready_fence &&
            darktidevr::core::shared_mailbox_writable(menu_ready_value,
                                                      consumed)) {
          menu_publish_fence = menu_ready_fence;
          menu_publish_value = menu_ready_value + 1;
        }
      }
      if (menu_publish_fence && menu_publish_value != 0 &&
          SUCCEEDED(queue->Signal(menu_publish_fence.Get(),
                                  menu_publish_value))) {
        std::scoped_lock lock(state_mutex);
        menu_ready_value = menu_publish_value;
        if (menu_publish_value <= 5 || menu_publish_value % 120 == 0) {
          write_menu_resource_log(
              "MENU_DIRECT_RENDER\tframe=%llu\tready=%llu\r\n", present,
              static_cast<unsigned long long>(menu_publish_value));
        }
      }
    }
  }
  if constexpr (kStockMenuSwapchainCaptureEnabled) {
    if (interactive_menu_active && candidate && queue &&
        menu_draw_frame != (std::numeric_limits<std::uint64_t>::max)() &&
        menu_draw_frame + 1 == present) {
    ComPtr<ID3D12Resource> menu_back_buffer;
    const auto buffer_index = candidate->GetCurrentBackBufferIndex();
    if (SUCCEEDED(candidate->GetBuffer(
            buffer_index, IID_PPV_ARGS(&menu_back_buffer)))) {
      const auto menu_result = capture_menu_from_resource(
          queue.Get(), menu_back_buffer.Get(), D3D12_RESOURCE_STATE_PRESENT,
          menu_back_buffer->GetDesc().Width, [&] {
            const auto source = menu_back_buffer->GetDesc();
            RECT client{};
            const auto window = game_output_window.load(
                std::memory_order_relaxed);
            if (window && GetClientRect(window, &client) &&
                client.right > client.left && client.bottom > client.top) {
              const auto client_width =
                  static_cast<std::uint64_t>(client.right - client.left);
              const auto client_height =
                  static_cast<std::uint64_t>(client.bottom - client.top);
              const auto scaled_height =
                  (source.Width * client_height + client_width / 2U) /
                  client_width;
              return static_cast<UINT>((std::min)(
                  static_cast<std::uint64_t>(source.Height), scaled_height));
            }
            return source.Height;
          }());
      write_menu_resource_log(
          "MENU_SWAPCHAIN_CAPTURE\tframe=%llu\tresource=%p\tresult=%d"
          "\tready=%llu\r\n",
          present, menu_back_buffer.Get(), menu_result,
          static_cast<unsigned long long>(menu_ready_value));
    }
  }
  }
  if (present_capture_enabled.load(std::memory_order_relaxed) && candidate &&
      queue) {
    alternating_last_capture_result.store(
        capture_present_halves(candidate.Get(), queue.Get()),
        std::memory_order_relaxed);
  }
  bool packed_submission = false;
  if (candidate && present_queue && streamline_continuous_requested.load(std::memory_order_acquire)) {
    std::scoped_lock lock(streamline_input_snapshot_mutex);
    const auto tagging_modes = streamline_tagging_api_modes.load(std::memory_order_relaxed);
    if (tagging_modes == 1 || tagging_modes == 2) {
      const darktidevr::producer::StreamlineSubmissionApi api{
          original_sl_set_constants, original_sl_set_tag_for_frame, original_sl_set_tag};
      if (streamline_continuous.initialized() && !streamline_persistent_requested.load() && !game_process_foreground())
        streamline_continuous.cancel("foreground_lost");
      if (presentation_mode != darktidevr::core::SharedPresentationMode::stereo_world)
        streamline_continuous.pause(present_queue.Get(), original_execute_command_lists, "non_world_presentation");
      else streamline_continuous.before_present(candidate.Get(), present_queue.Get(), present,
          streamline_present_bindings(), api,
          tagging_modes == 1 ? darktidevr::producer::StreamlineSubmission::Tagging::legacy
                             : darktidevr::producer::StreamlineSubmission::Tagging::frame_based,
          original_execute_command_lists,current_gameplay_generation.load());
      if (streamline_continuous.staged()) {
        packed_submission = streamline_persistent_requested.load();
        darktidevr::producer::arm_ngx_output_probe(1, present);
        darktidevr::producer::generated_stereo_context(streamline_continuous.previous_pose(),
            streamline_continuous.pose(),current_gameplay_generation.load(),
            streamline_continuous.original_ready(),
            streamline_continuous.inputs());
      }
    }
  }
  streamline_packed_mirror_active.store(packed_submission);
  // Packed rendering gives the engine a private backbuffer. Flat menus and
  // loading screens must reach DXGI from that current buffer too; otherwise
  // skipping the eye mirror leaves the last world image on the desktop.
  const bool engine_flat_mirror = darktidevr::producer::engine_flat_mirror_required(
      streamline_stereo_swapchain_probe_requested.load(std::memory_order_acquire),
      presentation_mode);
  if ((engine_flat_mirror || (presentation_mode !=
          darktidevr::core::SharedPresentationMode::flat_loading_or_cinematic &&
      !darktidevr::core::flat_interactive_active(presentation_mode))) &&
      candidate && present_queue &&
      !packed_submission &&
      (engine_flat_mirror || desktop_mirror_ready.load(std::memory_order_acquire))) {
    const auto mirror_result =
        present_desktop_eye_mirror(candidate.Get(), present_queue.Get(), engine_flat_mirror);
    if (mirror_result != 0) {
      const auto error = desktop_mirror_error_count.fetch_add(
                             1, std::memory_order_relaxed) +
                         1;
      if (error <= 20 || error % 120 == 0) {
        write_menu_resource_log(
            "DESKTOP_EYE_MIRROR\tframe=%llu\tresult=%d\terror=%llu\r\n",
            present, mirror_result,
            static_cast<unsigned long long>(error));
      }
    }
  }
  if (candidate && !streamline_continuous_requested.load(std::memory_order_acquire) &&
      streamline_target_token_probe_requested.load(std::memory_order_acquire) &&
      streamline_stereo_swapchain_probe_requested.load(
          std::memory_order_acquire)) {
    std::scoped_lock lock(streamline_input_snapshot_mutex);
    auto& snapshot = streamline_input_snapshot_state;
    if (snapshot.submission_prepared && !snapshot.submission_attempted && snapshot.submission_context_samples < 4 &&
        (snapshot.submission_context_samples == 0 || present % 120 == 0)) {
      ++snapshot.submission_context_samples;
      for (std::size_t eye = 0; eye < 2; ++eye) {
        const auto& current = streamline_constants_observations[eye];
        const auto viewport = snapshot.constants[eye].viewport;
        StreamlineOptionsObservation options{};
        for (const auto& observation : streamline_options_observations) {
          if (observation.valid && observation.viewport == viewport) {
            options = observation;
            break;
          }
        }
        write_streamline_probe_log(
            "STEREO_SUBMISSION_CONTEXT\tpresent_frame=%llu\teye=%zu"
            "\tviewport=%u\tcurrent_viewport=%u\tconstants_valid=%u"
            "\tconstants_present=%llu\tframe_index=%u\ttoken=%p"
            "\ttoken_call=%llu\tpose=%llu\toptions_seen=%u\tmode=%u"
            "\toptions_present=%llu\ttags_staged=0\r\n",
            static_cast<unsigned long long>(present), eye, viewport,
            current.viewport, current.valid ? 1U : 0U,
            static_cast<unsigned long long>(current.present_frame),
            current.frame_index, current.frame_token,
            static_cast<unsigned long long>(current.frame_token_call),
            static_cast<unsigned long long>(current.pose_sequence),
            options.valid ? 1U : 0U, options.mode,
            static_cast<unsigned long long>(options.present_frame));
      }
    }
    if (snapshot.present_stage_pending && snapshot.fence) {
      const auto completed = snapshot.fence->GetCompletedValue();
      if (completed == UINT64_MAX) {
        snapshot.failed = true;
        snapshot.present_stage_pending = false;
        write_streamline_probe_log(
            "STEREO_PRESENT_STAGE\tphase=failed"
            "\treason=poisoned_fence\r\n");
      } else if (completed >= snapshot.submission_stage_fence) {
        snapshot.present_stage_pending = false;
        snapshot.present_stage_complete = true;
        write_streamline_probe_log(
            "STEREO_PRESENT_STAGE\tphase=complete"
            "\tfence_value=%llu\tcopy_staged=1\ttags_staged=%u"
            "\tadditional_present_submitted=0"
            "\tmetadata_published=0\tready_signaled=0\r\n",
            static_cast<unsigned long long>(snapshot.submission_stage_fence),
            snapshot.submission_presented ? 1U : 0U);
      }
    }
    if (!snapshot.failed && snapshot.stereo_backbuffer_complete &&
        snapshot.target_token_allocated && !snapshot.present_target_observed) {
      ComPtr<ID3D12Resource> present_backbuffer;
      const auto backbuffer_index = candidate->GetCurrentBackBufferIndex();
      if (SUCCEEDED(candidate->GetBuffer(
              backbuffer_index, IID_PPV_ARGS(&present_backbuffer)))) {
        const auto stereo_description = snapshot.stereo_backbuffer->GetDesc();
        const auto present_description = present_backbuffer->GetDesc();
        darktidevr::core::StreamlineStereoPresentTarget target{};
        target.stereo_backbuffer = reinterpret_cast<std::uintptr_t>(
            snapshot.stereo_backbuffer.Get());
        target.present_backbuffer = reinterpret_cast<std::uintptr_t>(
            present_backbuffer.Get());
        target.stereo_width = stereo_description.Width;
        target.present_width = present_description.Width;
        target.stereo_height = stereo_description.Height;
        target.present_height = present_description.Height;
        target.stereo_format = static_cast<std::uint32_t>(
            stereo_description.Format);
        target.present_format = static_cast<std::uint32_t>(
            present_description.Format);
        target.stereo_state = D3D12_RESOURCE_STATE_PRESENT;
        target.present_state = D3D12_RESOURCE_STATE_PRESENT;
        const auto compatible =
            darktidevr::core::streamline_stereo_present_target_matches(target);
        const bool submit_requested = streamline_stereo_submit_probe_requested.load(
            std::memory_order_acquire);
        const auto bindings = streamline_present_bindings();
        const auto tagging_modes = streamline_tagging_api_modes.load(std::memory_order_relaxed);
        bool binding_valid = darktidevr::core::streamline_present_binding_matches(
            present, {snapshot.constants[0].viewport, snapshot.constants[1].viewport},
            bindings);
        if (submit_requested) {
          binding_valid = binding_valid && (tagging_modes == 1 || tagging_modes == 2);
          if (!snapshot.submission_refresh_armed) {
            snapshot.submission_refresh_armed = true;
            streamline_submission_trace_start.store(present, std::memory_order_release);
            write_streamline_probe_log("STEREO_REFRESH\tphase=armed\r\n");
          }
          binding_valid = binding_valid && snapshot.submission_refresh_mask == 3;
          for (std::size_t eye = 0; eye < 2; ++eye) {
            const auto& refreshed = snapshot.submission_refresh_constants[eye];
            binding_valid = binding_valid && refreshed.valid &&
                refreshed.present_frame == bindings[eye].constants_present &&
                refreshed.frame_index == bindings[eye].frame_index &&
                refreshed.frame_token_call == bindings[eye].token_call &&
                reinterpret_cast<std::uintptr_t>(refreshed.frame_token) == bindings[eye].token &&
                refreshed.pose_sequence == bindings[eye].pose;
          }
          if (snapshot.submission_refresh_mask == 3 && !binding_valid) {
            snapshot.failed = true;
            write_streamline_probe_log("STEREO_REFRESH\tphase=failed\treason=stale_present_binding\r\n");
          }
        }
        snapshot.present_target_observed = !submit_requested || binding_valid;
        write_streamline_probe_log(
            "STEREO_PRESENT_TARGET\tphase=observed\tpresent_frame=%llu"
            "\tswapchain=%p\tbackbuffer_index=%u"
            "\tstereo_backbuffer=%p\tpresent_backbuffer=%p"
            "\tstereo_extent=%llux%u\tpresent_extent=%llux%u"
            "\tstereo_format=%u\tpresent_format=%u"
            "\tstereo_state=%u\tpresent_state=%u\tcompatible=%u"
            "\tcopy_staged=0\ttags_staged=0"
            "\tgeneration_present_submitted=0"
            "\tmetadata_published=0\tready_signaled=0\r\n",
            static_cast<unsigned long long>(present), swapchain,
            backbuffer_index, snapshot.stereo_backbuffer.Get(),
            present_backbuffer.Get(),
            static_cast<unsigned long long>(stereo_description.Width),
            stereo_description.Height,
            static_cast<unsigned long long>(present_description.Width),
            present_description.Height,
            static_cast<unsigned>(stereo_description.Format),
            static_cast<unsigned>(present_description.Format),
            static_cast<unsigned>(D3D12_RESOURCE_STATE_PRESENT),
            static_cast<unsigned>(D3D12_RESOURCE_STATE_PRESENT),
            compatible ? 1U : 0U);
        if (compatible && (!submit_requested || binding_valid) &&
            streamline_stereo_stage_probe_requested.load(
                std::memory_order_acquire) &&
            present_queue && !snapshot.present_stage_pending &&
            !snapshot.present_stage_complete) {
          ComPtr<ID3D12Device> device;
          if (FAILED(present_backbuffer->GetDevice(IID_PPV_ARGS(&device))) ||
              FAILED(device->CreateCommandAllocator(
                  D3D12_COMMAND_LIST_TYPE_DIRECT,
                  IID_PPV_ARGS(&snapshot.present_stage_allocator))) ||
              FAILED(device->CreateCommandList(
                  0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                  snapshot.present_stage_allocator.Get(), nullptr,
                  IID_PPV_ARGS(&snapshot.present_stage_commands)))) {
            snapshot.failed = true;
            write_streamline_probe_log(
                "STEREO_PRESENT_STAGE\tphase=failed"
                "\treason=create_commands\r\n");
          } else {
            if (submit_requested) {
              for (std::size_t eye = 0; eye < 2; ++eye) {
                const auto wait_result = present_queue->Wait(
                    snapshot.submission_refresh_fences[eye].Get(), 1);
                if (FAILED(wait_result)) {
                  snapshot.failed = true;
                  write_streamline_probe_log("STEREO_REFRESH\tphase=failed\treason=queue_wait\r\n");
                }
              }
              // Refresh the packed color from the same pair as depth/motion.
              auto* commands = snapshot.present_stage_commands.Get();
              D3D12_RESOURCE_BARRIER packed{};
              packed.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
              packed.Transition = {snapshot.stereo_backbuffer.Get(),
                  D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES, D3D12_RESOURCE_STATE_PRESENT,
                  D3D12_RESOURCE_STATE_COPY_DEST};
              commands->ResourceBarrier(1, &packed);
              for (std::size_t eye = 0; eye < 2; ++eye) {
                auto* source = snapshot.snapshots[eye][2].Get();
                D3D12_RESOURCE_BARRIER color{};
                color.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
                color.Transition = {source, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                    D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_COPY_SOURCE};
                commands->ResourceBarrier(1, &color);
                D3D12_TEXTURE_COPY_LOCATION destination{};
                destination.pResource = snapshot.stereo_backbuffer.Get();
                destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
                D3D12_TEXTURE_COPY_LOCATION from{};
                from.pResource = source;
                from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
                commands->CopyTextureRegion(&destination,
                    static_cast<UINT>(eye * source->GetDesc().Width), 0, 0, &from, nullptr);
                std::swap(color.Transition.StateBefore, color.Transition.StateAfter);
                commands->ResourceBarrier(1, &color);
              }
              std::swap(packed.Transition.StateBefore, packed.Transition.StateAfter);
              commands->ResourceBarrier(1, &packed);
            }
            std::array<D3D12_RESOURCE_BARRIER, 2> barriers{};
            barriers[0].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
            barriers[0].Transition.pResource =
                snapshot.stereo_backbuffer.Get();
            barriers[0].Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
            barriers[0].Transition.StateAfter =
                D3D12_RESOURCE_STATE_COPY_SOURCE;
            barriers[0].Transition.Subresource =
                D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
            barriers[1].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
            barriers[1].Transition.pResource = present_backbuffer.Get();
            barriers[1].Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
            barriers[1].Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_DEST;
            barriers[1].Transition.Subresource =
                D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
            snapshot.present_stage_commands->ResourceBarrier(
                static_cast<UINT>(barriers.size()), barriers.data());
            snapshot.present_stage_commands->CopyResource(
                present_backbuffer.Get(), snapshot.stereo_backbuffer.Get());
            for (auto& barrier : barriers) {
              std::swap(barrier.Transition.StateBefore,
                        barrier.Transition.StateAfter);
            }
            snapshot.present_stage_commands->ResourceBarrier(
                static_cast<UINT>(barriers.size()), barriers.data());
            if (submit_requested && !snapshot.failed && snapshot.submission_prepared) {
              snapshot.submission_attempted = true;
              const darktidevr::producer::StreamlineSubmissionApi api{
                  original_sl_set_constants, original_sl_set_tag_for_frame,
                  original_sl_set_tag};
              const bool staged = snapshot.submission.stage(api,
                  reinterpret_cast<void*>(bindings[0].token),
                  snapshot.present_stage_commands.Get(),
                  tagging_modes == 1
                      ? darktidevr::producer::StreamlineSubmission::Tagging::legacy
                      : darktidevr::producer::StreamlineSubmission::Tagging::frame_based,
                  darktidevr::producer::StreamlineSubmission::ConstantsMode::already_supplied);
              write_streamline_probe_log(
                  "STEREO_SUBMISSION\tphase=stage\tpresent_frame=%llu"
                  "\tframe_index=%u\ttoken_call=%llu\tresult=%d\tsuccess=%u"
                  "\ttags_staged=%u\thistory_reset=0\tcurrent_inputs=1\ttagging_modes=%u\tbatch=%llu\r\n",
                  static_cast<unsigned long long>(present), bindings[0].frame_index,
                  static_cast<unsigned long long>(bindings[0].token_call),
                  snapshot.submission.last_result(), staged ? 1U : 0U, staged ? 1U : 0U,
                  tagging_modes, static_cast<unsigned long long>(snapshot.submission_id));
              if (!staged) {
                const bool cleared = snapshot.submission.clear_tags(
                    snapshot.present_stage_commands.Get());
                snapshot.failed = true; // Keep diagnostic owners on any failure.
                write_streamline_probe_log(
                    "STEREO_SUBMISSION\tphase=abort\ttags_cleared=%u\tretained=1\r\n",
                    cleared ? 1U : 0U);
              }
            }
            const auto close_result = snapshot.present_stage_commands->Close();
            if (FAILED(close_result) || snapshot.failed) {
              snapshot.failed = true;
              write_streamline_probe_log(
                  "STEREO_PRESENT_STAGE\tphase=failed\treason=close"
                  "\thresult=0x%08x\r\n",
                  static_cast<unsigned>(close_result));
            } else {
              ID3D12CommandList* lists[]{snapshot.present_stage_commands.Get()};
              original_execute_command_lists(present_queue.Get(), 1, lists);
              if (FAILED(present_queue->Signal(snapshot.fence.Get(), snapshot.submission_stage_fence))) {
                snapshot.failed = true;
                write_streamline_probe_log(
                    "STEREO_PRESENT_STAGE\tphase=failed"
                    "\treason=signal\r\n");
              } else {
                snapshot.present_stage_pending = true;
                write_streamline_probe_log(
                    "STEREO_PRESENT_STAGE\tphase=scheduled"
                    "\tpresent_frame=%llu\tswapchain=%p"
                    "\tbackbuffer_index=%u\tsource=%p\tdestination=%p"
                    "\tfence_value=%llu\tcopy_staged=1\ttags_staged=%u"
                    "\tadditional_present_submitted=0"
                    "\tmetadata_published=0\tready_signaled=0\r\n",
                    static_cast<unsigned long long>(present), swapchain,
                    backbuffer_index, snapshot.stereo_backbuffer.Get(),
                    present_backbuffer.Get(),
                    static_cast<unsigned long long>(snapshot.submission_stage_fence),
                    snapshot.submission.phase() == darktidevr::producer::StreamlineSubmission::Phase::staged ? 1U : 0U);
              }
            }
          }
        }
      }
    }
  }
  if (streamline_stereo_submit_probe_requested.load(std::memory_order_acquire)) {
    std::scoped_lock lock(streamline_input_snapshot_mutex);
    auto& snapshot = streamline_input_snapshot_state;
    if (snapshot.submission_attempted && !snapshot.submission_presented &&
        snapshot.submission.begin_present()) {
      snapshot.submission_presented = true;
      darktidevr::producer::arm_ngx_output_probe(snapshot.submission_id, present);
      streamline_stereo_submission_present.store(present, std::memory_order_release);
      // The previous read-only observation must never supply this batch's tickets.
      snapshot.completion_observation_started = false;
      write_streamline_probe_log(
          "STEREO_SUBMISSION\tphase=present\tpresent_frame=%llu"
          "\tadditional_present_submitted=0\tmetadata_published=0\tbatch=%llu\r\n",
          static_cast<unsigned long long>(present),
          static_cast<unsigned long long>(snapshot.submission_id));
    }
  }
  streamline_outer_present_active_frame.store(present,
                                              std::memory_order_release);
  const bool report_present_health = streamline_persistent_requested.load();
  const bool trace_present_timing = trace_streamline_submission_images();
  const bool measure_present_cpu = report_present_health || trace_present_timing;
  const auto present_began_ms = trace_present_timing ? GetTickCount64() : 0;
  const auto present_cpu_began = measure_present_cpu
      ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
  const auto result = original_present(swapchain, interval, flags);
  const double present_cpu_ms = measure_present_cpu
      ? std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - present_cpu_began).count() : 0.0;
  if(report_present_health) {
    std::uint64_t published{};
    { std::scoped_lock lock(state_mutex); published=ready_value; }
    darktidevr::producer::generated_stereo_health(present,published,game_process_foreground(),present_cpu_ms);
  }
  if (trace_present_timing) {
    write_streamline_probe_log("STEREO_PRESENT_TIMING\tpresent_frame=%llu\tbegin_ms=%llu\tend_ms=%llu\tcpu_ms=%.4f\tclock=steady\r\n",
        present, present_began_ms, GetTickCount64(), present_cpu_ms);
  }
  streamline_outer_present_active_frame.store(0, std::memory_order_release);
  if (streamline_continuous_requested.load(std::memory_order_acquire) && present_queue) {
    std::scoped_lock api_lock(streamline_feature_api_mutex);
    std::scoped_lock lock(streamline_input_snapshot_mutex);
    streamline_continuous.after_present(present_queue.Get(),
        original_sl_dlssg_get_state.load(std::memory_order_acquire), original_execute_command_lists);
  }
  if (!streamline_continuous_requested.load(std::memory_order_acquire) &&
      SUCCEEDED(result) && streamline_input_snapshot_probe_requested.load(
          std::memory_order_acquire)) {
    const auto get_state = original_sl_dlssg_get_state.load(std::memory_order_acquire);
    std::array<std::uint32_t, 2> completion_viewports{};
    bool observe_completion = false;
    if (get_state) {
      std::scoped_lock snapshot_lock(streamline_input_snapshot_mutex);
      auto& snapshot = streamline_input_snapshot_state;
      if (snapshot.stereo_backbuffer_complete && (!snapshot.failed || snapshot.submission_presented) &&
          (!streamline_stereo_submit_probe_requested.load(std::memory_order_acquire) || snapshot.submission_presented) &&
          !snapshot.completion_observation_started) {
        snapshot.completion_observation_started = true;
        completion_viewports = {snapshot.constants[0].viewport, snapshot.constants[1].viewport};
        observe_completion = true;
      }
    }
    if (observe_completion) {
      for (std::size_t eye = 0; eye < 2; ++eye) {
        using namespace darktidevr::producer::streamline_2_7_30;
        const auto viewport = make_viewport(completion_viewports[eye]);
        auto observed = make_dlssg_state();
        int state_result{};
        {
          std::scoped_lock api_lock(streamline_feature_api_mutex);
          state_result = get_state(&viewport, &observed, nullptr);
        }
        ComPtr<ID3D12Fence> retained_fence;
        if (state_result == 0 && observed.base.struct_version >= 3 &&
            observed.inputs_processing_completion_fence) {
          static_cast<IUnknown*>(observed.inputs_processing_completion_fence)
              ->QueryInterface(IID_PPV_ARGS(&retained_fence));
        }
        const auto completed = retained_fence ? retained_fence->GetCompletedValue() : 0;
        {
          std::scoped_lock snapshot_lock(streamline_input_snapshot_mutex);
          streamline_input_snapshot_state.input_completion_fences[eye] = retained_fence;
          streamline_input_snapshot_state.input_completion_values[eye] =
              observed.last_present_inputs_processing_completion_fence_value;
          if (streamline_input_snapshot_state.submission_presented && retained_fence) {
            streamline_input_snapshot_state.submission.record_ticket(
                streamline_input_snapshot_state.submission_id,
                static_cast<std::uint32_t>(eye),
                reinterpret_cast<std::uintptr_t>(retained_fence.Get()),
                observed.last_present_inputs_processing_completion_fence_value);
          }
        }
        write_streamline_probe_log(
            "STEREO_INPUT_COMPLETION\tpresent_frame=%llu\tthread=%lu\teye=%zu"
            "\tviewport=%u\tresult=%d\tstatus=%u\tframes_presented=%u"
            "\tfence_retained=%u\tfence_value=%llu\tcompleted_value=%llu"
            "\tstereo_submission=%u\r\n",
            static_cast<unsigned long long>(present), GetCurrentThreadId(), eye,
            completion_viewports[eye], state_result, observed.status,
            observed.num_frames_actually_presented, retained_fence ? 1U : 0U,
            static_cast<unsigned long long>(observed.last_present_inputs_processing_completion_fence_value),
            static_cast<unsigned long long>(completed),
            streamline_stereo_submit_probe_requested.load(std::memory_order_relaxed) ? 1U : 0U);
      }
    }
  }
  if (streamline_stereo_submit_probe_requested.load(std::memory_order_acquire) &&
      present_queue) {
    std::scoped_lock lock(streamline_input_snapshot_mutex);
    auto& snapshot = streamline_input_snapshot_state;
    if (snapshot.submission_presented && !snapshot.submission_cleanup_attempted) {
      snapshot.submission_cleanup_attempted = true;
      ComPtr<ID3D12Device> device;
      bool cleared = false;
      HRESULT cleanup_result = snapshot.stereo_backbuffer->GetDevice(IID_PPV_ARGS(&device));
      if (SUCCEEDED(cleanup_result)) cleanup_result = device->CreateCommandAllocator(
          D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&snapshot.submission_cleanup_allocator));
      if (SUCCEEDED(cleanup_result)) cleanup_result = device->CreateCommandList(
          0, D3D12_COMMAND_LIST_TYPE_DIRECT, snapshot.submission_cleanup_allocator.Get(),
          nullptr, IID_PPV_ARGS(&snapshot.submission_cleanup_commands));
      if (SUCCEEDED(cleanup_result)) {
        cleared = snapshot.submission.clear_tags(snapshot.submission_cleanup_commands.Get());
        cleanup_result = snapshot.submission_cleanup_commands->Close();
      }
      if (SUCCEEDED(cleanup_result)) {
        ID3D12CommandList* lists[]{snapshot.submission_cleanup_commands.Get()};
        original_execute_command_lists(present_queue.Get(), 1, lists);
        cleanup_result = present_queue->Signal(snapshot.fence.Get(), snapshot.submission_cleanup_fence);
      }
      snapshot.submission_cleanup_pending = cleared && SUCCEEDED(cleanup_result);
      if (!snapshot.submission_cleanup_pending) snapshot.failed = true;
      write_streamline_probe_log(
          "STEREO_SUBMISSION\tphase=cleanup\ttags_cleared=%u"
          "\thresult=0x%08x\tfence_value=%llu\tpending=%u\tbatch=%llu\r\n",
          cleared ? 1U : 0U, static_cast<unsigned>(cleanup_result),
          static_cast<unsigned long long>(snapshot.submission_cleanup_fence),
          snapshot.submission_cleanup_pending ? 1U : 0U,
          static_cast<unsigned long long>(snapshot.submission_id));
    }
    if (snapshot.submission_cleanup_pending && !snapshot.failed && !snapshot.submission_retired) {
      const auto completed = snapshot.fence->GetCompletedValue();
      if (completed == UINT64_MAX) {
        snapshot.failed = true;
        write_streamline_probe_log("STEREO_SUBMISSION\tphase=failed\treason=cleanup_device_removed\r\n");
      } else if (completed >= snapshot.submission_cleanup_fence) {
        for (std::uint32_t eye = 0; eye < 2; ++eye) {
          const auto& fence = snapshot.input_completion_fences[eye];
          if (fence) snapshot.submission.observe_completion(snapshot.submission_id, eye,
              reinterpret_cast<std::uintptr_t>(fence.Get()), fence->GetCompletedValue());
        }
        if (snapshot.present_stage_complete && snapshot.submission.retire()) {
          snapshot.submission_retired = true;
          snapshot.submission_cleanup_pending = false;
          write_streamline_probe_log(
              "STEREO_SUBMISSION\tphase=retired\tinput_tickets_complete=1"
              "\tcleanup_fence_complete=1\tmetadata_published=0\tbatch=%llu\r\n",
              static_cast<unsigned long long>(snapshot.submission_id));
          if (snapshot.submission_id < snapshot.submission_limit) {
            // Both SL input tickets and our cleanup queue have completed. Only
            // now may the bounded diagnostic reuse textures and release command
            // owners. Keep the root fence monotonic across all batches.
            ++snapshot.submission_id;
            snapshot.submission_stage_fence += 2;
            snapshot.submission_cleanup_fence += 2;
            snapshot.present_stage_commands.Reset();
            snapshot.present_stage_allocator.Reset();
            snapshot.submission_cleanup_commands.Reset();
            snapshot.submission_cleanup_allocator.Reset();
            for (std::size_t eye = 0; eye < 2; ++eye) {
              snapshot.submission_refresh_commands[eye].Reset();
              snapshot.submission_refresh_allocators[eye].Reset();
              snapshot.submission_refresh_fences[eye].Reset();
              snapshot.input_completion_fences[eye].Reset();
            }
            snapshot.submission_refresh_constants = {};
            snapshot.input_completion_values = {};
            snapshot.submission_refresh_mask = 0;
            snapshot.submission_refresh_armed = false;
            snapshot.submission_attempted = false;
            snapshot.submission_presented = false;
            snapshot.submission_cleanup_attempted = false;
            snapshot.submission_retired = false;
            snapshot.completion_observation_started = false;
            snapshot.present_target_observed = false;
            snapshot.present_stage_pending = false;
            snapshot.present_stage_complete = false;
            const auto description = snapshot.stereo_backbuffer->GetDesc();
            snapshot.submission_prepared = snapshot.submission.prepare(
                snapshot.submission_id,
                static_cast<std::uint32_t>(description.Width / 2), description.Height,
                {snapshot.constants[0].viewport, snapshot.constants[1].viewport},
                {snapshot.constants[0].constants, snapshot.constants[1].constants},
                snapshot.submission_inputs);
            snapshot.failed = !snapshot.submission_prepared;
            write_streamline_probe_log(
                "STEREO_SEQUENCE\tphase=rearm\tbatch=%llu\tready=%u\tpresent_frame=%llu\r\n",
                static_cast<unsigned long long>(snapshot.submission_id),
                snapshot.submission_prepared ? 1U : 0U,
                static_cast<unsigned long long>(present));
          }
        }
      }
    }
  }
  if (sample_streamline) {
    LARGE_INTEGER streamline_end{};
    QueryPerformanceCounter(&streamline_end);
    ComPtr<ID3D12Fence> capture_ready_fence;
    std::uint64_t capture_ready_value{};
    {
      std::scoped_lock lock(state_mutex);
      capture_ready_fence = ready_fence;
      capture_ready_value = ready_value;
    }
    const auto completed = capture_ready_fence
                               ? capture_ready_fence->GetCompletedValue()
                               : 0;
    write_streamline_probe_log(
        "PRESENT_END\tframe=%llu\tthread=%lu\tqpc=%lld\tresult=%ld"
        "\tready_fence=%p\tready_value=%llu\tready_completed=%llu"
        "\tnative_present_count=%llu\r\n",
        present, GetCurrentThreadId(), streamline_end.QuadPart, result,
        capture_ready_fence.Get(),
        static_cast<unsigned long long>(capture_ready_value),
        static_cast<unsigned long long>(completed),
        static_cast<unsigned long long>(
            streamline_native_present_count.load(std::memory_order_relaxed)));
  }
  // Resize after DXGI Present completes. A real client-area change makes
  // Stingray rebuild every viewport-dependent resource; the old synthetic
  // WM_SIZE only persisted a fake dimension and left the scene half-built.
  lock_swapchain_client_extent(client_lock_window);
  nudge_swapchain_client_extent(client_lock_window, resize_pending);
  return result;
}

void STDMETHODCALLTYPE set_marker_hook(ID3D12GraphicsCommandList* commands,
                                       UINT metadata, const void* data,
                                       UINT size) {
  log_marker_event("MARK", commands, metadata, data, size);
  log_focused_marker_event("MARK", commands, metadata, data, size);
  original_set_marker(commands, metadata, data, size);
}

void STDMETHODCALLTYPE begin_event_hook(ID3D12GraphicsCommandList* commands,
                                        UINT metadata, const void* data,
                                        UINT size) {
  log_marker_event("BEGIN", commands, metadata, data, size);
  log_focused_marker_event("BEGIN", commands, metadata, data, size);
  if (boundary_census_log != INVALID_HANDLE_VALUE ||
      marker_log != INVALID_HANDLE_VALUE ||
      cluster_trace_log != INVALID_HANDLE_VALUE) {
    std::scoped_lock lock(boundary_capture_mutex);
    command_marker_stacks[commands].push_back(
        boundary_marker_label(metadata, data, size));
  }
  original_begin_event(commands, metadata, data, size);
}

void STDMETHODCALLTYPE end_event_hook(ID3D12GraphicsCommandList* commands) {
  const auto sequence = marker_sequence.fetch_add(1, std::memory_order_relaxed);
  write_marker_log("%llu\t%lu\tCL=%p\tEND\r\n", sequence,
                   GetCurrentThreadId(), commands);
  write_focused_log("phase=%d\tframe=%llu\tCL=%p\tEND\r\n",
                    focused_trace_phase.load(std::memory_order_relaxed),
                    present_count.load(std::memory_order_relaxed), commands);
  if (boundary_census_log != INVALID_HANDLE_VALUE ||
      marker_log != INVALID_HANDLE_VALUE ||
      cluster_trace_log != INVALID_HANDLE_VALUE) {
    std::scoped_lock lock(boundary_capture_mutex);
    const auto found = command_marker_stacks.find(commands);
    if (found != command_marker_stacks.end() && !found->second.empty()) {
      found->second.pop_back();
    }
  }
  original_end_event(commands);
}

LRESULT CALLBACK dummy_window_proc(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam) {
  return DefWindowProcW(window, message, wparam, lparam);
}

int install_hooks(ID3D12Device* supplied_device = nullptr) {
  if (hooks_installed.load(std::memory_order_acquire)) {
    return 0;
  }

  ComPtr<ID3D12Device> device;
  if (supplied_device) {
    supplied_device->AddRef();
    device.Attach(supplied_device);
  } else {
    if (FAILED(D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_12_0,
                                 IID_PPV_ARGS(&device)))) {
      return 10;
    }
  }
  D3D12_COMMAND_QUEUE_DESC queue_description{};
  queue_description.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
  ComPtr<ID3D12CommandQueue> queue;
  if (FAILED(device->CreateCommandQueue(&queue_description,
                                        IID_PPV_ARGS(&queue)))) {
    return 11;
  }
  ComPtr<ID3D12CommandAllocator> dummy_allocator;
  ComPtr<ID3D12GraphicsCommandList> dummy_commands;
  if (FAILED(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                             IID_PPV_ARGS(&dummy_allocator))) ||
      FAILED(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                       dummy_allocator.Get(), nullptr,
                                       IID_PPV_ARGS(&dummy_commands)))) {
    return 15;
  }
  D3D12_HEAP_PROPERTIES dummy_upload_properties{};
  dummy_upload_properties.Type = D3D12_HEAP_TYPE_UPLOAD;
  D3D12_RESOURCE_DESC dummy_buffer_description{};
  dummy_buffer_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
  dummy_buffer_description.Width = 256;
  dummy_buffer_description.Height = 1;
  dummy_buffer_description.DepthOrArraySize = 1;
  dummy_buffer_description.MipLevels = 1;
  dummy_buffer_description.SampleDesc.Count = 1;
  dummy_buffer_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  ComPtr<ID3D12Resource> dummy_upload_resource;
  if (FAILED(device->CreateCommittedResource(
          &dummy_upload_properties, D3D12_HEAP_FLAG_NONE,
          &dummy_buffer_description, D3D12_RESOURCE_STATE_GENERIC_READ,
          nullptr, IID_PPV_ARGS(&dummy_upload_resource)))) {
    return 20;
  }

  const wchar_t class_name[] = L"DarktideVRNativeCaptureDummy";
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = dummy_window_proc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.lpszClassName = class_name;
  RegisterClassW(&window_class);
  const auto window = CreateWindowExW(0, class_name, L"", WS_OVERLAPPED,
                                      0, 0, 16, 16, nullptr, nullptr,
                                      window_class.hInstance, nullptr);
  if (!window) {
    return 12;
  }

  ComPtr<IDXGIFactory4> factory;
  ComPtr<IDXGISwapChain1> swapchain1;
  DXGI_SWAP_CHAIN_DESC1 swapchain_description{};
  swapchain_description.Width = 16;
  swapchain_description.Height = 16;
  swapchain_description.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  swapchain_description.SampleDesc.Count = 1;
  swapchain_description.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  swapchain_description.BufferCount = 2;
  swapchain_description.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  const auto factory_result = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
  const auto swapchain_result = SUCCEEDED(factory_result)
                                    ? factory->CreateSwapChainForHwnd(
                                          queue.Get(), window,
                                          &swapchain_description, nullptr,
                                          nullptr, &swapchain1)
                                    : factory_result;
  if (FAILED(swapchain_result)) {
    DestroyWindow(window);
    UnregisterClassW(class_name, window_class.hInstance);
    return 13;
  }
  ComPtr<IDXGISwapChain3> dummy_swapchain3;
  if (FAILED(swapchain1.As(&dummy_swapchain3))) {
    DestroyWindow(window);
    UnregisterClassW(class_name, window_class.hInstance);
    return 18;
  }

  auto** queue_vtable = *reinterpret_cast<void***>(queue.Get());
  auto** device_vtable = *reinterpret_cast<void***>(device.Get());
  ComPtr<ID3D12Device2> device2;
  if (FAILED(device.As(&device2))) {
    return 16;
  }
  ComPtr<ID3D12Device1> device1;
  ComPtr<ID3D12PipelineLibrary> pipeline_library;
  ComPtr<ID3D12PipelineLibrary1> pipeline_library1;
  if (FAILED(device.As(&device1)) ||
      FAILED(device1->CreatePipelineLibrary(nullptr, 0,
                                            IID_PPV_ARGS(&pipeline_library))) ||
      FAILED(pipeline_library.As(&pipeline_library1))) {
    return 17;
  }
  auto** device2_vtable = *reinterpret_cast<void***>(device2.Get());
  auto** pipeline_library_vtable =
      *reinterpret_cast<void***>(pipeline_library.Get());
  auto** pipeline_library1_vtable =
      *reinterpret_cast<void***>(pipeline_library1.Get());
  auto** swapchain_vtable =
      *reinterpret_cast<void***>(dummy_swapchain3.Get());
  constexpr GUID kStreamlineRetrieveBaseInterface{
      0xadec44e2, 0x61f0, 0x45c3,
      {0xad, 0x9f, 0x1b, 0x37, 0x37, 0x92, 0x84, 0xff}};
  ComPtr<IDXGISwapChain> streamline_native_swapchain;
  void* streamline_native_present{};
  if (SUCCEEDED(dummy_swapchain3->QueryInterface(
          kStreamlineRetrieveBaseInterface,
          reinterpret_cast<void**>(
              streamline_native_swapchain.GetAddressOf())))) {
    auto** native_swapchain_vtable =
        *reinterpret_cast<void***>(streamline_native_swapchain.Get());
    streamline_native_present = native_swapchain_vtable[8];
  }
  auto** command_list_vtable =
      *reinterpret_cast<void***>(dummy_commands.Get());
  auto** resource_vtable =
      *reinterpret_cast<void***>(dummy_upload_resource.Get());
  const auto get_client_rect_target = reinterpret_cast<void*>(
      GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetClientRect"));
  const auto dispatch_message_w_target = reinterpret_cast<void*>(
      GetProcAddress(GetModuleHandleW(L"user32.dll"), "DispatchMessageW"));
  if (!get_client_rect_target || !dispatch_message_w_target) {
    return 19;
  }
  ComPtr<ID3D12GraphicsCommandList7> dummy_commands7;
  const auto enhanced_barriers_available =
      SUCCEEDED(dummy_commands.As(&dummy_commands7));
  void** command_list7_vtable = enhanced_barriers_available
                                    ? *reinterpret_cast<void***>(
                                          dummy_commands7.Get())
                                    : nullptr;
  const auto install_cluster_trace_hooks =
      cluster_trace_log != INVALID_HANDLE_VALUE;
  const auto install_cluster_light_visibility_fix_hooks =
      cluster_light_visibility_fix_requested.load(std::memory_order_relaxed);
  initialize_streamline_probe(swapchain_vtable[8],
                              streamline_native_present);
  const auto install_pso_substitution_hooks =
      kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed) ||
      kStockMenuDirectRenderEnabled ||
      install_cluster_trace_hooks ||
      install_cluster_light_visibility_fix_hooks ||
      billboard_shader_substitution_requested.load(std::memory_order_relaxed) ||
      billboard_pixel_shader_probe_requested.load(std::memory_order_relaxed);
  void* stingray_upload_flush_target{};
  if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed) ||
      install_cluster_trace_hooks ||
      install_cluster_light_visibility_fix_hooks) {
    constexpr std::uintptr_t kUploadFlushRva = 0x7d5840;
    constexpr std::array<std::byte, 12> kUploadFlushSignature{
        std::byte{0x4c}, std::byte{0x8b}, std::byte{0xdc}, std::byte{0x48},
        std::byte{0x83}, std::byte{0xec}, std::byte{0x48}, std::byte{0x80},
        std::byte{0xb9}, std::byte{0xb0}, std::byte{0x00}, std::byte{0x00}};
    auto* candidate = reinterpret_cast<std::byte*>(GetModuleHandleW(nullptr)) +
                      kUploadFlushRva;
    MEMORY_BASIC_INFORMATION memory{};
    if (VirtualQuery(candidate, &memory, sizeof(memory)) == sizeof(memory) &&
        memory.State == MEM_COMMIT &&
        std::memcmp(candidate, kUploadFlushSignature.data(),
                    kUploadFlushSignature.size()) == 0) {
      stingray_upload_flush_target = candidate;
      billboard_upload_flush_hook_state.store(1, std::memory_order_relaxed);
    } else {
      billboard_upload_flush_hook_state.store(2, std::memory_order_relaxed);
    }
  }
  if (MH_Initialize() != MH_OK ||
      !darktidevr::producer::install_resource_handle_trace(native_capture_module) ||
      !darktidevr::producer::install_ngx_output_probe(native_capture_module) ||
      (streamline_feature_resolver_target &&
       MH_CreateHook(streamline_feature_resolver_target,
                     &sl_get_feature_function_hook,
                     reinterpret_cast<void**>(
                         &original_sl_get_feature_function)) != MH_OK) ||
      (streamline_get_new_frame_token_target &&
       MH_CreateHook(streamline_get_new_frame_token_target,
                     &sl_get_new_frame_token_hook,
                     reinterpret_cast<void**>(
                         &original_sl_get_new_frame_token)) != MH_OK) ||
      (streamline_set_constants_target &&
       MH_CreateHook(streamline_set_constants_target,
                     &sl_set_constants_hook,
                     reinterpret_cast<void**>(
                         &original_sl_set_constants)) != MH_OK) ||
      (streamline_set_tag_target &&
       MH_CreateHook(streamline_set_tag_target, &sl_set_tag_hook,
                     reinterpret_cast<void**>(&original_sl_set_tag)) != MH_OK) ||
      (streamline_set_tag_for_frame_target &&
       MH_CreateHook(streamline_set_tag_for_frame_target,
                     &sl_set_tag_for_frame_hook,
                     reinterpret_cast<void**>(
                         &original_sl_set_tag_for_frame)) != MH_OK) ||
      MH_CreateHook(get_client_rect_target, &get_client_rect_hook,
                    reinterpret_cast<void**>(&original_get_client_rect)) !=
          MH_OK ||
      MH_CreateHook(dispatch_message_w_target, &dispatch_message_w_hook,
                    reinterpret_cast<void**>(&original_dispatch_message_w)) !=
          MH_OK ||
      (install_pso_substitution_hooks &&
       MH_CreateHook(device_vtable[10], &create_graphics_pipeline_state_hook,
                    reinterpret_cast<void**>(
                        &original_create_graphics_pipeline_state)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(device_vtable[11], &create_compute_pipeline_state_hook,
                    reinterpret_cast<void**>(
                        &original_create_compute_pipeline_state)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kMenuLayerConsumerProbeEnabled ||
        install_cluster_trace_hooks) &&
       MH_CreateHook(device_vtable[14], &create_descriptor_heap_hook,
                     reinterpret_cast<void**>(
                         &original_create_descriptor_heap)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kMenuLayerConsumerProbeEnabled ||
        install_cluster_trace_hooks) &&
       MH_CreateHook(device_vtable[16], &create_root_signature_hook,
                    reinterpret_cast<void**>(
                        &original_create_root_signature)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(device_vtable[17], &create_constant_buffer_view_hook,
                    reinterpret_cast<void**>(
                        &original_create_constant_buffer_view)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kMenuLayerConsumerProbeEnabled ||
        install_cluster_trace_hooks) &&
       MH_CreateHook(device_vtable[18], &create_shader_resource_view_hook,
                    reinterpret_cast<void**>(
                        &original_create_shader_resource_view)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(device_vtable[19], &create_unordered_access_view_hook,
                    reinterpret_cast<void**>(
                        &original_create_unordered_access_view)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kStockMenuDirectRenderEnabled) &&
       MH_CreateHook(device_vtable[20], &create_render_target_view_hook,
                    reinterpret_cast<void**>(
                         &original_create_render_target_view)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[21], &create_depth_stencil_view_hook,
                    reinterpret_cast<void**>(
                        &original_create_depth_stencil_view)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[41], &create_command_signature_hook,
                     reinterpret_cast<void**>(
                         &original_create_command_signature)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kStockMenuDirectRenderEnabled ||
        install_cluster_trace_hooks) &&
       MH_CreateHook(device_vtable[23], &copy_descriptors_hook,
                    reinterpret_cast<void**>(
                         &original_copy_descriptors)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kStockMenuDirectRenderEnabled ||
        install_cluster_trace_hooks) &&
       MH_CreateHook(device_vtable[24], &copy_descriptors_simple_hook,
                    reinterpret_cast<void**>(
                         &original_copy_descriptors_simple)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks ||
        install_cluster_light_visibility_fix_hooks) &&
       MH_CreateHook(device_vtable[27], &create_committed_resource_hook,
                    reinterpret_cast<void**>(
                        &original_create_committed_resource)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks ||
        install_cluster_light_visibility_fix_hooks) &&
       MH_CreateHook(device_vtable[29], &create_placed_resource_hook,
                    reinterpret_cast<void**>(
                        &original_create_placed_resource)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(resource_vtable[8], &resource_map_hook,
                     reinterpret_cast<void**>(&original_resource_map)) !=
           MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(resource_vtable[9], &resource_unmap_hook,
                     reinterpret_cast<void**>(&original_resource_unmap)) !=
           MH_OK) ||
      (stingray_upload_flush_target &&
       MH_CreateHook(stingray_upload_flush_target, &stingray_upload_flush_hook,
                     reinterpret_cast<void**>(
                         &original_stingray_upload_flush)) != MH_OK) ||
      (install_pso_substitution_hooks &&
       MH_CreateHook(device2_vtable[47], &create_pipeline_state_stream_hook,
                    reinterpret_cast<void**>(
                        &original_create_pipeline_state_stream)) != MH_OK) ||
      (install_pso_substitution_hooks &&
       MH_CreateHook(pipeline_library_vtable[9], &load_graphics_pipeline_hook,
                    reinterpret_cast<void**>(
                        &original_load_graphics_pipeline)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(pipeline_library_vtable[10], &load_compute_pipeline_hook,
                    reinterpret_cast<void**>(
                        &original_load_compute_pipeline)) != MH_OK) ||
      (install_pso_substitution_hooks &&
       MH_CreateHook(pipeline_library1_vtable[13], &load_pipeline_hook,
                    reinterpret_cast<void**>(&original_load_pipeline)) !=
          MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kStockMenuDirectRenderEnabled) &&
       MH_CreateHook(command_list_vtable[9], &close_hook,
                    reinterpret_cast<void**>(&original_close)) != MH_OK) ||
      MH_CreateHook(command_list_vtable[10], &reset_hook,
                    reinterpret_cast<void**>(&original_reset)) != MH_OK ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[27], &execute_bundle_hook,
                     reinterpret_cast<void**>(&original_execute_bundle)) !=
           MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kStockMenuDirectRenderEnabled ||
        install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[12], &draw_instanced_hook,
                    reinterpret_cast<void**>(&original_draw_instanced)) !=
           MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks ||
        install_cluster_light_visibility_fix_hooks) &&
       MH_CreateHook(command_list_vtable[13], &draw_indexed_instanced_hook,
                    reinterpret_cast<void**>(
                         &original_draw_indexed_instanced)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[14], &dispatch_hook,
                     reinterpret_cast<void**>(&original_dispatch)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[15], &copy_buffer_region_hook,
                     reinterpret_cast<void**>(&original_copy_buffer_region)) !=
           MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[16], &copy_texture_region_hook,
                     reinterpret_cast<void**>(
                         &original_copy_texture_region)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[17], &copy_resource_hook,
                     reinterpret_cast<void**>(&original_copy_resource)) !=
           MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[19], &resolve_subresource_hook,
                     reinterpret_cast<void**>(
                         &original_resolve_subresource)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[20],
                    &ia_set_primitive_topology_hook,
                    reinterpret_cast<void**>(
                        &original_ia_set_primitive_topology)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || world_ui_capture_requested()) &&
       MH_CreateHook(command_list_vtable[21], &rs_set_viewports_hook,
                     reinterpret_cast<void**>(&original_rs_set_viewports)) !=
           MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[22], &rs_set_scissor_rects_hook,
                     reinterpret_cast<void**>(
                         &original_rs_set_scissor_rects)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kStockMenuDirectRenderEnabled ||
        install_cluster_trace_hooks ||
        install_cluster_light_visibility_fix_hooks) &&
       MH_CreateHook(command_list_vtable[25], &set_pipeline_state_hook,
                    reinterpret_cast<void**>(&original_set_pipeline_state)) !=
           MH_OK) ||
      MH_CreateHook(command_list_vtable[26], &resource_barrier_hook,
                    reinterpret_cast<void**>(&original_resource_barrier)) != MH_OK ||
      (enhanced_barriers_available &&
       MH_CreateHook(command_list7_vtable[80], &enhanced_barrier_hook,
                     reinterpret_cast<void**>(&original_enhanced_barrier)) !=
           MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kStockMenuDirectRenderEnabled) &&
       enhanced_barriers_available &&
       MH_CreateHook(command_list7_vtable[68], &begin_render_pass_hook,
                    reinterpret_cast<void**>(&original_begin_render_pass)) !=
           MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kStockMenuDirectRenderEnabled) &&
       enhanced_barriers_available &&
       MH_CreateHook(command_list7_vtable[69], &end_render_pass_hook,
                    reinterpret_cast<void**>(&original_end_render_pass)) !=
           MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[28], &set_descriptor_heaps_hook,
                     reinterpret_cast<void**>(
                         &original_set_descriptor_heaps)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[29], &set_compute_root_signature_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_signature)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kMenuLayerConsumerProbeEnabled ||
        install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[30],
                    &set_graphics_root_signature_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_signature)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[31],
                    &set_compute_root_descriptor_table_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_descriptor_table)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kMenuLayerConsumerProbeEnabled ||
        install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[32],
                    &set_graphics_root_descriptor_table_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_descriptor_table)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[33],
                    &set_compute_root_32bit_constant_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_32bit_constant)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[34],
                    &set_graphics_root_32bit_constant_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_32bit_constant)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[35],
                    &set_compute_root_32bit_constants_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_32bit_constants)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[36],
                    &set_graphics_root_32bit_constants_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_32bit_constants)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[37],
                    &set_compute_root_constant_buffer_view_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_constant_buffer_view)) !=
           MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks ||
        install_cluster_light_visibility_fix_hooks) &&
       MH_CreateHook(command_list_vtable[38],
                    &set_graphics_root_constant_buffer_view_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_constant_buffer_view)) !=
           MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[39],
                    &set_compute_root_shader_resource_view_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_shader_resource_view)) !=
           MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[40],
                    &set_graphics_root_shader_resource_view_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_shader_resource_view)) !=
           MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[41],
                    &set_compute_root_unordered_access_view_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_unordered_access_view)) !=
           MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[42],
                    &set_graphics_root_unordered_access_view_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_unordered_access_view)) !=
           MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[43], &ia_set_index_buffer_hook,
                    reinterpret_cast<void**>(
                        &original_ia_set_index_buffer)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[44], &ia_set_vertex_buffers_hook,
                    reinterpret_cast<void**>(
                        &original_ia_set_vertex_buffers)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || kStockMenuDirectRenderEnabled) &&
       MH_CreateHook(command_list_vtable[46], &om_set_render_targets_hook,
                    reinterpret_cast<void**>(
                         &original_om_set_render_targets)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[47], &clear_depth_stencil_view_hook,
                    reinterpret_cast<void**>(
                        &original_clear_depth_stencil_view)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[48], &clear_render_target_view_hook,
                    reinterpret_cast<void**>(
                        &original_clear_render_target_view)) != MH_OK) ||
      MH_CreateHook(queue_vtable[10], &execute_command_lists_hook,
                    reinterpret_cast<void**>(&original_execute_command_lists)) !=
          MH_OK ||
      (streamline_native_present_target &&
       streamline_native_present_target != swapchain_vtable[8] &&
       MH_CreateHook(streamline_native_present_target,
                     &streamline_native_present_hook,
                     reinterpret_cast<void**>(
                         &original_streamline_native_present)) != MH_OK) ||
      MH_CreateHook(swapchain_vtable[8], &present_hook,
                     reinterpret_cast<void**>(&original_present)) != MH_OK ||
      (streamline_stereo_swapchain_probe_requested.load(std::memory_order_acquire) &&
       (MH_CreateHook(swapchain_vtable[9], &swapchain_get_buffer_hook,
           reinterpret_cast<void**>(&original_swapchain_get_buffer)) != MH_OK ||
        MH_CreateHook(swapchain_vtable[12], &swapchain_get_desc_hook,
           reinterpret_cast<void**>(&original_swapchain_get_desc)) != MH_OK ||
        MH_CreateHook(swapchain_vtable[18], &swapchain_get_desc1_hook,
           reinterpret_cast<void**>(&original_swapchain_get_desc1)) != MH_OK)) ||
      MH_CreateHook(swapchain_vtable[13], &resize_buffers_hook,
                    reinterpret_cast<void**>(&original_resize_buffers)) !=
          MH_OK ||
      MH_CreateHook(swapchain_vtable[39], &resize_buffers1_hook,
                    reinterpret_cast<void**>(&original_resize_buffers1)) !=
          MH_OK ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[55], &set_marker_hook,
                     reinterpret_cast<void**>(&original_set_marker)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[56], &begin_event_hook,
                     reinterpret_cast<void**>(&original_begin_event)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[57], &end_event_hook,
                     reinterpret_cast<void**>(&original_end_event)) != MH_OK) ||
      ((kInstallDiagnosticRenderHooks || install_cluster_trace_hooks) &&
       MH_CreateHook(command_list_vtable[59], &execute_indirect_hook,
                     reinterpret_cast<void**>(&original_execute_indirect)) !=
           MH_OK) ||
      MH_EnableHook(MH_ALL_HOOKS) != MH_OK) {
    DestroyWindow(window);
    UnregisterClassW(class_name, window_class.hInstance);
    return 14;
  }

  DestroyWindow(window);
  UnregisterClassW(class_name, window_class.hInstance);
  if (stingray_upload_flush_target) {
    billboard_upload_flush_hook_state.store(3, std::memory_order_relaxed);
  }
  cluster_light_visibility_fix_active.store(
      install_cluster_light_visibility_fix_hooks &&
          stingray_upload_flush_target != nullptr,
      std::memory_order_release);
  hooks_installed.store(true, std::memory_order_release);
  return 0;
}

void close_shared_handles() {
  for (auto& handle : eye_handles) {
    if (handle) {
      CloseHandle(handle);
      handle = nullptr;
    }
  }
  if (ready_fence_handle) {
    CloseHandle(ready_fence_handle);
    ready_fence_handle = nullptr;
  }
  if (consumed_fence_handle) {
    CloseHandle(consumed_fence_handle);
    consumed_fence_handle = nullptr;
  }
}

void reset_eye_surface_resources() {
  close_shared_handles();
  eye_surfaces = {};
  desktop_mirror_surface.Reset();
  desktop_mirror_fence.Reset();
  desktop_mirror_fence_value = 0;
  desktop_mirror_pending.clear();
  desktop_mirror_available.clear();
  desktop_mirror_ready.store(false, std::memory_order_relaxed);
  ready_fence.Reset();
  consumed_fence.Reset();
  ready_value = 0;
  pending_captures.clear();
  available_captures.clear();
  staged_eye0_capture = {};
  staged_eye0_capture_valid = false;
  staged_pair_dropped = false;
}

void close_menu_shared_handles() {
  if (menu_surface_handle) {
    CloseHandle(menu_surface_handle);
    menu_surface_handle = nullptr;
  }
  if (menu_ready_fence_handle) {
    CloseHandle(menu_ready_fence_handle);
    menu_ready_fence_handle = nullptr;
  }
  if (menu_consumed_fence_handle) {
    CloseHandle(menu_consumed_fence_handle);
    menu_consumed_fence_handle = nullptr;
  }
}

void reset_menu_surface_resources() {
  close_menu_shared_handles();
  menu_surface.Reset();
  menu_rtv_heap.Reset();
  menu_rtv = {};
  menu_rtv_format = DXGI_FORMAT_UNKNOWN;
  menu_ready_fence.Reset();
  menu_consumed_fence.Reset();
  menu_ready_value = 0;
  direct_menu_clear_frame = (std::numeric_limits<std::uint64_t>::max)();
  direct_menu_render_frame.store((std::numeric_limits<std::uint64_t>::max)(),
                                 std::memory_order_relaxed);
  direct_menu_render_lists.clear();
  direct_menu_ui_stream_frame = (std::numeric_limits<std::uint64_t>::max)();
  options_layer_resources[0].store(nullptr, std::memory_order_release);
  options_layer_resources[1].store(nullptr, std::memory_order_release);
  direct_menu_render_list_count.store(0, std::memory_order_release);
  menu_pending_captures.clear();
  menu_available_captures.clear();
}

int ensure_menu_surface(ID3D12Device* device,
                        const D3D12_RESOURCE_DESC& source_description,
                        DXGI_FORMAT render_target_format) {
  const auto requested_rtv_format =
      render_target_format != DXGI_FORMAT_UNKNOWN
          ? render_target_format
          : source_description.Format;
  const auto requested_resource_format = static_cast<DXGI_FORMAT>(
      darktidevr::core::canonical_shared_render_target_format(
          static_cast<std::uint32_t>(source_description.Format),
          static_cast<std::uint32_t>(requested_rtv_format)));
  const auto current_description =
      menu_surface ? menu_surface->GetDesc() : D3D12_RESOURCE_DESC{};
  const bool matching_surface =
      menu_surface && menu_rtv_heap && menu_surface_handle &&
      darktidevr::core::shared_render_target_description_matches(
          current_description.Width, current_description.Height,
          static_cast<std::uint32_t>(current_description.Format),
          source_description.Width, source_description.Height,
          static_cast<std::uint32_t>(source_description.Format),
          static_cast<std::uint32_t>(requested_rtv_format)) &&
      menu_rtv_format == requested_rtv_format;
  const bool shared_fences_healthy =
      menu_ready_fence && menu_consumed_fence && menu_ready_fence_handle &&
      menu_consumed_fence_handle &&
      menu_ready_fence->GetCompletedValue() != UINT64_MAX &&
      menu_consumed_fence->GetCompletedValue() != UINT64_MAX;
  if (matching_surface && shared_fences_healthy) {
    return 0;
  }
  if (matching_surface && !shared_fences_healthy) {
    write_menu_resource_log(
        "MENU_SHARED_RECREATE\treason=poisoned_or_missing_fence"
        "\tready=%llu\tconsumed=%llu\r\n",
        menu_ready_fence
            ? static_cast<unsigned long long>(
                  menu_ready_fence->GetCompletedValue())
            : 0ULL,
        menu_consumed_fence
            ? static_cast<unsigned long long>(
                  menu_consumed_fence->GetCompletedValue())
            : 0ULL);
  } else if (menu_surface && !matching_surface) {
    write_menu_resource_log(
        "MENU_SHARED_RECREATE\treason=description_mismatch"
        "\tcurrent_width=%llu\tcurrent_height=%u"
        "\tcurrent_resource_format=%u\tcurrent_rtv_format=%u"
        "\trequested_width=%llu\trequested_height=%u"
        "\trequested_source_format=%u\trequested_resource_format=%u"
        "\trequested_rtv_format=%u"
        "\thas_heap=%u\thas_handle=%u\r\n",
        static_cast<unsigned long long>(current_description.Width),
        current_description.Height,
        static_cast<unsigned>(current_description.Format),
        static_cast<unsigned>(menu_rtv_format),
        static_cast<unsigned long long>(source_description.Width),
        source_description.Height,
        static_cast<unsigned>(source_description.Format),
        static_cast<unsigned>(requested_resource_format),
        static_cast<unsigned>(requested_rtv_format), menu_rtv_heap ? 1U : 0U,
        menu_surface_handle ? 1U : 0U);
  }

  // Recorded command lists retain the current surface through
  // direct_menu_render_lists until their next Reset. Replacing the global
  // surface while any such list is pending leaves the GPU referencing a
  // destroyed resource (observed as a DRED page fault when crafting changed
  // from its landing page to the item picker). A differently sized UI pass is
  // not the presentation surface and must wait rather than invalidating work
  // already recorded against it.
  if (!direct_menu_render_lists.empty()) {
    return 89;
  }

  reset_menu_surface_resources();

  D3D12_HEAP_PROPERTIES heap{};
  heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  auto description = source_description;
  description.Format = requested_resource_format;
  description.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
  description.MipLevels = 1;
  description.SampleDesc.Count = 1;
  const D3D12_DESCRIPTOR_HEAP_DESC rtv_heap_description{
      D3D12_DESCRIPTOR_HEAP_TYPE_RTV, 1, D3D12_DESCRIPTOR_HEAP_FLAG_NONE, 0};
  const auto resource_result = device->CreateCommittedResource(
      &heap, D3D12_HEAP_FLAG_SHARED, &description,
      D3D12_RESOURCE_STATE_COMMON, nullptr, IID_PPV_ARGS(&menu_surface));
  const auto handle_result =
      SUCCEEDED(resource_result)
          ? device->CreateSharedHandle(menu_surface.Get(), nullptr, GENERIC_ALL,
                                       kMenuSurfaceName, &menu_surface_handle)
          : E_FAIL;
  const auto heap_result =
      SUCCEEDED(handle_result)
          ? device->CreateDescriptorHeap(&rtv_heap_description,
                                         IID_PPV_ARGS(&menu_rtv_heap))
          : E_FAIL;
  if (FAILED(resource_result) || FAILED(handle_result) || FAILED(heap_result)) {
    write_menu_resource_log(
        "MENU_DIRECT_CREATE_FAILED\tresource=%ld\thandle=%ld\theap=%ld"
        "\twidth=%llu\theight=%u\tresource_format=%u\trtv_format=%u\r\n",
        resource_result, handle_result, heap_result,
        static_cast<unsigned long long>(description.Width), description.Height,
        static_cast<unsigned>(description.Format),
        static_cast<unsigned>(render_target_format));
    reset_menu_surface_resources();
    return 90;
  }
  menu_rtv = menu_rtv_heap->GetCPUDescriptorHandleForHeapStart();
  D3D12_RENDER_TARGET_VIEW_DESC rtv_description{};
  rtv_description.Format = requested_rtv_format;
  rtv_description.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
  device->CreateRenderTargetView(menu_surface.Get(), &rtv_description, menu_rtv);
  menu_rtv_format = requested_rtv_format;
  const auto ready_fence_result = device->CreateFence(
      0, D3D12_FENCE_FLAG_SHARED, IID_PPV_ARGS(&menu_ready_fence));
  const auto ready_handle_result =
      SUCCEEDED(ready_fence_result)
          ? device->CreateSharedHandle(
                menu_ready_fence.Get(), nullptr, GENERIC_ALL,
                kMenuReadyFenceName, &menu_ready_fence_handle)
          : E_FAIL;
  if (FAILED(ready_fence_result) || FAILED(ready_handle_result)) {
    write_menu_resource_log(
        "MENU_DIRECT_CREATE_FAILED\tready_fence=%ld\tready_handle=%ld\r\n",
        ready_fence_result, ready_handle_result);
    reset_menu_surface_resources();
    return 91;
  }
  const auto consumed_fence_result = device->CreateFence(
      0, D3D12_FENCE_FLAG_SHARED, IID_PPV_ARGS(&menu_consumed_fence));
  const auto consumed_handle_result =
      SUCCEEDED(consumed_fence_result)
          ? device->CreateSharedHandle(
                menu_consumed_fence.Get(), nullptr, GENERIC_ALL,
                kMenuConsumedFenceName, &menu_consumed_fence_handle)
          : E_FAIL;
  if (FAILED(consumed_fence_result) || FAILED(consumed_handle_result)) {
    write_menu_resource_log(
        "MENU_DIRECT_CREATE_FAILED\tconsumed_fence=%ld"
        "\tconsumed_handle=%ld\r\n",
        consumed_fence_result, consumed_handle_result);
    reset_menu_surface_resources();
    return 92;
  }
  const auto surface_generation =
      shared_head_pose_reader().advance_menu_surface_generation();
  if (surface_generation != 0) {
    write_menu_resource_log(
        "MENU_SHARED_GENERATION\tgeneration=%llu\r\n",
        static_cast<unsigned long long>(surface_generation));
  }
  return 0;
}

MenuDrawRedirect begin_stock_menu_draw_redirect(
    ID3D12GraphicsCommandList* commands, const PsoMetadata& metadata,
    UINT vertex_count, UINT instance_count) {
  if (!kStockMenuDirectRenderEnabled || !commands ||
      metadata.render_target_count != 1 || metadata.depth_enabled) {
    return {};
  }
  const auto scoped_menu_draw =
      menu_direct_capture_enabled.load(std::memory_order_relaxed) &&
      menu_draw_scope_depth != 0;
  if (scoped_menu_draw && !metadata.blend_enabled) {
    return {};
  }
  const auto mode = static_cast<darktidevr::core::SharedPresentationMode>(
      current_presentation_mode.load(std::memory_order_relaxed));
  if (mode != darktidevr::core::SharedPresentationMode::flat_menu &&
      mode != darktidevr::core::SharedPresentationMode::world_anchored_menu) {
    return {};
  }

  CommandTrace trace{};
  {
    std::scoped_lock lock(trace_mutex);
    const auto found = command_traces.find(commands);
    if (found == command_traces.end() || found->second.render_target_count != 1 ||
        found->second.render_target == 0 || found->second.depth_target != 0) {
      return {};
    }
    trace = found->second;
  }
  const auto original_descriptor = descriptor_snapshot(trace.render_target);
  auto* original_resource =
      reinterpret_cast<ID3D12Resource*>(original_descriptor.resource);
  if (!original_resource || original_descriptor.width == 0 ||
      original_descriptor.height == 0 ||
      metadata.render_target_format !=
          static_cast<DXGI_FORMAT>(original_descriptor.format)) {
    return {};
  }

  ComPtr<ID3D12Device> device;
  if (FAILED(commands->GetDevice(IID_PPV_ARGS(&device)))) {
    return {};
  }
  {
    std::scoped_lock lock(state_mutex);
    static std::atomic<std::uint64_t> diagnostic_redirect_count{};
    const auto diagnostic_id =
        diagnostic_redirect_count.fetch_add(1, std::memory_order_relaxed) + 1;
    const auto trace_redirect = diagnostic_id <= 2;
    const auto source_description = original_resource->GetDesc();
    // Reject the offscreen HUD canvas before it can seed an alias stream or
    // recreate the shared menu surface. The HUD uses the same UI shaders.
    if (!darktidevr::core::menu_capture_extent_matches(
            source_description.Width, source_description.Height,
            current_presentation_source_width.load(std::memory_order_relaxed),
            current_presentation_source_height.load(std::memory_order_relaxed))) {
      return {};
    }
    static std::atomic<std::uint64_t> candidate_log_count{};
    const auto candidate_id =
        candidate_log_count.fetch_add(1, std::memory_order_relaxed) + 1;
    if (candidate_id <= 5000) {
      write_menu_resource_log(
          "MENU_DRAW_CANDIDATE\tid=%llu\tframe=%llu\tcommands=%p"
          "\tresource=%p\tresource_format=%u\trtv_format=%u"
          "\tvs=%llu\tps=%llu\tvertices=%u\tinstances=%u"
          "\tstream=%s\r\n",
          static_cast<unsigned long long>(candidate_id),
          static_cast<unsigned long long>(
              present_count.load(std::memory_order_relaxed)),
          commands, original_resource,
          static_cast<unsigned>(source_description.Format),
          static_cast<unsigned>(metadata.render_target_format),
          static_cast<unsigned long long>(metadata.vertex_shader),
          static_cast<unsigned long long>(metadata.pixel_shader), vertex_count,
          instance_count,
          source_description.Format == metadata.render_target_format
              ? "typed"
              : "alias");
    }
    // OptionsView records the settings widgets before its typeless
    // category-layer marker. Those content batches use the exact stock widget
    // shader pair below; the other pre-alias pair consists of six fullscreen
    // compositor draws and must stay on the native target. After the alias,
    // retain the complete category/chrome stream as before.
    const auto frame = present_count.load(std::memory_order_relaxed);
    const auto options_armed_frame =
        options_menu_capture_armed_frame.load(std::memory_order_relaxed);
    const bool options_capture_armed =
        options_armed_frame !=
            (std::numeric_limits<std::uint64_t>::max)() &&
        frame >= options_armed_frame && frame - options_armed_frame <= 2;
    const auto alias_stream =
        metadata.render_target_format != DXGI_FORMAT_UNKNOWN &&
        source_description.Format != metadata.render_target_format;
    const auto options_widget_draw =
        !alias_stream &&
        metadata.vertex_shader == kOptionsWidgetShaderPair.vertex_shader &&
        metadata.pixel_shader == kOptionsWidgetShaderPair.pixel_shader;
    options_layer_resources[alias_stream ? 0 : 1].store(
        original_resource, std::memory_order_release);
    if (options_capture_armed) {
      // The Options settings widgets are not replayable in isolation: their
      // draw depends on a retained target that the same command stream later
      // samples. Leave every Options draw on its native target. The resource
      // barrier hook snapshots the completed typeless target after execution.
      return {};
    }
    const auto options_stream = options_widget_draw || alias_stream ||
                                direct_menu_ui_stream_frame == frame;
    if (!options_stream) {
      static std::atomic<std::uint64_t> pre_options_skip_count{};
      const auto skipped =
          pre_options_skip_count.fetch_add(1, std::memory_order_relaxed) + 1;
      if (skipped <= 4) {
        write_menu_resource_log(
            "MENU_REDIRECT_SKIP\treason=before_options_alias"
            "\tsource_format=%u\trtv_format=%u\r\n",
            static_cast<unsigned>(source_description.Format),
            static_cast<unsigned>(metadata.render_target_format));
      }
      return {};
    }
    static std::atomic<std::uint64_t> options_stream_log_count{};
    const auto options_stream_id =
        options_stream_log_count.fetch_add(1, std::memory_order_relaxed) + 1;
    if (options_stream_id <= 5000) {
      write_menu_resource_log(
          "MENU_OPTIONS_STREAM\tid=%llu\tframe=%llu\tcommands=%p"
          "\tresource=%p\tresource_format=%u\trtv_format=%u"
          "\tvs=%llu\tps=%llu\tvertices=%u\tinstances=%u"
          "\tblend=%u\tstage=%s\r\n",
          static_cast<unsigned long long>(options_stream_id),
          static_cast<unsigned long long>(frame), commands, original_resource,
          static_cast<unsigned>(source_description.Format),
          static_cast<unsigned>(metadata.render_target_format),
          static_cast<unsigned long long>(metadata.vertex_shader),
          static_cast<unsigned long long>(metadata.pixel_shader), vertex_count,
          instance_count, metadata.blend_enabled ? 1U : 0U,
          alias_stream ? "alias" : "after_alias");
    }
    if (ensure_menu_surface(device.Get(), source_description,
                            metadata.render_target_format) != 0 ||
        !menu_surface || !menu_rtv_heap) {
      return {};
    }
    if (trace_redirect) {
      write_menu_resource_log(
          "MENU_REDIRECT_STAGE\tid=%llu\tstage=surface_ready\r\n",
          static_cast<unsigned long long>(diagnostic_id));
    }
    // Never overwrite the one-slot mailbox while OpenXR is sampling it.
    const auto menu_consumed =
        menu_consumed_fence ? menu_consumed_fence->GetCompletedValue()
                            : UINT64_MAX;
    if (!darktidevr::core::shared_mailbox_writable(menu_ready_value,
                                                    menu_consumed)) {
      return {};
    }
    if (alias_stream) {
      direct_menu_ui_stream_frame = frame;
    }
    if (trace_redirect) {
      write_menu_resource_log(
          "MENU_REDIRECT_STAGE\tid=%llu\tstage=mailbox_writable\r\n",
          static_cast<unsigned long long>(diagnostic_id));
    }
    if (direct_menu_render_lists.find(commands) ==
        direct_menu_render_lists.end()) {
      D3D12_RESOURCE_BARRIER barrier{};
      barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      barrier.Transition.pResource = menu_surface.Get();
      barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
      barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
      barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
      commands->ResourceBarrier(1, &barrier);
      if (trace_redirect) {
        write_menu_resource_log(
            "MENU_REDIRECT_STAGE\tid=%llu\tstage=barrier_recorded\r\n",
            static_cast<unsigned long long>(diagnostic_id));
      }
      if (direct_menu_clear_frame != frame) {
        constexpr FLOAT transparent[4]{0.0F, 0.0F, 0.0F, 0.0F};
        commands->ClearRenderTargetView(menu_rtv, transparent, 0, nullptr);
        direct_menu_clear_frame = frame;
        if (trace_redirect) {
          write_menu_resource_log(
              "MENU_REDIRECT_STAGE\tid=%llu\tstage=clear_recorded\r\n",
              static_cast<unsigned long long>(diagnostic_id));
        }
      }
      const auto insertion =
          direct_menu_render_lists.emplace(commands, menu_surface);
      if (insertion.second) {
        direct_menu_render_list_count.fetch_add(1, std::memory_order_release);
      }
    }
    direct_menu_render_frame.store(present_count.load(std::memory_order_relaxed),
                                   std::memory_order_relaxed);
    original_om_set_render_targets(commands, 1, &menu_rtv, FALSE, nullptr);
    if (trace_redirect) {
      write_menu_resource_log(
          "MENU_REDIRECT_STAGE\tid=%llu\tstage=target_bound\r\n",
          static_cast<unsigned long long>(diagnostic_id));
    }
    MenuDrawRedirect redirect{};
    redirect.active = true;
    redirect.original_target = {trace.render_target};
    redirect.capture_target = menu_rtv;
    redirect.original_resource = original_resource;
    redirect.capture_resource = menu_surface;
    redirect.diagnostic_id = diagnostic_id;
    return redirect;
  }
}

void end_stock_menu_draw_redirect(ID3D12GraphicsCommandList* commands,
                                  const MenuDrawRedirect& redirect) {
  if (!redirect.active || !commands) {
    return;
  }
  original_om_set_render_targets(commands, 1, &redirect.original_target, FALSE,
                                 nullptr);
}

int capture_menu_from_resource(ID3D12CommandQueue* queue,
                               ID3D12Resource* source,
                               D3D12_RESOURCE_STATES source_state,
                               std::uint64_t capture_width,
                               UINT capture_height) {
  if (!queue || !source) {
    return 93;
  }
  ComPtr<ID3D12Device> device;
  if (FAILED(source->GetDevice(IID_PPV_ARGS(&device)))) {
    return 94;
  }

  ComPtr<ID3D12Resource> destination;
  ComPtr<ID3D12Fence> fence;
  PendingCapture pending;
  std::uint64_t signal_value{};
  {
    std::scoped_lock lock(state_mutex);
    auto capture_description = source->GetDesc();
    if (capture_width != 0) {
      capture_description.Width =
          (std::min)(capture_description.Width, capture_width);
    }
    if (capture_height != 0) {
      capture_description.Height =
          (std::min)(capture_description.Height, capture_height);
    }
    const auto ensure_result = ensure_menu_surface(
        device.Get(), capture_description,
        static_cast<DXGI_FORMAT>(
            darktidevr::core::canonical_shared_copy_format(
                static_cast<std::uint32_t>(capture_description.Format))));
    if (ensure_result != 0) {
      return ensure_result;
    }
    const auto completed = menu_ready_fence->GetCompletedValue();
    while (!menu_pending_captures.empty() &&
           menu_pending_captures.front().fence_value <= completed) {
      menu_pending_captures.front().fence_value = 0;
      menu_available_captures.push_back(
          std::move(menu_pending_captures.front()));
      menu_pending_captures.pop_front();
    }
    // A single-slot mailbox intentionally drops producer frames rather than
    // stalling the game queue while OpenXR is between frames or inactive.
    if (!darktidevr::core::shared_mailbox_writable(
            menu_ready_value, menu_consumed_fence->GetCompletedValue())) {
      return 0;
    }
    if (!menu_available_captures.empty()) {
      pending = std::move(menu_available_captures.front());
      menu_available_captures.pop_front();
    }
    destination = menu_surface;
    fence = menu_ready_fence;
    signal_value = menu_ready_value + 1;
  }

  if (pending.allocator && pending.commands) {
    if (FAILED(pending.allocator->Reset()) ||
        FAILED(pending.commands->Reset(pending.allocator.Get(), nullptr))) {
      return 95;
    }
  } else if (FAILED(device->CreateCommandAllocator(
                 D3D12_COMMAND_LIST_TYPE_DIRECT,
                 IID_PPV_ARGS(&pending.allocator))) ||
             FAILED(device->CreateCommandList(
                 0, D3D12_COMMAND_LIST_TYPE_DIRECT, pending.allocator.Get(),
                 nullptr, IID_PPV_ARGS(&pending.commands)))) {
    return 95;
  }

  D3D12_RESOURCE_BARRIER source_barrier{};
  source_barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  source_barrier.Transition.pResource = source;
  source_barrier.Transition.StateBefore = source_state;
  source_barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
  source_barrier.Transition.Subresource =
      D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  pending.commands->ResourceBarrier(1, &source_barrier);
  D3D12_RESOURCE_BARRIER destination_barrier{};
  destination_barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  destination_barrier.Transition.pResource = destination.Get();
  destination_barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
  destination_barrier.Transition.StateAfter =
      D3D12_RESOURCE_STATE_COPY_DEST;
  destination_barrier.Transition.Subresource =
      D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  pending.commands->ResourceBarrier(1, &destination_barrier);
  const auto source_description = source->GetDesc();
  const auto destination_description = destination->GetDesc();
  if (source_description.Width == destination_description.Width &&
      source_description.Height == destination_description.Height) {
    pending.commands->CopyResource(destination.Get(), source);
  } else {
    D3D12_TEXTURE_COPY_LOCATION destination_location{};
    destination_location.pResource = destination.Get();
    destination_location.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    D3D12_TEXTURE_COPY_LOCATION source_location{};
    source_location.pResource = source;
    source_location.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    D3D12_BOX source_box{};
    source_box.right = static_cast<UINT>(destination_description.Width);
    source_box.bottom = destination_description.Height;
    source_box.back = 1;
    pending.commands->CopyTextureRegion(&destination_location, 0, 0, 0,
                                        &source_location, &source_box);
  }
  std::swap(destination_barrier.Transition.StateBefore,
            destination_barrier.Transition.StateAfter);
  pending.commands->ResourceBarrier(1, &destination_barrier);
  std::swap(source_barrier.Transition.StateBefore,
            source_barrier.Transition.StateAfter);
  pending.commands->ResourceBarrier(1, &source_barrier);
  if (FAILED(pending.commands->Close())) {
    return 96;
  }
  ID3D12CommandList* command_lists[]{pending.commands.Get()};
  original_execute_command_lists(queue, 1, command_lists);
  if (FAILED(queue->Signal(fence.Get(), signal_value))) {
    std::scoped_lock lock(state_mutex);
    reset_menu_surface_resources();
    return 97;
  }
  pending.fence_value = signal_value;
  {
    std::scoped_lock lock(state_mutex);
    menu_pending_captures.push_back(std::move(pending));
    menu_ready_value = signal_value;
  }
  return 0;
}

int ensure_eye_surfaces(ID3D12Device* device,
                        const D3D12_RESOURCE_DESC& source_description,
                        std::uint64_t eye_width = 0,
                        UINT eye_height = 0) {
  if (source_description.Width < 2) {
    return 25;
  }
  if (eye_width == 0) {
    eye_width = source_description.Width / 2;
  }
  if (eye_height == 0) {
    eye_height = source_description.Height;
  }
  const auto shared_format = static_cast<DXGI_FORMAT>(
      darktidevr::core::canonical_shared_copy_format(
          static_cast<std::uint32_t>(source_description.Format)));
  const bool matching_surfaces = eye_surfaces[0] && eye_surfaces[1] &&
      eye_handles[0] && eye_handles[1] &&
      eye_surfaces[0]->GetDesc().Width == eye_width &&
      eye_surfaces[0]->GetDesc().Height == eye_height &&
      eye_surfaces[0]->GetDesc().Format == shared_format &&
      eye_surfaces[1]->GetDesc().Width == eye_width &&
      eye_surfaces[1]->GetDesc().Height == eye_height &&
      eye_surfaces[1]->GetDesc().Format == shared_format;
  const bool shared_fences_healthy =
      ready_fence && consumed_fence && ready_fence_handle &&
      consumed_fence_handle &&
      ready_fence->GetCompletedValue() != UINT64_MAX &&
      consumed_fence->GetCompletedValue() != UINT64_MAX;
  if (matching_surfaces && shared_fences_healthy) {
    return 0;
  }
  if (matching_surfaces && !shared_fences_healthy) {
    // A shared D3D12 fence becomes permanently poisoned when an attached
    // consumer device disappears without a graceful queue drain (for example,
    // restarting only the XR bridge). GetCompletedValue reports UINT64_MAX in
    // that state. Recreate the producer-owned mailbox under the same names so
    // a later bridge can attach to a healthy generation without restarting
    // Darktide.
    write_boundary_census_log(
        "frame=%llu\tSHARED_EYE_RECREATE\treason=poisoned_fence\r\n",
        present_count.load(std::memory_order_relaxed));
  }

  reset_eye_surface_resources();

  D3D12_HEAP_PROPERTIES heap{};
  heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  auto eye_description = source_description;
  eye_description.Format = shared_format;
  eye_description.Width = eye_width;
  eye_description.Height = eye_height;
  eye_description.Flags = D3D12_RESOURCE_FLAG_NONE;
  eye_description.MipLevels = 1;
  eye_description.SampleDesc.Count = 1;
  const std::array<const wchar_t*, 2> names{kLeftEyeName, kRightEyeName};
  for (std::size_t eye = 0; eye < eye_surfaces.size(); ++eye) {
    if (FAILED(device->CreateCommittedResource(
            &heap, D3D12_HEAP_FLAG_SHARED, &eye_description,
            D3D12_RESOURCE_STATE_COMMON, nullptr,
            IID_PPV_ARGS(&eye_surfaces[eye])))) {
      reset_eye_surface_resources();
      return 20 + static_cast<int>(eye);
    }
    if (FAILED(device->CreateSharedHandle(eye_surfaces[eye].Get(), nullptr,
                                          GENERIC_ALL, names[eye],
                                          &eye_handles[eye]))) {
      reset_eye_surface_resources();
      return 22 + static_cast<int>(eye);
    }
  }
  if (FAILED(device->CreateCommittedResource(
          &heap, D3D12_HEAP_FLAG_NONE, &eye_description,
          D3D12_RESOURCE_STATE_COMMON, nullptr,
          IID_PPV_ARGS(&desktop_mirror_surface))) ||
      FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                 IID_PPV_ARGS(&desktop_mirror_fence)))) {
    reset_eye_surface_resources();
    return 26;
  }
  if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                                 IID_PPV_ARGS(&ready_fence))) ||
      FAILED(device->CreateSharedHandle(ready_fence.Get(), nullptr, GENERIC_ALL,
                                        kReadyFenceName,
                                        &ready_fence_handle))) {
    reset_eye_surface_resources();
    return 24;
  }
  if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                                 IID_PPV_ARGS(&consumed_fence))) ||
      FAILED(device->CreateSharedHandle(
          consumed_fence.Get(), nullptr, GENERIC_ALL, kConsumedFenceName,
          &consumed_fence_handle))) {
    reset_eye_surface_resources();
    return 25;
  }
  const auto surface_generation =
      shared_head_pose_reader().advance_eye_surface_generation();
  if (surface_generation != 0) {
    write_boundary_census_log(
        "frame=%llu\tSHARED_EYE_GENERATION\tgeneration=%llu\r\n",
        present_count.load(std::memory_order_relaxed),
        static_cast<unsigned long long>(surface_generation));
  }
  return 0;
}

int capture_eye_from_resource(int eye, ID3D12CommandQueue* supplied_queue,
                              ID3D12Resource* supplied_back_buffer,
                              bool bypass_execute_hook,
                              D3D12_RESOURCE_STATES source_state) {
  if (eye < 0 || eye > 1) {
    return 30;
  }
  capture_stage.store(1, std::memory_order_relaxed);
  ComPtr<ID3D12CommandQueue> queue;
  ComPtr<ID3D12Resource> back_buffer;
  if (supplied_queue && supplied_back_buffer) {
    queue = supplied_queue;
    back_buffer = supplied_back_buffer;
  } else {
    ComPtr<IDXGISwapChain3> swapchain;
    std::scoped_lock lock(state_mutex);
    queue = game_queue;
    swapchain = game_swapchain;
    if (swapchain &&
        FAILED(swapchain->GetBuffer(swapchain->GetCurrentBackBufferIndex(),
                                    IID_PPV_ARGS(&back_buffer)))) {
      return 32;
    }
  }
  if (!queue || !back_buffer) {
    return 31;
  }

  capture_stage.store(2, std::memory_order_relaxed);
  ComPtr<ID3D12Device> device;
  if (FAILED(back_buffer->GetDevice(IID_PPV_ARGS(&device)))) {
    return 32;
  }
  const auto source_description = back_buffer->GetDesc();
  const bool isolated_eye = streamline_eye_target_probe_requested.load(
      std::memory_order_acquire);
  if (isolated_eye) {
    const auto expected_width = camera_input_width.load(std::memory_order_relaxed);
    const auto expected_height = camera_input_height.load(std::memory_order_relaxed);
    const auto named_eye = named_eye_final_index(back_buffer.Get());
    const bool valid = darktidevr::core::streamline_isolated_eye_matches(
        eye, named_eye, source_description.Width, source_description.Height,
        expected_width, expected_height);
    static std::array<std::atomic<std::uint64_t>, 2> checks{};
    const auto check = checks[static_cast<std::size_t>(eye)].fetch_add(
        1, std::memory_order_relaxed);
    if (check < 8 || check % 120 == 0 || trace_streamline_submission_images()) {
      write_streamline_probe_log(
          "ISOLATED_EYE_CAPTURE\teye=%d\tnamed_eye=%d\tsource=%llux%u"
          "\texpected=%ux%u\tvalid=%u\tcropped=0\r\n",
          eye, named_eye, static_cast<unsigned long long>(source_description.Width),
          source_description.Height, expected_width, expected_height, valid ? 1U : 0U);
    }
    if (!valid) return 39;
  }
  // The feasibility path historically rendered each full-origin eye into a
  // 3840x2160 intermediate and retained its central 1920x2160 region. A
  // portrait/square eye-sized intermediate has no unused side regions, so
  // preserve its complete width. This lets the game render only pixels that
  // are transported to OpenXR while leaving the known-good 4K path unchanged.
  const bool source_is_eye_sized =
      isolated_eye || source_description.Width <= source_description.Height;
  const auto captured_width = static_cast<UINT64>(
      source_is_eye_sized ? source_description.Width
                          : source_description.Width / 2);

  capture_stage.store(3, std::memory_order_relaxed);
  ComPtr<ID3D12Resource> eye_surface;
  ComPtr<ID3D12Resource> mirror_surface;
  ComPtr<ID3D12Resource> mirror_source;
  ComPtr<ID3D12Fence> fence;
  {
    std::scoped_lock lock(state_mutex);
    const auto surface_result =
        ensure_eye_surfaces(device.Get(), source_description,
                            captured_width,
                            source_description.Height);
    if (surface_result != 0) {
      return surface_result;
    }
    const auto completed = ready_fence->GetCompletedValue();
    while (!pending_captures.empty() &&
           pending_captures.front().fence_value <= completed) {
      pending_captures.front().fence_value = 0;
      available_captures.push_back(std::move(pending_captures.front()));
      pending_captures.pop_front();
    }
    if (pending_captures.size() >= 16) {
      return 36;
    }
    if (eye == 0 && !darktidevr::core::shared_mailbox_writable(
                        ready_value, consumed_fence->GetCompletedValue())) {
      staged_pair_dropped = true;
      return 0;
    }
    if (eye == 0) {
      staged_pair_dropped = false;
    }
    if (eye == 1 && staged_pair_dropped) {
      staged_pair_dropped = false;
      return 0;
    }
    if ((eye == 0 && staged_eye0_capture_valid) ||
        (eye == 1 && !staged_eye0_capture_valid)) {
      return 37;
    }
    eye_surface = eye_surfaces[static_cast<std::size_t>(eye)];
    if (eye == 1) {
      mirror_surface = desktop_mirror_surface;
      mirror_source = eye_surfaces[0];
    }
    fence = ready_fence;
  }

  capture_stage.store(4, std::memory_order_relaxed);
  PendingCapture pending;
  {
    std::scoped_lock lock(state_mutex);
    if (!available_captures.empty()) {
      pending = std::move(available_captures.front());
      available_captures.pop_front();
    }
  }
  if (pending.allocator && pending.commands) {
    if (FAILED(pending.allocator->Reset()) ||
        FAILED(pending.commands->Reset(pending.allocator.Get(), nullptr))) {
      return 33;
    }
  } else {
    if (FAILED(device->CreateCommandAllocator(
            D3D12_COMMAND_LIST_TYPE_DIRECT,
            IID_PPV_ARGS(&pending.allocator))) ||
        FAILED(device->CreateCommandList(
            0, D3D12_COMMAND_LIST_TYPE_DIRECT, pending.allocator.Get(),
            nullptr, IID_PPV_ARGS(&pending.commands)))) {
      return 33;
    }
  }

  capture_stage.store(5, std::memory_order_relaxed);
  D3D12_RESOURCE_BARRIER barrier{};
  barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barrier.Transition.pResource = back_buffer.Get();
  // The caller supplies the source's state at the observed queue boundary:
  // PRESENT for the legacy back-buffer path, RENDER_TARGET for the completed
  // per-camera intermediate worker submission.
  barrier.Transition.StateBefore = source_state;
  barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
  barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  pending.commands->ResourceBarrier(1, &barrier);
  D3D12_RESOURCE_BARRIER destination_barrier{};
  destination_barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  destination_barrier.Transition.pResource = eye_surface.Get();
  destination_barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
  destination_barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_DEST;
  destination_barrier.Transition.Subresource =
      D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  pending.commands->ResourceBarrier(1, &destination_barrier);
  D3D12_TEXTURE_COPY_LOCATION destination{};
  destination.pResource = eye_surface.Get();
  destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
  D3D12_TEXTURE_COPY_LOCATION source{};
  source.pResource = back_buffer.Get();
  source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
  const auto eye_width = static_cast<UINT>(captured_width);
  const auto left = source_is_eye_sized
                        ? 0U
                        : static_cast<UINT>(
                              (source_description.Width - eye_width) / 2);
  const D3D12_BOX source_box{left, 0, 0, left + eye_width,
                             source_description.Height, 1};
  pending.commands->CopyTextureRegion(&destination, 0, 0, 0, &source,
                                      &source_box);
  std::swap(destination_barrier.Transition.StateBefore,
            destination_barrier.Transition.StateAfter);
  pending.commands->ResourceBarrier(1, &destination_barrier);
  if (eye == 1 && mirror_surface && mirror_source) {
    std::array<D3D12_RESOURCE_BARRIER, 2> mirror_barriers{};
    mirror_barriers[0].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    mirror_barriers[0].Transition.pResource = mirror_source.Get();
    mirror_barriers[0].Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
    mirror_barriers[0].Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
    mirror_barriers[0].Transition.Subresource =
        D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    mirror_barriers[1].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    mirror_barriers[1].Transition.pResource = mirror_surface.Get();
    mirror_barriers[1].Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
    mirror_barriers[1].Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_DEST;
    mirror_barriers[1].Transition.Subresource =
        D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    pending.commands->ResourceBarrier(
        static_cast<UINT>(mirror_barriers.size()), mirror_barriers.data());
    D3D12_TEXTURE_COPY_LOCATION mirror_destination{};
    mirror_destination.pResource = mirror_surface.Get();
    mirror_destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    D3D12_TEXTURE_COPY_LOCATION mirror_left_eye{};
    mirror_left_eye.pResource = mirror_source.Get();
    mirror_left_eye.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    pending.commands->CopyTextureRegion(&mirror_destination, 0, 0, 0,
                                        &mirror_left_eye, nullptr);
    for (auto& mirror_barrier : mirror_barriers) {
      std::swap(mirror_barrier.Transition.StateBefore,
                mirror_barrier.Transition.StateAfter);
    }
    pending.commands->ResourceBarrier(
        static_cast<UINT>(mirror_barriers.size()), mirror_barriers.data());
  }
  std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
  pending.commands->ResourceBarrier(1, &barrier);
  if (FAILED(pending.commands->Close())) {
    return 34;
  }
  capture_stage.store(6, std::memory_order_relaxed);
  ID3D12CommandList* lists[]{pending.commands.Get()};
  if (bypass_execute_hook) {
    original_execute_command_lists(queue.Get(), 1, lists);
  } else {
    queue->ExecuteCommandLists(1, lists);
  }
  if (eye == 0) {
    std::scoped_lock lock(state_mutex);
    staged_eye0_capture = std::move(pending);
    staged_eye0_capture_valid = true;
    capture_stage.store(8, std::memory_order_relaxed);
    return 0;
  }

  capture_stage.store(7, std::memory_order_relaxed);
  std::uint64_t signal_value{};
  {
    std::scoped_lock lock(state_mutex);
    signal_value = ready_value + 1;
  }
  if (FAILED(queue->Signal(fence.Get(), signal_value))) {
    std::scoped_lock lock(state_mutex);
    reset_eye_surface_resources();
    return 35;
  }
  pending.fence_value = signal_value;
  {
    std::scoped_lock lock(state_mutex);
    staged_eye0_capture.fence_value = signal_value;
    pending_captures.push_back(std::move(staged_eye0_capture));
    staged_eye0_capture_valid = false;
    pending_captures.push_back(std::move(pending));
    ready_value = signal_value;
    desktop_mirror_ready.store(mirror_surface != nullptr,
                               std::memory_order_release);
  }
  capture_stage.store(8, std::memory_order_relaxed);
  return 0;
}

int capture_eye(int eye) {
  return capture_eye_from_resource(eye, nullptr, nullptr, false,
                                   D3D12_RESOURCE_STATE_PRESENT);
}

int capture_armed_eye_from_swapchain(int eye) {
  if (eye < 0 || eye > 1) {
    return 80;
  }

  ArmedEyeCapture requested{};
  {
    std::scoped_lock lock(boundary_capture_mutex);
    if (armed_eye_captures.empty()) {
      return 81;
    }
    if (armed_eye_captures.front().eye != eye) {
      return 82;
    }
    requested = armed_eye_captures.front();
    armed_eye_captures.pop_front();
  }

  ComPtr<ID3D12CommandQueue> queue;
  ComPtr<IDXGISwapChain3> swapchain;
  {
    std::scoped_lock lock(state_mutex);
    queue = game_queue;
    swapchain = game_swapchain;
  }
  if (!queue || !swapchain) {
    return 83;
  }

  ComPtr<ID3D12Resource> back_buffer;
  if (FAILED(swapchain->GetBuffer(swapchain->GetCurrentBackBufferIndex(),
                                  IID_PPV_ARGS(&back_buffer)))) {
    return 84;
  }

  D3D12_RESOURCE_STATES source_state{};
  {
    std::scoped_lock lock(boundary_capture_mutex);
    const auto found = swapchain_back_buffer_states.find(back_buffer.Get());
    if (found == swapchain_back_buffer_states.end()) {
      return 85;
    }
    source_state = found->second;
  }
  if (source_state != D3D12_RESOURCE_STATE_RENDER_TARGET &&
      source_state != D3D12_RESOURCE_STATE_PRESENT) {
    return 86;
  }

  std::uint64_t ready_before{};
  {
    std::scoped_lock lock(state_mutex);
    ready_before = ready_value;
  }
  const auto result = capture_eye_from_resource(
      eye, queue.Get(), back_buffer.Get(), true, source_state);
  boundary_last_capture_result.store(result, std::memory_order_relaxed);
  if (result != 0) {
    return result;
  }

  boundary_eye_capture_counts[static_cast<std::size_t>(eye)].fetch_add(
      1, std::memory_order_relaxed);
  boundary_eye_pose_sequences[static_cast<std::size_t>(eye)].store(
      requested.pose_sequence, std::memory_order_relaxed);
  if (eye == 0) {
    boundary_staged_eye0_pose_sequence.store(requested.pose_sequence,
                                              std::memory_order_relaxed);
    boundary_staged_eye0_vertical_fov.store(requested.vertical_fov_radians,
                                             std::memory_order_relaxed);
    boundary_staged_eye0_aspect_ratio.store(requested.aspect_ratio,
                                            std::memory_order_relaxed);
  } else {
    std::uint64_t ready_after{};
    {
      std::scoped_lock lock(state_mutex);
      ready_after = ready_value;
    }
    if (ready_after > ready_before) {
      boundary_published_pair_pose.store(requested.pose_sequence);
      (void)shared_head_pose_reader().publish_rendered_pair(
          {ready_after,
           current_gameplay_generation.load(std::memory_order_acquire),
           {boundary_staged_eye0_pose_sequence.load(std::memory_order_relaxed),
            requested.pose_sequence},
           {boundary_staged_eye0_vertical_fov.load(std::memory_order_relaxed),
            requested.vertical_fov_radians},
           {boundary_staged_eye0_aspect_ratio.load(std::memory_order_relaxed),
            requested.aspect_ratio}});
    }
  }
  return 0;
}

int capture_present_halves(IDXGISwapChain3* swapchain,
                           ID3D12CommandQueue* queue) {
  ComPtr<ID3D12Device> device;
  ComPtr<ID3D12Resource> back_buffer;
  if (FAILED(swapchain->GetDevice(IID_PPV_ARGS(&device))) ||
      FAILED(swapchain->GetBuffer(swapchain->GetCurrentBackBufferIndex(),
                                  IID_PPV_ARGS(&back_buffer)))) {
    return 50;
  }
  const auto source_description = back_buffer->GetDesc();
  const auto alternating =
      alternating_full_capture_enabled.load(std::memory_order_relaxed);
  const auto top_bottom =
      top_bottom_capture_enabled.load(std::memory_order_relaxed);
  const auto alternating_eye =
      alternating_present_eye.load(std::memory_order_relaxed);
  if (alternating && (alternating_eye < 0 || alternating_eye > 1)) {
    return 55;
  }
  std::array<ComPtr<ID3D12Resource>, 2> surfaces;
  ComPtr<ID3D12Fence> fence;
  std::uint64_t signal_value{};
  {
    std::scoped_lock lock(state_mutex);
    const auto surface_result =
        ensure_eye_surfaces(
            device.Get(), source_description,
            (alternating || top_bottom) ? source_description.Width
                                        : source_description.Width / 2,
            top_bottom ? source_description.Height / 2
                       : source_description.Height);
    if (surface_result != 0) {
      return surface_result;
    }
    const auto completed = ready_fence->GetCompletedValue();
    while (!pending_captures.empty() &&
           pending_captures.front().fence_value <= completed) {
      pending_captures.pop_front();
    }
    if (pending_captures.size() >= 8) {
      return 51;
    }
    if (!darktidevr::core::shared_mailbox_writable(
            ready_value, consumed_fence->GetCompletedValue())) {
      // All present-derived modes share the same single eye-pair slot. Drop
      // producer frames until OpenXR has finished copying the published pair.
      return 0;
    }
    surfaces = eye_surfaces;
    fence = ready_fence;
    signal_value = ready_value + 1;
  }

  PendingCapture pending;
  if (FAILED(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
                                             IID_PPV_ARGS(&pending.allocator))) ||
      FAILED(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
                                       pending.allocator.Get(), nullptr,
                                       IID_PPV_ARGS(&pending.commands)))) {
    return 52;
  }
  D3D12_RESOURCE_BARRIER barrier{};
  barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barrier.Transition.pResource = back_buffer.Get();
  barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
  barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
  barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  pending.commands->ResourceBarrier(1, &barrier);

  const auto eye_width = static_cast<UINT>(
      (alternating || top_bottom) ? source_description.Width
                                  : source_description.Width / 2);
  const auto eye_height = static_cast<UINT>(
      top_bottom ? source_description.Height / 2 : source_description.Height);
  D3D12_TEXTURE_COPY_LOCATION source{};
  source.pResource = back_buffer.Get();
  source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
  const UINT first_eye = alternating ? static_cast<UINT>(alternating_eye) : 0U;
  const UINT eye_count = alternating ? 1U : 2U;
  for (UINT index = 0; index < eye_count; ++index) {
    const UINT eye = first_eye + index;
    D3D12_RESOURCE_BARRIER destination_barrier{};
    destination_barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    destination_barrier.Transition.pResource = surfaces[eye].Get();
    destination_barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COMMON;
    destination_barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_DEST;
    destination_barrier.Transition.Subresource =
        D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    pending.commands->ResourceBarrier(1, &destination_barrier);
    D3D12_TEXTURE_COPY_LOCATION destination{};
    destination.pResource = surfaces[eye].Get();
    destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    const auto left = (alternating || top_bottom) ? 0U : eye * eye_width;
    const auto top = top_bottom ? eye * eye_height : 0U;
    const D3D12_BOX box{left, top, 0, left + eye_width, top + eye_height, 1};
    pending.commands->CopyTextureRegion(&destination, 0, 0, 0, &source, &box);
    std::swap(destination_barrier.Transition.StateBefore,
              destination_barrier.Transition.StateAfter);
    pending.commands->ResourceBarrier(1, &destination_barrier);
  }
  std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
  pending.commands->ResourceBarrier(1, &barrier);
  if (FAILED(pending.commands->Close())) {
    return 53;
  }
  ID3D12CommandList* lists[]{pending.commands.Get()};
  queue->ExecuteCommandLists(1, lists);
  if (alternating) {
    alternating_eye_copy_counts[static_cast<std::size_t>(alternating_eye)]
        .fetch_add(1, std::memory_order_relaxed);
  }
  bool publish = true;
  if (alternating) {
    const auto bit = 1U << static_cast<unsigned>(alternating_eye);
    const auto seen = alternating_seen_eyes.fetch_or(bit,
                                                     std::memory_order_relaxed) |
                      bit;
    publish = (seen & 3U) == 3U;
  }
  if (publish && FAILED(queue->Signal(fence.Get(), signal_value))) {
    std::scoped_lock lock(state_mutex);
    reset_eye_surface_resources();
    return 54;
  }
  pending.fence_value = signal_value;
  {
    std::scoped_lock lock(state_mutex);
    if (publish) {
      ready_value = signal_value;
    }
    pending_captures.push_back(std::move(pending));
  }
  return 0;
}

bool publish_presentation_state(
    const darktidevr::core::SharedPresentationState& state) {
  try {
    static darktidevr::core::SharedPresentationStateWriter writer;
    static std::atomic<std::uint64_t> transport_sequence{0};
    auto published = state;
    published.sequence =
        transport_sequence.fetch_add(1, std::memory_order_relaxed) + 1;
    return writer.publish(published);
  } catch (...) {
    return false;
  }
}

bool publish_gameplay_aim_state(float distance_metres, bool active, bool hit,
    bool target_point_valid = false, darktidevr::math::Vec3 target_point = {},
    std::uint64_t head_sequence = 0, std::uint64_t head_generation = 0,
    std::uint32_t recenter_generation = 0) {
  try {
    static darktidevr::core::SharedGameplayAimStateWriter writer;
    static std::atomic<std::uint64_t> transport_sequence{0};
    const auto timestamp_ns = static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now().time_since_epoch())
            .count());
    const darktidevr::core::SharedGameplayAimState state{
        transport_sequence.fetch_add(1, std::memory_order_relaxed) + 1,
        timestamp_ns,
        active ? distance_metres : 0.0F,
        active,
        active && hit, 0, active && target_point_valid, target_point,
        head_sequence, head_generation, recenter_generation};
    return writer.publish(state);
  } catch (...) {
    return false;
  }
}

}  // namespace

extern "C" __declspec(dllexport) int dtvr_install() { return install_hooks(); }
extern "C" __declspec(dllexport) int dtvr_set_gameplay_aim_state(
    int active, int hit, float distance_metres) {
  if (active != 0 && active != 1) {
    return 1;
  }
  if (hit != 0 && hit != 1) {
    return 2;
  }
  return publish_gameplay_aim_state(distance_metres, active != 0, hit != 0)
             ? 0
             : 3;
}
extern "C" __declspec(dllexport) int dtvr_set_gameplay_aim_target(
    int hit, float distance_metres, float x, float y, float z,
    unsigned long long head_sequence, unsigned long long head_generation,
    unsigned int recenter_generation) {
  if (hit != 0 && hit != 1) return 2;
  return publish_gameplay_aim_state(distance_metres, true, hit != 0, true,
      {x, y, z}, head_sequence, head_generation, recenter_generation) ? 0 : 3;
}
extern "C" __declspec(dllexport) int dtvr_commit_gameplay_generation(
    unsigned long long generation) {
  if (generation == 0) {
    return 1;
  }
  current_gameplay_generation.store(generation, std::memory_order_release);
  return shared_head_pose_reader().publish_gameplay_generation(generation)
             ? 0
             : 2;
}
extern "C" __declspec(dllexport) int
dtvr_install_for_device(ID3D12Device* device) {
  return device ? install_hooks(device) : 20;
}
extern "C" __declspec(dllexport) int dtvr_set_projection_active(int enabled) {
  const auto event = shared_projection_active_event();
  if (!event) {
    return 1;
  }
  const auto event_result = enabled ? SetEvent(event) : ResetEvent(event);
  const darktidevr::core::SharedPresentationState state{
      1,
      enabled
          ? darktidevr::core::SharedPresentationMode::stereo_world
          : darktidevr::core::SharedPresentationMode::flat_loading_or_cinematic,
      1, 1, 0, 0, 1, 1, 2.0F, 2.0F};
  current_presentation_mode.store(static_cast<unsigned int>(state.mode),
                                  std::memory_order_relaxed);
  current_presentation_source_width.store(state.source_width,
                                          std::memory_order_relaxed);
  current_presentation_source_height.store(state.source_height,
                                           std::memory_order_relaxed);
  if (!publish_presentation_state(state)) {
    return 3;
  }
  return event_result ? 0 : 2;
}
extern "C" __declspec(dllexport) int dtvr_set_presentation_state(
    unsigned int mode, unsigned long long sequence, unsigned int source_width,
    unsigned int source_height, unsigned int crop_x, unsigned int crop_y,
    unsigned int crop_width, unsigned int crop_height,
    float maximum_panel_width_metres, float maximum_panel_height_metres) {
  const darktidevr::core::SharedPresentationState state{
      sequence,
      static_cast<darktidevr::core::SharedPresentationMode>(mode),
      source_width,
      source_height,
      crop_x,
      crop_y,
      crop_width,
      crop_height,
      maximum_panel_width_metres,
      maximum_panel_height_metres};
  if (!darktidevr::core::valid_presentation_state(state)) {
    return 1;
  }
  current_presentation_mode.store(static_cast<unsigned int>(state.mode),
                                  std::memory_order_relaxed);
  current_presentation_source_width.store(state.source_width,
                                          std::memory_order_relaxed);
  current_presentation_source_height.store(state.source_height,
                                           std::memory_order_relaxed);
  if (!publish_presentation_state(state)) {
    return 2;
  }

  const auto event = shared_projection_active_event();
  if (!event) {
    return 3;
  }
  // Interactive menu modes are overlays on the live stereo projection. Do
  // not conflate "show a quad" with "release the projection producer";
  // doing so lets menu open/close perturb eye ownership and produces
  // frozen/mono transitions. Only loading/cinematic presentation suspends the
  // immersive projection.
  const auto projection_active =
      darktidevr::core::immersive_projection_active(state.mode);
  return (projection_active ? SetEvent(event) : ResetEvent(event)) ? 0 : 4;
}
extern "C" __declspec(dllexport) int dtvr_set_presentation_state_v2(
    unsigned int mode, unsigned long long sequence, unsigned int source_width,
    unsigned int source_height, unsigned int crop_x, unsigned int crop_y,
    unsigned int crop_width, unsigned int crop_height,
    float maximum_panel_width_metres, float maximum_panel_height_metres,
    int body_panel_pose_valid, float panel_x, float panel_y, float panel_z,
    float panel_qx, float panel_qy, float panel_qz, float panel_qw) {
  const darktidevr::core::SharedPresentationState state{
      sequence,
      static_cast<darktidevr::core::SharedPresentationMode>(mode),
      source_width,
      source_height,
      crop_x,
      crop_y,
      crop_width,
      crop_height,
      maximum_panel_width_metres,
      maximum_panel_height_metres,
      body_panel_pose_valid != 0,
      {{panel_qx, panel_qy, panel_qz, panel_qw},
       {panel_x, panel_y, panel_z}}};
  if (!darktidevr::core::valid_presentation_state(state)) {
    return 1;
  }
  current_presentation_mode.store(static_cast<unsigned int>(state.mode),
                                  std::memory_order_relaxed);
  current_presentation_source_width.store(state.source_width,
                                          std::memory_order_relaxed);
  current_presentation_source_height.store(state.source_height,
                                           std::memory_order_relaxed);
  if (!publish_presentation_state(state)) {
    return 2;
  }
  const auto event = shared_projection_active_event();
  if (!event) {
    return 3;
  }
  const auto projection_active =
      darktidevr::core::immersive_projection_active(state.mode);
  return (projection_active ? SetEvent(event) : ResetEvent(event)) ? 0 : 4;
}
extern "C" __declspec(dllexport) int
dtvr_set_menu_draw_scope(int enabled) {
  if (enabled) {
    ++menu_draw_scope_depth;
  } else if (menu_draw_scope_depth != 0) {
    --menu_draw_scope_depth;
  }
  return static_cast<int>(menu_draw_scope_depth);
}

extern "C" __declspec(dllexport) unsigned long long
dtvr_menu_draw_scope_redirect_count() {
  return menu_draw_scope_redirect_count.load(std::memory_order_relaxed);
}

extern "C" __declspec(dllexport) int
dtvr_arm_options_menu_capture() {
  options_menu_capture_armed_frame.store(
      present_count.load(std::memory_order_relaxed),
      std::memory_order_release);
  return 1;
}

extern "C" __declspec(dllexport) int
dtvr_set_vendor_menu_widget_capture(int enabled) {
  vendor_menu_widget_capture_enabled.store(enabled != 0,
                                           std::memory_order_relaxed);
  return enabled != 0 ? 1 : 0;
}

extern "C" __declspec(dllexport) int __cdecl
dtvr_set_menu_direct_capture(int enabled) {
  const auto requested = enabled != 0;
  const auto previous =
      menu_direct_capture_enabled.exchange(requested, std::memory_order_relaxed);
  if (previous && !requested && marker_log == INVALID_HANDLE_VALUE &&
      !billboard_horizon_lock_enabled.load(std::memory_order_relaxed) &&
      focused_trace_phase.load(std::memory_order_relaxed) == 0) {
    // Runtime-gated hooks stop maintaining command traces outside an
    // interactive menu. Drop their last menu state at the transition so a
    // later enable can only redirect a command list whose PSO/RT state was
    // observed after that enable.
    std::scoped_lock lock(trace_mutex);
    command_traces.clear();
  }
  return requested ? 1 : 0;
}

extern "C" __declspec(dllexport) int
dtvr_set_diagnostic_render_hooks(int enabled) {
  if (hooks_installed.load(std::memory_order_acquire)) {
    return kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed) ==
                   (enabled != 0)
               ? 0
               : 1;
  }
  kInstallDiagnosticRenderHooks.store(enabled != 0,
                                      std::memory_order_release);
  return 0;
}
extern "C" __declspec(dllexport) int
dtvr_set_cluster_light_visibility_fix(int enabled) {
  if (hooks_installed.load(std::memory_order_acquire)) {
    return cluster_light_visibility_fix_requested.load(
               std::memory_order_relaxed) == (enabled != 0)
               ? 0
               : 1;
  }
  cluster_light_visibility_fix_requested.store(enabled != 0,
                                               std::memory_order_release);
  cluster_light_visibility_fix_active.store(false,
                                            std::memory_order_release);
  cluster_light_visibility_fix_candidate_count.store(
      0, std::memory_order_relaxed);
  cluster_light_visibility_fix_patch_count.store(0,
                                                 std::memory_order_relaxed);
  cluster_light_visibility_fix_reject_count.store(0,
                                                  std::memory_order_relaxed);
  cluster_light_visibility_fix_target_draw_count.store(
      0, std::memory_order_relaxed);
  cluster_light_visibility_fix_root_missing_count.store(
      0, std::memory_order_relaxed);
  cluster_light_visibility_fix_resource_missing_count.store(
      0, std::memory_order_relaxed);
  {
    std::scoped_lock lock(cluster_light_visibility_fix_mutex);
    cluster_pending_fov_patches.fill({});
    cluster_pending_fov_patch_cursor = 0;
  }
  return 0;
}
extern "C" __declspec(dllexport) int
dtvr_cluster_light_visibility_fix_active() {
  return cluster_light_visibility_fix_active.load(std::memory_order_acquire)
             ? 1
             : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_cluster_light_visibility_fix_candidate_count() {
  return cluster_light_visibility_fix_candidate_count.load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_cluster_light_visibility_fix_patch_count() {
  return cluster_light_visibility_fix_patch_count.load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_cluster_light_visibility_fix_reject_count() {
  return cluster_light_visibility_fix_reject_count.load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_cluster_light_visibility_fix_target_draw_count() {
  return cluster_light_visibility_fix_target_draw_count.load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_cluster_light_visibility_fix_root_missing_count() {
  return cluster_light_visibility_fix_root_missing_count.load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_cluster_light_visibility_fix_resource_missing_count() {
  return cluster_light_visibility_fix_resource_missing_count.load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) int
dtvr_set_billboard_shader_substitution(int enabled) {
  if (hooks_installed.load(std::memory_order_acquire)) {
    return billboard_shader_substitution_requested.load(
               std::memory_order_relaxed) == (enabled != 0)
               ? 0
               : 1;
  }
  billboard_shader_substitution_requested.store(enabled != 0,
                                                std::memory_order_release);
  billboard_shader_substitution_count.store(0, std::memory_order_relaxed);
  billboard_shader_substitution_reject_count.store(0,
                                                   std::memory_order_relaxed);
  for (auto& count : billboard_shader_substitution_attempt_counts) {
    count.store(0, std::memory_order_relaxed);
  }
  for (auto& count : billboard_shader_substitution_applied_counts) {
    count.store(0, std::memory_order_relaxed);
  }
  for (auto& count :
       billboard_shader_substitution_validation_reject_counts) {
    count.store(0, std::memory_order_relaxed);
  }
  for (auto& count : billboard_shader_substitution_creation_reject_counts) {
    count.store(0, std::memory_order_relaxed);
  }
  if (enabled != 0) {
    load_billboard_shader_replacements();
  } else {
    std::scoped_lock lock(billboard_shader_replacement_mutex);
    billboard_shader_replacements.clear();
  }
  return 0;
}
extern "C" __declspec(dllexport) int
dtvr_set_billboard_pixel_shader_probe(int enabled) {
  if (hooks_installed.load(std::memory_order_acquire)) {
    return billboard_pixel_shader_probe_requested.load(
               std::memory_order_relaxed) == (enabled != 0)
               ? 0
               : 1;
  }
  billboard_pixel_shader_probe_requested.store(enabled != 0,
                                               std::memory_order_release);
  billboard_pixel_shader_probe_attempt_count.store(0,
                                                   std::memory_order_relaxed);
  billboard_pixel_shader_probe_validation_reject_count.store(
      0, std::memory_order_relaxed);
  billboard_pixel_shader_probe_applied_count.store(0,
                                                   std::memory_order_relaxed);
  billboard_pixel_shader_probe_creation_reject_count.store(
      0, std::memory_order_relaxed);
  if (enabled != 0) {
    load_billboard_shader_replacements();
  }
  return 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_pixel_shader_probe_result_count(unsigned int kind) {
  switch (kind) {
    case 0:
      return billboard_pixel_shader_probe_attempt_count.load(
          std::memory_order_relaxed);
    case 1:
      return billboard_pixel_shader_probe_applied_count.load(
          std::memory_order_relaxed);
    case 2:
      return billboard_pixel_shader_probe_validation_reject_count.load(
          std::memory_order_relaxed);
    case 3:
      return billboard_pixel_shader_probe_creation_reject_count.load(
          std::memory_order_relaxed);
    default:
      return 0;
  }
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_shader_substitution_count() {
  return billboard_shader_substitution_count.load(std::memory_order_relaxed);
}
// Offline tooling uses the same gate as runtime vertex substitution. This
// export neither installs hooks nor creates a D3D/OpenXR device.
extern "C" __declspec(dllexport) int dtvr_validate_shader_interface(
    const void* original, unsigned long long original_size,
    const void* replacement, unsigned long long replacement_size) {
  constexpr unsigned long long maximum_size = 64ULL * 1024ULL * 1024ULL;
  if (!original || !replacement || original_size == 0 || replacement_size == 0 ||
      original_size > maximum_size || replacement_size > maximum_size) return 1;
  try {
    return compatible_shader_interfaces(
        {original, static_cast<SIZE_T>(original_size)},
        {replacement, static_cast<SIZE_T>(replacement_size)}) ? 0 : 2;
  } catch (...) {
    return 3;
  }
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_shader_substitution_reject_count() {
  return billboard_shader_substitution_reject_count.load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_shader_substitution_result_count(unsigned int rank,
                                               unsigned int kind) {
  if (rank >= billboard_shader_substitution_attempt_counts.size()) {
    return 0;
  }
  switch (kind) {
    case 0:
      return billboard_shader_substitution_attempt_counts[rank].load(
          std::memory_order_relaxed);
    case 1:
      return billboard_shader_substitution_applied_counts[rank].load(
          std::memory_order_relaxed);
    case 2:
      return billboard_shader_substitution_validation_reject_counts[rank]
          .load(std::memory_order_relaxed);
    case 3:
      return billboard_shader_substitution_creation_reject_counts[rank].load(
          std::memory_order_relaxed);
    default:
      return 0;
  }
}
extern "C" __declspec(dllexport) int dtvr_set_vertex_shader_dump(int enabled) {
  if (hooks_installed.load(std::memory_order_acquire)) {
    return vertex_shader_dump_requested.load(std::memory_order_relaxed) ==
                   (enabled != 0)
               ? 0
               : 1;
  }
  vertex_shader_dump_requested.store(enabled != 0,
                                     std::memory_order_release);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_begin_billboard_draw_readback() {
  try {
    std::scoped_lock lock(billboard_readback_start_mutex);
    if (billboard_readback.load(std::memory_order_acquire)) return 1;
    if (!hooks_installed.load(std::memory_order_acquire) ||
        !kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed) ||
        !billboard_horizon_lock_enabled.load(std::memory_order_relaxed) ||
        !original_begin_render_pass || !original_end_render_pass || !original_enhanced_barrier)
      return 2;
    // The worker and command recordings can outlive a mod reload. Pin code
    // and retain this bounded diagnostic owner until process termination.
    HMODULE pinned{};
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(&dtvr_begin_billboard_draw_readback), &pinned)) return 3;
    wchar_t temporary[MAX_PATH]{};
    const auto length = GetTempPathW(MAX_PATH, temporary);
    if (!length || length >= MAX_PATH) return 3;
    const auto directory = std::filesystem::path(temporary) /
        (L"darktidevr-billboard-readback-" + std::to_wstring(GetCurrentProcessId()) +
         L"-" + std::to_wstring(GetTickCount64()));
    if (!std::filesystem::create_directory(directory)) return 3;
    auto owner = std::make_unique<darktidevr::producer::BillboardDrawReadback>();
    auto* capture = owner.get();
    // Launch the worker before publication, so thread-allocation failure cannot
    // leave live draw hooks with an owner that has already been destroyed.
    std::thread worker([capture, directory] {
      unsigned exported{};
      try {
        for (unsigned attempt = 0; attempt < 480 && exported < 3; ++attempt) {
          for (auto& pixels : capture->collect()) {
            std::ostringstream name;
            name << "pair-" << std::hex << pixels.vertex_shader << '-' << pixels.pixel_shader;
            const auto stem = name.str();
            for (const bool after : {false, true}) {
              const auto& bytes = after ? pixels.after : pixels.before;
              std::ofstream file(directory / (stem + (after ? "-after.bin" : "-before.bin")),
                                 std::ios::binary);
              file.exceptions(std::ios::badbit | std::ios::failbit);
              file.write(reinterpret_cast<const char*>(bytes.data()),
                         static_cast<std::streamsize>(bytes.size()));
              file.close();
            }
            // Write metadata last. Its existence certifies both payload writes.
            std::ofstream meta(directory / (stem + ".json"));
            meta.exceptions(std::ios::badbit | std::ios::failbit);
            meta << "{\"schema_version\":1,\"status\":\"complete\",\"vertex_shader\":\""
                 << std::hex << pixels.vertex_shader << "\",\"pixel_shader\":\""
                 << pixels.pixel_shader << "\",\"width\":" << std::dec << pixels.width
                 << ",\"height\":" << pixels.height << ",\"row_pitch\":" << pixels.row_pitch
                 << ",\"format\":" << static_cast<unsigned>(pixels.format)
                 << ",\"bytes\":" << pixels.before.size()
                 << ",\"source_frame\":" << pixels.source_frame << "}";
            meta.close();
            ++exported;
          }
          std::this_thread::sleep_for(std::chrono::milliseconds(250));
        }
        std::ofstream summary(directory / "session.json");
        summary << "{\"exported_pairs\":" << exported << ",\"limit\":3,\"deadline_seconds\":120}";
      } catch (...) {
        try { std::ofstream(directory / "export-error.txt") << "Readback export failed; incomplete files are not evidence."; }
        catch (...) {}
      }
      billboard_readback_accepting.store(false, std::memory_order_release);
    });
    billboard_readback.store(owner.release(), std::memory_order_release);
    billboard_readback_accepting.store(true, std::memory_order_release);
    worker.detach();
    return 0;
  } catch (...) { return 3; }
}

extern "C" __declspec(dllexport) int dtvr_set_billboard_view_basis(
    float right_x, float right_y, float right_z, float up_x,
    float up_y, float up_z, int enabled) {
  if (enabled < 0 || enabled > 2) {
    return 1;
  }
  if (enabled == 1 && !kAllowRetiredBillboardDescriptorWrites) {
    billboard_basis_write_enabled.store(false, std::memory_order_release);
    billboard_staging_write_enabled.store(false, std::memory_order_release);
    billboard_horizon_lock_enabled.store(false, std::memory_order_release);
    return 2;
  }
  const std::array<float, 6> values{right_x, right_y, right_z,
                                     up_x, up_y, up_z};
  for (std::size_t i = 0; i < values.size(); ++i) {
    billboard_view_basis[i].store(values[i], std::memory_order_relaxed);
  }
  if (enabled != 0 &&
      !billboard_horizon_lock_enabled.load(std::memory_order_relaxed)) {
    billboard_exact_shader_draw_count.store(0, std::memory_order_relaxed);
    billboard_exact_pso_draw_count.store(0, std::memory_order_relaxed);
    for (auto& count : billboard_exact_pso_cbv_slot_counts) {
      count.store(0, std::memory_order_relaxed);
    }
    for (auto& count : billboard_exact_pso_table_slot_counts) {
      count.store(0, std::memory_order_relaxed);
    }
    for (auto& count : billboard_exact_register_counts) {
      count.store(0, std::memory_order_relaxed);
    }
    for (auto& count : billboard_exact_vertex_table_slot_counts) {
      count.store(0, std::memory_order_relaxed);
    }
    for (auto& count : billboard_exact_descriptor_offset_counts) {
      count.store(0, std::memory_order_relaxed);
    }
    for (auto& count : billboard_exact_table_span_counts) {
      count.store(0, std::memory_order_relaxed);
    }
    billboard_exact_cbv_descriptor_count.store(0, std::memory_order_relaxed);
    billboard_exact_buffer_resource_count.store(0, std::memory_order_relaxed);
    for (auto& count : billboard_exact_heap_type_counts) {
      count.store(0, std::memory_order_relaxed);
    }
    billboard_exact_map_success_count.store(0, std::memory_order_relaxed);
    billboard_exact_map_failure_count.store(0, std::memory_order_relaxed);
    billboard_resource_map_count.store(0, std::memory_order_relaxed);
    billboard_resource_map_match_count.store(0, std::memory_order_relaxed);
    billboard_resource_unmap_count.store(0, std::memory_order_relaxed);
    billboard_selected_map_stack_count.store(0, std::memory_order_relaxed);
    billboard_upload_flush_count.store(0, std::memory_order_relaxed);
    billboard_direct_patch_count.store(0, std::memory_order_relaxed);
    billboard_selected_cpu_address.store(0, std::memory_order_relaxed);
    billboard_selected_gpu_address.store(0, std::memory_order_relaxed);
    billboard_selected_size.store(0, std::memory_order_relaxed);
    billboard_cbv_log_count.store(0, std::memory_order_relaxed);
    billboard_staging_log_count.store(0, std::memory_order_relaxed);
    for (auto& count : billboard_shadow_stage_counts) {
      count.store(0, std::memory_order_relaxed);
    }
    for (auto& count : billboard_exact_command_list_type_counts) {
      count.store(0, std::memory_order_relaxed);
    }
    {
      std::scoped_lock lock(buffer_resource_mutex);
      billboard_tested_cbvs.clear();
      billboard_staging_tested_cbvs.clear();
    }
    billboard_exact_root_mapping_count.store(0, std::memory_order_relaxed);
    billboard_root_metadata_draw_count.store(0, std::memory_order_relaxed);
    billboard_table_b2_draw_count.store(0, std::memory_order_relaxed);
    billboard_bound_table_b2_draw_count.store(0, std::memory_order_relaxed);
    billboard_observed_draw_count.store(0, std::memory_order_relaxed);
    billboard_direct_draw_hook_count.store(0, std::memory_order_relaxed);
    for (auto& slot_counts : billboard_observed_stride_counts) {
      for (auto& count : slot_counts) {
        count.store(0, std::memory_order_relaxed);
      }
    }
    billboard_stride_candidate_count.store(0, std::memory_order_relaxed);
    billboard_b1_bound_count.store(0, std::memory_order_relaxed);
    billboard_b2_bound_count.store(0, std::memory_order_relaxed);
    billboard_basis_patch_count.store(0, std::memory_order_relaxed);
  }
  billboard_basis_write_enabled.store(
      enabled == 1 && kAllowRetiredBillboardDescriptorWrites,
                                       std::memory_order_release);
  billboard_staging_write_enabled.store(false, std::memory_order_release);
  billboard_direct_write_enabled.store(false, std::memory_order_release);
  billboard_horizon_lock_enabled.store(enabled == 2,
                                        std::memory_order_release);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_set_billboard_staging_view_basis(
    float right_x, float right_y, float right_z, float up_x, float up_y,
    float up_z, int enabled) {
  if (enabled != 0) {
    // The Stingray flush pointer is a scratch arena, not a byte mirror of the
    // bound upload resource (live comparison: 0 matches / 3825 mismatches).
    // Never arm this retired path.
    billboard_staging_write_enabled.store(false, std::memory_order_release);
    return 4;
  }
  const auto result = dtvr_set_billboard_view_basis(
      right_x, right_y, right_z, up_x, up_y, up_z, enabled ? 2 : 0);
  if (result != 0) {
    return result;
  }
  billboard_staging_write_enabled.store(enabled != 0,
                                        std::memory_order_release);
  return 0;
}
extern "C" __declspec(dllexport) int
dtvr_set_billboard_direct_view_direction(float right_x, float right_y,
                                         int enabled) {
  if (enabled != 0 &&
      !kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed)) {
    billboard_direct_write_enabled.store(false, std::memory_order_release);
    return 3;
  }
  if (!std::isfinite(right_x) || !std::isfinite(right_y)) {
    billboard_direct_write_enabled.store(false, std::memory_order_release);
    return 1;
  }
  const float length_squared = right_x * right_x + right_y * right_y;
  if (enabled != 0 && length_squared < 1.0e-6F) {
    billboard_direct_write_enabled.store(false, std::memory_order_release);
    return 2;
  }
  if (enabled != 0) {
    const float inverse_length = 1.0F / std::sqrt(length_squared);
    const auto normalized_x = right_x * inverse_length;
    const auto normalized_y = right_y * inverse_length;
    const auto result = dtvr_set_billboard_view_basis(
        normalized_x, normalized_y, 0.0F, 0.0F, 0.0F, 1.0F, 2);
    if (result != 0) {
      billboard_direct_write_enabled.store(false, std::memory_order_release);
      return result;
    }
  }
  billboard_direct_write_enabled.store(enabled != 0,
                                       std::memory_order_release);
  return 0;
}

extern "C" __declspec(dllexport) int dtvr_solve_two_bone_ik(
    const float* input, unsigned int input_count, float* output,
    unsigned int output_count, unsigned int* flags) {
  constexpr unsigned int required_input_count = 17;
  constexpr unsigned int required_output_count = 14;
  if (!input || !output || !flags) {
    return 1;
  }
  if (input_count < required_input_count ||
      output_count < required_output_count) {
    return 2;
  }
  darktidevr::core::TwoBoneIkInput request{};
  request.shoulder = {input[0], input[1], input[2]};
  request.wrist_target = {input[3], input[4], input[5]};
  request.pole_target = {input[6], input[7], input[8]};
  request.fallback_direction = {input[9], input[10], input[11]};
  request.fallback_bend_direction = {input[12], input[13], input[14]};
  request.upper_length = input[15];
  request.lower_length = input[16];
  const auto solved = darktidevr::core::solve_two_bone_ik(request);
  if (!solved.valid) {
    return 3;
  }
  output[0] = solved.elbow.x;
  output[1] = solved.elbow.y;
  output[2] = solved.elbow.z;
  output[3] = solved.wrist.x;
  output[4] = solved.wrist.y;
  output[5] = solved.wrist.z;
  output[6] = solved.reach_direction.x;
  output[7] = solved.reach_direction.y;
  output[8] = solved.reach_direction.z;
  output[9] = solved.bend_direction.x;
  output[10] = solved.bend_direction.y;
  output[11] = solved.bend_direction.z;
  output[12] = solved.requested_distance;
  output[13] = solved.solved_distance;
  *flags = (solved.clamped_near ? 1U : 0U) |
           (solved.clamped_far ? 2U : 0U) |
           (solved.used_direction_fallback ? 4U : 0U) |
           (solved.used_bend_fallback ? 8U : 0U);
  return 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_shader_draw_count() {
  return billboard_exact_shader_draw_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_pso_draw_count() {
  return billboard_exact_pso_draw_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_pso_cbv_slot_count(unsigned int slot) {
  return slot < billboard_exact_pso_cbv_slot_counts.size()
             ? billboard_exact_pso_cbv_slot_counts[slot].load(
                   std::memory_order_relaxed)
             : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_pso_table_slot_count(unsigned int slot) {
  return slot < billboard_exact_pso_table_slot_counts.size()
             ? billboard_exact_pso_table_slot_counts[slot].load(
                   std::memory_order_relaxed)
             : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_register_count(unsigned int shader_register) {
  return shader_register < billboard_exact_register_counts.size()
             ? billboard_exact_register_counts[shader_register].load(
                   std::memory_order_relaxed)
             : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_vertex_table_slot_count(unsigned int slot) {
  return slot < billboard_exact_vertex_table_slot_counts.size()
             ? billboard_exact_vertex_table_slot_counts[slot].load(
                   std::memory_order_relaxed)
             : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_descriptor_offset_count(unsigned int offset) {
  return offset < billboard_exact_descriptor_offset_counts.size()
             ? billboard_exact_descriptor_offset_counts[offset].load(
                   std::memory_order_relaxed)
             : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_table_span_count(unsigned int span) {
  return span < billboard_exact_table_span_counts.size()
             ? billboard_exact_table_span_counts[span].load(
                   std::memory_order_relaxed)
             : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_cbv_descriptor_count() {
  return billboard_exact_cbv_descriptor_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_buffer_resource_count() {
  return billboard_exact_buffer_resource_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_heap_type_count(unsigned int heap_type) {
  return heap_type < billboard_exact_heap_type_counts.size()
             ? billboard_exact_heap_type_counts[heap_type].load(
                   std::memory_order_relaxed)
             : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_map_success_count() {
  return billboard_exact_map_success_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_map_failure_count() {
  return billboard_exact_map_failure_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_resource_map_count() {
  return billboard_resource_map_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_resource_map_match_count() {
  return billboard_resource_map_match_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_resource_unmap_count() {
  return billboard_resource_unmap_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_selected_map_stack_count() {
  return billboard_selected_map_stack_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_upload_flush_count() {
  return billboard_upload_flush_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_direct_patch_count() {
  return billboard_direct_patch_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) int dtvr_billboard_upload_flush_hook_state() {
  return billboard_upload_flush_hook_state.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_selected_cpu_address() {
  return static_cast<unsigned long long>(
      billboard_selected_cpu_address.load(std::memory_order_acquire));
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_selected_gpu_address() {
  return billboard_selected_gpu_address.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_selected_size() {
  return billboard_selected_size.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_shadow_stage_count(unsigned int stage) {
  return stage < billboard_shadow_stage_counts.size()
             ? billboard_shadow_stage_counts[stage].load(
                   std::memory_order_relaxed)
             : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_command_list_type_count(unsigned int type) {
  return type < billboard_exact_command_list_type_counts.size()
             ? billboard_exact_command_list_type_counts[type].load(
                   std::memory_order_relaxed)
             : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_exact_root_mapping_count() {
  return billboard_exact_root_mapping_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_root_metadata_draw_count() {
  return billboard_root_metadata_draw_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_table_b2_draw_count() {
  return billboard_table_b2_draw_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_bound_table_b2_draw_count() {
  return billboard_bound_table_b2_draw_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_observed_draw_count() {
  return billboard_observed_draw_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_direct_draw_hook_count() {
  return billboard_direct_draw_hook_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_diagnostic_root_signature_create_count() {
  return diagnostic_root_signature_create_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_diagnostic_graphics_pso_create_count() {
  return diagnostic_graphics_pso_create_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_diagnostic_compute_pso_create_count() {
  return diagnostic_compute_pso_create_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_diagnostic_stream_pso_create_count() {
  return diagnostic_stream_pso_create_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_diagnostic_graphics_pipeline_load_count() {
  return diagnostic_graphics_pipeline_load_count.load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_diagnostic_compute_pipeline_load_count() {
  return diagnostic_compute_pipeline_load_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_diagnostic_stream_pipeline_load_count() {
  return diagnostic_stream_pipeline_load_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_root_b2_candidate_draw_count() {
  return billboard_root_b2_candidate_draw_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_candidate_shader_hash(unsigned int rank) {
  std::vector<std::pair<std::uint64_t, std::uint64_t>> ranked;
  {
    std::scoped_lock lock(billboard_candidate_shader_mutex);
    ranked.assign(billboard_candidate_shader_counts.begin(),
                  billboard_candidate_shader_counts.end());
  }
  std::sort(ranked.begin(), ranked.end(), [](const auto& left,
                                             const auto& right) {
    return left.second != right.second ? left.second > right.second
                                       : left.first < right.first;
  });
  return rank < ranked.size() ? ranked[rank].first : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_candidate_shader_count(unsigned int rank) {
  std::vector<std::pair<std::uint64_t, std::uint64_t>> ranked;
  {
    std::scoped_lock lock(billboard_candidate_shader_mutex);
    ranked.assign(billboard_candidate_shader_counts.begin(),
                  billboard_candidate_shader_counts.end());
  }
  std::sort(ranked.begin(), ranked.end(), [](const auto& left,
                                             const auto& right) {
    return left.second != right.second ? left.second > right.second
                                       : left.first < right.first;
  });
  return rank < ranked.size() ? ranked[rank].second : 0;
}
extern "C" __declspec(dllexport) unsigned int
dtvr_billboard_candidate_shader_hash_low(unsigned int rank) {
  return static_cast<unsigned int>(dtvr_billboard_candidate_shader_hash(rank));
}
extern "C" __declspec(dllexport) unsigned int
dtvr_billboard_candidate_shader_hash_high(unsigned int rank) {
  return static_cast<unsigned int>(
      dtvr_billboard_candidate_shader_hash(rank) >> 32U);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_candidate_pair_vertex_shader(unsigned int rank) {
  std::vector<std::pair<std::pair<std::uint64_t, std::uint64_t>,
                        std::uint64_t>> ranked;
  {
    std::scoped_lock lock(billboard_candidate_shader_mutex);
    ranked.assign(billboard_candidate_shader_pair_counts.begin(),
                  billboard_candidate_shader_pair_counts.end());
  }
  std::sort(ranked.begin(), ranked.end(), [](const auto& left,
                                             const auto& right) {
    return left.second != right.second ? left.second > right.second
                                       : left.first < right.first;
  });
  return rank < ranked.size() ? ranked[rank].first.first : 0;
}
extern "C" __declspec(dllexport) unsigned int
dtvr_copy_billboard_candidate_pairs(
    darktidevr::producer::ShaderPairSample* output, unsigned int capacity) {
  if (!output || capacity == 0 || capacity > 256) return 0;
  std::scoped_lock lock(billboard_candidate_shader_mutex);
  return darktidevr::producer::copy_shader_pair_snapshot(
      billboard_candidate_shader_pair_counts, {output, capacity});
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_candidate_pair_pixel_shader(unsigned int rank) {
  std::vector<std::pair<std::pair<std::uint64_t, std::uint64_t>,
                        std::uint64_t>> ranked;
  {
    std::scoped_lock lock(billboard_candidate_shader_mutex);
    ranked.assign(billboard_candidate_shader_pair_counts.begin(),
                  billboard_candidate_shader_pair_counts.end());
  }
  std::sort(ranked.begin(), ranked.end(), [](const auto& left,
                                             const auto& right) {
    return left.second != right.second ? left.second > right.second
                                       : left.first < right.first;
  });
  return rank < ranked.size() ? ranked[rank].first.second : 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_candidate_pair_count(unsigned int rank) {
  std::vector<std::pair<std::pair<std::uint64_t, std::uint64_t>,
                        std::uint64_t>> ranked;
  {
    std::scoped_lock lock(billboard_candidate_shader_mutex);
    ranked.assign(billboard_candidate_shader_pair_counts.begin(),
                  billboard_candidate_shader_pair_counts.end());
  }
  std::sort(ranked.begin(), ranked.end(), [](const auto& left,
                                             const auto& right) {
    return left.second != right.second ? left.second > right.second
                                       : left.first < right.first;
  });
  return rank < ranked.size() ? ranked[rank].second : 0;
}
extern "C" __declspec(dllexport) unsigned int
dtvr_billboard_candidate_pair_vertex_low(unsigned int rank) {
  return static_cast<unsigned int>(
      dtvr_billboard_candidate_pair_vertex_shader(rank));
}
extern "C" __declspec(dllexport) unsigned int
dtvr_billboard_candidate_pair_vertex_high(unsigned int rank) {
  return static_cast<unsigned int>(
      dtvr_billboard_candidate_pair_vertex_shader(rank) >> 32U);
}
extern "C" __declspec(dllexport) unsigned int
dtvr_billboard_candidate_pair_pixel_low(unsigned int rank) {
  return static_cast<unsigned int>(
      dtvr_billboard_candidate_pair_pixel_shader(rank));
}
extern "C" __declspec(dllexport) unsigned int
dtvr_billboard_candidate_pair_pixel_high(unsigned int rank) {
  return static_cast<unsigned int>(
      dtvr_billboard_candidate_pair_pixel_shader(rank) >> 32U);
}
extern "C" __declspec(dllexport) int dtvr_billboard_probe_state() {
  return (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed) ? 1 : 0) |
         (billboard_horizon_lock_enabled.load(std::memory_order_relaxed) ? 2 : 0) |
         (billboard_basis_write_enabled.load(std::memory_order_relaxed) ? 4 : 0);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_observed_stride_count(unsigned int slot, unsigned int stride) {
  if (slot >= billboard_observed_stride_counts.size() ||
      stride >= kBillboardObservedStrideCount) {
    return 0;
  }
  return billboard_observed_stride_counts[slot][stride].load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_stride_candidate_count() {
  return billboard_stride_candidate_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_b1_bound_count() {
  return billboard_b1_bound_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_b2_bound_count() {
  return billboard_b2_bound_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_basis_patch_count() {
  return billboard_basis_patch_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long dtvr_qpc_ticks() {
  LARGE_INTEGER value{};
  return QueryPerformanceCounter(&value)
             ? static_cast<unsigned long long>(value.QuadPart)
             : 0ULL;
}
extern "C" __declspec(dllexport) unsigned long long dtvr_qpc_frequency() {
  LARGE_INTEGER value{};
  return QueryPerformanceFrequency(&value)
             ? static_cast<unsigned long long>(value.QuadPart)
             : 0ULL;
}
extern "C" __declspec(dllexport) int dtvr_take_gpu_eye_profile(
    int eye, unsigned long long* values) {
  if (eye < 0 || eye > 1 || !values) {
    return 1;
  }
  std::scoped_lock lock(gpu_profile_mutex);
  harvest_gpu_profile_samples();
  const auto index = static_cast<std::size_t>(eye);
  values[0] = gpu_profile_sample_counts[index].exchange(
      0, std::memory_order_relaxed);
  values[1] = gpu_profile_total_ticks[index].exchange(
      0, std::memory_order_relaxed);
  values[2] = gpu_profile_max_ticks[index].exchange(
      0, std::memory_order_relaxed);
  values[3] = gpu_profile_frequency;
  auto durations = std::move(gpu_profile_duration_ticks[index]);
  gpu_profile_duration_ticks[index].clear();
  if (!durations.empty()) {
    std::sort(durations.begin(), durations.end());
    values[4] = durations[(durations.size() - 1U) / 2U];
    values[5] = durations[((durations.size() - 1U) * 95U) / 100U];
  } else {
    values[4] = 0;
    values[5] = 0;
  }
  return gpu_profile_frequency != 0 ? 0 : 2;
}
extern "C" __declspec(dllexport) int dtvr_take_gpu_stage_profile(
    int eye, unsigned long long* values) {
  if (eye < 0 || eye > 1 || !values) {
    return 1;
  }
  std::scoped_lock lock(gpu_profile_mutex);
  harvest_gpu_profile_samples();
  const auto index = static_cast<std::size_t>(eye);
  values[0] = gpu_profile_stage_sample_counts[index].exchange(
      0, std::memory_order_relaxed);
  values[1] = gpu_profile_world_total_ticks[index].exchange(
      0, std::memory_order_relaxed);
  values[2] = gpu_profile_world_max_ticks[index].exchange(
      0, std::memory_order_relaxed);
  values[3] = gpu_profile_output_total_ticks[index].exchange(
      0, std::memory_order_relaxed);
  values[4] = gpu_profile_output_max_ticks[index].exchange(
      0, std::memory_order_relaxed);
  values[5] = gpu_profile_frequency;
  return gpu_profile_frequency != 0 ? 0 : 2;
}
extern "C" __declspec(dllexport) int dtvr_set_gpu_eye_profile(int enabled) {
  gpu_profile_enabled.store(enabled != 0, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_capture_eye(int eye) {
  try {
    return capture_eye(eye);
  } catch (...) {
    return 39;
  }
}
extern "C" __declspec(dllexport) int dtvr_capture_armed_swapchain_eye(int eye) {
  try {
    return capture_armed_eye_from_swapchain(eye);
  } catch (...) {
    return 89;
  }
}
extern "C" __declspec(dllexport) int
dtvr_set_camera_output_candidate_index(int index) {
  if (index < -1 || index > 31) {
    return 1;
  }
  camera_output_candidate_index.store(index, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_arm_eye_capture_pose(
    int eye, unsigned long long pose_sequence) {
  if (eye < 0 || eye > 1) {
    return 60;
  }
  std::scoped_lock lock(boundary_capture_mutex);
  if (eye == 0 && camera_output_realign_pending &&
      known_camera_output_resources.size() >= 2) {
    boundary_tag_reset_count.fetch_add(armed_eye_captures.size(),
                                       std::memory_order_relaxed);
    armed_eye_captures.clear();
    camera_output_realign_pending = false;
    write_boundary_census_log(
        "frame=%llu\tOUTPUT_REALIGN\tknown=%llu\r\n",
        present_count.load(std::memory_order_relaxed),
        static_cast<unsigned long long>(known_camera_output_resources.size()));
  }
  if (armed_eye_captures.size() >= 8) {
    boundary_tag_reset_count.fetch_add(armed_eye_captures.size(),
                                       std::memory_order_relaxed);
    armed_eye_captures.clear();
    // An overflow observed on eye 1 has already lost its matching eye 0.
    // Resume cleanly at the next eye-0 boundary instead of queuing half a pair.
    if (eye == 1) {
      return 0;
    }
  }
  const auto vertical_fov =
      render_vertical_fov_radians.load(std::memory_order_relaxed);
  const auto aspect_ratio =
      render_aspect_ratio.load(std::memory_order_relaxed);
  if (!(vertical_fov > 0.0F && vertical_fov < 3.14159265F) ||
      !(aspect_ratio > 0.0F)) {
    return 64;
  }
  armed_eye_captures.push_back(
      {eye, pose_sequence, vertical_fov, aspect_ratio});
  boundary_arm_count.fetch_add(1, std::memory_order_relaxed);
  write_boundary_census_log(
      "frame=%llu\tARM\teye=%d\tpose=%llu\tqueued_tags=%llu"
      "\toutput=%llux%u\tformat=%u\tvfov=%.7f\taspect=%.7f\r\n",
      present_count.load(std::memory_order_relaxed), eye,
      static_cast<unsigned long long>(pose_sequence),
      static_cast<unsigned long long>(armed_eye_captures.size()),
      static_cast<unsigned long long>(camera_output_width),
      camera_output_height, static_cast<unsigned>(camera_output_format),
      static_cast<double>(vertical_fov), static_cast<double>(aspect_ratio));
  begin_gpu_eye_profile(eye);
  return 0;
}

extern "C" __declspec(dllexport) int dtvr_set_swapchain_render_extent(
    unsigned long long width, unsigned int height) {
  if (width == 0 && height == 0) {
    swapchain_render_extent_enabled.store(false, std::memory_order_release);
    return 0;
  }
  const auto extent = darktidevr::core::streamline_render_extent(width, height,
      streamline_stereo_swapchain_probe_requested.load(std::memory_order_acquire));
  if (!extent.eye_width) return 1;
  camera_input_width.store(extent.eye_width, std::memory_order_relaxed);
  camera_input_height.store(extent.height, std::memory_order_relaxed);
  swapchain_present_width.store(extent.present_width, std::memory_order_relaxed);
  {
    std::scoped_lock lock(boundary_census_log_mutex);
    if (boundary_census_log != INVALID_HANDLE_VALUE) {
      CloseHandle(boundary_census_log);
      boundary_census_log = INVALID_HANDLE_VALUE;
    }
    // The resource census is diagnostic-only. Keep it out of the accepted
    // renderer unless a deliberately staged process opts in.
    wchar_t census_value[2]{};
    const auto census_length = GetEnvironmentVariableW(
        L"DARKTIDEVR_BOUNDARY_CENSUS", census_value,
        static_cast<DWORD>(std::size(census_value)));
    const bool enable_census =
        boundary_census_requested.load(std::memory_order_relaxed) ||
        (census_length == 1 && census_value[0] == L'1');
    wchar_t temporary_path[MAX_PATH]{};
    if (enable_census && GetTempPathW(MAX_PATH, temporary_path) != 0) {
      const std::wstring path =
          std::wstring(temporary_path) + L"darktidevr-boundary-census.log";
      boundary_census_log =
          CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      boundary_census_log_count.store(0, std::memory_order_relaxed);
    }
  }
  swapchain_render_width.store(static_cast<UINT>(width),
                               std::memory_order_relaxed);
  swapchain_render_height.store(height, std::memory_order_relaxed);
  swapchain_render_extent_enabled.store(true, std::memory_order_release);
  swapchain_resize_nudge_pending.store(true, std::memory_order_release);
  write_boundary_census_log("CONFIG\trequested=%llux%u\tpresent=%ux%u\r\n",
      width, height, extent.present_width, extent.height);
  write_streamline_probe_log(
      "STEREO_RENDER_EXTENT\tengine=%ux%u\tpresent=%ux%u\tisolated_window_extent=1\r\n",
      extent.eye_width, extent.height, extent.present_width, extent.height);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_enable_boundary_census() {
  boundary_census_requested.store(true, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_read_mirror_cursor(int* values,
                                                          unsigned int count) {
  if (!values || count < 5) {
    return 1;
  }
  const auto window = game_output_window.load(std::memory_order_acquire);
  RECT client{};
  POINT cursor{};
  // Read physical window coordinates, bypassing the extent we advertise to
  // Stingray for XR rendering. These remain paired across DPI/fullscreen changes.
  const auto got_client = window && (original_get_client_rect
      ? original_get_client_rect(window, &client)
      : GetClientRect(window, &client));
  if (!got_client || client.right <= client.left || client.bottom <= client.top ||
      !GetCursorPos(&cursor) || !ScreenToClient(window, &cursor)) {
    return 2;
  }
  values[0] = cursor.x;
  values[1] = cursor.y;
  values[2] = client.right - client.left;
  values[3] = client.bottom - client.top;
  values[4] = GetForegroundWindow() == window ? 1 : 0;
  return 0;
}

extern "C" __declspec(dllexport) int dtvr_set_mirror_client_extent(
    unsigned int width, unsigned int height) {
  if ((width == 0) != (height == 0) || width > 3840 || height > 3840) {
    return 1;
  }
  mirror_client_width.store(width, std::memory_order_relaxed);
  mirror_client_height.store(height, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_set_virtual_client_extent(
    int enabled) {
  virtual_client_extent_enabled.store(enabled != 0,
                                      std::memory_order_release);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_set_virtual_size_message(
    int enabled) {
  const auto requested = enabled != 0;
  virtual_size_message_enabled.store(requested, std::memory_order_release);
  if (requested) {
    // The output window is normally discovered before Lua enables stereo.
    // Install the translating window procedure at configuration time so the
    // first real client-area nudge reaches Stingray with the XR render extent.
    // Waiting for a later swapchain-metadata refresh leaves that first nudge
    // physical-sized and creates viewport-dependent resources at mixed sizes.
    ensure_virtual_window_proc(
        game_output_window.load(std::memory_order_acquire));
  }
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_lock_swapchain_client_extent(
    int enabled) {
  swapchain_client_extent_locked.store(enabled != 0,
                                       std::memory_order_release);
  swapchain_resize_nudge_pending.store(true, std::memory_order_release);
  swapchain_resize_nudge_phase.store(0, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_set_render_projection(
    float vertical_fov_radians, float aspect_ratio) {
  if (!(vertical_fov_radians > 0.0F &&
        vertical_fov_radians < 3.14159265F) ||
      !(aspect_ratio > 0.0F)) {
    return 1;
  }
  render_vertical_fov_radians.store(vertical_fov_radians,
                                     std::memory_order_release);
  render_aspect_ratio.store(aspect_ratio, std::memory_order_release);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_arm_eye_capture(int eye) {
  return dtvr_arm_eye_capture_pose(eye, 0);
}
extern "C" __declspec(dllexport) int dtvr_reset_eye_capture_tags() {
  std::scoped_lock lock(boundary_capture_mutex);
  boundary_tag_reset_count.fetch_add(armed_eye_captures.size(),
                                     std::memory_order_relaxed);
  armed_eye_captures.clear();
  write_boundary_census_log(
      "frame=%llu\tTAG_RESET\r\n",
      present_count.load(std::memory_order_relaxed));
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_wait_eye_capture_count(
    int eye, unsigned long long target, unsigned int timeout_ms) {
  if (eye < 0 || eye > 1) {
    return 70;
  }
  const auto deadline = GetTickCount64() + timeout_ms;
  const auto& count =
      boundary_eye_capture_counts[static_cast<std::size_t>(eye)];
  while (count.load(std::memory_order_acquire) < target) {
    if (GetTickCount64() >= deadline) {
      std::uint64_t queued_tags{};
      {
        std::scoped_lock lock(boundary_capture_mutex);
        queued_tags = armed_eye_captures.size();
      }
      write_boundary_census_log(
          "frame=%llu\tWAIT_TIMEOUT\teye=%d\ttarget=%llu\tactual=%llu"
          "\tqueued_tags=%llu\r\n",
          present_count.load(std::memory_order_relaxed), eye, target,
          count.load(std::memory_order_relaxed),
          static_cast<unsigned long long>(queued_tags));
      return 71;
    }
    Sleep(0);
  }
  return 0;
}
extern "C" __declspec(dllexport) unsigned long long dtvr_boundary_arm_count() {
  return boundary_arm_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_boundary_transition_count() {
  return boundary_transition_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_boundary_eye_capture_count(int eye) {
  if (eye < 0 || eye > 1) {
    return 0;
  }
  return boundary_eye_capture_counts[static_cast<std::size_t>(eye)].load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_boundary_eye_pose_sequence(int eye) {
  if (eye < 0 || eye > 1) {
    return 0;
  }
  return boundary_eye_pose_sequences[static_cast<std::size_t>(eye)].load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_boundary_tag_queue_depth() {
  std::scoped_lock lock(boundary_capture_mutex);
  return armed_eye_captures.size();
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_boundary_tag_reset_count() {
  return boundary_tag_reset_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) int dtvr_boundary_last_capture_result() {
  return boundary_last_capture_result.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long dtvr_ready_value() {
  std::scoped_lock lock(state_mutex);
  return ready_value;
}
extern "C" __declspec(dllexport) unsigned long long dtvr_execute_call_count() {
  return execute_call_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long dtvr_present_count() {
  return present_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) int dtvr_capture_stage() {
  return capture_stage.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) int dtvr_enable_present_capture() {
  present_capture_enabled.store(true, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_disable_present_capture() {
  present_capture_enabled.store(false, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_enable_alternating_full_capture() {
  alternating_present_eye.store(-1, std::memory_order_relaxed);
  alternating_seen_eyes.store(0, std::memory_order_relaxed);
  alternating_eye_copy_counts[0].store(0, std::memory_order_relaxed);
  alternating_eye_copy_counts[1].store(0, std::memory_order_relaxed);
  alternating_eye_tag_count.store(0, std::memory_order_relaxed);
  alternating_last_capture_result.store(0, std::memory_order_relaxed);
  alternating_full_capture_enabled.store(true, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_disable_alternating_full_capture() {
  alternating_full_capture_enabled.store(false, std::memory_order_relaxed);
  alternating_present_eye.store(-1, std::memory_order_relaxed);
  alternating_seen_eyes.store(0, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_enable_top_bottom_capture() {
  top_bottom_capture_enabled.store(true, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_disable_top_bottom_capture() {
  top_bottom_capture_enabled.store(false, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_set_alternating_present_eye(int eye) {
  if (eye < 0 || eye > 1) {
    return 56;
  }
  alternating_present_eye.store(eye, std::memory_order_relaxed);
  alternating_eye_tag_count.fetch_add(1, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_alternating_eye_copy_count(int eye) {
  if (eye < 0 || eye > 1) {
    return 0;
  }
  return alternating_eye_copy_counts[static_cast<std::size_t>(eye)].load(
      std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_alternating_eye_tag_count() {
  return alternating_eye_tag_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) int dtvr_alternating_last_capture_result() {
  return alternating_last_capture_result.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) int dtvr_enable_table4_alias() {
  table4_alias_count.store(0, std::memory_order_relaxed);
  table4_alias_eye0_to_eye1.store(true, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_disable_table4_alias() {
  table4_alias_eye0_to_eye1.store(false, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_table4_alias_count() {
  return table4_alias_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_table4_exact_match_count() {
  return table4_exact_match_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_table4_exact_ambiguous_count() {
  return table4_exact_ambiguous_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) int dtvr_enable_candidate_instance_clamp() {
  candidate_instance_clamp_count.store(0, std::memory_order_relaxed);
  candidate_instance_clamp_enabled.store(true, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_disable_candidate_instance_clamp() {
  candidate_instance_clamp_enabled.store(false, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_candidate_instance_clamp_count() {
  return candidate_instance_clamp_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) int dtvr_enable_candidate_table4_alias() {
  candidate_table4_alias_count.store(0, std::memory_order_relaxed);
  candidate_table4_match_count.store(0, std::memory_order_relaxed);
  candidate_table4_ambiguous_count.store(0, std::memory_order_relaxed);
  candidate_table4_alias_enabled.store(true, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_disable_candidate_table4_alias() {
  candidate_table4_alias_enabled.store(false, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_candidate_table4_alias_count() {
  return candidate_table4_alias_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_candidate_table4_match_count() {
  return candidate_table4_match_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_candidate_table4_ambiguous_count() {
  return candidate_table4_ambiguous_count.load(std::memory_order_relaxed);
}
extern "C" __declspec(dllexport) int dtvr_enable_rich_center_sbs_remap() {
  {
    std::scoped_lock lock(viewport_remap_mutex);
    viewport_remap_states.clear();
  }
  rich_center_sbs_remap_enabled.store(true, std::memory_order_relaxed);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_disable_rich_center_sbs_remap() {
  rich_center_sbs_remap_enabled.store(false, std::memory_order_relaxed);
  {
    std::scoped_lock lock(viewport_remap_mutex);
    viewport_remap_states.clear();
  }
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_set_focused_trace_phase(int phase) {
  if (phase < 0 || phase > 4) {
    return 60;
  }
  {
    std::scoped_lock lock(focused_trace_mutex);
    focused_trace_phase.store(0, std::memory_order_relaxed);
    if (phase == 0) {
      if (focused_trace_log != INVALID_HANDLE_VALUE) {
        FlushFileBuffers(focused_trace_log);
      }
      return 0;
    }
    if (phase == 1) {
      if (focused_trace_log != INVALID_HANDLE_VALUE) {
        CloseHandle(focused_trace_log);
        focused_trace_log = INVALID_HANDLE_VALUE;
      }
      wchar_t temporary_path[MAX_PATH]{};
      if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
        return 61;
      }
      const std::wstring path =
          std::wstring(temporary_path) + L"darktidevr-focused-draws.log";
      focused_trace_log =
          CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (focused_trace_log == INVALID_HANDLE_VALUE) {
        return 62;
      }
      focused_trace_count.store(0, std::memory_order_relaxed);
      for (auto& claimed : gpu_profile_pass_trace_claimed) {
        claimed.store(false, std::memory_order_relaxed);
      }
    } else if (focused_trace_log == INVALID_HANDLE_VALUE) {
      return 63;
    }
    focused_trace_phase.store(phase, std::memory_order_relaxed);
  }
  write_focused_log("phase=%d\tframe=%llu\tPHASE\r\n", phase,
                    present_count.load(std::memory_order_relaxed));
  return 0;
}
extern "C" __declspec(dllexport) unsigned long long
dtvr_focused_trace_count() {
  return focused_trace_count.load(std::memory_order_relaxed);
}
int read_head_pose(float* values, unsigned long long* sequence,
                   unsigned long long* transport_generation) {
  if (!values || !sequence) {
    return 1;
  }
  darktidevr::core::SharedHeadPoseSample sample{};
  darktidevr::core::SharedHeadPoseReadDiagnostics diagnostic{};
  if (!shared_head_pose_reader().read(sample, &diagnostic)) {
    // Startup failures can precede the bounded DLSS submission window. Keep
    // failure evidence independently bounded so a one-frame regression is not
    // silently omitted while ordinary successful reads stay window-scoped.
    static std::atomic<unsigned> startup_pose_failures{};
    if (trace_streamline_submission_images() ||
        startup_pose_failures.fetch_add(1, std::memory_order_relaxed) < 256) {
      write_streamline_probe_log("HEAD_POSE_READ\tpresent_frame=%llu\tresult=2\treason=%s\ttick_ms=%llu\tpublished_ms=%llu\tsequence=%llu\tepoch_before=%llu\tepoch_after=%llu\tattempts=%u\r\n",
          static_cast<unsigned long long>(present_count.load(std::memory_order_relaxed)),
          diagnostic.reason, diagnostic.now_ms, diagnostic.published_ms,
          diagnostic.sequence, diagnostic.epoch_before, diagnostic.epoch_after,
          diagnostic.attempts);
    }
    return 2;
  }
  if (trace_streamline_submission_images()) {
    write_streamline_probe_log("HEAD_POSE_READ\tpresent_frame=%llu\tresult=0\tsequence=%llu\r\n",
        static_cast<unsigned long long>(present_count.load(std::memory_order_relaxed)),
        static_cast<unsigned long long>(sample.sequence));
  }
  values[0] = sample.pose.position.x;
  values[1] = sample.pose.position.y;
  values[2] = sample.pose.position.z;
  values[3] = sample.pose.orientation.x;
  values[4] = sample.pose.orientation.y;
  values[5] = sample.pose.orientation.z;
  values[6] = sample.pose.orientation.w;
  values[7] = sample.render_vertical_fov_radians;
  values[8] = sample.render_aspect_ratio;
  values[9] = sample.render_frusta[0].left;
  values[10] = sample.render_frusta[0].right;
  values[11] = sample.render_frusta[0].down;
  values[12] = sample.render_frusta[0].up;
  values[13] = sample.render_frusta[1].left;
  values[14] = sample.render_frusta[1].right;
  values[15] = sample.render_frusta[1].down;
  values[16] = sample.render_frusta[1].up;
  values[17] = static_cast<float>(sample.render_width);
  values[18] = static_cast<float>(sample.render_height);
  values[19] = sample.ipd_metres;
  values[20] = sample.body_follow_offset.x;
  values[21] = sample.body_follow_offset.y;
  values[22] = sample.body_follow_offset.z;
  values[23] = static_cast<float>(sample.recenter_generation);
  values[24] = sample.floor_eye_height_metres;
  *sequence = sample.sequence;
  if (transport_generation) {
    *transport_generation = sample.transport_generation;
  }
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_read_head_pose(
    float* values, unsigned long long* sequence) {
  return read_head_pose(values, sequence, nullptr);
}
extern "C" __declspec(dllexport) int dtvr_read_head_pose_v2(
    float* values, unsigned long long* sequence,
    unsigned long long* transport_generation) {
  if (!transport_generation) {
    return 1;
  }
  return read_head_pose(values, sequence, transport_generation);
}
int read_controller_state(
    float* values, unsigned int* tracking_flags, unsigned int* buttons,
    unsigned long long* sequence, unsigned long long* timestamp_ns,
    unsigned long long* transport_generation) {
  if (!values || !tracking_flags || !buttons || !sequence || !timestamp_ns) {
    return 1;
  }
  darktidevr::core::SharedControllerState sample{};
  if (!shared_controller_state_reader().read(sample)) {
    return 2;
  }
  // Gameplay consumes recenter-relative Darktide-basis poses. The absolute
  // OpenXR LOCAL poses remain in the shared mapping for the XR menu adapter.
  for (std::size_t hand = 0; hand < 2; ++hand) {
    const auto& source = sample.hands[hand];
    const auto offset = hand * 18;
    values[offset + 0] = source.body_aim_pose.position.x;
    values[offset + 1] = source.body_aim_pose.position.y;
    values[offset + 2] = source.body_aim_pose.position.z;
    values[offset + 3] = source.body_aim_pose.orientation.x;
    values[offset + 4] = source.body_aim_pose.orientation.y;
    values[offset + 5] = source.body_aim_pose.orientation.z;
    values[offset + 6] = source.body_aim_pose.orientation.w;
    values[offset + 7] = source.body_grip_pose.position.x;
    values[offset + 8] = source.body_grip_pose.position.y;
    values[offset + 9] = source.body_grip_pose.position.z;
    values[offset + 10] = source.body_grip_pose.orientation.x;
    values[offset + 11] = source.body_grip_pose.orientation.y;
    values[offset + 12] = source.body_grip_pose.orientation.z;
    values[offset + 13] = source.body_grip_pose.orientation.w;
    values[offset + 14] = source.trigger;
    values[offset + 15] = source.squeeze;
    values[offset + 16] = source.thumbstick_x;
    values[offset + 17] = source.thumbstick_y;
    tracking_flags[hand * 2] = source.body_aim_tracking_flags;
    tracking_flags[hand * 2 + 1] = source.body_grip_tracking_flags;
    buttons[hand] = source.buttons;
  }
  *sequence = sample.sequence;
  *timestamp_ns = sample.timestamp_ns;
  if (transport_generation) {
    *transport_generation = sample.transport_generation;
  }
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_read_controller_state(
    float* values, unsigned int* tracking_flags, unsigned int* buttons,
    unsigned long long* sequence, unsigned long long* timestamp_ns) {
  return read_controller_state(values, tracking_flags, buttons, sequence,
                               timestamp_ns, nullptr);
}
extern "C" __declspec(dllexport) int dtvr_read_controller_state_v2(
    float* values, unsigned int* tracking_flags, unsigned int* buttons,
    unsigned long long* sequence, unsigned long long* timestamp_ns,
    unsigned long long* transport_generation) {
  if (!transport_generation) {
    return 1;
  }
  return read_controller_state(values, tracking_flags, buttons, sequence,
                               timestamp_ns, transport_generation);
}
int read_menu_pointer_state(unsigned int* values,
                            unsigned long long* sequence,
                            unsigned long long* timestamp_ns,
                            unsigned long long* transport_generation,
                            bool include_secondary = false) {
  if (!values || !sequence || !timestamp_ns) {
    return 1;
  }
  darktidevr::core::SharedMenuPointerState sample{};
  if (!shared_menu_pointer_state_reader().read(sample)) {
    return 2;
  }
  values[0] = sample.active ? 1U : 0U;
  values[1] = sample.source_x;
  values[2] = sample.source_y;
  values[3] = sample.source_width;
  values[4] = sample.source_height;
  values[5] = sample.primary_down ? 1U : 0U;
  values[6] = sample.back_down ? 1U : 0U;
  values[7] = static_cast<unsigned int>(sample.scroll_steps);
  values[8] = sample.primary_press_sequence;
  values[9] = sample.back_press_sequence;
  values[10] = sample.scroll_sequence;
  if (include_secondary) {
    values[11] = sample.secondary_down ? 1U : 0U;
    values[12] = sample.secondary_press_sequence;
  }
  *sequence = sample.sequence;
  *timestamp_ns = sample.timestamp_ns;
  if (transport_generation) {
    *transport_generation = sample.transport_generation;
  }
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_read_menu_pointer_state(
    unsigned int* values, unsigned long long* sequence,
    unsigned long long* timestamp_ns) {
  return read_menu_pointer_state(values, sequence, timestamp_ns, nullptr);
}
extern "C" __declspec(dllexport) int dtvr_read_menu_pointer_state_v2(
    unsigned int* values, unsigned long long* sequence,
    unsigned long long* timestamp_ns,
    unsigned long long* transport_generation) {
  if (!transport_generation) {
    return 1;
  }
  return read_menu_pointer_state(values, sequence, timestamp_ns,
                                 transport_generation);
}
// V1/V2 retain their eleven-value ABI; only V3 writes the two new fields.
extern "C" __declspec(dllexport) int dtvr_read_menu_pointer_state_v3(
    unsigned int* values, unsigned int value_count,
    unsigned long long* sequence, unsigned long long* timestamp_ns,
    unsigned long long* transport_generation) {
  if (value_count < 13 || !transport_generation) {
    return 1;
  }
  return read_menu_pointer_state(values, sequence, timestamp_ns,
                                 transport_generation, true);
}
static int read_mapped_controller_input(
    darktidevr::core::GameplayInputMapper& mapper,
    int gameplay_active, unsigned long long* pressed,
    unsigned long long* held, unsigned long long* released,
    unsigned long long* sequence, float* movement,
    unsigned long long* generation = nullptr, float* right_stick = nullptr) {
  if (!pressed || !held || !released || !sequence || !movement) {
    return 1;
  }
  darktidevr::core::SharedControllerState sample{};
  const auto read_available = shared_controller_state_reader().read(sample);
  const auto now_ns = static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
          std::chrono::steady_clock::now().time_since_epoch())
          .count());
  constexpr std::uint64_t maximum_controller_age_ns = 100'000'000ULL;
  const auto available =
      read_available && darktidevr::core::controller_state_is_fresh(
                            sample, now_ns, maximum_controller_age_ns);
  const auto frame = available
                         ? mapper.update(sample, gameplay_active != 0)
                         : mapper.reset();
  *pressed = frame.pressed;
  *held = frame.held;
  *released = frame.released;
  *sequence = available ? sample.sequence : 0;
  movement[0] = frame.move_x;
  movement[1] = frame.move_y;
  if (generation) *generation = available ? sample.transport_generation : 0;
  if (right_stick) {
    right_stick[0] = available ? sample.hands[1].thumbstick_x : 0.0F;
    right_stick[1] = available ? sample.hands[1].thumbstick_y : 0.0F;
    constexpr auto valid_pose = darktidevr::core::controller_orientation_valid |
                                darktidevr::core::controller_position_valid;
    right_stick[2] = available &&
                            (sample.hands[1].aim_tracking_flags & valid_pose) == valid_pose
                        ? 1.0F : 0.0F;
  }
  // Lua's pose observation may still have the previous generation. Signal the
  // button reader's own transition so its cancellation cannot finish a charge.
  return !available ? 2 : frame.publisher_changed ? 3 : 0;
}
extern "C" __declspec(dllexport) int dtvr_read_gameplay_input(
    int gameplay_active, unsigned long long* pressed,
    unsigned long long* held, unsigned long long* released,
    unsigned long long* sequence, float* movement) {
  return read_mapped_controller_input(gameplay_input_mapper(), gameplay_active,
                                     pressed, held, released, sequence, movement);
}
extern "C" __declspec(dllexport) int dtvr_read_spectator_input(
    int active, unsigned long long* pressed, unsigned long long* held,
    unsigned long long* released, unsigned long long* sequence, float* movement,
    unsigned long long* generation, float* right_stick) {
  if (!generation || !right_stick) return 1;
  // Camera input survives an unavailable character. It must never share the
  // combat mapper's cancellation/rearming state or consume its press edges.
  static darktidevr::core::GameplayInputMapper mapper;
  return read_mapped_controller_input(mapper, active, pressed, held, released,
                                     sequence, movement, generation, right_stick);
}
extern "C" __declspec(dllexport) int dtvr_enable_marker_log() {
  std::scoped_lock lock(state_mutex);
  if (marker_log != INVALID_HANDLE_VALUE) {
    return 0;
  }
  wchar_t temporary_path[MAX_PATH]{};
  if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
    return 40;
  }
  const std::wstring path =
      std::wstring(temporary_path) + L"darktidevr-command-events.log";
  marker_log = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                           nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                           nullptr);
  const std::wstring enhanced_path =
      std::wstring(temporary_path) + L"darktidevr-enhanced-barriers.log";
  enhanced_barrier_log =
      CreateFileW(enhanced_path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                  nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  enhanced_barrier_log_count.store(0, std::memory_order_relaxed);
  marker_count.store(0, std::memory_order_relaxed);
  marker_sequence.store(0, std::memory_order_relaxed);
  table4_exact_match_count.store(0, std::memory_order_relaxed);
  table4_exact_ambiguous_count.store(0, std::memory_order_relaxed);
  return marker_log == INVALID_HANDLE_VALUE ? 41 : 0;
}

extern "C" __declspec(dllexport) int dtvr_enable_cluster_trace() {
  std::scoped_lock lock(cluster_trace_mutex);
  if (cluster_trace_log != INVALID_HANDLE_VALUE) {
    return 0;
  }
  wchar_t temporary_path[MAX_PATH]{};
  if (GetTempPathW(MAX_PATH, temporary_path) == 0) {
    return 42;
  }
  const std::wstring path =
      std::wstring(temporary_path) + L"darktidevr-cluster-trace.log";
  cluster_trace_log =
      CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                  CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  cluster_trace_count.store(0, std::memory_order_relaxed);
  cluster_trace_saw_flat_presentation.store(false, std::memory_order_relaxed);
  cluster_linked_list_resource.store(0, std::memory_order_relaxed);
  cluster_linked_list_learned_frame.store(0, std::memory_order_relaxed);
  cluster_generic_dispatch_log_count.store(0, std::memory_order_relaxed);
  cluster_target_dispatch_log_count.store(0, std::memory_order_relaxed);
  cluster_barrier_log_count.store(0, std::memory_order_relaxed);
  cluster_raster_binding_log_count.store(0, std::memory_order_relaxed);
  cluster_constant_copy_log_count.store(0, std::memory_order_relaxed);
  cluster_upload_flush_log_count.store(0, std::memory_order_relaxed);
  {
    std::scoped_lock copy_lock(cluster_constant_copy_mutex);
    cluster_constant_ring_resources.clear();
    cluster_constant_copies.fill({});
    cluster_constant_copy_count = 0;
    cluster_pending_constant_samples.fill({});
    cluster_pending_constant_count = 0;
    cluster_pending_transform_samples.fill({});
    cluster_pending_transform_count = 0;
  }
  {
    std::scoped_lock submission_lock(cluster_submission_mutex);
    cluster_submission_rings.clear();
  }
  return cluster_trace_log == INVALID_HANDLE_VALUE ? 43 : 0;
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    native_capture_module = module;
    DisableThreadLibraryCalls(module);
  } else if (reason == DLL_PROCESS_DETACH) {
    if (marker_log != INVALID_HANDLE_VALUE) {
      CloseHandle(marker_log);
      marker_log = INVALID_HANDLE_VALUE;
    }
    if (focused_trace_log != INVALID_HANDLE_VALUE) {
      CloseHandle(focused_trace_log);
      focused_trace_log = INVALID_HANDLE_VALUE;
    }
    if (cluster_trace_log != INVALID_HANDLE_VALUE) {
      CloseHandle(cluster_trace_log);
      cluster_trace_log = INVALID_HANDLE_VALUE;
    }
    if (enhanced_barrier_log != INVALID_HANDLE_VALUE) {
      CloseHandle(enhanced_barrier_log);
      enhanced_barrier_log = INVALID_HANDLE_VALUE;
    }
    if (boundary_census_log != INVALID_HANDLE_VALUE) {
      CloseHandle(boundary_census_log);
      boundary_census_log = INVALID_HANDLE_VALUE;
    }
    if (menu_resource_log != INVALID_HANDLE_VALUE) {
      CloseHandle(menu_resource_log);
      menu_resource_log = INVALID_HANDLE_VALUE;
    }
    if (resize_diagnostic_log != INVALID_HANDLE_VALUE) {
      CloseHandle(resize_diagnostic_log);
      resize_diagnostic_log = INVALID_HANDLE_VALUE;
    }
    if (streamline_probe_log != INVALID_HANDLE_VALUE) {
      CloseHandle(streamline_probe_log);
      streamline_probe_log = INVALID_HANDLE_VALUE;
    }
    close_shared_handles();
    close_menu_shared_handles();
    if (const auto event = projection_active_event.exchange(
            nullptr, std::memory_order_acq_rel)) {
      CloseHandle(event);
    }
  }
  return TRUE;
}
