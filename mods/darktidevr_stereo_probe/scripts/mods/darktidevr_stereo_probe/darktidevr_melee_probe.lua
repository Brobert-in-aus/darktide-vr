-- Non-damaging engine overlap adapter, not imported or hooked by the live mod.
-- Call only with a validated tracking pose mapped to the stock sweep origin.
-- Results are raw actor candidates: no shield/world occlusion, hit-zone choice,
-- authority, cooldown or damage eligibility is implied by an overlap.
local Probe = {}
local function finite(value)
    return type(value) == "number" and value == value and
        value > -math.huge and value < math.huge
end
local function triple(value, positive)
    if type(value) ~= "table" then return false end
    for i=1,3 do
        if not finite(value[i]) or (positive and value[i] <= 0) then return false end
    end
    return true
end

function Probe.overlap(world, volume, origin, rotation, filter, rewind_ms)
    if world == nil or origin == nil or rotation == nil or
            type(volume) ~= "table" or not triple(volume.offset, false) or
            type(filter) ~= "string" or filter == "" or
            not finite(rewind_ms) or rewind_ms < 0 then
        return nil, "invalid_context"
    end
    if volume.shape == "oobb" then
        if not triple(volume.half_extents, true) then return nil, "invalid_volume" end
    elseif volume.shape == "sphere" then
        if not finite(volume.radius) or volume.radius <= 0 then
            return nil, "invalid_volume"
        end
    else
        return nil, "unsupported_shape"
    end
    -- Volume.resolve supplies the centre offset exactly once. The caller must
    -- not supply an origin which has already received that half-length shift.
    local center = origin + Quaternion.rotate(rotation,
        Vector3(volume.offset[1], volume.offset[2], volume.offset[3]))
    local size = volume.radius
    if volume.shape == "oobb" then
        size = Vector3(volume.half_extents[1], volume.half_extents[2],
            volume.half_extents[3])
    end
    local actors, count = PhysicsWorld.immediate_overlap(world,
        "position", center, "rotation", rotation, "size", size,
        "shape", volume.shape, "types", "both", "collision_filter", filter,
        "rewind_ms", rewind_ms)
    if not finite(count) or count < 0 or count ~= math.floor(count) or
            (count > 0 and type(actors) ~= "table") then
        return nil, "invalid_query_result"
    end
    local candidates = {}
    for i=1,count do
        if actors[i] == nil then return nil, "incomplete_query_result" end
        candidates[i] = actors[i]
    end
    -- Snapshot the reusable list now. Actor handles are for this simulation
    -- update only; recheck liveness before use. Do not invent hit normals from
    -- an overlap (unlike stock sweeps, it returns no contact manifold).
    return {actors=candidates, actor_count=count, capacity_verified=false}
end

return Probe
