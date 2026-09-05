#include "core/menu_pointer_input.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace darktidevr::core {

bool MenuPrimaryInputState::update(
    const SharedPresentationState& presentation, bool menu_active,
    bool pointer_hit, bool down, double time_seconds) {
  if (!menu_active) {
    active_ = armed_ = down_ = false;
    release_time_.reset();
    return false;
  }
  if (!active_ || mode_ != presentation.mode ||
      generation_ != presentation.transport_generation) {
    active_ = true;
    armed_ = false;
    down_ = down;
    mode_ = presentation.mode;
    generation_ = presentation.transport_generation;
    release_time_.reset();
  }
  if (!armed_) {
    if (down) {
      release_time_.reset();
    } else {
      if (!release_time_) release_time_ = time_seconds;
      // A settled release prevents inherited trigger/A holds from clicking.
      // A separate menu-age delay only discards deliberate fresh presses.
      armed_ = time_seconds - *release_time_ >= 0.25;
    }
  }
  const bool pressed = armed_ && pointer_hit && down && !down_;
  down_ = down;
  return pressed;
}

std::vector<MenuPointerEvent> MenuPointerInputState::update(
    const MenuPointerInput& input) {
  if (!std::isfinite(input.trigger) || !std::isfinite(input.thumbstick_y) ||
      !std::isfinite(input.time_seconds) || input.time_seconds < 0.0 ||
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
    back_armed_ = false;
    back_release_start_seconds_ = -1.0;
    scroll_direction_ = 0;
    next_scroll_repeat_time_ = 0.0;
    last_time_seconds_ = input.time_seconds;
    return events;
  }
  if (!active_) {
    active_ = true;
    trigger_down_ = trigger_down;
    back_down_ = input.back;
    back_armed_ = false;
    back_release_start_seconds_ = input.back ? -1.0 : input.time_seconds;
    scroll_direction_ = scroll_direction;
    next_scroll_repeat_time_ = scroll_direction == 0
                                   ? 0.0
                                   : input.time_seconds + 0.35;
    last_time_seconds_ = input.time_seconds;
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
  if (!back_armed_) {
    constexpr double release_settle_seconds = 0.1;
    if (input.back) {
      back_release_start_seconds_ = -1.0;
    } else {
      if (back_release_start_seconds_ < 0.0) {
        back_release_start_seconds_ = input.time_seconds;
      }
      if (input.time_seconds - back_release_start_seconds_ >=
          release_settle_seconds) {
        back_armed_ = true;
      }
    }
  } else if (input.back && !back_down_) {
    events.push_back({MenuPointerEventType::back});
  }
  back_down_ = input.back;
  if (input.time_seconds < last_time_seconds_) {
    next_scroll_repeat_time_ = scroll_direction == 0
                                   ? 0.0
                                   : input.time_seconds + 0.35;
  }
  if (scroll_direction != scroll_direction_) {
    if (scroll_direction != 0) {
      events.push_back(
          {MenuPointerEventType::scroll, 0, 0, scroll_direction});
      next_scroll_repeat_time_ = input.time_seconds + 0.35;
    } else {
      next_scroll_repeat_time_ = 0.0;
    }
  } else if (scroll_direction != 0 &&
             input.time_seconds >= next_scroll_repeat_time_) {
    constexpr double repeat_interval = 0.1;
    const auto elapsed = input.time_seconds - next_scroll_repeat_time_;
    const auto repeats = std::min(
        4, 1 + static_cast<int>(std::floor(elapsed / repeat_interval)));
    events.push_back(
        {MenuPointerEventType::scroll, 0, 0,
         scroll_direction * repeats});
    next_scroll_repeat_time_ += repeats * repeat_interval;
  }
  scroll_direction_ = scroll_direction;
  last_time_seconds_ = input.time_seconds;
  return events;
}

}  // namespace darktidevr::core
