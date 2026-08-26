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

// Reconstructs an absolute OpenXR eye pose from the same recentered head
// delta consumed by the game camera. Keeping translation in this composition
// is essential for 6DoF: stripping it would make the compositor's virtual
// image plane remain stationary while the rendered cameras lean with the HMD.
math::Pose anchored_recentered_eye_pose(math::Pose recenter_pose,
                                        math::Pose head_delta,
                                        math::Pose current_head_pose,
                                        math::Pose current_eye_pose);

// Returns a controller pose in Darktide body-local coordinates. The OpenXR
// controller is first made relative to the same HMD recenter anchor used by
// head tracking, then converted from OpenXR axes to Darktide's Z-up basis.
// Character/body rotation is intentionally composed later by the game adapter.
math::Pose recentered_controller_pose(math::Pose recenter_head_pose,
                                      math::Pose current_controller_pose);

// Converts a Darktide-basis pose relative to the immutable HMD recenter anchor
// back into absolute OpenXR LOCAL space. Spatial shop/menu anchors use this to
// share the same origin as controller and head tracking.
math::Pose anchored_body_panel_pose(math::Pose recenter_head_pose,
                                    math::Pose body_panel_pose);

}  // namespace darktidevr::core
