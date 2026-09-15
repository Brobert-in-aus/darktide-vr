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
local Mirror = {}

Mirror.FLAG = "./../mods/darktidevr/darktidevr_body_mirror.flag"
Mirror.MIRROR_DISTANCE = 2.5
Mirror.KEPT_SLOT_TYPES = {body = true, gear = true, material = true}

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
    local poll, enabled = 0, false
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
        enabled = type(value) == "string" and value:match("^%s*mirror%s*$") ~= nil
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
    local function place(avatar, unit)
        local rotation = Unit.world_rotation(avatar, 1)
        local position = Unit.world_position(avatar, 1) + Quaternion.forward(rotation) * Mirror.MIRROR_DISTANCE
        Unit.set_local_position(unit, 1, position)
        Unit.set_local_rotation(unit, 1, Quaternion.multiply(rotation, Quaternion(Vector3.up(), math.pi)))
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
        profile_spawner:spawn_profile(profile, Unit.world_position(avatar, 1) + Quaternion.forward(rotation) * Mirror.MIRROR_DISTANCE,
            rotation, nil, nil, nil, nil, nil, false, false, nil, true)
        state = {world = world, avatar = avatar, unit_spawner = unit_spawner, profile_spawner = profile_spawner, frames = 0}
        mod:info("DARKTIDEVR_BODY_MIRROR spawn kept_slots=%d ignored_slots=%d", kept, ignored)
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
            local slots = 0
            for _ in pairs(data.slots or {}) do slots = slots + 1 end
            mod:info("DARKTIDEVR_BODY_MIRROR ready nodes=%d avatar_nodes=%d same_layout=%s spawned_slots=%d",
                state.count, Unit.num_scene_graph_items(avatar), tostring(state.same_layout), slots)
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
        state.frames = state.frames + 1
        if state.frames == 1 or state.frames % 900 == 0 then
            local hand = Vector3.distance(Unit.local_position(unit, Unit.node(unit, "j_righthand")),
                Unit.local_position(avatar, Unit.node(avatar, "j_righthand")))
            mod:info("DARKTIDEVR_BODY_MIRROR copying frames=%d right_hand_local_error_m=%.6f", state.frames, hand)
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
