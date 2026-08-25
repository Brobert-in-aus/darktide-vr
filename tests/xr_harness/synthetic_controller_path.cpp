#include "synthetic_controller_path.h"

#include <stdexcept>

namespace darktidevr::harness {

SyntheticControllerPathSample synthetic_controller_path_sample(
    std::uint64_t frame, std::uint64_t sequence, std::uint64_t timestamp_ns,
    math::Pose panel_pose, float panel_width_metres,
    float panel_height_metres) {
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
  return sample;
}

}  // namespace darktidevr::harness
