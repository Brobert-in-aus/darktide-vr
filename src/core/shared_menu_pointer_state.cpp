#include "core/shared_menu_pointer_state.h"

#include <Windows.h>

#include <cstring>
#include <limits>
#include <stdexcept>

namespace darktidevr::core {
namespace {

struct SharedLayout {
  volatile LONG64 epoch{};
  SharedMenuPointerState state{};
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

bool valid_menu_pointer_state(const SharedMenuPointerState& state) {
  if (state.sequence == 0 || state.timestamp_ns == 0 ||
      state.sequence >
          static_cast<std::uint64_t>(std::numeric_limits<LONG64>::max())) {
    return false;
  }
  if (!state.active) {
    return true;
  }
  return state.source_width != 0 && state.source_height != 0 &&
         state.source_x < state.source_width &&
         state.source_y < state.source_height;
}

SharedMenuPointerStateWriter::SharedMenuPointerStateWriter() {
  mapping_ = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
                                0, sizeof(SharedLayout),
                                kSharedMenuPointerStateName);
  if (!mapping_) {
    throw std::runtime_error("CreateFileMapping(shared menu pointer) failed");
  }
  view_ = MapViewOfFile(static_cast<HANDLE>(mapping_), FILE_MAP_ALL_ACCESS, 0,
                        0, sizeof(SharedLayout));
  if (!view_) {
    close_mapping(mapping_, view_);
    throw std::runtime_error("MapViewOfFile(shared menu pointer) failed");
  }
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedExchange64(&data.epoch, 1);
  std::memset(&data.state, 0, sizeof(data.state));
  MemoryBarrier();
  InterlockedExchange64(&data.epoch, 2);
}

SharedMenuPointerStateWriter::~SharedMenuPointerStateWriter() {
  close_mapping(mapping_, view_);
}

bool SharedMenuPointerStateWriter::publish(
    const SharedMenuPointerState& state) {
  if (!valid_menu_pointer_state(state)) {
    return false;
  }
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedIncrement64(&data.epoch);
  std::memcpy(&data.state, &state, sizeof(state));
  MemoryBarrier();
  InterlockedIncrement64(&data.epoch);
  return true;
}

SharedMenuPointerStateReader::~SharedMenuPointerStateReader() {
  close_mapping(mapping_, view_);
}

bool SharedMenuPointerStateReader::ensure_open() {
  if (view_) {
    return true;
  }
  mapping_ = OpenFileMappingW(FILE_MAP_READ, FALSE,
                              kSharedMenuPointerStateName);
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

bool SharedMenuPointerStateReader::read(SharedMenuPointerState& state) {
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
    SharedMenuPointerState candidate{};
    std::memcpy(&candidate, &data.state, sizeof(candidate));
    MemoryBarrier();
    const auto after = data.epoch;
    if (before == after && (after & 1) == 0 &&
        valid_menu_pointer_state(candidate)) {
      state = candidate;
      return true;
    }
  }
  return false;
}

}  // namespace darktidevr::core
