#include "core/shared_gameplay_aim_state.h"

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
    SharedGameplayAimState sample{7, 12.5F, true, true};
    expect(valid_gameplay_aim_state(sample), "Valid aim state was rejected");

    SharedGameplayAimStateWriter writer;
    SharedGameplayAimStateReader reader;
    expect(writer.publish(sample), "Gameplay aim publish failed");
    SharedGameplayAimState read{};
    expect(reader.read(read), "Gameplay aim read failed");
    expect(read.sequence == sample.sequence &&
               read.distance_metres == sample.distance_metres && read.active &&
               read.hit,
           "Gameplay aim transport changed the sample");

    sample = {8, 0.0F, false, false};
    expect(writer.publish(sample), "Inactive gameplay aim publish failed");
    expect(reader.read(read) && !read.active && !read.hit,
           "Inactive gameplay aim state was not preserved");

    sample = {9, 201.0F, true, false};
    expect(!valid_gameplay_aim_state(sample),
           "Out-of-range gameplay aim distance was accepted");
    expect(!writer.publish(sample),
           "Invalid gameplay aim state was published");

    std::cout << "gameplay_aim_state.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "gameplay_aim_state: " << error.what() << '\n';
    return 1;
  }
}
