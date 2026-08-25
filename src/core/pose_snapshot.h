#pragma once

#include <atomic>
#include <cstdint>
#include <optional>

#include "core/xr_math.h"

namespace darktidevr::core {

struct PosePacket {
  std::uint64_t sequence{};
  std::uint64_t received_time_ns{};
  std::uint64_t source_id{};
  math::Pose pose{};
  float vertical_fov_rad{};
};

enum class PoseReadState { empty, fresh, stale };

struct PoseRead {
  PoseReadState state{PoseReadState::empty};
  std::optional<PosePacket> packet;
};

// Single-writer, multi-reader snapshot for transferring the newest camera pose
// without making a reader wait on a mutex. Atomic fields plus an epoch prevent
// C++ data races while bounded retries prevent a stalled writer from blocking.
class PoseSnapshot {
 public:
  bool publish(const PosePacket& packet);
  PoseRead read(std::uint64_t now_ns, std::uint64_t maximum_age_ns) const;

 private:
  std::atomic<std::uint64_t> epoch_{0};
  std::atomic<std::uint64_t> sequence_{0};
  std::atomic<std::uint64_t> received_time_ns_{0};
  std::atomic<std::uint64_t> source_id_{0};
  std::atomic<float> position_x_{0.0F};
  std::atomic<float> position_y_{0.0F};
  std::atomic<float> position_z_{0.0F};
  std::atomic<float> rotation_x_{0.0F};
  std::atomic<float> rotation_y_{0.0F};
  std::atomic<float> rotation_z_{0.0F};
  std::atomic<float> rotation_w_{1.0F};
  std::atomic<float> vertical_fov_rad_{0.0F};
};

}  // namespace darktidevr::core
