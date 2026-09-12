-- Pure policy for the future always-active tracked melee volume. Not installed
-- in the live damage path yet; collision/profile/authority adapters own contact
-- validation before calling accept_contact. No motion or global cadence gate.
local Policy = {}

local function finite(value)
    return type(value) == "number" and value == value and
        value > -math.huge and value < math.huge
end

local function valid_time(now, duration)
    return finite(now) and finite(duration) and duration > 0
end

function Policy.new(now, heavy_charge)
    assert(valid_time(now, heavy_charge), "valid simulation time and charge duration required")
    return {heavy_ready_at=now + heavy_charge, next_hit={}}
end

function Policy.begin_heavy_charge(state, now, heavy_charge)
    assert(valid_time(now, heavy_charge), "valid simulation time and charge duration required")
    -- Starting/restarting a charge cannot erase already owed target cooldowns.
    state.heavy_ready_at = now + heavy_charge
end

function Policy.accept_contact(state, target_generation, now, kind, interval)
    if target_generation == nil or not valid_time(now, interval) or
            (kind ~= "light" and kind ~= "heavy") then
        return false, "invalid_contact"
    end
    if kind == "heavy" and now < state.heavy_ready_at then
        return false, "heavy_charging"
    end
    local ready_at = state.next_hit[target_generation]
    if ready_at and now < ready_at then
        return false, "target_cooldown"
    end
    state.next_hit[target_generation] = now + interval
    return true
end

function Policy.forget_target(state, target_generation)
    -- Only on confirmed despawn/generation removal, never on overlap exit,
    -- hand tracking loss, a menu, recentering, or switching attack mode.
    state.next_hit[target_generation] = nil
end

return Policy
