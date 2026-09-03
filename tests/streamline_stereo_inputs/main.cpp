#include "core/streamline_stereo_inputs.h"

#include <cstdint>
#include <iostream>
#include <stdexcept>

namespace {

using darktidevr::core::StreamlineEyeInputSet;
using darktidevr::core::StreamlineStereoPresentationStatus;
using darktidevr::core::StreamlineStereoPresentationTransaction;
using darktidevr::core::StreamlineStereoPresentTarget;
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

StreamlineStereoPresentationTransaction ready_transaction() {
  StreamlineStereoPresentationTransaction transaction{};
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

StreamlineStereoPresentTarget matching_present_target() {
  return {1000, 2000, 4992, 4992, 2688, 2688, 28, 28, 0, 0};
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
    expect(darktidevr::core::evaluate_streamline_stereo_presentation(transaction) ==
               StreamlineStereoPresentationStatus::ready_to_stage,
           "complete transaction must become ready to stage");
    transaction.source_frame_indices[1] = 44;
    expect(darktidevr::core::evaluate_streamline_stereo_presentation(transaction) ==
               StreamlineStereoPresentationStatus::source_timing_mismatch,
           "nonadjacent source frames must fail closed");
    transaction = ready_transaction();
    transaction.source_viewports[1] = transaction.source_viewports[0];
    expect(darktidevr::core::evaluate_streamline_stereo_presentation(transaction) ==
               StreamlineStereoPresentationStatus::invalid_viewports,
           "aliased viewports must fail closed");
    transaction = ready_transaction();
    transaction.target_frame_index = 43;
    expect(darktidevr::core::evaluate_streamline_stereo_presentation(transaction) ==
               StreamlineStereoPresentationStatus::invalid_target_frame,
           "target frame must follow both source frames");
    transaction = ready_transaction();
    transaction.stereo_width = 2496;
    expect(darktidevr::core::evaluate_streamline_stereo_presentation(transaction) ==
               StreamlineStereoPresentationStatus::invalid_backbuffer,
           "non-stereo extent must fail closed");
    transaction = ready_transaction();
    transaction.consumer_slot_reserved = false;
    expect(darktidevr::core::evaluate_streamline_stereo_presentation(transaction) ==
               StreamlineStereoPresentationStatus::transport_unavailable,
           "generation present must not start without reserved transport");
    transaction = ready_transaction();
    transaction.generation_present_submitted = true;
    expect(darktidevr::core::evaluate_streamline_stereo_presentation(transaction) ==
               StreamlineStereoPresentationStatus::awaiting_generated_present,
           "submitted generation present must wait for its GPU fence");
    transaction.generated_output_fence_complete = true;
    expect(darktidevr::core::evaluate_streamline_stereo_presentation(transaction) ==
               StreamlineStereoPresentationStatus::ready_to_publish,
           "only a fence-complete output may be published");

    auto present_target = matching_present_target();
    expect(darktidevr::core::streamline_stereo_present_target_matches(
               present_target),
           "matching distinct stereo and Present targets must pass");
    present_target.present_width = 2496;
    expect(!darktidevr::core::streamline_stereo_present_target_matches(
               present_target),
           "mismatched Present extent must fail closed");
    present_target = matching_present_target();
    present_target.present_backbuffer = present_target.stereo_backbuffer;
    expect(!darktidevr::core::streamline_stereo_present_target_matches(
               present_target),
           "the staging source and Present destination must be distinct");

    std::cout << "streamline_stereo_inputs=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "streamline_stereo_inputs: " << error.what() << '\n';
    return 1;
  }
}
