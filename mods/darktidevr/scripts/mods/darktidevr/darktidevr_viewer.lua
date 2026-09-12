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
    return true
end

function Viewer.state()
    return read_state()
end

-- Polling counts updates rather than reading a clock: the mod update runs
-- every frame and the state rarely changes.
local POLL_UPDATES = 120

function Viewer.update()
    if not state.requested then
        if not native() then
            return
        end
        state.requested = true
        if bootstrap_active() then
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
    if state.poll_t < POLL_UPDATES then
        return
    end
    state.poll_t = 0
    local current = read_state()
    if not current or current.running == state.running then
        return
    end
    state.running = current.running
    state.mod:info(
        "DARKTIDEVR_VIEWER running=%s exit_code=%d starts=%d installed=%s",
        tostring(current.running), current.exit_code, current.starts,
        tostring(current.installed))
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
