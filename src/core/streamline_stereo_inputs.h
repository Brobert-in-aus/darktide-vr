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

enum class StreamlineStereoEvaluationStatus : std::uint8_t {
  snapshot_not_ready,
  source_timing_mismatch,
  invalid_viewports,
  invalid_target_frame,
  invalid_backbuffer,
  transport_unavailable,
  ready_to_evaluate,
  awaiting_generated_output,
  ready_to_publish,
};

struct StreamlineStereoEvaluationTransaction {
  bool snapshot_ready{};
  std::array<std::uint32_t, 2> source_frame_indices{~0U, ~0U};
  std::array<std::uint64_t, 2> source_token_calls{};
  std::array<std::uint32_t, 2> source_viewports{};
  std::uintptr_t target_frame_token{};
  std::uint32_t target_frame_index{~0U};
  std::uintptr_t stereo_backbuffer{};
  std::uint64_t stereo_width{};
  std::uint32_t stereo_height{};
  std::uint64_t eye_width{};
  std::uint32_t format{};
  std::uint32_t resource_state{};
  bool consumer_slot_reserved{};
  bool evaluation_submitted{};
  bool generated_output_fence_complete{};
};

constexpr bool streamline_source_values_coherent(std::uint64_t first,
                                                  std::uint64_t second) noexcept {
  return first == second || first + 1 == second || second + 1 == first;
}

constexpr StreamlineStereoEvaluationStatus
evaluate_streamline_stereo_transaction(
    const StreamlineStereoEvaluationTransaction& transaction) noexcept {
  if (!transaction.snapshot_ready) {
    return StreamlineStereoEvaluationStatus::snapshot_not_ready;
  }
  if (transaction.source_frame_indices[0] == ~0U ||
      transaction.source_frame_indices[1] == ~0U ||
      transaction.source_token_calls[0] == 0 ||
      transaction.source_token_calls[1] == 0 ||
      !streamline_source_values_coherent(
          transaction.source_frame_indices[0],
          transaction.source_frame_indices[1]) ||
      !streamline_source_values_coherent(transaction.source_token_calls[0],
                                         transaction.source_token_calls[1])) {
    return StreamlineStereoEvaluationStatus::source_timing_mismatch;
  }
  if (transaction.source_viewports[0] == 0 ||
      transaction.source_viewports[1] == 0 ||
      transaction.source_viewports[0] == transaction.source_viewports[1]) {
    return StreamlineStereoEvaluationStatus::invalid_viewports;
  }
  if (transaction.target_frame_token == 0 ||
      transaction.target_frame_index == ~0U ||
      transaction.target_frame_index <= transaction.source_frame_indices[0] ||
      transaction.target_frame_index <= transaction.source_frame_indices[1]) {
    return StreamlineStereoEvaluationStatus::invalid_target_frame;
  }
  constexpr std::uint32_t required_format = 26;
  constexpr std::uint32_t required_state = 8;
  if (transaction.stereo_backbuffer == 0 || transaction.eye_width == 0 ||
      transaction.eye_width > (~std::uint64_t{} / 2) ||
      transaction.stereo_width != transaction.eye_width * 2 ||
      transaction.stereo_height == 0 ||
      transaction.format != required_format ||
      transaction.resource_state != required_state) {
    return StreamlineStereoEvaluationStatus::invalid_backbuffer;
  }
  if (!transaction.consumer_slot_reserved) {
    return StreamlineStereoEvaluationStatus::transport_unavailable;
  }
  if (!transaction.evaluation_submitted) {
    return StreamlineStereoEvaluationStatus::ready_to_evaluate;
  }
  if (!transaction.generated_output_fence_complete) {
    return StreamlineStereoEvaluationStatus::awaiting_generated_output;
  }
  return StreamlineStereoEvaluationStatus::ready_to_publish;
}

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
