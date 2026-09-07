-- Diagnostic orchestration with explicit dependencies for isolated tests and
-- the opt-in live probe. No cooldown consumption, damage or proc execution.
local Diagnostics = {}

function Diagnostics.new(simulation, planner, probe)
    return {simulation=simulation, planner=planner, probe=probe,
        tick=simulation.new(), previous=nil, previous_time=nil, history_key=nil}
end

local function engine_pose(pose)
    local p, q = pose.position, pose.rotation
    return Vector3(p[1],p[2],p[3]), Quaternion.from_elements(q[1],q[2],q[3],q[4])
end

function Diagnostics.sample(state, request)
    -- A stable history key identifies the weapon/calibration/tracking reference
    -- generation. Change it after recenter or transport restart, never per eye.
    if type(request) ~= "table" or not request.history_key or
            type(request.volume) ~= "table" or type(request.limits) ~= "table" then
        state.previous = nil
        return nil, "invalid_request"
    end
    local accepted, reason = state.simulation.begin_step(state.tick, request.step)
    if not accepted then
        -- Invalid tracking/timing and correction replay break pose continuity.
        -- An ordinary duplicate tick does not. Keep the simulation ledger intact
        -- while preventing recovery from sweeping across an unknown interval.
        if reason == "invalid_tracking" or reason == "resimulation" or
                reason == "nonadvancing_time" or reason == "invalid_step" then
            state.previous = nil
        end
        return nil, reason
    end
    local planner = state.planner
    local current = planner.trajectory(request.pose, request.pose)
    if not current then
        state.previous = nil
        return nil, "invalid_pose"
    end
    current = current.last
    local previous = state.history_key == request.history_key and state.previous or nil
    local trajectory = previous and planner.trajectory(previous, current)
    local plan = planner.make({current_valid=true, previous_valid=trajectory ~= nil,
        dt=state.previous_time and request.step.time-state.previous_time,
        translation=trajectory and trajectory.translation,
        angle=trajectory and trajectory.angle, radius=request.volume.corner_radius}, request.limits)
    -- On an exception/invalid physics result retain the claimed tick but drop
    -- history; a retry must not replay a partially processed simulation update.
    state.previous = nil
    local ok, report, query_reason = pcall(function()
        local position, rotation = engine_pose(current)
        local overlap, overlap_reason = state.probe.overlap(request.world,
            request.volume, position, rotation, request.filter, request.rewind_ms)
        if not overlap then return nil, overlap_reason end
        local result = {overlap=overlap, contacts={}, plan=plan,
            query_count=1, saturated=false, capacity_verified=false}
        local current_contacts, contact_reason = state.probe.contact_scan(request.world,
            request.volume, position, rotation, request.filter, request.rewind_ms, request.max_hits)
        if not current_contacts then return nil, contact_reason end
        result.query_count = result.query_count + 1
        result.saturated = current_contacts.saturated
        for _, contact in ipairs(current_contacts.contacts) do
            result.contacts[#result.contacts+1] = contact
        end
        for segment=1,plan.segments do
            local first = planner.pose_at(trajectory,(segment-1)/plan.segments)
            local last = planner.pose_at(trajectory,segment/plan.segments)
            local start_position, start_rotation = engine_pose(first)
            local end_position, end_rotation = engine_pose(last)
            -- Two fixed orientations per substep, as in the stock box sweep.
            -- Sphere orientation is immaterial, so it needs only one query.
            local rotations = request.volume.shape == "sphere" and
                {start_rotation} or {start_rotation,end_rotation}
            for _, sweep_rotation in ipairs(rotations) do
                local sweep, sweep_reason = state.probe.sweep(request.world,
                    request.volume, start_position, end_position, start_rotation,
                    request.filter, request.rewind_ms, request.max_hits,
                    end_rotation, sweep_rotation)
                if not sweep then return nil, sweep_reason end
                result.query_count = result.query_count + 1
                result.saturated = result.saturated or sweep.saturated
                for _, contact in ipairs(sweep.contacts) do
                    result.contacts[#result.contacts+1] = contact
                end
            end
        end
        return result
    end)
    if not ok then return nil, "query_error", tostring(report) end
    if not report then return nil, query_reason end
    state.previous, state.previous_time, state.history_key = current,
        request.step.time, request.history_key
    return report
end

-- Resolve every raw contact before target deduplication. This is diagnostic
-- selection, not an obstruction/authority/damage-eligibility decision.
function Diagnostics.select_contacts(report, resolver, collector, context)
    if type(report) ~= "table" or type(report.contacts) ~= "table" or
            type(context) ~= "table" or not context.attacker_position then
        return nil, "invalid_selection_context"
    end
    local batch = collector.new()
    local result = {selected=batch.ordered,unresolved={},raw_count=#report.contacts,
        saturated=report.saturated==true,capacity_verified=report.capacity_verified==true,
        damage_eligible=false}
    for _,hit in ipairs(report.contacts) do
        local resolved, reason = resolver.resolve(hit,context)
        if resolved then
            local added, add_reason = collector.add(batch,resolved)
            if not added and add_reason ~= "existing_priority" then
                return nil, "invalid_resolved_contact"
            end
        else
            local position, normal = hit.position, hit.normal
            result.unresolved[#result.unresolved+1] = {reason=reason,actor=hit.actor,
                distance=hit.distance,
                position=position and {x=position.x,y=position.y,z=position.z},
                normal=normal and {x=normal.x,y=normal.y,z=normal.z}}
        end
    end
    return result
end

return Diagnostics
