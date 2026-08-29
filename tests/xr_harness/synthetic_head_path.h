#pragma once

#include "core/xr_math.h"

#include <cstdint>

namespace darktidevr::harness {

enum class SyntheticHeadPhase {
  neutral,
  pitch,
  roll,
  combined,
};

// Keep each orientation long enough for unattended capture and visual
// comparison. At a 120 Hz runtime this is three seconds per phase.
inline constexpr std::uint64_t kSyntheticHeadPhaseFrames = 360;

struct SyntheticHeadPathSample {
  math::Pose delta{};
  SyntheticHeadPhase phase{};
};

// Deterministic test-only orientation sweep. Translation is preserved so the
// path can replace only the physical headset orientation in an otherwise live
// OpenXR sample.
SyntheticHeadPathSample synthetic_head_path_sample(
    std::uint64_t frame, math::Vec3 preserved_translation);

// Deterministic test-only room-scale path. The 0.65 m excursions deliberately
// cross the production 0.25 m camera-lean envelope so unattended tests can
// verify that excess horizontal motion is exported as body-follow movement.
math::Vec3 synthetic_roomscale_position(std::uint64_t frame);

// Deterministic test-only standing-to-crouch path. OpenXR +Y is up, so the
// negative excursion represents a physical crouch while X/Z remain neutral.
// The 0.65 m depth exercises the full presentation-IK range without moving
// the character capsule.
math::Vec3 synthetic_crouch_position(std::uint64_t frame);

}  // namespace darktidevr::harness
