#include "core/pose_snapshot.h"

#include <atomic>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <thread>

namespace {

void expect(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

darktidevr::core::PosePacket packet(std::uint64_t sequence,
                                    std::uint64_t time_ns) {
  return {sequence, time_ns, 0x706C6179657231ULL,
          {{0.0F, 0.0F, 0.0F, 1.0F},
           {static_cast<float>(sequence), 2.0F, 3.0F}},
          1.0F};
}

}  // namespace

int main() {
  try {
    using namespace darktidevr::core;
    PoseSnapshot snapshot;
    expect(snapshot.read(100, 50).state == PoseReadState::empty,
           "Unpublished snapshot must be empty");

    expect(snapshot.publish(packet(1, 100)), "First packet should publish");
    const auto fresh = snapshot.read(140, 50);
    expect(fresh.state == PoseReadState::fresh && fresh.packet,
           "Recent packet should be fresh");
    expect(fresh.packet->sequence == 1 &&
               fresh.packet->pose.position.x == 1.0F,
           "Snapshot fields must remain coherent");
    expect(snapshot.read(151, 50).state == PoseReadState::stale,
           "Old packet must become stale deterministically");
    expect(snapshot.read(99, 50).state == PoseReadState::stale,
           "Clock reversal must fail to stale");

    expect(!snapshot.publish(packet(1, 200)),
           "Duplicate sequence must be rejected");
    expect(!snapshot.publish(packet(0, 200)),
           "Zero sequence must be rejected");
    auto invalid = packet(2, 200);
    invalid.pose.position.x = std::numeric_limits<float>::infinity();
    expect(!snapshot.publish(invalid), "Non-finite pose must be rejected");
    invalid = packet(2, 200);
    invalid.pose.orientation.w = 0.5F;
    expect(!snapshot.publish(invalid),
           "Non-unit quaternion must be rejected");

    expect(snapshot.publish(packet(2, 200)),
           "New monotonic packet should publish");
    const auto newest = snapshot.read(200, 0);
    expect(newest.state == PoseReadState::fresh && newest.packet &&
               newest.packet->sequence == 2,
           "Newest zero-age packet should be readable");

    PoseSnapshot concurrent;
    std::atomic<bool> writer_failed{false};
    std::thread writer([&concurrent, &writer_failed] {
      for (std::uint64_t sequence = 1; sequence <= 10000; ++sequence) {
        if (!concurrent.publish(packet(sequence, sequence))) {
          writer_failed.store(true);
          return;
        }
      }
    });
    std::uint64_t last_sequence = 0;
    while (last_sequence < 10000) {
      const auto read = concurrent.read(10000, 10000);
      if (!read.packet) {
        continue;
      }
      expect(read.packet->sequence >= last_sequence,
             "Concurrent reads must not move backwards");
      expect(read.packet->pose.position.x ==
                 static_cast<float>(read.packet->sequence),
             "Concurrent snapshot fields must be coherent");
      last_sequence = read.packet->sequence;
    }
    writer.join();
    expect(!writer_failed.load(),
           "Concurrent writer should accept monotonic valid packets");

    std::cout << "pose_snapshot.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "pose_snapshot: " << error.what() << '\n';
    return 1;
  }
}
