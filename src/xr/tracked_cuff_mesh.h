#pragma once

#include "core/xr_math.h"

#include <cstdint>
#include <vector>

namespace darktidevr::harness {

struct TrackedCuffDimensions {
  float front_y_metres{0.015F};
  float back_y_metres{-0.050F};
  float front_radius_x_metres{0.057F};
  float front_radius_z_metres{0.046F};
  float back_radius_x_metres{0.050F};
  float back_radius_z_metres{0.041F};
  std::uint32_t radial_segments{24};
};

struct TrackedCuffVertex {
  math::Vec3 position{};
  math::Vec3 normal{};
};

// Builds a sealed, wrist-local elliptical cuff aligned to Touch grip +Y.
// The front sits beneath the glove opening; the capped rear prevents the
// camera from seeing through the otherwise open one-sided cloth mesh.
std::vector<TrackedCuffVertex> make_tracked_cuff_mesh(
    const TrackedCuffDimensions& dimensions = {});

}  // namespace darktidevr::harness
