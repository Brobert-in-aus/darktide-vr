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

-- One linear query at a supplied orientation. The rotational planner owns
-- subdivision; callers must sample both orientations and current overlap as
-- appropriate. This function does not claim to cover an entire rotating blade.
function Probe.sweep(world, volume, start_origin, end_origin, rotation,
        filter, rewind_ms, max_hits, end_rotation, query_rotation)
    if world == nil or start_origin == nil or end_origin == nil or rotation == nil or
            type(volume) ~= "table" or not triple(volume.offset, false) or
            type(filter) ~= "string" or filter == "" or
            not finite(rewind_ms) or rewind_ms < 0 or not finite(max_hits) or
            max_hits < 1 or max_hits ~= math.floor(max_hits) or max_hits > 2147483647 then
        return nil, "invalid_context"
    end
    if volume.shape == "oobb" then
        if not triple(volume.half_extents, true) then return nil, "invalid_volume" end
    elseif volume.shape == "sphere" then
        if not finite(volume.radius) or volume.radius <= 0 then return nil, "invalid_volume" end
    else
        return nil, "unsupported_shape"
    end
    local local_offset = Vector3(volume.offset[1],volume.offset[2],volume.offset[3])
    local start_center = start_origin + Quaternion.rotate(rotation, local_offset)
    local end_center = end_origin + Quaternion.rotate(end_rotation or rotation, local_offset)
    local results
    if volume.shape == "oobb" then
        results = PhysicsWorld.linear_obb_sweep(world, start_center, end_center,
            Vector3(volume.half_extents[1],volume.half_extents[2],volume.half_extents[3]),
            query_rotation or rotation, max_hits, "collision_filter", filter, "rewind_ms", rewind_ms,
            "report_initial_overlap")
    else
        results = PhysicsWorld.linear_sphere_sweep(world, start_center, end_center,
            volume.radius, max_hits, "collision_filter", filter, "rewind_ms", rewind_ms,
            "report_initial_overlap")
    end
    if results ~= nil and type(results) ~= "table" then return nil, "invalid_query_result" end
    local count = results and #results or 0
    local contacts = {}
    for i=1,count do
        local hit = results[i]
        local position, normal = hit and hit.position, hit and hit.normal
        if not hit or hit.actor == nil or not position or not normal or
                not finite(position.x) or not finite(position.y) or not finite(position.z) or
                not finite(normal.x) or not finite(normal.y) or not finite(normal.z) or
                not finite(hit.distance) then
            return nil, "invalid_query_result"
        end
        contacts[i] = {actor=hit.actor, distance=hit.distance,
            position={x=position.x,y=position.y,z=position.z},
            normal={x=normal.x,y=normal.y,z=normal.z}}
    end
    return {contacts=contacts, count=count, requested_limit=max_hits,
        saturated=count >= max_hits, capacity_verified=false}
end

-- The stock box query includes a thin cross-section swept along local Z. It
-- produces a contact manifold even when the weapon origin has not moved.
-- Preserve that construction (including legacy volume offsets), rather than
-- fabricating hit normals from the actor-only immediate overlap.
function Probe.contact_scan(world, volume, origin, rotation, filter, rewind_ms, max_hits)
    if type(volume) ~= "table" or not triple(volume.offset, false) or
            origin == nil or rotation == nil then return nil, "invalid_context" end
    if volume.shape == "sphere" then
        return Probe.sweep(world,volume,origin,origin,rotation,filter,rewind_ms,max_hits)
    end
    if volume.shape ~= "oobb" or not triple(volume.half_extents, true) then
        return nil, "invalid_volume"
    end
    local offset, half = volume.offset, volume.half_extents
    local first = origin + Quaternion.rotate(rotation,Vector3(offset[1],offset[2],offset[3]-half[3]))
    local last = origin + Quaternion.rotate(rotation,Vector3(offset[1],offset[2],offset[3]+half[3]))
    return Probe.sweep(world,{shape="oobb",offset={0,0,0},
        half_extents={half[1],half[2],.0001}},first,last,rotation,filter,rewind_ms,max_hits)
end

return Probe
