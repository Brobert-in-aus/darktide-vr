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

-- Chat cycles: "chat N" opens and closes stock chat N times, 3 s apart,
-- logging slow frames within a second of each action; bounded to 20.
do
    local hooked
    local chat_mod = {info = mod.info, error = mod.error,
        hook_safe = function(_, class, name, fn) assert(class == "ConstantElementChat" and name == "update"); hooked = fn end}
    Managers.state.game_mode = nil
    local cycles = SessionControl.install(chat_mod)
    local opens, cursor = 0, {}
    local chat = {_input_field_widget = {content = {is_writing = false, input_text = ""}}}
    function chat:_start_chatting(renderer) assert(renderer == "renderer"); opens = opens + 1; self._input_field_widget.content.is_writing = true end
    function chat:_enable_mouse_cursor(value) cursor[#cursor + 1] = value end
    files[SessionControl.QUIT_FLAG] = "chat 2"
    for _ = 1, 30 do cycles.update() end
    assert(files[SessionControl.QUIT_FLAG] == "consumed")
    local before = #infos
    local t = 10
    local function frame(dt) t = t + dt; hooked(chat, dt, t, "renderer") end
    frame(0.016)
    assert(opens == 1 and chat._input_field_widget.content.is_writing)
    frame(0.2) -- a 200 ms frame right after opening is logged
    local spike = infos[#infos]
    assert(spike:find("frame_spike dt_ms=200.0 since_open_ms=200.0", 1, true), spike)
    for _ = 1, 200 do frame(0.016) end -- past the interval: closes once
    assert(not chat._input_field_widget.content.is_writing and cursor[1] == false)
    for _ = 1, 400 do frame(0.016) end -- open and close again, then stop
    assert(opens == 2 and #cursor == 2)
    for _ = 1, 400 do frame(0.016) end
    assert(opens == 2, "cycled past the request")
    frame(0.3) -- long after the last action: not logged
    assert(not infos[#infos]:find("dt_ms=300", 1, true))
    assert(#infos - before >= 5)

    -- Probes toggle one engine call without touching chat.
    local clips = {}
    Window = {set_clip_cursor = function(value) clips[#clips + 1] = value end}
    files[SessionControl.QUIT_FLAG] = "probe clip 1"
    for _ = 1, 30 do cycles.update() end
    assert(files[SessionControl.QUIT_FLAG] == "consumed")
    for _ = 1, 800 do frame(0.016) end
    assert(#clips == 2 and clips[1] == false and clips[2] == true, "clip probe toggled wrong")
    assert(opens == 2, "a probe opened chat")
    assert(infos[#infos - 0]:find("probe_clip_off remaining=0", 1, true) or infos[#infos - 1]:find("probe_clip_off", 1, true))
    files[SessionControl.QUIT_FLAG] = "probe bogus 2"
    for _ = 1, 30 do cycles.update() end
    assert(files[SessionControl.QUIT_FLAG] == "probe bogus 2", "unknown probe consumed")

    -- "chat N trace" wraps resource creation while cycles run, then restores it.
    local created = 0
    local function stock_create(kind) created = created + 1; return kind end
    Renderer = {create_resource = stock_create}
    files[SessionControl.QUIT_FLAG] = "chat 1 trace"
    for _ = 1, 30 do cycles.update() end
    assert(Renderer.create_resource ~= stock_create, "trace not installed")
    frame(0.016)
    assert(Renderer.create_resource("render_target") == "render_target" and created == 1)
    assert(infos[#infos]:find("resource call=Renderer.create_resource since_open", 1, true), infos[#infos])
    for _ = 1, 600 do frame(0.016) end
    assert(Renderer.create_resource == stock_create, "trace not restored after the cycles")
end

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
