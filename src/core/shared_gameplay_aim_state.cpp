#include "core/shared_object_name.h"
#include "core/shared_gameplay_aim_state.h"

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
  SharedGameplayAimState state{};
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

}  // namespace

bool valid_gameplay_aim_state(const SharedGameplayAimState& state) {
  if (state.sequence == 0 || state.timestamp_ns == 0 ||
      state.sequence >
          static_cast<std::uint64_t>(std::numeric_limits<LONG64>::max()) ||
      !std::isfinite(state.distance_metres)) {
    return false;
  }
  if (!state.active) {
    return state.distance_metres == 0.0F && !state.hit && !state.target_point_valid;
  }
  if (state.target_point_valid) {
    const auto& p = state.target_point;
    if (state.head_pose_sequence == 0 || state.head_transport_generation == 0 ||
        !std::isfinite(p.x) || !std::isfinite(p.y) || !std::isfinite(p.z) ||
        std::abs(p.x) > 1000.0F || std::abs(p.y) > 1000.0F ||
        std::abs(p.z) > 1000.0F) {
      return false;
    }
  }
  return state.distance_metres >= 0.05F && state.distance_metres <= 200.0F;
}

bool gameplay_aim_state_is_fresh(const SharedGameplayAimState& state,
                                 std::uint64_t now_ns,
                                 std::uint64_t maximum_age_ns) {
  return valid_gameplay_aim_state(state) && now_ns >= state.timestamp_ns &&
         now_ns - state.timestamp_ns <= maximum_age_ns;
}

std::optional<math::Vec3> resolve_gameplay_aim_target(
    const SharedGameplayAimState& state, std::uint64_t reference_sequence,
    std::uint64_t head_generation, std::uint32_t recenter_generation,
    math::Pose sampled_origin) {
  if (!valid_gameplay_aim_state(state) || !state.active ||
      !state.target_point_valid || state.head_pose_sequence != reference_sequence ||
      state.head_transport_generation != head_generation ||
      state.recenter_generation != recenter_generation) {
    return std::nullopt;
  }
  return math::transform_point(sampled_origin, state.target_point);
}

SharedGameplayAimStateWriter::SharedGameplayAimStateWriter() {
  mapping_ = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
                                0, sizeof(SharedLayout),
                                shared_object_name(kSharedGameplayAimStateName).c_str());
  if (!mapping_) {
    throw std::runtime_error("CreateFileMapping(shared gameplay aim) failed");
  }
  view_ = MapViewOfFile(static_cast<HANDLE>(mapping_), FILE_MAP_ALL_ACCESS, 0,
                        0, sizeof(SharedLayout));
  if (!view_) {
    close_mapping(mapping_, view_);
    throw std::runtime_error("MapViewOfFile(shared gameplay aim) failed");
  }
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedExchange64(&data.epoch, 1);
  InterlockedIncrement64(&data.writer_generation);
  std::memset(&data.state, 0, sizeof(data.state));
  MemoryBarrier();
  InterlockedExchange64(&data.epoch, 2);
}

SharedGameplayAimStateWriter::~SharedGameplayAimStateWriter() {
  close_mapping(mapping_, view_);
}

bool SharedGameplayAimStateWriter::publish(
    const SharedGameplayAimState& state) {
  if (!valid_gameplay_aim_state(state)) {
    return false;
  }
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedIncrement64(&data.epoch);
  std::memcpy(&data.state, &state, sizeof(state));
  MemoryBarrier();
  InterlockedIncrement64(&data.epoch);
  return true;
}

SharedGameplayAimStateReader::~SharedGameplayAimStateReader() {
  close_mapping(mapping_, view_);
}

bool SharedGameplayAimStateReader::ensure_open() {
  if (view_) {
    return true;
  }
  mapping_ =
      OpenFileMappingW(FILE_MAP_READ, FALSE, shared_object_name(kSharedGameplayAimStateName).c_str());
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

bool SharedGameplayAimStateReader::read(SharedGameplayAimState& state) {
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
    SharedGameplayAimState candidate{};
    std::memcpy(&candidate, &data.state, sizeof(candidate));
    candidate.transport_generation =
        static_cast<std::uint64_t>(data.writer_generation);
    MemoryBarrier();
    const auto after = data.epoch;
    if (before == after && (after & 1) == 0 &&
        candidate.transport_generation != 0 &&
        valid_gameplay_aim_state(candidate)) {
      state = candidate;
      return true;
    }
  }
  return false;
}

}  // namespace darktidevr::core
