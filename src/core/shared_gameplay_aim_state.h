#pragma once

#include <cstdint>
#include <optional>
#include "core/xr_math.h"

namespace darktidevr::core {

inline constexpr wchar_t kSharedGameplayAimStateName[] =
    L"Local\\DarktideVR-gameplay-aim-state-v4";

struct SharedGameplayAimState {
  std::uint64_t sequence{};
  std::uint64_t timestamp_ns{};
  float distance_metres{};
  bool active{};
  bool hit{};
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
