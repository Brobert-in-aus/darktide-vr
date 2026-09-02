#include "core/shared_gameplay_aim_state.h"

#include <chrono>
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
    const auto now_ns = static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now().time_since_epoch())
            .count());
    SharedGameplayAimState sample{7, now_ns, 12.5F, true, true};
    expect(valid_gameplay_aim_state(sample), "Valid aim state was rejected");
    expect(gameplay_aim_state_is_fresh(sample, now_ns, 100'000'000ULL),
           "Current aim state was treated as stale");
    expect(!gameplay_aim_state_is_fresh(sample, now_ns + 100'000'001ULL,
                                        100'000'000ULL),
           "Expired aim state was treated as fresh");

    SharedGameplayAimStateReader reader;
    SharedGameplayAimState read{};
    std::uint64_t first_generation{};
    {
      SharedGameplayAimStateWriter writer;
      expect(writer.publish(sample), "Gameplay aim publish failed");
      expect(reader.read(read), "Gameplay aim read failed");
      expect(read.sequence == sample.sequence &&
                 read.distance_metres == sample.distance_metres &&
                 read.active && read.hit && read.transport_generation != 0,
             "Gameplay aim transport changed the sample");
      first_generation = read.transport_generation;

      sample = {8, now_ns, 0.0F, false, false};
      expect(writer.publish(sample), "Inactive gameplay aim publish failed");
      expect(reader.read(read) && !read.active && !read.hit,
             "Inactive gameplay aim state was not preserved");

      sample = {9, now_ns, 201.0F, true, false};
      expect(!valid_gameplay_aim_state(sample),
             "Out-of-range gameplay aim distance was accepted");
      expect(!writer.publish(sample),
             "Invalid gameplay aim state was published");
    }

    {
      SharedGameplayAimStateWriter writer;
      sample = {1, now_ns, 3.0F, true, false};
      expect(writer.publish(sample),
             "Restarted gameplay aim writer should publish sequence one");
      expect(reader.read(read) && read.sequence == 1 &&
                 read.transport_generation == first_generation + 1,
             "Gameplay aim reader must identify a restarted writer");
    }

    std::cout << "gameplay_aim_state.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "gameplay_aim_state: " << error.what() << '\n';
    return 1;
  }
}
