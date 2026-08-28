#include "synthetic_controller_path.h"

#include <cmath>
#include <stdexcept>

namespace darktidevr::harness {

SyntheticControllerPathSample synthetic_controller_path_sample(
    std::uint64_t frame, std::uint64_t sequence, std::uint64_t timestamp_ns,
    math::Pose panel_pose, float panel_width_metres,
    float panel_height_metres, bool emit_gameplay_input) {
  if (sequence == 0 || panel_width_metres <= 0.0F ||
      panel_height_metres <= 0.0F) {
    throw std::invalid_argument("Invalid synthetic controller path inputs");
  }
  constexpr std::uint64_t phase_frames = 60;
  const auto cycle_frame = frame % (phase_frames * 6);
  const auto phase_index = cycle_frame / phase_frames;
  const auto phase_t = static_cast<float>(cycle_frame % phase_frames) /
                       static_cast<float>(phase_frames - 1);
  const auto sweep = (phase_t * 2.0F - 1.0F) * panel_width_metres * 0.6F;

  SyntheticControllerPathSample sample{};
  sample.state.sequence = sequence;
  sample.state.timestamp_ns = timestamp_ns;
  sample.phase = static_cast<SyntheticControllerPhase>(phase_index);
  const auto panel_forward =
      math::rotate(panel_pose.orientation, {0.0F, 0.0F, -1.0F});
  std::array<math::Vec3, 2> local_positions{{
      {-panel_width_metres, panel_height_metres * 0.15F, 1.5F},
      {panel_width_metres, -panel_height_metres * 0.15F, 1.5F},
  }};

  if (sample.phase == SyntheticControllerPhase::left_sweep) {
    local_positions[0].x = sweep;
  } else if (sample.phase == SyntheticControllerPhase::right_sweep) {
    local_positions[1].x = sweep;
  } else if (sample.phase == SyntheticControllerPhase::crossed_sweep) {
    local_positions[0].x = sweep;
    local_positions[1].x = -sweep;
  } else if (sample.phase == SyntheticControllerPhase::outside_panel) {
    local_positions[0].x = -panel_width_metres;
    local_positions[1].x = panel_width_metres;
  } else if (sample.phase == SyntheticControllerPhase::beyond_reach) {
    local_positions[0] = {-panel_width_metres * 0.2F, 0.0F, 4.5F};
    local_positions[1] = {panel_width_metres * 0.2F, 0.0F, 4.5F};
  } else {
    local_positions[0] = {-panel_width_metres * 0.2F, 0.0F, 1.5F};
    local_positions[1] = {panel_width_metres * 0.2F, 0.0F, 1.5F};
  }

  for (std::size_t hand = 0; hand < 2; ++hand) {
    auto& destination = sample.state.hands[hand];
    destination.aim_pose.orientation = panel_pose.orientation;
    destination.grip_pose.orientation = panel_pose.orientation;
    destination.body_aim_pose.orientation.w = 1.0F;
    destination.body_grip_pose.orientation.w = 1.0F;
    destination.aim_pose.position =
        math::transform_point(panel_pose, local_positions[hand]);
    destination.grip_pose.position = destination.aim_pose.position;
    if (sample.phase != SyntheticControllerPhase::tracking_invalid) {
      destination.aim_tracking_flags =
          core::controller_orientation_valid |
          core::controller_position_valid |
          core::controller_orientation_tracked |
          core::controller_position_tracked;
      destination.grip_tracking_flags = destination.aim_tracking_flags;
    }
    sample.rays[hand] = {destination.aim_pose.position, panel_forward};
  }
  if (emit_gameplay_input) {
    if (sample.phase == SyntheticControllerPhase::left_sweep) {
      sample.state.hands[1].trigger = 1.0F;
      sample.state.hands[0].thumbstick_y = 1.0F;
    } else if (sample.phase == SyntheticControllerPhase::right_sweep) {
      sample.state.hands[0].trigger = 1.0F;
      sample.state.hands[0].thumbstick_x = 1.0F;
    } else if (sample.phase == SyntheticControllerPhase::crossed_sweep) {
      sample.state.hands[0].squeeze = 1.0F;
      sample.state.hands[1].squeeze = 1.0F;
      sample.state.hands[0].thumbstick_y = -1.0F;
    } else if (sample.phase == SyntheticControllerPhase::outside_panel) {
      sample.state.hands[0].buttons = core::controller_primary |
                                      core::controller_secondary;
      sample.state.hands[1].buttons = core::controller_primary |
                                      core::controller_secondary;
      sample.state.hands[0].thumbstick_x = -1.0F;
    } else if (sample.phase == SyntheticControllerPhase::beyond_reach) {
      sample.state.hands[0].buttons = core::controller_stick_click |
                                      core::controller_menu;
      sample.state.hands[1].buttons = core::controller_stick_click;
    }
  }
  return sample;
}

void apply_synthetic_body_reach_path(core::SharedControllerState& state,
                                     std::uint64_t frame) {
  constexpr std::uint64_t phase_frames = 60;
  const auto cycle_frame = frame % (phase_frames * 6);
  const auto phase =
      static_cast<SyntheticControllerPhase>(cycle_frame / phase_frames);
  const auto phase_t = static_cast<float>(cycle_frame % phase_frames) /
                       static_cast<float>(phase_frames - 1);
  const auto sweep = phase_t * 0.70F - 0.35F;

  // Darktide body-local basis: +X right, +Y forward and +Z up. These neutral
  // targets sit below and in front of the HMD, close to an adult human's hand
  // positions. The fifth phase intentionally exceeds arm reach.
  std::array<math::Vec3, 2> positions{{
      {-0.25F, 0.25F, -0.25F},
      {0.25F, 0.25F, -0.25F},
  }};
  if (phase == SyntheticControllerPhase::left_sweep) {
    positions[0].x = sweep;
  } else if (phase == SyntheticControllerPhase::right_sweep) {
    positions[1].x = sweep;
  } else if (phase == SyntheticControllerPhase::crossed_sweep) {
    positions[0].x = 0.25F;
    positions[1].x = -0.25F;
    positions[0].y += 0.05F * std::sin(phase_t * 6.28318530718F);
    positions[1].y -= 0.05F * std::sin(phase_t * 6.28318530718F);
  } else if (phase == SyntheticControllerPhase::outside_panel) {
    positions[0] = {-0.65F, 0.25F, -0.25F};
    positions[1] = {0.65F, 0.25F, -0.25F};
  } else if (phase == SyntheticControllerPhase::beyond_reach) {
    positions[0] = {-0.20F, 1.50F, -0.10F};
    positions[1] = {0.20F, 1.50F, -0.10F};
  }

  for (std::size_t hand = 0; hand < 2; ++hand) {
    auto& destination = state.hands[hand];
    const auto wrist_yaw =
        (hand == 0 ? 1.0F : -1.0F) * (phase_t - 0.5F) * 1.2F;
    const auto wrist_orientation =
        math::from_axis_angle({0.0F, 0.0F, 1.0F}, wrist_yaw);
    destination.body_aim_pose.position = positions[hand];
    destination.body_grip_pose.position = positions[hand];
    destination.body_aim_pose.orientation = wrist_orientation;
    destination.body_grip_pose.orientation = wrist_orientation;
    if (phase == SyntheticControllerPhase::tracking_invalid) {
      destination.body_aim_tracking_flags = 0;
      destination.body_grip_tracking_flags = 0;
    } else {
      destination.body_aim_tracking_flags = destination.aim_tracking_flags;
      destination.body_grip_tracking_flags = destination.grip_tracking_flags;
    }
  }
}

}  // namespace darktidevr::harness
