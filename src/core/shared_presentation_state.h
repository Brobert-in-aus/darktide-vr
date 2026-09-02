#pragma once

#include "core/xr_math.h"

#include <cstdint>

namespace darktidevr::core {

inline constexpr wchar_t kSharedPresentationStateName[] =
    L"Local\\DarktideVR-presentation-state-v4";

enum class SharedPresentationMode : std::uint32_t {
  disabled = 0,
  stereo_world = 1,
  flat_loading_or_cinematic = 2,
  world_anchored_menu = 3,
  flat_menu = 4,
  flat_interactive = 5,
  flat_interactive_native_aspect = 6,
  error = 7,
};

struct SharedPresentationState {
  std::uint64_t sequence{};
  SharedPresentationMode mode{SharedPresentationMode::disabled};
  std::uint32_t source_width{};
  std::uint32_t source_height{};
  std::uint32_t crop_x{};
  std::uint32_t crop_y{};
  std::uint32_t crop_width{};
  std::uint32_t crop_height{};
  float maximum_panel_width_metres{2.0F};
  float maximum_panel_height_metres{2.0F};
  bool body_panel_pose_valid{};
  math::Pose body_panel_pose{};
  // Transport-owned writer generation. Publishers leave this zero; readers
  // use it with sequence to distinguish an identical sequence after restart.
  std::uint64_t transport_generation{};
  // Transport-owned monotonic publication time from GetTickCount64. The Lua
  // producer republishes unchanged modes as a heartbeat so a live consumer can
  // fail flat if the mod stops updating while the game process remains alive.
  std::uint64_t published_at_ms{};
};

class SharedPresentationStateWriter {
 public:
  SharedPresentationStateWriter();
  ~SharedPresentationStateWriter();

  SharedPresentationStateWriter(const SharedPresentationStateWriter&) = delete;
  SharedPresentationStateWriter& operator=(
      const SharedPresentationStateWriter&) = delete;

  bool publish(const SharedPresentationState& state);

 private:
  void* mapping_{};
  void* view_{};
};

class SharedPresentationStateReader {
 public:
  SharedPresentationStateReader() = default;
  ~SharedPresentationStateReader();

  SharedPresentationStateReader(const SharedPresentationStateReader&) = delete;
  SharedPresentationStateReader& operator=(
      const SharedPresentationStateReader&) = delete;

  bool read(SharedPresentationState& state);

 private:
  bool ensure_open();

  void* mapping_{};
  void* view_{};
};

bool valid_presentation_state(const SharedPresentationState& state);
bool presentation_state_fresh(const SharedPresentationState& state,
                              std::uint64_t now_ms,
                              std::uint64_t maximum_age_ms);
bool immersive_projection_active(SharedPresentationMode mode);
bool flat_interactive_active(SharedPresentationMode mode);
bool flat_interactive_uses_eye_aspect(SharedPresentationMode mode,
                                      bool shared_eyes_open);
// Heartbeat publications advance sequence and publication time without
// creating a new spatial panel. Only a transport/mode change, or a changed
// authored body anchor, owns a new panel pose.
bool same_flat_panel_anchor_identity(const SharedPresentationState& left,
                                     const SharedPresentationState& right);

}  // namespace darktidevr::core
