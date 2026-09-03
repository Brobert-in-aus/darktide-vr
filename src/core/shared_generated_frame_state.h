#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace darktidevr::core {

inline constexpr wchar_t kSharedGeneratedFrameStateName[] =
    L"Local\\DarktideVR-generated-frame-state-v1";
inline constexpr std::size_t kSharedGeneratedFrameSlotCount = 3;

struct SharedGeneratedFrameSlot {
  std::uint64_t sequence{};
  std::uint64_t native_call{};
  std::uint32_t frame_index{};
};

struct SharedGeneratedFrameState {
  std::uint64_t transport_generation{};
  std::uint64_t latest_sequence{};
  std::uint32_t width{};
  std::uint32_t height{};
  std::uint32_t format{};
  std::array<SharedGeneratedFrameSlot, kSharedGeneratedFrameSlotCount> slots{};
};

constexpr std::size_t generated_frame_slot(std::uint64_t sequence) noexcept {
  return sequence == 0
             ? 0
             : static_cast<std::size_t>(
                   (sequence - 1) % kSharedGeneratedFrameSlotCount);
}

bool valid_generated_frame_state(const SharedGeneratedFrameState& state);

class SharedGeneratedFrameStateWriter {
 public:
  SharedGeneratedFrameStateWriter();
  ~SharedGeneratedFrameStateWriter();

  SharedGeneratedFrameStateWriter(const SharedGeneratedFrameStateWriter&) =
      delete;
  SharedGeneratedFrameStateWriter& operator=(
      const SharedGeneratedFrameStateWriter&) = delete;

  bool publish(std::uint64_t sequence, std::uint64_t native_call,
               std::uint32_t frame_index, std::uint32_t width,
               std::uint32_t height, std::uint32_t format);

 private:
  void* mapping_{};
  void* view_{};
};

class SharedGeneratedFrameStateReader {
 public:
  SharedGeneratedFrameStateReader() = default;
  ~SharedGeneratedFrameStateReader();

  SharedGeneratedFrameStateReader(const SharedGeneratedFrameStateReader&) =
      delete;
  SharedGeneratedFrameStateReader& operator=(
      const SharedGeneratedFrameStateReader&) = delete;

  bool read(SharedGeneratedFrameState& state);

 private:
  bool ensure_open();

  void* mapping_{};
  void* view_{};
};

}  // namespace darktidevr::core
