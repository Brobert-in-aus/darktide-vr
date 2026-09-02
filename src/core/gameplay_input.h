#pragma once

#include "core/shared_controller_state.h"

#include <cstdint>

namespace darktidevr::core {

enum class GameplayAction : std::uint64_t {
  action_one = 1ULL << 0U,
  action_two = 1ULL << 1U,
  weapon_extra = 1ULL << 2U,
  interact_reload = 1ULL << 3U,
  quick_wield = 1ULL << 4U,
  jump_dodge = 1ULL << 5U,
  crouch = 1ULL << 6U,
  sprint = 1ULL << 7U,
  smart_tag = 1ULL << 8U,
  grenade_ability = 1ULL << 9U,
  menu = 1ULL << 10U,
};

constexpr std::uint64_t gameplay_action_bit(GameplayAction action) {
  return static_cast<std::uint64_t>(action);
}

struct GameplayInputFrame {
  std::uint64_t pressed{};
  std::uint64_t held{};
  std::uint64_t released{};
  float move_x{};
  float move_y{};
};

class GameplayInputMapper {
 public:
  GameplayInputFrame update(const SharedControllerState& controllers,
                            bool gameplay_active);
  GameplayInputFrame reset();

 private:
  std::uint64_t transport_generation_{};
  std::uint64_t held_{};
  bool left_trigger_down_{};
  bool right_trigger_down_{};
  bool left_squeeze_down_{};
  bool right_squeeze_down_{};
};

}  // namespace darktidevr::core
