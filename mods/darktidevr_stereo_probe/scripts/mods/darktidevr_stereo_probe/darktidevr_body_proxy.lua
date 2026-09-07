local UIProfileSpawner = require("scripts/managers/ui/ui_profile_spawner")
local UIUnitSpawner = require("scripts/managers/ui/ui_unit_spawner")
local ItemSlotSettings = require("scripts/settings/item/item_slot_settings")
local MasterItems = require("scripts/backend/master_items")

local BodyProxy = {}

function BodyProxy.uses_stock_melee_animation(slot, kind, action, actions)
    if kind == "sweep" or kind == "push" or kind == "melee_explosive" then
        return true
    end
    if kind ~= "windup" then return false end
    if slot == "slot_primary" then return true end
    -- Staff special attacks have ranged-slot windups too. Follow their
    -- declared action transitions instead of classifying every ranged charge
    -- or relying on weapon-specific action names.
    for _, chain in pairs(action and action.allowed_chain_actions or {}) do
        local next_action = actions and actions[chain.action_name]
        if next_action and (next_action.kind == "sweep" or
                next_action.kind == "melee_explosive") then
            return true
        end
    end
    return false
end

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

local rigid_hand_items = {
    left = "content/items/characters/player/human/gear_hands/hmn_gloves_b_left_only",
    right = "content/items/characters/player/human/gear_hands/hmn_gloves_b_right_only",
}

local rigid_hands = {
    left = {},
    right = {},
}

local hidden_source_slots = {
    slot_body_arms = true,
    slot_body_torso = true,
    slot_gear_upperbody = true,
    slot_gear_extra_cosmetic = true,
}

local function safe_destroy()
    for _, hand in pairs(rigid_hands) do
        if hand.profile_spawner then
            pcall(hand.profile_spawner.destroy, hand.profile_spawner)
        end
        if hand.unit_spawner then
            pcall(hand.unit_spawner.destroy, hand.unit_spawner)
        end
        table.clear(hand)
    end
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

local function inverse_quaternion(rotation)
    local x, y, z, w = Quaternion.to_elements(rotation)
    return Quaternion.from_elements(-x, -y, -z, w)
end

local function normalized_anatomical_axis(axis)
    local length_squared = Vector3.length_squared(axis)
    if not (length_squared > 1e-12 and length_squared < math.huge) then
        return nil
    end
    return Vector3.normalize(axis)
end

local function anatomical_hand_rotation(unit, side, target_rotation)
    local hand = rigid_hands[side]
    local target_frame = Quaternion.look(
        Quaternion.right(target_rotation) * -1,
        Quaternion.forward(target_rotation))
    if hand.anatomy_inverse then
        return Quaternion.multiply(target_frame, hand.anatomy_inverse:unbox())
    end
    local hand_name = side == "left" and "j_lefthand" or "j_righthand"
    local middle_name = side == "left" and
        "j_lefthandmiddle1" or "j_righthandmiddle1"
    local index_name = side == "left" and
        "j_lefthandindex1" or "j_righthandindex1"
    local pinky_name = side == "left" and
        "j_lefthandpinky1" or "j_righthandpinky1"
    if not Unit.has_node(unit, hand_name) or
            not Unit.has_node(unit, middle_name) or
            not Unit.has_node(unit, index_name) or
            not Unit.has_node(unit, pinky_name) then
        return nil
    end

    -- Match the accepted articulated-hand solve instead of treating the
    -- authored hand joint's mirrored local axes as the OpenXR grip axes.
    -- Touch grip +Y runs down the handle: fingertips point along -grip-Y,
    -- little-to-index follows grip-forward. The cross(across, longitudinal)
    -- normal maps to -grip-X on BOTH hands: outward on the right, inward on
    -- the left. It is a signed anatomical basis, not always the palm normal.
    -- OpenXR defines grip +X with opposite palm-relative signs by hand, so
    -- adding another left-hand sign flip here would double-mirror the basis.
    local hand_node = Unit.node(unit, hand_name)
    local wrist = Unit.world_position(unit, hand_node)
    local inverse_hand = inverse_quaternion(Unit.world_rotation(unit, hand_node))
    local longitudinal = Quaternion.rotate(inverse_hand,
        Unit.world_position(unit, Unit.node(unit, middle_name)) - wrist)
    local across = Quaternion.rotate(inverse_hand,
        Unit.world_position(unit, Unit.node(unit, index_name)) -
            Unit.world_position(unit, Unit.node(unit, pinky_name)))
    longitudinal = normalized_anatomical_axis(longitudinal)
    across = normalized_anatomical_axis(across)
    if not longitudinal or not across then return nil end
    local palm = normalized_anatomical_axis(Vector3.cross(across, longitudinal))
    -- A partial pose must not permanently poison the cached wrist basis.
    -- Leave calibration unset so the next usable authored pose can retry.
    if not palm then return nil end
    local source_frame = Quaternion.look(palm, across)
    -- Capture the authored basis before importing finger animation. Rebuilding
    -- it from curled fingers would make an open/closed palm rotate the wrist.
    hand.anatomy_inverse = QuaternionBox(inverse_quaternion(source_frame))
    return Quaternion.multiply(target_frame, hand.anatomy_inverse:unbox())
end

local function copy_gameplay_fingers(hand)
    local source = state.source_unit
    if not source or not Unit.alive(source) then
        return
    end
    if not hand.finger_nodes then
        hand.finger_nodes = {}
        for _, suffix in ipairs({"handindex", "handmiddle", "handring",
                "handpinky", "handthumb", "thumb"}) do
            for joint = 1, 4 do
                for _, number in ipairs({tostring(joint), "0" .. joint}) do
                    local name = "j_" .. hand.side .. suffix .. number
                    if Unit.has_node(source, name) and Unit.has_node(hand.unit, name) then
                        hand.finger_nodes[#hand.finger_nodes + 1] = {
                            source = Unit.node(source, name),
                            target = Unit.node(hand.unit, name)
                        }
                    end
                end
            end
        end
        print("DARKTIDEVR_IK finger_animation side=" .. hand.side ..
            " joints=" .. #hand.finger_nodes .. " owner=gameplay")
    end
    for _, node in ipairs(hand.finger_nodes) do
        Unit.set_local_rotation(hand.unit, node.target,
            Unit.local_rotation(source, node.source))
    end
end

local function show_rigid_hand_surface(hand)
    local unit = hand.unit
    Unit.set_unit_visibility(unit, true, false)
    set_meshes_visible(unit, false)
    local spawn_data = hand.profile_spawner._character_spawn_data
    local slots = spawn_data and spawn_data.slots
    local visible_meshes = 0
    if slots then
        for slot_name, slot in pairs(slots) do
            local slot_unit = slot.unit_3p
            if slot_unit and Unit.alive(slot_unit) then
                local item_name = slot.item and slot.item.name
                local visible = slot_name == "slot_gear_upperbody" and
                    type(item_name) == "string" and
                    string.find(item_name, "/gear_hands/", 1, true) ~= nil
                Unit.set_unit_visibility(slot_unit, true, false)
                local mesh_count = set_meshes_visible(slot_unit, visible)
                if visible then
                    visible_meshes = visible_meshes + mesh_count
                end
                local attachments = slot.attachments_by_unit_3p and
                    slot.attachments_by_unit_3p[slot_unit]
                if attachments then
                    for i = 1, #attachments do
                        local attachment = attachments[i]
                        if attachment and Unit.alive(attachment) then
                            Unit.set_unit_visibility(attachment, false, true)
                            set_meshes_visible(attachment, false)
                        end
                    end
                end
            end
        end
    end
    if not hand.surface_logged then
        hand.surface_logged = true
        print("DARKTIDEVR_IK rigid_hand_surface side=" .. hand.side ..
            " visible_meshes=" .. tostring(visible_meshes) ..
            " item=" .. rigid_hand_items[hand.side])
    end
end

local function spawn_rigid_hand(world, source_unit, profile, side)
    local hand = rigid_hands[side]
    hand.side = side
    hand.unit_spawner = UIUnitSpawner:new(world)
    hand.profile_spawner = UIProfileSpawner:new(
        "DarktideVRRigidHand_" .. side,
        world, nil, hand.unit_spawner, false)
    for slot_name, settings in pairs(ItemSlotSettings) do
        if slot_name ~= "slot_gear_upperbody" and
                slot_name ~= "slot_unarmed" and
                not settings.ignore_character_spawning then
            hand.profile_spawner:ignore_slot(slot_name)
        end
    end
    local item = MasterItems.get_item(rigid_hand_items[side])
    if not item then
        hand.failure = "item_unavailable"
        return
    end
    local spawned_profile = table.clone_instance(profile)
    spawned_profile.loadout = table.clone_instance(profile.loadout)
    spawned_profile.loadout.slot_gear_upperbody = item
    hand.profile_spawner:spawn_profile(
        spawned_profile,
        Unit.local_position(source_unit, 1),
        Unit.local_rotation(source_unit, 1),
        nil, nil, nil, nil, nil, false, false, nil, true)
end

local function spawn_rigid_hands(world, source_unit, profile)
    safe_destroy()
    state.world = world
    state.source_unit = source_unit
    state.profile = profile
    state.hands_only = true
    spawn_rigid_hand(world, source_unit, profile, "left")
    spawn_rigid_hand(world, source_unit, profile, "right")
end

local function update_rigid_hand(hand, dt, t)
    if hand.failure then
        return nil
    end
    if not hand.ready then
        local ok, error_message = pcall(
            hand.profile_spawner.update, hand.profile_spawner,
            dt or 0, t or 0)
        if not ok then
            hand.failure = tostring(error_message)
            print("DARKTIDEVR_IK rigid_hand=failed side=" .. hand.side ..
                " reason=" .. hand.failure)
            return nil
        end
        -- Unit creation precedes the spawner's final streaming/visibility and
        -- pending-animation work. Keep updating until stock reports readiness.
        if not hand.profile_spawner:spawned() then return nil end
    end
    local unit = hand.profile_spawner:spawned_character_unit()
    if unit and Unit.alive(unit) then
        hand.unit = unit
        if not hand.ready then show_rigid_hand_surface(hand) end
        hand.ready = true
        return unit
    end
    return nil
end

local function place_rigid_hand(world, hand, target_position, target_rotation,
        authored_rotation)
    local unit = hand.unit
    local hand_name = hand.side == "left" and "j_lefthand" or "j_righthand"
    if not hand.ready or not unit or not Unit.alive(unit) or
            not target_position or not target_rotation or
            not Unit.has_node(unit, hand_name) then
        return false
    end
    local hand_node = Unit.node(unit, hand_name)
    local desired_hand_rotation = anatomical_hand_rotation(
        unit, hand.side, target_rotation)
    if not desired_hand_rotation then
        return false
    end
    if authored_rotation then
        desired_hand_rotation = target_rotation
    end
    copy_gameplay_fingers(hand)
    local root_rotation = Unit.world_rotation(unit, 1)
    local relative_rotation = Quaternion.multiply(
        inverse_quaternion(root_rotation),
        Unit.world_rotation(unit, hand_node))
    local desired_root_rotation = Quaternion.multiply(
        desired_hand_rotation, inverse_quaternion(relative_rotation))
    Unit.set_local_rotation(unit, 1, desired_root_rotation)
    World.update_unit_and_children(world, unit)
    local root_position = Unit.local_position(unit, 1)
    Unit.set_local_position(unit, 1,
        root_position + target_position - Unit.world_position(unit, hand_node))
    World.update_unit_and_children(world, unit)
    show_rigid_hand_surface(hand)
    hand.placement_count = (hand.placement_count or 0) + 1
    if hand.placement_count == 1 or hand.placement_count % 600 == 0 then
        local wrist = Unit.world_position(unit, hand_node)
        hand.render_check_position = Vector3Box(wrist)
        hand.render_check_rotation = QuaternionBox(Unit.world_rotation(unit, hand_node))
        local spawn_data = hand.profile_spawner._character_spawn_data
        local slot = spawn_data and spawn_data.slots and
            spawn_data.slots.slot_gear_upperbody
        local glove = slot and slot.unit_3p
        local glove_error = -1
        if glove and Unit.alive(glove) and Unit.has_node(glove, hand_name) then
            glove_error = Vector3.length(
                Unit.world_position(glove, Unit.node(glove, hand_name)) - wrist)
        end
        local scale = Unit.local_scale(unit, 1)
        print(string.format(
            "DARKTIDEVR_IK rigid_hand_pose side=%s samples=%d wrist_error_m=%.6f glove_joint_error_m=%.6f root_scale=%.4f,%.4f,%.4f",
            hand.side, hand.placement_count,
            Vector3.length(wrist - target_position), glove_error,
            Vector3.x(scale), Vector3.y(scale), Vector3.z(scale)))
    end
    return true
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
    local selected_slots = retained_slots
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
                rigid_hands.left.profile_spawner or
                rigid_hands.right.profile_spawner or
                state.failed_source_unit then
            safe_destroy()
        end
        return nil
    end
    if state.failed_source_unit == source_unit then
        return nil
    end
    if hands_only then
        if state.world ~= world or state.source_unit ~= source_unit or
                state.profile ~= profile or not state.hands_only then
            spawn_rigid_hands(world, source_unit, profile)
        end
        local left_unit = update_rigid_hand(rigid_hands.left, dt, t)
        local right_unit = update_rigid_hand(rigid_hands.right, dt, t)
        if state.ready and (not left_unit or not right_unit) then
            -- Retire the pair together so fallback source hands cannot overlap
            -- a surviving glove. Reuse the failed-owner quarantine until a
            -- source/enable transition instead of respawning every frame.
            safe_destroy()
            state.failed_source_unit = source_unit
            state.failure = "rigid_hand_unit_lost"
            print("DARKTIDEVR_IK rigid_hands=failed reason=" .. state.failure)
            return nil
        end
        if left_unit and right_unit and not state.ready then
            state.ready = true
            state.ready_transition = true
            state.unit = left_unit
            print("DARKTIDEVR_IK rigid_hands=ready geometry=one_sided_profile_roots")
        end
        return left_unit or right_unit
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
    if state.hands_only then
        local left, right = rigid_hands.left, rigid_hands.right
        return state.ready and left.ready and right.ready and
            left.unit ~= nil and right.unit ~= nil and
            Unit.alive(left.unit) and Unit.alive(right.unit)
    end
    return state.ready and state.unit and Unit.alive(state.unit)
end

function BodyProxy.rigid_hands_active()
    return state.hands_only and BodyProxy.active()
end

function BodyProxy.check_rigid_hands_before_render()
    for side, hand in pairs(rigid_hands) do
        if hand.render_check_position and hand.unit and Unit.alive(hand.unit) then
            local node = Unit.node(hand.unit,
                side == "left" and "j_lefthand" or "j_righthand")
            local drift = Vector3.length(Unit.world_position(hand.unit, node) -
                hand.render_check_position:unbox())
            local ax, ay, az, aw = Quaternion.to_elements(
                hand.render_check_rotation:unbox())
            local bx, by, bz, bw = Quaternion.to_elements(
                Unit.world_rotation(hand.unit, node))
            local dot = math.min(1, math.abs(ax * bx + ay * by + az * bz + aw * bw))
            print(string.format(
                "DARKTIDEVR_IK rigid_hand_prerender side=%s position_drift_m=%.6f rotation_drift_deg=%.4f",
                side, drift, 2 * math.acos(dot) * 180 / math.pi))
            hand.render_check_position = nil
            hand.render_check_rotation = nil
        end
    end
end

function BodyProxy.place_rigid_hands(
        world, left_position, left_rotation, right_position, right_rotation)
    if not BodyProxy.rigid_hands_active() then
        return nil, nil, false
    end
    local left_written = place_rigid_hand(
        world, rigid_hands.left, left_position, left_rotation)
    local right_written = place_rigid_hand(
        world, rigid_hands.right, right_position, right_rotation)
    return rigid_hands.left.unit, rigid_hands.right.unit,
        left_written or right_written
end

function BodyProxy.follow_gameplay_hands(world, aim_rotation)
    local source = state.source_unit
    if not BodyProxy.rigid_hands_active() or not source or not Unit.alive(source) then
        return false
    end
    -- The third-person hand nodes also receive the VR equipment attachment
    -- writes. Read the untouched first-person animation rig instead, otherwise
    -- the previous VR pose becomes the next frame's supposedly authored input.
    local first_person = ScriptUnit.has_extension(source, "first_person_system")
    local animation_source = first_person and first_person._first_person_unit
    local use_first_person = animation_source and Unit.alive(animation_source) and
        Unit.has_node(animation_source, "j_lefthand") and
        Unit.has_node(animation_source, "j_righthand")
    if use_first_person then source = animation_source end
    local pivot, delta
    if aim_rotation and (use_first_person or Unit.has_node(source, "j_head")) then
        pivot = Unit.world_position(source,
            use_first_person and 1 or Unit.node(source, "j_head"))
        delta = Quaternion.multiply(aim_rotation,
            inverse_quaternion(Unit.world_rotation(source, 1)))
    end
    for side, hand in pairs(rigid_hands) do
        local name = side == "left" and "j_lefthand" or "j_righthand"
        if Unit.has_node(source, name) then
            local node = Unit.node(source, name)
            -- Copy the stock wrist pose, not an OpenXR grip pose. Finger
            -- animation still comes from the same authoritative skeleton.
            local position = Unit.world_position(source, node)
            local rotation = Unit.world_rotation(source, node)
            if delta then
                position = pivot + Quaternion.rotate(delta, position - pivot)
                rotation = Quaternion.multiply(delta, rotation)
            end
            place_rigid_hand(world, hand, position, rotation, true)
        end
    end
    return true, rigid_hands.left.unit, rigid_hands.right.unit
end

function BodyProxy.visual_owner(unit)
    if not unit then return nil end
    if unit==state.unit then return 'body_proxy' end
    for side,hand in pairs(rigid_hands) do
        if unit==hand.unit then return side..'_hand_proxy' end
    end
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
