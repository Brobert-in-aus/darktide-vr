#pragma once
#include <algorithm>
#include <cmath>
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

// The aim-down-sights vignette: black, clear at the centre, darkening toward
// the edge of the sprite. The sprite is shown on a head-locked quad a metre
// ahead, so where its darkening lands in the view depends entirely on the
// quad's size; kVignetteClearFraction is the squared radius where the ramp
// starts, and the ramp reaches its peak at the sprite's inscribed edge.
constexpr float kVignetteClearFraction = 0.2F;
constexpr float kVignettePeakAlpha = 0.7F;

// The alpha at a squared radius (0 at the centre, 1 at the inscribed edge),
// before the strength. The paint below and vignette_alpha share it, so the
// sprite and anything that reasons about it cannot drift apart. Pure.
inline float vignette_ramp(float squared_radius) {
  float r = squared_radius < 0.0F ? 0.0F : squared_radius;
  if (r > 1.0F) r = 1.0F;
  float t = (r - kVignetteClearFraction) / (1.0F - kVignetteClearFraction);
  if (t < 0.0F) t = 0.0F;
  t = t * t * (3.0F - 2.0F * t);
  return kVignettePeakAlpha * t;
}

// The quad's half-size at one metre that makes the sprite's inscribed edge
// land on the edge of what the eye can see: the largest tangent of the
// runtime's own field of view. Painted at a fixed 1.8 m (a 3.6 m quad), the
// ramp peaked at 61 degrees off the view's centre while Virtual Desktop
// shows at most about 52, so the darkening was all but invisible: at 45
// degrees it reached 9 of 255 (built 12 September, never seen working; the
// user, 17 September: "I suspect it's never worked"). Angles are OpenXR's
// signed field-of-view angles in radians. Pure.
inline float vignette_half_extent(float angle_left, float angle_right,
                                  float angle_up, float angle_down) {
  const float tangents[4] = {std::tan(angle_left), std::tan(angle_right),
                             std::tan(angle_up), std::tan(angle_down)};
  float half = 0.0F;
  for (const float tangent : tangents) {
    if (!std::isfinite(tangent)) continue;
    half = (std::max)(half, std::fabs(tangent));
  }
  return half;
}

// The alpha the vignette shows at a direction given as tangents from the
// view's centre, for a quad of that half-extent at one metre. Pure.
inline float vignette_alpha(float tangent_x, float tangent_y,
                            float half_extent, float strength) {
  if (!(half_extent > 0.0F)) return 0.0F;
  if (strength < 0.0F) strength = 0.0F;
  if (strength > 1.0F) strength = 1.0F;
  const float dx = tangent_x / half_extent;
  const float dy = tangent_y / half_extent;
  return vignette_ramp(dx * dx + dy * dy) * strength;
}

// Paint the 64x64 sprite. strength (0..1) scales the whole alpha so the
// viewer can ease it in and out by repainting.
inline void paint_vignette_atlas(std::byte* pixels, std::uint32_t row_pitch,
                                 float strength) {
  if (strength < 0.0F) strength = 0.0F;
  if (strength > 1.0F) strength = 1.0F;
  for (int y = 0; y < 64; ++y) {
    for (int x = 0; x < 64; ++x) {
      const float dx = (static_cast<float>(x) + 0.5F - 32.0F) / 32.0F;
      const float dy = (static_cast<float>(y) + 0.5F - 32.0F) / 32.0F;
      const float alpha = vignette_ramp(dx * dx + dy * dy) * strength;
      auto* p = pixels + y * row_pitch + x * 4;
      p[0] = p[1] = p[2] = std::byte{0};
      p[3] = static_cast<std::byte>(static_cast<int>(alpha * 255.0F + 0.5F));
    }
  }
}
}
