#include "core/head_tracking.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace darktidevr::core {

math::Pose horizon_locked_recenter_pose(math::Pose current_pose) {
  const auto forward =
      math::rotate(current_pose.orientation, {0.0F, 0.0F, -1.0F});
  const auto forward_horizontal =
      std::sqrt(forward.x * forward.x + forward.z * forward.z);
  float yaw{};
  if (forward_horizontal > 1.0e-4F) {
    yaw = std::atan2(-forward.x, -forward.z);
  } else {
    // Looking almost vertically makes projected forward undefined. The HMD's
    // right axis still carries the same yaw except at a physically impossible
    // degenerate orientation, so use it as the deterministic fallback.
    const auto right =
        math::rotate(current_pose.orientation, {1.0F, 0.0F, 0.0F});
    const auto right_horizontal =
        std::sqrt(right.x * right.x + right.z * right.z);
    yaw = right_horizontal > 1.0e-4F
              ? std::atan2(-right.z, right.x)
              : 0.0F;
  }
  return {math::from_axis_angle({0.0F, 1.0F, 0.0F}, yaw),
          current_pose.position};
}

math::Pose recentered_head_delta(math::Pose recenter_pose,
                                 math::Pose current_pose,
                                 HeadTranslationLimits limits) {
  if (!(limits.horizontal_metres >= 0.0F) ||
      !(limits.vertical_metres >= 0.0F) ||
      !std::isfinite(limits.horizontal_metres) ||
      !std::isfinite(limits.vertical_metres)) {
    throw std::invalid_argument("Head translation limits must be finite and non-negative");
  }

  auto delta = math::compose(math::inverse(recenter_pose), current_pose);
  const auto horizontal_length = std::sqrt(
      delta.position.x * delta.position.x +
      delta.position.z * delta.position.z);
  if (horizontal_length > limits.horizontal_metres &&
      horizontal_length > 0.0F) {
    const auto scale = limits.horizontal_metres / horizontal_length;
    delta.position.x *= scale;
    delta.position.z *= scale;
  }
  delta.position.y = std::clamp(delta.position.y, -limits.vertical_metres,
                                limits.vertical_metres);
  return delta;
}

math::Pose sliding_recentered_head_delta(math::Pose& recenter_pose,
                                         math::Pose current_pose,
                                         HeadTranslationLimits limits) {
  return sliding_head_translation(recenter_pose, current_pose, limits)
      .camera_delta;
}

SlidingHeadTranslation sliding_head_translation(
    math::Pose& recenter_pose, math::Pose current_pose,
    HeadTranslationLimits limits) {
  const auto raw = math::compose(math::inverse(recenter_pose), current_pose);
  const auto bounded =
      recentered_head_delta(recenter_pose, current_pose, limits);
  SlidingHeadTranslation result{bounded,
                                {raw.position.x - bounded.position.x, 0.0F,
                                 raw.position.z - bounded.position.z}};
  constexpr float epsilon = 0.000001F;
  if (std::abs(raw.position.x - bounded.position.x) > epsilon ||
      std::abs(raw.position.y - bounded.position.y) > epsilon ||
      std::abs(raw.position.z - bounded.position.z) > epsilon) {
    // Preserve the complete orientation delta. Only translate the immutable
    // basis enough that `new_recenter * bounded == current_pose`.
    recenter_pose =
        math::compose(current_pose, math::inverse(bounded));
  }
  return result;
}

math::Pose anchored_recentered_eye_pose(math::Pose recenter_pose,
                                        math::Pose head_delta,
                                        math::Pose current_head_pose,
                                        math::Pose current_eye_pose) {
  const auto eye_from_head = math::compose(
      math::inverse(current_head_pose), current_eye_pose);
  return math::compose(
      recenter_pose, math::compose(head_delta, eye_from_head));
}

math::Pose recentered_controller_pose(math::Pose recenter_head_pose,
                                      math::Pose current_controller_pose) {
  return math::openxr_to_darktide(math::compose(
      math::inverse(recenter_head_pose), current_controller_pose));
}

math::Pose anchored_body_panel_pose(math::Pose recenter_head_pose,
                                    math::Pose body_panel_pose) {
  return math::compose(recenter_head_pose,
                       math::darktide_to_openxr(body_panel_pose));
}

float neck_pivot_height_delta(math::Pose baseline_head_delta,
                              math::Pose current_head_delta,
                              math::Vec3 neck_to_hmd_local) {
  const auto baseline_neck = baseline_head_delta.position;
  const auto current_neck = current_head_delta.position;
  const auto baseline_arc =
      math::rotate(baseline_head_delta.orientation, neck_to_hmd_local);
  const auto current_arc =
      math::rotate(current_head_delta.orientation, neck_to_hmd_local);
  return (current_neck.y - current_arc.y) -
         (baseline_neck.y - baseline_arc.y);
}

}  // namespace darktidevr::core
