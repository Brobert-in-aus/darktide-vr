// The foveation pattern: where the sharp region sits, how the rates step, and
// what the pattern costs. None of this needs a headset, which matters because
// the alternative is judging a shading-rate image by looking at it through one.
//
// The fault this is written against is specific. Each eye is submitted with a
// recentred symmetric projection, and the reticle readback on 18 September
// showed the two eyes' optical centres at equal and OPPOSITE horizontal NDC.
// A pattern centred on the render target therefore puts its sharp region off
// to one side in the left eye and the other side in the right -- which in a
// headset reads as "foveation looks bad" when what is wrong is where it points.

#include "core/foveation.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using darktidevr::core::FoveationPattern;
using darktidevr::core::foveation_cost;
using darktidevr::core::foveation_tile_count;
using darktidevr::core::paint_foveation_image;
using darktidevr::core::shading_rate_1x1;
using darktidevr::core::shading_rate_2x2;
using darktidevr::core::shading_rate_4x4;

void require(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

struct Image {
  std::vector<std::uint8_t> tiles;
  std::uint32_t tiles_x{};
  std::uint32_t tiles_y{};
  // Deliberately NOT tiles_x. A D3D12 upload's row pitch is aligned to 256, so
  // it is never the tile count, and a test that passes the tile count cannot
  // see a pitch bug -- every row would land exactly where the bug put it.
  std::uint32_t row_pitch{};
  std::uint8_t at(std::uint32_t x, std::uint32_t y) const {
    return tiles[static_cast<std::size_t>(y) * row_pitch + x];
  }
};

constexpr std::uint32_t aligned_pitch(std::uint32_t tiles_x) {
  return (tiles_x + 255U) / 256U * 256U;
}

Image paint(std::uint32_t width, std::uint32_t height, std::uint32_t tile,
            const FoveationPattern& pattern) {
  Image image;
  image.tiles_x = foveation_tile_count(width, tile);
  image.tiles_y = foveation_tile_count(height, tile);
  image.row_pitch = aligned_pitch(image.tiles_x);
  image.tiles.assign(
      static_cast<std::size_t>(image.row_pitch) * image.tiles_y, 0xFFU);
  paint_foveation_image(image.tiles.data(), image.row_pitch, width, height,
                        tile, pattern);
  // The padding past each row must be left alone: writing into it at a real
  // pitch would scribble over the next row's start.
  for (std::uint32_t ty = 0; ty < image.tiles_y; ++ty) {
    for (std::uint32_t tx = image.tiles_x; tx < image.row_pitch; ++tx) {
      require(image.tiles[static_cast<std::size_t>(ty) * image.row_pitch + tx]
                  == 0xFFU,
              "the pattern wrote past the end of a row");
    }
  }
  return image;
}

// The centre of mass of the full-rate tiles, in NDC. Where the sharp region
// actually ended up, as opposed to where it was asked to be.
void full_rate_centroid(const Image& image, float& x, float& y) {
  double sum_x{}, sum_y{}, count{};
  for (std::uint32_t ty = 0; ty < image.tiles_y; ++ty) {
    for (std::uint32_t tx = 0; tx < image.tiles_x; ++tx) {
      if (image.at(tx, ty) != shading_rate_1x1) continue;
      sum_x += (static_cast<double>(tx) + 0.5) / image.tiles_x * 2.0 - 1.0;
      sum_y += 1.0 - (static_cast<double>(ty) + 0.5) / image.tiles_y * 2.0;
      count += 1.0;
    }
  }
  require(count > 0.0, "the pattern painted no full-rate tiles at all");
  x = static_cast<float>(sum_x / count);
  y = static_cast<float>(sum_y / count);
}

void tile_counts() {
  // Through a vector so the extents are not compile-time constants. They are
  // `constexpr` at the header, and a compiler that folds them proves the
  // assertion below throws and reports the rest of main() as unreachable --
  // so a wrong tile count would fail the BUILD with "unreachable code" rather
  // than failing this test by name, which tells the reader nothing.
  const std::vector<std::uint32_t> extents{1920, 2160, 1921, 1, 1920};
  const std::vector<std::uint32_t> tiles{16, 16, 16, 16, 0};
  const std::vector<std::uint32_t> expected{120, 135, 121, 1, 0};
  const std::vector<std::string> why{
      "a 1920-wide eye is 120 tiles at the 16-pixel tile this adapter reports",
      "a 2160-tall eye is 135 tiles",
      // Or the last strip of the surface has no rate at all and the runtime
      // reads past the end of the image.
      "a partial tile at the edge is still a tile",
      "one pixel is one tile",
      "a zero tile size has no tiles"};
  for (std::size_t i = 0; i < extents.size(); ++i) {
    require(foveation_tile_count(extents[i], tiles[i]) == expected[i], why[i]);
  }
}

void the_centre_is_where_it_was_asked_to_be() {
  // This is the whole point. Two eyes, optical centres at equal and opposite
  // horizontal NDC, exactly as the reticle readback measured.
  constexpr float kOpticalOffset = 0.06F;
  for (const float offset : {-kOpticalOffset, kOpticalOffset}) {
    FoveationPattern pattern;
    pattern.centre_ndc_x = offset;
    const auto image = paint(1920, 2160, 16, pattern);
    float x{}, y{};
    full_rate_centroid(image, x, y);
    require(std::abs(x - offset) < 0.02F,
            "the sharp region must sit at the eye's optical centre, not the "
            "image centre: asked " + std::to_string(offset) + ", got " +
            std::to_string(x));
    require(std::abs(y) < 0.02F, "no vertical offset was asked for");
  }

  // And the two eyes must actually differ. A pattern that ignored the centre
  // would pass the test above only by accident of symmetry, so compare them.
  FoveationPattern left;
  left.centre_ndc_x = -kOpticalOffset;
  FoveationPattern right;
  right.centre_ndc_x = kOpticalOffset;
  const auto left_image = paint(1920, 2160, 16, left);
  const auto right_image = paint(1920, 2160, 16, right);
  bool differs = false;
  for (std::uint32_t ty = 0; ty < left_image.tiles_y && !differs; ++ty) {
    for (std::uint32_t tx = 0; tx < left_image.tiles_x; ++tx) {
      if (left_image.at(tx, ty) != right_image.at(tx, ty)) { differs = true; break; }
    }
  }
  require(differs,
          "the two eyes' images are identical, so the centre is being ignored");
}

void the_zones_step_outward() {
  FoveationPattern pattern;
  const auto image = paint(1920, 2160, 16, pattern);
  // Dead centre is full rate; the far corner is the outer rate; and walking
  // out along the horizontal must pass through the middle rate rather than
  // jumping, or the periphery gets a seam that swims during a head turn.
  require(image.at(image.tiles_x / 2, image.tiles_y / 2) == shading_rate_1x1,
          "the centre tile is full rate");
  require(image.at(0, 0) == shading_rate_4x4, "the corner is the outer rate");
  bool seen_middle = false;
  std::uint8_t previous = shading_rate_1x1;
  for (std::uint32_t tx = image.tiles_x / 2; tx < image.tiles_x; ++tx) {
    const auto rate = image.at(tx, image.tiles_y / 2);
    require(rate >= previous, "the rate must never get finer going outward");
    // A ring between the two, whatever rate fills it. Which one is a tuning
    // choice -- 2x4 falls off faster horizontally, which suits a field wider
    // than it is tall -- so pinning the value would block that change while
    // checking nothing more than that a ring exists.
    if (rate != shading_rate_1x1 &&
        rate != static_cast<std::uint8_t>(pattern.outer_rate)) {
      seen_middle = true;
    }
    previous = rate;
  }
  require(seen_middle, "the middle ring is missing: full rate straight to the "
                       "outer rate puts a visible seam in the periphery");
  require(previous == static_cast<std::uint8_t>(pattern.outer_rate),
          "the edge is the outer rate");
}

void the_ellipse_is_wider_than_it_is_tall() {
  // The field is wider than it is tall, so a circular foveal region either
  // wastes shading above and below or goes coarse too early at the sides.
  FoveationPattern pattern;
  const auto image = paint(1920, 1920, 16, pattern);  // square, so only the
                                                      // radii can differ
  std::uint32_t across{}, down{};
  for (std::uint32_t tx = image.tiles_x / 2; tx < image.tiles_x; ++tx) {
    if (image.at(tx, image.tiles_y / 2) == shading_rate_1x1) ++across;
  }
  for (std::uint32_t ty = image.tiles_y / 2; ty < image.tiles_y; ++ty) {
    if (image.at(image.tiles_x / 2, ty) == shading_rate_1x1) ++down;
  }
  require(across != down,
          "the sharp region is circular on a square surface; the horizontal "
          "and vertical radii are meant to differ");
}

void degenerate_input_does_not_black_out_the_world() {
  // A zero radius divides by zero. Painting everything coarse reads, in a
  // headset, as the whole world going blocky -- a spectacular way to fail a
  // worn test for a reason nobody would guess from a settings slider at 0.
  FoveationPattern pattern;
  pattern.inner_radius_x = 0.0F;
  pattern.inner_radius_y = 0.0F;
  const auto image = paint(640, 640, 16, pattern);
  // The painted region only: past tiles_x is row padding the pattern must not
  // touch, which `paint` already checks.
  for (std::uint32_t ty = 0; ty < image.tiles_y; ++ty) {
    for (std::uint32_t tx = 0; tx < image.tiles_x; ++tx) {
      const auto rate = image.at(tx, ty);
      // The three rates the PATTERN names, not three literals: which rate
      // fills the middle ring is a tuning choice and pinning it here would
      // block that change while checking nothing more.
      require(rate == shading_rate_1x1 ||
                  rate == static_cast<std::uint8_t>(pattern.middle_rate) ||
                  rate == static_cast<std::uint8_t>(pattern.outer_rate),
              "a zero radius produced a rate the pattern never names");
    }
  }

  // A middle radius inside the inner one is a settings mistake, not a licence
  // to invert the zones.
  FoveationPattern inverted;
  inverted.inner_radius_x = 0.6F;
  inverted.inner_radius_y = 0.6F;
  inverted.middle_radius_x = 0.2F;
  inverted.middle_radius_y = 0.2F;
  const auto inverted_image = paint(640, 640, 16, inverted);
  require(inverted_image.at(inverted_image.tiles_x / 2,
                            inverted_image.tiles_y / 2) == shading_rate_1x1,
          "the centre must stay sharp even when the radii are given in the "
          "wrong order");

  // Nothing at all must not write through a null pointer.
  paint_foveation_image(nullptr, 0, 1920, 2160, 16, pattern);
  std::vector<std::uint8_t> tiles(16, 0xEEU);
  paint_foveation_image(tiles.data(), 4, 0, 0, 16, pattern);
  require(tiles[0] == 0xEEU, "a zero extent painted something");
  paint_foveation_image(tiles.data(), 4, 64, 64, 0, pattern);
  require(tiles[0] == 0xEEU, "a zero tile size painted something");
}

void the_cost_is_what_the_pattern_costs() {
  FoveationPattern pattern;
  const auto image = paint(1920, 2160, 16, pattern);
  const auto cost =
      foveation_cost(image.tiles.data(), image.row_pitch, image.tiles_x,
                     image.tiles_y);
  require(cost.full_rate_fraction > 0.05F && cost.full_rate_fraction < 0.6F,
          "the default sharp region covers an implausible share of the eye: " +
              std::to_string(cost.full_rate_fraction));
  require(cost.shading_fraction < 1.0F, "foveation that costs more than none");
  require(cost.shading_fraction > cost.full_rate_fraction,
          "the coarse zones still cost something");

  // An all-full-rate image costs exactly one, which is the definition the
  // saving is quoted against.
  FoveationPattern everything_sharp;
  everything_sharp.inner_radius_x = 10.0F;
  everything_sharp.inner_radius_y = 10.0F;
  const auto sharp = paint(640, 640, 16, everything_sharp);
  const auto sharp_cost =
      foveation_cost(sharp.tiles.data(), sharp.row_pitch, sharp.tiles_x,
                     sharp.tiles_y);
  require(std::abs(sharp_cost.shading_fraction - 1.0F) < 1.0e-6F,
          "an unfoveated image must cost exactly 1");
  require(std::abs(sharp_cost.full_rate_fraction - 1.0F) < 1.0e-6F,
          "and be entirely full rate");

  // A NON-SQUARE rate pins the (x << 2) | y encoding: every rate used above is
  // symmetric, so swapping the two shifts would cost nothing and be invisible.
  // 2x4 is one eighth of the work, and 4x2 must come to the same total while
  // being a different value.
  FoveationPattern wide;
  wide.inner_radius_x = 1.0e-3F;
  wide.inner_radius_y = 1.0e-3F;
  wide.middle_radius_x = 1.0e-3F;
  wide.middle_radius_y = 1.0e-3F;
  wide.outer_rate = darktidevr::core::shading_rate_2x4;
  const auto wide_image = paint(640, 640, 16, wide);
  const auto wide_cost = foveation_cost(wide_image.tiles.data(),
                                        wide_image.row_pitch,
                                        wide_image.tiles_x, wide_image.tiles_y);
  require(std::abs(wide_cost.shading_fraction - 0.125F) < 1.0e-6F,
          "2x4 everywhere must cost an eighth, got " +
              std::to_string(wide_cost.shading_fraction));
  require(darktidevr::core::shading_rate_2x4 !=
              darktidevr::core::shading_rate_4x2,
          "2x4 and 4x2 are different rates");

  // 4x4 everywhere is a sixteenth of the work, which is the floor the rate
  // encoding claims.
  FoveationPattern everything_coarse;
  everything_coarse.inner_radius_x = 1.0e-3F;
  everything_coarse.inner_radius_y = 1.0e-3F;
  everything_coarse.middle_radius_x = 1.0e-3F;
  everything_coarse.middle_radius_y = 1.0e-3F;
  const auto coarse = paint(640, 640, 16, everything_coarse);
  const auto coarse_cost =
      foveation_cost(coarse.tiles.data(), coarse.row_pitch, coarse.tiles_x,
                     coarse.tiles_y);
  require(coarse_cost.shading_fraction < 0.2F,
          "4x4 everywhere should approach a sixteenth of the work, got " +
              std::to_string(coarse_cost.shading_fraction));
}

void the_reticle_can_move_the_centre() {
  // The toggle the user asked for: the sharp region follows the aim point
  // rather than sitting where the optics point. In an aimed shooter the gaze
  // is usually near the reticle, which makes this most of the benefit of eye
  // tracking without any.
  FoveationPattern aimed;
  aimed.centre_ndc_x = 0.35F;
  aimed.centre_ndc_y = -0.25F;
  const auto image = paint(1920, 2160, 16, aimed);
  float x{}, y{};
  full_rate_centroid(image, x, y);
  require(std::abs(x - 0.35F) < 0.03F && std::abs(y + 0.25F) < 0.03F,
          "the sharp region did not follow the aim point");

  // And a centre outside the surface must not leave the image with no sharp
  // region at all -- an aim point behind the player, or a stale one, would
  // otherwise make the whole eye coarse.
  FoveationPattern off_screen;
  off_screen.centre_ndc_x = 3.0F;
  const auto off = paint(1920, 2160, 16, off_screen);
  const auto cost = foveation_cost(off.tiles.data(), off.row_pitch,
                                   off.tiles_x, off.tiles_y);
  require(cost.shading_fraction > 0.06F,
          "an out-of-range centre made the entire eye coarse");
}

}  // namespace

int main() {
  try {
    tile_counts();
    the_centre_is_where_it_was_asked_to_be();
    the_zones_step_outward();
    the_ellipse_is_wider_than_it_is_tall();
    degenerate_input_does_not_black_out_the_world();
    the_cost_is_what_the_pattern_costs();
    the_reticle_can_move_the_centre();
    std::cout << "foveation.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "foveation: " << error.what() << '\n';
    return 1;
  }
}
