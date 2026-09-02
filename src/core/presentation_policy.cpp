#include "core/presentation_policy.h"

#include <cmath>
#include <stdexcept>

namespace darktidevr::core {

PresentationDecision choose_presentation_mode(bool emergency_disabled,
                                              bool xr_renderable,
                                              GamePresentationState game_state,
                                              PoseReadState camera_state) {
  if (emergency_disabled) {
    return {PresentationMode::disabled,
            PresentationReason::emergency_disabled};
  }
  if (!xr_renderable) {
    return {PresentationMode::disabled,
            PresentationReason::xr_not_renderable};
  }
  if (game_state != GamePresentationState::gameplay) {
    return {PresentationMode::theatre,
            PresentationReason::semantic_state_requires_theatre};
  }
  if (camera_state == PoseReadState::empty) {
    return {PresentationMode::theatre,
            PresentationReason::camera_unavailable};
  }
  if (camera_state == PoseReadState::stale) {
    return {PresentationMode::theatre, PresentationReason::camera_stale};
  }
  return {PresentationMode::mono_projection,
          PresentationReason::gameplay_camera_ready};
}

math::Pose horizon_locked_panel_pose(math::Pose head_pose,
                                     float distance_metres) {
  if (!(distance_metres > 0.0F) || !std::isfinite(distance_metres)) {
    throw std::invalid_argument("Panel distance must be finite and positive");
  }
  const auto forward =
      math::rotate(head_pose.orientation, {0.0F, 0.0F, -1.0F});
  const auto horizontal_length =
      std::sqrt(forward.x * forward.x + forward.z * forward.z);
  const auto yaw = horizontal_length > 1.0e-4F
                       ? std::atan2(-forward.x, -forward.z)
                       : 0.0F;
  const math::Pose horizon_head{
      math::from_axis_angle({0.0F, 1.0F, 0.0F}, yaw), head_pose.position};
  return math::compose(
      horizon_head, math::Pose{{}, {0.0F, 0.0F, -distance_metres}});
}

PanelExtent fit_panel_extent(std::uint32_t source_width,
                             std::uint32_t source_height,
                             float maximum_width_metres,
                             float maximum_height_metres) {
  if (source_width == 0 || source_height == 0 ||
      !(maximum_width_metres > 0.0F) ||
      !(maximum_height_metres > 0.0F) ||
      !std::isfinite(maximum_width_metres) ||
      !std::isfinite(maximum_height_metres)) {
    throw std::invalid_argument("Panel fit inputs must be finite and positive");
  }
  const auto source_aspect =
      static_cast<float>(source_width) / static_cast<float>(source_height);
  const auto maximum_aspect = maximum_width_metres / maximum_height_metres;
  return source_aspect >= maximum_aspect
             ? PanelExtent{maximum_width_metres,
                           maximum_width_metres / source_aspect}
             : PanelExtent{maximum_height_metres * source_aspect,
                           maximum_height_metres};
}

bool cached_stereo_pair_allowed(bool fresh_pair_available,
                                bool cached_pair_valid,
                                bool projection_active,
                                std::uint64_t stale_milliseconds,
                                std::uint64_t grace_milliseconds) {
  return !fresh_pair_available && cached_pair_valid && projection_active &&
         grace_milliseconds != 0 && stale_milliseconds <= grace_milliseconds;
}

}  // namespace darktidevr::core
