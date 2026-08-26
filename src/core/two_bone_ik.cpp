#include "core/two_bone_ik.h"

#include <algorithm>
#include <cmath>

namespace darktidevr::core {
namespace {

constexpr float kEpsilon = 1.0e-5F;

math::Vec3 add(math::Vec3 left, math::Vec3 right) {
  return {left.x + right.x, left.y + right.y, left.z + right.z};
}

math::Vec3 subtract(math::Vec3 left, math::Vec3 right) {
  return {left.x - right.x, left.y - right.y, left.z - right.z};
}

math::Vec3 scale(math::Vec3 value, float amount) {
  return {value.x * amount, value.y * amount, value.z * amount};
}

float dot(math::Vec3 left, math::Vec3 right) {
  return left.x * right.x + left.y * right.y + left.z * right.z;
}

float length_squared(math::Vec3 value) { return dot(value, value); }

bool finite(math::Vec3 value) {
  return std::isfinite(value.x) && std::isfinite(value.y) &&
         std::isfinite(value.z);
}

math::Vec3 normalized_or(math::Vec3 value, math::Vec3 fallback,
                         bool* used_fallback) {
  auto squared = length_squared(value);
  if (!std::isfinite(squared) || squared < kEpsilon * kEpsilon) {
    value = fallback;
    squared = length_squared(value);
    if (used_fallback) {
      *used_fallback = true;
    }
  }
  if (!std::isfinite(squared) || squared < kEpsilon * kEpsilon) {
    return {};
  }
  return scale(value, 1.0F / std::sqrt(squared));
}

math::Vec3 perpendicular_component(math::Vec3 value, math::Vec3 axis) {
  return subtract(value, scale(axis, dot(value, axis)));
}

math::Vec3 automatic_perpendicular(math::Vec3 axis) {
  const math::Vec3 candidate = std::abs(axis.z) < 0.75F
                                   ? math::Vec3{0.0F, 0.0F, 1.0F}
                                   : math::Vec3{0.0F, 1.0F, 0.0F};
  return perpendicular_component(candidate, axis);
}

}  // namespace

TwoBoneIkResult solve_two_bone_ik(const TwoBoneIkInput& input) {
  TwoBoneIkResult result{};
  if (!finite(input.shoulder) || !finite(input.wrist_target) ||
      !finite(input.pole_target) || !finite(input.fallback_direction) ||
      !finite(input.fallback_bend_direction) ||
      !std::isfinite(input.upper_length) ||
      !std::isfinite(input.lower_length) || input.upper_length <= kEpsilon ||
      input.lower_length <= kEpsilon) {
    return result;
  }

  const auto requested = subtract(input.wrist_target, input.shoulder);
  result.requested_distance = std::sqrt(length_squared(requested));
  result.reach_direction = normalized_or(requested, input.fallback_direction,
                                         &result.used_direction_fallback);
  if (length_squared(result.reach_direction) < 0.5F) {
    return result;
  }

  const float minimum_reach =
      std::abs(input.upper_length - input.lower_length) + kEpsilon;
  const float maximum_reach =
      std::max(minimum_reach,
               input.upper_length + input.lower_length - kEpsilon);
  result.solved_distance =
      std::clamp(result.requested_distance, minimum_reach, maximum_reach);
  result.clamped_near = result.requested_distance < minimum_reach;
  result.clamped_far = result.requested_distance > maximum_reach;

  const auto pole_from_shoulder = subtract(input.pole_target, input.shoulder);
  auto bend = perpendicular_component(pole_from_shoulder,
                                      result.reach_direction);
  if (length_squared(bend) < kEpsilon * kEpsilon) {
    bend = perpendicular_component(input.fallback_bend_direction,
                                   result.reach_direction);
    result.used_bend_fallback = true;
  }
  if (length_squared(bend) < kEpsilon * kEpsilon) {
    bend = automatic_perpendicular(result.reach_direction);
    result.used_bend_fallback = true;
  }
  result.bend_direction = normalized_or(bend, {}, nullptr);
  if (length_squared(result.bend_direction) < 0.5F) {
    return result;
  }

  const float upper_squared = input.upper_length * input.upper_length;
  const float lower_squared = input.lower_length * input.lower_length;
  const float distance_squared =
      result.solved_distance * result.solved_distance;
  const float along =
      (upper_squared + distance_squared - lower_squared) /
      (2.0F * result.solved_distance);
  const float height =
      std::sqrt(std::max(0.0F, upper_squared - along * along));

  result.wrist = add(input.shoulder,
                     scale(result.reach_direction, result.solved_distance));
  result.elbow =
      add(add(input.shoulder, scale(result.reach_direction, along)),
          scale(result.bend_direction, height));
  result.valid = finite(result.elbow) && finite(result.wrist);
  return result;
}

}  // namespace darktidevr::core
