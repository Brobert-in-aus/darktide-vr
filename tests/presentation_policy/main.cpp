#include "core/presentation_policy.h"

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
    using namespace darktidevr::core;
    auto decision = choose_presentation_mode(
        false, true, GamePresentationState::gameplay, PoseReadState::fresh);
    expect(decision.mode == PresentationMode::mono_projection &&
               decision.reason == PresentationReason::gameplay_camera_ready,
           "Fresh gameplay camera should permit mono projection");

    decision = choose_presentation_mode(
        false, true, GamePresentationState::gameplay, PoseReadState::stale);
    expect(decision.mode == PresentationMode::theatre &&
               decision.reason == PresentationReason::camera_stale,
           "Stale gameplay camera must fall back to theatre");

    decision = choose_presentation_mode(
        false, true, GamePresentationState::loading, PoseReadState::fresh);
    expect(decision.mode == PresentationMode::theatre &&
               decision.reason ==
                   PresentationReason::semantic_state_requires_theatre,
           "Loading must remain in theatre even with a fresh camera");

    decision = choose_presentation_mode(
        true, true, GamePresentationState::gameplay, PoseReadState::fresh);
    expect(decision.mode == PresentationMode::disabled &&
               decision.reason == PresentationReason::emergency_disabled,
           "Emergency disable must dominate all other state");

    decision = choose_presentation_mode(
        false, false, GamePresentationState::gameplay, PoseReadState::fresh);
    expect(decision.mode == PresentationMode::disabled &&
               decision.reason == PresentationReason::xr_not_renderable,
           "Non-renderable XR session must disable submission");

    std::cout << "presentation_policy.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "presentation_policy: " << error.what() << '\n';
    return 1;
  }
}
