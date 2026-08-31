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

math::Pose synthetic_body_inspection_pose(math::Vec3 preserved_translation) {
  constexpr float pi = 3.14159265358979323846F;
  constexpr float pitch = -70.0F * pi / 180.0F;
  return {math::from_axis_angle({1.0F, 0.0F, 0.0F}, pitch),
          preserved_translation};
}

math::Pose synthetic_neck_pivot_path_sample(
    std::uint64_t frame, math::Vec3 preserved_translation) {
  constexpr std::uint64_t phase_frames = 360;
  constexpr float pi = 3.14159265358979323846F;
  constexpr math::Vec3 neck_to_hmd{0.0F, 0.075F, -0.0805F};
  const auto phase_t = static_cast<float>(frame % phase_frames) /
                       static_cast<float>(phase_frames - 1);
  const auto pitch = std::sin(phase_t * 2.0F * pi) * pi * 0.25F;
  const auto orientation =
      math::from_axis_angle({1.0F, 0.0F, 0.0F}, pitch);
  const auto rotated_offset = math::rotate(orientation, neck_to_hmd);
  return {orientation,
          {preserved_translation.x + rotated_offset.x - neck_to_hmd.x,
           preserved_translation.y + rotated_offset.y - neck_to_hmd.y,
           preserved_translation.z + rotated_offset.z - neck_to_hmd.z}};
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
