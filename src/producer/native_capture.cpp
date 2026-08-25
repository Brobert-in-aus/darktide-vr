#include <Windows.h>
#include <d3d12.h>
#include <d3d12shader.h>
#include <dxcapi.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <intrin.h>

#include <MinHook.h>

#include "core/shared_head_pose.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdarg>
#include <cstring>
#include <cstdio>
#include <deque>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

HMODULE native_capture_module{};
INIT_ONCE dxc_reflection_once = INIT_ONCE_STATIC_INIT;
HMODULE dxcompiler_module{};
DxcCreateInstanceProc dxc_create_instance{};

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
using DrawInstancedFn = void(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*,
                                                 UINT, UINT, UINT, UINT);
using DrawIndexedInstancedFn = void(STDMETHODCALLTYPE*)(
    ID3D12GraphicsCommandList*, UINT, UINT, UINT, INT, UINT);
using DispatchFn = void(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*, UINT,
                                            UINT, UINT);
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
GetClientRectFn original_get_client_rect{};
DispatchMessageWFn original_dispatch_message_w{};
ResizeBuffersFn original_resize_buffers{};
ResizeBuffers1Fn original_resize_buffers1{};
MarkerEventFn original_set_marker{};
MarkerEventFn original_begin_event{};
EndEventFn original_end_event{};
CloseFn original_close{};
ResetFn original_reset{};
DrawInstancedFn original_draw_instanced{};
DrawIndexedInstancedFn original_draw_indexed_instanced{};
DispatchFn original_dispatch{};
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
CreateDescriptorHeapFn original_create_descriptor_heap{};
CreateConstantBufferViewFn original_create_constant_buffer_view{};
CreateShaderResourceViewFn original_create_shader_resource_view{};
CreateUnorderedAccessViewFn original_create_unordered_access_view{};
CreateRenderTargetViewFn original_create_render_target_view{};
CreateDepthStencilViewFn original_create_depth_stencil_view{};
CreateCommittedResourceFn original_create_committed_resource{};
CreatePlacedResourceFn original_create_placed_resource{};
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
ComPtr<IDXGISwapChain3> game_swapchain;
std::array<ComPtr<ID3D12Resource>, 2> eye_surfaces;
ComPtr<ID3D12Fence> ready_fence;
ComPtr<ID3D12Fence> consumed_fence;
std::array<HANDLE, 2> eye_handles{};
HANDLE ready_fence_handle{};
HANDLE consumed_fence_handle{};
std::uint64_t ready_value{};
std::atomic<bool> hooks_installed{};
std::atomic<std::uint64_t> execute_call_count{};
std::atomic<std::uint64_t> present_count{};
std::atomic<std::uint64_t> marker_count{};
std::atomic<std::uint64_t> marker_sequence{};
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
HANDLE enhanced_barrier_log{INVALID_HANDLE_VALUE};
std::atomic<std::uint64_t> enhanced_barrier_log_count{};
std::atomic<int> focused_trace_phase{};
std::atomic<std::uint64_t> focused_trace_count{};
HANDLE focused_trace_log{INVALID_HANDLE_VALUE};
std::mutex focused_trace_mutex;
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

struct DescriptorHeapInfo {
  D3D12_DESCRIPTOR_HEAP_TYPE type{};
  UINT descriptor_count{};
  UINT increment{};
  std::uint64_t cpu_start{};
  std::uint64_t gpu_start{};
};

struct BufferResourceInfo {
  ID3D12Resource* resource{};
  std::uint64_t gpu_start{};
  std::uint64_t size{};
  D3D12_HEAP_TYPE heap_type{D3D12_HEAP_TYPE_CUSTOM};
};

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
  int eye{-1};
  std::uintptr_t pso{};
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
std::mutex buffer_resource_mutex;
std::vector<BufferResourceInfo> buffer_resources;
std::unordered_set<std::uint64_t> billboard_tested_cbvs;
std::mutex billboard_cbv_log_mutex;
bool billboard_cbv_log_initialized{};
std::atomic<std::uint64_t> billboard_cbv_log_count{};

struct PsoMetadata {
  char kind{'U'};
  std::uint64_t vertex_shader{};
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
};

std::mutex pso_mutex;
std::unordered_map<std::uintptr_t, PsoMetadata> pso_metadata;

struct PendingCapture {
  ComPtr<ID3D12CommandAllocator> allocator;
  ComPtr<ID3D12GraphicsCommandList> commands;
  std::uint64_t fence_value{};
};

std::deque<PendingCapture> pending_captures;
std::deque<PendingCapture> available_captures;
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
    swapchain_write_resources;
std::unordered_map<ID3D12GraphicsCommandList*, ComPtr<ID3D12Resource>>
    camera_output_resources;
std::unordered_map<ID3D12GraphicsCommandList*, D3D12_RESOURCE_STATES>
    camera_output_source_states;
std::unordered_set<ID3D12Resource*> known_camera_output_resources;
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
std::atomic<bool> swapchain_render_extent_enabled{};
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
std::atomic<UINT> mirror_client_width{};
std::atomic<UINT> mirror_client_height{};
std::atomic<std::uint64_t> boundary_arm_count{};
std::atomic<std::uint64_t> boundary_transition_count{};
std::array<std::atomic<std::uint64_t>, 2> boundary_eye_capture_counts{};
std::array<std::atomic<std::uint64_t>, 2> boundary_eye_pose_sequences{};
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
std::atomic<int> boundary_last_capture_result{};

constexpr std::size_t kGpuProfileSlotCount = 512;
struct GpuProfileSample {
  int eye{-1};
  UINT slot{};
  std::uint64_t fence_value{};
  bool internal_target_seen{};
  bool stage_boundary_recorded{};
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
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_stage_sample_counts{};
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_world_total_ticks{};
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_world_max_ticks{};
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_output_total_ticks{};
std::array<std::atomic<std::uint64_t>, 2> gpu_profile_output_max_ticks{};
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
std::atomic<std::uint64_t> billboard_shader_substitution_count{};
std::atomic<std::uint64_t> billboard_shader_substitution_reject_count{};
std::array<std::atomic<std::uint64_t>, 5>
    billboard_shader_substitution_attempt_counts{};
std::array<std::atomic<std::uint64_t>, 5>
    billboard_shader_substitution_applied_counts{};
std::array<std::atomic<std::uint64_t>, 5>
    billboard_shader_substitution_validation_reject_counts{};
std::array<std::atomic<std::uint64_t>, 5>
    billboard_shader_substitution_creation_reject_counts{};
std::mutex billboard_shader_replacement_mutex;
std::unordered_map<std::uint64_t, std::vector<std::uint8_t>>
    billboard_shader_replacements;
std::array<std::atomic<float>, 6> billboard_view_basis{};
std::atomic<bool> billboard_horizon_lock_enabled{};
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
std::unordered_set<std::uint64_t> dumped_pipeline_blobs;
std::unordered_set<std::uint64_t> dumped_pso_shader_mappings;

int capture_present_halves(IDXGISwapChain3* swapchain,
                           ID3D12CommandQueue* queue);
int capture_eye_from_resource(int eye, ID3D12CommandQueue* queue,
                              ID3D12Resource* back_buffer,
                              bool bypass_execute_hook,
                              D3D12_RESOURCE_STATES source_state);

void update_atomic_max(std::atomic<std::uint64_t>& destination,
                       std::uint64_t value) {
  auto current = destination.load(std::memory_order_relaxed);
  while (current < value &&
         !destination.compare_exchange_weak(current, value,
                                            std::memory_order_relaxed)) {
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
      static_cast<UINT>(kGpuProfileSlotCount * 3U);
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
      kGpuProfileSlotCount * 3U * sizeof(std::uint64_t);
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
    gpu_profile_query_heap.Reset();
    gpu_profile_readback.Reset();
    gpu_profile_fence.Reset();
    gpu_profile_ticks = nullptr;
    gpu_profile_frequency = 0;
    return false;
  }
  return true;
}

void harvest_gpu_profile_samples() {
  if (!gpu_profile_fence || !gpu_profile_ticks) {
    return;
  }
  const auto completed = gpu_profile_fence->GetCompletedValue();
  while (!gpu_profile_pending.empty() &&
         gpu_profile_pending.front().fence_value <= completed) {
    const auto& sample = gpu_profile_pending.front();
    const auto query_start = sample.slot * 3U;
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
    }
    gpu_profile_pending.pop_front();
  }
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
  harvest_gpu_profile_samples();
  const auto completed = gpu_profile_fence->GetCompletedValue();
  const auto slot = gpu_profile_next_slot;
  if (gpu_profile_slot_fences[slot] > completed) {
    return;
  }
  GpuProfileSample sample{};
  sample.eye = eye;
  sample.slot = slot;
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
                                  D3D12_QUERY_TYPE_TIMESTAMP, slot * 3U);
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
  const auto query_start = sample.slot * 3U;
  sample.end_commands->EndQuery(gpu_profile_query_heap.Get(),
                                D3D12_QUERY_TYPE_TIMESTAMP,
                                query_start + 2U);
  sample.end_commands->ResolveQueryData(
      gpu_profile_query_heap.Get(), D3D12_QUERY_TYPE_TIMESTAMP, query_start,
      3, gpu_profile_readback.Get(),
      static_cast<UINT64>(query_start) * sizeof(std::uint64_t));
  if (FAILED(sample.end_commands->Close())) {
    return;
  }
  ID3D12CommandList* lists[]{sample.end_commands.Get()};
  original_execute_command_lists(queue, 1, lists);
  sample.fence_value = ++gpu_profile_next_fence;
  if (FAILED(queue->Signal(gpu_profile_fence.Get(), sample.fence_value))) {
    return;
  }
  gpu_profile_slot_fences[sample.slot] = sample.fence_value;
  gpu_profile_pending.push_back(std::move(sample));
}

constexpr wchar_t kLeftEyeName[] = L"Local\\DarktideVR-eye-left";
constexpr wchar_t kRightEyeName[] = L"Local\\DarktideVR-eye-right";
constexpr wchar_t kReadyFenceName[] = L"Local\\DarktideVR-eye-ready";
constexpr wchar_t kConsumedFenceName[] = L"Local\\DarktideVR-eye-consumed";

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
  constexpr std::array<std::uint64_t, 5> known{
      0x6e5fa4d1f1e2cd16ULL, 0x25920ba45ba58e76ULL,
      0xaf848a96a230342aULL, 0x903cb53d8ac05f28ULL,
      0x13e04962148fc216ULL};
  return std::find(known.begin(), known.end(), hash) != known.end();
}

std::optional<std::size_t> billboard_vertex_shader_index(
    std::uint64_t hash) {
  constexpr std::array<std::uint64_t, 5> known{
      0x6e5fa4d1f1e2cd16ULL, 0x25920ba45ba58e76ULL,
      0xaf848a96a230342aULL, 0x903cb53d8ac05f28ULL,
      0x13e04962148fc216ULL};
  const auto found = std::find(known.begin(), known.end(), hash);
  return found == known.end()
             ? std::nullopt
             : std::optional<std::size_t>(found - known.begin());
}

bool compatible_shader_interfaces(const D3D12_SHADER_BYTECODE& original,
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
  constexpr std::array<std::uint64_t, 5> known{
      0x6e5fa4d1f1e2cd16ULL, 0x25920ba45ba58e76ULL,
      0xaf848a96a230342aULL, 0x903cb53d8ac05f28ULL,
      0x13e04962148fc216ULL};
  const auto directory = native_capture_directory();
  std::scoped_lock lock(billboard_shader_replacement_mutex);
  billboard_shader_replacements.clear();
  for (const auto hash : known) {
    wchar_t name[96]{};
    swprintf_s(name, L"billboard_shaders\\vs-%016llx.dxil",
               static_cast<unsigned long long>(hash));
    auto bytes = read_binary_file(directory + name);
    if (!bytes.empty()) {
      billboard_shader_replacements.emplace(hash, std::move(bytes));
    }
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
  write_focused_log(
      "phase=%d\tframe=%llu\tCL=%p\tDRAW\teye=%d\tvpx=%u\tvpy=%u\tvpw=%u\tvph=%u\tsc=%ld,%ld,%ld,%ld\tkind=%llu\ta=%llu,%llu,%llu,%llu,%llu\tcoarse=%llu\texact=%llu\tpso=%p\tsig=%p\ttopo=%u\trtv=%llu\tdsv=%llu\tib=%llu,%u,%u\tvb0=%llu,%u,%u\tvb1=%llu,%u,%u\tbind=%llu\ttables=%llu\tconstants=%llu\tcbvs=%llu\tt4=%llu\tt7=%llu\tcbv1=%llu\ts4=%u,%llu,%llu,%u,%p,%llu,%u,%u,%p\ts7=%u,%llu,%llu\r\n",
      phase, present_count.load(std::memory_order_relaxed), commands,
      trace.eye, trace.viewport_x, trace.viewport_y, trace.viewport_width,
      trace.viewport_height, trace.scissor.left, trace.scissor.top,
      trace.scissor.right, trace.scissor.bottom, draw_kind, argument0,
      argument1, argument2, argument3, argument4, coarse, exact,
      reinterpret_cast<void*>(trace.pso),
      reinterpret_cast<void*>(trace.root_signature),
      static_cast<UINT>(trace.primitive_topology), trace.render_target,
      trace.depth_target, trace.index_buffer.BufferLocation,
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
    D3D12_SIGNATURE_PARAMETER_DESC b{};
    if (FAILED(left->GetOutputParameterDesc(index, &a)) ||
        FAILED(right->GetOutputParameterDesc(index, &b)) ||
        !compatible_signature_parameter(a, b)) {
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
      if (right_buffer && SUCCEEDED(right_buffer->GetDesc(&right_buffer_desc)) &&
          left_buffer_desc.Size == right_buffer_desc.Size &&
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
    bool* substituted = nullptr) {
  PsoMetadata metadata{};
  const auto* stream = static_cast<const std::uint8_t*>(
      description.pPipelineStateSubobjectStream);
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
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        metadata.pixel_shader = read ? hash_bytecode(value) : 0;
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
                                     value);
        metadata.blend_enabled = read && value.RenderTarget[0].BlendEnable;
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DEPTH_STENCIL: {
        D3D12_DEPTH_STENCIL_DESC value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        metadata.depth_enabled = read && value.DepthEnable;
        break;
      }
      case D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DEPTH_STENCIL1: {
        D3D12_DEPTH_STENCIL_DESC1 value{};
        read = read_stream_subobject(stream, description.SizeInBytes, offset,
                                     value);
        metadata.depth_enabled = read && value.DepthEnable;
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
  return metadata;
}

HRESULT STDMETHODCALLTYPE create_pipeline_state_stream_hook(
    ID3D12Device2* device, const D3D12_PIPELINE_STATE_STREAM_DESC* description,
    REFIID iid, void** output) {
  diagnostic_stream_pso_create_count.fetch_add(1, std::memory_order_relaxed);
  std::vector<std::uint8_t> replacement_stream;
  D3D12_PIPELINE_STATE_STREAM_DESC replacement_description{};
  bool substituted{};
  std::uint64_t original_vertex_shader{};
  const auto* effective_description = description;
  if (description && description->pPipelineStateSubobjectStream &&
      description->SizeInBytes > 0) {
    const auto* bytes = static_cast<const std::uint8_t*>(
        description->pPipelineStateSubobjectStream);
    replacement_stream.assign(bytes, bytes + description->SizeInBytes);
    original_vertex_shader =
        inspect_pipeline_stream(*description, &replacement_stream,
                                &substituted)
            .vertex_shader;
    if (substituted) {
      replacement_description = *description;
      replacement_description.pPipelineStateSubobjectStream =
          replacement_stream.data();
      effective_description = &replacement_description;
    }
  }
  auto result = original_create_pipeline_state_stream(
      device, effective_description, iid, output);
  if (FAILED(result) && substituted) {
    record_billboard_shader_creation_result(original_vertex_shader, false);
    result = original_create_pipeline_state_stream(device, description, iid,
                                                   output);
    substituted = false;
  }
  if (SUCCEEDED(result) && substituted) {
    record_billboard_shader_creation_result(original_vertex_shader, true);
  }
  if (SUCCEEDED(result) && description && output && *output) {
    auto metadata = inspect_pipeline_stream(*description);
    record_pso_shader_mapping_if_requested(
        reinterpret_cast<ID3D12PipelineState*>(*output), metadata);
    std::scoped_lock lock(pso_mutex);
    pso_metadata[reinterpret_cast<std::uintptr_t>(*output)] = metadata;
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

bool is_named_eye_output_resource(ID3D12Resource* resource) {
  const auto name = resource_debug_name(resource);
  return name == "0x388e18bf99514d34" || // darktidevr_left_eye_output
         name == "0x81442e111aacc90e";   // darktidevr_right_eye_output
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
      std::scoped_lock lock(buffer_resource_mutex);
      buffer_resources.push_back(BufferResourceInfo{
          resource, gpu_start, description->Width,
          properties ? properties->Type : D3D12_HEAP_TYPE_CUSTOM});
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
      std::scoped_lock lock(buffer_resource_mutex);
      buffer_resources.push_back(BufferResourceInfo{
          resource, gpu_start, description->Width,
          heap_description.Properties.Type});
    }
  }
  return result;
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
    dump_vertex_shader_if_requested(description->VS,
                                    &description->InputLayout);
  }
  D3D12_GRAPHICS_PIPELINE_STATE_DESC replacement_description{};
  D3D12_SHADER_BYTECODE replacement_shader{};
  bool substituted{};
  const auto* effective_description = description;
  if (description && select_billboard_shader_replacement(
                         description->VS, replacement_shader)) {
    replacement_description = *description;
    replacement_description.VS = replacement_shader;
    // Cached PSO data describes the original shader and must not be offered to
    // D3D12 after changing the VS.
    replacement_description.CachedPSO = {};
    effective_description = &replacement_description;
    substituted = true;
  }
  auto result = original_create_graphics_pipeline_state(
      device, effective_description, iid, output);
  if (FAILED(result) && substituted) {
    record_billboard_shader_creation_result(hash_bytecode(description->VS),
                                            false);
    result = original_create_graphics_pipeline_state(device, description, iid,
                                                     output);
    substituted = false;
  }
  if (SUCCEEDED(result) && substituted) {
    record_billboard_shader_creation_result(hash_bytecode(description->VS),
                                            true);
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
    record_pso_shader_mapping_if_requested(
        reinterpret_cast<ID3D12PipelineState*>(*output), metadata);
    std::scoped_lock lock(pso_mutex);
    pso_metadata[reinterpret_cast<std::uintptr_t>(*output)] = metadata;
  }
  return result;
}

HRESULT STDMETHODCALLTYPE create_compute_pipeline_state_hook(
    ID3D12Device* device, const D3D12_COMPUTE_PIPELINE_STATE_DESC* description,
    REFIID iid, void** output) {
  diagnostic_compute_pso_create_count.fetch_add(1,
                                                std::memory_order_relaxed);
  const auto result = original_create_compute_pipeline_state(
      device, description, iid, output);
  if (SUCCEEDED(result) && description && output && *output) {
    PsoMetadata metadata{};
    metadata.kind = 'C';
    metadata.compute_shader = hash_bytecode(description->CS);
    std::scoped_lock lock(pso_mutex);
    pso_metadata[reinterpret_cast<std::uintptr_t>(*output)] = metadata;
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
    dump_vertex_shader_if_requested(description->VS,
                                    &description->InputLayout);
  }
  D3D12_GRAPHICS_PIPELINE_STATE_DESC replacement_description{};
  D3D12_SHADER_BYTECODE replacement_shader{};
  bool substituted{};
  const auto* effective_description = description;
  if (description && select_billboard_shader_replacement(
                         description->VS, replacement_shader)) {
    replacement_description = *description;
    replacement_description.VS = replacement_shader;
    replacement_description.CachedPSO = {};
    effective_description = &replacement_description;
    substituted = true;
  }
  HRESULT result{};
  if (substituted) {
    ComPtr<ID3D12Device> device;
    result = FAILED(library->GetDevice(IID_PPV_ARGS(&device)))
                 ? E_NOINTERFACE
                 : original_create_graphics_pipeline_state(
                       device.Get(), effective_description, iid, output);
  } else {
    result = original_load_graphics_pipeline(
        library, name, effective_description, iid, output);
  }
  if (FAILED(result) && substituted) {
    record_billboard_shader_creation_result(hash_bytecode(description->VS),
                                            false);
    result = original_load_graphics_pipeline(library, name, description, iid,
                                             output);
    substituted = false;
  }
  if (SUCCEEDED(result) && substituted) {
    record_billboard_shader_creation_result(hash_bytecode(description->VS),
                                            true);
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
    record_pso_shader_mapping_if_requested(
        reinterpret_cast<ID3D12PipelineState*>(*output), metadata);
    std::scoped_lock lock(pso_mutex);
    pso_metadata[reinterpret_cast<std::uintptr_t>(*output)] = metadata;
  }
  return result;
}

HRESULT STDMETHODCALLTYPE load_compute_pipeline_hook(
    ID3D12PipelineLibrary* library, LPCWSTR name,
    const D3D12_COMPUTE_PIPELINE_STATE_DESC* description, REFIID iid,
    void** output) {
  diagnostic_compute_pipeline_load_count.fetch_add(1,
                                                   std::memory_order_relaxed);
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
  std::uint64_t original_vertex_shader{};
  const auto* effective_description = description;
  if (description && description->pPipelineStateSubobjectStream &&
      description->SizeInBytes > 0) {
    const auto* bytes = static_cast<const std::uint8_t*>(
        description->pPipelineStateSubobjectStream);
    replacement_stream.assign(bytes, bytes + description->SizeInBytes);
    original_vertex_shader =
        inspect_pipeline_stream(*description, &replacement_stream,
                                &substituted)
            .vertex_shader;
    if (substituted) {
      replacement_description = *description;
      replacement_description.pPipelineStateSubobjectStream =
          replacement_stream.data();
      effective_description = &replacement_description;
    }
  }
  HRESULT result{};
  if (substituted) {
    ComPtr<ID3D12Device2> device;
    result = FAILED(library->GetDevice(IID_PPV_ARGS(&device)))
                 ? E_NOINTERFACE
                 : original_create_pipeline_state_stream(
                       device.Get(), effective_description, iid, output);
  } else {
    result = original_load_pipeline(library, name, effective_description, iid,
                                    output);
  }
  if (FAILED(result) && substituted) {
    record_billboard_shader_creation_result(original_vertex_shader, false);
    result = original_load_pipeline(library, name, description, iid, output);
    substituted = false;
  }
  if (SUCCEEDED(result) && substituted) {
    record_billboard_shader_creation_result(original_vertex_shader, true);
  }
  if (SUCCEEDED(result) && description && output && *output) {
    auto metadata = inspect_pipeline_stream(*description);
    record_pso_shader_mapping_if_requested(
        reinterpret_cast<ID3D12PipelineState*>(*output), metadata);
    std::scoped_lock lock(pso_mutex);
    pso_metadata[reinterpret_cast<std::uintptr_t>(*output)] = metadata;
  }
  return result;
}

HRESULT STDMETHODCALLTYPE close_hook(ID3D12GraphicsCommandList* commands) {
  if (marker_log != INVALID_HANDLE_VALUE) {
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
  return original_close(commands);
}

HRESULT STDMETHODCALLTYPE reset_hook(ID3D12GraphicsCommandList* commands,
                                     ID3D12CommandAllocator* allocator,
                                     ID3D12PipelineState* initial_state) {
  if (marker_log != INVALID_HANDLE_VALUE ||
      billboard_horizon_lock_enabled.load(std::memory_order_relaxed)) {
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    trace = {};
    trace.pso = reinterpret_cast<std::uintptr_t>(initial_state);
  }
  if (rich_center_sbs_remap_enabled.load(std::memory_order_relaxed)) {
    std::scoped_lock lock(viewport_remap_mutex);
    viewport_remap_states.erase(commands);
  }
  {
    std::scoped_lock lock(boundary_capture_mutex);
    present_transition_resources.erase(commands);
    swapchain_write_resources.erase(commands);
    camera_output_resources.erase(commands);
    camera_output_source_states.erase(commands);
    const auto candidates = camera_output_candidates.find(commands);
    if (candidates != camera_output_candidates.end()) {
      candidates->second.clear();
    }
    command_transition_ordinals.erase(commands);
    command_marker_stacks.erase(commands);
  }
  return original_reset(commands, allocator, initial_state);
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

  bool first_observation{};
  {
    std::scoped_lock lock(buffer_resource_mutex);
    first_observation = billboard_tested_cbvs.insert(
        descriptor.gpu_address).second;
  }
  if (!first_observation) {
    return;
  }
  void* mapped{};
  const auto resource_offset = descriptor.gpu_address - resource->gpu_start;
  const auto readable_size = (std::min<std::uint64_t>)(
      descriptor.width == 0 ? 132 : descriptor.width,
      resource->size - resource_offset);
  const D3D12_RANGE cpu_read_range{
      static_cast<SIZE_T>(resource_offset),
      static_cast<SIZE_T>(resource_offset + readable_size)};
  if (SUCCEEDED(resource->resource->Map(0, &cpu_read_range, &mapped)) && mapped) {
    billboard_exact_map_success_count.fetch_add(1,
                                                 std::memory_order_relaxed);
    const auto sample_index =
        billboard_cbv_log_count.fetch_add(1, std::memory_order_relaxed);
    if (sample_index < 32 && readable_size >= sizeof(float)) {
      std::scoped_lock log_lock(billboard_cbv_log_mutex);
      std::array<wchar_t, MAX_PATH> temp{};
      if (GetTempPathW(static_cast<DWORD>(temp.size()), temp.data()) != 0) {
        std::wstring path(temp.data());
        path += L"darktidevr-billboard-cbv.tsv";
        const DWORD disposition =
            billboard_cbv_log_initialized ? OPEN_ALWAYS : CREATE_ALWAYS;
        HANDLE log = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                                 nullptr, disposition, FILE_ATTRIBUTE_NORMAL,
                                 nullptr);
        if (log != INVALID_HANDLE_VALUE) {
          billboard_cbv_log_initialized = true;
          std::array<char, 4096> line{};
          int length = std::snprintf(
              line.data(), line.size(),
              "%llu\tgpu=%llu\tbase=%llu\toffset=%llu\tcbv_size=%llu\theap=%u",
              static_cast<unsigned long long>(sample_index),
              static_cast<unsigned long long>(descriptor.gpu_address),
              static_cast<unsigned long long>(resource->gpu_start),
              static_cast<unsigned long long>(resource_offset),
              static_cast<unsigned long long>(descriptor.width),
              static_cast<unsigned>(resource->heap_type));
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
    const D3D12_RANGE no_cpu_writes{0, 0};
    resource->resource->Unmap(0, &no_cpu_writes);
  } else {
    billboard_exact_map_failure_count.fetch_add(1,
                                                 std::memory_order_relaxed);
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
  constexpr std::array<std::uint64_t, 5> kBillboardVertexShaders{
      0x6e5fa4d1f1e2cd16ULL, 0x25920ba45ba58e76ULL,
      0xaf848a96a230342aULL, 0x903cb53d8ac05f28ULL,
      0x13e04962148fc216ULL};
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
  (void)kBillboardVertexShaders;

  bool billboard_pso{};
  UINT billboard_register = UINT_MAX;
  {
    std::scoped_lock lock(pso_mutex);
    const auto found = pso_metadata.find(pipeline);
    if (found != pso_metadata.end()) {
      billboard_pso = found->second.billboard_shader ||
                      is_billboard_vertex_shader(found->second.vertex_shader);
      billboard_register = found->second.billboard_register;
      if (billboard_register == UINT_MAX &&
          is_billboard_vertex_shader(found->second.vertex_shader)) {
        billboard_register = 2;
      }
    }
  }
  if (!billboard_pso || billboard_register == UINT_MAX) {
    return override_state;
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
      }
    }
  }
  if (!billboard_basis_write_enabled.load(std::memory_order_relaxed)) {
    return override_state;
  }
  if (billboard_table_index != UINT_MAX && billboard_descriptor.kind == 'C') {
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

void STDMETHODCALLTYPE draw_instanced_hook(ID3D12GraphicsCommandList* commands,
                                           UINT vertex_count,
                                           UINT instance_count,
                                           UINT start_vertex,
                                           UINT start_instance) {
  billboard_direct_draw_hook_count.fetch_add(1, std::memory_order_relaxed);
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
        trace.viewport_width == camera_output_width &&
        trace.viewport_height == camera_output_height &&
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
  const auto billboard_override = apply_billboard_view_basis(commands);
  original_draw_instanced(commands, vertex_count, instance_count, start_vertex,
                          start_instance);
  end_billboard_binding_override(commands, billboard_override);
}

void STDMETHODCALLTYPE draw_indexed_instanced_hook(
    ID3D12GraphicsCommandList* commands, UINT index_count, UINT instance_count,
    UINT start_index, INT base_vertex, UINT start_instance) {
  billboard_direct_draw_hook_count.fetch_add(1, std::memory_order_relaxed);
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
  original_draw_indexed_instanced(commands, index_count,
                                  submitted_instance_count, start_index,
                                  base_vertex, start_instance);
  end_billboard_binding_override(commands, billboard_override);
}

void STDMETHODCALLTYPE dispatch_hook(ID3D12GraphicsCommandList* commands,
                                     UINT x, UINT y, UINT z) {
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
  original_dispatch(commands, x, y, z);
}

void STDMETHODCALLTYPE rs_set_viewports_hook(ID3D12GraphicsCommandList* commands,
                                             UINT count,
                                             const D3D12_VIEWPORT* viewports) {
  if (marker_log != INVALID_HANDLE_VALUE && count > 0 && viewports) {
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
  if (marker_log != INVALID_HANDLE_VALUE ||
      billboard_horizon_lock_enabled.load(std::memory_order_relaxed)) {
    bool metadata_missing{};
    {
      std::scoped_lock lock(pso_mutex);
      metadata_missing = state &&
                         pso_metadata.find(reinterpret_cast<std::uintptr_t>(state)) ==
                             pso_metadata.end();
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
    command_traces[commands].pso = reinterpret_cast<std::uintptr_t>(state);
    if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
      write_focused_log("phase=%d\tframe=%llu\tCL=%p\tPSO\tpso=%p\r\n",
                        focused_trace_phase.load(std::memory_order_relaxed),
                        present_count.load(std::memory_order_relaxed), commands,
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
  if (marker_log != INVALID_HANDLE_VALUE) {
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
       billboard_horizon_lock_enabled.load(std::memory_order_relaxed)) &&
      root_index < kRootSlotCount) {
    std::scoped_lock lock(trace_mutex);
    command_traces[commands].graphics_tables[root_index] = table.ptr;
  }
  original_set_graphics_root_descriptor_table(commands, root_index, table);
}

void STDMETHODCALLTYPE set_compute_root_descriptor_table_hook(
    ID3D12GraphicsCommandList* commands, UINT root_index,
    D3D12_GPU_DESCRIPTOR_HANDLE table) {
  if (marker_log != INVALID_HANDLE_VALUE && root_index < kRootSlotCount) {
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
  if (marker_log != INVALID_HANDLE_VALUE && root_index < kRootSlotCount) {
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
  if (marker_log != INVALID_HANDLE_VALUE && root_index < kRootSlotCount) {
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
  if (marker_log != INVALID_HANDLE_VALUE && root_index < kRootSlotCount) {
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
                         active->slot * 3U + 1U);
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
  if (count > 0 && targets) {
    const auto target = descriptor_snapshot(targets[0].ptr);
    record_gpu_stage_boundary(commands, target);
    auto* resource = reinterpret_cast<ID3D12Resource*>(target.resource);
    if (resource) {
      std::scoped_lock lock(boundary_capture_mutex);
      if (swapchain_back_buffers.find(resource) !=
          swapchain_back_buffers.end()) {
        swapchain_write_resources[commands] = resource;
        swapchain_back_buffer_states[resource] =
            D3D12_RESOURCE_STATE_RENDER_TARGET;
        boundary_transition_count.fetch_add(1, std::memory_order_relaxed);
      }
    }
  }
  if (marker_log != INVALID_HANDLE_VALUE) {
    std::scoped_lock lock(trace_mutex);
    auto& trace = command_traces[commands];
    trace.render_target_count = count;
    trace.render_target =
        count > 0 && targets ? static_cast<std::uint64_t>(targets[0].ptr) : 0;
    trace.depth_target =
        depth ? static_cast<std::uint64_t>(depth->ptr) : 0;
    if (focused_trace_phase.load(std::memory_order_relaxed) != 0) {
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
  const bool census_enabled = boundary_census_log != INVALID_HANDLE_VALUE;
  const bool enhanced_log_enabled =
      enhanced_barrier_log != INVALID_HANDLE_VALUE;
  const bool collect_candidates =
      census_enabled ||
      camera_output_candidate_index.load(std::memory_order_relaxed) >= 0;
  if (barriers) {
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
          boundary_transition_count.fetch_add(1, std::memory_order_relaxed);
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
        DescriptorInfo stage_target{};
        stage_target.width = description.Width;
        stage_target.height = description.Height;
        record_gpu_stage_boundary(commands, stage_target);
        if (census_enabled &&
            description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
            description.Width == camera_output_width &&
            description.Height == camera_output_height &&
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
            description.Width == camera_output_width &&
            description.Height == camera_output_height &&
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
        const auto is_named_eye_final =
            !is_known_output &&
            description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
            description.Width == camera_output_width &&
            description.Height == camera_output_height &&
            is_named_eye_final_resource(barrier.Transition.pResource);
        if (is_named_eye_final && !is_known_output) {
          known_camera_output_resources.insert(barrier.Transition.pResource);
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
            description.Width == camera_output_width &&
            description.Height == camera_output_height &&
            (description.Format == camera_output_format ||
             is_named_eye_final || is_known_output) &&
            barrier.Transition.StateAfter == D3D12_RESOURCE_STATE_RENDER_TARGET &&
            barrier.Flags == D3D12_RESOURCE_BARRIER_FLAG_NONE &&
            is_output_reuse_begin && !is_known_output) {
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
            description.Width == camera_output_width &&
            description.Height == camera_output_height &&
            (description.Format == camera_output_format ||
             is_named_eye_final || is_known_output) &&
            barrier.Transition.StateBefore ==
                D3D12_RESOURCE_STATE_RENDER_TARGET &&
            barrier.Transition.StateAfter == shader_resource_state &&
            barrier.Flags == D3D12_RESOURCE_BARRIER_FLAG_NONE &&
            is_known_output;
        if (census_enabled &&
            description.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D &&
            description.Width == camera_output_width &&
            description.Height == camera_output_height &&
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
}

void STDMETHODCALLTYPE enhanced_barrier_hook(
    ID3D12GraphicsCommandList7* commands, UINT32 group_count,
    const D3D12_BARRIER_GROUP* groups) {
  const bool log_resources = boundary_census_log != INVALID_HANDLE_VALUE ||
                             enhanced_barrier_log != INVALID_HANDLE_VALUE;
  if (groups) {
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
              description.Width == camera_output_width &&
              description.Height == camera_output_height &&
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
        boundary_transition_count.fetch_add(1, std::memory_order_relaxed);
      }
    }
  }
  original_enhanced_barrier(commands, group_count, groups);
}

void STDMETHODCALLTYPE execute_command_lists_hook(
    ID3D12CommandQueue* queue, UINT count, ID3D12CommandList* const* lists) {
  const auto description = queue->GetDesc();
  if (description.Type == D3D12_COMMAND_LIST_TYPE_DIRECT) {
    std::scoped_lock lock(state_mutex);
    if (!game_queue) {
      game_queue = queue;
    }
  }
  execute_call_count.fetch_add(1, std::memory_order_relaxed);
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
  ComPtr<ID3D12Resource> completed_back_buffer;
  auto completed_source_state = D3D12_RESOURCE_STATE_RENDER_TARGET;
  if (description.Type == D3D12_COMMAND_LIST_TYPE_DIRECT && count > 0) {
    std::scoped_lock lock(boundary_capture_mutex);
    for (UINT index = 0; index < count; ++index) {
      auto* graphics = static_cast<ID3D12GraphicsCommandList*>(lists[index]);
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
        const auto state_found = camera_output_source_states.find(graphics);
        if (state_found != camera_output_source_states.end()) {
          completed_source_state = state_found->second;
        }
      }
      camera_output_resources.erase(found);
      camera_output_source_states.erase(graphics);
      if (candidates_found != camera_output_candidates.end()) {
        candidates_found->second.clear();
      }
      present_transition_resources.erase(graphics);
    }
  }
  original_execute_command_lists(queue, count, lists);
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
          (void)shared_head_pose_reader().publish_rendered_pair(
              {ready_after,
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

HRESULT STDMETHODCALLTYPE resize_buffers_hook(IDXGISwapChain* swapchain,
                                               UINT buffer_count, UINT width,
                                               UINT height, DXGI_FORMAT format,
                                               UINT flags) {
  if (swapchain_render_extent_enabled.load(std::memory_order_acquire)) {
    width = swapchain_render_width.load(std::memory_order_relaxed);
    height = swapchain_render_height.load(std::memory_order_relaxed);
  }
  {
    std::scoped_lock lock(boundary_capture_mutex);
    swapchain_back_buffers.clear();
    swapchain_back_buffer_states.clear();
    camera_output_resources.clear();
    camera_output_source_states.clear();
    known_camera_output_resources.clear();
    camera_output_realign_pending = false;
    present_transition_resources.clear();
  }
  return original_resize_buffers(swapchain, buffer_count, width, height,
                                 format, flags);
}

HRESULT STDMETHODCALLTYPE resize_buffers1_hook(
    IDXGISwapChain3* swapchain, UINT buffer_count, UINT width, UINT height,
    DXGI_FORMAT format, UINT flags, const UINT* creation_node_masks,
    IUnknown* const* present_queues) {
  if (swapchain_render_extent_enabled.load(std::memory_order_acquire)) {
    width = swapchain_render_width.load(std::memory_order_relaxed);
    height = swapchain_render_height.load(std::memory_order_relaxed);
  }
  {
    std::scoped_lock lock(boundary_capture_mutex);
    swapchain_back_buffers.clear();
    swapchain_back_buffer_states.clear();
    camera_output_resources.clear();
    camera_output_source_states.clear();
    known_camera_output_resources.clear();
    camera_output_realign_pending = false;
    present_transition_resources.clear();
  }
  return original_resize_buffers1(swapchain, buffer_count, width, height,
                                  format, flags, creation_node_masks,
                                  present_queues);
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
  if (!message || message->message != WM_SIZE ||
      !virtual_size_message_enabled.load(std::memory_order_acquire) ||
      message->hwnd != game_output_window.load(std::memory_order_relaxed)) {
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
    if (SetWindowPos(window, nullptr, 0, 0, outer.right - outer.left,
                     outer.bottom - outer.top,
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)) {
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
    if (SetWindowPos(window, nullptr, 0, 0, restore_width, restore_height,
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)) {
      swapchain_resize_nudge_phase.store(2, std::memory_order_relaxed);
    }
  }
}

HRESULT STDMETHODCALLTYPE present_hook(IDXGISwapChain* swapchain,
                                        UINT interval, UINT flags) {
  if (kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed)) {
    std::scoped_lock lock(trace_mutex);
    frame_eye0_table4_draws.clear();
    candidate_frame_eye0_table4 = {};
    candidate_frame_eye0_instance_count = 0;
  }
  const auto present = present_count.fetch_add(1, std::memory_order_relaxed) + 1;
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
  ComPtr<ID3D12Device> device;
  ComPtr<IDXGISwapChain3> candidate;
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
      std::scoped_lock lock(boundary_capture_mutex);
      swapchain_back_buffers = std::move(buffers);
      for (auto* buffer : swapchain_back_buffers) {
        swapchain_back_buffer_states[buffer] = D3D12_RESOURCE_STATE_PRESENT;
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
  {
    std::scoped_lock lock(state_mutex);
    queue = game_queue;
  }
  if (present_capture_enabled.load(std::memory_order_relaxed) && candidate &&
      queue) {
    alternating_last_capture_result.store(
        capture_present_halves(candidate.Get(), queue.Get()),
        std::memory_order_relaxed);
  }
  const auto result = original_present(swapchain, interval, flags);
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
  if (boundary_census_log != INVALID_HANDLE_VALUE) {
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
  if (boundary_census_log != INVALID_HANDLE_VALUE) {
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
  auto** command_list_vtable =
      *reinterpret_cast<void***>(dummy_commands.Get());
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
  const auto install_pso_substitution_hooks =
      kInstallDiagnosticRenderHooks.load(std::memory_order_relaxed) ||
      billboard_shader_substitution_requested.load(std::memory_order_relaxed);
  if (MH_Initialize() != MH_OK ||
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
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[11], &create_compute_pipeline_state_hook,
                    reinterpret_cast<void**>(
                        &original_create_compute_pipeline_state)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[14], &create_descriptor_heap_hook,
                     reinterpret_cast<void**>(
                         &original_create_descriptor_heap)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[16], &create_root_signature_hook,
                    reinterpret_cast<void**>(
                        &original_create_root_signature)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[17], &create_constant_buffer_view_hook,
                    reinterpret_cast<void**>(
                        &original_create_constant_buffer_view)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[18], &create_shader_resource_view_hook,
                    reinterpret_cast<void**>(
                        &original_create_shader_resource_view)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[19], &create_unordered_access_view_hook,
                    reinterpret_cast<void**>(
                        &original_create_unordered_access_view)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[20], &create_render_target_view_hook,
                     reinterpret_cast<void**>(
                         &original_create_render_target_view)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[21], &create_depth_stencil_view_hook,
                    reinterpret_cast<void**>(
                        &original_create_depth_stencil_view)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[23], &copy_descriptors_hook,
                     reinterpret_cast<void**>(
                         &original_copy_descriptors)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[24], &copy_descriptors_simple_hook,
                     reinterpret_cast<void**>(
                         &original_copy_descriptors_simple)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[27], &create_committed_resource_hook,
                    reinterpret_cast<void**>(
                        &original_create_committed_resource)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(device_vtable[29], &create_placed_resource_hook,
                    reinterpret_cast<void**>(
                        &original_create_placed_resource)) != MH_OK) ||
      (install_pso_substitution_hooks &&
       MH_CreateHook(device2_vtable[47], &create_pipeline_state_stream_hook,
                    reinterpret_cast<void**>(
                        &original_create_pipeline_state_stream)) != MH_OK) ||
      (install_pso_substitution_hooks &&
       MH_CreateHook(pipeline_library_vtable[9], &load_graphics_pipeline_hook,
                    reinterpret_cast<void**>(
                        &original_load_graphics_pipeline)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(pipeline_library_vtable[10], &load_compute_pipeline_hook,
                    reinterpret_cast<void**>(
                        &original_load_compute_pipeline)) != MH_OK) ||
      (install_pso_substitution_hooks &&
       MH_CreateHook(pipeline_library1_vtable[13], &load_pipeline_hook,
                    reinterpret_cast<void**>(&original_load_pipeline)) !=
          MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[9], &close_hook,
                    reinterpret_cast<void**>(&original_close)) != MH_OK) ||
      MH_CreateHook(command_list_vtable[10], &reset_hook,
                    reinterpret_cast<void**>(&original_reset)) != MH_OK ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[12], &draw_instanced_hook,
                     reinterpret_cast<void**>(&original_draw_instanced)) !=
           MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[13], &draw_indexed_instanced_hook,
                     reinterpret_cast<void**>(
                         &original_draw_indexed_instanced)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[14], &dispatch_hook,
                     reinterpret_cast<void**>(&original_dispatch)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[20],
                    &ia_set_primitive_topology_hook,
                    reinterpret_cast<void**>(
                        &original_ia_set_primitive_topology)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[21], &rs_set_viewports_hook,
                     reinterpret_cast<void**>(&original_rs_set_viewports)) !=
           MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[22], &rs_set_scissor_rects_hook,
                     reinterpret_cast<void**>(
                         &original_rs_set_scissor_rects)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[25], &set_pipeline_state_hook,
                     reinterpret_cast<void**>(&original_set_pipeline_state)) !=
           MH_OK) ||
      MH_CreateHook(command_list_vtable[26], &resource_barrier_hook,
                    reinterpret_cast<void**>(&original_resource_barrier)) != MH_OK ||
      (enhanced_barriers_available &&
       MH_CreateHook(command_list7_vtable[80], &enhanced_barrier_hook,
                     reinterpret_cast<void**>(&original_enhanced_barrier)) !=
           MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[28], &set_descriptor_heaps_hook,
                     reinterpret_cast<void**>(
                         &original_set_descriptor_heaps)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[29], &set_compute_root_signature_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_signature)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[30],
                    &set_graphics_root_signature_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_signature)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[31],
                    &set_compute_root_descriptor_table_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_descriptor_table)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[32],
                    &set_graphics_root_descriptor_table_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_descriptor_table)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[33],
                    &set_compute_root_32bit_constant_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_32bit_constant)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[34],
                    &set_graphics_root_32bit_constant_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_32bit_constant)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[35],
                    &set_compute_root_32bit_constants_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_32bit_constants)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[36],
                    &set_graphics_root_32bit_constants_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_32bit_constants)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[37],
                    &set_compute_root_constant_buffer_view_hook,
                    reinterpret_cast<void**>(
                        &original_set_compute_root_constant_buffer_view)) !=
           MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[38],
                    &set_graphics_root_constant_buffer_view_hook,
                    reinterpret_cast<void**>(
                        &original_set_graphics_root_constant_buffer_view)) !=
           MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
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
      (kInstallDiagnosticRenderHooks &&
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
      (kInstallDiagnosticRenderHooks &&
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
      MH_CreateHook(swapchain_vtable[8], &present_hook,
                     reinterpret_cast<void**>(&original_present)) != MH_OK ||
      MH_CreateHook(swapchain_vtable[13], &resize_buffers_hook,
                    reinterpret_cast<void**>(&original_resize_buffers)) !=
          MH_OK ||
      MH_CreateHook(swapchain_vtable[39], &resize_buffers1_hook,
                    reinterpret_cast<void**>(&original_resize_buffers1)) !=
          MH_OK ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[55], &set_marker_hook,
                     reinterpret_cast<void**>(&original_set_marker)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[56], &begin_event_hook,
                     reinterpret_cast<void**>(&original_begin_event)) != MH_OK) ||
      (kInstallDiagnosticRenderHooks &&
       MH_CreateHook(command_list_vtable[57], &end_event_hook,
                     reinterpret_cast<void**>(&original_end_event)) != MH_OK) ||
      MH_EnableHook(MH_ALL_HOOKS) != MH_OK) {
    DestroyWindow(window);
    UnregisterClassW(class_name, window_class.hInstance);
    return 14;
  }

  DestroyWindow(window);
  UnregisterClassW(class_name, window_class.hInstance);
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
  if (eye_surfaces[0] &&
      eye_surfaces[0]->GetDesc().Width == eye_width &&
      eye_surfaces[0]->GetDesc().Height == eye_height &&
      eye_surfaces[0]->GetDesc().Format == source_description.Format) {
    return 0;
  }

  close_shared_handles();
  eye_surfaces = {};
  ready_fence.Reset();
  consumed_fence.Reset();
  ready_value = 0;
  pending_captures.clear();
  available_captures.clear();
  staged_eye0_capture = {};
  staged_eye0_capture_valid = false;
  staged_pair_dropped = false;

  D3D12_HEAP_PROPERTIES heap{};
  heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  auto eye_description = source_description;
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
      return 20 + static_cast<int>(eye);
    }
    if (FAILED(device->CreateSharedHandle(eye_surfaces[eye].Get(), nullptr,
                                          GENERIC_ALL, names[eye],
                                          &eye_handles[eye]))) {
      return 22 + static_cast<int>(eye);
    }
  }
  if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                                 IID_PPV_ARGS(&ready_fence))) ||
      FAILED(device->CreateSharedHandle(ready_fence.Get(), nullptr, GENERIC_ALL,
                                        kReadyFenceName,
                                        &ready_fence_handle))) {
    return 24;
  }
  if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED,
                                 IID_PPV_ARGS(&consumed_fence))) ||
      FAILED(device->CreateSharedHandle(
          consumed_fence.Get(), nullptr, GENERIC_ALL, kConsumedFenceName,
          &consumed_fence_handle))) {
    return 25;
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
  // The feasibility path historically rendered each full-origin eye into a
  // 3840x2160 intermediate and retained its central 1920x2160 region. A
  // portrait/square eye-sized intermediate has no unused side regions, so
  // preserve its complete width. This lets the game render only pixels that
  // are transported to OpenXR while leaving the known-good 4K path unchanged.
  const bool source_is_eye_sized =
      source_description.Width <= source_description.Height;
  const auto captured_width = static_cast<UINT64>(
      source_is_eye_sized ? source_description.Width
                          : source_description.Width / 2);

  capture_stage.store(3, std::memory_order_relaxed);
  ComPtr<ID3D12Resource> eye_surface;
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
    if (eye == 0 && ready_value != 0 &&
        consumed_fence->GetCompletedValue() < ready_value) {
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
      (void)shared_head_pose_reader().publish_rendered_pair(
          {ready_after,
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

}  // namespace

extern "C" __declspec(dllexport) int dtvr_install() { return install_hooks(); }
extern "C" __declspec(dllexport) int
dtvr_install_for_device(ID3D12Device* device) {
  return device ? install_hooks(device) : 20;
}
extern "C" __declspec(dllexport) int dtvr_set_projection_active(int enabled) {
  static const HANDLE event = CreateEventW(
      nullptr, TRUE, FALSE, L"Local\\DarktideVR-projection-active-v1");
  if (!event) {
    return 1;
  }
  return (enabled ? SetEvent(event) : ResetEvent(event)) ? 0 : 2;
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
extern "C" __declspec(dllexport) unsigned long long
dtvr_billboard_shader_substitution_count() {
  return billboard_shader_substitution_count.load(std::memory_order_relaxed);
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
extern "C" __declspec(dllexport) int dtvr_set_billboard_view_basis(
    float right_x, float right_y, float right_z, float up_x,
    float up_y, float up_z, int enabled) {
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
    billboard_cbv_log_count.store(0, std::memory_order_relaxed);
    for (auto& count : billboard_shadow_stage_counts) {
      count.store(0, std::memory_order_relaxed);
    }
    for (auto& count : billboard_exact_command_list_type_counts) {
      count.store(0, std::memory_order_relaxed);
    }
    {
      std::scoped_lock lock(buffer_resource_mutex);
      billboard_tested_cbvs.clear();
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
  billboard_basis_write_enabled.store(enabled == 1,
                                      std::memory_order_release);
  billboard_horizon_lock_enabled.store(enabled != 0,
                                       std::memory_order_release);
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
  if (width < 640 || height < 640 || width > 7680 || height > 7680) {
    return 1;
  }
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
  write_boundary_census_log("CONFIG\trequested=%llux%u\r\n", width, height);
  return 0;
}
extern "C" __declspec(dllexport) int dtvr_enable_boundary_census() {
  boundary_census_requested.store(true, std::memory_order_relaxed);
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
  virtual_size_message_enabled.store(enabled != 0,
                                     std::memory_order_release);
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
extern "C" __declspec(dllexport) int dtvr_read_head_pose(
    float* values, unsigned long long* sequence) {
  if (!values || !sequence) {
    return 1;
  }
  darktidevr::core::SharedHeadPoseSample sample{};
  if (!shared_head_pose_reader().read(sample)) {
    return 2;
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
  *sequence = sample.sequence;
  return 0;
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
    if (enhanced_barrier_log != INVALID_HANDLE_VALUE) {
      CloseHandle(enhanced_barrier_log);
      enhanced_barrier_log = INVALID_HANDLE_VALUE;
    }
    if (boundary_census_log != INVALID_HANDLE_VALUE) {
      CloseHandle(boundary_census_log);
      boundary_census_log = INVALID_HANDLE_VALUE;
    }
    close_shared_handles();
  }
  return TRUE;
}
