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

float length(Vec3 value) {
  return std::sqrt(value.x * value.x + value.y * value.y + value.z * value.z);
}

void validate_scale(float engine_units_per_metre) {
  if (!(engine_units_per_metre > 0.0F) ||
      !std::isfinite(engine_units_per_metre)) {
    throw std::invalid_argument("Engine units per metre must be finite and positive");
  }
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

}  // namespace

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

Quaternion from_axis_angle(Vec3 axis, float radians) {
  const auto axis_length = length(axis);
  if (!(axis_length > 0.0F) || !std::isfinite(axis_length) ||
      !std::isfinite(radians)) {
    throw std::invalid_argument("Axis-angle inputs must be finite with a nonzero axis");
  }
  const auto half_angle = radians * 0.5F;
  const auto sine = std::sin(half_angle) / axis_length;
  return normalized(
      {axis.x * sine, axis.y * sine, axis.z * sine, std::cos(half_angle)});
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

Vec3 transform_point(Pose pose, Vec3 point) {
  return add(pose.position, rotate(pose.orientation, point));
}

Matrix4 projection_d3d(Fov fov, float near_z, float far_z) {
  if (!(near_z > 0.0F) || !std::isfinite(near_z) ||
      !std::isfinite(far_z)) {
    throw std::invalid_argument("Projection near/far values must be finite and near positive");
  }
  const auto left = std::tan(fov.angle_left);
  const auto right = std::tan(fov.angle_right);
  const auto up = std::tan(fov.angle_up);
  const auto down = std::tan(fov.angle_down);
  const auto width = right - left;
  const auto height = up - down;
  if (!(width > 0.0F) || !(height > 0.0F)) {
    throw std::invalid_argument("Projection FOV must have positive width and height");
  }

  Matrix4 result{};
  result.m[0] = 2.0F / width;
  result.m[5] = 2.0F / height;
  result.m[8] = (right + left) / width;
  result.m[9] = (up + down) / height;
  if (far_z <= near_z) {
    result.m[10] = -1.0F;
    result.m[14] = -near_z;
  } else {
    result.m[10] = -far_z / (far_z - near_z);
    result.m[14] = -(far_z * near_z) / (far_z - near_z);
  }
  result.m[11] = -1.0F;
  return result;
}

Matrix4 pose_matrix(Pose pose) {
  const auto q = normalized(pose.orientation);
  const auto xx = q.x * q.x;
  const auto yy = q.y * q.y;
  const auto zz = q.z * q.z;
  const auto xy = q.x * q.y;
  const auto xz = q.x * q.z;
  const auto yz = q.y * q.z;
  const auto wx = q.w * q.x;
  const auto wy = q.w * q.y;
  const auto wz = q.w * q.z;

  Matrix4 result{};
  result.m[0] = 1.0F - 2.0F * (yy + zz);
  result.m[1] = 2.0F * (xy + wz);
  result.m[2] = 2.0F * (xz - wy);
  result.m[4] = 2.0F * (xy - wz);
  result.m[5] = 1.0F - 2.0F * (xx + zz);
  result.m[6] = 2.0F * (yz + wx);
  result.m[8] = 2.0F * (xz + wy);
  result.m[9] = 2.0F * (yz - wx);
  result.m[10] = 1.0F - 2.0F * (xx + yy);
  result.m[12] = pose.position.x;
  result.m[13] = pose.position.y;
  result.m[14] = pose.position.z;
  result.m[15] = 1.0F;
  return result;
}

Matrix4 multiply(Matrix4 left, Matrix4 right) {
  Matrix4 result{};
  for (std::size_t column = 0; column < 4; ++column) {
    for (std::size_t row = 0; row < 4; ++row) {
      for (std::size_t inner = 0; inner < 4; ++inner) {
        result.m[column * 4 + row] +=
            left.m[inner * 4 + row] * right.m[column * 4 + inner];
      }
    }
  }
  return result;
}

std::array<float, 4> transform(Matrix4 matrix,
                               std::array<float, 4> vector) {
  std::array<float, 4> result{};
  for (std::size_t row = 0; row < 4; ++row) {
    result[row] = matrix.m[row] * vector[0] +
                  matrix.m[4 + row] * vector[1] +
                  matrix.m[8 + row] * vector[2] +
                  matrix.m[12 + row] * vector[3];
  }
  return result;
}

float linear_depth_forward(float depth, float near_z, float far_z) {
  if (!(near_z > 0.0F) || !(far_z > near_z) || depth < 0.0F || depth > 1.0F) {
    throw std::invalid_argument("Invalid forward depth conversion inputs");
  }
  return near_z * far_z / (far_z - depth * (far_z - near_z));
}

float linear_depth_reversed(float depth, float near_z, float far_z) {
  if (!(near_z > 0.0F) || !(far_z > near_z) || depth < 0.0F || depth > 1.0F) {
    throw std::invalid_argument("Invalid reversed depth conversion inputs");
  }
  return near_z * far_z / (near_z + depth * (far_z - near_z));
}

float metres_to_engine_units(float metres, float engine_units_per_metre) {
  validate_scale(engine_units_per_metre);
  return metres * engine_units_per_metre;
}

float engine_units_to_metres(float units, float engine_units_per_metre) {
  validate_scale(engine_units_per_metre);
  return units / engine_units_per_metre;
}

float eye_offset_engine_units(float ipd_metres, float engine_units_per_metre) {
  return metres_to_engine_units(ipd_metres, engine_units_per_metre) * 0.5F;
}

RecenteredProjection recentered_symmetric_projection(
    Fov runtime_fov, float render_aspect) {
  if (!(render_aspect > 0.0F) || !std::isfinite(render_aspect) ||
      !std::isfinite(runtime_fov.angle_left) ||
      !std::isfinite(runtime_fov.angle_right) ||
      !std::isfinite(runtime_fov.angle_up) ||
      !std::isfinite(runtime_fov.angle_down) ||
      runtime_fov.angle_left >= runtime_fov.angle_right ||
      runtime_fov.angle_down >= runtime_fov.angle_up) {
    throw std::invalid_argument("Invalid recentered projection inputs");
  }

  const auto horizontal_center =
      (runtime_fov.angle_left + runtime_fov.angle_right) * 0.5F;
  const auto vertical_center =
      (runtime_fov.angle_down + runtime_fov.angle_up) * 0.5F;
  const auto vertical_half =
      (runtime_fov.angle_up - runtime_fov.angle_down) * 0.5F;
  const auto horizontal_half =
      std::atan(std::tan(vertical_half) * render_aspect);
  if (!(vertical_half > 0.0F) || !(horizontal_half > 0.0F) ||
      vertical_half >= 1.57079633F || horizontal_half >= 1.57079633F) {
    throw std::invalid_argument("Recentered projection exceeds a hemisphere");
  }

  // OpenXR is +X right, +Y up and -Z forward. Positive rotation around +Y
  // turns -Z toward -X, hence the negated horizontal optical-center angle.
  const auto yaw = from_axis_angle({0.0F, 1.0F, 0.0F}, -horizontal_center);
  const auto pitch =
      from_axis_angle({1.0F, 0.0F, 0.0F}, vertical_center);
  return {multiply(yaw, pitch),
          {-horizontal_half, horizontal_half, vertical_half, -vertical_half}};
}

}  // namespace darktidevr::math
