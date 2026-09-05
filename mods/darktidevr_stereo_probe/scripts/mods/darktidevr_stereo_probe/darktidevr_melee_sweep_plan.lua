-- Offline preparation for tracked melee; not installed in the live mod.
-- The adapter supplies shortest-arc rotation (radians), hilt displacement and
-- the furthest collision-box corner's radius about that hilt, all in game units.
-- This plans queries; it neither performs collision nor grants damage eligibility.
local Plan = {}

local function finite(value)
    return type(value) == "number" and value == value and
        value > -math.huge and value < math.huge
end

local function positive(value)
    return finite(value) and value > 0
end

function Plan.make(sample, limits)
    assert(positive(limits.max_gap) and positive(limits.max_translation) and
        positive(limits.arc_step) and positive(limits.max_segments) and
        limits.max_segments == math.floor(limits.max_segments), "invalid sweep limits")

    if not sample.current_valid then
        return {overlap=false, segments=0, reset=true, reason="invalid_tracking"}
    end
    -- Always overlap a valid current pose, even when no safe history exists.
    local result = {overlap=true, segments=0, reset=true}
    if not sample.previous_valid or sample.discontinuity then
        result.reason = "fresh_pose"
        return result
    end
    if not positive(sample.dt) then
        -- A replay/duplicate simulation step must be handled by the simulation
        -- owner, not converted into another fresh contact or a reverse sweep.
        return {overlap=false, segments=0, reset=true, reason="invalid_time"}
    end
    if not finite(sample.translation) or sample.translation < 0 or
        not finite(sample.angle) or sample.angle < 0 or sample.angle > math.pi or
        not positive(sample.radius) then
        result.reason = "invalid_history"
        return result
    end
    if sample.dt > limits.max_gap or sample.translation > limits.max_translation then
        result.reason = "discontinuity"
        return result
    end

    -- Linear sweeps cover translation. Rotation needs intermediate orientations:
    -- radius * angle bounds any corner's rotational travel over each substep.
    -- This is a spacing bound, NOT proof of exact rotating-box collision coverage.
    -- The physics adapter must validate thin-target contacts between samples.
    local segments = math.max(1, math.ceil(sample.radius * sample.angle / limits.arc_step))
    if segments > limits.max_segments then
        -- Never silently coarsen a fast swing into an inaccurate long sweep.
        -- Keep current overlap; report the dropped history for diagnostic tuning.
        result.reason = "query_budget"
        return result
    end
    result.segments = segments
    result.reset = false
    result.reason = "continuous"
    return result
end

return Plan
