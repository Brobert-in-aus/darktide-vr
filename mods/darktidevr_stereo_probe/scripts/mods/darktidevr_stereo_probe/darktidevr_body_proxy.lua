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
    hands_only = nil,
    surface_hidden = false,
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

local retained_hand_slots = {
    slot_body_arms = true,
    -- Human glove cosmetics are attachment units owned by the upper-body
    -- slot; Darktide has no separate slot_gear_gloves. The proxy hides the
    -- upper-body surface below and reveals only its /gear_hands/ attachment.
    slot_gear_upperbody = true,
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
    state.hands_only = nil
    state.surface_hidden = false
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
    "j_leftforearmroll1", "j_leftforearmroll2",
    "j_rightshoulder", "j_rightarm", "j_rightforearm",
    "j_rightforearmroll1", "j_rightforearmroll2",
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

local function set_meshes_visible(unit, visible)
    local count = Unit.num_meshes(unit)
    for i = 1, count do
        Unit.set_mesh_visibility(unit, i, visible)
    end
    return count
end

local function apply_hands_only_surface_visibility(unit)
    -- Linked units inherit a recursively hidden parent's visibility. Keep the
    -- proxy skeleton and cosmetic attachment hierarchy alive, but suppress
    -- the unwanted surfaces mesh-by-mesh so the glove skin can still consume
    -- the controller-authored wrist bones.
    Unit.set_unit_visibility(unit, true, false)
    local hidden_meshes = set_meshes_visible(unit, false)

    local spawn_data = state.profile_spawner and
        state.profile_spawner._character_spawn_data
    local slots = spawn_data and spawn_data.slots
    local visible_body_hands = 0
    local visible_body_hand_meshes = 0
    local visible_gloves = 0
    local visible_glove_meshes = 0
    if slots then
        for slot_name, slot in pairs(slots) do
            local slot_unit = slot.unit_3p
            if slot_unit and Unit.alive(slot_unit) then
                -- The human body-skin arms slot is authored as exposed hands
                -- only; the upper-body cosmetic supplies sleeves/gloves. Now
                -- that the complete forearm subtree follows the controller,
                -- the skin no longer stretches back to a stock wrist and can
                -- safely provide the fingers under fingerless cosmetics.
                local is_body_hands = slot_name == "slot_body_arms"
                Unit.set_unit_visibility(slot_unit, true, false)
                local slot_mesh_count = set_meshes_visible(
                    slot_unit, is_body_hands)
                if is_body_hands then
                    visible_body_hands = visible_body_hands + 1
                    visible_body_hand_meshes =
                        visible_body_hand_meshes + slot_mesh_count
                else
                    hidden_meshes = hidden_meshes + slot_mesh_count
                end
                local attachments = slot.attachments_by_unit_3p and
                    slot.attachments_by_unit_3p[slot_unit]
                if attachments then
                    for i = 1, #attachments do
                        local attachment = attachments[i]
                        if attachment and Unit.alive(attachment) then
                            local item_name = slot.item_name_by_unit_3p and
                                slot.item_name_by_unit_3p[attachment]
                            local is_glove = type(item_name) == "string" and
                                string.find(item_name, "/gear_hands/", 1, true) ~= nil
                            Unit.flow_event(attachment, is_glove and
                                "lua_visible" or "lua_hidden")
                            Unit.set_unit_visibility(
                                attachment, is_glove, true)
                            local mesh_count = set_meshes_visible(
                                attachment, is_glove)
                            if is_glove then
                                visible_gloves = visible_gloves + 1
                                visible_glove_meshes =
                                    visible_glove_meshes + mesh_count
                            else
                                hidden_meshes = hidden_meshes + mesh_count
                            end
                        end
                    end
                end
            end
        end
    end

    if not state.surface_hidden then
        state.surface_hidden = true
        print("DARKTIDEVR_IK hand_proxy_surface=skin_and_gloves " ..
            "visible_body_hands=" .. tostring(visible_body_hands) ..
            " visible_body_hand_meshes=" ..
                tostring(visible_body_hand_meshes) ..
            " visible_gloves=" .. tostring(visible_gloves) ..
            " visible_glove_meshes=" .. tostring(visible_glove_meshes) ..
            " hidden_meshes=" .. tostring(hidden_meshes) ..
            " hierarchy=visible source_gloves=hidden")
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

local function spawn(world, source_unit, profile, hands_only)
    safe_destroy()
    state.world = world
    state.source_unit = source_unit
    state.profile = profile
    state.hands_only = hands_only
    state.unit_spawner = UIUnitSpawner:new(world)
    state.profile_spawner = UIProfileSpawner:new(
        "DarktideVRUpperBody", world, nil, state.unit_spawner, false)
    local selected_slots = hands_only and retained_hand_slots or retained_slots
    for slot_name, settings in pairs(ItemSlotSettings) do
        if not selected_slots[slot_name] and
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

function BodyProxy.update(
        world, source_unit, player, enabled, dt, t, hands_only)
    local profile = player_profile(player)
    if not enabled or not world or not source_unit or
            not Unit.alive(source_unit) or not profile then
        -- A failed streaming update deliberately caches the source unit so we
        -- do not respawn and fault on every active frame. Owner disable or
        -- source invalidation is the generation boundary that must clear that
        -- cache; otherwise toggling presentation off and back on in the same
        -- mission can never reacquire a proxy for the unchanged player unit.
        if state.profile_spawner or state.unit_spawner or state.unit or
                state.failed_source_unit then
            safe_destroy()
        end
        return nil
    end
    if state.failed_source_unit == source_unit then
        return nil
    end
    if state.world ~= world or state.source_unit ~= source_unit or
            state.profile ~= profile or state.hands_only ~= hands_only then
        spawn(world, source_unit, profile, hands_only)
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
        if hands_only then
            -- UI/profile visibility and linked-unit propagation can run again
            -- during the frame, so enforce proxy ownership after pose update
            -- on every presentation pass rather than only at spawn time.
            apply_hands_only_surface_visibility(unit)
        end
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
    if not BodyProxy.active() then
        return false
    end
    if state.hands_only then
        return slot_name == "slot_body_arms" or
            slot_name == "slot_gear_upperbody"
    end
    return hidden_source_slots[slot_name] == true
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
