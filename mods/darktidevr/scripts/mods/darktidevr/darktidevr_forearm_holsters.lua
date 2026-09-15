-- Weapon hand holsters (option "vr_forearm_holsters", default off; user
-- request, 15 September): small holsters along the gun hand's forearm. The
-- off hand reaches into one and presses grip to wield what it holds, through
-- the same grip request as the body holsters (darktidevr_holsters.lua). Each
-- occupied holster always shows a miniature of its item; the one the off hand
-- is in grows a little and ticks in that hand.
--
-- Layout (user, 15 September evening): 8 cm grab zones with 4 cm between
-- them, in a line above the forearm along the gun hand's aim, the weapon
-- above the wrist. The miniature is drawn at its grab zone.
--   1. the other weapon (ranged while the melee weapon is out, and back)
--   2. stim, 3. carried item, 4. device
--
-- Worn, 15 September evening: the first layout used the controller grip's
-- axes, which put the holsters below the wrist; the 3.5 cm grab zones were
-- far too small; the miniatures overlapped; fixed scales left the weapon tiny
-- and the medkit and ammo pack large. Miniatures are now fitted to one size.
local Forearm = {}

-- The wrist sits about 8 cm behind the controller grip.
Forearm.ZONE_START = 0.08
Forearm.ZONE_RADIUS = 0.04
Forearm.ZONE_GAP = 0.04
Forearm.ZONE_SPACING = 2 * Forearm.ZONE_RADIUS + Forearm.ZONE_GAP
-- 5 cm higher than the first line (worn, 15 September evening).
Forearm.ZONE_HEIGHT = 0.13
-- Every miniature's largest dimension, and its growth while hovered.
-- Larger again (worn, 15 September evening, twice).
Forearm.PREVIEW_SIZE = 0.13
Forearm.HOVER_SCALE = 1.25
-- Scale used until the item's meshes report a size, and if they never do.
Forearm.SPAWN_SCALE = 0.2
Forearm.FALLBACK_SCALE = 0.12
Forearm.FIT_TIMEOUT = 3
Forearm.TEST_FLAG = "./../mods/darktidevr/darktidevr_forearm_holsters_test.flag"
-- Hidden while this close (degrees, from the eye) to the line to the reticle
-- and nearer than it: they must not block aiming (worn, 15 September evening).
Forearm.AIM_CLEAR_DEGREES = 12
-- Labels: the weapon's name above a hovered weapon miniature (with holster
-- labels on), the gun's ammo always below it; metres per overlay pixel.
Forearm.LABEL_GAP = 0.012
Forearm.LABEL_FONT = 54
Forearm.LABEL_PIXEL_METRES = 0.0003

-- The scale that makes an item whose largest unscaled dimension is extent
-- PREVIEW_SIZE long, or nil for an unusable extent. Pure.
function Forearm.fit_scale(extent)
    if type(extent) ~= "number" or extent ~= extent or extent < 0.01 or extent > 10 then return nil end
    return Forearm.PREVIEW_SIZE / extent
end

-- A preview's scale this frame. Pure.
function Forearm.shown_scale(base, hovered)
    return hovered and base * Forearm.HOVER_SCALE or base
end

Forearm.SLOTS = {
    {id = "forearm_weapon"},
    {id = "forearm_stim", slot = "slot_pocketable_small", selector = "stim"},
    {id = "forearm_carried", slot = "slot_pocketable", selector = "pocketable"},
    {id = "forearm_device", slot = "slot_device", selector = "device"},
}

-- The slot and selector of each zone for the wielded slot. Pure.
function Forearm.assignment(index, wielded_slot)
    local entry = Forearm.SLOTS[index]
    if not entry then return nil end
    if entry.id == "forearm_weapon" then
        if wielded_slot == "slot_secondary" then return "slot_primary", "melee" end
        return "slot_secondary", "ranged"
    end
    return entry.slot, entry.selector
end

-- The forearm's "above" direction that ignores wrist roll: world up with
-- its component along the forearm removed, like the ammo counter's world-up
-- placement (user, 15 September evening). Falls back to the given axis when
-- the forearm points almost straight up or down. 3-arrays. Pure.
function Forearm.stable_up(forward, fallback)
    local d = forward[3]
    local up = {-forward[1] * d, -forward[2] * d, 1 - forward[3] * d}
    local length = math.sqrt(up[1] ^ 2 + up[2] ^ 2 + up[3] ^ 2)
    if length < 0.2 then return fallback end
    return {up[1] / length, up[2] / length, up[3] / length}
end

-- The horizontal direction a miniature's long axis lies along so it turns
-- about world up to face the eye side-on (a cylindrical billboard). 3-arrays;
-- nil when the eye is straight above or below. Pure.
function Forearm.billboard_side(position, eye)
    local fx, fy = eye[1] - position[1], eye[2] - position[2]
    local length = math.sqrt(fx * fx + fy * fy)
    if length < 1e-4 then return nil end
    fx, fy = fx / length, fy / length
    -- cross(to_eye, up) with up = z
    return {fy, -fx, 0}
end

-- Whether an item sits roughly between the eye and the target: nearer than
-- the target and within degrees of the line to it. 3-arrays. Pure.
function Forearm.in_aim_line(item, eye, target, degrees)
    local a = {item[1] - eye[1], item[2] - eye[2], item[3] - eye[3]}
    local b = {target[1] - eye[1], target[2] - eye[2], target[3] - eye[3]}
    local la = math.sqrt(a[1] ^ 2 + a[2] ^ 2 + a[3] ^ 2)
    local lb = math.sqrt(b[1] ^ 2 + b[2] ^ 2 + b[3] ^ 2)
    if la < 1e-4 or lb < 1e-4 or la >= lb then return false end
    local cosine = (a[1] * b[1] + a[2] * b[2] + a[3] * b[3]) / (la * lb)
    return cosine >= math.cos(math.rad(degrees))
end

-- A forearm point in world space from the gun hand's grip position and the
-- forearm's axes (3-arrays: forward along the aim, up above it). Pure.
function Forearm.centre(index, grip, forward, up)
    local along = -(Forearm.ZONE_START + Forearm.ZONE_SPACING * (index - 1))
    return {grip[1] + forward[1] * along + up[1] * Forearm.ZONE_HEIGHT,
        grip[2] + forward[2] * along + up[2] * Forearm.ZONE_HEIGHT,
        grip[3] + forward[3] * along + up[3] * Forearm.ZONE_HEIGHT}
end

function Forearm.install(mod, presentation)
    local api = {}
    -- Persistent zone tables: the holster state compares zones by identity.
    local zones = {}
    for index, entry in ipairs(Forearm.SLOTS) do
        zones[index] = {id = entry.id, centre = {0, 0, 0}, radius = Forearm.ZONE_RADIUS, world = {0, 0, 0}}
    end
    local local_zones = {}
    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Forearm.TEST_FLAG, "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and (value:match("^%s*enabled%s*$") ~= nil or
            value:match("^%s*front%s*$") ~= nil)
        -- "front": previews 50 cm ahead of the eye, to check they render.
        api.test_front = type(value) == "string" and value:match("^%s*front%s*$") ~= nil
        return test_enabled
    end
    function api.enabled()
        return (mod.get and mod:get("vr_forearm_holsters") == true) or test_flag()
    end
    local function array(v) return v and {Vector3.x(v), Vector3.y(v), Vector3.z(v)} or nil end
    local function eye_of(unit)
        if not presentation.eye_pose then return nil end
        local position, rotation = presentation.eye_pose(unit)
        return position, rotation
    end

    -- The gun hand's grip as drawn (presentation.visible_grip_target: the
    -- glove after gun alignment, which follows the walking avatar's gun), the
    -- aim's forward and the roll-free up, or nil. Anchoring to the raw
    -- controller flickered while the character moved (worn, 15 September).
    local function hand_basis()
        local position, grip_rotation
        if presentation.visible_grip_target then
            position, grip_rotation = presentation.visible_grip_target("dominant")
        else
            position, grip_rotation = presentation.weapon_grip_target("dominant")
        end
        if not position then return nil end
        local aim
        if presentation.weapon_aim_target then
            local _, rotation = presentation.weapon_aim_target("dominant")
            aim = rotation
        end
        local rotation = aim or grip_rotation
        if not rotation then return nil end
        local forward = array(Quaternion.forward(rotation))
        return array(position), forward, Forearm.stable_up(forward, array(Quaternion.up(rotation)))
    end

    -- Zones in the holster body frame (x right, y forward, z up, divided by
    -- the frame scale) for the off hand this frame, or nil.
    function api.local_zones(unit, frame, Holsters, inventory)
        if not frame then return nil end
        local grip, forward, up = hand_basis()
        if not grip then return nil end
        for index, zone in ipairs(zones) do
            local world = Forearm.centre(index, grip, forward, up)
            zone.world = world
            zone.slot, zone.selector = Forearm.assignment(index, inventory and inventory.wielded_slot)
            zone.centre = Holsters.local_point(frame, world)
            zone.radius = Forearm.ZONE_RADIUS / frame.scale
            local_zones[index] = zone
        end
        api.grip, api.forward, api.up = grip, forward, up
        return local_zones
    end

    -- Miniature previews: one UIWeaponSpawner per zone, respawned when the
    -- zone's item changes, fitted to PREVIEW_SIZE once its meshes report a
    -- size, and posed every frame.
    local UIWeaponSpawner, UIUnitSpawner
    local previews, preview_world, failed = {}, nil, false
    local hovered_id
    local logged_boxes = {}
    local function destroy_preview(preview)
        if preview.spawner then pcall(preview.spawner.destroy, preview.spawner) end
        if preview.unit_spawner then pcall(preview.unit_spawner.destroy, preview.unit_spawner) end
    end
    function api.destroy()
        for index, preview in pairs(previews) do destroy_preview(preview); previews[index] = nil end
        preview_world, hovered_id = nil, nil
    end
    local function item_in(unit, slot)
        local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
        local equipment = loadout and loadout._equipment and loadout._equipment[slot]
        return equipment and equipment.item or nil
    end
    local function collect_units(value, out, depth)
        if depth > 3 then return out end
        if type(value) == "userdata" then
            out[#out + 1] = value
        elseif type(value) == "table" then
            for _, inner in pairs(value) do collect_units(inner, out, depth + 1) end
        end
        return out
    end
    -- The item's meshes in the link unit's unscaled frame: the largest
    -- dimension, the box count and the bounds' centre, or nil while no mesh
    -- reports a size.
    -- log_boxes: an item name, to log every box once (bounds investigation).
    local function model_extent(data, log_boxes)
        local link = data.link_unit
        local inverse = Matrix4x4.inverse(Unit.world_pose(link, 1))
        local low, high = {math.huge, math.huge, math.huge}, {-math.huge, -math.huge, -math.huge}
        local units = collect_units(data.attachment_units_3p, {data.item_unit_3p}, 0)
        local boxes = 0
        for _, candidate in ipairs(units) do
            local alive_ok, alive = pcall(Unit.alive, candidate)
            if alive_ok and alive then
                for mesh_index = 1, Unit.num_meshes(candidate) do
                    local ok, pose, half = pcall(Mesh.box, Unit.mesh(candidate, mesh_index))
                    if ok and pose and half and Vector3.length(half) > 1e-4 then
                        boxes = boxes + 1
                        if log_boxes then
                            local mid = Matrix4x4.transform(inverse, Matrix4x4.translation(pose))
                            mod:info("DARKTIDEVR_FOREARM_HOLSTERS box item=%s unit=%s mesh=%d centre=%.3f,%.3f,%.3f half=%.3f,%.3f,%.3f",
                                tostring(log_boxes), tostring(candidate == data.item_unit_3p and "item" or "attachment"),
                                mesh_index, Vector3.x(mid), Vector3.y(mid), Vector3.z(mid),
                                Vector3.x(half), Vector3.y(half), Vector3.z(half))
                        end
                        local hx, hy, hz = Vector3.x(half), Vector3.y(half), Vector3.z(half)
                        for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
                            local world = Matrix4x4.transform(pose, Vector3(sx * hx, sy * hy, sz * hz))
                            local p = Matrix4x4.transform(inverse, world)
                            local c = {Vector3.x(p), Vector3.y(p), Vector3.z(p)}
                            for i = 1, 3 do
                                if c[i] < low[i] then low[i] = c[i] end
                                if c[i] > high[i] then high[i] = c[i] end
                            end
                        end end end
                    end
                end
            end
        end
        if boxes == 0 then return nil end
        return math.max(high[1] - low[1], high[2] - low[2], high[3] - low[3]), boxes,
            {(low[1] + high[1]) * 0.5, (low[2] + high[2]) * 0.5, (low[3] + high[3]) * 0.5}
    end
    local Ammo
    local function ammo_text(unit)
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local slot = unit_data and unit_data:read_component("slot_secondary")
        if not slot then return nil end
        Ammo = Ammo or require("scripts/utilities/ammo")
        local ok, clip = pcall(Ammo.current_ammo_in_clips, slot)
        if not ok or type(clip) ~= "number" then return nil end
        local reserve = slot.current_ammunition_reserve
        return type(reserve) == "number" and string.format("%d / %d", clip, reserve) or tostring(clip)
    end
    local function weapon_name(item)
        local display = item and item.display_name
        if type(display) ~= "string" or display == "" then return nil end
        local ok, text = pcall(Localize, display)
        if ok and type(text) == "string" and not text:find("<unlocalized", 1, true) then return text end
        return nil
    end
    local function label(world, key, position, text)
        local overlay = presentation.hand_overlay
        local canvas = overlay and overlay.canvas(world, key, position, Forearm.LABEL_PIXEL_METRES)
        if canvas then canvas.text(text, Forearm.LABEL_FONT, 0, 0, {235, 235, 225, 190}) end
    end
    local function update_previews(world, unit, dt, t)
        if not api.enabled() or presentation.mode ~= 1 then api.destroy(); return end
        local grip, forward, up = hand_basis()
        if not grip then api.destroy(); return end
        if preview_world ~= world then api.destroy(); preview_world = world end
        UIWeaponSpawner = UIWeaponSpawner or require("scripts/managers/ui/ui_weapon_spawner")
        UIUnitSpawner = UIUnitSpawner or require("scripts/managers/ui/ui_unit_spawner")
        local support = presentation.weapon_hand_roles.physical("support")
        -- The zone the off hand is in, from the holster state.
        local holsters = presentation.holsters
        local hand_state = holsters and holsters.hands and holsters.hands[support]
        local hovered = hand_state and hand_state.zone
        local hovered_forearm
        for index, zone in ipairs(zones) do
            if zone == hovered and previews[index] then hovered_forearm = zone end
        end
        local hover_id = hovered_forearm and hovered_forearm.id or nil
        if hover_id and hover_id ~= hovered_id and presentation.haptics and presentation.haptics.pulse and
                (support == "left" or support == "right") then
            pcall(presentation.haptics.pulse, support, "zone", t)
        end
        hovered_id = hover_id
        local eye = eye_of(unit)
        local eye_array = eye and array(eye)
        local aim_state = presentation.controller_aim
        local reticle = aim_state and aim_state.reticle_point_owner == unit and aim_state.reticle_world_point
        local target = reticle and array(reticle:unbox())
        local names_on = mod.get and mod:get("vr_holster_counts") == true
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local inventory = unit_data and unit_data:read_component("inventory")
        for index, zone in ipairs(zones) do
            -- This frame's drawn-hand position (the grab zones use the same).
            zone.slot, zone.selector = Forearm.assignment(index, inventory and inventory.wielded_slot)
            zone.world = Forearm.centre(index, grip, forward, up)
            local item = zone.slot and item_in(unit, zone.slot)
            local preview = previews[index]
            if preview and preview.item ~= item then destroy_preview(preview); previews[index] = nil; preview = nil end
            local centre = Vector3(zone.world[1], zone.world[2], zone.world[3])
            if item and not preview then
                local unit_spawner = UIUnitSpawner:new(world)
                local spawner = UIWeaponSpawner:new("DarktideVRForearm_" .. index, world, nil, unit_spawner)
                local scale = Forearm.SPAWN_SCALE
                spawner:start_presentation(item, centre, Quaternion.identity(), Vector3(scale, scale, scale), nil, false)
                preview = {item = item, spawner = spawner, unit_spawner = unit_spawner, started_t = t}
                previews[index] = preview
                mod:info("DARKTIDEVR_FOREARM_HOLSTERS preview_start zone=%s item=%s", zone.id, tostring(item.name))
            end
            if preview then
                preview.spawner:update(dt, t, nil)
                local data = preview.spawner:get_spawn_data()
                if data and data.link_unit and Unit.alive(data.link_unit) and
                        data.item_unit_3p and Unit.alive(data.item_unit_3p) then
                    if not preview.base_scale then
                        local extent, boxes, middle = model_extent(data)
                        if extent and not logged_boxes[item.name] then
                            logged_boxes[item.name] = true
                            model_extent(data, item.name)
                            if middle then
                                mod:info("DARKTIDEVR_FOREARM_HOLSTERS bounds item=%s middle=%.3f,%.3f,%.3f extent_m=%.3f",
                                    tostring(item.name), middle[1], middle[2], middle[3], extent)
                            end
                        end
                        local fitted = Forearm.fit_scale(extent)
                        if fitted or t - (preview.started_t or t) > Forearm.FIT_TIMEOUT then
                            preview.base_scale = fitted or Forearm.FALLBACK_SCALE
                            preview.extent = fitted and extent or nil
                            preview.middle = fitted and middle or nil
                            mod:info("DARKTIDEVR_FOREARM_HOLSTERS preview_fitted zone=%s item=%s extent_m=%s boxes=%s scale=%.3f",
                                zone.id, tostring(item.name), tostring(extent), tostring(boxes), preview.base_scale)
                        end
                    end
                    -- Turned about world up to face the eye side-on. Melee
                    -- weapons are long along their local z, guns and items along y.
                    local side = eye_array and Forearm.billboard_side(zone.world, eye_array)
                    local side_vector = side and Vector3(side[1], side[2], side[3]) or
                        Vector3.normalize(Vector3.cross(Vector3(forward[1], forward[2], forward[3]), Vector3.up()))
                    local rotation = zone.slot == "slot_primary" and Quaternion.look(Vector3.up(), side_vector) or
                        Quaternion.look(side_vector, Vector3.up())
                    local scale = preview.base_scale and Forearm.shown_scale(preview.base_scale, hover_id == zone.id) or
                        Forearm.SPAWN_SCALE
                    -- The bounds' centre, not the item's origin, sits at the holster.
                    local middle = preview.middle
                    local offset = middle and Quaternion.rotate(rotation, Vector3(middle[1], middle[2], middle[3]) * scale) or
                        Vector3(0, 0, 0)
                    if api.test_front and eye then
                        local _, eye_rotation = eye_of(unit)
                        centre = eye + Quaternion.forward(eye_rotation) * 0.5 + Quaternion.right(eye_rotation) * (0.12 * (index - 2.5))
                    end
                    Unit.set_local_position(data.link_unit, 1, centre - offset)
                    Unit.set_local_rotation(data.link_unit, 1, rotation)
                    Unit.set_local_scale(data.link_unit, 1, Vector3(scale, scale, scale))
                    local in_line = eye_array and target and Forearm.in_aim_line(zone.world, eye_array, target,
                        Forearm.AIM_CLEAR_DEGREES) or false
                    local shown = preview.base_scale ~= nil and not api.debug_hide and not in_line
                    -- Every frame: the spawner shows the unit once streaming completes.
                    Unit.set_unit_visibility(data.item_unit_3p, shown, true)
                    -- The world has already updated this frame: without this the
                    -- miniature draws at last frame's pose and jitters behind a
                    -- moving hand (worn, 15 September evening).
                    World.update_unit_and_children(world, data.link_unit)
                    if shown and zone.id == "forearm_weapon" then
                        local half = (preview.extent and preview.extent * scale or Forearm.PREVIEW_SIZE) * 0.5
                        if names_on and hover_id == zone.id then
                            local name = weapon_name(item)
                            if name then
                                label(world, "forearm_name", centre + Vector3.up() * (half + Forearm.LABEL_GAP), name)
                            end
                        end
                        if zone.slot == "slot_secondary" then
                            local text = ammo_text(unit)
                            if text then
                                label(world, "forearm_ammo", centre - Vector3.up() * (half + Forearm.LABEL_GAP), text)
                            end
                        end
                    end
                end
            end
        end
    end
    function api.update_previews(world, unit, dt, t)
        if failed then return end
        local ok, err = pcall(update_previews, world, unit, dt, t)
        if not ok then
            failed = true
            api.destroy()
            mod:warning("DARKTIDEVR_FOREARM_HOLSTERS preview_error=%s", tostring(err))
        end
    end
    return api
end

return Forearm
