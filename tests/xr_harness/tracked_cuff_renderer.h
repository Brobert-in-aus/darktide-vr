#pragma once

#include "core/shared_controller_state.h"

#include <Windows.h>
#include <d3d12.h>
#include <wrl/client.h>

#ifndef XR_USE_GRAPHICS_API_D3D12
#define XR_USE_GRAPHICS_API_D3D12
#endif
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace darktidevr::harness {

// Projects the tracked cuff's wrist-offset centre with the exact transform
// convention used by the renderer. Intended for one-shot live diagnostics.
std::array<float, 4> tracked_cuff_clip_center(
    const XrPosef& eye_pose, const XrFovf& fov,
    const core::ControllerHandState& hand);

class TrackedCuffRenderer {
 public:
  TrackedCuffRenderer(
      ID3D12Device* device, DXGI_FORMAT color_format,
      const std::vector<std::vector<XrSwapchainImageD3D12KHR>>& images,
      const std::vector<XrViewConfigurationView>& view_configurations);
  ~TrackedCuffRenderer();

  TrackedCuffRenderer(const TrackedCuffRenderer&) = delete;
  TrackedCuffRenderer& operator=(const TrackedCuffRenderer&) = delete;

  std::uint32_t record(
      ID3D12GraphicsCommandList* command_list, std::size_t eye,
      std::uint32_t image_index, const XrPosef& eye_pose, const XrFovf& fov,
      const std::array<core::ControllerHandState, 2>& hands);

 private:
  struct Vertex {
    float position[3];
    float normal[3];
  };

  struct Constants {
    float view_projection[16];
    float model[16];
    float color[4];
  };

  Microsoft::WRL::ComPtr<ID3D12RootSignature> root_signature_;
  Microsoft::WRL::ComPtr<ID3D12PipelineState> pipeline_;
  Microsoft::WRL::ComPtr<ID3D12Resource> vertex_buffer_;
  D3D12_VERTEX_BUFFER_VIEW vertex_view_{};
  std::uint32_t vertex_count_{};
  Microsoft::WRL::ComPtr<ID3D12Resource> constant_buffer_;
  std::byte* constants_mapped_{};
  Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> rtv_heap_;
  std::vector<std::vector<std::uint32_t>> rtv_offsets_;
  std::vector<XrViewConfigurationView> view_configurations_;
  UINT rtv_increment_{};
};

}  // namespace darktidevr::harness
