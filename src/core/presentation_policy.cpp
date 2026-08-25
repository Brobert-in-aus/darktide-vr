#include "core/presentation_policy.h"

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

}  // namespace darktidevr::core
