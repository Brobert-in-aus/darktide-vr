#pragma once

#include "core/xr_math.h"

namespace darktidevr::core {

struct HeadTranslationLimits {
  float horizontal_metres{0.25F};
  float vertical_metres{0.18F};
};

// Returns the current HMD pose relative to the recenter pose. Translation is
// expressed in recenter-local OpenXR metres and clamped to the configured
// horizontal radius and vertical range. Orientation remains unconstrained.
math::Pose recentered_head_delta(math::Pose recenter_pose,
                                 math::Pose current_pose,
                                 HeadTranslationLimits limits);

}  // namespace darktidevr::core
