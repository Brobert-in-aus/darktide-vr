#include "synthetic_controller_path.h"

#include <algorithm>
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
      // Continue holding secondary from right_sweep, then press primary.
      // This gives unattended Psyker validation a deterministic charged/ADS
      // staff shot instead of testing the two inputs in isolation.
      sample.state.hands[0].trigger = 1.0F;
      sample.state.hands[1].trigger = 1.0F;
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
    positions[0].y = 0.25F + phase_t * 0.90F;
  } else if (phase == SyntheticControllerPhase::right_sweep) {
    positions[1].x = sweep;
    positions[1].y = 0.25F + phase_t * 0.90F;
  } else if (phase == SyntheticControllerPhase::crossed_sweep) {
    positions[0].x = 0.25F;
    positions[1].x = -0.25F;
    // Equal forward reach must keep the shoulder girdle square. This phase
    // simultaneously retains the full wrist-roll and crossed-arm coverage.
    positions[0].y = 0.25F + phase_t * 0.70F;
    positions[1].y = positions[0].y;
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
    const auto yaw_orientation =
        math::from_axis_angle({0.0F, 0.0F, 1.0F}, wrist_yaw);
    // Crossed reach also performs a complete pronation/supination sweep. The
    // local +Y axis is Darktide forward, so this changes controller roll while
    // keeping the requested pointing direction stable. It exists specifically
    // to exercise the forearm's otherwise-underdetermined axial degree of
    // freedom and both upside-down endpoints.
    const auto wrist_roll =
        phase == SyntheticControllerPhase::crossed_sweep
            ? (phase_t * 2.0F - 1.0F) * 3.14159265359F
            : 0.0F;
    const auto wrist_orientation = math::multiply(
        yaw_orientation,
        math::from_axis_angle({0.0F, 1.0F, 0.0F}, wrist_roll));
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

void apply_synthetic_weapon_aim_matrix(core::SharedControllerState& state,
                                       std::uint64_t frame) {
  constexpr std::uint64_t cycle_frames = 720;
  const auto cycle_frame = frame % cycle_frames;
  for (auto& hand : state.hands) {
    hand.trigger = 0.0F;
    hand.squeeze = 0.0F;
    hand.thumbstick_x = 0.0F;
    hand.thumbstick_y = 0.0F;
    hand.buttons = 0;
  }

  // Begin from the range's default melee slot and switch to the force staff.
  // Leave one second for the run-scoped Lua input adapter to observe its flag
  // after stereo-world presentation begins; an edge on frame zero can precede
  // that polling boundary and be correctly ignored by production input gates.
  if (cycle_frame >= 60 && cycle_frame < 66) {
    state.hands[0].buttons = core::controller_secondary;
  // Normal staff projectile: right trigger, right-hand aim direction.
  } else if (cycle_frame >= 150 && cycle_frame < 180) {
    state.hands[1].trigger = 1.0F;
  // Hold alternate fire, then press primary while it remains held. This is
  // Darktide's charged/ADS-equivalent staff projectile sequence.
  } else if (cycle_frame >= 240 && cycle_frame < 360) {
    state.hands[0].trigger = 1.0F;
    if (cycle_frame >= 300 && cycle_frame < 330) {
      state.hands[1].trigger = 1.0F;
    }
  // Psyker grenade-ability input owns chain lightning on this test profile.
  } else if (cycle_frame >= 420 && cycle_frame < 540) {
    state.hands[0].squeeze = 1.0F;
    if (cycle_frame >= 480 && cycle_frame < 510) {
      state.hands[1].trigger = 1.0F;
    }
  // Return from staff to sword, then exercise its normal primary attack.
  } else if (cycle_frame >= 600 && cycle_frame < 606) {
    state.hands[0].buttons = core::controller_secondary;
  } else if (cycle_frame >= 660 && cycle_frame < 690) {
    state.hands[1].trigger = 1.0F;
  }
}

void apply_synthetic_movement_reference_path(
    core::SharedControllerState& state, std::uint64_t frame) {
  // 150 harness frames deliberately does not alias the game's 60-fixed-frame
  // (roughly two-second) locomotion diagnostic cadence.
  constexpr std::uint64_t phase_frames = 150;
  const auto phase = (frame / phase_frames) % 4;
  for (auto& hand : state.hands) {
    hand.trigger = 0.0F;
    hand.squeeze = 0.0F;
    hand.thumbstick_x = 0.0F;
    hand.thumbstick_y = 0.0F;
    hand.buttons = 0;
  }
  state.hands[0].thumbstick_y = 1.0F;
  const auto yaw = phase == 1 ? 1.57079632679F
                   : phase == 2 ? -1.57079632679F
                                : 0.0F;
  const auto yaw_rotation =
      // Synthetic controller poses cross the shared-state seam in Darktide's
      // body basis, whose vertical axis is +Z.
      math::from_axis_angle({0.0F, 0.0F, 1.0F}, yaw);
  state.hands[0].aim_pose.orientation = math::multiply(
      yaw_rotation, state.hands[0].aim_pose.orientation);
  // Lua consumes body_aim_pose. The generic sample has already populated it
  // before this matrix runs, so rotate both representations in lockstep.
  state.hands[0].body_aim_pose.orientation = math::multiply(
      yaw_rotation, state.hands[0].body_aim_pose.orientation);
  if (phase == 3) {
    state.hands[0].aim_tracking_flags = 0;
    state.hands[0].body_aim_tracking_flags = 0;
  }
}

void apply_synthetic_holster_path(core::SharedControllerState& state,
                                  std::uint64_t frame, bool once) {
  constexpr std::uint64_t zone_frames = 120;
  // Body-local zone centres (+X right, +Y forward, +Z up from the head), the
  // same numbers as Holsters.ZONES at the reference eye height.
  static constexpr std::array<math::Vec3, 6> zones{{
      {0.16F, -0.14F, -0.10F},
      {-0.20F, 0.00F, -0.72F},
      {-0.13F, 0.16F, -0.38F},
      {0.20F, 0.00F, -0.72F},
      {0.13F, 0.16F, -0.38F},
      {0.00F, 0.14F, -0.60F},
  }};
  constexpr std::size_t belt_zone = 5;
  const bool resting = once && frame >= zone_frames;
  const auto cycle = resting ? zone_frames - 1 : frame % (zone_frames * zones.size());
  const auto zone = static_cast<std::size_t>(cycle / zone_frames);
  const auto step = cycle % zone_frames;
  for (auto& hand : state.hands) {
    hand.trigger = 0.0F;
    hand.squeeze = 0.0F;
    hand.thumbstick_x = 0.0F;
    hand.thumbstick_y = 0.0F;
    hand.buttons = 0;
  }
  const std::array<math::Vec3, 2> neutral{{
      {-0.25F, 0.25F, -0.25F},
      {0.25F, 0.25F, -0.25F},
  }};
  // Tracked throughout: the generic sample's tracking-loss phase would
  // otherwise interrupt a zone visit.
  const auto tracked = core::controller_orientation_valid |
                       core::controller_position_valid |
                       core::controller_orientation_tracked |
                       core::controller_position_tracked;
  for (std::size_t hand = 0; hand < 2; ++hand) {
    auto& destination = state.hands[hand];
    destination.aim_tracking_flags = tracked;
    destination.grip_tracking_flags = tracked;
    auto position = neutral[hand];
    if (resting && hand == 1) {
      // Hold the drawn gun further out and lower, where it frames well in
      // an eye capture.
      position = {0.12F, 0.42F, -0.30F};
    }
    if (hand == 1 && step < 90 && !resting) {
      position = zones[zone];
    }
    destination.body_aim_pose.position = position;
    destination.body_grip_pose.position = position;
    destination.body_aim_pose.orientation = {0.0F, 0.0F, 0.0F, 1.0F};
    destination.body_grip_pose.orientation = {0.0F, 0.0F, 0.0F, 1.0F};
    destination.body_aim_tracking_flags = destination.aim_tracking_flags;
    destination.body_grip_tracking_flags = destination.grip_tracking_flags;
  }
  // The belt's blitz is held for a second, past the hand leaving the zone at
  // frame 90, so the draw, aim and release (throw) all happen.
  const auto squeeze_end = zone == belt_zone ? 105U : 60U;
  // Two-hand check (once mode): from 2 s after the draw, every 4 s the left
  // hand moves to the galvanic rifle's measured authored foregrip (3.4 cm
  // left, 32.9 cm forward of the right grip, gun pitched down 10 degrees)
  // and squeezes its grip for 2 s. Half a second into the hold the hand
  // rises 5 cm over a quarter second and stays there for a second, so the
  // support hand has something to steer.
  if (resting && frame >= zone_frames * 3) {
    const auto phase = (frame - zone_frames * 3) % 480;
    if (phase < 240) {
      const float pitch = -0.1745F;
      const math::Vec3 grip = state.hands[1].body_grip_pose.position;
      float lift = 0.0F;
      if (phase >= 90 && phase < 180) {
        lift = 0.05F * std::min(1.0F, static_cast<float>(phase - 90) / 30.0F);
      }
      const math::Vec3 foregrip{grip.x - 0.034F, grip.y + 0.329F * std::cos(pitch),
                                grip.z + 0.329F * std::sin(pitch) + lift};
      state.hands[0].body_aim_pose.position = foregrip;
      state.hands[0].body_grip_pose.position = foregrip;
      if (phase >= 30 && phase < 210) {
        state.hands[0].squeeze = 1.0F;
      }
    }
  }
  if (!resting && step >= 45 && step < squeeze_end) {
    state.hands[1].squeeze = 1.0F;
  }
}

}  // namespace darktidevr::harness
