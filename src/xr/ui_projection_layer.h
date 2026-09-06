#pragma once

#include <Windows.h>
#include <d3d12.h>
#ifndef XR_USE_GRAPHICS_API_D3D12
#define XR_USE_GRAPHICS_API_D3D12
#endif
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>
#include <array>
#include <vector>

namespace darktidevr::harness {

// A transparent projection has its own source poses. Excluded UI must not
// inherit the interpolated world pose when the two were rendered at different
// times. Resources and dimensions are supplied by the active runtime.
class UiProjectionLayer {
 public:
  UiProjectionLayer(XrSession session, XrSpace space, std::int64_t format,
                    std::uint32_t width, std::uint32_t height);
  ~UiProjectionLayer();
  UiProjectionLayer(const UiProjectionLayer&) = delete;
  UiProjectionLayer& operator=(const UiProjectionLayer&) = delete;

  // Sources are immutable COMMON textures owned by the consumer's pending
  // original pair. Caller submits and completes these copies before release.
  void record(ID3D12GraphicsCommandList* commands,
              const std::array<ID3D12Resource*, 2>& sources,
              const std::array<XrPosef, 2>& source_poses,
              const std::array<XrFovf, 2>& source_fovs);
  void release();
  const XrCompositionLayerProjection* layer() const noexcept { return &layer_; }

 private:
  void destroy() noexcept;
  std::uint32_t width_{}, height_{};
  std::array<XrSwapchain, 2> swapchains_{};
  std::array<std::vector<XrSwapchainImageD3D12KHR>, 2> images_;
  std::array<bool, 2> acquired_{};
  std::array<XrCompositionLayerProjectionView, 2> views_{};
  XrCompositionLayerProjection layer_{XR_TYPE_COMPOSITION_LAYER_PROJECTION};
};
}
