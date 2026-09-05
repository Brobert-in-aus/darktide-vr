#pragma once

#include <cstdint>

namespace darktidevr::core {

inline bool streamline_isolated_eye_matches(
    int requested_eye, int named_eye, std::uint64_t width, std::uint32_t height,
    std::uint32_t expected_width, std::uint32_t expected_height) noexcept {
  return requested_eye >= 0 && requested_eye < 2 && named_eye == requested_eye &&
      expected_width > 0 && expected_height > 0 &&
      width == expected_width && height == expected_height;
}

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
