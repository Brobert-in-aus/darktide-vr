#include "core/shared_object_name.h"
#include "core/shared_controller_state.h"

#include <Windows.h>

#include <cmath>
#include <cstring>
#include <limits>
#include <stdexcept>

namespace darktidevr::core {
namespace {

struct SharedLayout {
  volatile LONG64 epoch{};
  volatile LONG64 writer_generation{};
  SharedControllerState state{};
};

static_assert(alignof(SharedLayout) >= alignof(LONG64));

void close_mapping(void*& mapping, void*& view) {
  if (view) {
    UnmapViewOfFile(view);
    view = nullptr;
  }
  if (mapping) {
    CloseHandle(static_cast<HANDLE>(mapping));
    mapping = nullptr;
  }
}

bool finite_pose(const math::Pose& pose) {
  const auto& q = pose.orientation;
  const auto& p = pose.position;
  const auto length_squared = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w;
  return std::isfinite(q.x) && std::isfinite(q.y) && std::isfinite(q.z) &&
         std::isfinite(q.w) && length_squared > 0.25F &&
         length_squared < 4.0F && std::isfinite(p.x) && std::isfinite(p.y) &&
         std::isfinite(p.z);
}

bool finite_unit(float value) {
  return std::isfinite(value) && value >= 0.0F && value <= 1.0F;
}

bool finite_axis(float value) {
  return std::isfinite(value) && value >= -1.0F && value <= 1.0F;
}

}  // namespace

bool valid_controller_state(const SharedControllerState& state) {
  constexpr std::uint32_t kAllTrackingFlags =
      controller_orientation_valid | controller_position_valid |
      controller_orientation_tracked | controller_position_tracked;
  constexpr std::uint32_t kAllButtons = controller_primary |
                                          controller_secondary |
                                          controller_stick_click |
                                          controller_menu;
  if (state.sequence == 0 || state.timestamp_ns == 0 ||
      state.sequence >
          static_cast<std::uint64_t>(std::numeric_limits<LONG64>::max())) {
    return false;
  }
  for (const auto& hand : state.hands) {
    if (!finite_pose(hand.aim_pose) || !finite_pose(hand.grip_pose) ||
        !finite_pose(hand.body_aim_pose) ||
        !finite_pose(hand.body_grip_pose) ||
        (hand.aim_tracking_flags & ~kAllTrackingFlags) != 0 ||
        (hand.grip_tracking_flags & ~kAllTrackingFlags) != 0 ||
        (hand.body_aim_tracking_flags & ~kAllTrackingFlags) != 0 ||
        (hand.body_grip_tracking_flags & ~kAllTrackingFlags) != 0 ||
        !finite_unit(hand.trigger) || !finite_unit(hand.squeeze) ||
        !finite_axis(hand.thumbstick_x) || !finite_axis(hand.thumbstick_y) ||
        (hand.buttons & ~kAllButtons) != 0) {
      return false;
    }
  }
  return true;
}

bool controller_state_is_fresh(const SharedControllerState& state,
                               std::uint64_t now_ns,
                               std::uint64_t maximum_age_ns) {
  return valid_controller_state(state) && now_ns >= state.timestamp_ns &&
         now_ns - state.timestamp_ns <= maximum_age_ns;
}

SharedControllerStateWriter::SharedControllerStateWriter() {
  mapping_ = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
                                0, sizeof(SharedLayout),
                                shared_object_name(kSharedControllerStateName).c_str());
  if (!mapping_) {
    throw std::runtime_error("CreateFileMapping(shared controllers) failed");
  }
  view_ = MapViewOfFile(static_cast<HANDLE>(mapping_), FILE_MAP_ALL_ACCESS, 0,
                        0, sizeof(SharedLayout));
  if (!view_) {
    close_mapping(mapping_, view_);
    throw std::runtime_error("MapViewOfFile(shared controllers) failed");
  }
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedExchange64(&data.epoch, 1);
  InterlockedIncrement64(&data.writer_generation);
  std::memset(&data.state, 0, sizeof(data.state));
  data.state.hands[0].aim_pose.orientation.w = 1.0F;
  data.state.hands[0].grip_pose.orientation.w = 1.0F;
  data.state.hands[0].body_aim_pose.orientation.w = 1.0F;
  data.state.hands[0].body_grip_pose.orientation.w = 1.0F;
  data.state.hands[1].aim_pose.orientation.w = 1.0F;
  data.state.hands[1].grip_pose.orientation.w = 1.0F;
  data.state.hands[1].body_aim_pose.orientation.w = 1.0F;
  data.state.hands[1].body_grip_pose.orientation.w = 1.0F;
  MemoryBarrier();
  InterlockedExchange64(&data.epoch, 2);
}

SharedControllerStateWriter::~SharedControllerStateWriter() {
  close_mapping(mapping_, view_);
}

bool SharedControllerStateWriter::publish(const SharedControllerState& state) {
  if (!valid_controller_state(state)) {
    return false;
  }
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedIncrement64(&data.epoch);
  std::memcpy(&data.state, &state, sizeof(state));
  MemoryBarrier();
  InterlockedIncrement64(&data.epoch);
  return true;
}

SharedControllerStateReader::~SharedControllerStateReader() {
  close_mapping(mapping_, view_);
}

bool SharedControllerStateReader::ensure_open() {
  if (view_) {
    return true;
  }
  mapping_ = OpenFileMappingW(FILE_MAP_READ, FALSE, shared_object_name(kSharedControllerStateName).c_str());
  if (!mapping_) {
    return false;
  }
  view_ = MapViewOfFile(static_cast<HANDLE>(mapping_), FILE_MAP_READ, 0, 0,
                        sizeof(SharedLayout));
  if (!view_) {
    close_mapping(mapping_, view_);
    return false;
  }
  return true;
}

bool SharedControllerStateReader::read(SharedControllerState& state) {
  if (!ensure_open()) {
    return false;
  }
  const auto& data = *static_cast<const SharedLayout*>(view_);
  for (int attempt = 0; attempt < 4; ++attempt) {
    const auto before = data.epoch;
    MemoryBarrier();
    if ((before & 1) != 0) {
      continue;
    }
    SharedControllerState candidate{};
    std::memcpy(&candidate, &data.state, sizeof(candidate));
    candidate.transport_generation =
        static_cast<std::uint64_t>(data.writer_generation);
    MemoryBarrier();
    const auto after = data.epoch;
    if (before == after && (after & 1) == 0 &&
        candidate.transport_generation != 0 &&
        valid_controller_state(candidate)) {
      state = candidate;
      return true;
    }
  }
  return false;
}

}  // namespace darktidevr::core
