local UIProfileSpawner = require("scripts/managers/ui/ui_profile_spawner")
local UIUnitSpawner = require("scripts/managers/ui/ui_unit_spawner")
local ItemSlotSettings = require("scripts/settings/item/item_slot_settings")

local BodyProxy = {}

local state = {
    world = nil,
    source_unit = nil,
    profile = nil,
    unit_spawner = nil,
    profile_spawner = nil,
    unit = nil,
    ready = false,
    ready_transition = false,
    failed_source_unit = nil,
    failure = nil,
}

-- The authoritative hub avatar keeps its lower body and gait. The proxy owns
-- only pieces deformed by the VR-authored torso/arm chain. Head and face slots
-- stay absent because the tracked camera lives inside this rig.
local retained_slots = {
    slot_body_arms = true,
    slot_body_torso = true,
    slot_gear_upperbody = true,
    slot_gear_extra_cosmetic = true,
    -- UIProfileSpawner always selects a wielded slot while constructing the
    -- character, even when every visible weapon slot is ignored.  The
    -- unarmed item supplies that required equipment record and has no proxy
    -- geometry of its own.
    slot_unarmed = true,
}

local hidden_source_slots = {
    slot_body_arms = true,
    slot_body_torso = true,
    slot_gear_upperbody = true,
    slot_gear_extra_cosmetic = true,
}

local function safe_destroy()
    if state.profile_spawner then
        pcall(state.profile_spawner.destroy, state.profile_spawner)
    end
    if state.unit_spawner then
        pcall(state.unit_spawner.destroy, state.unit_spawner)
    end
    state.world = nil
    state.source_unit = nil
    state.profile = nil
    state.unit_spawner = nil
    state.profile_spawner = nil
    state.unit = nil
    state.ready = false
    state.ready_transition = false
    state.failed_source_unit = nil
    state.failure = nil
end

-- Once spawned, this rig must not advance a second animation timeline. The
-- hub avatar is the sole gait/root authority; the proxy inherits its current
-- upper-body baseline and the tracked IK pass then modifies that baseline.
-- Calling UIProfileSpawner.update after readiness moved j_hips by 23--25 cm
-- between our authored pose and its private idle pose on every frame.
local inherited_nodes = {
    "j_hips", "j_spine", "j_spine1", "j_spine2", "j_neck", "j_head",
    "j_leftshoulder", "j_leftarm", "j_leftforearm",
    "j_leftforearmroll1", "j_leftforearmroll2", "j_lefthand",
    "j_rightshoulder", "j_rightarm", "j_rightforearm",
    "j_rightforearmroll1", "j_rightforearmroll2", "j_righthand",
}

local function inherit_authoritative_pose(unit, source_unit)
    for i = 1, #inherited_nodes do
        local name = inherited_nodes[i]
        if Unit.has_node(unit, name) and Unit.has_node(source_unit, name) then
            local target = Unit.node(unit, name)
            local source = Unit.node(source_unit, name)
            Unit.set_local_position(
                unit, target, Unit.local_position(source_unit, source))
            Unit.set_local_rotation(
                unit, target, Unit.local_rotation(source_unit, source))
        end
    end
end

local function player_profile(player)
    if not player then
        return nil
    end
    if type(player.profile) == "function" then
        local ok, profile = pcall(player.profile, player)
        if ok and profile then
            return profile
        end
    end
    return player._profile
end

local function spawn(world, source_unit, profile)
    safe_destroy()
    state.world = world
    state.source_unit = source_unit
    state.profile = profile
    state.unit_spawner = UIUnitSpawner:new(world)
    state.profile_spawner = UIProfileSpawner:new(
        "DarktideVRUpperBody", world, nil, state.unit_spawner, false)
    for slot_name, settings in pairs(ItemSlotSettings) do
        if not retained_slots[slot_name] and
                not settings.ignore_character_spawning then
            state.profile_spawner:ignore_slot(slot_name)
        end
    end
    state.profile_spawner:spawn_profile(
        profile,
        Unit.local_position(source_unit, 1),
        Unit.local_rotation(source_unit, 1),
        nil,
        nil,
        nil,
        nil,
        nil,
        false,
        false,
        nil,
        true)
end

function BodyProxy.update(world, source_unit, player, enabled, dt, t)
    local profile = player_profile(player)
    if not enabled or not world or not source_unit or
            not Unit.alive(source_unit) or not profile then
        if state.profile_spawner then
            safe_destroy()
        end
        return nil
    end
    if state.failed_source_unit == source_unit then
        return nil
    end
    if state.world ~= world or state.source_unit ~= source_unit or
            state.profile ~= profile then
        spawn(world, source_unit, profile)
    end
    if not state.ready then
        local update_ok, update_error = pcall(
            state.profile_spawner.update, state.profile_spawner,
            dt or 0, t or 0)
        if not update_ok then
            local failed_source_unit = source_unit
            safe_destroy()
            state.failed_source_unit = failed_source_unit
            state.failure = tostring(update_error)
            print("DARKTIDEVR_IK upper_body_proxy=failed reason=" ..
                state.failure)
            return nil
        end
    end
    local unit = state.profile_spawner:spawned_character_unit()
    if unit and Unit.alive(unit) then
        Unit.set_local_position(unit, 1, Unit.local_position(source_unit, 1))
        Unit.set_local_rotation(unit, 1, Unit.local_rotation(source_unit, 1))
        inherit_authoritative_pose(unit, source_unit)
        World.update_unit_and_children(world, unit)
        state.unit = unit
        if not state.ready then
            state.ready = true
            state.ready_transition = true
        end
        return unit
    end
    return nil
end

function BodyProxy.active()
    return state.ready and state.unit and Unit.alive(state.unit)
end

function BodyProxy.hides_source_slot(slot_name)
    return BodyProxy.active() and hidden_source_slots[slot_name] == true
end

function BodyProxy.consume_ready_transition()
    local transitioned = state.ready_transition
    state.ready_transition = false
    return transitioned
end

function BodyProxy.destroy()
    safe_destroy()
end

return BodyProxy
