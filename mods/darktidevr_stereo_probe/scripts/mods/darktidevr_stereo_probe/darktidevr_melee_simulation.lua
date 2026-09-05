-- Offline simulation ownership for physical melee. No live hooks or damage.
-- Keep this owner for the player's simulation lifetime, across weapon swaps,
-- pose resets and tracking loss. A new controller sequence is NOT a new tick.
local Simulation = {}
local function finite(value)
    return type(value) == "number" and value == value and
        value > -math.huge and value < math.huge
end

function Simulation.new()
    return {last_frame=nil, last_time=nil}
end

function Simulation.begin_step(state, step)
    if type(step) ~= "table" or not finite(step.frame) or step.frame < 0 or
            step.frame ~= math.floor(step.frame) or not finite(step.time) or
            type(step.resimulating) ~= "boolean" or
            type(step.tracking_valid) ~= "boolean" then
        return false, "invalid_step"
    end
    -- Replayed simulation must not spend cooldowns or produce effects again.
    -- The future network adapter must reconcile prediction separately.
    if step.resimulating then return false, "resimulation" end
    if state.last_frame and step.frame <= state.last_frame then
        return false, "repeated_frame"
    end
    if state.last_time and step.time <= state.last_time then
        return false, "nonadvancing_time"
    end
    -- Claim before any queries/effects, including tracking-loss ticks. A failed
    -- query must not permit a partial update to replay damage on a retry.
    state.last_frame, state.last_time = step.frame, step.time
    if not step.tracking_valid then return false, "invalid_tracking" end
    return true
end

return Simulation
