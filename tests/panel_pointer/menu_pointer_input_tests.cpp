#include "core/menu_pointer_input.h"

#include <stdexcept>

void test_menu_pointer_input() {
  using namespace darktidevr::core;
  MenuPointerInputState state;
  auto events = state.update({true, {{10, 20}}, 1.0F, 0.0F, true});
  if (events.size() != 1 || events[0].type != MenuPointerEventType::move) {
    throw std::runtime_error("Entering menu generated a click/back edge");
  }
  events = state.update({true, {{11, 21}}, 0.0F, 0.7F, false});
  if (events.size() != 3 || events[0].type != MenuPointerEventType::move ||
      events[1].type != MenuPointerEventType::button_up ||
      events[2].type != MenuPointerEventType::scroll ||
      events[2].scroll_steps != 1) {
    throw std::runtime_error("Menu edge generation was incorrect");
  }
  events = state.update({true, {{12, 22}}, 0.8F, 0.7F, true});
  if (events.size() != 3 || events[1].type != MenuPointerEventType::button_down ||
      events[2].type != MenuPointerEventType::back) {
    throw std::runtime_error("Menu click/back edges were not generated once");
  }
  events = state.update({false, std::nullopt, 0.0F, 0.0F, false});
  if (events.size() != 1 || events[0].type != MenuPointerEventType::button_up) {
    throw std::runtime_error("Leaving menu did not release held pointer input");
  }
}
