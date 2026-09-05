-- Engine hit-zone adapter for the offline physical-melee prototype. Not live.
local HitZone = require("scripts/utilities/attack/hit_zone")
local SweepSettings = require("scripts/settings/equipment/action_sweep_settings")
local Resolver = {}

function Resolver.resolve(hit, context)
    if type(hit) ~= "table" or hit.actor == nil or type(context) ~= "table" or
            context.attacker == nil or context.attacker_position == nil or
            type(context.action) ~= "table" or type(context.target_key) ~= "function" then
        return nil, "invalid_context"
    end
    local unit = Actor.unit(hit.actor)
    if unit == nil or not ALIVE[unit] or unit == context.attacker then
        return nil, "ineligible_unit"
    end
    local zone = HitZone.get(unit, hit.actor)
    if not zone then
        -- Scenery/props without a combat hit zone still belong to the caller's
        -- obstruction handling. No resolved combat contact is not an empty ray.
        return nil, "unresolved_hit_zone"
    end
    local priorities = context.action.hit_zone_priority or SweepSettings.default_hit_zone_priority
    local priority = priorities[zone.name]
    local dynamic = SweepSettings.hit_zone_priority_functions[zone.name]
    if dynamic then
        priority = dynamic(unit, context.attacker_position, priority)
    end
    if type(priority) ~= "number" or priority ~= priority or priority == -math.huge then
        return nil, "unresolved_priority"
    end
    local key = context.target_key(unit)
    if key == nil or key == false then return nil, "unregistered_target" end
    -- No head-facing rejection and no cooldown test here. Shield priority must
    -- be resolved even when that enemy is currently ineligible for more damage.
    return {target=key, actor=hit.actor, hit_zone=zone.name, priority=priority,
        position=hit.position, normal=hit.normal}
end

return Resolver
