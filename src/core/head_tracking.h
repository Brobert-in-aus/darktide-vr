#pragma once

#include "core/xr_math.h"

namespace darktidevr::core {

struct HeadTranslationLimits {
  float horizontal_metres{0.25F};
  float vertical_metres{0.18F};
};

struct SlidingHeadTranslation {
  math::Pose camera_delta{};
  // Incremental recenter-local OpenXR displacement rejected by the horizontal
  // camera lean envelope. A game adapter can accumulate this into an absolute
  // body-follow target while leaving vertical crouch/stand motion camera-only.
  math::Vec3 body_follow_delta{};
};

// Builds a recenter anchor at the current HMD position while preserving only
// its yaw. Pitch and roll remain in the live head delta, so a reset performed
// while leaning or looking up/down cannot redefine the physical horizon.
math::Pose horizon_locked_recenter_pose(math::Pose current_pose);

// Returns the current HMD pose relative to the recenter pose. Translation is
// expressed in recenter-local OpenXR metres and clamped to the configured
// horizontal radius and vertical range. Orientation remains unconstrained.
math::Pose recentered_head_delta(math::Pose recenter_pose,
                                 math::Pose current_pose,
                                 HeadTranslationLimits limits);

// Applies the same bound as recentered_head_delta, but shifts the recenter
// origin by any rejected excess. This keeps a large donning movement from
// leaving subsequent small movements stranded far outside the safety box.
math::Pose sliding_recentered_head_delta(math::Pose& recenter_pose,
                                         math::Pose current_pose,
                                         HeadTranslationLimits limits);

// Splits physical movement into bounded camera lean and incremental horizontal
// body following. The recenter anchor advances by all rejected translation so
// donning and large vertical movements cannot strand tracking outside the
// envelope, but only horizontal excess is exposed as character movement.
SlidingHeadTranslation sliding_head_translation(
    math::Pose& recenter_pose, math::Pose current_pose,
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

// Estimates vertical neck travel from two recenter-relative HMD poses. The
// headset follows an arc when the user pitches around the neck; subtracting
// that rigid head-to-neck arc leaves actual body height change. The local
// neck-to-HMD vector is calibrated separately from the target avatar rig.
float neck_pivot_height_delta(math::Pose baseline_head_delta,
                              math::Pose current_head_delta,
                              math::Vec3 neck_to_hmd_local);

}  // namespace darktidevr::core
