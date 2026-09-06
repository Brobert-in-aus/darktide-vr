-- Mission attack preparation can use hand poses only when this process owns
-- the simulation. A remote server does not run our local action hooks.
local Context = {}
local ranges = {shooting_range=true, training_grounds=true}
local missions = {coop_complete_objective=true, survival=true, expedition=true, prologue=true}

function Context.local_authority(session)
    if not session or type(session.is_server) ~= "function" then return false end
    local ok, server = pcall(session.is_server, session)
    return ok and server == true
end

function Context.aim_mode(mode, session)
    if ranges[mode] then return true end
    return missions[mode] == true and Context.local_authority(session)
end

function Context.body_mode(mode, session)
    return mode == "hub" or Context.aim_mode(mode, session)
end

return Context
