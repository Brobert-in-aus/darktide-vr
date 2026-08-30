#pragma once

#include "core/xr_math.h"

#include <cstdint>

namespace darktidevr::core {

inline constexpr wchar_t kSharedPresentationStateName[] =
    L"Local\\DarktideVR-presentation-state-v2";

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
bool immersive_projection_active(SharedPresentationMode mode);
bool flat_interactive_active(SharedPresentationMode mode);
bool flat_interactive_uses_eye_aspect(SharedPresentationMode mode,
                                      bool shared_eyes_open);

}  // namespace darktidevr::core
