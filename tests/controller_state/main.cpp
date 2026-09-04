#include "../isolated_transports.h"
#include "core/shared_controller_state.h"

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
  try {
    darktidevr::tests::isolate_transports();
    using namespace darktidevr::core;
    SharedControllerState sample{};
    sample.sequence = 7;
    sample.timestamp_ns = 1'000'000;
    sample.hands[0].aim_pose.orientation.w = 1.0F;
    sample.hands[0].grip_pose.orientation.w = 1.0F;
    sample.hands[0].body_aim_pose.orientation.w = 1.0F;
    sample.hands[0].body_grip_pose.orientation.w = 1.0F;
    sample.hands[1].aim_pose.orientation.w = 1.0F;
    sample.hands[1].grip_pose.orientation.w = 1.0F;
    sample.hands[1].body_aim_pose.orientation.w = 1.0F;
    sample.hands[1].body_grip_pose.orientation.w = 1.0F;
    sample.hands[1].aim_pose.position = {0.25F, 1.2F, -0.5F};
    sample.hands[1].aim_tracking_flags =
        controller_orientation_valid | controller_position_valid;
    sample.hands[1].body_aim_pose.position = {0.25F, 0.5F, 1.2F};
    sample.hands[1].body_aim_tracking_flags =
        controller_orientation_valid | controller_position_valid;
    sample.hands[1].trigger = 0.75F;
    sample.hands[1].squeeze = 0.5F;
    sample.hands[1].thumbstick_x = -0.25F;
    sample.hands[1].thumbstick_y = 1.0F;
    sample.hands[1].buttons = controller_primary | controller_stick_click;
    expect(valid_controller_state(sample), "Valid sample was rejected");
    expect(controller_state_is_fresh(sample, 1'010'000, 20'000),
           "Fresh sample was rejected");
    expect(!controller_state_is_fresh(sample, 1'030'001, 20'000),
           "Stale sample was accepted");

    SharedControllerStateReader reader;
    SharedControllerState read{};
    std::uint64_t first_generation{};
    {
      SharedControllerStateWriter writer;
      expect(writer.publish(sample), "Controller publish failed");
      expect(reader.read(read), "Controller read failed");
      expect(read.sequence == 7 && read.transport_generation != 0 &&
                 read.hands[1].trigger == 0.75F &&
                 read.hands[1].buttons == sample.hands[1].buttons &&
                 read.hands[1].body_aim_pose.position.y == 0.5F &&
                 read.hands[1].body_aim_tracking_flags ==
                     sample.hands[1].body_aim_tracking_flags,
             "Controller transport changed the sample");
      first_generation = read.transport_generation;

      sample.hands[0].trigger = 2.0F;
      expect(!valid_controller_state(sample),
             "Out-of-range trigger was accepted");
      expect(!writer.publish(sample),
             "Invalid controller sample was published");
    }
    sample.hands[0].trigger = 0.0F;
    {
      SharedControllerStateWriter restarted_writer;
      expect(restarted_writer.publish(sample),
             "Restarted controller writer could not publish");
      expect(reader.read(read) && read.sequence == sample.sequence &&
                 read.transport_generation == first_generation + 1,
             "Controller writer generation must disambiguate equal restart sequences");
    }

    std::cout << "controller_state.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "controller_state: " << error.what() << '\n';
    return 1;
  }
}
