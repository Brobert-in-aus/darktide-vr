#include "synthetic_controller_path.h"

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
      reacquired.phase ==
          darktidevr::harness::SyntheticControllerPhase::left_sweep;
  if (!valid) {
    std::cerr << "Synthetic controller path contract failed\n";
    return 1;
  }
  std::cout << "Synthetic controller path contract passed\n";
  return 0;
}
