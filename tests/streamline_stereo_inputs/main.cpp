#include "core/streamline_stereo_inputs.h"

#include <cstdint>
#include <iostream>
#include <stdexcept>

namespace {

using darktidevr::core::StreamlineEyeInputSet;
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

    std::cout << "streamline_stereo_inputs=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "streamline_stereo_inputs: " << error.what() << '\n';
    return 1;
  }
}
