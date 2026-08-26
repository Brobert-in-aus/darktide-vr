#include "synthetic_head_path.h"

#include <cmath>
#include <iostream>
#include <stdexcept>

namespace {

void expect(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

}  // namespace

int main() {
  using darktidevr::harness::SyntheticHeadPhase;
  using darktidevr::harness::synthetic_head_path_sample;
  using darktidevr::math::rotate;

  const darktidevr::math::Vec3 translation{0.1F, -0.2F, 0.3F};
  const auto neutral = synthetic_head_path_sample(30, translation);
  expect(neutral.phase == SyntheticHeadPhase::neutral,
         "First phase must remain neutral");
  expect(neutral.delta.position.x == translation.x &&
             neutral.delta.position.y == translation.y &&
             neutral.delta.position.z == translation.z,
         "Synthetic orientation must preserve translation");

  const auto pitch = synthetic_head_path_sample(150, translation);
  const auto pitched_forward =
      rotate(pitch.delta.orientation, {0.0F, 0.0F, -1.0F});
  expect(pitch.phase == SyntheticHeadPhase::pitch &&
             std::abs(pitched_forward.y) > 0.2F,
         "Pitch phase must move the forward vector vertically");

  const auto roll = synthetic_head_path_sample(270, translation);
  const auto rolled_up = rotate(roll.delta.orientation, {0.0F, 1.0F, 0.0F});
  expect(roll.phase == SyntheticHeadPhase::roll &&
             std::abs(rolled_up.x) > 0.2F,
         "Roll phase must tilt the head up vector");

  const auto combined = synthetic_head_path_sample(390, translation);
  const auto combined_forward =
      rotate(combined.delta.orientation, {0.0F, 0.0F, -1.0F});
  const auto combined_up =
      rotate(combined.delta.orientation, {0.0F, 1.0F, 0.0F});
  expect(combined.phase == SyntheticHeadPhase::combined &&
             std::abs(combined_forward.y) > 0.2F &&
             std::abs(combined_up.x) > 0.2F,
         "Combined phase must contain both pitch and roll");

  std::cout << "synthetic_head_path.result=pass\n";
  return 0;
}
