#include "core/menu_pointer_input.h"

#include <stdexcept>

void test_menu_pointer_input() {
  using namespace darktidevr::core;
  MenuPointerInputState state;
  auto events = state.update({true, {{10, 20}}, 1.0F, 0.0F, true, 1.0});
  if (events.size() != 1 || events[0].type != MenuPointerEventType::move) {
    throw std::runtime_error("Entering menu generated a click/back edge");
  }
  events = state.update({true, {{11, 21}}, 0.0F, 0.7F, false, 1.1});
  if (events.size() != 3 || events[0].type != MenuPointerEventType::move ||
      events[1].type != MenuPointerEventType::button_up ||
      events[2].type != MenuPointerEventType::scroll ||
      events[2].scroll_steps != 1) {
    throw std::runtime_error("Menu edge generation was incorrect");
  }
  events = state.update({true, {{11, 21}}, 0.0F, 0.7F, false, 1.21});
  if (events.size() != 1 || events[0].type != MenuPointerEventType::move) {
    throw std::runtime_error("Released Back level did not settle cleanly");
  }
  events = state.update({true, {{12, 22}}, 0.8F, 0.7F, true, 1.3});
  if (events.size() != 3 || events[1].type != MenuPointerEventType::button_down ||
      events[2].type != MenuPointerEventType::back) {
    throw std::runtime_error("Menu click/back edges were not generated once");
  }
  events = state.update({true, {{12, 22}}, 0.8F, 0.7F, true, 1.46});
  if (events.size() != 2 ||
      events[1].type != MenuPointerEventType::scroll ||
      events[1].scroll_steps != 1) {
    throw std::runtime_error("Held menu scroll did not repeat after delay");
  }
  events = state.update({true, {{12, 22}}, 0.8F, 0.7F, true, 1.76});
  if (events.size() != 2 ||
      events[1].type != MenuPointerEventType::scroll ||
      events[1].scroll_steps != 3) {
    throw std::runtime_error("Delayed menu scroll did not catch up safely");
  }
  events = state.update({false, std::nullopt, 0.0F, 0.0F, false, 1.8});
  if (events.size() != 1 || events[0].type != MenuPointerEventType::button_up) {
    throw std::runtime_error("Leaving menu did not release held pointer input");
  }

  MenuPointerInputState transient_back_state;
  events = transient_back_state.update(
      {true, {{20, 30}}, 0.0F, 0.0F, false, 2.0});
  events = transient_back_state.update(
      {true, {{20, 30}}, 0.0F, 0.0F, true, 2.02});
  if (events.size() != 1 || events[0].type != MenuPointerEventType::move) {
    throw std::runtime_error("Menu-entry Back transient was not suppressed");
  }
  transient_back_state.update(
      {true, {{20, 30}}, 0.0F, 0.0F, false, 2.03});
  transient_back_state.update(
      {true, {{20, 30}}, 0.0F, 0.0F, false, 2.14});
  events = transient_back_state.update(
      {true, {{20, 30}}, 0.0F, 0.0F, true, 2.15});
  if (events.size() != 2 || events[1].type != MenuPointerEventType::back) {
    throw std::runtime_error("Settled Back input did not re-arm");
  }
}
