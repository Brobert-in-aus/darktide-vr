#include "core/shared_presentation_state.h"

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
    using namespace darktidevr::core;
    SharedPresentationStateReader reader;
    {
      SharedPresentationStateWriter writer;
      SharedPresentationState state{7,
                                    SharedPresentationMode::flat_menu,
                                    1920,
                                    1080,
                                    80,
                                    40,
                                    1760,
                                    1000,
                                    2.0F,
                                    2.0F};
      expect(writer.publish(state), "Valid menu state should publish");
      SharedPresentationState observed{};
      expect(reader.read(observed), "Published menu state should be readable");
      expect(observed.sequence == 7 &&
                 observed.mode == SharedPresentationMode::flat_menu &&
                 observed.crop_x == 80 && observed.crop_width == 1760,
             "Reader should preserve the complete packet");

      state.sequence = 8;
      state.crop_width = 1920;
      expect(!writer.publish(state), "Out-of-bounds crop must fail closed");

      state = {9,
               SharedPresentationMode::world_anchored_menu,
               1920,
               1080,
               0,
               0,
               1920,
               1080,
               2.0F,
               2.0F,
               true,
               {{0.0F, 0.0F, 0.0F, 1.0F}, {1.0F, 2.0F, 1.5F}}};
      expect(writer.publish(state), "Valid world-anchored menu should publish");
      expect(reader.read(observed) && observed.body_panel_pose_valid &&
                 observed.body_panel_pose.position.y == 2.0F,
             "Reader should preserve the body-relative panel pose");
      state.body_panel_pose_valid = false;
      expect(!writer.publish(state),
             "World-anchored menu without a pose must fail closed");
    }

    std::cout << "presentation_state_transport.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "presentation_state_transport: " << error.what() << '\n';
    return 1;
  }
}
