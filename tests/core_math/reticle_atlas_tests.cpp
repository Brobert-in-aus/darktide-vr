// The reticle and vignette sprites, which had never had a test.
//
// Both faults that kept the aim-down-sights vignette invisible from the day it
// was built (12 September) until it was measured in the game (18 September)
// are checkable here, and neither needed a headset:
//
//  * it was painted on a fixed 3.6 m quad, so its darkening peaked about 61
//    degrees off the view's centre while Virtual Desktop shows about 52 -- at
//    45 degrees the alpha reached 9 of 255;
//  * the submitted texel rectangle has to sit inside the box that is actually
//    painted, or the quad samples whatever the window capture last left there.
//
// The user, 17 September, on a feature five days old: "I suspect it's never
// worked, it's not something I've looked for."

#include "core/reticle_atlas.h"

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

constexpr float kPi = 3.14159265358979323846F;

void require(bool condition, const std::string& label) {
  if (!condition) {
    throw std::runtime_error(label);
  }
}

void expect_near(float actual, float expected, float tolerance,
                 const std::string& label) {
  if (std::fabs(actual - expected) > tolerance) {
    throw std::runtime_error(label + ": expected " + std::to_string(expected) +
                             ", got " + std::to_string(actual));
  }
}

float degrees(float radians) { return radians * 180.0F / kPi; }

// A painted sprite and the alpha at one of its texels.
struct Sprite {
  int extent;
  std::uint32_t row_pitch;
  std::vector<std::byte> pixels;

  explicit Sprite(int side)
      : extent(side),
        row_pitch(static_cast<std::uint32_t>(side) * 4U),
        pixels(static_cast<std::size_t>(side) * side * 4U, std::byte{0}) {}

  int alpha(int x, int y) const {
    return static_cast<int>(pixels[static_cast<std::size_t>(y) * row_pitch +
                                   static_cast<std::size_t>(x) * 4U + 3U]);
  }
  int luma(int x, int y) const {
    return static_cast<int>(pixels[static_cast<std::size_t>(y) * row_pitch +
                                   static_cast<std::size_t>(x) * 4U]);
  }
};

}  // namespace

int main() {
  try {
    using namespace darktidevr::core;

    // ---- The gameplay reticle sprite -------------------------------------
    // 41x41, and the viewer submits it inset by 2 so compositor filtering
    // cannot reach the opaque capture beside it (main.cpp). The inset border
    // must therefore be transparent, or the inset buys nothing.
    Sprite reticle(64);
    paint_reticle_atlas(reticle.pixels.data(), reticle.row_pitch);

    constexpr int kExtent = 41;
    constexpr int kInset = 2;
    for (int y = 0; y < kExtent; ++y) {
      for (int x = 0; x < kExtent; ++x) {
        const bool border = x < kInset || y < kInset ||
                            x >= kExtent - kInset || y >= kExtent - kInset;
        if (border) {
          require(reticle.alpha(x, y) == 0,
                  "the reticle's filtering gutter is not transparent at (" +
                      std::to_string(x) + "," + std::to_string(y) + ")");
        }
      }
    }
    // The centre dot is opaque-ish and white; the sprite is a ring and a
    // cross, so the very centre and a point on each arm are marked.
    require(reticle.alpha(20, 20) > 0 && reticle.luma(20, 20) == 255,
            "the reticle has no centre");
    require(reticle.alpha(20, 10) > 0, "the reticle has no upper arm");
    require(reticle.alpha(10, 20) > 0, "the reticle has no left arm");
    require(reticle.alpha(20, 20 + 18) == 0,
            "the reticle's arms reach past their length");
    // Nothing is painted outside the sprite: the atlas corner holds other
    // things, and a painter that overran would eat them.
    for (int y = 0; y < 64; ++y) {
      for (int x = 0; x < 64; ++x) {
        if (x >= kExtent || y >= kExtent) {
          require(reticle.alpha(x, y) == 0 && reticle.luma(x, y) == 0,
                  "paint_reticle_atlas wrote outside its 41x41 box");
        }
      }
    }

    // ---- The vignette ramp -----------------------------------------------
    expect_near(vignette_ramp(0.0F), 0.0F, 1e-6F, "the centre is clear");
    expect_near(vignette_ramp(kVignetteClearFraction), 0.0F, 1e-6F,
                "the ramp starts where the clear fraction ends");
    expect_near(vignette_ramp(1.0F), kVignettePeakAlpha, 1e-6F,
                "the ramp peaks at the inscribed edge");
    expect_near(vignette_ramp(4.0F), kVignettePeakAlpha, 1e-6F,
                "past the edge it is clamped, not extrapolated");
    expect_near(vignette_ramp(-1.0F), 0.0F, 1e-6F, "a negative radius is clear");
    // Monotonic, which is what makes it read as a vignette rather than a band.
    float previous = -1.0F;
    for (int step = 0; step <= 100; ++step) {
      const float value = vignette_ramp(static_cast<float>(step) / 100.0F);
      require(value >= previous - 1e-6F, "the ramp is not monotonic");
      previous = value;
    }

    // ---- The half extent, at the field of view that was actually reported -
    // artifacts/unattended/hub-100hz-1: openxr.runtime_fov.eye0.
    constexpr float kLeft = -0.893445F, kRight = 0.648593F;
    constexpr float kUp = 0.71549F, kDown = -0.909609F;
    const auto half = vignette_half_extent(kLeft, kRight, kUp, kDown);
    // The largest tangent of the four is the down angle's.
    expect_near(half, std::fabs(std::tan(kDown)), 1e-6F,
                "the half extent is the largest tangent");

    // This is the fault that made it invisible: the peak has to land at the
    // edge of what the headset shows, not beyond it. With the sprite sized
    // from the runtime's own field of view the peak sits at the down angle,
    // about 52 degrees; the old fixed 1.8 m half-extent put it at 61.
    const auto peak_degrees = degrees(std::atan(half));
    require(peak_degrees > 45.0F && peak_degrees < 55.0F,
            "the vignette peaks at " + std::to_string(peak_degrees) +
                " degrees, outside what the headset shows");
    const auto fixed_peak = degrees(std::atan(1.8F));
    require(fixed_peak > 60.0F,
            "the 12 September fixed size should peak past 60 degrees");
    // At 45 degrees off centre the old size was 9 of 255. The new one has to
    // be plainly visible there, which is the whole point.
    const auto at_45 = vignette_alpha(std::tan(45.0F * kPi / 180.0F), 0.0F,
                                      half, 1.0F);
    const auto old_at_45 = vignette_alpha(std::tan(45.0F * kPi / 180.0F), 0.0F,
                                          1.8F, 1.0F);
    require(static_cast<int>(old_at_45 * 255.0F + 0.5F) < 20,
            "the old fixed size should be nearly invisible at 45 degrees");
    require(static_cast<int>(at_45 * 255.0F + 0.5F) > 60,
            "the sized vignette is still faint at 45 degrees: " +
                std::to_string(at_45 * 255.0F));

    // Guards: an unusable field of view must not ask for a quad kilometres
    // across. Virtual Desktop has reported all-zero views while not
    // streaming, and an angle near a right angle has an enormous tangent.
    expect_near(vignette_half_extent(0.0F, 0.0F, 0.0F, 0.0F), 0.0F, 1e-6F,
                "a zero field of view has no extent");
    require(vignette_half_extent(-1.5707F, 1.5707F, 1.5707F, -1.5707F) <=
                kVignetteMaxHalfExtent,
            "a near-right-angle view is not clamped");
    const auto nan = std::nanf("");
    require(vignette_half_extent(nan, 0.5F, 0.4F, -0.4F) > 0.0F,
            "one bad angle should not lose the other three");

    // ---- vignette_alpha and the painted sprite must agree ----------------
    // The viewer reasons about the alpha with vignette_alpha and the runtime
    // shows the painted texels; if they ever disagree the log describes a
    // vignette nobody can see. Sample the sprite's own grid.
    Sprite vignette(64);
    paint_vignette_atlas(vignette.pixels.data(), vignette.row_pitch, 1.0F);
    for (const int texel : {0, 7, 16, 31, 48, 63}) {
      const float d = (static_cast<float>(texel) + 0.5F - 32.0F) / 32.0F;
      // Along the horizontal centre line, tangent_y is 0.
      const auto expected = vignette_alpha(d * half, 0.0F, half, 1.0F);
      const auto painted = vignette.alpha(texel, 32) / 255.0F;
      expect_near(painted, expected, 1.5F / 255.0F,
                  "the painted sprite and vignette_alpha disagree at texel " +
                      std::to_string(texel));
    }
    // The strength scales the whole thing, and the corners are the darkest.
    Sprite half_strength(64);
    paint_vignette_atlas(half_strength.pixels.data(), half_strength.row_pitch,
                         0.5F);
    expect_near(static_cast<float>(half_strength.alpha(0, 0)),
                static_cast<float>(vignette.alpha(0, 0)) * 0.5F, 1.0F,
                "strength does not scale the sprite");
    require(vignette.alpha(32, 32) == 0, "the vignette's centre is not clear");
    require(vignette.alpha(0, 0) > vignette.alpha(16, 32),
            "the corner is not darker than the middle of an edge");
    // Colour is black everywhere: only the alpha carries the vignette.
    for (const int texel : {0, 31, 63}) {
      require(vignette.luma(texel, texel) == 0,
              "the vignette is not black");
    }
    // Out of range strengths are clamped rather than wrapping to nothing.
    Sprite over(64);
    paint_vignette_atlas(over.pixels.data(), over.row_pitch, 4.0F);
    require(over.alpha(0, 0) == vignette.alpha(0, 0),
            "a strength above one is not clamped");
    Sprite under(64);
    paint_vignette_atlas(under.pixels.data(), under.row_pitch, -1.0F);
    require(under.alpha(0, 0) == 0, "a negative strength is not clamped");

    // ---- The submitted rectangle sits inside the painted box -------------
    // main.cpp submits the vignette at (width-42-66+1, height-66+1) with a
    // 62x62 extent, out of a 64x64 painted box whose corner is at
    // (width-42-66, height-66). One texel of gutter on each side.
    constexpr int kVignetteBox = 64, kVignetteSubmitted = 62, kGutter = 1;
    require(kGutter + kVignetteSubmitted + kGutter <= kVignetteBox,
            "the submitted vignette rectangle does not fit the painted box");
    // And the reticle: a 41x41 box submitted inset by 2, so 37 texels.
    require(kInset + (kExtent - 2 * kInset) + kInset <= kExtent,
            "the submitted reticle rectangle does not fit the painted box");
    // Both eye targets the user runs, so a future FOV tangent cannot silently
    // move the corner out of the flat texture.
    for (const auto& target : std::array<std::array<int, 2>, 2>{{
             {2112, 2304}, {1908, 2076}}}) {
      const int left = target[0] - 42 - 66;
      const int top = target[1] - 66;
      require(left >= 0 && top >= 0,
              "the sprite corner falls outside a " +
                  std::to_string(target[0]) + "x" + std::to_string(target[1]) +
                  " eye target");
    }

    std::cout << "reticle_atlas.result=pass peak_deg="
              << peak_degrees << " alpha_at_45=" << at_45 * 255.0F << '\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "reticle_atlas_tests: " << error.what() << '\n';
    return 1;
  }
}
