#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace darktidevr::core {

inline constexpr wchar_t kSharedGeneratedFrameStateName[] =
    L"Local\\DarktideVR-generated-frame-state-v2";
inline constexpr std::size_t kSharedGeneratedFrameSlotCount = 3;

struct SharedGeneratedFrameSlot {
  std::uint64_t sequence{};
  std::uint64_t native_call{};
  std::uint32_t frame_index{};
  std::uint64_t previous_pose{}, current_pose{}, gameplay_generation{}, tick_ms{};
  std::uint64_t rendered_ready{};
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
  explicit SharedGeneratedFrameStateWriter(const wchar_t* name = kSharedGeneratedFrameStateName);
  ~SharedGeneratedFrameStateWriter();

  SharedGeneratedFrameStateWriter(const SharedGeneratedFrameStateWriter&) =
      delete;
  SharedGeneratedFrameStateWriter& operator=(
      const SharedGeneratedFrameStateWriter&) = delete;

  bool publish(std::uint64_t sequence, std::uint64_t native_call,
               std::uint32_t frame_index, std::uint32_t width,
               std::uint32_t height, std::uint32_t format,
               std::uint64_t previous_pose = 0, std::uint64_t current_pose = 0,
               std::uint64_t gameplay_generation = 0, std::uint64_t tick_ms = 0,
               std::uint64_t rendered_ready = 0);

 private:
  void* mapping_{};
  void* view_{};
};

class SharedGeneratedFrameStateReader {
 public:
  explicit SharedGeneratedFrameStateReader(const wchar_t* name = kSharedGeneratedFrameStateName) : name_(name) {}
  ~SharedGeneratedFrameStateReader();

  SharedGeneratedFrameStateReader(const SharedGeneratedFrameStateReader&) =
      delete;
  SharedGeneratedFrameStateReader& operator=(
      const SharedGeneratedFrameStateReader&) = delete;

  bool read(SharedGeneratedFrameState& state);

 private:
  bool ensure_open();
  std::wstring name_;

  void* mapping_{};
  void* view_{};
};

}  // namespace darktidevr::core
