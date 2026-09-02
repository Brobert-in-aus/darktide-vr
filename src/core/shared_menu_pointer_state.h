#pragma once

#include <cstdint>

namespace darktidevr::core {

inline constexpr wchar_t kSharedMenuPointerStateName[] =
    L"Local\\DarktideVR-menu-pointer-state-v4";

struct SharedMenuPointerState {
  std::uint64_t sequence{};
  std::uint64_t timestamp_ns{};
  std::uint32_t source_x{};
  std::uint32_t source_y{};
  std::uint32_t source_width{};
  std::uint32_t source_height{};
  bool active{};
  bool primary_down{};
  bool back_down{};
  std::int32_t scroll_steps{};
  std::uint32_t primary_press_sequence{};
  std::uint32_t back_press_sequence{};
  std::uint32_t scroll_sequence{};
  std::uint64_t transport_generation{};
};

class SharedMenuPointerStateWriter {
 public:
  SharedMenuPointerStateWriter();
  ~SharedMenuPointerStateWriter();

  SharedMenuPointerStateWriter(const SharedMenuPointerStateWriter&) = delete;
  SharedMenuPointerStateWriter& operator=(
      const SharedMenuPointerStateWriter&) = delete;

  bool publish(const SharedMenuPointerState& state);

 private:
  void* mapping_{};
  void* view_{};
};

class SharedMenuPointerStateReader {
 public:
  SharedMenuPointerStateReader() = default;
  ~SharedMenuPointerStateReader();

  SharedMenuPointerStateReader(const SharedMenuPointerStateReader&) = delete;
  SharedMenuPointerStateReader& operator=(
      const SharedMenuPointerStateReader&) = delete;

  bool read(SharedMenuPointerState& state);

 private:
  bool ensure_open();

  void* mapping_{};
  void* view_{};
};

bool valid_menu_pointer_state(const SharedMenuPointerState& state);

}  // namespace darktidevr::core
