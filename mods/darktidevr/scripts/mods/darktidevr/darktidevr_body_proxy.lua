local UIProfileSpawner = require("scripts/managers/ui/ui_profile_spawner")
local UIUnitSpawner = require("scripts/managers/ui/ui_unit_spawner")
local ItemSlotSettings = require("scripts/settings/item/item_slot_settings")
local MasterItems = require("scripts/backend/master_items")

local BodyProxy = {}

function BodyProxy.uses_stock_melee_animation(slot, kind, action, actions)
    if kind == "sweep" or kind == "push" or kind == "melee_explosive" then
        return true
    end
    -- A held block plays the authored guard pose on every melee weapon (and
    -- the shield states); the tracked arms would otherwise overwrite it and
    -- leave the block invisible. Block direction still follows the hand.
    if kind == "block" or kind == "block_windup" or kind == "block_aiming" or
            kind == "block_unaim" then
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

-- Where the visible hands come from. Every hand placement below (tracked
-- grip, gun alignment, two-hand support grip, stock melee follow) ends in
-- place_rigid_hand, which records the final wrist pose per side
-- (hand.pose_position, hand.pose_rotation). The equipment hand joints and a
-- body read that pose.
-- - Default (hand_rig nil): two rigid glove units draw the hands. They are
--   the fallback until the third-person body is finished.
-- - hand_rig set (BodyProxy.set_hand_rig, by a full-profile body that draws
--   its own hands): no glove units exist. The same placements only record
--   the pose, using the anatomical wrist basis measured once from that rig.
--   The gloves return when the rig is cleared or its unit dies.
local hand_rig = nil
local hand_rig_anatomy = {}

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

-- The inverse of a rig's anatomical wrist basis for one side, measured from
-- its hand and knuckle joints, or nil when the pose cannot define it.
local function measure_anatomy_inverse(unit, side)
    local hand_name = side == "left" and "j_lefthand" or "j_righthand"
    local middle_name = side == "left" and
        "j_lefthandmiddle1" or "j_righthandmiddle1"
    local index_name = side == "left" and
        "j_lefthandindex1" or "j_righthandindex1"
    local pinky_name = side == "left" and
        "j_lefthandpinky1" or "j_righthandpinky1"
    if not unit or not Unit.has_node(unit, hand_name) or
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
    if not palm then return nil end
    return QuaternionBox(inverse_quaternion(Quaternion.look(palm, across)))
end

local function anatomical_hand_rotation(unit, side, target_rotation)
    local hand = rigid_hands[side]
    local target_frame = Quaternion.look(
        Quaternion.right(target_rotation) * -1,
        Quaternion.forward(target_rotation))
    if hand.anatomy_inverse then
        return Quaternion.multiply(target_frame, hand.anatomy_inverse:unbox())
    end
    -- A partial pose must not permanently poison the cached wrist basis.
    -- Leave calibration unset so the next usable authored pose can retry.
    -- Capture the authored basis before importing finger animation. Rebuilding
    -- it from curled fingers would make an open/closed palm rotate the wrist.
    local anatomy_inverse = measure_anatomy_inverse(unit, side)
    if not anatomy_inverse then return nil end
    hand.anatomy_inverse = anatomy_inverse
    return Quaternion.multiply(target_frame, hand.anatomy_inverse:unbox())
end

local function copy_gameplay_fingers(hand)
    local source = state.source_unit
    if not source or not Unit.alive(source) then
        return
    end
    if not hand.finger_nodes then
        -- The node list is rebuilt whenever the rig respawns, and it is only
        -- the nodes this glove and this source rig share. Poses captured
        -- against an older list are indexed by position, so they would land on
        -- the wrong joints: drop them with the list.
        BodyProxy.finger_poses = {}
        hand.finger_key, hand.finger_samples = nil, nil
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
    -- Animation audit item H. The fingers followed the gameplay rig's live
    -- animation, so they breathed with the idle and twitched through every
    -- action. As with the gun hand's grip (item E), take the curl once per
    -- weapon while nothing is happening and hold it.
    --
    -- Only while the gun path is driving this frame. With no fresh capture
    -- key -- melee, or no weapon -- the fingers keep following the animation,
    -- which is what the user asked for during melee swings.
    local key = BodyProxy.finger_capture_key(hand.side)
    local held = key and BodyProxy.finger_poses[key]
    if held then
        for index, node in ipairs(hand.finger_nodes) do
            local rotation = held[index]
            if rotation then Unit.set_local_rotation(hand.unit, node.target, rotation:unbox()) end
        end
        return
    end
    for _, node in ipairs(hand.finger_nodes) do
        Unit.set_local_rotation(hand.unit, node.target,
            Unit.local_rotation(source, node.source))
    end
    if key and state.finger_steady then
        -- Per hand and per weapon: a shared counter let the second hand
        -- capture off the first hand's steady frames, and a counter that
        -- survived a weapon swap let the new weapon capture one frame in.
        if hand.finger_key ~= key then hand.finger_key, hand.finger_samples = key, 0 end
        local count = (hand.finger_samples or 0) + 1
        hand.finger_samples = count
        if count >= BodyProxy.FINGER_SAMPLES then
            local pose = {}
            for index, node in ipairs(hand.finger_nodes) do
                pose[index] = QuaternionBox(Unit.local_rotation(source, node.source))
            end
            BodyProxy.finger_poses[key] = pose
            print(string.format('DARKTIDEVR_IK finger_pose key=%s joints=%d samples=%d',
                tostring(key), #pose, count))
        end
    elseif key then
        hand.finger_key, hand.finger_samples = key, 0
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

local function disable_visual_colliders(unit)
    assert(unit~=state.source_unit,'Visual collision cleanup cannot own the gameplay body')
    local count=Unit.num_actors(unit)
    local disabled=0
    for index=1,count do
        local actor=Unit.actor(unit,index)
        -- Stock deployable/pickup loops also allow empty actor slots.
        if actor then
            Actor.set_collision_enabled(actor,false)
            Actor.set_scene_query_enabled(actor,false)
            disabled=disabled+1
        end
    end
    print('DARKTIDEVR_IK visual_colliders=disabled actors='..disabled..' slots='..count)
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
        if hand.unit~=unit or not hand.ready then disable_visual_colliders(unit) end
        hand.unit = unit
        if not hand.ready then show_rigid_hand_surface(hand) end
        hand.ready = true
        return unit
    end
    return nil
end

local function place_rigid_hand(world, hand, target_position, target_rotation,
        authored_rotation)
    if hand_rig then
        -- Body-drawn hands: record the final wrist pose, nothing to move.
        if not hand.anatomy_inverse or not target_position or not target_rotation then
            return false
        end
        local rotation = authored_rotation and target_rotation or
            anatomical_hand_rotation(nil, hand.side, target_rotation)
        if hand.pose_position then
            hand.pose_position:store(target_position)
            hand.pose_rotation:store(rotation)
        else
            hand.pose_position = Vector3Box(target_position)
            hand.pose_rotation = QuaternionBox(rotation)
        end
        return true
    end
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
    if hand.pose_position then
        hand.pose_position:store(Unit.world_position(unit, hand_node))
        hand.pose_rotation:store(Unit.world_rotation(unit, hand_node))
    else
        hand.pose_position = Vector3Box(Unit.world_position(unit, hand_node))
        hand.pose_rotation = QuaternionBox(Unit.world_rotation(unit, hand_node))
    end
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
    if hands_only and hand_rig and not Unit.alive(hand_rig) then
        hand_rig, hand_rig_anatomy = nil, {}
        safe_destroy()
        print("DARKTIDEVR_IK hand_rig=gloves reason=rig_unit_lost")
    end
    if hands_only and hand_rig then
        -- Body-drawn hands: no glove units. The source unit carries the head
        -- joint the tracked grip targets need.
        if state.world ~= world or state.source_unit ~= source_unit or
                state.profile ~= profile or not state.hands_only then
            safe_destroy()
            state.world, state.source_unit, state.profile = world, source_unit, profile
            state.hands_only, state.ready, state.ready_transition = true, true, true
            print("DARKTIDEVR_IK rigid_hands=pose_only source=body_rig")
        end
        for side, hand in pairs(rigid_hands) do
            hand.side, hand.ready, hand.anatomy_inverse = side, true, hand_rig_anatomy[side]
        end
        return source_unit
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
        if state.unit~=unit or not state.ready then disable_visual_colliders(unit) end
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
    if state.hands_only and hand_rig then
        return state.ready == true and Unit.alive(hand_rig)
    end
    if state.hands_only then
        local left, right = rigid_hands.left, rigid_hands.right
        return state.ready and left.ready and right.ready and
            left.unit ~= nil and right.unit ~= nil and
            Unit.alive(left.unit) and Unit.alive(right.unit)
    end
    return state.ready and state.unit and Unit.alive(state.unit)
end

-- A full-profile body that draws its own hands takes over from the glove
-- units (unit), or hands back to them (nil). Call it before the body copies
-- any animated pose: the wrist basis is measured from its hand joints now.
-- Returns whether body-drawn hands are active.
function BodyProxy.set_hand_rig(unit)
    if unit ~= nil and not Unit.alive(unit) then unit = nil end
    if unit == hand_rig then return hand_rig ~= nil end
    local anatomy = {}
    if unit then
        for _, side in ipairs({"left", "right"}) do
            anatomy[side] = measure_anatomy_inverse(unit, side)
            if not anatomy[side] then
                print("DARKTIDEVR_IK hand_rig=rejected reason=anatomy_unavailable side=" .. side)
                return false
            end
        end
    end
    safe_destroy()
    hand_rig, hand_rig_anatomy = unit, anatomy
    print("DARKTIDEVR_IK hand_rig=" .. (unit and "body" or "gloves"))
    return unit ~= nil
end

-- The final wrist pose of a physical side after every placement so far this
-- frame (the pose the visible hand shows), or nil.
function BodyProxy.hand_pose(side)
    local hand = rigid_hands[side]
    if not hand or not hand.pose_position or not BodyProxy.rigid_hands_active() then return nil end
    return hand.pose_position:unbox(), hand.pose_rotation:unbox()
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
        left_written or right_written, left_written, right_written
end

-- Keep the weapon's authored wrist basis when its role moves to another grip.
-- Anatomical glove placement and raw physical controller identities stay fixed.
function BodyProxy.equipment_hand_rotation(source, authored_side, grip_rotation)
    if source~=state.source_unit or not source or not Unit.alive(source) or
            not grip_rotation or (authored_side~='left' and authored_side~='right') or
            not BodyProxy.rigid_hands_active() then return nil end
    local hand=rigid_hands[authored_side]
    if not hand.ready or not hand.anatomy_inverse or
            (not hand_rig and (not hand.unit or not Unit.alive(hand.unit))) then return nil end
    return anatomical_hand_rotation(hand.unit,authored_side,grip_rotation)
end

function BodyProxy.convert_hand_rotation(source,authored_side,destination_side,rotation)
    if not source or source~=state.source_unit or not Unit.alive(source) or not rotation or
            not BodyProxy.rigid_hands_active() or
            (authored_side~='left' and authored_side~='right') or
            (destination_side~='left' and destination_side~='right') then return nil end
    if authored_side==destination_side then return rotation end
    local authored,destination=rigid_hands[authored_side],rigid_hands[destination_side]
    if not authored.anatomy_inverse or not destination.anatomy_inverse then return nil end
    return Quaternion.multiply(Quaternion.multiply(rotation,
        inverse_quaternion(authored.anatomy_inverse:unbox())),destination.anatomy_inverse:unbox())
end

-- The gun hand's grip on each weapon (animation audit, 16 September, item E):
-- the animated right hand in the weapon attach node's frame, averaged over
-- GUN_HAND_SAMPLES steady frames (no action running, not moving) and then
-- held. Live, the offset carried the character's strafe turns, idle sway and
-- per-frame animation into the glove. key: the weapon template; without a key
-- the live offset is used. Returns the offset to place the hand with.
BodyProxy.GUN_HAND_SAMPLES=30
BodyProxy.gun_hand_offsets={}
-- The finger curl per weapon and side (animation audit item H), captured after
-- this many steady frames and then held. The key is only valid on the frame
-- the gun path set it, so melee keeps the animation.
BodyProxy.FINGER_SAMPLES=30
BodyProxy.finger_poses={}
function BodyProxy.finger_capture_key(side)
    if not state.finger_key or not side then return nil end
    local now=Managers and Managers.time and Managers.time:time('main')
    if not now or state.finger_t~=now then return nil end
    return state.finger_key..'/'..side
end
function BodyProxy.gun_hand_offset(key,steady,relative_position,relative_rotation)
    if not key then return relative_position,relative_rotation end
    local entry=BodyProxy.gun_hand_offsets[key]
    if entry and entry.position then return entry.position:unbox(),entry.rotation:unbox() end
    if not steady then return relative_position,relative_rotation end
    if not entry then
        entry={samples=0,x=0,y=0,z=0,q={0,0,0,0}}
        BodyProxy.gun_hand_offsets[key]=entry
    end
    local qx,qy,qz,qw=Quaternion.to_elements(relative_rotation)
    local q=entry.q
    if entry.samples>0 and qx*q[1]+qy*q[2]+qz*q[3]+qw*q[4]<0 then qx,qy,qz,qw=-qx,-qy,-qz,-qw end
    q[1],q[2],q[3],q[4]=q[1]+qx,q[2]+qy,q[3]+qz,q[4]+qw
    entry.x=entry.x+Vector3.x(relative_position)
    entry.y=entry.y+Vector3.y(relative_position)
    entry.z=entry.z+Vector3.z(relative_position)
    entry.samples=entry.samples+1
    if entry.samples>=BodyProxy.GUN_HAND_SAMPLES then
        local n=entry.samples
        local length=math.sqrt(q[1]*q[1]+q[2]*q[2]+q[3]*q[3]+q[4]*q[4])
        entry.position=Vector3Box(entry.x/n,entry.y/n,entry.z/n)
        entry.rotation=QuaternionBox(Quaternion.from_elements(q[1]/length,q[2]/length,q[3]/length,q[4]/length))
        print(string.format('DARKTIDEVR_IK gun_hand_grip template=%s samples=%d offset=%.3f,%.3f,%.3f',
            tostring(key),n,entry.x/n,entry.y/n,entry.z/n))
        return entry.position:unbox(),entry.rotation:unbox()
    end
    return relative_position,relative_rotation
end

function BodyProxy.align_gun_hand(world,source,old_position,old_rotation,new_position,new_rotation,destination,key,steady)
    destination=destination or 'right'
    -- The fingers read this on the same frame (item H).
    state.finger_key=key
    state.finger_steady=steady==true
    state.finger_t=Managers and Managers.time and Managers.time:time('main')
    if not BodyProxy.rigid_hands_active() or source~=state.source_unit or
            not Unit.alive(source) or not Unit.has_node(source,'j_righthand') or
            (destination~='left' and destination~='right') then return false end
    local node=Unit.node(source,'j_righthand')
    local inverse_old=inverse_quaternion(old_rotation)
    local relative_position=Quaternion.rotate(inverse_old,Unit.world_position(source,node)-old_position)
    local relative_rotation=Quaternion.multiply(inverse_old,Unit.world_rotation(source,node))
    relative_position,relative_rotation=BodyProxy.gun_hand_offset(key,steady,relative_position,relative_rotation)
    local position=new_position+Quaternion.rotate(new_rotation,relative_position)
    local rotation=Quaternion.multiply(new_rotation,relative_rotation)
    if destination~='right' then
        rotation=BodyProxy.convert_hand_rotation(source,'right',destination,rotation)
        if not rotation then return false end
    end
    return place_rigid_hand(world,rigid_hands[destination],position,rotation,true)
end

-- authored_rotation: rotation is a stock hand joint rotation (the authored
-- grip) rather than a controller grip rotation to convert anatomically.
-- weight, when below 1, blends from the glove's pose already placed this frame
-- (the tracked hand) toward the grip pose: 0 leaves the tracked hand.
function BodyProxy.place_support_hand(world,source,side,position,rotation,authored_rotation,weight)
    if not BodyProxy.rigid_hands_active() or source~=state.source_unit or
        not Unit.alive(source) or (side~='left' and side~='right') then return false end
    local hand=rigid_hands[side]
    if weight~=nil and weight<1 then
        if not (weight>0) then return false end
        local name=side=='left' and 'j_lefthand' or 'j_righthand'
        local from_position,from_rotation
        if hand_rig then
            -- Body-drawn hands blend from the recorded tracked pose.
            if not hand.pose_position or not position or not rotation then return false end
            from_position,from_rotation=hand.pose_position:unbox(),hand.pose_rotation:unbox()
        else
            if not hand.ready or not hand.unit or not Unit.alive(hand.unit) or
                not Unit.has_node(hand.unit,name) or not position or not rotation then return false end
        end
        local joint=authored_rotation and rotation or anatomical_hand_rotation(hand.unit,side,rotation)
        if not joint then return false end
        if not from_position then
            local node=Unit.node(hand.unit,name)
            from_position,from_rotation=Unit.world_position(hand.unit,node),Unit.world_rotation(hand.unit,node)
        end
        position=Vector3.lerp(from_position,position,weight)
        rotation=Quaternion.lerp(from_rotation,joint,weight)
        authored_rotation=true
    end
    return place_rigid_hand(world,hand,position,rotation,authored_rotation==true)
end

-- offset, when given, moves both animated hands by one world vector, keeping
-- the animation itself unchanged. pivot_position, when given, is where the
-- animation's root is placed instead of its own world position: the rendered
-- first-person root follows the smoothed character position, which drifts
-- against the VR camera anchor from frame to frame while moving.
function BodyProxy.follow_gameplay_hands(world, aim_rotation, offset, pivot_position)
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
                position = (pivot_position or pivot) + Quaternion.rotate(delta, position - pivot)
                rotation = Quaternion.multiply(delta, rotation)
            end
            if offset then position = position + offset end
            place_rigid_hand(world, hand, position, rotation, true)
        end
    end
    return true, rigid_hands.left.unit, rigid_hands.right.unit
end

-- Every unit this module has drawn, labelled, for a census that has to name
-- what is on screen. `hand_pose` returns a position and a rotation, not a
-- record, so there was no way to reach these from outside until now.
function BodyProxy.drawn_units()
    local units = {}
    if state.unit and Unit.alive(state.unit) then units[#units + 1] = {label = "proxy_body", unit = state.unit} end
    for side, hand in pairs(rigid_hands) do
        if hand.unit and Unit.alive(hand.unit) then
            units[#units + 1] = {label = "proxy_glove/" .. tostring(side), unit = hand.unit}
        end
    end
    return units
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
