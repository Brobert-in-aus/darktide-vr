#include "core/pose_snapshot.h"

#include <cmath>

namespace darktidevr::core {
namespace {

constexpr float kPi = 3.14159265358979323846F;

bool valid_packet(const PosePacket& packet) {
  const auto& position = packet.pose.position;
  const auto& rotation = packet.pose.orientation;
  const auto quaternion_norm =
      std::sqrt(rotation.x * rotation.x + rotation.y * rotation.y +
                rotation.z * rotation.z + rotation.w * rotation.w);
  return packet.sequence != 0 && packet.received_time_ns != 0 &&
         std::isfinite(position.x) && std::isfinite(position.y) &&
         std::isfinite(position.z) && std::isfinite(rotation.x) &&
         std::isfinite(rotation.y) && std::isfinite(rotation.z) &&
         std::isfinite(rotation.w) &&
         std::abs(quaternion_norm - 1.0F) <= 0.01F &&
         std::isfinite(packet.vertical_fov_rad) &&
         packet.vertical_fov_rad > 0.0F && packet.vertical_fov_rad < kPi;
}

}  // namespace

bool PoseSnapshot::publish(const PosePacket& packet) {
  if (!valid_packet(packet) ||
      packet.sequence <= sequence_.load(std::memory_order_acquire)) {
    return false;
  }

  const auto writing_epoch = epoch_.load(std::memory_order_relaxed) + 1;
  epoch_.store(writing_epoch, std::memory_order_relaxed);
  // The odd epoch must become visible before any field store; a release
  // store alone lets later relaxed stores move ahead of it.
  std::atomic_thread_fence(std::memory_order_release);
  received_time_ns_.store(packet.received_time_ns, std::memory_order_relaxed);
  source_id_.store(packet.source_id, std::memory_order_relaxed);
  position_x_.store(packet.pose.position.x, std::memory_order_relaxed);
  position_y_.store(packet.pose.position.y, std::memory_order_relaxed);
  position_z_.store(packet.pose.position.z, std::memory_order_relaxed);
  rotation_x_.store(packet.pose.orientation.x, std::memory_order_relaxed);
  rotation_y_.store(packet.pose.orientation.y, std::memory_order_relaxed);
  rotation_z_.store(packet.pose.orientation.z, std::memory_order_relaxed);
  rotation_w_.store(packet.pose.orientation.w, std::memory_order_relaxed);
  vertical_fov_rad_.store(packet.vertical_fov_rad, std::memory_order_relaxed);
  sequence_.store(packet.sequence, std::memory_order_relaxed);
  epoch_.store(writing_epoch + 1, std::memory_order_release);
  return true;
}

PoseRead PoseSnapshot::read(std::uint64_t now_ns,
                            std::uint64_t maximum_age_ns) const {
  for (int attempt = 0; attempt < 4; ++attempt) {
    const auto before = epoch_.load(std::memory_order_acquire);
    if ((before & 1U) != 0U) {
      continue;
    }

    PosePacket packet{};
    packet.sequence = sequence_.load(std::memory_order_relaxed);
    packet.received_time_ns =
        received_time_ns_.load(std::memory_order_relaxed);
    packet.source_id = source_id_.load(std::memory_order_relaxed);
    packet.pose.position = {position_x_.load(std::memory_order_relaxed),
                            position_y_.load(std::memory_order_relaxed),
                            position_z_.load(std::memory_order_relaxed)};
    packet.pose.orientation = {rotation_x_.load(std::memory_order_relaxed),
                               rotation_y_.load(std::memory_order_relaxed),
                               rotation_z_.load(std::memory_order_relaxed),
                               rotation_w_.load(std::memory_order_relaxed)};
    packet.vertical_fov_rad =
        vertical_fov_rad_.load(std::memory_order_relaxed);

    // The field loads must complete before the closing epoch check.
    std::atomic_thread_fence(std::memory_order_acquire);
    const auto after = epoch_.load(std::memory_order_relaxed);
    if (before != after || (after & 1U) != 0U) {
      continue;
    }
    if (packet.sequence == 0) {
      return {};
    }

    const auto stale = now_ns < packet.received_time_ns ||
                       now_ns - packet.received_time_ns > maximum_age_ns;
    return {stale ? PoseReadState::stale : PoseReadState::fresh, packet};
  }
  return {};
}

}  // namespace darktidevr::core
