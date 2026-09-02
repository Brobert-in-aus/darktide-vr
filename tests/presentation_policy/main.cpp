#include "core/presentation_policy.h"

#include <iostream>
#include <cmath>
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

    const auto pitched_head = darktidevr::math::Pose{
        darktidevr::math::multiply(
            darktidevr::math::from_axis_angle({0.0F, 1.0F, 0.0F}, 0.6F),
            darktidevr::math::from_axis_angle(
                {1.0F, 0.0F, 0.0F}, -0.7F)),
        {1.0F, 1.7F, -3.0F}};
    const auto panel = horizon_locked_panel_pose(pitched_head, 2.0F);
    const auto panel_up =
        darktidevr::math::rotate(panel.orientation, {0.0F, 1.0F, 0.0F});
    expect(std::abs(panel_up.x) < 1.0e-5F &&
               std::abs(panel_up.y - 1.0F) < 1.0e-5F &&
               std::abs(panel_up.z) < 1.0e-5F,
           "Flat panels must discard head pitch and roll");
    expect(std::abs(panel.position.y - pitched_head.position.y) < 1.0e-5F,
           "Flat panels must remain level with the opening head pose");

    const auto wide = fit_panel_extent(1920, 1080, 2.0F, 2.0F);
    expect(std::abs(wide.width_metres - 2.0F) < 1.0e-5F &&
               std::abs(wide.height_metres - 1.125F) < 1.0e-5F,
           "Wide captures must fit inside the panel without stretching");
    const auto tall = fit_panel_extent(1080, 1920, 2.0F, 2.0F);
    expect(std::abs(tall.width_metres - 1.125F) < 1.0e-5F &&
               std::abs(tall.height_metres - 2.0F) < 1.0e-5F,
           "Tall captures must fit inside the panel without stretching");
    const auto darktide_window = fit_panel_extent(1280, 768, 2.0F, 2.0F);
    expect(std::abs(darktide_window.width_metres - 2.0F) < 1.0e-5F &&
               std::abs(darktide_window.height_metres - 1.2F) < 1.0e-5F,
           "Native shop panels must preserve the Darktide client aspect");

    expect(cached_stereo_pair_allowed(false, true, true, 5000, 5000),
           "A cached stereo pair should cover a bounded producer gap");
    expect(!cached_stereo_pair_allowed(false, true, true, 5001, 5000),
           "A stale stereo pair must not freeze projection indefinitely");
    expect(!cached_stereo_pair_allowed(true, true, true, 100, 5000),
           "Fresh producer output must supersede the recovery cache");
    expect(!cached_stereo_pair_allowed(false, true, false, 100, 5000),
           "Inactive projection must not retain a cached immersive pair");
    expect(!cached_stereo_pair_allowed(false, true, true, 0, 0),
           "A zero recovery grace must disable cached-pair reuse");

    std::cout << "presentation_policy.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "presentation_policy: " << error.what() << '\n';
    return 1;
  }
}
