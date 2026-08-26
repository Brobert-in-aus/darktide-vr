#pragma once

#include <cstdint>
#include <optional>
#include <vector>

namespace darktidevr::core {

enum class MenuPointerEventType {
  move,
  button_down,
  button_up,
  scroll,
  back,
};

struct MenuPointerEvent {
  MenuPointerEventType type{};
  std::uint32_t source_x{};
  std::uint32_t source_y{};
  int scroll_steps{};
};

struct MenuPointerInput {
  bool active{};
  std::optional<std::pair<std::uint32_t, std::uint32_t>> source_position;
  float trigger{};
  float thumbstick_y{};
  bool back{};
  double time_seconds{};
};

// Converts level input into UI-owned edges. Entering pointer mode adopts the
// current button levels without generating an action; leaving releases any
// held mouse button so no gameplay input can remain stuck.
class MenuPointerInputState {
 public:
  std::vector<MenuPointerEvent> update(const MenuPointerInput& input);

 private:
  bool active_{};
  bool trigger_down_{};
  bool back_down_{};
  int scroll_direction_{};
  double next_scroll_repeat_time_{};
  double last_time_seconds_{};
};

}  // namespace darktidevr::core
