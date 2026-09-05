#pragma once

#include <cstdint>

namespace darktidevr::core {

struct StreamlineRenderExtent {
  std::uint32_t eye_width{};
  std::uint32_t height{};
  std::uint32_t present_width{};

  bool accepts_eye(std::uint64_t width, std::uint32_t eye_height) const noexcept {
    return eye_width != 0 && width == eye_width && eye_height == height;
  }
};

// Packing is a presentation contract. Never report its width to the engine's
// window, camera, UI, or input coordinate APIs.
inline StreamlineRenderExtent streamline_render_extent(
    std::uint64_t width, std::uint32_t height, bool packed) noexcept {
  if (width < 640 || height < 640 || width > (packed ? 3840U : 7680U) ||
      height > 7680) return {};
  const auto eye = static_cast<std::uint32_t>(width);
  return {eye, height, packed ? eye * 2 : eye};
}

} // namespace darktidevr::core
