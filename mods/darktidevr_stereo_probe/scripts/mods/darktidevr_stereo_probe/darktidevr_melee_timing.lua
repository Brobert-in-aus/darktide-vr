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

-- Resolve a normal cycle from an explicitly observed/validated stock windup.
-- This intentionally rejects chain alternatives and unknown input parsers;
-- callers cannot silently substitute a block cancel or heavy recovery time.
function Timing.from_windup(template, windup_name, scale_for, inverted_kinds, validate)
    local actions = type(template) == "table" and template.actions
    local windup = actions and actions[windup_name]
    if not windup or windup.kind ~= "windup" or type(validate) ~= "function" then
        return nil, "invalid_windup"
    end
    local function destination(name, input, kind)
        local action = actions[name]
        local chain = action and action.allowed_chain_actions and action.allowed_chain_actions[input]
        local target = chain and chain.action_name and actions[chain.action_name]
        if not target or target.kind ~= kind or #chain > 0 or chain.chain_until or
                chain.running_action_state_requirement or not validate(target) then return nil end
        return chain.action_name
    end
    if not validate(windup) then return nil, "unavailable_windup" end
    local light = destination(windup_name,"light_attack","sweep")
    local heavy = destination(windup_name,"heavy_attack","sweep")
    local next_windup = light and destination(light,"start_attack","windup")
    local next_light = next_windup and destination(next_windup,"light_attack","sweep")
    if not light or not heavy or not next_light then return nil, "unsupported_route" end
    local interval, reason = Timing.resolve(actions,{
        {action=light,input="start_attack"},{action=next_windup,input="light_attack"}},
        scale_for,inverted_kinds)
    if not interval then return nil, reason end
    local input = template.action_inputs and template.action_inputs.heavy_attack
    local sequence = input and input.input_sequence
    local hold, release = sequence and sequence[1], sequence and sequence[2]
    if not sequence or #sequence ~= 2 or not hold or not release or
            hold.input ~= "action_one_hold" or hold.value ~= true or
            release.input ~= "action_one_hold" or release.value ~= false or
            not finite(hold.duration) or hold.duration < 0 then
        return nil, "unsupported_heavy_input"
    end
    local charge, charge_reason = Timing.resolve(actions,{
        {action=windup_name,input="heavy_attack",input_ready_after=hold.duration}},
        scale_for,inverted_kinds)
    if not charge then return nil, charge_reason end
    return {light_action=light,heavy_action=heavy,next_light_action=next_light,
        light_interval=interval,heavy_charge=charge}
end

return Timing
