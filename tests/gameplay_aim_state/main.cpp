#include "../isolated_transports.h"
#include "core/shared_gameplay_aim_state.h"

#include <chrono>
#include <cmath>
#include <iostream>
#include <limits>
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
    const auto now_ns = static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now().time_since_epoch())
            .count());
    SharedGameplayAimState sample{7, now_ns, 12.5F, true, true};
    expect(valid_gameplay_aim_state(sample), "Valid aim state was rejected");
    // THE AIM ZOOM MUST FAIL CLOSED (19 September). A magnification the reader
    // accepts is one the viewer will narrow its submitted frustum by, and a
    // wrong one pulls the player's two eyes apart -- 2 * 0.1224 * (m - 1)
    // radians, which is past the fusion limit before m reaches 1.2. So the
    // rule is rejected-not-clamped, and this is the only new validation rule
    // in that change, which is reason enough for it to have a test.
    //
    // The default first: a sample from a producer that never sets it carries
    // the NSDMI of 1, which must read as "no zoom" rather than as invalid.
    expect(sample.zoom_magnification == 1.0F,
           "An unset magnification did not default to no zoom");
    for (const float accepted : {1.0F, 1.0001F, 1.05F, 1.30F, 4.0F}) {
      auto zoomed = sample;
      zoomed.zoom_magnification = accepted;
      expect(valid_gameplay_aim_state(zoomed),
             "A magnification inside the range was rejected");
    }
    // Below 1 would WIDEN the submitted frustum, which is the same fault with
    // its sign flipped; above 4 is past what the Lua will ever ask for, and a
    // value that large would be unusable rather than merely wrong.
    for (const float refused : {0.0F, 0.5F, 0.9999F, 4.0001F, 100.0F, -1.0F,
                                std::numeric_limits<float>::infinity(),
                                -std::numeric_limits<float>::infinity(),
                                std::numeric_limits<float>::quiet_NaN()}) {
      auto zoomed = sample;
      zoomed.zoom_magnification = refused;
      expect(!valid_gameplay_aim_state(zoomed),
             "A magnification outside the range was accepted");
    }
    expect(gameplay_aim_state_is_fresh(sample, now_ns, 100'000'000ULL),
           "Current aim state was treated as stale");
    expect(!gameplay_aim_state_is_fresh(sample, now_ns + 100'000'001ULL,
                                        100'000'000ULL),
           "Expired aim state was treated as fresh");
    const auto frame_start_ns = now_ns;
    const auto post_wait_ns = frame_start_ns + 16'000'000ULL;
    auto during_wait = sample;
    during_wait.timestamp_ns = frame_start_ns + 8'000'000ULL;
    expect(!gameplay_aim_state_is_fresh(during_wait, frame_start_ns,
                                        100'000'000ULL) &&
               gameplay_aim_state_is_fresh(during_wait, post_wait_ns,
                                           100'000'000ULL),
           "Aim published during a frame wait requires a post-read clock");
    during_wait.timestamp_ns = post_wait_ns + 1;
    expect(!gameplay_aim_state_is_fresh(during_wait, post_wait_ns,
                                        100'000'000ULL),
           "Actually future aim must still be rejected");

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

      sample.target_point_valid = true;
      sample.target_point = {0.4F, -0.2F, -12.5F};
      sample.head_pose_sequence = 42;
      sample.head_transport_generation = 3;
      sample.recenter_generation = 8;
      expect(writer.publish(sample) && reader.read(read) &&
                 read.target_point_valid && read.target_point.x == 0.4F &&
                 read.head_pose_sequence == 42 && read.head_transport_generation == 3 &&
                 read.recenter_generation == 8,
             "Target point and tracking reference must survive transport");
      const darktidevr::math::Pose sampled_origin{
          darktidevr::math::from_axis_angle({0, 1, 0}, 1.57079632679F),
          {1.0F, 1.7F, 2.0F}};
      const auto target = resolve_gameplay_aim_target(sample, 42, 3, 8, sampled_origin);
      expect(target && std::abs(target->x + 11.5F) < 0.0001F &&
                 std::abs(target->y - 1.5F) < 0.0001F &&
                 std::abs(target->z - 1.6F) < 0.0001F,
             "Stock target must use sampled origin rather than current controller ray");
      expect(!resolve_gameplay_aim_target(sample, 41, 3, 8, sampled_origin) &&
                 !resolve_gameplay_aim_target(sample, 42, 4, 8, sampled_origin) &&
                 !resolve_gameplay_aim_target(sample, 42, 3, 9, sampled_origin),
             "Wrong head frame, publisher or recenter must hide the target");
      auto invalid_target = sample;
      invalid_target.target_point.x = std::numeric_limits<float>::quiet_NaN();
      expect(!writer.publish(invalid_target), "Nonfinite target was published");
      invalid_target = sample;
      invalid_target.head_transport_generation = 0;
      expect(!writer.publish(invalid_target), "Unidentified target reference was published");
      invalid_target = sample;
      invalid_target.active = false;
      invalid_target.hit = false;
      invalid_target.distance_metres = 0;
      expect(!writer.publish(invalid_target), "Inactive target must clear point validity");

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
