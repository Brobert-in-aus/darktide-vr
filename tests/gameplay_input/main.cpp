#include "core/gameplay_input.h"

#include <cmath>
#include <iostream>
#include <stdexcept>

namespace {

using darktidevr::core::GameplayAction;
using darktidevr::core::GameplayInputFrame;
using darktidevr::core::GameplayInputMapper;
using darktidevr::core::SharedControllerState;
using darktidevr::core::gameplay_action_bit;

void expect(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

bool contains(std::uint64_t actions, GameplayAction action) {
  return (actions & gameplay_action_bit(action)) != 0;
}

void expect_edge(const GameplayInputFrame& frame, GameplayAction action,
                 bool pressed, bool held, bool released) {
  expect(contains(frame.pressed, action) == pressed, "unexpected press edge");
  expect(contains(frame.held, action) == held, "unexpected held state");
  expect(contains(frame.released, action) == released,
         "unexpected release edge");
}

}  // namespace

int main() {
  try {
    GameplayInputMapper mapper;
    SharedControllerState state{};

    state.hands[0].thumbstick_x = 0.10F;
    state.hands[0].thumbstick_y = -0.10F;
    auto frame = mapper.update(state, true);
    expect(frame.move_x == 0.0F && frame.move_y == 0.0F,
           "radial locomotion deadzone was not applied");

    state.hands[0].thumbstick_x = 0.6F;
    state.hands[0].thumbstick_y = 0.8F;
    frame = mapper.update(state, true);
    expect(std::abs(frame.move_x - 0.6F) < 0.0001F &&
               std::abs(frame.move_y - 0.8F) < 0.0001F,
           "full-scale analog locomotion changed direction or magnitude");

    state.hands[1].trigger = 0.6F;
    frame = mapper.update(state, true);
    expect_edge(frame, GameplayAction::action_one, true, true, false);

    state.hands[1].trigger = 0.5F;
    frame = mapper.update(state, true);
    expect_edge(frame, GameplayAction::action_one, false, true, false);

    state.hands[1].trigger = 0.4F;
    frame = mapper.update(state, true);
    expect_edge(frame, GameplayAction::action_one, false, false, true);

    state.hands[0].trigger = 1.0F;
    state.hands[1].trigger = 1.0F;
    state.hands[0].squeeze = 1.0F;
    state.hands[1].squeeze = 1.0F;
    state.hands[0].buttons = darktidevr::core::controller_primary |
                             darktidevr::core::controller_secondary |
                             darktidevr::core::controller_stick_click |
                             darktidevr::core::controller_menu;
    state.hands[1].buttons = darktidevr::core::controller_primary |
                             darktidevr::core::controller_secondary |
                             darktidevr::core::controller_stick_click;
    frame = mapper.update(state, true);
    constexpr std::uint64_t all_direct_actions = (1ULL << 11U) - 1ULL;
    expect(frame.pressed == all_direct_actions,
           "not every direct Quest action was reachable");
    expect(frame.held == all_direct_actions,
           "not every direct Quest action was held");

    frame = mapper.update(state, false);
    expect(frame.pressed == 0 && frame.held == 0 &&
               frame.released == all_direct_actions && frame.move_x == 0.0F &&
               frame.move_y == 0.0F,
           "leaving gameplay did not release every action");

    frame = mapper.update(state, false);
    expect(frame.pressed == 0 && frame.held == 0 && frame.released == 0,
           "inactive context repeated release edges");

    state.hands[1].trigger = 0.5F;
    frame = mapper.update(state, true);
    expect_edge(frame, GameplayAction::action_one, false, false, false);
    expect_edge(frame, GameplayAction::jump_dodge, false, false, false);
    frame = mapper.update(state, true);
    expect_edge(frame, GameplayAction::jump_dodge, false, false, false);
    state.hands[1].buttons = 0;
    mapper.update(state, true);
    state.hands[1].buttons = darktidevr::core::controller_primary;
    frame = mapper.update(state, true);
    expect_edge(frame, GameplayAction::jump_dodge, true, true, false);

    GameplayInputMapper restart_mapper;
    SharedControllerState restarted{};
    restarted.transport_generation = 7;
    restarted.hands[1].trigger = 1.0F;
    frame = restart_mapper.update(restarted, true);
    expect_edge(frame, GameplayAction::action_one, false, false, false);
    frame = restart_mapper.update(restarted, true);
    expect_edge(frame, GameplayAction::action_one, false, false, false);
    restarted.transport_generation = 8;
    restarted.hands[1].trigger = 0.0F;
    frame = restart_mapper.update(restarted, true);
    expect_edge(frame, GameplayAction::action_one, false, false, false);
    restarted.hands[1].trigger = 1.0F;
    frame = restart_mapper.update(restarted, true);
    expect_edge(frame, GameplayAction::action_one, true, true, false);
    restarted.transport_generation = 9;
    frame = restart_mapper.update(restarted, true);
    expect_edge(frame, GameplayAction::action_one, false, false, true);
    expect(frame.publisher_changed, "A valid publisher change must identify its cancellation frame");
    frame = restart_mapper.update(restarted, true);
    expect(!frame.publisher_changed && frame.held == 0 && frame.released == 0,
           "The publisher-change signal must be one frame, with inherited holds still blocked");

    // Every held control, not only menu-confirm A, is quarantined on reentry.
    GameplayInputMapper entry_mapper;
    using namespace darktidevr::core;
    SharedControllerState entry{};
    entry.hands[0].trigger=entry.hands[1].trigger=1;
    entry.hands[0].squeeze=entry.hands[1].squeeze=1;
    entry.hands[0].buttons=controller_primary | controller_secondary | controller_stick_click | controller_menu;
    entry.hands[1].buttons=controller_primary | controller_secondary | controller_stick_click;
    frame=entry_mapper.update(entry,true);
    expect(frame.pressed==0 && frame.held==0,"Inherited gameplay levels became actions");
    entry.hands[1].buttons &= ~controller_stick_click;
    entry_mapper.update(entry,true);
    entry.hands[1].buttons |= controller_stick_click;
    frame=entry_mapper.update(entry,true);
    expect(frame.pressed==gameplay_action_bit(GameplayAction::smart_tag) &&
           frame.held==frame.pressed,"Independent tag rearm unblocked another held control");
    entry_mapper.update(entry,false);
    frame=entry_mapper.update(entry,true);
    expect(frame.pressed==0 && frame.held==0,"Menu return reactivated inherited controls");

    std::cout << "gameplay_input.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "gameplay_input: " << error.what() << '\n';
    return 1;
  }
}
