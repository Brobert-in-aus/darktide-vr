#pragma once

#include <Windows.h>
#include <d3d12.h>
#include <wrl/client.h>

#ifndef XR_USE_GRAPHICS_API_D3D12
#define XR_USE_GRAPHICS_API_D3D12
#endif
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>

#include <cstdint>
#include <vector>

namespace darktidevr::harness {

class SyntheticScene {
 public:
  SyntheticScene(
      ID3D12Device* device, DXGI_FORMAT color_format,
      const std::vector<std::vector<XrSwapchainImageD3D12KHR>>& images,
      const std::vector<XrViewConfigurationView>& view_configurations);

  void record(ID3D12GraphicsCommandList* command_list, std::size_t eye,
              std::uint32_t image_index, const XrView& view,
              std::uint32_t frame_number);

  std::uint32_t triangle_count() const { return triangle_count_; }

 public:
  struct Vertex {
    float position[3];
    float normal[3];
    float color_material[4];
  };

  struct Constants {
    float view_projection[16];
    float time_eye[4];
    float camera_right[4];
    float camera_up[4];
    float camera_position[4];
  };

 private:

  void create_pipeline(ID3D12Device* device, DXGI_FORMAT color_format);
  void create_mesh(ID3D12Device* device);
  void create_targets(
      ID3D12Device* device, DXGI_FORMAT color_format,
      const std::vector<std::vector<XrSwapchainImageD3D12KHR>>& images,
      const std::vector<XrViewConfigurationView>& view_configurations);

  Microsoft::WRL::ComPtr<ID3D12RootSignature> root_signature_;
  Microsoft::WRL::ComPtr<ID3D12PipelineState> pipeline_;
  Microsoft::WRL::ComPtr<ID3D12PipelineState> spherical_billboard_pipeline_;
  Microsoft::WRL::ComPtr<ID3D12PipelineState> cylindrical_billboard_pipeline_;
  Microsoft::WRL::ComPtr<ID3D12Resource> vertex_buffer_;
  D3D12_VERTEX_BUFFER_VIEW vertex_view_{};
  Microsoft::WRL::ComPtr<ID3D12Resource> constant_buffer_;
  std::byte* constants_mapped_{};
  Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> rtv_heap_;
  Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> dsv_heap_;
  std::vector<std::vector<std::uint32_t>> rtv_offsets_;
  std::vector<Microsoft::WRL::ComPtr<ID3D12Resource>> depth_buffers_;
  std::vector<XrViewConfigurationView> view_configurations_;
  UINT rtv_increment_{};
  UINT dsv_increment_{};
  std::uint32_t vertex_count_{};
  std::uint32_t triangle_count_{};
  std::uint32_t scene_vertex_count_{};
  std::uint32_t spherical_billboard_offset_{};
  std::uint32_t cylindrical_billboard_offset_{};
};

}  // namespace darktidevr::harness
