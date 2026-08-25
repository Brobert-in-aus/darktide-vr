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

}  // namespace darktidevr::core
