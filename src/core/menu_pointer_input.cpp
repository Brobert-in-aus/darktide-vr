#include "core/menu_pointer_input.h"

#include <cmath>
#include <stdexcept>

namespace darktidevr::core {

std::vector<MenuPointerEvent> MenuPointerInputState::update(
    const MenuPointerInput& input) {
  if (!std::isfinite(input.trigger) || !std::isfinite(input.thumbstick_y) ||
      input.trigger < 0.0F || input.trigger > 1.0F ||
      input.thumbstick_y < -1.0F || input.thumbstick_y > 1.0F) {
    throw std::invalid_argument("Invalid menu pointer input");
  }
  std::vector<MenuPointerEvent> events;
  const auto trigger_down = input.trigger >= 0.55F;
  const auto scroll_direction = input.thumbstick_y >= 0.6F
                                    ? 1
                                    : (input.thumbstick_y <= -0.6F ? -1 : 0);

  if (!input.active) {
    if (active_ && trigger_down_) {
      events.push_back({MenuPointerEventType::button_up});
    }
    active_ = false;
    trigger_down_ = false;
    back_down_ = false;
    scroll_direction_ = 0;
    return events;
  }
  if (!active_) {
    active_ = true;
    trigger_down_ = trigger_down;
    back_down_ = input.back;
    scroll_direction_ = scroll_direction;
    if (input.source_position) {
      events.push_back({MenuPointerEventType::move,
                        input.source_position->first,
                        input.source_position->second});
    }
    return events;
  }

  if (input.source_position) {
    events.push_back({MenuPointerEventType::move, input.source_position->first,
                      input.source_position->second});
  }
  if (trigger_down != trigger_down_) {
    if (trigger_down && input.source_position) {
      events.push_back({MenuPointerEventType::button_down,
                        input.source_position->first,
                        input.source_position->second});
    } else if (!trigger_down) {
      events.push_back({MenuPointerEventType::button_up});
    }
    trigger_down_ = trigger_down && input.source_position.has_value();
  }
  if (input.back && !back_down_) {
    events.push_back({MenuPointerEventType::back});
  }
  back_down_ = input.back;
  if (scroll_direction != 0 && scroll_direction != scroll_direction_) {
    events.push_back(
        {MenuPointerEventType::scroll, 0, 0, scroll_direction});
  }
  scroll_direction_ = scroll_direction;
  return events;
}

}  // namespace darktidevr::core
