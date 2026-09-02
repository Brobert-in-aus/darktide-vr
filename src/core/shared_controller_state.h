#pragma once

#include "core/xr_math.h"

#include <cstdint>

namespace darktidevr::core {

inline constexpr wchar_t kSharedControllerStateName[] =
    L"Local\\DarktideVR-controller-state-v3";

enum ControllerTrackingFlags : std::uint32_t {
  controller_orientation_valid = 1U << 0U,
  controller_position_valid = 1U << 1U,
  controller_orientation_tracked = 1U << 2U,
  controller_position_tracked = 1U << 3U,
};

enum ControllerButtons : std::uint32_t {
  controller_primary = 1U << 0U,
  controller_secondary = 1U << 1U,
  controller_stick_click = 1U << 2U,
  controller_menu = 1U << 3U,
};

struct ControllerHandState {
  // Absolute OpenXR LOCAL-space poses used by spatial compositor panels.
  math::Pose aim_pose{};
  math::Pose grip_pose{};
  std::uint32_t aim_tracking_flags{};
  std::uint32_t grip_tracking_flags{};
  // Recenter-relative poses converted to Darktide's Z-up body-local basis.
  // Flags remain zero until the immutable HMD recenter anchor is available.
  math::Pose body_aim_pose{};
  math::Pose body_grip_pose{};
  std::uint32_t body_aim_tracking_flags{};
  std::uint32_t body_grip_tracking_flags{};
  float trigger{};
  float squeeze{};
  float thumbstick_x{};
  float thumbstick_y{};
  std::uint32_t buttons{};
};

struct SharedControllerState {
  std::uint64_t sequence{};
  std::uint64_t timestamp_ns{};
  ControllerHandState hands[2]{};
  // Transport-owned writer generation. Readers use it to distinguish an XR
  // restart even when its first sequence equals the last old sequence.
  std::uint64_t transport_generation{};
};

class SharedControllerStateWriter {
 public:
  SharedControllerStateWriter();
  ~SharedControllerStateWriter();

  SharedControllerStateWriter(const SharedControllerStateWriter&) = delete;
  SharedControllerStateWriter& operator=(const SharedControllerStateWriter&) =
      delete;

  bool publish(const SharedControllerState& state);

 private:
  void* mapping_{};
  void* view_{};
};

class SharedControllerStateReader {
 public:
  SharedControllerStateReader() = default;
  ~SharedControllerStateReader();

  SharedControllerStateReader(const SharedControllerStateReader&) = delete;
  SharedControllerStateReader& operator=(const SharedControllerStateReader&) =
      delete;

  bool read(SharedControllerState& state);

 private:
  bool ensure_open();

  void* mapping_{};
  void* view_{};
};

bool valid_controller_state(const SharedControllerState& state);
bool controller_state_is_fresh(const SharedControllerState& state,
                               std::uint64_t now_ns,
                               std::uint64_t maximum_age_ns);

}  // namespace darktidevr::core
