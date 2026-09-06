-- Minimal accepted input-name contract, audited against game source 0f0cb45:
-- scripts/managers/player/player_game_states/input_handler_settings.lua.
-- No game code is required to run the isolated bindings tests.
return {
    actions={"action_one_hold","action_two_hold","weapon_extra_hold",
        "interact_hold","weapon_reload_hold","jump_held","crouching",
        "sprinting","grenade_ability_hold","combat_ability_hold","weapon_inspect_hold"},
    ephemeral_actions={"action_one_pressed","action_one_release","action_two_pressed",
        "action_two_release","weapon_extra_pressed","weapon_extra_release",
        "interact_pressed","weapon_reload_pressed","quick_wield","jump","dodge",
        "crouch","sprint","grenade_ability_pressed","grenade_ability_release",
        "combat_ability_pressed","combat_ability_release",
        "wield_3","wield_3_gamepad","wield_4","wield_5","interact_inspect_pressed"},
}
