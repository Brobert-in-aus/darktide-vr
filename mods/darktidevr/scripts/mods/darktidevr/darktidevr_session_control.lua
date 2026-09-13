-- Development control for unattended runs: a one-shot request file asks the
-- game to quit through the same path as the system menu's Quit button, so a
-- scripted run can end the game normally (and reproduce shutdown behaviour)
-- without typed chat or faked keys. Players never have the file.
local SessionControl = {}

SessionControl.QUIT_FLAG = "./../mods/darktidevr/darktidevr_quit_game.flag"
SessionControl.POLL_UPDATES = 30

local function read_request(files)
    local flag = files.open(SessionControl.QUIT_FLAG, "r")
    if not flag then
        return nil
    end
    local value = flag:read("*all")
    flag:close()
    return value
end

-- Returns the quit route taken, or nil when nothing was requested.
function SessionControl.quit()
    local session = Managers and Managers.multiplayer_session
    local in_gameplay = Managers and Managers.state and Managers.state.game_mode ~= nil
    if in_gameplay and session and session.leave then
        -- In-game Quit (system menu) leaves the session with this reason, and
        -- MechanismLeftSession then calls Application.quit.
        session:leave("quit_game")
        return "multiplayer_session_leave"
    end
    -- Title and character select quit directly, as their Quit buttons do.
    Application.quit()
    return "application_quit"
end

-- Chat cycles (open-chat stutter, 14 September): "chat N" opens chat through
-- the stock start and closes it as Back does, N times, 3 s apart, logging every
-- frame slower than 50 ms within a second of each open or close.
SessionControl.CHAT_INTERVAL = 3
SessionControl.SPIKE_SECONDS = 0.05

-- Probes toggle one engine call on and off instead of the whole chat, to find
-- which part of closing chat stalls a frame: "probe clip N" (Window clip
-- cursor), "probe show N" (Window cursor visibility), "probe cursor N" (the
-- input manager's cursor stack, as chat pushes and pops it).
SessionControl.PROBES = {
    clip = function(on) Window.set_clip_cursor(not on) end,
    show = function(on) Window.set_show_cursor(on) end,
    cursor = function(on)
        if on then
            Managers.input:push_cursor("DarktideVRProbe")
        else
            Managers.input:pop_cursor("DarktideVRProbe")
        end
    end,
}

-- Resource trace (chat stall diagnosis): while cycles run, log every engine
-- resource, GUI and material creation or destruction with its Lua caller.
SessionControl.TRACED = {
    Renderer = {"create_resource", "destroy_resource"},
    World = {"create_world_gui", "create_screen_gui", "destroy_gui", "create_shading_environment",
        "destroy_shading_environment", "create_viewport", "destroy_viewport"},
    Gui = {"create_material"},
    UIRenderer = {"create_resource_renderer", "destroy_resource_renderer", "create_renderer"},
}

function SessionControl.trace_resources(api, mod, on)
    api.traced = api.traced or {}
    local owners = {Renderer = Renderer, World = World, Gui = Gui, UIRenderer = UIRenderer}
    for owner_name, names in pairs(SessionControl.TRACED) do
        -- Named directly: a mod environment reaches engine globals through __index.
        local owner = owners[owner_name]
        for i = 1, #names do
            local name = names[i]
            local key = owner_name .. "." .. name
            local original = api.traced[key]
            if on and not original and type(owner) == "table" and type(owner[name]) == "function" then
                original = owner[name]
                api.traced[key] = original
                owner[name] = function(...)
                    if api.chat_last_t then
                        local info = debug and debug.getinfo and debug.getinfo(2, "Sl")
                        mod:info("DARKTIDEVR_SESSION resource call=%s since_%s caller=%s:%s",
                            key, tostring(api.chat_last_action),
                            info and tostring(info.short_src):match("[^/\\]+$") or "?", info and tostring(info.currentline) or "?")
                    end
                    return original(...)
                end
            elseif not on and original then
                owner[name] = original
                api.traced[key] = nil
            end
        end
    end
end

function SessionControl.chat_step(api, chat, dt, t, ui_renderer, mod)
    if api.chat_watch_until and t <= api.chat_watch_until and dt > SessionControl.SPIKE_SECONDS then
        mod:info("DARKTIDEVR_SESSION frame_spike dt_ms=%.1f since_%s_ms=%.1f",
            dt * 1000, tostring(api.chat_last_action), (t - api.chat_last_t) * 1000)
    end
    if (api.chat_remaining or 0) <= 0 and api.traced and api.chat_watch_until and t > api.chat_watch_until then
        SessionControl.trace_resources(api, mod, false)
    end
    if (api.chat_remaining or 0) <= 0 or t < (api.chat_next_t or 0) then
        return
    end
    local probe = api.probe and SessionControl.PROBES[api.probe]
    if probe then
        api.probe_on = not api.probe_on
        probe(api.probe_on)
        api.chat_last_action = api.probe .. (api.probe_on and "_on" or "_off")
        if not api.probe_on then
            api.chat_remaining = api.chat_remaining - 1
        end
        api.chat_last_t = t
        api.chat_watch_until = t + 1
        api.chat_next_t = t + SessionControl.CHAT_INTERVAL
        mod:info("DARKTIDEVR_SESSION probe_%s remaining=%d t=%.3f", api.chat_last_action, api.chat_remaining, t)
        return
    end
    local widget = chat._input_field_widget
    if not widget or not ui_renderer then
        return
    end
    local writing = widget.content.is_writing == true
    if not writing then
        chat:_start_chatting(ui_renderer)
        api.chat_last_action = "open"
    else
        widget.content.input_text = ""
        widget.content.is_writing = false
        chat:_enable_mouse_cursor(false)
        api.chat_last_action = "close"
        api.chat_remaining = api.chat_remaining - 1
    end
    api.chat_last_t = t
    api.chat_watch_until = t + 1
    api.chat_next_t = t + SessionControl.CHAT_INTERVAL
    mod:info("DARKTIDEVR_SESSION chat_%s remaining=%d t=%.3f", api.chat_last_action, api.chat_remaining, t)
end

function SessionControl.install(mod)
    local api = {updates = 0, requested = false}

    if mod.hook_safe then
        mod:hook_safe("ConstantElementChat", "update", function(self, dt, t, ui_renderer)
            if (api.chat_remaining or 0) > 0 or api.chat_watch_until then
                local ok, err = pcall(SessionControl.chat_step, api, self, dt, t, ui_renderer, mod)
                if not ok then
                    api.chat_remaining = 0
                    mod:error("DARKTIDEVR_SESSION chat_cycle_failed error=%s", tostring(err))
                end
            end
        end)
    end

    function api.update()
        if api.requested then
            return
        end
        api.updates = api.updates + 1
        if api.updates < SessionControl.POLL_UPDATES then
            return
        end
        api.updates = 0
        local files = Mods and Mods.lua and Mods.lua.io
        if not files then
            return
        end
        local value = read_request(files)
        local cycles, trace
        if type(value) == "string" then
            cycles, trace = value:match("^%s*chat%s+(%d+)%s*(%a*)%s*$")
            cycles = tonumber(cycles)
        end
        local probe, probe_cycles
        if type(value) == "string" then
            probe, probe_cycles = value:match("^%s*probe%s+(%a+)%s+(%d+)%s*$")
        end
        if probe and SessionControl.PROBES[probe] then
            cycles = tonumber(probe_cycles)
        else
            probe = nil
        end
        if cycles then
            api.probe = probe
            api.probe_on = false
            local consumed = files.open(SessionControl.QUIT_FLAG, "w")
            if consumed then
                consumed:write("consumed")
                consumed:close()
                api.chat_remaining = math.min(cycles, 20)
                api.chat_next_t = 0
                if trace == "trace" then
                    SessionControl.trace_resources(api, mod, true)
                    local wrapped = 0
                    for _ in pairs(api.traced) do wrapped = wrapped + 1 end
                    mod:info("DARKTIDEVR_SESSION resource_trace wrapped=%d", wrapped)
                end
                mod:info("DARKTIDEVR_SESSION chat_cycle_requested cycles=%d probe=%s",
                    api.chat_remaining, tostring(probe or "none"))
            end
            return
        end
        if type(value) ~= "string" or not value:match("^%s*quit%s*$") then
            return
        end
        -- Consume before acting, so a failed quit is never replayed.
        local consumed = files.open(SessionControl.QUIT_FLAG, "w")
        if not consumed then
            return
        end
        consumed:write("consumed")
        consumed:close()
        api.requested = true
        local ok, route = pcall(SessionControl.quit)
        mod:info("DARKTIDEVR_SESSION quit_requested source=flag route=%s ok=%s",
            tostring(ok and route or "error"), tostring(ok))
        if not ok then
            mod:error("DARKTIDEVR_SESSION quit_failed error=%s", tostring(route))
        end
    end

    return api
end

return SessionControl
