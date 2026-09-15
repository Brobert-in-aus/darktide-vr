-- Rig scan (dev flag darktidevr_rig_scan.flag "scan"; full-body IK design,
-- milestone 1, 15 September). Spawns presentation-only characters with the
-- same UIProfileSpawner the body proxy uses, 3 m ahead of the player: the
-- player's own (human) profile and the stock Ogryn bot profile
-- (darktide_seven_02). For each it logs the design's joint map: whether each
-- joint exists, its parent joint, its bone length and its position from the
-- root, on the first ready frame and again 30 frames later with the spawner
-- no longer updated (is the first frame the bind pose, and does it move?).
-- Then it despawns them. Players never have the flag.
local RigScan = {}

RigScan.FLAG = "./../mods/darktidevr/darktidevr_rig_scan.flag"
RigScan.JOINTS = {
    "j_hips", "j_spine", "j_spine1", "j_spine2", "j_spine3", "j_neck", "j_head",
    "j_leftshoulder", "j_leftarm", "j_leftforearm", "j_leftforearmroll1", "j_leftforearmroll2", "j_lefthand",
    "j_rightshoulder", "j_rightarm", "j_rightforearm", "j_rightforearmroll1", "j_rightforearmroll2", "j_righthand",
    "j_leftupleg", "j_leftleg", "j_leftfoot", "j_lefttoebase",
    "j_rightupleg", "j_rightleg", "j_rightfoot", "j_righttoebase",
    "j_left_hand_ik_handle", "j_right_hand_ik_handle", "j_left_foot_ik_handle", "j_right_foot_ik_handle",
    "j_hips_handle", "j_lefteye", "j_righteye",
}
RigScan.SECOND_SAMPLE_FRAMES = 30

-- The nearest mapped ancestor of each joint, by name, from a parent lookup
-- (index -> parent index) and name lookup (index -> joint name). Pure.
function RigScan.mapped_parent(index, parent_of, name_of)
    local parent = parent_of[index]
    local guard = 0
    while parent and guard < 256 do
        if name_of[parent] then return name_of[parent] end
        parent = parent_of[parent]
        guard = guard + 1
    end
    return nil
end

function RigScan.install(mod, presentation)
    local api = {}
    local poll, enabled, done = 0, false, false
    local subjects
    local function flag()
        poll = poll - 1
        if poll > 0 then return enabled end
        poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(RigScan.FLAG, "r")
        if not file then enabled = false; return false end
        local value = file:read("*all"); file:close()
        enabled = type(value) == "string" and value:match("^%s*scan%s*$") ~= nil
        return enabled
    end
    local function destroy_subject(subject)
        if subject.profile_spawner then pcall(subject.profile_spawner.destroy, subject.profile_spawner) end
        if subject.unit_spawner then pcall(subject.unit_spawner.destroy, subject.unit_spawner) end
    end
    function api.destroy()
        for _, subject in ipairs(subjects or {}) do destroy_subject(subject) end
        subjects = nil
    end
    local function log_rig(subject, label)
        local unit = subject.unit
        local count = Unit.num_scene_graph_items(unit)
        local root = Unit.world_pose(unit, 1)
        local inverse = Matrix4x4.inverse(root)
        local name_of, parent_of = {}, {}
        for _, name in ipairs(RigScan.JOINTS) do
            if Unit.has_node(unit, name) then name_of[Unit.node(unit, name)] = name end
        end
        for index = 1, count do parent_of[index] = Unit.scene_graph_parent(unit, index) end
        mod:info("DARKTIDEVR_RIG_SCAN subject=%s sample=%s nodes=%d scale=%.3f", subject.name, label, count,
            Vector3.x(Unit.local_scale(unit, 1)))
        for _, name in ipairs(RigScan.JOINTS) do
            if Unit.has_node(unit, name) then
                local index = Unit.node(unit, name)
                local position = Matrix4x4.transform(inverse, Unit.world_position(unit, index))
                local parent = RigScan.mapped_parent(index, parent_of, name_of)
                local length = Vector3.length(Unit.local_position(unit, index))
                mod:info("DARKTIDEVR_RIG_SCAN subject=%s sample=%s joint=%s parent=%s bone_m=%.4f root_local=%.3f,%.3f,%.3f",
                    subject.name, label, name, tostring(parent), length,
                    Vector3.x(position), Vector3.y(position), Vector3.z(position))
            else
                mod:info("DARKTIDEVR_RIG_SCAN subject=%s sample=%s joint=%s missing", subject.name, label, name)
            end
        end
    end
    local function start(world, player_unit)
        local UIProfileSpawner = require("scripts/managers/ui/ui_profile_spawner")
        local UIUnitSpawner = require("scripts/managers/ui/ui_unit_spawner")
        local ProfileUtils = require("scripts/utilities/profile_utils")
        local player = Managers.player and Managers.player:local_player(1)
        local profiles = {}
        if player and player:profile() then profiles[#profiles + 1] = {name = "player_" .. tostring(player:profile().archetype and player:profile().archetype.name), profile = player:profile()} end
        local ok, ogryn = pcall(ProfileUtils.get_bot_profile, "darktide_seven_02")
        if ok and ogryn then profiles[#profiles + 1] = {name = "bot_ogryn", profile = ogryn}
        else mod:info("DARKTIDEVR_RIG_SCAN ogryn_profile=unavailable error=%s", tostring(ogryn)) end
        local root = Unit.world_pose(player_unit, 1)
        local forward = Quaternion.forward(Unit.world_rotation(player_unit, 1))
        subjects = {}
        for i, entry in ipairs(profiles) do
            local unit_spawner = UIUnitSpawner:new(world)
            local profile_spawner = UIProfileSpawner:new("DarktideVRRigScan_" .. i, world, nil, unit_spawner, false)
            local position = Matrix4x4.translation(root) + forward * 3 + Quaternion.right(Unit.world_rotation(player_unit, 1)) * (1.2 * (i - 1.5))
            profile_spawner:spawn_profile(entry.profile, position, Unit.world_rotation(player_unit, 1),
                nil, nil, nil, nil, nil, false, false, nil, true)
            subjects[#subjects + 1] = {name = entry.name, unit_spawner = unit_spawner, profile_spawner = profile_spawner}
            mod:info("DARKTIDEVR_RIG_SCAN spawn subject=%s", entry.name)
        end
    end
    local function update(world, player_unit, dt, t)
        if done or not flag() or not world or not player_unit then return end
        if not subjects then start(world, player_unit); return end
        local finished = true
        for _, subject in ipairs(subjects) do
            if not subject.logged_second then
                finished = false
                if not subject.unit then
                    subject.profile_spawner:update(dt, t)
                    if subject.profile_spawner:spawned() then
                        local data = subject.profile_spawner._character_spawn_data
                        subject.unit = data and data.unit_3p
                        if subject.unit then
                            log_rig(subject, "first_ready")
                            subject.frames = 0
                        end
                    end
                else
                    subject.frames = subject.frames + 1
                    if subject.frames >= RigScan.SECOND_SAMPLE_FRAMES and Unit.alive(subject.unit) then
                        log_rig(subject, "after_30_frames_no_update")
                        subject.logged_second = true
                    end
                end
            end
        end
        if finished then
            done = true
            api.destroy()
            mod:info("DARKTIDEVR_RIG_SCAN done")
        end
    end
    function api.update(world, player_unit, dt, t)
        local ok, err = pcall(update, world, player_unit, dt, t)
        if not ok then
            done = true
            api.destroy()
            mod:info("DARKTIDEVR_RIG_SCAN failed=%s", tostring(err):sub(1, 200))
        end
    end
    return api
end

return RigScan
