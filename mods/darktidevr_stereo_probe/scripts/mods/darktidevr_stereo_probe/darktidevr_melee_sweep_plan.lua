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

local function copy_pose(pose)
    if type(pose) ~= "table" or type(pose.position) ~= "table" or
            type(pose.rotation) ~= "table" then return nil end
    local result = {position={}, rotation={}}
    local norm = 0
    for i=1,4 do
        local value = pose.rotation[i]
        if not finite(value) then return nil end
        result.rotation[i] = value
        norm = norm + value * value
        if i <= 3 then
            if not finite(pose.position[i]) then return nil end
            result.position[i] = pose.position[i]
        end
    end
    if not positive(norm) then return nil end
    norm = math.sqrt(norm)
    for i=1,4 do result.rotation[i] = result.rotation[i] / norm end
    return result
end

-- Scalar snapshots survive engine temporary-vector reuse. Spherical rotation
-- interpolation gives equal angular substeps; this is collision coverage, not
-- an additional smoothing delay on the rendered or attacking hand.
function Plan.trajectory(previous, current)
    local first, last = copy_pose(previous), copy_pose(current)
    if not first or not last then return nil, "invalid_pose" end
    local dot, distance_squared = 0, 0
    for i=1,4 do
        dot = dot + first.rotation[i] * last.rotation[i]
        if i <= 3 then
            local delta = last.position[i] - first.position[i]
            distance_squared = distance_squared + delta * delta
        end
    end
    if not finite(distance_squared) then return nil, "invalid_pose" end
    if dot < 0 then
        for i=1,4 do last.rotation[i] = -last.rotation[i] end
        dot = -dot
    end
    dot = math.max(0, math.min(1, dot))
    return {first=first, last=last, angle=2*math.acos(dot),
        translation=math.sqrt(distance_squared)}
end

function Plan.pose_at(trajectory, fraction)
    if not finite(fraction) or fraction < 0 or fraction > 1 then
        return nil, "invalid_fraction"
    end
    local first, last = trajectory.first, trajectory.last
    local half_angle = trajectory.angle * .5
    local sine = math.sin(half_angle)
    local a, b = 1-fraction, fraction
    if sine > 1e-8 then
        a = math.sin((1-fraction)*half_angle) / sine
        b = math.sin(fraction*half_angle) / sine
    end
    local result, norm = {position={},rotation={}}, 0
    for i=1,4 do
        local value = a*first.rotation[i] + b*last.rotation[i]
        result.rotation[i] = value
        norm = norm + value*value
        if i <= 3 then
            result.position[i] = first.position[i] +
                (last.position[i]-first.position[i])*fraction
        end
    end
    norm = math.sqrt(norm)
    for i=1,4 do result.rotation[i] = result.rotation[i] / norm end
    return result
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
