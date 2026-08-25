#include "core/xr_math.h"
#include "core/head_tracking.h"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

constexpr float kPi = 3.14159265358979323846F;

void expect_near(float actual, float expected, float tolerance,
                 const std::string& label) {
  if (std::abs(actual - expected) > tolerance) {
    throw std::runtime_error(label + ": expected " + std::to_string(expected) +
                             ", got " + std::to_string(actual));
  }
}

void expect_vec(darktidevr::math::Vec3 actual, darktidevr::math::Vec3 expected,
                const std::string& label) {
  expect_near(actual.x, expected.x, 0.0001F, label + ".x");
  expect_near(actual.y, expected.y, 0.0001F, label + ".y");
  expect_near(actual.z, expected.z, 0.0001F, label + ".z");
}

}  // namespace

int main() {
  try {
    using namespace darktidevr::math;

    const auto yaw_90 = from_axis_angle({0.0F, 1.0F, 0.0F}, kPi * 0.5F);
    expect_vec(rotate(yaw_90, {0.0F, 0.0F, -1.0F}), {-1.0F, 0.0F, 0.0F},
               "yaw rotation");

    const Pose parent{yaw_90, {10.0F, 2.0F, 3.0F}};
    const Pose child{{}, {0.0F, 0.0F, -2.0F}};
    const auto composed = compose(parent, child);
    expect_vec(composed.position, {8.0F, 2.0F, 3.0F}, "pose composition");
    const Vec3 local_point{0.3F, -0.4F, 2.0F};
    expect_vec(transform_point(inverse(composed),
                               transform_point(composed, local_point)),
               local_point, "pose inverse");
    const auto composed_matrix = pose_matrix(composed);
    const auto point_matrix = transform(
        composed_matrix, {local_point.x, local_point.y, local_point.z, 1.0F});
    expect_vec({point_matrix[0], point_matrix[1], point_matrix[2]},
               transform_point(composed, local_point), "pose matrix");
    const auto identity_matrix =
        multiply(pose_matrix(inverse(composed)), composed_matrix);
    const auto identity_point = transform(identity_matrix, {0.2F, 0.3F, -4.0F, 1.0F});
    expect_near(identity_point[0], 0.2F, 0.0001F, "matrix inverse x");
    expect_near(identity_point[1], 0.3F, 0.0001F, "matrix inverse y");
    expect_near(identity_point[2], -4.0F, 0.0001F, "matrix inverse z");

    const Fov fov{-0.7F, 0.9F, 0.8F, -0.6F};
    const auto projection = projection_d3d(fov, 0.1F, 100.0F);
    const auto project_ray = [&projection](float x, float y) {
      const auto clip = transform(projection, {x, y, -1.0F, 1.0F});
      return std::array<float, 2>{clip[0] / clip[3], clip[1] / clip[3]};
    };
    expect_near(project_ray(std::tan(fov.angle_left), 0.0F)[0], -1.0F,
                0.0001F, "left FOV maps to clip edge");
    expect_near(project_ray(std::tan(fov.angle_right), 0.0F)[0], 1.0F,
                0.0001F, "right FOV maps to clip edge");
    expect_near(project_ray(0.0F, std::tan(fov.angle_up))[1], 1.0F, 0.0001F,
                "upper FOV maps to clip edge");
    expect_near(project_ray(0.0F, std::tan(fov.angle_down))[1], -1.0F,
                0.0001F, "lower FOV maps to clip edge");

    const Fov runtime_eye{-0.942478F, 0.698132F, 0.767945F, -0.959931F};
    const auto recentered_projection =
        recentered_symmetric_projection(runtime_eye, 2112.0F / 2304.0F);
    expect_near(recentered_projection.symmetric_fov.angle_left,
                -recentered_projection.symmetric_fov.angle_right, 0.0001F,
                "recentered horizontal symmetry");
    expect_near(recentered_projection.symmetric_fov.angle_down,
                -recentered_projection.symmetric_fov.angle_up, 0.0001F,
                "recentered vertical symmetry");
    expect_near(recentered_projection.symmetric_fov.angle_up,
                (runtime_eye.angle_up - runtime_eye.angle_down) * 0.5F,
                0.0001F, "recentered vertical coverage");
    const auto optical_forward = rotate(
        recentered_projection.orientation_offset, {0.0F, 0.0F, -1.0F});
    if (!(optical_forward.x < 0.0F && optical_forward.y < 0.0F)) {
      throw std::runtime_error(
          "recentered optical axis did not rotate left and down");
    }

    expect_near(linear_depth_forward(0.0F, 0.1F, 100.0F), 0.1F, 0.0001F,
                "forward depth near");
    expect_near(linear_depth_forward(1.0F, 0.1F, 100.0F), 100.0F, 0.01F,
                "forward depth far");
    expect_near(linear_depth_reversed(1.0F, 0.1F, 100.0F), 0.1F, 0.0001F,
                "reversed depth near");
    expect_near(linear_depth_reversed(0.0F, 0.1F, 100.0F), 100.0F, 0.01F,
                "reversed depth far");

    expect_near(metres_to_engine_units(1.25F, 100.0F), 125.0F, 0.0001F,
                "metres to engine units");
    expect_near(engine_units_to_metres(125.0F, 100.0F), 1.25F, 0.0001F,
                "engine units to metres");
    expect_near(eye_offset_engine_units(0.064F, 100.0F), 3.2F, 0.0001F,
                "per-eye IPD offset");

    const Pose recenter{{}, {10.0F, 2.0F, -4.0F}};
    const Pose current{yaw_90, {10.3F, 2.5F, -4.4F}};
    const auto head_delta = darktidevr::core::recentered_head_delta(
        recenter, current, {0.25F, 0.18F});
    expect_near(std::sqrt(head_delta.position.x * head_delta.position.x +
                          head_delta.position.z * head_delta.position.z),
                0.25F, 0.0001F, "horizontal lean clamp");
    expect_near(head_delta.position.y, 0.18F, 0.0001F,
                "vertical lean clamp");
    expect_vec(rotate(head_delta.orientation, {0.0F, 0.0F, -1.0F}),
               {-1.0F, 0.0F, 0.0F}, "recentered orientation");

    const auto rotated_recenter = Pose{yaw_90, {0.0F, 0.0F, 0.0F}};
    const auto local_forward = darktidevr::core::recentered_head_delta(
        rotated_recenter, {yaw_90, {-1.0F, 0.0F, 0.0F}}, {2.0F, 2.0F});
    expect_vec(local_forward.position, {0.0F, 0.0F, -1.0F},
               "translation uses recenter-local coordinates");

    // A pure headset roll must survive recentering. Yaw/pitch-only coverage
    // would not catch an accidental 2DoF projection path.
    const auto roll_30 = from_axis_angle({0.0F, 0.0F, -1.0F}, kPi / 6.0F);
    const auto roll_delta = darktidevr::core::recentered_head_delta(
        Pose{}, Pose{roll_30, {}}, {0.0F, 0.0F});
    expect_vec(rotate(roll_delta.orientation, {0.0F, 1.0F, 0.0F}),
               {0.5F, std::sqrt(3.0F) * 0.5F, 0.0F},
               "recentered roll orientation");

    // Projection poses are absolute in LOCAL space: anchoring the delta back
    // onto its baseline must reconstruct the current orientation, including
    // roll, rather than treating the relative delta as an absolute pose.
    const Pose roll_anchor{yaw_90, {1.0F, 2.0F, 3.0F}};
    const Pose rolled_current{multiply(yaw_90, roll_30),
                              roll_anchor.position};
    const auto anchored_delta = darktidevr::core::recentered_head_delta(
        roll_anchor, rolled_current, {0.0F, 0.0F});
    const auto reconstructed = compose(
        roll_anchor, Pose{anchored_delta.orientation, {}});
    expect_vec(rotate(reconstructed.orientation, {0.0F, 1.0F, 0.0F}),
               rotate(rolled_current.orientation, {0.0F, 1.0F, 0.0F}),
               "absolute projection roll anchor");

    // Both the game cameras and submitted OpenXR image planes must consume
    // the same full head delta. Verify that anchoring a translated delta
    // moves the eye-pair midpoint while preserving the runtime IPD.
    const Pose sixdof_anchor{yaw_90, {1.0F, 2.0F, 3.0F}};
    const Pose sixdof_local_delta{
        roll_30, {0.12F, -0.08F, -0.16F}};
    const auto sixdof_current = compose(sixdof_anchor, sixdof_local_delta);
    const auto sixdof_delta = darktidevr::core::recentered_head_delta(
        sixdof_anchor, sixdof_current, {0.25F, 0.18F});
    const Pose left_eye = compose(
        sixdof_current, Pose{{}, {-0.032F, 0.0F, 0.0F}});
    const Pose right_eye = compose(
        sixdof_current, Pose{{}, {0.032F, 0.0F, 0.0F}});
    const auto anchored_left =
        darktidevr::core::anchored_recentered_eye_pose(
            sixdof_anchor, sixdof_delta, sixdof_current, left_eye);
    const auto anchored_right =
        darktidevr::core::anchored_recentered_eye_pose(
            sixdof_anchor, sixdof_delta, sixdof_current, right_eye);
    const Vec3 submitted_midpoint{
        (anchored_left.position.x + anchored_right.position.x) * 0.5F,
        (anchored_left.position.y + anchored_right.position.y) * 0.5F,
        (anchored_left.position.z + anchored_right.position.z) * 0.5F};
    expect_vec(submitted_midpoint, sixdof_current.position,
               "6dof submitted eye midpoint");
    const Vec3 submitted_ipd{
        anchored_right.position.x - anchored_left.position.x,
        anchored_right.position.y - anchored_left.position.y,
        anchored_right.position.z - anchored_left.position.z};
    expect_near(std::sqrt(submitted_ipd.x * submitted_ipd.x +
                          submitted_ipd.y * submitted_ipd.y +
                          submitted_ipd.z * submitted_ipd.z),
                0.064F, 0.0001F, "6dof submitted IPD");

    std::cout << "core_math.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "core_math: " << error.what() << '\n';
    return 1;
  }
}
