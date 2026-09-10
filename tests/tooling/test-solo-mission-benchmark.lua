local install = dofile(arg[1])
package.preload["scripts/managers/ui/ui_manager"] = function() return "UIManager" end
local hooks, settings, logs, starts = {}, {}, {}, 0
local allowed, solo = false, false
local mod = {
    hook_safe = function(_, class, _, fn) hooks[class] = fn end,
    set = function(_, key, value) settings[key] = value end,
    info = function(_, format, ...) logs[#logs + 1] = string.format(format, ...) end,
    can_start_game = function() return allowed end,
    is_soloplay = function() return solo end,
    start_game = function(mode) assert(mode == "normal"); starts = starts + 1 end,
}
assert(not pcall(install, mod, "hub_ship", 3))
assert(not pcall(install, mod, "cm_archives", 3.5))
install(mod, "cm_archives", 3)
Managers = {state={}, player={local_player=function() return nil end}}
hooks.UIManager()
local play = {visible=true, hotspot={disabled=false}}
local view = {_widgets_by_name={play_button={content=play}}}
local null = {}
null.null_service = function() return null end
local input = {null_service=function() return null end}
hooks.MainMenuView(view, 0, 0, input)
assert(starts == 0)
allowed = true
for _, field in ipairs({"_input_disabled", "_profiles_wait_overlay_active", "_server_migration_element"}) do
    view[field] = true
    hooks.MainMenuView(view, 0, 0, input)
    view[field] = nil
end
hooks.MainMenuView(view, 0, 0, nil)
hooks.MainMenuView(view, 0, 0, null)
play.hotspot.disabled = true
hooks.MainMenuView(view, 0, 0, input)
assert(starts == 0)
play.hotspot.disabled = false
hooks.MainMenuView(view, 0, 0, input)
hooks.MainMenuView(view, 0, 0, input)
assert(starts == 1 and settings.choose_mission == "cm_archives" and settings.choose_difficulty == 3)
assert(#logs == 1)
Managers.state.mission = {mission_name=function() return "hub_ship" end}
Managers.player.local_player = function() return {player_unit={}} end
solo = true
hooks.UIManager()
assert(#logs == 1)
Managers.state.mission.mission_name = function() return "cm_archives" end
solo = false
hooks.UIManager()
assert(#logs == 1)
solo = true
hooks.UIManager()
hooks.UIManager()
assert(#logs == 2 and logs[2]:find("host=singleplay", 1, true))
print("solo_mission_benchmark=pass")
