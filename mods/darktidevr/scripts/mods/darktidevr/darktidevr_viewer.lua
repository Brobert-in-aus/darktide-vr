-- The headset viewer is a child process of the game, started by the native
-- module beside which it is installed. A plain Steam launch therefore reaches
-- the headset without a launcher script. This module asks for the start once
-- the game loop runs, reports the process state, and offers a chat command
-- for a manual restart.
local Viewer = {}

local state = {
    mod = nil,
    native = nil,
    values = nil,
    requested = false,
    poll_t = 0,
    running = nil,
    bootstrap_missing_logged = false,
}

local function native()
    if state.native then
        return state.native
    end
    local accessor = state.native_accessor
    state.native = accessor and accessor() or nil
    if state.native and not state.values then
        local ffi = Mods and Mods.lua and Mods.lua.ffi
        state.values = ffi and ffi.new("int[8]") or nil
    end
    return state.native
end

-- The d3d12 bootstrap installs the native module at device creation. Without
-- it (flat mode, or a proxy that failed to load) the viewer must not start:
-- it would wait for a producer that never publishes.
local function bootstrap_active()
    local module = native()
    if not module or not state.values then
        return false
    end
    local ok, result = pcall(function()
        return module.dtvr_bootstrap_state()
    end)
    return ok and tonumber(result) == 1
end

local function read_state()
    local module = native()
    if not module or not state.values then
        return nil
    end
    local ok, result = pcall(function()
        return module.dtvr_viewer_state(state.values, 8)
    end)
    if not ok or tonumber(result) ~= 0 then
        return nil
    end
    return {
        running = state.values[0] == 1,
        exit_code = tonumber(state.values[1]),
        starts = tonumber(state.values[2]),
        last_error = tonumber(state.values[3]),
        installed = state.values[4] == 1,
    }
end

function Viewer.control(enabled)
    local module = native()
    if not module then
        return false, "native_unavailable"
    end
    local ok, result = pcall(function()
        return module.dtvr_viewer_control(enabled and 1 or 0)
    end)
    if not ok then
        return false, tostring(result)
    end
    local code = tonumber(result)
    if code ~= 0 then
        local current = read_state()
        state.mod:error(
            "DARKTIDEVR_VIEWER control=%s failed code=%d win32=%s installed=%s",
            enabled and "start" or "stop", code,
            current and tostring(current.last_error) or "?",
            current and tostring(current.installed) or "?")
        return false, "code_" .. tostring(code)
    end
    state.mod:info("DARKTIDEVR_VIEWER control=%s accepted",
        enabled and "start" or "stop")
    -- A stop asked for by the mod (quit, the chat command) is not a failure.
    state.stopped_on_request = not enabled
    return true
end

function Viewer.state()
    return read_state()
end

-- Polling counts updates rather than reading a clock: the mod update runs
-- every frame and the state rarely changes.
local POLL_UPDATES = 120
Viewer.RESTART_LIMIT = 3
Viewer.RESTART_WINDOW = 120 * 60 * 5 -- updates (about five minutes)

-- Development runs that start their own viewer (a synthetic controller path,
-- the OpenXR simulator runtime) write "external" into this file before the
-- launch; a second viewer would compete for the OpenXR session. Players never
-- have the file, so the game starts its viewer as usual.
Viewer.EXTERNAL_FLAG = "./../mods/darktidevr/darktidevr_external_viewer.flag"

function Viewer.external_requested()
    local files = Mods and Mods.lua and Mods.lua.io
    local flag = files and files.open(Viewer.EXTERNAL_FLAG, "r")
    if not flag then
        return false
    end
    local value = flag:read("*all")
    flag:close()
    return type(value) == "string" and value:match("^%s*external%s*$") ~= nil
end

function Viewer.update()
    if not state.requested then
        if not native() then
            return
        end
        state.requested = true
        if Viewer.external_requested() then
            state.mod:info("DARKTIDEVR_VIEWER start=skipped reason=external_viewer_flag")
        elseif bootstrap_active() then
            Viewer.control(true)
        elseif not state.bootstrap_missing_logged then
            state.bootstrap_missing_logged = true
            state.mod:info(
                "DARKTIDEVR_VIEWER start=skipped reason=bootstrap_inactive")
        end
        state.poll_t = 0
        return
    end
    state.poll_t = state.poll_t + 1
    state.update_count = (state.update_count or 0) + 1
    if state.poll_t < POLL_UPDATES then
        return
    end
    state.poll_t = 0
    local current = read_state()
    if not current or current.running == state.running then
        return
    end
    local was_running = state.running
    state.running = current.running
    state.mod:info(
        "DARKTIDEVR_VIEWER running=%s exit_code=%d starts=%d installed=%s",
        tostring(current.running), current.exit_code, current.starts,
        tostring(current.installed))
    -- A viewer that fails mid-game (14 September: an intermittent D3D12
    -- command-list failure) leaves the headset dark until someone types
    -- /dtvr_viewer restart. Restart it automatically, at most
    -- RESTART_LIMIT times per RESTART_WINDOW updates; a clean exit (0) or a
    -- stop the mod asked for is left alone.
    if was_running and not current.running and current.exit_code ~= 0 and
            not state.stopped_on_request then
        state.update_count = state.update_count or 0
        state.restarts = state.restarts or {}
        local recent = {}
        for _, at in ipairs(state.restarts) do
            if state.update_count - at < Viewer.RESTART_WINDOW then recent[#recent + 1] = at end
        end
        state.restarts = recent
        if #recent < Viewer.RESTART_LIMIT then
            recent[#recent + 1] = state.update_count
            state.mod:info("DARKTIDEVR_VIEWER restart=automatic exit_code=%d attempt=%d",
                current.exit_code, #recent)
            Viewer.control(true)
        elseif not state.restart_limit_logged then
            state.restart_limit_logged = true
            state.mod:info("DARKTIDEVR_VIEWER restart=gave_up exit_code=%d attempts=%d", current.exit_code, #recent)
        end
    end
end

function Viewer.install(mod, native_accessor)
    state.mod = mod
    state.native_accessor = native_accessor
    mod:command("dtvr_viewer", "Start, stop or restart the VR viewer: /dtvr_viewer start|stop|restart|status", function(action)
        action = action or "status"
        if action == "restart" then
            Viewer.control(false)
            Viewer.control(true)
        elseif action == "start" or action == "stop" then
            Viewer.control(action == "start")
        end
        local current = read_state()
        if current then
            mod:echo(string.format(
                "VR viewer running=%s exit_code=%d starts=%d installed=%s",
                tostring(current.running), current.exit_code, current.starts,
                tostring(current.installed)))
        else
            mod:echo("VR viewer state unavailable")
        end
    end)
    return Viewer
end

return Viewer
