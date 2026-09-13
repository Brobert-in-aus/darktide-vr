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

function SessionControl.install(mod)
    local api = {updates = 0, requested = false}

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
