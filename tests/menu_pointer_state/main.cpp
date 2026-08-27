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
    expect(valid_menu_pointer_state(sample), "Valid pointer was rejected");

    SharedMenuPointerStateWriter writer;
    SharedMenuPointerStateReader reader;
    expect(writer.publish(sample), "Pointer publish failed");
    SharedMenuPointerState read{};
    expect(reader.read(read), "Pointer read failed");
    expect(read.sequence == sample.sequence && read.active &&
               read.source_x == sample.source_x &&
               read.source_y == sample.source_y &&
               read.source_width == sample.source_width &&
               read.source_height == sample.source_height &&
               read.primary_down && !read.back_down,
           "Pointer transport changed the sample");

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

    std::cout << "menu_pointer_state.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "menu_pointer_state: " << error.what() << '\n';
    return 1;
  }
}
