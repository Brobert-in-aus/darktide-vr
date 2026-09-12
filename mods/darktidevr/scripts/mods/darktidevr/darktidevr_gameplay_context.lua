-- Mission attack preparation can use hand poses only when this process owns
-- the simulation. A remote server does not run our local action hooks.
local Context = {}
local ranges = {shooting_range=true, training_grounds=true}
local missions = {coop_complete_objective=true, survival=true, expedition=true, prologue=true}
local function query_owner(owner, name)
    -- Lookup belongs inside the protected call too: a retiring proxy may throw
    -- from __index before its method is even obtained. Shared helper, no closure
    -- allocation on each frame's authority/ownership query.
    local method = owner[name]
    if type(method) == "function" then return method(owner) end
end

-- Established authority of the live session: true when this process owns the
-- simulation, false when a remote server does, nil when the session is
-- missing, retiring, or answers with anything but a boolean. Only the two
-- established answers admit anything; nil admits nothing.
function Context.authority(session)
    local ok, server = pcall(query_owner, session, "is_server")
    if not ok or type(server) ~= "boolean" then return nil end
    return server
end

function Context.local_authority(session)
    return Context.authority(session) == true
end

-- The owner installs its setting reader here; without one, remote missions
-- are admitted. A failing reader admits nothing.
function Context.remote_missions_allowed() return true end

-- A mission whose simulation a remote (dedicated) server owns. The client
-- keeps stock input, presentation and the stock-input aim route; it never
-- gets the local-authority action-pose overrides or aim-field writes.
function Context.remote_mission(mode, session)
    if missions[mode] ~= true or Context.authority(session) ~= false then return false end
    local ok, allowed = pcall(Context.remote_missions_allowed)
    return ok and allowed == true
end

-- The onboarding hub (prologue_hub) is the hub level with the same player
-- template, locomotion and third-person camera; the mod treats it as the hub.
function Context.game_mode_name(game_mode)
    local ok, name = pcall(query_owner, game_mode, "game_mode_name")
    if not ok or type(name) ~= "string" then return nil end
    if name == "prologue_hub" then return "hub" end
    return name
end

function Context.aim_mode(mode, session)
    if ranges[mode] then return true end
    return missions[mode] == true and Context.local_authority(session)
end

function Context.local_mission(mode, session)
    return missions[mode] == true and Context.local_authority(session)
end

-- Presentation and stock input: the hub, ranges, local missions, and remote
-- missions (whose hand aim then travels only through the stock-input route).
function Context.body_mode(mode, session)
    return mode == "hub" or Context.aim_mode(mode, session) or
        Context.remote_mission(mode, session)
end

function Context.ui_blocks_gameplay(ui)
    -- inputs_in_use() is a key-filter table for stock keyboard input. Query
    -- the actual owner, including chat, HUD and views. A retiring manager
    -- cannot authorize fresh VR input. Scanner display explicitly owns none.
    local ok, using = pcall(query_owner, ui, "using_input")
    return not ok or using ~= false
end

function Context.device_axes(state_machine)
    local ok, name = pcall(query_owner, state_machine, "current_state_name")
    return ok and name == "minigame"
end

function Context.input_service_enabled(input)
    -- Stock HumanGameplay substitutes a null service for UI, ImGui and
    -- cinematics. It remains authoritative even when our stereo mode is active.
    local ok, is_null = pcall(query_owner, input, "is_null_service")
    return ok and is_null == false
end

local function current_input_handler(handler, players)
    local player = players:local_player(1)
    return player ~= nil and handler._player == player and player.input_handler == handler
end

function Context.local_input_handler(handler, players)
    local ok, current = pcall(current_input_handler, handler, players)
    return ok and current == true
end

local function current_input_unit(handler, players)
    if not current_input_handler(handler, players) then return end
    local unit = handler._player.player_unit
    return unit and Unit.alive(unit) and unit or nil
end

function Context.local_input_unit(handler, players)
    local ok, unit = pcall(current_input_unit, handler, players)
    return ok and unit or nil
end

return Context
