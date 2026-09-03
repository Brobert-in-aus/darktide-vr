#include "core/shared_generated_frame_state.h"

#include <Windows.h>

#include <limits>
#include <stdexcept>

namespace darktidevr::core {
namespace {

struct SharedSlotLayout {
  volatile LONG64 sequence{};
  volatile LONG64 native_call{};
  volatile LONG frame_index{};
};

struct SharedLayout {
  volatile LONG64 epoch{};
  volatile LONG64 writer_generation{};
  volatile LONG64 latest_sequence{};
  volatile LONG width{};
  volatile LONG height{};
  volatile LONG format{};
  SharedSlotLayout slots[kSharedGeneratedFrameSlotCount]{};
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

bool valid_generated_frame_state(const SharedGeneratedFrameState& state) {
  if (state.transport_generation == 0 || state.latest_sequence == 0 ||
      state.width == 0 || state.width > 16384 || state.height == 0 ||
      state.height > 16384 || state.format == 0) {
    return false;
  }
  const auto& latest = state.slots[generated_frame_slot(
      state.latest_sequence)];
  return latest.sequence == state.latest_sequence && latest.native_call != 0;
}

SharedGeneratedFrameStateWriter::SharedGeneratedFrameStateWriter() {
  mapping_ = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
                                0, sizeof(SharedLayout),
                                kSharedGeneratedFrameStateName);
  if (!mapping_) {
    throw std::runtime_error(
        "CreateFileMapping(shared generated frame state) failed");
  }
  view_ = MapViewOfFile(static_cast<HANDLE>(mapping_), FILE_MAP_ALL_ACCESS, 0,
                        0, sizeof(SharedLayout));
  if (!view_) {
    close_mapping(mapping_, view_);
    throw std::runtime_error(
        "MapViewOfFile(shared generated frame state) failed");
  }
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedExchange64(&data.epoch, 1);
  InterlockedIncrement64(&data.writer_generation);
  InterlockedExchange64(&data.latest_sequence, 0);
  data.width = 0;
  data.height = 0;
  data.format = 0;
  for (auto& slot : data.slots) {
    slot.sequence = 0;
    slot.native_call = 0;
    slot.frame_index = 0;
  }
  MemoryBarrier();
  InterlockedExchange64(&data.epoch, 2);
}

SharedGeneratedFrameStateWriter::~SharedGeneratedFrameStateWriter() {
  close_mapping(mapping_, view_);
}

bool SharedGeneratedFrameStateWriter::publish(
    std::uint64_t sequence, std::uint64_t native_call,
    std::uint32_t frame_index, std::uint32_t width, std::uint32_t height,
    std::uint32_t format) {
  if (sequence == 0 ||
      sequence > static_cast<std::uint64_t>(
                     (std::numeric_limits<LONG64>::max)()) ||
      native_call == 0 || width == 0 || width > 16384 || height == 0 ||
      height > 16384 || format == 0) {
    return false;
  }
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedIncrement64(&data.epoch);
  data.width = static_cast<LONG>(width);
  data.height = static_cast<LONG>(height);
  data.format = static_cast<LONG>(format);
  auto& slot = data.slots[generated_frame_slot(sequence)];
  InterlockedExchange64(&slot.native_call,
                        static_cast<LONG64>(native_call));
  slot.frame_index = static_cast<LONG>(frame_index);
  InterlockedExchange64(&slot.sequence, static_cast<LONG64>(sequence));
  InterlockedExchange64(&data.latest_sequence,
                        static_cast<LONG64>(sequence));
  MemoryBarrier();
  InterlockedIncrement64(&data.epoch);
  return true;
}

SharedGeneratedFrameStateReader::~SharedGeneratedFrameStateReader() {
  close_mapping(mapping_, view_);
}

bool SharedGeneratedFrameStateReader::ensure_open() {
  if (view_) {
    return true;
  }
  mapping_ = OpenFileMappingW(FILE_MAP_READ, FALSE,
                              kSharedGeneratedFrameStateName);
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

bool SharedGeneratedFrameStateReader::read(
    SharedGeneratedFrameState& state) {
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
    SharedGeneratedFrameState candidate{};
    candidate.transport_generation =
        static_cast<std::uint64_t>(data.writer_generation);
    candidate.latest_sequence =
        static_cast<std::uint64_t>(data.latest_sequence);
    candidate.width = static_cast<std::uint32_t>(data.width);
    candidate.height = static_cast<std::uint32_t>(data.height);
    candidate.format = static_cast<std::uint32_t>(data.format);
    for (std::size_t index = 0; index < candidate.slots.size(); ++index) {
      candidate.slots[index] = {
          static_cast<std::uint64_t>(data.slots[index].sequence),
          static_cast<std::uint64_t>(data.slots[index].native_call),
          static_cast<std::uint32_t>(data.slots[index].frame_index)};
    }
    MemoryBarrier();
    const auto after = data.epoch;
    if (before == after && (after & 1) == 0 &&
        valid_generated_frame_state(candidate)) {
      state = candidate;
      return true;
    }
  }
  return false;
}

}  // namespace darktidevr::core
