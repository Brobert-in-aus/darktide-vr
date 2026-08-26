#include "core/gameplay_input.h"

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

  const GameplayInputFrame frame{next & ~held_, next, held_ & ~next};
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
