#include "core/shared_head_pose.h"

#include <chrono>
#include <cmath>
#include <iostream>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

void expect(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

}  // namespace

int main(int argc, char** argv) {
  try {
    if (argc == 2 && std::string(argv[1]) == "--live") {
      darktidevr::core::SharedHeadPoseReader reader;
      darktidevr::core::SharedHeadPoseSample received{};
      for (int attempt = 0; attempt < 100; ++attempt) {
        if (reader.read(received)) {
          std::cout << "shared_head_pose.live=pass sequence="
                    << received.sequence << " position="
                    << received.pose.position.x << ','
                    << received.pose.position.y << ','
                    << received.pose.position.z << " orientation="
                    << received.pose.orientation.x << ','
                    << received.pose.orientation.y << ','
                    << received.pose.orientation.z << ','
                    << received.pose.orientation.w << '\n';
          return 0;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
      }
      throw std::runtime_error("Live shared head pose is unavailable");
    }
    auto writer = std::make_unique<darktidevr::core::SharedHeadPoseWriter>();
    darktidevr::core::SharedHeadPoseReader reader;
    darktidevr::core::SharedHeadPoseSample sample{};
    sample.sequence = 7;
    sample.recenter_generation = 3;
    sample.pose = {{0.0F, 0.38268343F, 0.0F, 0.92387953F},
                   {0.1F, -0.2F, 0.3F}};
    sample.body_follow_offset = {0.75F, 0.0F, -0.25F};
    sample.render_vertical_fov_radians = 1.7F;
    sample.render_aspect_ratio = 0.8888889F;
    sample.render_width = 2112;
    sample.render_height = 2304;
    sample.render_frusta[0] = {-0.94F, 0.70F, -0.96F, 0.77F};
    sample.render_frusta[1] = {-0.70F, 0.94F, -0.96F, 0.77F};
    expect(writer->publish(sample), "Valid shared pose was rejected");
    darktidevr::core::SharedHeadPoseSample received{};
    expect(reader.read(received), "Published shared pose was unreadable");
    expect(received.sequence == sample.sequence &&
               received.recenter_generation == 3 &&
               std::abs(received.pose.position.z - 0.3F) < 0.0001F &&
               std::abs(received.pose.orientation.w - 0.92387953F) < 0.0001F &&
               std::abs(received.render_vertical_fov_radians - 1.7F) < 0.0001F &&
               std::abs(received.render_aspect_ratio - 0.8888889F) < 0.0001F &&
               received.render_width == 2112 &&
               received.render_height == 2304 &&
               std::abs(received.body_follow_offset.x - 0.75F) < 0.0001F &&
               std::abs(received.body_follow_offset.z + 0.25F) < 0.0001F &&
               std::abs(received.ipd_metres - 0.064F) < 0.0001F &&
               std::abs(received.render_frusta[0].left + 0.94F) < 0.0001F &&
               std::abs(received.render_frusta[1].right - 0.94F) < 0.0001F,
           "Shared pose changed in transit");
    expect(reader.publish_rendered_pair(
               {11, {7, 7}, {1.6F, 1.6F}, {0.8888889F, 0.8888889F}}),
           "Rendered-pair pose tag was rejected");
    darktidevr::core::SharedRenderedEyePairPose pair{};
    expect(writer->read_rendered_pair(pair) && pair.ready_value == 11 &&
               pair.eye_pose_sequences[0] == 7 &&
               pair.eye_pose_sequences[1] == 7 &&
               std::abs(pair.vertical_fov_radians[0] - 1.6F) < 0.0001F &&
               std::abs(pair.aspect_ratios[1] - 0.8888889F) < 0.0001F,
           "Rendered-pair pose tag changed in transit");
    expect(!reader.publish_rendered_pair(
               {0, {7, 7}, {1.6F, 1.6F}, {0.8888889F, 0.8888889F}}),
           "Invalid rendered-pair tag was accepted");
    expect(!reader.publish_rendered_pair(
               {12, {7, 7}, {0.0F, 1.6F}, {0.8888889F, 0.8888889F}}),
           "Invalid rendered-pair projection was accepted");
    expect(!reader.publish_rendered_pair(
               {std::numeric_limits<std::uint64_t>::max(),
                {7, 7}, {1.6F, 1.6F}, {0.8888889F, 0.8888889F}}),
           "An unrepresentable rendered-pair counter was accepted");
    writer.reset();
    writer = std::make_unique<darktidevr::core::SharedHeadPoseWriter>();
    expect(!reader.read(received),
           "A restarted writer retained the previous session pose");
    expect(!writer->read_rendered_pair(pair),
           "A restarted writer retained the previous rendered-pair tag");
    expect(writer->publish(sample),
           "A restarted writer could not publish a new session pose");
    std::this_thread::sleep_for(std::chrono::milliseconds(275));
    expect(!reader.read(received), "Stale shared pose remained readable");
    sample.sequence = 8;
    sample.pose.position.x = std::numeric_limits<float>::infinity();
    expect(!writer->publish(sample), "Non-finite shared pose was accepted");
    sample.pose.position.x = 0.0F;
    sample.sequence = 8;
    sample.ipd_metres = 0.0F;
    expect(!writer->publish(sample), "Invalid runtime IPD was accepted");
    sample.ipd_metres = 0.064F;
    sample.sequence = std::numeric_limits<std::uint64_t>::max();
    expect(!writer->publish(sample),
           "An unrepresentable shared-pose counter was accepted");
    std::cout << "shared_head_pose.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "shared_head_pose: " << error.what() << '\n';
    return 1;
  }
}
