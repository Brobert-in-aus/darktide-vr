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
  if (state.sequence == 0 ||
      state.sequence >
          static_cast<std::uint64_t>(std::numeric_limits<LONG64>::max()) ||
      !std::isfinite(state.distance_metres)) {
    return false;
  }
  if (!state.active) {
    return state.distance_metres == 0.0F && !state.hit;
  }
  return state.distance_metres >= 0.05F && state.distance_metres <= 200.0F;
}

SharedGameplayAimStateWriter::SharedGameplayAimStateWriter() {
  mapping_ = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
                                0, sizeof(SharedLayout),
                                kSharedGameplayAimStateName);
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
      OpenFileMappingW(FILE_MAP_READ, FALSE, kSharedGameplayAimStateName);
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
    MemoryBarrier();
    const auto after = data.epoch;
    if (before == after && (after & 1) == 0 &&
        valid_gameplay_aim_state(candidate)) {
      state = candidate;
      return true;
    }
  }
  return false;
}

}  // namespace darktidevr::core
