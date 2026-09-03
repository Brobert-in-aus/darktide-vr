#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace darktidevr::core {

enum class StreamlineStereoResource : std::uint8_t {
  depth,
  hudless_color,
  motion_vectors,
  scaling_input_color,
  scaling_output_color,
  count,
};

constexpr std::size_t kStreamlineStereoResourceCount =
    static_cast<std::size_t>(StreamlineStereoResource::count);
constexpr std::uint32_t kAllStreamlineStereoResources =
    (1U << kStreamlineStereoResourceCount) - 1U;

struct StreamlineEyeInputSet {
  std::uint32_t frame_index{};
  bool frame_identity_valid{};
  std::uint32_t observed_mask{};
  std::array<std::uintptr_t, kStreamlineStereoResourceCount> resources{};
};

enum class StreamlineStereoInputStatus : std::uint8_t {
  incomplete,
  frame_mismatch,
  cross_eye_alias,
  ready,
};

struct StreamlineStereoInputVerdict {
  StreamlineStereoInputStatus status{StreamlineStereoInputStatus::incomplete};
  std::uint32_t aliased_mask{};
};

constexpr std::uint32_t streamline_resource_bit(
    StreamlineStereoResource resource) noexcept {
  return 1U << static_cast<std::uint32_t>(resource);
}

constexpr void begin_streamline_eye_frame(StreamlineEyeInputSet& inputs,
                                           std::uint32_t frame_index) noexcept {
  inputs = {};
  inputs.frame_index = frame_index;
  inputs.frame_identity_valid = true;
}

constexpr bool observe_streamline_eye_resource(
    StreamlineEyeInputSet& inputs, StreamlineStereoResource resource,
    std::uintptr_t identity) noexcept {
  const auto index = static_cast<std::size_t>(resource);
  if (!inputs.frame_identity_valid || index >= inputs.resources.size() ||
      identity == 0) {
    return false;
  }
  inputs.resources[index] = identity;
  inputs.observed_mask |= streamline_resource_bit(resource);
  return true;
}

constexpr bool streamline_eye_inputs_complete(
    const StreamlineEyeInputSet& inputs) noexcept {
  return inputs.frame_identity_valid &&
         inputs.observed_mask == kAllStreamlineStereoResources;
}

constexpr StreamlineStereoInputVerdict evaluate_streamline_stereo_inputs(
    const StreamlineEyeInputSet& eye0,
    const StreamlineEyeInputSet& eye1) noexcept {
  if (!streamline_eye_inputs_complete(eye0) ||
      !streamline_eye_inputs_complete(eye1)) {
    return {StreamlineStereoInputStatus::incomplete, 0};
  }
  if (eye0.frame_index != eye1.frame_index) {
    return {StreamlineStereoInputStatus::frame_mismatch, 0};
  }
  std::uint32_t aliased_mask{};
  for (std::size_t index = 0; index < kStreamlineStereoResourceCount;
       ++index) {
    if (eye0.resources[index] == eye1.resources[index]) {
      aliased_mask |= 1U << index;
    }
  }
  if (aliased_mask != 0) {
    return {StreamlineStereoInputStatus::cross_eye_alias, aliased_mask};
  }
  return {StreamlineStereoInputStatus::ready, 0};
}

}  // namespace darktidevr::core
