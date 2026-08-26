#include "core/two_bone_ik.h"

#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>

namespace {

float distance(darktidevr::math::Vec3 left, darktidevr::math::Vec3 right) {
  const auto x = left.x - right.x;
  const auto y = left.y - right.y;
  const auto z = left.z - right.z;
  return std::sqrt(x * x + y * y + z * z);
}

void expect(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

void expect_near(float actual, float expected, float tolerance,
                 const char* message) {
  expect(std::abs(actual - expected) <= tolerance, message);
}

}  // namespace

int main() {
  using darktidevr::core::TwoBoneIkInput;
  using darktidevr::core::solve_two_bone_ik;

  TwoBoneIkInput input{};
  input.shoulder = {0.0F, 0.0F, 1.5F};
  input.wrist_target = {0.45F, 0.35F, 1.25F};
  input.pole_target = {0.25F, 0.1F, 0.8F};
  input.upper_length = 0.36F;
  input.lower_length = 0.34F;
  const auto nominal = solve_two_bone_ik(input);
  expect(nominal.valid && !nominal.clamped_near && !nominal.clamped_far,
         "Nominal arm target must solve without clamping");
  expect_near(distance(input.shoulder, nominal.elbow), input.upper_length,
              1.0e-4F, "Upper-arm length must be preserved");
  expect_near(distance(nominal.elbow, nominal.wrist), input.lower_length,
              1.0e-4F, "Lower-arm length must be preserved");
  expect_near(distance(nominal.wrist, input.wrist_target), 0.0F, 1.0e-4F,
              "Reachable wrist must meet its target");

  input.wrist_target = {2.0F, 0.0F, 1.5F};
  const auto far = solve_two_bone_ik(input);
  expect(far.valid && far.clamped_far && !far.clamped_near,
         "Over-reach must clamp at full extension");
  expect(far.solved_distance < input.upper_length + input.lower_length,
         "Far clamp must stay inside the singular full-extension limit");
  expect_near(distance(input.shoulder, far.elbow), input.upper_length,
              1.0e-4F, "Far-clamped upper arm must preserve length");

  input.upper_length = 0.5F;
  input.lower_length = 0.25F;
  input.wrist_target = input.shoulder;
  input.fallback_direction = {0.0F, 1.0F, 0.0F};
  input.pole_target = {0.0F, 5.0F, 1.5F};
  input.fallback_bend_direction = {0.0F, 0.0F, -1.0F};
  const auto near = solve_two_bone_ik(input);
  expect(near.valid && near.clamped_near && near.used_direction_fallback &&
             near.used_bend_fallback,
         "Collapsed target and axial pole must use stable fallbacks");
  expect(near.wrist.y > input.shoulder.y,
         "Direction fallback must determine collapsed-target reach");
  expect(near.elbow.z < input.shoulder.z,
         "Bend fallback must keep the elbow on its prior side");

  input.wrist_target = {0.0F, 0.4F, 1.5F};
  input.pole_target = {0.0F, 4.0F, 1.5F};
  const auto axial_a = solve_two_bone_ik(input);
  input.pole_target = {1.0e-7F, 4.0F, 1.5F};
  const auto axial_b = solve_two_bone_ik(input);
  expect(axial_a.valid && axial_b.valid && axial_a.used_bend_fallback &&
             axial_b.used_bend_fallback && axial_a.elbow.z < input.shoulder.z &&
             axial_b.elbow.z < input.shoulder.z,
         "Near-axial poles must not flip the elbow across frames");

  input.upper_length = std::numeric_limits<float>::quiet_NaN();
  expect(!solve_two_bone_ik(input).valid,
         "Non-finite limb lengths must fail closed");

  std::cout << "two_bone_ik.result=pass\n";
  return 0;
}
