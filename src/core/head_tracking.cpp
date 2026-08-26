#include "core/head_tracking.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace darktidevr::core {

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

}  // namespace darktidevr::core
