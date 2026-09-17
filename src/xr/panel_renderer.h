#pragma once

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

namespace darktidevr::harness {

// One spatial quad, described as an OpenXR quad layer describes it: centred on
// the pose, in the pose's XY plane, facing +Z; the texel rectangle's top-left
// is the quad's top-left.
struct PanelQuad {
  enum class Source : std::uint32_t { board = 0, swatch = 1 };
  XrPosef pose{};
  XrExtent2Df size{};
  XrRect2Di texels{};
  Source source{Source::board};
};

// Clip-space position of the point (u, v) of a quad (0..1 from its top-left),
// with the exact transform convention the renderer uses. For tests and
// one-shot diagnostics.
std::array<float, 4> panel_point_clip(const XrPosef& eye_pose,
                                      const XrFovf& fov,
                                      const XrPosef& quad_pose,
                                      XrExtent2Df size, float u, float v);

// Whether a quad's centre is inside the frustum the renderer draws with:
// in front of the near plane and not past the far one. A caller that stands
// another path down when it draws needs to know the draw will be SEEN, and
// `record` only reports that one was issued.
bool panel_quad_centre_visible(const XrPosef& eye_pose, const XrFovf& fov,
                               const XrPosef& quad_pose, XrExtent2Df size);

// Draws the flat board (loading screens, menus) and the menu pointer into the
// eye images, so they reach the runtime inside the projection layer instead
// of as quad layers. Worn, 16 and 17 September 2026: with Virtual Desktop's
// FOV tangent below 100 per cent its compositor drew our world-locked quad
// layers with a projection that did not match the display (boards turned
// against the head and compressed), while the projection layer was right.
// Rendering the quads ourselves with the pose and field of view we submit
// makes them exactly as right as the world.
class PanelRenderer {
 public:
  static constexpr std::size_t maximum_quads_per_eye = 4;

  // The descriptions are those of the textures the board and swatch pixels
  // are copied from today (the flat and pointer swapchain images), so every
  // existing copy and upload footprint applies unchanged; view_format is the
  // typed format for the views and the render target.
  PanelRenderer(ID3D12Device* device, DXGI_FORMAT view_format,
                D3D12_RESOURCE_DESC board_description,
                D3D12_RESOURCE_DESC swatch_description);
  ~PanelRenderer();

  PanelRenderer(const PanelRenderer&) = delete;
  PanelRenderer& operator=(const PanelRenderer&) = delete;

  // Kept in COPY_DEST between frames: the frame's first command list copies
  // the board pixels in, begin() makes it readable, end() returns it.
  ID3D12Resource* board_texture() const { return board_.Get(); }

  // The pointer swatch is static: copied once from the staged upload buffer.
  bool swatch_ready() const { return swatch_ready_; }
  void upload_swatch(ID3D12GraphicsCommandList* command_list,
                     ID3D12Resource* upload,
                     const D3D12_PLACED_SUBRESOURCE_FOOTPRINT& footprint);

  void begin(ID3D12GraphicsCommandList* command_list);
  // Draws the quads in order into image_rect of the render target, cleared
  // first to transparent black when asked (the board's own layer is blended
  // over the world by its premultiplied alpha). Returns the quads drawn.
  std::uint32_t record(ID3D12GraphicsCommandList* command_list,
                       D3D12_CPU_DESCRIPTOR_HANDLE render_target,
                       const XrRect2Di& image_rect, std::size_t eye,
                       const XrPosef& eye_pose, const XrFovf& fov,
                       const PanelQuad* quads, std::size_t quad_count,
                       bool clear_transparent);
  void end(ID3D12GraphicsCommandList* command_list);

 private:
  struct Constants {
    float view_projection[16];
    float model[16];
    float uv_rect[4];
    float size[2];
    float half_texel[2];
  };

  Microsoft::WRL::ComPtr<ID3D12RootSignature> root_signature_;
  Microsoft::WRL::ComPtr<ID3D12PipelineState> pipeline_;
  Microsoft::WRL::ComPtr<ID3D12Resource> board_;
  Microsoft::WRL::ComPtr<ID3D12Resource> swatch_;
  Microsoft::WRL::ComPtr<ID3D12Resource> constant_buffer_;
  std::byte* constants_mapped_{};
  Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> srv_heap_;
  UINT srv_increment_{};
  std::array<std::array<float, 2>, 2> texture_extent_{};
  bool swatch_ready_{};
};

}  // namespace darktidevr::harness
