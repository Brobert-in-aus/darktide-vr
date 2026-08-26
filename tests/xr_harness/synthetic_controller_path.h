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

}  // namespace darktidevr::harness
