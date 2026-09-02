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

struct PanelExtent {
  float width_metres{};
  float height_metres{};
};

PresentationDecision choose_presentation_mode(bool emergency_disabled,
                                              bool xr_renderable,
                                              GamePresentationState game_state,
                                              PoseReadState camera_state);

math::Pose horizon_locked_panel_pose(math::Pose head_pose,
                                     float distance_metres);
PanelExtent fit_panel_extent(std::uint32_t source_width,
                             std::uint32_t source_height,
                             float maximum_width_metres,
                             float maximum_height_metres);

// A cached pair hides short producer gaps and menu-to-world handoffs, but it
// must not turn a dead producer into an indefinitely frozen immersive world.
bool cached_stereo_pair_allowed(bool fresh_pair_available,
                                bool cached_pair_valid,
                                bool projection_active,
                                std::uint64_t stale_milliseconds,
                                std::uint64_t grace_milliseconds);

}  // namespace darktidevr::core
