-- Development scan (flag file darktidevr_attachment_scan.flag, "scan"; players
-- never have it): once per wielded item, and again while a reload runs, logs
-- the wielded slot's third- and first-person units and every attachment with
-- its item and unit names, visibility, the node it is linked to, and its
-- position relative to each tracked grip. Written to find a stray cartridge
-- near the right glove that disappears during reloads (worn, 14 September).
local Scan = {}
Scan.FLAG = "./../mods/darktidevr/darktidevr_attachment_scan.flag"

function Scan.install(mod, presentation)
    local api = {}
    local poll, enabled = 0, false
    local logged = {}
    local function flag()
        poll = poll - 1
        if poll > 0 then return enabled end
        poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Scan.FLAG, "r")
        if not file then enabled = false; return false end
        local value = file:read("*all"); file:close()
        enabled = type(value) == "string" and value:match("^%s*scan%s*$") ~= nil
        return enabled
    end
    local function vector_text(v)
        return v and string.format("%.3f,%.3f,%.3f", Vector3.x(v), Vector3.y(v), Vector3.z(v)) or "nil"
    end
    local function offset(position, target)
        if not position or not target then return "nil" end
        return string.format("%.3f", Vector3.length(position - target))
    end
    local function describe(label, unit, item_name, grips)
        if not unit or not Unit.alive(unit) then return end
        local position = Unit.world_position(unit, 1)
        local parent = Unit.scene_graph_parent and Unit.scene_graph_parent(unit, 1)
        local meshes = Unit.num_meshes and Unit.num_meshes(unit) or -1
        mod:info("DARKTIDEVR_ATTACHMENT_SCAN %s item=%s unit_name=%s meshes=%d position=%s to_right_grip=%s to_left_grip=%s parent_node=%s",
            label, tostring(item_name), tostring(Unit.get_data(unit, "unit_name")), meshes,
            vector_text(position), offset(position, grips.right), offset(position, grips.left), tostring(parent))
        -- Mesh centres show where the visible geometry is, which can differ
        -- from the unit root for attachments authored in the weapon's space.
        for index = 1, math.min(meshes, 12) do
            local ok, mesh = pcall(Unit.mesh, unit, index)
            local box_ok, pose = false, nil
            if ok and mesh then box_ok, pose = pcall(Mesh.box, mesh) end
            if box_ok and pose then
                local centre = Matrix4x4.translation(pose)
                mod:info("DARKTIDEVR_ATTACHMENT_SCAN %s mesh=%d centre=%s to_right_grip=%s to_left_grip=%s",
                    label, index, vector_text(centre), offset(centre, grips.right), offset(centre, grips.left))
            end
        end
    end
    local function scan(unit, reason)
        local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local inventory = unit_data and unit_data:read_component("inventory")
        local equipment = loadout and loadout._equipment
        local slot = inventory and equipment and equipment[inventory.wielded_slot]
        if not slot then return end
        local grips = {
            right = presentation.controller_grip_target and presentation.controller_grip_target(),
            left = presentation.left_controller_grip_target and presentation.left_controller_grip_target(),
        }
        mod:info("DARKTIDEVR_ATTACHMENT_SCAN begin reason=%s slot=%s item=%s", reason,
            tostring(inventory.wielded_slot), tostring(slot.item and slot.item.name))
        describe("unit_3p", slot.unit_3p, slot.item and slot.item.name, grips)
        describe("unit_1p", slot.unit_1p, slot.item and slot.item.name, grips)
        for _, side in ipairs({"3p", "1p"}) do
            local by_unit = slot["attachments_by_unit_" .. side]
            local names = slot["item_name_by_unit_" .. side]
            for owner, attachments in pairs(type(by_unit) == "table" and by_unit or {}) do
                for index, attachment in ipairs(attachments) do
                    describe(string.format("attachment_%s index=%d owner=%s", side, index, tostring(owner)),
                        attachment, names and names[attachment], grips)
                end
            end
        end
        mod:info("DARKTIDEVR_ATTACHMENT_SCAN end reason=%s", reason)
    end
    -- Drift: every scene-graph node of the wielded 3P weapon unit and its
    -- attachments, sampled in its unit root's space every DRIFT_EVERY frames.
    -- A node rigid with the gun keeps its local position as the gun moves; a
    -- node driven by something else (the character's animation) drifts.
    local DRIFT_EVERY, DRIFT_SAMPLES, DRIFT_LOG_METRES = 15, 120, 0.02
    local drift
    local function drift_units(unit)
        local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local inventory = unit_data and unit_data:read_component("inventory")
        local slot = inventory and loadout and loadout._equipment and loadout._equipment[inventory.wielded_slot]
        if not slot or not slot.unit_3p then return nil end
        local units = {{label = "weapon_3p", unit = slot.unit_3p}}
        local by_unit = slot.attachments_by_unit_3p
        for _, attachments in pairs(type(by_unit) == "table" and by_unit or {}) do
            for index, attachment in ipairs(attachments) do
                local name = slot.item_name_by_unit_3p and slot.item_name_by_unit_3p[attachment]
                units[#units + 1] = {label = string.format("attachment_%d:%s", index, tostring(name):match("[^/]+$")), unit = attachment}
            end
        end
        return inventory.wielded_slot, units
    end
    local function drift_update(unit)
        local slot, units = drift_units(unit)
        if not slot or slot ~= "slot_secondary" then return end
        if not drift then drift = {frame = 0, samples = 0, nodes = {}} end
        if drift.done then return end
        drift.frame = drift.frame + 1
        if drift.frame % DRIFT_EVERY ~= 0 then return end
        drift.samples = drift.samples + 1
        local right = presentation.controller_grip_target and presentation.controller_grip_target()
        for _, entry in ipairs(units) do
            local u = entry.unit
            if u and Unit.alive(u) then
                local root = Unit.world_pose(u, 1)
                local inverse = Matrix4x4.inverse(root)
                local count = Unit.num_scene_graph_items(u)
                for index = 1, count do
                    local world = Unit.world_position(u, index)
                    local local_position = Matrix4x4.transform(inverse, world)
                    local key = entry.label .. "#" .. index
                    local node = drift.nodes[key]
                    if not node then
                        node = {first = Vector3Box(local_position), max = 0, label = entry.label, index = index, count = count}
                        drift.nodes[key] = node
                    else
                        local d = Vector3.length(local_position - node.first:unbox())
                        if d > node.max then
                            node.max = d
                            node.world = Vector3Box(world)
                            node.to_right = right and Vector3.length(world - right) or -1
                        end
                    end
                end
            end
        end
        if drift.samples >= DRIFT_SAMPLES then
            drift.done = true
            local drifting = 0
            for _, node in pairs(drift.nodes) do
                if node.max > DRIFT_LOG_METRES then
                    drifting = drifting + 1
                    local world = node.world and node.world:unbox()
                    mod:info("DARKTIDEVR_ATTACHMENT_SCAN drift %s node=%d/%d max_local_drift_m=%.3f world=%s to_right_grip=%.3f",
                        node.label, node.index, node.count, node.max, vector_text(world), node.to_right or -1)
                end
            end
            mod:info("DARKTIDEVR_ATTACHMENT_SCAN drift_done samples=%d drifting_nodes=%d", drift.samples, drifting)
        end
    end
    function api.update(unit)
        if not unit or not flag() then return end
        pcall(drift_update, unit)
        local ok, err = pcall(function()
            local weapon = ScriptUnit.has_extension(unit, "weapon_system")
            local template = weapon and weapon:weapon_template()
            local action = weapon and weapon:running_action_settings()
            local name = template and template.name or "none"
            local reloading = action and type(action.kind) == "string" and action.kind:match("^reload") ~= nil
            local key = name .. (reloading and ":reload" or ":idle")
            if logged[key] then return end
            logged[key] = true
            scan(unit, reloading and "reloading" or "wielded")
        end)
        if not ok and not logged.failure then
            logged.failure = true
            mod:info("DARKTIDEVR_ATTACHMENT_SCAN failed=%s", tostring(err):sub(1, 160))
        end
    end
    return api
end

return Scan
