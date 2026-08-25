#pragma once

#include "core/pose_snapshot.h"

namespace darktidevr::core {

enum class GamePresentationState {
  unknown,
  gameplay,
  hub,
  menu,
  loading,
  cutscene,
  incapacitated,
  spectator,
};

enum class PresentationMode { disabled, theatre, mono_projection };

enum class PresentationReason {
  emergency_disabled,
  xr_not_renderable,
  semantic_state_requires_theatre,
  camera_unavailable,
  camera_stale,
  gameplay_camera_ready,
};

struct PresentationDecision {
  PresentationMode mode{PresentationMode::disabled};
  PresentationReason reason{PresentationReason::xr_not_renderable};
};

PresentationDecision choose_presentation_mode(bool emergency_disabled,
                                              bool xr_renderable,
                                              GamePresentationState game_state,
                                              PoseReadState camera_state);

}  // namespace darktidevr::core
