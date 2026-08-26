#pragma once

#include <array>

namespace darktidevr::math {

struct Vec3 {
  float x{};
  float y{};
  float z{};
};

struct Quaternion {
  float x{};
  float y{};
  float z{};
  float w{1.0F};
};

struct Pose {
  Quaternion orientation{};
  Vec3 position{};
};

struct Fov {
  float angle_left{};
  float angle_right{};
  float angle_up{};
  float angle_down{};
};

struct RecenteredProjection {
  Quaternion orientation_offset{};
  Fov symmetric_fov{};
};

struct BillboardBasis {
  Vec3 right{};
  Vec3 up{};
  bool used_fallback{};
};

// Column-major, column-vector convention. OpenXR space is +X right, +Y up,
// -Z forward. D3D clip depth is [0, 1].
struct Matrix4 {
  std::array<float, 16> m{};
};

Quaternion normalized(Quaternion value);
Quaternion conjugate(Quaternion value);
Quaternion multiply(Quaternion parent, Quaternion child);
Quaternion from_axis_angle(Vec3 axis, float radians);
Vec3 rotate(Quaternion rotation, Vec3 value);

// Converts OpenXR's +X right, +Y up, -Z forward convention to Darktide's
// +X right, +Y forward, +Z up convention. The quaternion conversion is the
// equivalent basis change, not an Euler-angle reinterpretation.
Vec3 openxr_to_darktide(Vec3 value);
Quaternion openxr_to_darktide(Quaternion value);
Pose openxr_to_darktide(Pose value);
Vec3 darktide_to_openxr(Vec3 value);
Quaternion darktide_to_openxr(Quaternion value);
Pose darktide_to_openxr(Pose value);

Pose compose(Pose parent, Pose child);
Pose inverse(Pose pose);
Vec3 transform_point(Pose pose, Vec3 point);

Matrix4 projection_d3d(Fov fov, float near_z, float far_z);
Matrix4 pose_matrix(Pose pose);
Matrix4 multiply(Matrix4 left, Matrix4 right);
std::array<float, 4> transform(Matrix4 matrix,
                               std::array<float, 4> vector);

float linear_depth_forward(float depth, float near_z, float far_z);
float linear_depth_reversed(float depth, float near_z, float far_z);

float metres_to_engine_units(float metres, float engine_units_per_metre);
float engine_units_to_metres(float units, float engine_units_per_metre);
float eye_offset_engine_units(float ipd_metres, float engine_units_per_metre);

// Converts an off-axis runtime frustum into a symmetric render frustum plus a
// local camera rotation. The returned FOV is constrained to render_aspect so
// an engine with only vertical-FOV control and the OpenXR compositor consume
// exactly the same projection.
RecenteredProjection recentered_symmetric_projection(
    Fov runtime_fov, float render_aspect);

// Builds a cylindrical billboard basis for Darktide's Z-up world. Camera
// pitch/roll are deliberately removed. Near a vertical look direction, the
// previous horizontal right vector prevents an undefined yaw and visible flip.
BillboardBasis z_up_billboard_basis(Vec3 camera_forward,
                                    Vec3 fallback_right);

}  // namespace darktidevr::math
