#include "../isolated_transports.h"
#include "core/shared_menu_pointer_state.h"

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
    SharedMenuPointerState sample{};
    sample.sequence = 7;
    sample.timestamp_ns = 1'000'000;
    sample.source_x = 960;
    sample.source_y = 1080;
    sample.source_width = 1920;
    sample.source_height = 2160;
    sample.active = true;
    sample.primary_down = true;
    sample.secondary_down = true;
    sample.secondary_press_sequence = 14;
    sample.scroll_steps = -2;
    sample.primary_press_sequence = 11;
    sample.back_press_sequence = 12;
    sample.scroll_sequence = 13;
    expect(valid_menu_pointer_state(sample), "Valid pointer was rejected");

    SharedMenuPointerStateReader reader;
    SharedMenuPointerState read{};
    std::uint64_t first_generation{};
    {
      SharedMenuPointerStateWriter writer;
      expect(writer.publish(sample), "Pointer publish failed");
      expect(reader.read(read), "Pointer read failed");
      first_generation = read.transport_generation;
    }
    expect(read.sequence == sample.sequence && read.active &&
               read.source_x == sample.source_x &&
               read.source_y == sample.source_y &&
               read.source_width == sample.source_width &&
               read.source_height == sample.source_height &&
               read.primary_down && !read.back_down &&
               read.secondary_down && read.secondary_press_sequence == 14 &&
               read.scroll_steps == -2 &&
               read.primary_press_sequence == 11 &&
               read.back_press_sequence == 12 &&
               read.scroll_sequence == 13,
           "Pointer transport changed the sample");

    sample.sequence = 1;
    sample.primary_press_sequence = 0;
    sample.secondary_down = false;
    sample.secondary_press_sequence = 0;
    sample.back_press_sequence = 0;
    sample.scroll_sequence = 0;
    {
      SharedMenuPointerStateWriter restarted_writer;
      expect(restarted_writer.publish(sample),
             "Restarted pointer publish failed");
      expect(reader.read(read), "Restarted pointer read failed");
    }
    expect(read.sequence == 1 &&
               !read.secondary_down && read.secondary_press_sequence == 0 &&
               read.transport_generation > first_generation,
           "Pointer writer restart did not advance its transport generation");

    sample.active = false;
    sample.source_width = 0;
    sample.source_height = 0;
    expect(valid_menu_pointer_state(sample),
           "Inactive pointer without an extent was rejected");

    sample.active = true;
    sample.source_width = 1920;
    sample.source_height = 2160;
    sample.source_x = 1920;
    expect(!valid_menu_pointer_state(sample),
           "Out-of-bounds pointer was accepted");

    sample.active = false;
    sample.scroll_steps = 5;
    expect(!valid_menu_pointer_state(sample),
           "Out-of-range scroll burst was accepted");

    std::cout << "menu_pointer_state.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "menu_pointer_state: " << error.what() << '\n';
    return 1;
  }
}
