#pragma once

#include "core/panel_pointer.h"
#include "core/shared_controller_state.h"

#include <array>
#include <cstdint>

namespace darktidevr::harness {

enum class SyntheticControllerPhase {
  left_sweep,
  right_sweep,
  crossed_sweep,
  outside_panel,
  beyond_reach,
  tracking_invalid,
};

struct SyntheticControllerPathSample {
  core::SharedControllerState state{};
  std::array<core::PointerRay, 2> rays{};
  SyntheticControllerPhase phase{};
};

SyntheticControllerPathSample synthetic_controller_path_sample(
    std::uint64_t frame, std::uint64_t sequence, std::uint64_t timestamp_ns,
    math::Pose panel_pose, float panel_width_metres,
    float panel_height_metres, bool emit_gameplay_input = false);

// Replaces only the recenter-relative, Darktide-basis poses with a repeatable
// arm-scale trajectory. Absolute poses and pointer rays remain suitable for
// the spatial-panel tests above.
void apply_synthetic_body_reach_path(core::SharedControllerState& state,
                                     std::uint64_t frame);

// Replaces only gameplay controls with a repeatable private-range matrix:
// staff wield, primary projectile, charged/ADS projectile, Psyker lightning,
// sword wield and melee primary. Tracking poses remain unchanged.
void apply_synthetic_weapon_aim_matrix(core::SharedControllerState& state,
                                       std::uint64_t frame);

// Holds forward locomotion while yawing only the left aim pose through aligned,
// right, left and tracking-invalid phases. This isolates locomotion-reference
// selection from body IK and weapon-aim controls.
void apply_synthetic_movement_reference_path(
    core::SharedControllerState& state, std::uint64_t frame);

// Virtual holster reach: the right hand visits each holster zone centre of
// darktidevr_holsters.lua (right shoulder, left hip, left chest, right hip,
// right chest) for 90 of 120 frames and squeezes its grip for frames 45-59;
// the left hand rests at the neutral reach pose. Other controls are neutral.
void apply_synthetic_holster_path(core::SharedControllerState& state,
                                  std::uint64_t frame);

}  // namespace darktidevr::harness
