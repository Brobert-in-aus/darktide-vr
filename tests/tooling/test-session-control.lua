-- Unattended run controls: a quit request file ends the game through the
-- system menu's route (session leave in gameplay, Application.quit in menus),
-- once; the viewer skips its own start when an external viewer is flagged.
local SessionControl = dofile(assert(arg[1]))
local Viewer = dofile(assert(arg[2]))

local files = {}
local function file_api()
    return {open = function(path, mode)
        if mode == "r" then
            if files[path] == nil then return nil end
            return {read = function() return files[path] end, close = function() end}
        end
        return {write = function(_, value) files[path] = value end, close = function() end}
    end}
end
Mods = {lua = {io = file_api()}}
local infos, errors = {}, {}
local mod = {info = function(_, format, ...) infos[#infos + 1] = string.format(format, ...) end,
    error = function(_, format, ...) errors[#errors + 1] = string.format(format, ...) end}

local quits, leaves = 0, {}
Application = {quit = function() quits = quits + 1 end}
Managers = {multiplayer_session = {leave = function(_, reason) leaves[#leaves + 1] = reason end}, state = {}}

local control = SessionControl.install(mod)
local function tick(n) for _ = 1, n do control.update() end end

-- Nothing requested: nothing happens, polling is bounded to every 30 updates.
tick(90)
assert(quits == 0 and #leaves == 0 and #infos == 0)
-- Wrong content is ignored and left alone.
files[SessionControl.QUIT_FLAG] = "consumed"
tick(30)
assert(quits == 0 and #leaves == 0 and files[SessionControl.QUIT_FLAG] == "consumed")
-- A menu (no game mode) quits directly, consuming first.
files[SessionControl.QUIT_FLAG] = "quit\n"
tick(29)
assert(quits == 0, "polled before the interval")
tick(1)
assert(quits == 1 and #leaves == 0 and files[SessionControl.QUIT_FLAG] == "consumed")
assert(infos[1]:find("route=application_quit ok=true", 1, true), infos[1])
-- One request per install: a second request is not acted on.
files[SessionControl.QUIT_FLAG] = "quit"
tick(60)
assert(quits == 1 and #infos == 1)

-- Gameplay leaves the session with the system menu's reason.
control = SessionControl.install(mod)
Managers.state.game_mode = {}
files[SessionControl.QUIT_FLAG] = "quit"
tick(30)
assert(#leaves == 1 and leaves[1] == "quit_game" and quits == 1)
assert(infos[2]:find("route=multiplayer_session_leave", 1, true), infos[2])
-- A failing quit is logged, not replayed.
control = SessionControl.install(mod)
Managers.multiplayer_session.leave = function() error("session gone") end
files[SessionControl.QUIT_FLAG] = "quit"
tick(60)
assert(#errors == 1 and errors[1]:find("session gone", 1, true) and files[SessionControl.QUIT_FLAG] == "consumed")

-- Viewer: an external-viewer file means no game-started viewer.
local controls = {}
local native = {dtvr_bootstrap_state = function() return 1 end,
    dtvr_viewer_control = function(enabled) controls[#controls + 1] = enabled; return 0 end,
    dtvr_viewer_state = function() return 0 end}
Mods.lua.ffi = {new = function() return {[0] = 0, 0, 0, 0, 0} end}
Viewer.install({info = mod.info, error = mod.error, command = function() end}, function() return native end)
files[Viewer.EXTERNAL_FLAG] = "external\n"
Viewer.update()
assert(#controls == 0, "the game started a second viewer beside the external one")
assert(infos[#infos]:find("reason=external_viewer_flag", 1, true), infos[#infos])
assert(Viewer.external_requested())
files[Viewer.EXTERNAL_FLAG] = "no"
assert(not Viewer.external_requested())
files[Viewer.EXTERNAL_FLAG] = nil
assert(not Viewer.external_requested())
-- Without the file (every player) the game starts its viewer as before.
local PlayerViewer = dofile(arg[2])
PlayerViewer.install({info = mod.info, error = mod.error, command = function() end}, function() return native end)
PlayerViewer.update()
assert(#controls == 1 and controls[1] == 1, "the player's viewer did not start")
print("session_control=pass quit_once menu_and_gameplay_routes failure_not_replayed external_viewer_skip")
