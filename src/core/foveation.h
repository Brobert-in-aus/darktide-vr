#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

// The shading rate image for foveated rendering: fine in the centre of vision,
// coarse at the edges. This is the whole of the interesting decision, and none
// of it needs a headset or a game to check.
//
// D3D12 image-based variable rate shading (tier 2, which this adapter reports
// with a 16-pixel tile) takes an R8_UINT texture of one texel per tile, whose
// value is a D3D12_SHADING_RATE. The values are a packed pair of log2 coarse
// factors -- (x << 2) | y -- so 1x1 is 0, 2x2 is 5, 4x4 is 10. They are spelled
// out here rather than included from d3d12.h so this stays a pure header that
// the tests can reach without Windows.
namespace darktidevr::core {

enum ShadingRate : std::uint8_t {
  shading_rate_1x1 = 0x0,
  shading_rate_1x2 = 0x1,
  shading_rate_2x1 = 0x4,
  shading_rate_2x2 = 0x5,
  shading_rate_2x4 = 0x6,
  shading_rate_4x2 = 0x9,
  shading_rate_4x4 = 0xA,
};

// Where the sharp region sits and how quickly it falls away.
//
// `centre_ndc_x/y` is the foveal centre in normalised device coordinates,
// -1..1, with +y up. It is NOT assumed to be the middle of the image: the eyes
// are submitted with a recentred symmetric projection and each eye's optical
// centre sits at an equal and opposite horizontal offset, so a pattern centred
// on the render target would put its sharp region measurably off where the eye
// looks, in opposite directions per eye (reticle readback, 18 September).
//
// The radii are in NDC too, and horizontal and vertical are separate because
// the field is wider than it is tall: a circular foveal region either wastes
// shading above and below or goes coarse too early at the sides.
struct FoveationPattern {
  float centre_ndc_x{0.0F};
  float centre_ndc_y{0.0F};
  // Inside this ellipse, full rate. Normalised radius 1.0 would be the edge.
  float inner_radius_x{0.35F};
  float inner_radius_y{0.45F};
  // Between inner and middle, the middle rate; beyond, the outer rate.
  float middle_radius_x{0.62F};
  float middle_radius_y{0.72F};
  ShadingRate middle_rate{shading_rate_2x2};
  ShadingRate outer_rate{shading_rate_4x4};
};

// How many tiles a render extent needs. The image covers the whole surface, so
// a partial tile at the right or bottom edge still needs a texel.
constexpr std::uint32_t foveation_tile_count(std::uint32_t extent,
                                             std::uint32_t tile_size) {
  return tile_size == 0U ? 0U : (extent + tile_size - 1U) / tile_size;
}

// Fill `tiles` (row-major, `row_pitch` bytes per row, at least
// foveation_tile_count(width, tile) entries per row) with the pattern.
//
// A tile is judged by its CENTRE, and a tile is a coarse thing: at a 16-pixel
// tile and a 1920-wide eye there are 120 across, so a zone boundary can only
// land on a tile edge. That is why the rates step rather than blend, and why
// the middle ring exists at all -- going straight from 1x1 to 4x4 puts a
// visible seam in the periphery during a head turn.
inline void paint_foveation_image(std::uint8_t* tiles, std::uint32_t row_pitch,
                                  std::uint32_t width, std::uint32_t height,
                                  std::uint32_t tile_size,
                                  const FoveationPattern& pattern) {
  if (tiles == nullptr || tile_size == 0U || width == 0U || height == 0U) {
    return;
  }
  const auto tiles_x = foveation_tile_count(width, tile_size);
  const auto tiles_y = foveation_tile_count(height, tile_size);
  // A zero or negative radius would divide by zero and paint everything
  // coarse, which in a headset reads as the whole world going blocky. Treat it
  // as "no such zone" instead: an inner radius of zero means the sharp region
  // is a point and the middle ring starts immediately.
  const auto guard = [](float value) {
    return value > 1.0e-4F ? value : 1.0e-4F;
  };
  const auto inner_x = guard(pattern.inner_radius_x);
  const auto inner_y = guard(pattern.inner_radius_y);
  const auto middle_x = guard(std::max(pattern.middle_radius_x,
                                       pattern.inner_radius_x));
  const auto middle_y = guard(std::max(pattern.middle_radius_y,
                                       pattern.inner_radius_y));
  for (std::uint32_t ty = 0; ty < tiles_y; ++ty) {
    auto* row = tiles + static_cast<std::size_t>(ty) * row_pitch;
    // The tile's centre in pixels, then in NDC with +y up.
    const auto pixel_y = (static_cast<float>(ty) + 0.5F) *
                         static_cast<float>(tile_size);
    const auto ndc_y =
        1.0F - 2.0F * pixel_y / static_cast<float>(height);
    for (std::uint32_t tx = 0; tx < tiles_x; ++tx) {
      const auto pixel_x = (static_cast<float>(tx) + 0.5F) *
                           static_cast<float>(tile_size);
      const auto ndc_x =
          2.0F * pixel_x / static_cast<float>(width) - 1.0F;
      const auto dx = ndc_x - pattern.centre_ndc_x;
      const auto dy = ndc_y - pattern.centre_ndc_y;
      const auto inner = (dx / inner_x) * (dx / inner_x) +
                         (dy / inner_y) * (dy / inner_y);
      if (inner <= 1.0F) {
        row[tx] = shading_rate_1x1;
        continue;
      }
      const auto middle = (dx / middle_x) * (dx / middle_x) +
                          (dy / middle_y) * (dy / middle_y);
      row[tx] = middle <= 1.0F ? static_cast<std::uint8_t>(pattern.middle_rate)
                               : static_cast<std::uint8_t>(pattern.outer_rate);
    }
  }
}

// What fraction of the surface is shaded at full rate, and the total shading
// work as a fraction of an unfoveated frame. The second number is the only
// honest way to talk about the saving before it is measured: it is what the
// PATTERN costs, not what the frame costs, because a frame that is not
// shading-bound will not move by it.
struct FoveationCost {
  float full_rate_fraction{};
  float shading_fraction{};
};

inline FoveationCost foveation_cost(const std::uint8_t* tiles,
                                    std::uint32_t row_pitch,
                                    std::uint32_t tiles_x,
                                    std::uint32_t tiles_y) {
  if (tiles == nullptr || tiles_x == 0U || tiles_y == 0U) {
    return {};
  }
  double full{};
  double shaded{};
  for (std::uint32_t ty = 0; ty < tiles_y; ++ty) {
    const auto* row = tiles + static_cast<std::size_t>(ty) * row_pitch;
    for (std::uint32_t tx = 0; tx < tiles_x; ++tx) {
      const auto rate = row[tx];
      // (x << 2) | y, each a log2 factor, so the cost is 1 / (2^x * 2^y).
      const auto coarse_x = 1U << ((rate >> 2) & 0x3U);
      const auto coarse_y = 1U << (rate & 0x3U);
      shaded += 1.0 / static_cast<double>(coarse_x * coarse_y);
      if (rate == shading_rate_1x1) {
        full += 1.0;
      }
    }
  }
  const auto total = static_cast<double>(tiles_x) * static_cast<double>(tiles_y);
  return {static_cast<float>(full / total), static_cast<float>(shaded / total)};
}

}  // namespace darktidevr::core
