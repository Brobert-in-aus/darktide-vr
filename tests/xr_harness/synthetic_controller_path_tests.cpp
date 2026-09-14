#include "synthetic_controller_path.h"

#include <cmath>
#include <iostream>
#include <optional>

namespace {

bool hits_panel(const darktidevr::harness::SyntheticControllerPathSample& sample,
                std::size_t hand, darktidevr::math::Pose panel_pose) {
  return darktidevr::core::map_pointer_to_panel(
             sample.rays[hand], panel_pose, 2.0F, 2.0F, 1000, 1000, 0, 0,
             1000, 1000)
      .has_value();
}

float length(darktidevr::math::Vec3 value) {
  return std::sqrt(value.x * value.x + value.y * value.y +
                   value.z * value.z);
}

}  // namespace

int main() {
  const darktidevr::math::Pose panel{{0.0F, 0.0F, 0.0F, 1.0F},
                                     {0.0F, 0.0F, -2.0F}};
  const auto left = darktidevr::harness::synthetic_controller_path_sample(
      29, 1, 1, panel, 2.0F, 2.0F);
  const auto right = darktidevr::harness::synthetic_controller_path_sample(
      89, 2, 2, panel, 2.0F, 2.0F);
  const auto outside = darktidevr::harness::synthetic_controller_path_sample(
      180, 3, 3, panel, 2.0F, 2.0F);
  const auto far = darktidevr::harness::synthetic_controller_path_sample(
      240, 4, 4, panel, 2.0F, 2.0F);
  const auto invalid = darktidevr::harness::synthetic_controller_path_sample(
      300, 5, 5, panel, 2.0F, 2.0F);
  const auto reacquired =
      darktidevr::harness::synthetic_controller_path_sample(
          360, 6, 6, panel, 2.0F, 2.0F);
  const auto attack = darktidevr::harness::synthetic_controller_path_sample(
      0, 7, 7, panel, 2.0F, 2.0F, true);
  const auto move_right =
      darktidevr::harness::synthetic_controller_path_sample(
          60, 10, 10, panel, 2.0F, 2.0F, true);
  const auto move_backward =
      darktidevr::harness::synthetic_controller_path_sample(
          120, 11, 11, panel, 2.0F, 2.0F, true);
  const auto face_buttons =
      darktidevr::harness::synthetic_controller_path_sample(
          180, 8, 8, panel, 2.0F, 2.0F, true);
  const auto utility = darktidevr::harness::synthetic_controller_path_sample(
      240, 9, 9, panel, 2.0F, 2.0F, true);
  auto body_near = left.state;
  auto body_left_reach = left.state;
  auto body_right_reach = right.state;
  auto body_crossed = outside.state;
  auto body_crossed_mid = outside.state;
  auto body_crossed_end = outside.state;
  auto body_far = far.state;
  auto body_invalid = invalid.state;
  auto matrix_staff_wield = left.state;
  auto matrix_staff_primary = left.state;
  auto matrix_staff_charge = left.state;
  auto matrix_staff_fire = left.state;
  auto matrix_lightning = left.state;
  auto matrix_sword_wield = left.state;
  auto matrix_sword_attack = left.state;
  auto movement_aligned = left.state;
  auto movement_right = left.state;
  auto movement_left = left.state;
  auto movement_invalid = left.state;
  darktidevr::harness::apply_synthetic_body_reach_path(body_near, 5);
  darktidevr::harness::apply_synthetic_body_reach_path(body_left_reach, 59);
  darktidevr::harness::apply_synthetic_body_reach_path(body_right_reach, 119);
  darktidevr::harness::apply_synthetic_body_reach_path(body_crossed, 120);
  darktidevr::harness::apply_synthetic_body_reach_path(body_crossed_mid, 149);
  darktidevr::harness::apply_synthetic_body_reach_path(body_crossed_end, 179);
  darktidevr::harness::apply_synthetic_body_reach_path(body_far, 240);
  darktidevr::harness::apply_synthetic_body_reach_path(body_invalid, 300);
  darktidevr::harness::apply_synthetic_weapon_aim_matrix(
      matrix_staff_wield, 60);
  darktidevr::harness::apply_synthetic_weapon_aim_matrix(
      matrix_staff_primary, 150);
  darktidevr::harness::apply_synthetic_weapon_aim_matrix(
      matrix_staff_charge, 240);
  darktidevr::harness::apply_synthetic_weapon_aim_matrix(
      matrix_staff_fire, 300);
  darktidevr::harness::apply_synthetic_weapon_aim_matrix(
      matrix_lightning, 480);
  darktidevr::harness::apply_synthetic_weapon_aim_matrix(
      matrix_sword_wield, 600);
  darktidevr::harness::apply_synthetic_weapon_aim_matrix(
      matrix_sword_attack, 660);
  darktidevr::harness::apply_synthetic_movement_reference_path(
      movement_aligned, 0);
  darktidevr::harness::apply_synthetic_movement_reference_path(
      movement_right, 150);
  darktidevr::harness::apply_synthetic_movement_reference_path(
      movement_left, 300);
  darktidevr::harness::apply_synthetic_movement_reference_path(
      movement_invalid, 450);

  const darktidevr::math::Vec3 head{0.0F, 0.0F, 0.0F};
  const bool valid =
      left.phase == darktidevr::harness::SyntheticControllerPhase::left_sweep &&
      hits_panel(left, 0, panel) &&
      right.phase == darktidevr::harness::SyntheticControllerPhase::right_sweep &&
      hits_panel(right, 1, panel) && !hits_panel(outside, 0, panel) &&
      !hits_panel(outside, 1, panel) && hits_panel(far, 0, panel) &&
      !darktidevr::core::pointer_origin_within_reach(
          far.state.hands[0].aim_pose.position, head, 1.5F) &&
      invalid.state.hands[0].aim_tracking_flags == 0 &&
      invalid.state.hands[1].aim_tracking_flags == 0 &&
      reacquired.state.hands[0].aim_tracking_flags != 0 &&
      left.state.hands[1].trigger == 0.0F &&
      attack.state.hands[1].trigger == 1.0F &&
      attack.state.hands[0].thumbstick_y == 1.0F &&
      move_right.state.hands[0].thumbstick_x == 1.0F &&
      move_backward.state.hands[0].trigger == 1.0F &&
      move_backward.state.hands[1].trigger == 1.0F &&
      move_backward.state.hands[0].thumbstick_y == -1.0F &&
      face_buttons.state.hands[0].thumbstick_x == -1.0F &&
      face_buttons.state.hands[0].buttons ==
          (darktidevr::core::controller_primary |
           darktidevr::core::controller_secondary) &&
      face_buttons.state.hands[1].buttons ==
          (darktidevr::core::controller_primary |
           darktidevr::core::controller_secondary) &&
      utility.state.hands[0].buttons ==
          (darktidevr::core::controller_stick_click |
           darktidevr::core::controller_menu) &&
      utility.state.hands[1].buttons ==
          darktidevr::core::controller_stick_click &&
      length(body_near.hands[0].body_grip_pose.position) < 0.60F &&
      body_near.hands[0].body_grip_tracking_flags != 0 &&
      body_left_reach.hands[0].body_grip_pose.position.y > 1.10F &&
      body_left_reach.hands[1].body_grip_pose.position.y < 0.30F &&
      body_right_reach.hands[1].body_grip_pose.position.y > 1.10F &&
      body_right_reach.hands[0].body_grip_pose.position.y < 0.30F &&
      body_crossed.hands[0].body_grip_pose.position.x > 0.0F &&
      body_crossed.hands[1].body_grip_pose.position.x < 0.0F &&
      std::abs(body_crossed_mid.hands[0].body_grip_pose.position.y -
               body_crossed_mid.hands[1].body_grip_pose.position.y) < 0.001F &&
      std::abs(body_crossed.hands[0].body_grip_pose.orientation.y) > 0.90F &&
      std::abs(body_crossed_mid.hands[0].body_grip_pose.orientation.y) < 0.05F &&
      std::abs(body_crossed_end.hands[0].body_grip_pose.orientation.y) > 0.90F &&
      std::abs(body_crossed.hands[1].body_grip_pose.orientation.y) > 0.90F &&
      std::abs(body_crossed_end.hands[1].body_grip_pose.orientation.y) > 0.90F &&
      length(body_far.hands[0].body_grip_pose.position) > 1.0F &&
      body_invalid.hands[0].body_grip_tracking_flags == 0 &&
      body_invalid.hands[1].body_grip_tracking_flags == 0 &&
      matrix_staff_wield.hands[0].buttons ==
          darktidevr::core::controller_secondary &&
      matrix_staff_primary.hands[1].trigger == 1.0F &&
      matrix_staff_primary.hands[0].trigger == 0.0F &&
      matrix_staff_charge.hands[0].trigger == 1.0F &&
      matrix_staff_charge.hands[1].trigger == 0.0F &&
      matrix_staff_fire.hands[0].trigger == 1.0F &&
      matrix_staff_fire.hands[1].trigger == 1.0F &&
      matrix_lightning.hands[0].squeeze == 1.0F &&
      matrix_lightning.hands[1].trigger == 1.0F &&
      matrix_sword_wield.hands[0].buttons ==
          darktidevr::core::controller_secondary &&
      matrix_sword_attack.hands[1].trigger == 1.0F &&
      matrix_sword_attack.hands[0].buttons == 0 &&
      movement_aligned.hands[0].thumbstick_y == 1.0F &&
      movement_right.hands[0].thumbstick_y == 1.0F &&
      movement_left.hands[0].thumbstick_y == 1.0F &&
      movement_invalid.hands[0].thumbstick_y == 1.0F &&
      movement_invalid.hands[0].aim_tracking_flags == 0 &&
      movement_invalid.hands[0].body_aim_tracking_flags == 0 &&
      std::abs(movement_right.hands[0].aim_pose.orientation.z -
               movement_left.hands[0].aim_pose.orientation.z) > 1.0F &&
      std::abs(movement_right.hands[0].body_aim_pose.orientation.z -
               movement_left.hands[0].body_aim_pose.orientation.z) > 1.0F &&
      reacquired.phase ==
          darktidevr::harness::SyntheticControllerPhase::left_sweep;
  if (!valid) {
    std::cerr << "Synthetic controller path contract failed\n";
    return 1;
  }
  // Holster reach: right hand at the zone, grip squeezed mid-visit, then away.
  auto holster_reach = left.state;
  auto holster_squeeze = left.state;
  auto holster_away = left.state;
  auto holster_second = left.state;
  darktidevr::harness::apply_synthetic_holster_path(holster_reach, 10);
  darktidevr::harness::apply_synthetic_holster_path(holster_squeeze, 50);
  darktidevr::harness::apply_synthetic_holster_path(holster_away, 100);
  darktidevr::harness::apply_synthetic_holster_path(holster_second, 170);
  const bool holster_valid =
      std::abs(holster_reach.hands[1].body_grip_pose.position.x - 0.16F) < 0.001F &&
      std::abs(holster_reach.hands[1].body_grip_pose.position.z + 0.10F) < 0.001F &&
      holster_reach.hands[1].squeeze == 0.0F &&
      holster_squeeze.hands[1].squeeze == 1.0F &&
      holster_squeeze.hands[0].squeeze == 0.0F && holster_squeeze.hands[1].trigger == 0.0F &&
      holster_away.hands[1].squeeze == 0.0F &&
      std::abs(holster_away.hands[1].body_grip_pose.position.y - 0.25F) < 0.001F &&
      std::abs(holster_second.hands[1].body_grip_pose.position.z + 0.72F) < 0.001F &&
      holster_second.hands[1].body_grip_pose.position.x < 0.0F &&
      holster_squeeze.hands[1].body_grip_tracking_flags != 0 &&
      [&] {
        auto belt_hold = left.state;
        auto belt_after_zone = left.state;
        auto belt_released = left.state;
        darktidevr::harness::apply_synthetic_holster_path(belt_hold, 600 + 50);
        darktidevr::harness::apply_synthetic_holster_path(belt_after_zone, 600 + 95);
        darktidevr::harness::apply_synthetic_holster_path(belt_released, 600 + 110);
        return std::abs(belt_hold.hands[1].body_grip_pose.position.z + 0.60F) < 0.001F &&
               belt_hold.hands[1].squeeze == 1.0F &&
               belt_after_zone.hands[1].squeeze == 1.0F &&
               std::abs(belt_after_zone.hands[1].body_grip_pose.position.y - 0.25F) < 0.001F &&
               belt_released.hands[1].squeeze == 0.0F;
      }() &&
      [&] {
        // Once mode: support grip at the foregrip, lifted mid-hold, released.
        auto grip = left.state;
        auto lifted = left.state;
        auto released = left.state;
        auto arriving = left.state;
        darktidevr::harness::apply_synthetic_holster_path(arriving, 360, true);
        darktidevr::harness::apply_synthetic_holster_path(grip, 360 + 60, true);
        darktidevr::harness::apply_synthetic_holster_path(lifted, 360 + 150, true);
        darktidevr::harness::apply_synthetic_holster_path(released, 360 + 300, true);
        auto spread = left.state;
        auto firing = left.state;
        auto between = left.state;
        auto reloading = left.state;
        darktidevr::harness::apply_synthetic_holster_path(firing, 360 + 252, true);
        darktidevr::harness::apply_synthetic_holster_path(between, 360 + 257, true);
        darktidevr::harness::apply_synthetic_holster_path(reloading, 360 + 474, true);
        auto ability = left.state;
        auto melee_draw = left.state;
        auto melee_windup = left.state;
        auto ranged_draw = left.state;
        darktidevr::harness::apply_synthetic_holster_path(melee_draw, 360 + 480 + 50, true);
        darktidevr::harness::apply_synthetic_holster_path(melee_windup, 360 + 480 + 150, true);
        darktidevr::harness::apply_synthetic_holster_path(ranged_draw, 360 + 480 + 350, true);
        darktidevr::harness::apply_synthetic_holster_path(ability, 360 + 442, true);
        darktidevr::harness::apply_synthetic_holster_path(spread, 360 + 205, true);
        const float rise = lifted.hands[0].body_grip_pose.position.z -
                           grip.hands[0].body_grip_pose.position.z;
        const auto& a = arriving.hands[0].body_grip_pose.position;
        const auto& g = grip.hands[0].body_grip_pose.position;
        const float approach = std::sqrt((a.x - g.x) * (a.x - g.x) + (a.y - g.y) * (a.y - g.y) +
                                         (a.z - g.z) * (a.z - g.z));
        return approach > 0.15F && arriving.hands[0].squeeze == 0.0F &&
               firing.hands[1].trigger == 1.0F && between.hands[1].trigger == 0.0F &&
               ability.hands[0].squeeze == 1.0F &&
               melee_draw.hands[1].squeeze == 1.0F &&
               std::abs(melee_draw.hands[1].body_grip_pose.position.z + 0.72F) < 0.001F &&
               melee_windup.hands[1].trigger == 1.0F && melee_windup.hands[0].squeeze == 0.0F &&
               ranged_draw.hands[1].squeeze == 1.0F &&
               std::abs(ranged_draw.hands[1].body_grip_pose.position.x - 0.16F) < 0.001F &&
               firing.hands[0].squeeze == 0.0F && reloading.hands[1].thumbstick_y == -1.0F &&
               grip.hands[1].trigger == 0.0F &&
               spread.hands[0].squeeze == 1.0F &&
               std::abs(spread.hands[0].body_grip_pose.position.y - g.y - 0.25F) < 0.001F &&
               grip.hands[0].squeeze == 1.0F && lifted.hands[0].squeeze == 1.0F &&
               released.hands[0].squeeze == 0.0F && std::abs(rise - 0.05F) < 0.001F &&
               std::abs(grip.hands[0].body_grip_pose.position.y -
                        grip.hands[1].body_grip_pose.position.y - 0.324F) < 0.001F;
      }();
  if (!holster_valid) {
    std::cerr << "Synthetic holster path contract failed\n";
    return 1;
  }
  std::cout << "Synthetic controller path contract passed\n";
  return 0;
}
