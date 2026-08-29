#include "synthetic_head_path.h"

#include <cmath>

namespace darktidevr::harness {

SyntheticHeadPathSample synthetic_head_path_sample(
    std::uint64_t frame, math::Vec3 preserved_translation) {
  constexpr auto phase_frames = kSyntheticHeadPhaseFrames;
  constexpr float pi = 3.14159265358979323846F;
  const auto cycle_frame = frame % (phase_frames * 4);
  const auto phase_index = cycle_frame / phase_frames;
  const auto phase_t = static_cast<float>(cycle_frame % phase_frames) /
                       static_cast<float>(phase_frames - 1);
  const auto sine = std::sin(phase_t * 2.0F * pi);
  const auto pitch = sine * 35.0F * pi / 180.0F;
  const auto roll = sine * 30.0F * pi / 180.0F;

  SyntheticHeadPathSample sample{};
  sample.delta.position = preserved_translation;
  sample.phase = static_cast<SyntheticHeadPhase>(phase_index);
  if (sample.phase == SyntheticHeadPhase::pitch) {
    sample.delta.orientation =
        math::from_axis_angle({1.0F, 0.0F, 0.0F}, pitch);
  } else if (sample.phase == SyntheticHeadPhase::roll) {
    sample.delta.orientation =
        math::from_axis_angle({0.0F, 0.0F, 1.0F}, roll);
  } else if (sample.phase == SyntheticHeadPhase::combined) {
    sample.delta.orientation = math::multiply(
        math::from_axis_angle({0.0F, 0.0F, 1.0F}, roll),
        math::from_axis_angle({1.0F, 0.0F, 0.0F}, pitch));
  }
  return sample;
}

math::Vec3 synthetic_roomscale_position(std::uint64_t frame) {
  constexpr std::uint64_t phase_frames = 120;
  constexpr float pi = 3.14159265358979323846F;
  constexpr float excursion_metres = 0.65F;
  const auto cycle_frame = frame % (phase_frames * 4);
  const auto phase = cycle_frame / phase_frames;
  const auto phase_t = static_cast<float>(cycle_frame % phase_frames) /
                       static_cast<float>(phase_frames - 1);
  const auto sine = std::sin(phase_t * 2.0F * pi);
  if (phase == 1) {
    return {excursion_metres * sine, 0.0F, 0.0F};
  }
  if (phase == 2) {
    return {0.0F, 0.0F, excursion_metres * sine};
  }
  if (phase == 3) {
    return {excursion_metres * sine, 0.0F,
            excursion_metres * std::cos(phase_t * 2.0F * pi)};
  }
  return {};
}

math::Vec3 synthetic_crouch_position(std::uint64_t frame) {
  constexpr std::uint64_t phase_frames = 240;
  constexpr float pi = 3.14159265358979323846F;
  constexpr float crouch_metres = 0.65F;
  const auto phase_t = static_cast<float>(frame % phase_frames) /
                       static_cast<float>(phase_frames - 1);
  // Starts and ends standing, reaches the full crouch at mid-cycle, and has
  // zero velocity at both endpoints so captured frames are deterministic.
  const auto depth = 0.5F - 0.5F * std::cos(phase_t * 2.0F * pi);
  return {0.0F, -crouch_metres * depth, 0.0F};
}

}  // namespace darktidevr::harness
