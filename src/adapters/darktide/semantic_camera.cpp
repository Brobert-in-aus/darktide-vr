#include "adapters/darktide/semantic_camera.h"

#include <array>
#include <cmath>
#include <cstdio>
#include <string>

namespace darktidevr::darktide {
namespace {

constexpr std::string_view kPrefix = "DARKTIDEVR_CAMERA schema=1 ";
constexpr float kPi = 3.14159265358979323846F;

bool finite(float value) { return std::isfinite(value); }

}  // namespace

std::optional<SemanticCameraSample> parse_semantic_camera_line(
    std::string_view line) {
  const auto prefix_offset = line.find(kPrefix);
  if (prefix_offset == std::string_view::npos) {
    return std::nullopt;
  }

  const std::string payload(line.substr(prefix_offset));
  std::array<char, 64> viewport{};
  SemanticCameraSample sample{};
  const auto matched = sscanf_s(
      payload.c_str(),
      "DARKTIDEVR_CAMERA schema=1 viewport=%63s "
      "position=%f,%f,%f rotation=%f,%f,%f,%f vfov_rad=%f",
      viewport.data(), static_cast<unsigned>(viewport.size()),
      &sample.pose.position.x, &sample.pose.position.y, &sample.pose.position.z,
      &sample.pose.orientation.x, &sample.pose.orientation.y,
      &sample.pose.orientation.z, &sample.pose.orientation.w,
      &sample.vertical_fov_rad);
  if (matched != 9) {
    return std::nullopt;
  }

  sample.viewport = viewport.data();
  const auto& position = sample.pose.position;
  const auto& rotation = sample.pose.orientation;
  if (sample.viewport.empty() || !finite(position.x) || !finite(position.y) ||
      !finite(position.z) || !finite(rotation.x) || !finite(rotation.y) ||
      !finite(rotation.z) || !finite(rotation.w) ||
      !finite(sample.vertical_fov_rad) || sample.vertical_fov_rad <= 0.0F ||
      sample.vertical_fov_rad >= kPi) {
    return std::nullopt;
  }

  const auto quaternion_norm =
      std::sqrt(rotation.x * rotation.x + rotation.y * rotation.y +
                rotation.z * rotation.z + rotation.w * rotation.w);
  if (std::abs(quaternion_norm - 1.0F) > 0.01F) {
    return std::nullopt;
  }

  return sample;
}

}  // namespace darktidevr::darktide
