#pragma once

#include <cstdint>
#include <optional>
#include "core/xr_math.h"

namespace darktidevr::core {

inline constexpr wchar_t kSharedGameplayAimStateName[] =
    L"Local\\DarktideVR-gameplay-aim-state-v6";

struct SharedGameplayAimState {
  std::uint64_t sequence{};
  std::uint64_t timestamp_ns{};
  float distance_metres{};
  bool active{};
  bool hit{};
  // Aim-down-sights (alternate fire) held on the wielded weapon; the viewer
  // tightens the reticle and draws the focus vignette from it.
  bool aiming_down_sights{};
  // The aim zoom the GAME is rendering with this frame, as a magnification.
  //
  // It has to cross, and this is why. The zoom narrows the frustum the game's
  // cameras render with (Lua: zoomed_frustum). Until 19 September the viewer
  // never learned of it and kept submitting the runtime's UNZOOMED field of
  // view, so the runtime displayed a zoomed image as though it were not. Each
  // eye's frustum leans the opposite way, so recentring rotates each view onto
  // its own optical axis 0.1224 rad off the fused forward -- and magnifying
  // each eye's image about THAT axis moves the two eyes' content in opposite
  // directions. Divergence is 2 * 0.1224 * (m - 1): 0.42 degrees at three per
  // cent, 1.93 at fifteen, against a fusion limit near one. Worn, at fifteen:
  // "so diverged I couldn't visually converge the reticules".
  //
  // 1 means no zoom, and anything outside [1, 4] is rejected rather than
  // clamped -- a bad magnification here pulls the player's eyes apart, so it
  // must not be guessed at.
  float zoom_magnification{1.0F};
  std::uint64_t transport_generation{};
  bool target_point_valid{};
  math::Vec3 target_point{}; // OpenXR coordinates relative to the sampled origin
  std::uint64_t head_pose_sequence{};
  std::uint64_t head_transport_generation{};
  std::uint32_t recenter_generation{};
};

class SharedGameplayAimStateWriter {
 public:
  SharedGameplayAimStateWriter();
  ~SharedGameplayAimStateWriter();

  SharedGameplayAimStateWriter(const SharedGameplayAimStateWriter&) = delete;
  SharedGameplayAimStateWriter& operator=(
      const SharedGameplayAimStateWriter&) = delete;

  bool publish(const SharedGameplayAimState& state);

 private:
  void* mapping_{};
  void* view_{};
};

class SharedGameplayAimStateReader {
 public:
  SharedGameplayAimStateReader() = default;
  ~SharedGameplayAimStateReader();

  SharedGameplayAimStateReader(const SharedGameplayAimStateReader&) = delete;
  SharedGameplayAimStateReader& operator=(
      const SharedGameplayAimStateReader&) = delete;

  bool read(SharedGameplayAimState& state);

 private:
  bool ensure_open();

  void* mapping_{};
  void* view_{};
};

bool valid_gameplay_aim_state(const SharedGameplayAimState& state);
bool gameplay_aim_state_is_fresh(const SharedGameplayAimState& state,
                                 std::uint64_t now_ns,
                                 std::uint64_t maximum_age_ns);
std::optional<math::Vec3> resolve_gameplay_aim_target(
    const SharedGameplayAimState& state, std::uint64_t reference_sequence,
    std::uint64_t head_generation, std::uint32_t recenter_generation,
    math::Pose sampled_origin);

}  // namespace darktidevr::core
