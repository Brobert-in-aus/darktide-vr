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
  using darktidevr::harness::kSyntheticHeadPhaseFrames;
  using darktidevr::harness::synthetic_head_path_sample;
  using darktidevr::harness::synthetic_neck_pivot_path_sample;
  using darktidevr::harness::synthetic_crouch_position;
  using darktidevr::harness::synthetic_roomscale_position;
  using darktidevr::math::rotate;

  const darktidevr::math::Vec3 translation{0.1F, -0.2F, 0.3F};
  constexpr auto quarter_phase = kSyntheticHeadPhaseFrames / 4;
  const auto neutral = synthetic_head_path_sample(quarter_phase, translation);
  expect(neutral.phase == SyntheticHeadPhase::neutral,
         "First phase must remain neutral");
  expect(neutral.delta.position.x == translation.x &&
             neutral.delta.position.y == translation.y &&
             neutral.delta.position.z == translation.z,
         "Synthetic orientation must preserve translation");

  const auto pitch = synthetic_head_path_sample(
      kSyntheticHeadPhaseFrames + quarter_phase, translation);
  const auto pitched_forward =
      rotate(pitch.delta.orientation, {0.0F, 0.0F, -1.0F});
  expect(pitch.phase == SyntheticHeadPhase::pitch &&
             std::abs(pitched_forward.y) > 0.2F,
         "Pitch phase must move the forward vector vertically");

  const auto roll = synthetic_head_path_sample(
      kSyntheticHeadPhaseFrames * 2 + quarter_phase, translation);
  const auto rolled_up = rotate(roll.delta.orientation, {0.0F, 1.0F, 0.0F});
  expect(roll.phase == SyntheticHeadPhase::roll &&
             std::abs(rolled_up.x) > 0.2F,
         "Roll phase must tilt the head up vector");

  const auto combined = synthetic_head_path_sample(
      kSyntheticHeadPhaseFrames * 3 + quarter_phase, translation);
  const auto combined_forward =
      rotate(combined.delta.orientation, {0.0F, 0.0F, -1.0F});
  const auto combined_up =
      rotate(combined.delta.orientation, {0.0F, 1.0F, 0.0F});
  expect(combined.phase == SyntheticHeadPhase::combined &&
             std::abs(combined_forward.y) > 0.2F &&
             std::abs(combined_up.x) > 0.2F,
         "Combined phase must contain both pitch and roll");

  const auto pivot = synthetic_neck_pivot_path_sample(90, translation);
  expect(std::abs(rotate(pivot.orientation, {0.0F, 0.0F, -1.0F}).y) >
             0.6F,
         "Neck-pivot path must reach approximately 45 degrees");
  const darktidevr::math::Vec3 neck_to_hmd{0.0F, 0.075F, -0.0805F};
  const auto estimated_neck = darktidevr::math::Vec3{
      pivot.position.x - rotate(pivot.orientation, neck_to_hmd).x,
      pivot.position.y - rotate(pivot.orientation, neck_to_hmd).y,
      pivot.position.z - rotate(pivot.orientation, neck_to_hmd).z};
  expect(std::abs(estimated_neck.x - (translation.x - neck_to_hmd.x)) <
             0.0001F &&
             std::abs(estimated_neck.y - (translation.y - neck_to_hmd.y)) <
                 0.0001F &&
             std::abs(estimated_neck.z - (translation.z - neck_to_hmd.z)) <
                 0.0001F,
         "Neck-pivot synthetic path must keep the anatomical neck fixed");

  const auto roomscale_neutral = synthetic_roomscale_position(30);
  const auto roomscale_x = synthetic_roomscale_position(150);
  const auto roomscale_z = synthetic_roomscale_position(270);
  const auto roomscale_combined = synthetic_roomscale_position(360);
  expect(roomscale_neutral.x == 0.0F && roomscale_neutral.z == 0.0F,
         "Room-scale path must begin with a neutral phase");
  expect(std::abs(roomscale_x.x) > 0.6F && roomscale_x.y == 0.0F,
         "Room-scale X phase must cross the camera envelope");
  expect(std::abs(roomscale_z.z) > 0.6F && roomscale_z.y == 0.0F,
         "Room-scale Z phase must cross the camera envelope");
  expect(std::abs(roomscale_combined.z) > 0.6F,
         "Room-scale combined phase must cross the camera envelope");

  const auto crouch_standing = synthetic_crouch_position(0);
  const auto crouch_low = synthetic_crouch_position(120);
  const auto crouch_return = synthetic_crouch_position(239);
  expect(crouch_standing.x == 0.0F && crouch_standing.y == 0.0F &&
             crouch_standing.z == 0.0F,
         "Crouch path must start at standing height");
  expect(crouch_low.y < -0.64F && crouch_low.x == 0.0F &&
             crouch_low.z == 0.0F,
         "Crouch path must reach the requested vertical depth only");
  expect(std::abs(crouch_return.y) < 0.0001F,
         "Crouch path must return to standing height");

  std::cout << "synthetic_head_path.result=pass\n";
  return 0;
}
