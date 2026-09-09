#pragma once
#include <d3d12.h>
#include <array>
#include <cstdint>
#include <type_traits>
namespace darktidevr::producer {
inline constexpr std::size_t kCommandRootSlotCount = 32;
// A recording's fixed state can be copied without cloning diagnostic pass maps.
struct CommandRecordingSnapshot {
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
  std::array<std::uint64_t, kCommandRootSlotCount> graphics_tables{};
  std::array<std::uint64_t, kCommandRootSlotCount> graphics_constants{};
  std::array<std::uint64_t, kCommandRootSlotCount> graphics_cbvs{};
  std::array<std::uint64_t, kCommandRootSlotCount> graphics_srvs{};
  std::array<std::uint64_t, kCommandRootSlotCount> graphics_uavs{};
  ID3D12DescriptorHeap* graphics_resource_heap{};
  ID3D12DescriptorHeap* graphics_sampler_heap{};
  std::uintptr_t compute_root_signature{};
  std::array<std::uint64_t, kCommandRootSlotCount> compute_tables{};
  std::array<std::uint64_t, kCommandRootSlotCount> compute_constants{};
  std::array<std::uint64_t, kCommandRootSlotCount> compute_cbvs{};
  std::array<std::uint64_t, kCommandRootSlotCount> compute_srvs{};
  std::array<std::uint64_t, kCommandRootSlotCount> compute_uavs{};
};
static_assert(std::is_trivially_copyable_v<CommandRecordingSnapshot>);
}
