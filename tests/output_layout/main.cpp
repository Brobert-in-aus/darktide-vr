#include "core/output_layout.h"

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

    const auto defaults = choose_output_layout({{2688, 2880}});
    expect(defaults.eye_extent == PixelExtent{2688, 2880},
           "Runtime recommendation must determine default eye resolution");
    expect(defaults.eye_surface_count == 2,
           "Stereo output must keep two independent eye surfaces");
    expect(defaults.mirror_mode == MirrorMode::left_eye &&
               defaults.mirror_extent == PixelExtent{1280, 720},
           "Default mirror must be a low-resolution left-eye copy");

    OutputLayoutRequest diagnostic{{2688, 2880}};
    diagnostic.eye_override = PixelExtent{1920, 2160};
    diagnostic.mirror_mode = MirrorMode::side_by_side;
    diagnostic.mirror_extent = {1920, 540};
    const auto overridden = choose_output_layout(diagnostic);
    expect(overridden.eye_extent == PixelExtent{1920, 2160},
           "Explicit eye resolution must be honored");
    expect(overridden.mirror_mode == MirrorMode::side_by_side &&
               overridden.mirror_extent == PixelExtent{1920, 540},
           "Diagnostic SBS mirror must not affect eye resolution");

    OutputLayoutRequest headless{{2688, 2880}};
    headless.mirror_mode = MirrorMode::disabled;
    headless.mirror_extent = {};
    const auto without_mirror = choose_output_layout(headless);
    expect(without_mirror.eye_extent == defaults.eye_extent &&
               without_mirror.mirror_extent == PixelExtent{},
           "Disabling the mirror must preserve headset resolution");

    bool rejected{};
    try {
      (void)choose_output_layout({{0, 2880}});
    } catch (const std::invalid_argument&) {
      rejected = true;
    }
    expect(rejected, "Zero-sized eye surfaces must be rejected");

    std::cout << "output_layout.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "output_layout: " << error.what() << '\n';
    return 1;
  }
}
