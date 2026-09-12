#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdlib>

namespace darktidevr::core {
// Paint only the 41x41 sprite, including transparent filtering gutters.
inline void paint_reticle_atlas(std::byte* pixels, std::uint32_t row_pitch) {
  for (int y = 0; y < 41; ++y) {
    for (int x = 0; x < 41; ++x) {
      const int dx = x - 20, dy = y - 20;
      const int ax = std::abs(dx), ay = std::abs(dy);
      const bool outline = dx*dx + dy*dy <= 16 ||
          (ax <= 2 && ay >= 6 && ay <= 16) ||
          (ay <= 2 && ax >= 6 && ax <= 16);
      const bool fill = dx*dx + dy*dy <= 4 ||
          (ax <= 1 && ay >= 8 && ay <= 14) ||
          (ay <= 1 && ax >= 8 && ax <= 14);
      auto* p = pixels + y * row_pitch + x * 4;
      p[0] = p[1] = p[2] = fill ? std::byte{255} : std::byte{0};
      p[3] = outline ? std::byte{171} : std::byte{0};
    }
  }
}

// Paint the 48x48 menu pointer target: a black-edged cyan ring with a white
// centre dot and cross, transparent elsewhere (4 texel gutters for filtering).
// The viewer shows it as a quad at the laser's hit on every menu panel.
constexpr int kPointerTargetExtent = 48;
inline void paint_pointer_target(std::byte* pixels, std::uint32_t row_pitch) {
  for (int y = 0; y < kPointerTargetExtent; ++y) {
    for (int x = 0; x < kPointerTargetExtent; ++x) {
      const float dx = static_cast<float>(x) + 0.5F - 24.0F;
      const float dy = static_cast<float>(y) + 0.5F - 24.0F;
      const float r2 = dx * dx + dy * dy;
      const float ax = dx < 0.0F ? -dx : dx;
      const float ay = dy < 0.0F ? -dy : dy;
      auto* p = pixels + y * row_pitch + x * 4;
      std::byte blue{0}, green{0}, red{0}, alpha{0};
      if (r2 < 36.0F || (ax <= 2.5F && ay <= 12.5F) ||
          (ay <= 2.5F && ax <= 12.5F)) {
        blue = green = red = std::byte{255};
        alpha = std::byte{255};
      } else if (r2 >= 196.0F && r2 < 324.0F) {
        blue = std::byte{255};
        green = std::byte{220};
        alpha = std::byte{255};
      } else if (r2 >= 324.0F && r2 < 400.0F) {
        alpha = std::byte{255};
      }
      p[0] = blue;
      p[1] = green;
      p[2] = red;
      p[3] = alpha;
    }
  }
}

// Paint the 64x64 aim-down-sights vignette sprite: black, transparent at the
// centre, darkening towards the edge. strength (0..1) scales the whole alpha
// so the viewer can ease it in and out by repainting.
inline void paint_vignette_atlas(std::byte* pixels, std::uint32_t row_pitch,
                                 float strength) {
  if (strength < 0.0F) strength = 0.0F;
  if (strength > 1.0F) strength = 1.0F;
  for (int y = 0; y < 64; ++y) {
    for (int x = 0; x < 64; ++x) {
      const float dx = (static_cast<float>(x) + 0.5F - 32.0F) / 32.0F;
      const float dy = (static_cast<float>(y) + 0.5F - 32.0F) / 32.0F;
      float r = dx * dx + dy * dy;  // squared radius, 1 at the inscribed edge
      if (r > 1.0F) r = 1.0F;
      // Smooth ramp from a clear centre (r < 0.2) to the edge.
      float t = (r - 0.2F) / 0.8F;
      if (t < 0.0F) t = 0.0F;
      t = t * t * (3.0F - 2.0F * t);
      const float alpha = 0.7F * t * strength;
      auto* p = pixels + y * row_pitch + x * 4;
      p[0] = p[1] = p[2] = std::byte{0};
      p[3] = static_cast<std::byte>(static_cast<int>(alpha * 255.0F + 0.5F));
    }
  }
}
}
