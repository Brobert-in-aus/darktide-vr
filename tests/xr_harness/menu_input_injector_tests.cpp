#include "menu_input_injector.h"

#include <iostream>
#include <stdexcept>

int main() {
  using darktidevr::harness::ClientRectOnDesktop;
  using darktidevr::harness::DesktopRect;
  using darktidevr::harness::map_source_to_absolute_pointer;
  try {
    const DesktopRect desktop{-1920, 0, 5760, 2160};
    const ClientRectOnDesktop client{0, 0, 1920, 1080};
    const auto top_left =
        map_source_to_absolute_pointer(0, 0, 2112, 2304, client, desktop);
    const auto bottom_right = map_source_to_absolute_pointer(
        2111, 2303, 2112, 2304, client, desktop);
    if (!top_left || !bottom_right || top_left->x != 21849 ||
        top_left->y != 0 || bottom_right->x != 43686 ||
        bottom_right->y != 32752) {
      throw std::runtime_error("Source-to-virtual-desktop mapping mismatch");
    }
    if (map_source_to_absolute_pointer(2112, 0, 2112, 2304, client,
                                       desktop) ||
        map_source_to_absolute_pointer(0, 0, 0, 2304, client, desktop)) {
      throw std::runtime_error("Invalid source coordinates were accepted");
    }
    const ClientRectOnDesktop outside{6000, 0, 1920, 1080};
    if (map_source_to_absolute_pointer(0, 0, 2112, 2304, outside, desktop)) {
      throw std::runtime_error("Off-desktop client was accepted");
    }
    std::cout << "menu_input_injector.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "menu_input_injector: " << error.what() << '\n';
    return 1;
  }
}
