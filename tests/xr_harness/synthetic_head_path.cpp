#include "synthetic_head_path.h"

#include <cmath>

namespace darktidevr::harness {

SyntheticHeadPathSample synthetic_head_path_sample(
    std::uint64_t frame, math::Vec3 preserved_translation) {
  constexpr std::uint64_t phase_frames = 120;
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

}  // namespace darktidevr::harness
