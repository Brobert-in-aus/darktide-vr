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
    -- View mode (flag "view variant=<name> yaw=<degrees> hide=<a>-<b>,..."):
    -- while the ranged weapon is wielded, the right controller is held at a
    -- fixed pose ahead of the headset so an eye readback shows the gun hand,
    -- and the listed meshes of the third-person receiver are hidden. Used to
    -- find the stray cartridge by elimination.
    api.view = nil
    local function parse_view(value)
        local rest = value:match("^%s*view(.-)%s*$")
        if not rest then return nil end
        local view = {variant = rest:match("variant=([%w_]+)") or "base",
            yaw = tonumber(rest:match("yaw=(%-?[%d.]+)")) or 60, hide = {},
            -- unit=<word>: hide every 3P attachment whose item name contains it.
            unit = rest:match("unit=([%w_,]+)"),
            -- group=<name>: hide that visibility group on the receiver.
            group = rest:match("group=([%w_]+)"),
            -- ads=1: hold the left trigger (aim down sights) while posed.
            ads = rest:match("ads=1") ~= nil,
            -- sight=1: grip placed so the sight line (11.8 cm above it) runs
            -- through the head origin, 25 cm ahead.
            sight = rest:match("sight=1") ~= nil,
            -- left=N: the off hand in weapon hand holster N; press=1 holds its
            -- grip after 60 frames; far=1 holds the gun further out.
            left = tonumber(rest:match("left=(%d)")),
            press = rest:match("press=1") ~= nil,
            far = rest:match("far=1") ~= nil,
            lowleft = rest:match("lowleft=1") ~= nil}
        for a, b in (rest:match("hide=([%d,%-]+)") or ""):gmatch("(%d+)%-?(%d*)") do
            for index = tonumber(a), tonumber(b ~= "" and b or a) do view.hide[index] = true end
        end
        return view
    end
    local function flag()
        poll = poll - 1
        if poll > 0 then return enabled end
        poll = 30
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Scan.FLAG, "r")
        if not file then enabled = false; api.view = nil; return false end
        local value = file:read("*all"); file:close()
        value = type(value) == "string" and value or ""
        local view = parse_view(value)
        if not (view and api.view and view.variant == api.view.variant) then api.view = view end
        enabled = value:match("^%s*scan%s*$") ~= nil or view ~= nil
        return enabled
    end
    -- Called after the controller poses are read each frame.
    function api.override_controllers(observation)
        local view = api.view
        if not view or not view.active then return end
        local half = math.rad(view.yaw) * 0.5
        local qz, qw = math.sin(half), math.cos(half)
        for _, kind in ipairs({"grip", "aim"}) do
            observation["right_" .. kind .. "_x"] = view.sight and 0.032 or 0.12
            observation["right_" .. kind .. "_y"] = view.sight and 0.25 or (view.far and 0.55 or 0.32)
            observation["right_" .. kind .. "_z"] = view.sight and -0.118 or -0.10
            observation["right_" .. kind .. "_qx"] = 0
            observation["right_" .. kind .. "_qy"] = 0
            observation["right_" .. kind .. "_qz"] = qz
            observation["right_" .. kind .. "_qw"] = qw
        end
        if view.left then
            local Forearm = presentation.forearm_holsters_module
            local along = -((Forearm and Forearm.ZONE_START or 0.10) + (Forearm and Forearm.ZONE_SPACING or 0.065) * (view.left - 1))
            local height = Forearm and Forearm.ZONE_HEIGHT or 0.035
            -- Yaw about z: forward (0,1,0) turns to (-sin, cos, 0).
            local yaw = math.rad(view.yaw)
            local fx, fy = -math.sin(yaw), math.cos(yaw)
            for _, kind in ipairs({"grip", "aim"}) do
                observation["left_" .. kind .. "_x"] = observation.right_grip_x + fx * along
                observation["left_" .. kind .. "_y"] = observation.right_grip_y + fy * along
                observation["left_" .. kind .. "_z"] = observation.right_grip_z + height - (view.lowleft and 0.15 or 0)
                observation["left_" .. kind .. "_qx"] = 0
                observation["left_" .. kind .. "_qy"] = 0
                observation["left_" .. kind .. "_qz"] = qz
                observation["left_" .. kind .. "_qw"] = qw
            end
        end
    end
    -- While held: no firing, reloading, grips or wield switches (right trigger,
    -- both grips, right stick up and down), so the weapon and ammo stay put.
    local VIEW_MASK = bit.bnot(1 + 4 + 512 + 2048 + 4096)
    function api.mask_gameplay_input(observation)
        local view = api.view
        if not view or not view.active then return end
        for _, name in ipairs({"gameplay_pressed", "gameplay_held", "gameplay_released"}) do
            local values = observation[name]
            if values then values[0] = bit.band(tonumber(values[0]) or 0, VIEW_MASK) end
        end
        if view.left and view.press and (view.frames or 0) > 60 then
            local held, pressed = observation.gameplay_held, observation.gameplay_pressed
            if held then held[0] = bit.bor(tonumber(held[0]) or 0, 512) end
            if pressed and not view.left_pressed then pressed[0] = bit.bor(tonumber(pressed[0]) or 0, 512) end
            view.left_pressed = true
        end
        if view.ads then
            local held, pressed, released = observation.gameplay_held, observation.gameplay_pressed, observation.gameplay_released
            if held then held[0] = bit.bor(tonumber(held[0]) or 0, 2) end
            if pressed and not view.ads_pressed then pressed[0] = bit.bor(tonumber(pressed[0]) or 0, 2) end
            if released then released[0] = bit.band(tonumber(released[0]) or 0, bit.bnot(2)) end
            view.ads_pressed = true
        end
    end
    local hidden, hidden_units = {}, {}
    local restore_group
    local function unit_matches(view, name)
        if not (view and view.unit and type(name) == "string") then return false end
        for word in view.unit:gmatch("[^,]+") do
            if name:find(word, 1, true) then return true end
        end
        return false
    end
    local function view_update(unit)
        local view = api.view
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local inventory = unit_data and unit_data:read_component("inventory")
        local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
        local slot = inventory and loadout and loadout._equipment and loadout._equipment[inventory.wielded_slot]
        local ranged = view and slot and inventory.wielded_slot == "slot_secondary" and slot.unit_3p
        if view then view.active = ranged and true or false end
        if not ranged then
            if view then view.frames = 0 end
            view = nil
        end
        local receiver
        for _, attachment in ipairs(ranged and slot.attachments_by_unit_3p and slot.attachments_by_unit_3p[slot.unit_3p] or {}) do
            local name = slot.item_name_by_unit_3p and slot.item_name_by_unit_3p[attachment]
            if type(name) == "string" and name:find("reciever", 1, true) then receiver = attachment end
        end
        for hidden_unit in pairs(hidden_units) do
            local name = slot and slot.item_name_by_unit_3p and slot.item_name_by_unit_3p[hidden_unit]
            if not unit_matches(view, name) then
                if Unit.alive(hidden_unit) then Unit.set_unit_visibility(hidden_unit, true) end
                hidden_units[hidden_unit] = nil
            end
        end
        if view and view.unit then
            for _, attachment in ipairs(slot.attachments_by_unit_3p and slot.attachments_by_unit_3p[slot.unit_3p] or {}) do
                local name = slot.item_name_by_unit_3p and slot.item_name_by_unit_3p[attachment]
                if unit_matches(view, name) then
                    Unit.set_unit_visibility(attachment, false)
                    hidden_units[attachment] = true
                end
            end
        end
        for mesh_unit, indices in pairs(hidden) do
            for index in pairs(indices) do
                if mesh_unit ~= receiver or not (view and view.hide[index]) then
                    if Unit.alive(mesh_unit) then Unit.set_mesh_visibility(mesh_unit, index, true) end
                    indices[index] = nil
                end
            end
        end
        if receiver and not logged.groups then
            logged.groups = true
            local found = {}
            for _, name in ipairs({"bullet", "bullets", "ammo", "clip", "magazine", "mag", "round", "rounds",
                    "shell", "shells", "cartridge", "reload", "stripper_clip", "top_bullet", "bullet_01", "clip_bullets"}) do
                local ok, has = pcall(Unit.has_visibility_group, receiver, name)
                if ok and has then found[#found + 1] = name end
            end
            mod:info("DARKTIDEVR_ATTACHMENT_SCAN receiver visibility_groups=%s", table.concat(found, ","))
        end
        if receiver and view and view.group and Unit.has_visibility_group(receiver, view.group) then
            Unit.set_visibility(receiver, view.group, false)
            restore_group = {unit = receiver, group = view.group}
        elseif restore_group and Unit.alive(restore_group.unit) then
            Unit.set_visibility(restore_group.unit, restore_group.group, true)
            restore_group = nil
        end
        if not view or not receiver then return end
        hidden[receiver] = hidden[receiver] or {}
        local meshes = Unit.num_meshes(receiver)
        for index in pairs(view.hide) do
            if index <= meshes then
                Unit.set_mesh_visibility(receiver, index, false)
                hidden[receiver][index] = true
            end
        end
        view.frames = (view.frames or 0) + 1
        if view.frames == 90 then
            local weapon = ScriptUnit.has_extension(unit, "weapon_system")
            local action = weapon and weapon:running_action_settings()
            mod:info("DARKTIDEVR_ATTACHMENT_SCAN view variant=%s ready yaw=%.0f hidden_units=%d hidden=%d action=%s",
                view.variant, view.yaw, (function() local n = 0 for _ in pairs(hidden_units) do n = n + 1 end return n end)(), #(function() local t = {} for i in pairs(view.hide) do t[#t + 1] = i end return t end)(),
                tostring(action and action.kind))
        end
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
        -- Centres also in the unit root's frame, to match against drifting nodes.
        local inverse = Matrix4x4.inverse(Unit.world_pose(unit, 1))
        for index = 1, math.min(meshes, 80) do
            local ok, mesh = pcall(Unit.mesh, unit, index)
            local box_ok, pose, extents = false, nil, nil
            if ok and mesh then box_ok, pose, extents = pcall(Mesh.box, mesh) end
            if box_ok and pose then
                local centre = Matrix4x4.translation(pose)
                local visible_ok, visible = pcall(Mesh.is_visible, mesh)
                mod:info("DARKTIDEVR_ATTACHMENT_SCAN %s mesh=%d centre=%s local=%s extents=%s visible=%s to_right_grip=%s to_left_grip=%s",
                    label, index, vector_text(centre), vector_text(Matrix4x4.transform(inverse, centre)),
                    vector_text(extents), visible_ok and tostring(visible) or "?",
                    offset(centre, grips.right), offset(centre, grips.left))
            end
        end
        -- Every scene-graph node's offset from the root, with its parent, so
        -- meshes can be tied to the node that carries them.
        local count = Unit.num_scene_graph_items and Unit.num_scene_graph_items(unit) or 0
        for index = 2, math.min(count, 80) do
            local parent = Unit.scene_graph_parent(unit, index)
            mod:info("DARKTIDEVR_ATTACHMENT_SCAN %s node=%d parent=%s local=%s scale=%s", label, index, tostring(parent),
                vector_text(Matrix4x4.transform(inverse, Unit.world_position(unit, index))),
                vector_text(Unit.local_scale(unit, index)))
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
                        -- Where it sits at the first sample: world, distance to the right grip,
                        -- and offset from the unit root in the root's frame (x forward).
                        node = {first = Vector3Box(local_position), max = 0, label = entry.label, index = index, count = count,
                            first_world = Vector3Box(world), first_to_right = right and Vector3.length(world - right) or -1}
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
                    mod:info("DARKTIDEVR_ATTACHMENT_SCAN drift %s node=%d/%d max_local_drift_m=%.3f world=%s to_right_grip=%.3f first_world=%s first_to_right_grip=%.3f first_local=%s",
                        node.label, node.index, node.count, node.max, vector_text(world), node.to_right or -1,
                        vector_text(node.first_world:unbox()), node.first_to_right or -1, vector_text(node.first:unbox()))
                end
            end
            mod:info("DARKTIDEVR_ATTACHMENT_SCAN drift_done samples=%d drifting_nodes=%d", drift.samples, drifting)
        end
    end
    -- Sight line (todo item 4): the hidden first-person rig still plays the
    -- stock aim-down-sights pose, which puts the sight on the first-person
    -- camera. Once ADS has settled, log that eye and the VR aim ray origin
    -- in each muzzle's frame, with the camera and aim forward directions.
    local ads_since, sight_logged = nil, {}
    local function in_frame(pose, position)
        return vector_text(Matrix4x4.transform(Matrix4x4.inverse(pose), position))
    end
    local function direction_in_frame(pose, direction)
        local inverse = Quaternion.inverse(Matrix4x4.rotation(pose))
        return vector_text(Quaternion.rotate(inverse, direction))
    end
    local function sight_update(unit, t)
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local alternate = unit_data and unit_data:read_component("alternate_fire")
        local inventory = unit_data and unit_data:read_component("inventory")
        if not alternate or not alternate.is_active or not inventory or inventory.wielded_slot ~= "slot_secondary" then
            ads_since = nil; return
        end
        ads_since = ads_since or t
        if t - ads_since < 0.8 then return end
        local weapon = ScriptUnit.has_extension(unit, "weapon_system")
        local template = weapon and weapon:weapon_template()
        local name = template and template.name
        local key = tostring(name) .. ":" .. tostring(api.view and api.view.variant)
        if not name or sight_logged[key] then return end
        sight_logged[key] = true
        local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
        local muzzle_name = template.fx_sources and template.fx_sources._muzzle
        local unit_1p, node_1p, unit_3p, node_3p
        if loadout and muzzle_name then
            unit_1p, node_1p, unit_3p, node_3p = loadout:unit_and_node_from_node_name("slot_secondary", muzzle_name)
        end
        local first_person = ScriptUnit.has_extension(unit, "first_person_system")
        local fp_unit = first_person and first_person:first_person_unit()
        local aim_position, aim_rotation
        if presentation.weapon_aim_target then aim_position, aim_rotation = presentation.weapon_aim_target("dominant") end
        mod:info("DARKTIDEVR_ATTACHMENT_SCAN sight template=%s muzzle=%s node_1p=%s node_3p=%s",
            name, tostring(muzzle_name), tostring(node_1p), tostring(node_3p))
        if unit_1p and node_1p and fp_unit then
            local muzzle = Unit.world_pose(unit_1p, node_1p)
            mod:info("DARKTIDEVR_ATTACHMENT_SCAN sight first_person eye_in_muzzle=%s camera_forward_in_muzzle=%s",
                in_frame(muzzle, Unit.world_position(fp_unit, 1)),
                direction_in_frame(muzzle, Quaternion.forward(Unit.world_rotation(fp_unit, 1))))
        end
        if unit_3p and node_3p and aim_position and aim_rotation then
            local muzzle = Unit.world_pose(unit_3p, node_3p)
            local grip = presentation.weapon_grip_target and presentation.weapon_grip_target("dominant")
            local reticle = presentation.controller_aim and presentation.controller_aim.reticle_world_point
            mod:info("DARKTIDEVR_ATTACHMENT_SCAN sight vr aim_origin_in_muzzle=%s aim_forward_in_muzzle=%s grip_in_muzzle=%s reticle_in_muzzle=%s reticle_distance=%s",
                in_frame(muzzle, aim_position), direction_in_frame(muzzle, Quaternion.forward(aim_rotation)),
                grip and in_frame(muzzle, grip) or "nil", reticle and in_frame(muzzle, reticle:unbox()) or "nil",
                tostring(presentation.controller_aim and presentation.controller_aim.reticle_distance))
        end
    end
    function api.update(unit)
        if not flag() and not next(hidden) and not next(hidden_units) then return end
        if not unit then return end
        local view_ok, view_error = pcall(view_update, unit)
        if not view_ok and not logged.view_failure then
            logged.view_failure = true
            mod:info("DARKTIDEVR_ATTACHMENT_SCAN view_failed=%s", tostring(view_error):sub(1, 160))
        end
        if not enabled then return end
        pcall(drift_update, unit)
        local sight_ok, sight_error = pcall(sight_update, unit, Managers.time and Managers.time:time("gameplay") or 0)
        if not sight_ok and not logged.sight_failure then
            logged.sight_failure = true
            mod:info("DARKTIDEVR_ATTACHMENT_SCAN sight_failed=%s", tostring(sight_error):sub(1, 160))
        end
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
