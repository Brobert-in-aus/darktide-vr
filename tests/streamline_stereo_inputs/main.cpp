#include "core/streamline_stereo_inputs.h"

#include <cstdint>
#include <iostream>
#include <stdexcept>

namespace {

using darktidevr::core::StreamlineEyeInputSet;
using darktidevr::core::StreamlineStereoEvaluationStatus;
using darktidevr::core::StreamlineStereoEvaluationTransaction;
using darktidevr::core::StreamlineStereoInputStatus;
using darktidevr::core::StreamlineStereoResource;

void expect(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

void fill(StreamlineEyeInputSet& inputs, std::uint32_t frame,
          std::uintptr_t base) {
  darktidevr::core::begin_streamline_eye_frame(inputs, frame);
  for (std::uint8_t value = 0;
       value < static_cast<std::uint8_t>(StreamlineStereoResource::count);
       ++value) {
    expect(darktidevr::core::observe_streamline_eye_resource(
               inputs, static_cast<StreamlineStereoResource>(value),
               base + value),
           "complete resource observation rejected");
  }
}

StreamlineStereoEvaluationTransaction ready_transaction() {
  StreamlineStereoEvaluationTransaction transaction{};
  transaction.snapshot_ready = true;
  transaction.source_frame_indices = {42, 43};
  transaction.source_token_calls = {100, 101};
  transaction.source_viewports = {7, 8};
  transaction.target_frame_token = 900;
  transaction.target_frame_index = 44;
  transaction.stereo_backbuffer = 1000;
  transaction.stereo_width = 4992;
  transaction.stereo_height = 2688;
  transaction.eye_width = 2496;
  transaction.format = 28;
  transaction.resource_state = 0;
  transaction.consumer_slot_reserved = true;
  return transaction;
}

}  // namespace

int main() {
  try {
    StreamlineEyeInputSet eye0{};
    StreamlineEyeInputSet eye1{};
    expect(darktidevr::core::evaluate_streamline_stereo_inputs(eye0, eye1)
               .status == StreamlineStereoInputStatus::incomplete,
           "empty inputs must fail closed");
    expect(!darktidevr::core::observe_streamline_eye_resource(
               eye0, StreamlineStereoResource::depth, 1),
           "resource observation without frame identity must fail");

    fill(eye0, 42, 100);
    fill(eye1, 42, 200);
    expect(darktidevr::core::evaluate_streamline_stereo_inputs(eye0, eye1)
               .status == StreamlineStereoInputStatus::ready,
           "complete distinct same-frame inputs must pass");

    fill(eye1, 43, 200);
    expect(darktidevr::core::evaluate_streamline_stereo_inputs(eye0, eye1)
               .status == StreamlineStereoInputStatus::frame_mismatch,
           "different frame identities must fail");

    fill(eye1, 42, 200);
    const auto depth_index =
        static_cast<std::size_t>(StreamlineStereoResource::depth);
    const auto motion_index =
        static_cast<std::size_t>(StreamlineStereoResource::motion_vectors);
    eye1.resources[depth_index] = eye0.resources[depth_index];
    eye1.resources[motion_index] = eye0.resources[motion_index];
    const auto aliased =
        darktidevr::core::evaluate_streamline_stereo_inputs(eye0, eye1);
    const auto expected_aliases =
        darktidevr::core::streamline_resource_bit(
            StreamlineStereoResource::depth) |
        darktidevr::core::streamline_resource_bit(
            StreamlineStereoResource::motion_vectors);
    expect(aliased.status == StreamlineStereoInputStatus::cross_eye_alias &&
               aliased.aliased_mask == expected_aliases,
           "aliased inputs must identify each shared resource class");

    darktidevr::core::begin_streamline_eye_frame(eye1, 42);
    expect(!darktidevr::core::observe_streamline_eye_resource(
               eye1, StreamlineStereoResource::depth, 0),
           "null resource identities must be rejected");
    expect(darktidevr::core::evaluate_streamline_stereo_inputs(eye0, eye1)
               .status == StreamlineStereoInputStatus::incomplete,
           "partially observed inputs must remain incomplete");

    auto transaction = ready_transaction();
    expect(darktidevr::core::evaluate_streamline_stereo_transaction(transaction) ==
               StreamlineStereoEvaluationStatus::ready_to_evaluate,
           "complete transaction must become evaluable");
    transaction.source_frame_indices[1] = 44;
    expect(darktidevr::core::evaluate_streamline_stereo_transaction(transaction) ==
               StreamlineStereoEvaluationStatus::source_timing_mismatch,
           "nonadjacent source frames must fail closed");
    transaction = ready_transaction();
    transaction.source_viewports[1] = transaction.source_viewports[0];
    expect(darktidevr::core::evaluate_streamline_stereo_transaction(transaction) ==
               StreamlineStereoEvaluationStatus::invalid_viewports,
           "aliased viewports must fail closed");
    transaction = ready_transaction();
    transaction.target_frame_index = 43;
    expect(darktidevr::core::evaluate_streamline_stereo_transaction(transaction) ==
               StreamlineStereoEvaluationStatus::invalid_target_frame,
           "target frame must follow both source frames");
    transaction = ready_transaction();
    transaction.stereo_width = 2496;
    expect(darktidevr::core::evaluate_streamline_stereo_transaction(transaction) ==
               StreamlineStereoEvaluationStatus::invalid_backbuffer,
           "non-stereo extent must fail closed");
    transaction = ready_transaction();
    transaction.consumer_slot_reserved = false;
    expect(darktidevr::core::evaluate_streamline_stereo_transaction(transaction) ==
               StreamlineStereoEvaluationStatus::transport_unavailable,
           "evaluation must not start without reserved transport");
    transaction = ready_transaction();
    transaction.evaluation_submitted = true;
    expect(darktidevr::core::evaluate_streamline_stereo_transaction(transaction) ==
               StreamlineStereoEvaluationStatus::awaiting_generated_output,
           "submitted evaluation must wait for its GPU fence");
    transaction.generated_output_fence_complete = true;
    expect(darktidevr::core::evaluate_streamline_stereo_transaction(transaction) ==
               StreamlineStereoEvaluationStatus::ready_to_publish,
           "only a fence-complete output may be published");

    std::cout << "streamline_stereo_inputs=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "streamline_stereo_inputs: " << error.what() << '\n';
    return 1;
  }
}
