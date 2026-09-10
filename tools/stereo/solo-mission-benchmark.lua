-- Installed only by the reversible simulator runner; no persistent mod entry.
return function(mod, mission_name, difficulty)
    assert(mission_name == "cm_archives", "unsupported benchmark mission")
    assert(type(difficulty) == "number" and difficulty >= 1 and difficulty <= 5
        and difficulty % 1 == 0, "invalid benchmark difficulty")
    local requested, finished = false, false
    mod:hook_safe("MainMenuView", "update", function(view, dt, t, input)
        if requested or finished then return end
        local buttons = view._widgets_by_name
        local play = buttons and buttons.play_button and buttons.play_button.content
        local null = input and input.null_service and input:null_service()
        if not input or input == null or view._input_disabled or
            view._profiles_wait_overlay_active or view._server_migration_element or
            not play or not play.visible or not play.hotspot or play.hotspot.disabled then return end
        if not mod.can_start_game() then return end
        requested = true
        mod:set("choose_mission", mission_name)
        mod:set("choose_difficulty", difficulty)
        mod:set("choose_circumstance", "default")
        mod:set("choose_side_mission", "default")
        mod:set("choose_mission_giver", "default")
        mod:info("DARKTIDEVR_SOLO_BENCHMARK requested mission=%s difficulty=%d", mission_name, difficulty)
        mod.start_game("normal")
    end)
    mod:hook_safe(require("scripts/managers/ui/ui_manager"), "update", function()
        if not requested or finished then return end
        local state = Managers.state
        local mission = state and state.mission
        local player = Managers.player and Managers.player:local_player(1)
        if not mission or mission:mission_name() ~= mission_name or
            not mod.is_soloplay() or not player or not player.player_unit then return end
        finished = true
        mod:info("DARKTIDEVR_SOLO_BENCHMARK ready mission=%s difficulty=%d host=singleplay workload=mission_start_stationary",
            mission_name, difficulty)
    end)
end
