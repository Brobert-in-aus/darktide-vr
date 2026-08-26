#pragma once

#include "core/xr_math.h"

namespace darktidevr::core {

struct TwoBoneIkInput {
  math::Vec3 shoulder{};
  math::Vec3 wrist_target{};
  math::Vec3 pole_target{};
  math::Vec3 fallback_direction{0.0F, 1.0F, 0.0F};
  math::Vec3 fallback_bend_direction{0.0F, 0.0F, -1.0F};
  float upper_length{};
  float lower_length{};
};

struct TwoBoneIkResult {
  math::Vec3 elbow{};
  math::Vec3 wrist{};
  math::Vec3 reach_direction{};
  math::Vec3 bend_direction{};
  float requested_distance{};
  float solved_distance{};
  bool clamped_near{};
  bool clamped_far{};
  bool used_direction_fallback{};
  bool used_bend_fallback{};
  bool valid{};
};

// Solves a shoulder/elbow/wrist chain in world space. The target is clamped to
// the physically reachable annulus and the pole is projected perpendicular to
// the reach direction. A caller-provided previous bend direction prevents
// elbow flips when the pole approaches the reach axis.
TwoBoneIkResult solve_two_bone_ik(const TwoBoneIkInput& input);

}  // namespace darktidevr::core
