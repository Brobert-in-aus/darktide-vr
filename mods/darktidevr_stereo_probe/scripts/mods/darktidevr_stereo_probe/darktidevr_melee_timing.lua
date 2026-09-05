-- Offline timing for an explicitly selected stock attack route. The adapter
-- chooses/validates the route and supplies ActionHandler's effective scale.
local Timing = {}
local function finite(value)
    return type(value) == "number" and value == value and
        value > -math.huge and value < math.huge
end

function Timing.resolve(actions, route, scale_for, inverted_kinds)
    if type(actions) ~= "table" or type(route) ~= "table" or #route == 0 or
            type(scale_for) ~= "function" then
        return nil, "invalid_route"
    end
    local elapsed, destination = 0, nil
    for index, step in ipairs(route) do
        if type(step) ~= "table" then return nil, "invalid_route" end
        local action = actions[step.action]
        local chain = type(action) == "table" and action.allowed_chain_actions and
            action.allowed_chain_actions[step.input]
        if type(chain) ~= "table" or not chain.action_name or not actions[chain.action_name] or
                (index > 1 and destination ~= step.action) then
            return nil, "disconnected_route"
        end
        -- Stock chain_until permits an alternative early window; conditions
        -- and running-state gates require the live handler's own validation.
        if chain.chain_until ~= nil or chain.running_action_state_requirement then
            return nil, "conditional_timing"
        end
        local threshold = chain.chain_time
        if threshold == nil then threshold = 0 end
        -- Relative to this action's entry, accounting for already-held input.
        local input_ready = step.input_ready_after
        if input_ready == nil then input_ready = 0 end
        local scale = scale_for(action)
        if not finite(threshold) or threshold < 0 or not finite(input_ready) or
                input_ready < 0 or not finite(scale) or scale <= 0 then
            return nil, "invalid_timing"
        end
        if scale < 1 and inverted_kinds and inverted_kinds[action.kind] then
            threshold = threshold * scale
        else
            threshold = threshold / scale
        end
        elapsed = elapsed + math.max(threshold, input_ready)
        if not finite(elapsed) then return nil, "invalid_timing" end
        destination = chain.action_name
    end
    if elapsed <= 0 then return nil, "zero_interval" end
    return elapsed, destination
end

return Timing
