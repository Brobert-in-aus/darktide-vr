// Pre-optimisation operations, compiled separately with the same Release flags.
#define normalized legacy_normalized
#define conjugate legacy_conjugate
#define multiply legacy_multiply
#define rotate legacy_rotate
#define compose legacy_compose
#define inverse legacy_inverse
#include "core/xr_math.h"
#include <cmath>
#include <stdexcept>
namespace darktidevr::math {
namespace {
Vec3 add(Vec3 left, Vec3 right) {
  return {left.x + right.x, left.y + right.y, left.z + right.z};
}
Vec3 scale(Vec3 value, float factor) {
  return {value.x * factor, value.y * factor, value.z * factor};
}
Quaternion hamilton(Quaternion left, Quaternion right) {
  return {
      left.w * right.x + left.x * right.w + left.y * right.z -
          left.z * right.y,
      left.w * right.y - left.x * right.z + left.y * right.w +
          left.z * right.x,
      left.w * right.z + left.x * right.y - left.y * right.x +
          left.z * right.w,
      left.w * right.w - left.x * right.x - left.y * right.y -
          left.z * right.z};
}
}
Quaternion normalized(Quaternion value) {
  const auto magnitude = std::sqrt(value.x * value.x + value.y * value.y +
                                   value.z * value.z + value.w * value.w);
  if (!(magnitude > 0.0F) || !std::isfinite(magnitude)) {
    throw std::invalid_argument("Quaternion must have finite nonzero length");
  }
  const auto inverse_magnitude = 1.0F / magnitude;
  return {value.x * inverse_magnitude, value.y * inverse_magnitude,
          value.z * inverse_magnitude, value.w * inverse_magnitude};
}
Quaternion conjugate(Quaternion value) {
  return {-value.x, -value.y, -value.z, value.w};
}
Quaternion multiply(Quaternion parent, Quaternion child) {
  parent = normalized(parent);
  child = normalized(child);
  return normalized(hamilton(parent, child));
}
Vec3 rotate(Quaternion rotation, Vec3 value) {
  rotation = normalized(rotation);
  const Quaternion vector{value.x, value.y, value.z, 0.0F};
  const auto rotated = hamilton(hamilton(rotation, vector), conjugate(rotation));
  return {rotated.x, rotated.y, rotated.z};
}
Pose compose(Pose parent, Pose child) {
  parent.orientation = normalized(parent.orientation);
  child.orientation = normalized(child.orientation);
  return {multiply(parent.orientation, child.orientation),
          add(parent.position, rotate(parent.orientation, child.position))};
}
Pose inverse(Pose pose) {
  const auto inverse_rotation = conjugate(normalized(pose.orientation));
  return {inverse_rotation,
          rotate(inverse_rotation, scale(pose.position, -1.0F))};
}
}
