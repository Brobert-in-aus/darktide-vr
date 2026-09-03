#include "core/shared_generated_frame_state.h"

#include <cstdint>
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
    using darktidevr::core::SharedGeneratedFrameState;
    using darktidevr::core::SharedGeneratedFrameStateReader;
    using darktidevr::core::SharedGeneratedFrameStateWriter;
    using darktidevr::core::generated_frame_slot;
    using darktidevr::core::valid_generated_frame_state;

    expect(generated_frame_slot(1) == 0 && generated_frame_slot(2) == 1 &&
               generated_frame_slot(3) == 2 && generated_frame_slot(4) == 0,
           "Generated frame sequences must cycle through three slots");

    SharedGeneratedFrameState invalid{};
    expect(!valid_generated_frame_state(invalid),
           "An empty generated frame state must be invalid");

    SharedGeneratedFrameStateWriter writer;
    SharedGeneratedFrameStateReader reader;
    expect(!writer.publish(0, 10, 20, 2496, 2688, 28),
           "Sequence zero must be rejected");
    expect(!writer.publish(1, 0, 20, 2496, 2688, 28),
           "Native call zero must be rejected");

    for (std::uint64_t sequence = 1; sequence <= 5; ++sequence) {
      const auto native_call = sequence + 4000;
      const auto frame_index = static_cast<std::uint32_t>(sequence + 9000);
      expect(writer.publish(sequence, native_call, frame_index, 2496, 2688,
                            28),
             "Valid generated frame publication failed");
      SharedGeneratedFrameState read{};
      expect(reader.read(read), "Generated frame reader failed");
      const auto& slot = read.slots[generated_frame_slot(sequence)];
      expect(read.transport_generation != 0 &&
                 read.latest_sequence == sequence && read.width == 2496 &&
                 read.height == 2688 && read.format == 28 &&
                 slot.sequence == sequence &&
                 slot.native_call == native_call &&
                 slot.frame_index == frame_index,
             "Generated frame metadata did not round-trip");
    }

    SharedGeneratedFrameStateWriter restarted_writer;
    expect(restarted_writer.publish(1, 1, 1, 2496, 2688, 28),
           "Restarted writer publication failed");
    SharedGeneratedFrameState restarted{};
    expect(reader.read(restarted) && restarted.latest_sequence == 1 &&
               restarted.transport_generation >= 2,
           "Writer restart must advance generation and reset sequence");

    std::cout << "generated_frame_state=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
