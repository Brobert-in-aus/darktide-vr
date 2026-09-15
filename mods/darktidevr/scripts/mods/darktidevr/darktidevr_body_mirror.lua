-- Body mirror (dev flag darktidevr_body_mirror.flag "mirror"; full-body IK
-- design, milestone 2, 15 September). Spawns a presentation-only copy of the
-- player's whole character profile (every body, gear and material slot, no
-- weapons) with the body proxy's UIProfileSpawner, stops its own animation
-- the moment it is ready (scan2: that freezes the pose), and every frame
-- copies every joint's local pose from the gameplay avatar onto it. It stands
-- MIRROR_DISTANCE ahead of the avatar, facing it, so an eye render shows
-- whether the full profile spawns with its cosmetics and follows the avatar's
-- pose. Nothing else changes: the avatar, gloves, proxy and visibility code
-- are untouched. Players never have the flag.
--
-- Flag "overlaycopy" (milestone 2 proper, no IK): the same copy stands exactly
-- on the avatar, facing its way, with the head, face and headgear slots hidden
-- so the eye cameras are not inside them. In the default hands mode the
-- avatar already hides every body slot, so this shows whether the full
-- profile reads as the player's own body with no double body. The plain copy
-- stretches the sleeves to the gloves (overlay2: 0.6-0.8 m from forearm to
-- hand against a 0.275 m bone).
--
-- Flag "overlay": the same, then each arm is re-solved as two bones of their
-- spawned lengths so the hand reaches the avatar's hand (which carries the
-- weapon and sits on the glove), bending toward the stock animated elbow.
-- Swing only: the forearm roll joints are not twisted yet.
local Mirror = {}

Mirror.FLAG = "./../mods/darktidevr/darktidevr_body_mirror.flag"
Mirror.MIRROR_DISTANCE = 2.5
Mirror.KEPT_SLOT_TYPES = {body = true, gear = true, material = true}
Mirror.MODES = {
    mirror = {distance = Mirror.MIRROR_DISTANCE, facing = true, hide_head = false},
    overlaycopy = {distance = 0, facing = false, hide_head = true, solve_arms = false},
    overlay = {distance = 0, facing = false, hide_head = true, solve_arms = true},
}
Mirror.ARM_SIDES = {"left", "right"}
-- Added to the stock elbow as the bend hint, so a straight stock arm still
-- bends downward.
Mirror.ELBOW_HINT_DOWN = 0.10

local function sub(a, b) return {a[1] - b[1], a[2] - b[2], a[3] - b[3]} end
local function add(a, b) return {a[1] + b[1], a[2] + b[2], a[3] + b[3]} end
local function scale(a, k) return {a[1] * k, a[2] * k, a[3] * k} end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function length(a) return math.sqrt(dot(a, a)) end

-- Two-bone arm: where the elbow goes so the upper and lower bones keep their
-- lengths and the hand reaches the target, bending toward the hint. Out of
-- reach the arm points at the target and the hand stops at full reach.
-- Returns elbow, hand, reachable (arrays), or nil for degenerate input. Pure.
function Mirror.elbow(shoulder, hint, target, upper, lower)
    if not (upper > 0 and lower > 0) then return nil end
    local to_target = sub(target, shoulder)
    local distance = length(to_target)
    if distance < 1e-6 then return nil end
    local direction = scale(to_target, 1 / distance)
    local near, far = math.abs(upper - lower) + 1e-4, (upper + lower) * 0.999
    local reachable = distance >= near and distance <= far
    local d = math.max(near, math.min(far, distance))
    local cosine = math.max(-1, math.min(1, (upper * upper + d * d - lower * lower) / (2 * upper * d)))
    local sine = math.sqrt(1 - cosine * cosine)
    local offset = sub(hint, shoulder)
    local bend = sub(offset, scale(direction, dot(offset, direction)))
    if length(bend) < 1e-6 then
        bend = sub({0, 0, -1}, scale(direction, -direction[3]))
        if length(bend) < 1e-6 then bend = {1, 0, 0} end
    end
    bend = scale(bend, 1 / length(bend))
    local elbow = add(shoulder, add(scale(direction, upper * cosine), scale(bend, upper * sine)))
    return elbow, add(shoulder, scale(direction, d)), reachable
end

-- The flag's mode, or nil. Pure.
function Mirror.parse_mode(value)
    local name = type(value) == "string" and value:match("^%s*(%a+)%s*$")
    return name and Mirror.MODES[name] and name or nil
end

-- Whether a spawned slot is hidden in this mode: head slots in overlay only,
-- from the caller's head slot lookup. Pure.
function Mirror.hides_slot(mode_name, slot_name, head_lookup)
    local mode = Mirror.MODES[mode_name]
    return mode ~= nil and mode.hide_head and type(head_lookup) == "table" and head_lookup[slot_name] == true
end

-- Whether the mirror spawns a slot: body, gear and material slots, plus the
-- unarmed slot the spawner needs for its wielded-slot plumbing. Pure.
function Mirror.keeps_slot(slot_name, settings)
    if slot_name == "slot_unarmed" then return true end
    if slot_name == "slot_companion_gear_full" then return false end
    return type(settings) == "table" and Mirror.KEPT_SLOT_TYPES[settings.slot_type] == true and
        not settings.ignore_character_spawning
end

-- Node correspondence between the avatar and the mirror: by index when both
-- rigs have the same node count and the probe joints sit at the same indices,
-- otherwise nil (the caller copies nothing and logs why). Pure over lookups.
function Mirror.same_layout(count_a, count_b, index_of_a, index_of_b, probes)
    if count_a ~= count_b or count_a < 2 then return false end
    for _, name in ipairs(probes) do
        if index_of_a(name) ~= index_of_b(name) then return false end
    end
    return true
end

function Mirror.install(mod, presentation)
    local api = {}
    local poll, enabled, mode_name = 0, false, nil
    local state
    local logged = {}
    local function flag()
        poll = poll - 1
        if poll > 0 then return enabled end
        poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Mirror.FLAG, "r")
        if not file then enabled = false; return false end
        local value = file:read("*all"); file:close()
        local parsed = Mirror.parse_mode(value)
        if state and parsed ~= mode_name then api.destroy() end
        mode_name = parsed
        enabled = parsed ~= nil
        return enabled
    end
    function api.destroy()
        if state then
            if state.profile_spawner then pcall(state.profile_spawner.destroy, state.profile_spawner) end
            if state.unit_spawner then pcall(state.unit_spawner.destroy, state.unit_spawner) end
        end
        state = nil
    end
    local function log_once(key, format, ...)
        if logged[key] then return end
        logged[key] = true
        mod:info("DARKTIDEVR_BODY_MIRROR " .. format, ...)
    end
    local function inverse(rotation)
        local x, y, z, w = Quaternion.to_elements(rotation)
        return Quaternion.from_elements(-x, -y, -z, w)
    end
    local function array(v) return {Vector3.x(v), Vector3.y(v), Vector3.z(v)} end
    local function vector(a) return Vector3(a[1], a[2], a[3]) end
    local function set_world_rotation(unit, index, rotation)
        local parent = Unit.scene_graph_parent(unit, index)
        local parent_rotation = parent and Unit.world_rotation(unit, parent) or Quaternion.identity()
        Unit.set_local_rotation(unit, index, Quaternion.multiply(inverse(parent_rotation), rotation))
    end
    -- Swing joint so the child joint points at the target position.
    local function aim_joint(world, unit, joint, child, target)
        local origin = Unit.world_position(unit, joint)
        local from, to = Unit.world_position(unit, child) - origin, target - origin
        local from_length, to_length = Vector3.length(from), Vector3.length(to)
        if from_length < 1e-6 or to_length < 1e-6 then return end
        from, to = from / from_length, to / to_length
        local axis = Vector3.cross(from, to)
        local sine = Vector3.length(axis)
        if sine < 1e-7 then return end
        local swing = Quaternion(axis / sine, math.atan2(sine, Vector3.dot(from, to)))
        set_world_rotation(unit, joint, Quaternion.multiply(swing, Unit.world_rotation(unit, joint)))
        World.update_unit(world, unit)
    end
    local function capture_arms(unit)
        state.arms = {}
        for _, side in ipairs(Mirror.ARM_SIDES) do
            local names = {"j_" .. side .. "arm", "j_" .. side .. "forearm", "j_" .. side .. "hand"}
            if Unit.has_node(unit, names[1]) and Unit.has_node(unit, names[2]) and Unit.has_node(unit, names[3]) then
                local arm = {side = side, arm = Unit.node(unit, names[1]), forearm = Unit.node(unit, names[2]),
                    hand = Unit.node(unit, names[3]), unreachable = 0}
                arm.rest_forearm = Vector3Box(Unit.local_position(unit, arm.forearm))
                arm.rest_hand = Vector3Box(Unit.local_position(unit, arm.hand))
                arm.upper = Vector3.length(arm.rest_forearm:unbox())
                arm.lower = Vector3.length(arm.rest_hand:unbox())
                state.arms[#state.arms + 1] = arm
            end
        end
    end
    local function solve_arm(world, avatar, unit, arm)
        local target = Unit.world_position(avatar, arm.hand)
        local target_rotation = Unit.world_rotation(avatar, arm.hand)
        Unit.set_local_position(unit, arm.forearm, arm.rest_forearm:unbox())
        Unit.set_local_position(unit, arm.hand, arm.rest_hand:unbox())
        World.update_unit(world, unit)
        local hint = Unit.world_position(unit, arm.forearm) - Vector3(0, 0, Mirror.ELBOW_HINT_DOWN)
        local shoulder = Unit.world_position(unit, arm.arm)
        local elbow, hand, reachable = Mirror.elbow(array(shoulder), array(hint), array(target), arm.upper, arm.lower)
        if not elbow then return end
        aim_joint(world, unit, arm.arm, arm.forearm, vector(elbow))
        aim_joint(world, unit, arm.forearm, arm.hand, vector(hand))
        set_world_rotation(unit, arm.hand, target_rotation)
        World.update_unit(world, unit)
        arm.distance = Vector3.length(target - shoulder)
        if not reachable then arm.unreachable = arm.unreachable + 1 end
        arm.error = Vector3.length(Unit.world_position(unit, arm.hand) - target)
    end
    local function place(avatar, unit)
        local mode = Mirror.MODES[mode_name] or Mirror.MODES.mirror
        local rotation = Unit.world_rotation(avatar, 1)
        local position = Unit.world_position(avatar, 1) + Quaternion.forward(rotation) * mode.distance
        Unit.set_local_position(unit, 1, position)
        Unit.set_local_rotation(unit, 1, mode.facing and
            Quaternion.multiply(rotation, Quaternion(Vector3.up(), math.pi)) or rotation)
        Unit.set_local_scale(unit, 1, Unit.local_scale(avatar, 1))
    end
    local function spawn(world, avatar)
        local UIProfileSpawner = require("scripts/managers/ui/ui_profile_spawner")
        local UIUnitSpawner = require("scripts/managers/ui/ui_unit_spawner")
        local ItemSlotSettings = require("scripts/settings/item/item_slot_settings")
        local player = Managers.player and Managers.player:local_player(1)
        local profile = player and player:profile()
        if not profile then return end
        local unit_spawner = UIUnitSpawner:new(world)
        local profile_spawner = UIProfileSpawner:new("DarktideVRBodyMirror", world, nil, unit_spawner, false)
        local kept, ignored = 0, 0
        for slot_name, settings in pairs(ItemSlotSettings) do
            if Mirror.keeps_slot(slot_name, settings) then kept = kept + 1
            else profile_spawner:ignore_slot(slot_name); ignored = ignored + 1 end
        end
        local rotation = Unit.world_rotation(avatar, 1)
        profile_spawner:spawn_profile(profile, Unit.world_position(avatar, 1) + Quaternion.forward(rotation) * Mirror.MODES[mode_name].distance,
            rotation, nil, nil, nil, nil, nil, false, false, nil, true)
        state = {world = world, avatar = avatar, unit_spawner = unit_spawner, profile_spawner = profile_spawner, frames = 0}
        mod:info("DARKTIDEVR_BODY_MIRROR spawn mode=%s kept_slots=%d ignored_slots=%d", tostring(mode_name), kept, ignored)
    end
    local function update(world, avatar, dt, t)
        if not flag() or not world or not avatar or not Unit.alive(avatar) then api.destroy(); return end
        if state and (state.world ~= world or state.avatar ~= avatar) then api.destroy() end
        if not state then spawn(world, avatar); return end
        if not state.unit then
            state.profile_spawner:update(dt, t)
            local data = state.profile_spawner:spawned() and state.profile_spawner._character_spawn_data
            local unit = data and data.unit_3p
            if not unit then return end
            state.unit = unit
            Unit.disable_animation_state_machine(unit)
            local probes = {"j_hips", "j_spine2", "j_head", "j_lefthand", "j_righthand", "j_leftfoot", "j_rightfoot"}
            state.same_layout = Mirror.same_layout(Unit.num_scene_graph_items(avatar), Unit.num_scene_graph_items(unit),
                function(name) return Unit.has_node(avatar, name) and Unit.node(avatar, name) end,
                function(name) return Unit.has_node(unit, name) and Unit.node(unit, name) end, probes)
            state.count = Unit.num_scene_graph_items(unit)
            capture_arms(unit)
            local slots, hidden = 0, {}
            for slot_name, slot in pairs(data.slots or {}) do
                slots = slots + 1
                if Mirror.hides_slot(mode_name, slot_name, presentation.headless_body_hidden_slot_lookup) and
                        slot.unit_3p and Unit.alive(slot.unit_3p) then
                    Unit.set_unit_visibility(slot.unit_3p, false, true)
                    local attachments = slot.attachments_by_unit_3p and slot.attachments_by_unit_3p[slot.unit_3p]
                    for _, attachment in ipairs(attachments or {}) do
                        if Unit.alive(attachment) then Unit.set_unit_visibility(attachment, false, true) end
                    end
                    hidden[#hidden + 1] = slot_name
                end
            end
            table.sort(hidden)
            mod:info("DARKTIDEVR_BODY_MIRROR ready mode=%s nodes=%d avatar_nodes=%d same_layout=%s spawned_slots=%d hidden_slots=%s",
                tostring(mode_name), state.count, Unit.num_scene_graph_items(avatar), tostring(state.same_layout), slots,
                #hidden > 0 and table.concat(hidden, ",") or "none")
        end
        local unit = state.unit
        if not Unit.alive(unit) then api.destroy(); return end
        if not state.same_layout then
            log_once("layout", "copy=skipped reason=layout_mismatch")
            place(avatar, unit)
            return
        end
        -- Every joint below the root: the avatar's local pose after its own
        -- animation and the mod's hand writes this frame.
        for index = 2, state.count do
            Unit.set_local_pose(unit, index, Unit.local_pose(avatar, index))
        end
        place(avatar, unit)
        World.update_unit(world, unit)
        if Mirror.MODES[mode_name].solve_arms then
            for _, arm in ipairs(state.arms) do solve_arm(world, avatar, unit, arm) end
        end
        state.frames = state.frames + 1
        if state.frames == 1 or state.frames % 900 == 0 then
            local unit_hand, avatar_hand = Unit.node(unit, "j_righthand"), Unit.node(avatar, "j_righthand")
            local hand = Vector3.distance(Unit.local_position(unit, unit_hand), Unit.local_position(avatar, avatar_hand))
            -- Overlay: how far the copied hand lands from the avatar's (which
            -- carries the weapon), and how far the hand sits from its forearm
            -- joint: the stretch a plain copy leaves where the gloves pull the
            -- avatar's hands.
            local world_hand = Vector3.distance(Unit.world_position(unit, unit_hand), Unit.world_position(avatar, avatar_hand))
            local stretch = Unit.has_node(unit, "j_rightforearm") and Vector3.distance(Unit.world_position(unit, unit_hand),
                Unit.world_position(unit, Unit.node(unit, "j_rightforearm"))) or -1
            mod:info("DARKTIDEVR_BODY_MIRROR copying mode=%s frames=%d right_hand_local_error_m=%.6f right_hand_world_error_m=%.4f right_forearm_to_hand_m=%.4f",
                tostring(mode_name), state.frames, hand, world_hand, stretch)
            if Mirror.MODES[mode_name].solve_arms then
                for _, arm in ipairs(state.arms) do
                    mod:info("DARKTIDEVR_BODY_MIRROR arm side=%s upper_m=%.4f lower_m=%.4f shoulder_to_target_m=%.4f hand_error_m=%.4f unreachable_frames=%d",
                        arm.side, arm.upper, arm.lower, arm.distance or -1, arm.error or -1, arm.unreachable)
                end
            end
        end
    end
    function api.update(world, avatar, dt, t)
        local ok, err = pcall(update, world, avatar, dt, t)
        if not ok then
            log_once("failure", "failed=%s", tostring(err):sub(1, 200))
            api.destroy()
            enabled = false; poll = 1e9
        end
    end
    return api
end

return Mirror
