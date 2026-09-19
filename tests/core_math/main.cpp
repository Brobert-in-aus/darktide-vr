#include "core/xr_math.h"
#include "core/head_tracking.h"

#include <cmath>
#include <iostream>
#include <limits>
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

    expect_vec(openxr_to_darktide(Vec3{0.0F, 0.0F, -1.0F}),
               {0.0F, 1.0F, 0.0F}, "OpenXR forward to Darktide");
    expect_vec(openxr_to_darktide(Vec3{0.0F, 1.0F, 0.0F}),
               {0.0F, 0.0F, 1.0F}, "OpenXR up to Darktide");
    const auto xr_pitch =
        from_axis_angle({1.0F, 0.0F, 0.0F}, kPi * 0.25F);
    const Vec3 xr_test_vector{0.2F, 0.4F, -0.8F};
    expect_vec(
        rotate(openxr_to_darktide(xr_pitch),
               openxr_to_darktide(xr_test_vector)),
        openxr_to_darktide(rotate(xr_pitch, xr_test_vector)),
        "OpenXR quaternion basis conversion");
    const Pose xr_controller{xr_pitch, {0.3F, 1.2F, -0.5F}};
    const auto darktide_controller = openxr_to_darktide(xr_controller);
    expect_vec(darktide_controller.position, {0.3F, 0.5F, 1.2F},
               "OpenXR controller pose position");
    expect_vec(darktide_to_openxr(darktide_controller).position,
               xr_controller.position,
               "Darktide pose converts back to OpenXR");
    expect_vec(rotate(darktide_to_openxr(darktide_controller).orientation,
                      {0.0F, 0.0F, -1.0F}),
               rotate(xr_controller.orientation, {0.0F, 0.0F, -1.0F}),
               "Darktide quaternion converts back to OpenXR");
    const Pose controller_recenter{
        from_axis_angle({0.0F, 1.0F, 0.0F}, kPi * 0.5F),
        {3.0F, 1.6F, -2.0F}};
    const Pose controller_body_local{
        from_axis_angle({1.0F, 0.0F, 0.0F}, -kPi * 0.25F),
        {0.35F, -0.25F, -0.55F}};
    const auto absolute_controller =
        compose(controller_recenter, controller_body_local);
    const auto body_controller =
        darktidevr::core::recentered_controller_pose(
            controller_recenter, absolute_controller);
    expect_vec(body_controller.position, {0.35F, 0.55F, -0.25F},
               "recentered controller position");
    expect_vec(
        rotate(body_controller.orientation, {0.0F, 1.0F, 0.0F}),
        openxr_to_darktide(rotate(controller_body_local.orientation,
                                 {0.0F, 0.0F, -1.0F})),
        "recentered controller aim direction");
    const auto reconstructed_controller =
        darktidevr::core::anchored_controller_pose(controller_recenter,
                                                   body_controller);
    expect_vec(reconstructed_controller.position, absolute_controller.position,
               "body-relative controller reconstructs OpenXR LOCAL position");
    expect_vec(rotate(reconstructed_controller.orientation,
                      {0.0F, 0.0F, -1.0F}),
               rotate(absolute_controller.orientation,
                      {0.0F, 0.0F, -1.0F}),
               "body-relative controller reconstructs OpenXR LOCAL orientation");
    const auto reconstructed_panel =
        darktidevr::core::anchored_body_panel_pose(controller_recenter,
                                                   body_controller);
    expect_vec(reconstructed_panel.position, reconstructed_controller.position,
               "body panel uses the shared anchored-pose mapping");

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
    if (!fov_usable(runtime_eye) || fov_usable(Fov{}) ||
        fov_usable(Fov{0.5F, -0.5F, 0.5F, -0.5F}) ||
        fov_usable(Fov{-0.5F, 0.5F, -0.5F, 0.5F}) ||
        fov_usable(Fov{-0.5F, std::numeric_limits<float>::quiet_NaN(), 0.5F, -0.5F})) {
      throw std::runtime_error("fov_usable accepted an unusable frustum or rejected a real one");
    }
    bool zero_fov_threw = false;
    try {
      static_cast<void>(recentered_symmetric_projection(Fov{}, 1.0F));
    } catch (const std::invalid_argument&) {
      zero_fov_threw = true;
    }
    if (!zero_fov_threw) {
      throw std::runtime_error("recentered projection accepted a zero field of view");
    }
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

    // The eye images are submitted with the recentered projection and the
    // game renders them with it, so anything the viewer draws INTO them --
    // the tracked cuffs, the gameplay reticle -- must use it too. It is not
    // interchangeable with the runtime's own off-axis frustum, which is what
    // the cuffs used until 18 September. Virtual Desktop's left eye at the 90
    // per cent tangent, from artifacts/unattended/hub-100hz-1.
    const Fov vd_left{-0.893445F, 0.648593F, 0.71549F, -0.909609F};
    const auto vd_recentered =
        recentered_symmetric_projection(vd_left, 1908.0F / 2076.0F);
    const auto ndc = [](Matrix4 matrix, Vec3 direction) {
      const auto clip =
          transform(matrix, {direction.x, direction.y, direction.z, 1.0F});
      return std::array<float, 2>{clip[0] / clip[3], clip[1] / clip[3]};
    };
    // A point ten metres along the eye's own optical axis: the direction the
    // rendered image is centred on.
    const auto vd_axis = rotate(vd_recentered.orientation_offset,
                                {0.0F, 0.0F, -1.0F});
    const Vec3 ahead{vd_axis.x * 10.0F, vd_axis.y * 10.0F, vd_axis.z * 10.0F};
    const auto submitted_ndc = ndc(
        multiply(projection_d3d(vd_recentered.symmetric_fov, 0.025F, 100.0F),
                 pose_matrix(inverse(Pose{vd_recentered.orientation_offset,
                                          {0.0F, 0.0F, 0.0F}}))),
        ahead);
    expect_near(submitted_ndc[0], 0.0F, 0.0001F,
                "the submitted projection centres its own optical axis");
    expect_near(submitted_ndc[1], 0.0F, 0.0001F,
                "the submitted projection centres its own optical axis");
    // The raw frustum does not centre it: a ninth of the way to the edge
    // horizontally and a tenth vertically, which is 6.2 and 5.9 degrees, and
    // is what anything drawn the old way is displaced by. Worse, the
    // horizontal error reverses in the other eye, so the two images disagree
    // -- a stereo disparity claiming a depth the object is not at.
    const auto raw_ndc = ndc(projection_d3d(vd_left, 0.025F, 100.0F), ahead);
    expect_near(raw_ndc[0], 0.11955F, 0.001F,
                "the runtime frustum's horizontal displacement");
    expect_near(raw_ndc[1], 0.10212F, 0.001F,
                "the runtime frustum's vertical displacement");
    const Fov vd_right{-0.648593F, 0.893445F, 0.71549F, -0.909609F};
    const auto right_axis =
        rotate(recentered_symmetric_projection(vd_right, 1908.0F / 2076.0F)
                   .orientation_offset,
               {0.0F, 0.0F, -1.0F});
    const auto right_raw_ndc =
        ndc(projection_d3d(vd_right, 0.025F, 100.0F),
            {right_axis.x * 10.0F, right_axis.y * 10.0F,
             right_axis.z * 10.0F});
    if (!(raw_ndc[0] * right_raw_ndc[0] < 0.0F)) {
      throw std::runtime_error(
          "the raw frustum's horizontal error should reverse between eyes");
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

    const auto billboard_north =
        z_up_billboard_basis({0.0F, 1.0F, 0.0F}, {0.0F, 1.0F, 0.0F});
    expect_vec(billboard_north.right, {1.0F, 0.0F, 0.0F},
               "north billboard right");
    expect_vec(billboard_north.up, {0.0F, 0.0F, 1.0F},
               "north billboard up");
    const auto billboard_east =
        z_up_billboard_basis({1.0F, 0.0F, 0.0F}, {1.0F, 0.0F, 0.0F});
    expect_vec(billboard_east.right, {0.0F, -1.0F, 0.0F},
               "east billboard right");
    const auto billboard_pitched =
        z_up_billboard_basis({0.0F, 0.001F, 10.0F}, {-1.0F, 0.0F, 0.0F});
    expect_vec(billboard_pitched.right, {1.0F, 0.0F, 0.0F},
               "pitched billboard removes camera pitch");
    if (billboard_pitched.used_fallback) {
      throw std::runtime_error("Finite horizontal billboard direction fell back");
    }
    const auto billboard_vertical =
        z_up_billboard_basis({0.0F, 0.0F, 1.0F}, {0.0F, -2.0F, 8.0F});
    expect_vec(billboard_vertical.right, {0.0F, -1.0F, 0.0F},
               "vertical billboard fallback");
    if (!billboard_vertical.used_fallback) {
      throw std::runtime_error("Vertical billboard direction did not fall back");
    }
    const auto nan = std::numeric_limits<float>::quiet_NaN();
    const auto billboard_invalid =
        z_up_billboard_basis({nan, nan, nan}, {nan, nan, nan});
    expect_vec(billboard_invalid.right, {1.0F, 0.0F, 0.0F},
               "invalid billboard deterministic fallback");

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

    Pose sliding_anchor{};
    const auto donned = darktidevr::core::sliding_recentered_head_delta(
        sliding_anchor, Pose{{}, {1.0F, 0.8F, 0.0F}}, {0.25F, 0.18F});
    expect_vec(donned.position, {0.25F, 0.18F, 0.0F},
               "donning movement remains bounded");
    expect_vec(sliding_anchor.position, {0.75F, 0.62F, 0.0F},
               "excess donning movement advances recenter origin");
    const auto small_return =
        darktidevr::core::sliding_recentered_head_delta(
            sliding_anchor, Pose{{}, {0.98F, 0.78F, 0.0F}},
            {0.25F, 0.18F});
    expect_vec(small_return.position, {0.23F, 0.16F, 0.0F},
               "small inward movement responds after donning clamp");

    Pose body_follow_anchor{};
    const auto body_follow = darktidevr::core::sliding_head_translation(
        body_follow_anchor, Pose{{}, {1.0F, 0.8F, -0.5F}},
        {0.25F, 0.18F});
    expect_near(std::sqrt(
                    body_follow.camera_delta.position.x *
                        body_follow.camera_delta.position.x +
                    body_follow.camera_delta.position.z *
                        body_follow.camera_delta.position.z),
                0.25F, 0.0001F, "body-follow camera lean remains bounded");
    expect_vec(body_follow.body_follow_delta,
               {1.0F - 0.25F / std::sqrt(1.25F), 0.0F,
                -0.5F + 0.125F / std::sqrt(1.25F)},
               "body-follow exposes horizontal excess only");
    expect_near(body_follow_anchor.position.y, 0.62F, 0.0001F,
                "vertical excess still advances tracking anchor");

    Pose direct_body_anchor{};
    const auto direct_body_follow =
        darktidevr::core::sliding_head_translation(
            direct_body_anchor, Pose{{}, {0.12F, 0.08F, -0.07F}},
            {0.0F, 0.18F});
    expect_vec(direct_body_follow.camera_delta.position,
               {0.0F, 0.08F, 0.0F},
               "zero horizontal envelope leaves only physical crouch camera motion");
    expect_vec(direct_body_follow.body_follow_delta,
               {0.12F, 0.0F, -0.07F},
               "zero horizontal envelope transfers all room-scale motion to body");

    Pose path_anchor{};
    Vec3 cumulative_body_follow{};
    const float physical_path[] = {
        0.0F, 0.10F, 0.30F, 0.65F, 0.30F,
        0.0F, -0.30F, -0.65F, -0.30F, 0.0F};
    for (const auto physical_x : physical_path) {
      const auto sample = darktidevr::core::sliding_head_translation(
          path_anchor, Pose{{}, {physical_x, 0.0F, 0.0F}},
          {0.25F, 0.18F});
      cumulative_body_follow.x += sample.body_follow_delta.x;
      cumulative_body_follow.z += sample.body_follow_delta.z;
      expect_near(cumulative_body_follow.x + sample.camera_delta.position.x,
                  physical_x, 0.0001F,
                  "body-follow plus camera lean preserves physical position");
      if (std::abs(sample.camera_delta.position.x) > 0.2501F) {
        throw std::runtime_error(
            "oscillating room-scale path escaped camera envelope");
      }
      if (std::abs(cumulative_body_follow.x) > 0.6501F) {
        throw std::runtime_error(
            "oscillating room-scale path inflated body displacement");
      }
    }

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

    // Recenter preserves yaw but never adopts physical pitch or roll as the
    // new level. Those components must remain in the first live camera delta.
    const auto pitch_down =
        from_axis_angle({1.0F, 0.0F, 0.0F}, -kPi / 4.0F);
    const Pose tilted_head{
        multiply(yaw_90, multiply(pitch_down, roll_30)),
        {1.0F, 1.6F, -2.0F}};
    const auto level_anchor =
        darktidevr::core::horizon_locked_recenter_pose(tilted_head);
    expect_vec(level_anchor.position, tilted_head.position,
               "level recenter preserves position");
    expect_vec(rotate(level_anchor.orientation, {0.0F, 1.0F, 0.0F}),
               {0.0F, 1.0F, 0.0F},
               "level recenter removes pitch and roll");
    expect_vec(rotate(level_anchor.orientation, {0.0F, 0.0F, -1.0F}),
               {-1.0F, 0.0F, 0.0F}, "level recenter preserves yaw");
    const auto tilted_delta = darktidevr::core::recentered_head_delta(
        level_anchor, tilted_head, {0.0F, 0.0F});
    const auto tilted_reconstructed = compose(level_anchor, tilted_delta);
    expect_vec(rotate(tilted_reconstructed.orientation,
                      {0.0F, 1.0F, 0.0F}),
               rotate(tilted_head.orientation, {0.0F, 1.0F, 0.0F}),
               "level recenter retains live tilt in camera delta");

    // The eyes translate vertically when the skull rotates about the neck.
    // A fixed-neck +/-45 degree look must not masquerade as crouch/tiptoe,
    // while a real simultaneous body descent must survive compensation.
    const Vec3 neck_to_hmd{0.0F, 0.075F, -0.0805F};
    const Pose neck_baseline{{}, {}};
    for (const auto pitch_radians : {-kPi * 0.25F, kPi * 0.25F}) {
      const auto orientation =
          from_axis_angle({1.0F, 0.0F, 0.0F}, pitch_radians);
      const auto arc = rotate(orientation, neck_to_hmd);
      const Vec3 fixed_neck_translation{
          arc.x - neck_to_hmd.x, arc.y - neck_to_hmd.y,
          arc.z - neck_to_hmd.z};
      const Pose fixed_neck_head{orientation, fixed_neck_translation};
      expect_near(darktidevr::core::neck_pivot_height_delta(
                      neck_baseline, fixed_neck_head, neck_to_hmd),
                  0.0F, 0.0001F, "neck pivot rejects pitch arc");
      auto crouched_head = fixed_neck_head;
      crouched_head.position.y -= 0.30F;
      expect_near(darktidevr::core::neck_pivot_height_delta(
                      neck_baseline, crouched_head, neck_to_hmd),
                  -0.30F, 0.0001F,
                  "neck pivot preserves simultaneous crouch");
    }

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

    // THE ZOOM MUST REACH THE RECENTRING, not just the submitted fov.
    //
    // `recentered_symmetric_projection` returns an orientation offset as well
    // as a frustum, and the offset is the half that diverges the eyes: it
    // turns each view onto its own optical axis, and the two eyes' axes lean
    // opposite ways. A build that zoomed the fov but recentred from the
    // UNZOOMED frustum would submit a symmetric frustum of the right width
    // pointing fractionally the wrong way, in opposite directions per eye.
    //
    // The frustum alone cannot catch that -- both orders leave it symmetric,
    // and their half-widths differ by 0.006 in tangent, which is noise next
    // to what the fov check above already covers. The offset can.
    {
      const Fov eye{-0.893445F, 0.648593F, 0.71549F, -0.909609F};
      const auto aspect = 2112.0F / 2304.0F;
      const auto m = 1.15F;
      const auto zoomed_first = recentered_symmetric_projection(zoomed_fov(eye, m), aspect);
      const auto not_zoomed = recentered_symmetric_projection(eye, aspect);
      // The frustum's own centre, computed here rather than taken from the
      // helper, is what the offset undoes.
      const auto centre = [](const Fov& f) {
        return (f.angle_left + f.angle_right) * 0.5F;
      };
      const auto shift = std::abs(centre(zoomed_fov(eye, m)) - centre(eye));
      // The zoom moves the optical axis. Small -- about 0.09 degrees at this
      // magnification -- but opposite per eye, and it is exactly the term
      // that has to come from the zoomed frustum rather than the raw one.
      if (!(shift > 1e-4F)) {
        throw std::runtime_error(
            "the zoom does not move the optical axis, so this guard cannot "
            "catch the recentring being fed the unzoomed frustum");
      }
      // And the two projections really are different objects: if a change
      // made recentring ignore the zoom, these would collapse together.
      const auto& a = zoomed_first.orientation_offset;
      const auto& b = not_zoomed.orientation_offset;
      const auto difference = std::abs(a.x - b.x) + std::abs(a.y - b.y) +
                              std::abs(a.z - b.z) + std::abs(a.w - b.w);
      if (!(difference > 1e-5F)) {
        throw std::runtime_error(
            "recentring gave the same orientation for a zoomed and an "
            "unzoomed frustum");
      }
    }

    // THE AIM ZOOM MUST REACH THE SUBMITTED PROJECTION (19 September).
    //
    // The game's cameras render through the Lua's Projection.zoomed_frustum;
    // the runtime displays the result through this. Any difference between
    // them is the two eyes pulled apart, because recentring turns each eye
    // onto its own optical axis and a magnification about THAT axis moves the
    // eyes in opposite directions.
    {
      const Fov zoom_runtime_eye{-0.893445F, 0.648593F, 0.71549F, -0.909609F};
      // The Lua's arithmetic, written out independently rather than by
      // calling the same helper -- that is the only way this can fail if the
      // C++ drifts from it.
      const auto lua_edge = [](float angle, float m) {
        return std::atan(std::tan(angle) / m);
      };
      for (const float m : {1.01F, 1.03F, 1.15F, 1.30F, 3.99F}) {
        const auto narrowed = zoomed_fov(zoom_runtime_eye, m);
        expect_near(narrowed.angle_left, lua_edge(zoom_runtime_eye.angle_left, m), 1e-6F,
                    "zoomed left edge matches the Lua");
        expect_near(narrowed.angle_right, lua_edge(zoom_runtime_eye.angle_right, m), 1e-6F,
                    "zoomed right edge matches the Lua");
        expect_near(narrowed.angle_up, lua_edge(zoom_runtime_eye.angle_up, m), 1e-6F,
                    "zoomed up edge matches the Lua");
        expect_near(narrowed.angle_down, lua_edge(zoom_runtime_eye.angle_down, m), 1e-6F,
                    "zoomed down edge matches the Lua");
        // It narrows. A zoom that widened the frustum would push the eyes the
        // other way and still "look like a zoom" in a still image.
        if (!(std::tan(narrowed.angle_right) - std::tan(narrowed.angle_left) <
              std::tan(zoom_runtime_eye.angle_right) - std::tan(zoom_runtime_eye.angle_left))) {
          throw std::runtime_error("zoomed_fov did not narrow the frustum");
        }
      }
      // No zoom, no change -- byte for byte, so the unzoomed path cannot
      // acquire a rounding drift that would itself diverge the eyes.
      for (const float m : {1.0F, 1.00005F, 0.5F, 4.5F,
                            std::numeric_limits<float>::quiet_NaN()}) {
        const auto untouched = zoomed_fov(zoom_runtime_eye, m);
        if (untouched.angle_left != zoom_runtime_eye.angle_left ||
            untouched.angle_right != zoom_runtime_eye.angle_right ||
            untouched.angle_up != zoom_runtime_eye.angle_up ||
            untouched.angle_down != zoom_runtime_eye.angle_down) {
          throw std::runtime_error("zoomed_fov moved an unzoomed frustum");
        }
      }
      // And the whole point, in the units the fault was measured in: with the
      // zoom carried through, the optical axis the submitted projection
      // recentres onto is the one the cameras rendered with. Left unfixed the
      // two differ, and the eyes diverge by twice that difference.
      const auto aspect = 2112.0F / 2304.0F;
      const auto unzoomed = recentered_symmetric_projection(zoom_runtime_eye, aspect);
      const auto zoom_recentred =
          recentered_symmetric_projection(zoomed_fov(zoom_runtime_eye, 1.15F), aspect);
      const auto horizontal = [](const Fov& f) {
        return (f.angle_left + f.angle_right) * 0.5F;
      };
      if (!(std::abs(horizontal(unzoomed.symmetric_fov) -
                     horizontal(zoom_recentred.symmetric_fov)) < 1e-6F)) {
        throw std::runtime_error("the recentred frustum is not symmetric");
      }
      // The submitted half-width must follow the zoom, or the image is
      // stretched across a frustum it was not rendered in.
      //
      // Within a quarter of a per cent rather than exactly, and the residual
      // is real rather than slack: the recentred half-width comes from the
      // VERTICAL half times the aspect, and this frustum is vertically
      // asymmetric (up 0.715, down -0.910), so halving the zoomed angles is
      // not quite atan(tan(half) / m). What matters is that it tracks the
      // magnification -- a submitted frustum that had not been zoomed at all
      // would be out by the full 15 per cent here, sixty times this bound.
      const auto half = [](const Fov& f) { return std::tan(f.angle_right); };
      const auto followed = half(zoom_recentred.symmetric_fov) * 1.15F;
      const auto wanted = half(unzoomed.symmetric_fov);
      expect_near(followed / wanted, 1.0F, 5e-3F,
                  "the submitted half-width follows the zoom");
      // And it is unambiguously narrower than the unzoomed one, which is the
      // thing that was missing before 19 September.
      if (!(half(zoom_recentred.symmetric_fov) < wanted * 0.9F)) {
        throw std::runtime_error("the submitted frustum did not narrow with the zoom");
      }
    }

    // Last, not first. Printed above the assertions it is meant to
    // summarise, the log says pass even when they throw -- which is how
    // twelve mutations once came back NOT CAUGHT (19 September).
    std::cout << "core_math.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "core_math: " << error.what() << '\n';
    return 1;
  }
}
