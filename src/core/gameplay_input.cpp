#include "core/gameplay_input.h"

#include <algorithm>
#include <cmath>

namespace darktidevr::core {
namespace {

bool analog_button(float value, bool was_down) {
  return was_down ? value > 0.45F : value >= 0.55F;
}

void set_action(std::uint64_t& actions, GameplayAction action, bool down) {
  if (down) {
    actions |= gameplay_action_bit(action);
  }
}

void apply_radial_deadzone(float raw_x, float raw_y, float& output_x,
                           float& output_y) {
  constexpr float deadzone = 0.20F;
  const auto x = std::clamp(raw_x, -1.0F, 1.0F);
  const auto y = std::clamp(raw_y, -1.0F, 1.0F);
  const auto magnitude = std::sqrt(x * x + y * y);
  if (!std::isfinite(magnitude) || magnitude <= deadzone) {
    output_x = 0.0F;
    output_y = 0.0F;
    return;
  }
  const auto normalized_magnitude = std::min(magnitude, 1.0F);
  const auto scaled_magnitude =
      (normalized_magnitude - deadzone) / (1.0F - deadzone);
  const auto scale = scaled_magnitude / magnitude;
  output_x = x * scale;
  output_y = y * scale;
}

}  // namespace

GameplayInputFrame GameplayInputMapper::update(
    const SharedControllerState& controllers, bool gameplay_active) {
  if (!gameplay_active) {
    return reset();
  }

  const auto& left = controllers.hands[0];
  const auto& right = controllers.hands[1];
  left_trigger_down_ = analog_button(left.trigger, left_trigger_down_);
  right_trigger_down_ = analog_button(right.trigger, right_trigger_down_);
  left_squeeze_down_ = analog_button(left.squeeze, left_squeeze_down_);
  right_squeeze_down_ = analog_button(right.squeeze, right_squeeze_down_);

  std::uint64_t next{};
  set_action(next, GameplayAction::action_one, right_trigger_down_);
  set_action(next, GameplayAction::action_two, left_trigger_down_);
  set_action(next, GameplayAction::weapon_extra, right_squeeze_down_);
  set_action(next, GameplayAction::grenade_ability, left_squeeze_down_);
  set_action(next, GameplayAction::interact_reload,
             (left.buttons & controller_primary) != 0);
  set_action(next, GameplayAction::quick_wield,
             (left.buttons & controller_secondary) != 0);
  set_action(next, GameplayAction::jump_dodge,
             (right.buttons & controller_primary) != 0);
  set_action(next, GameplayAction::crouch,
             (right.buttons & controller_secondary) != 0);
  set_action(next, GameplayAction::sprint,
             (left.buttons & controller_stick_click) != 0);
  set_action(next, GameplayAction::smart_tag,
             (right.buttons & controller_stick_click) != 0);
  set_action(next, GameplayAction::menu,
             (left.buttons & controller_menu) != 0);

  GameplayInputFrame frame{next & ~held_, next, held_ & ~next};
  apply_radial_deadzone(left.thumbstick_x, left.thumbstick_y, frame.move_x,
                        frame.move_y);
  held_ = next;
  return frame;
}

GameplayInputFrame GameplayInputMapper::reset() {
  const GameplayInputFrame frame{0, 0, held_};
  held_ = 0;
  left_trigger_down_ = false;
  right_trigger_down_ = false;
  left_squeeze_down_ = false;
  right_squeeze_down_ = false;
  return frame;
}

}  // namespace darktidevr::core
