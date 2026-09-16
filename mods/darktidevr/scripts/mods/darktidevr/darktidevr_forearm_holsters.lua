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
-- Labels: the item's name above a hovered miniature (with holster labels on),
-- the gun's ammo always below it; metres per overlay pixel.
Forearm.LABEL_GAP = 0.012
Forearm.LABEL_FONT = 54
Forearm.LABEL_PIXEL_METRES = 0.0003

-- The scale that makes an item whose largest unscaled dimension is extent
-- PREVIEW_SIZE long, or nil for an unusable extent. Pure.
function Forearm.fit_scale(extent)
    if type(extent) ~= "number" or extent ~= extent or extent < 0.01 or extent > 10 then return nil end
    return Forearm.PREVIEW_SIZE / extent
end

-- Whether a mesh box counts toward a miniature's bounds: flat boxes do not.
-- The power maul carries a zero-thickness 0.8 by 0.3 m plane (an effect
-- card, not drawn) reaching 0.8 m below the handle; it pulled the bounds'
-- centre down and the maul sat about 6 cm above its grab zone, unlike the
-- gun (worn, 15 September evening; box logs). Half extents in metres. Pure.
Forearm.MIN_BOX_HALF = 0.001
function Forearm.solid_box(hx, hy, hz)
    return math.min(hx, hy, hz) >= Forearm.MIN_BOX_HALF
end

-- A zone's grab radius for a fitted miniature's shown size (metres along
-- its three axes): half the mean of its two largest dimensions, at least
-- ZONE_RADIUS and at most MAX_GRAB_RADIUS. The medkit, 13 by 10 cm shown,
-- felt far bigger than its 8 cm zone and never grew under the hand (worn, 15
-- September evening). Pure.
Forearm.MAX_GRAB_RADIUS = 0.065
function Forearm.grab_radius(size)
    if type(size) ~= "table" then return Forearm.ZONE_RADIUS end
    local dims = {}
    for i = 1, 3 do
        local d = size[i]
        if type(d) ~= "number" or d ~= d or d < 0 then return Forearm.ZONE_RADIUS end
        dims[i] = d
    end
    table.sort(dims)
    local radius = (dims[2] + dims[3]) * 0.25
    return math.max(Forearm.ZONE_RADIUS, math.min(Forearm.MAX_GRAB_RADIUS, radius))
end

-- Body holster miniatures (user, 15 September evening): the visible body
-- holsters always show their item, so the player knows where to reach; it
-- grows while a hand is in the holster. The shoulder holster is behind the
-- head and the belt holds a blitz, so neither has one.
Forearm.BODY_MODELS = {hip_left = true, hip_right = true, chest_left = true, chest_right = true}
-- With the body holsters active this frame (darktidevr_holsters: available
-- and turned on), the holster frame known, presentation in gameplay and not
-- in the hub. Pure over its arguments.
function Forearm.body_models_enabled(mod, presentation, frame)
    if presentation.current_game_mode_name and presentation.current_game_mode_name() == "hub" then return false end
    return frame ~= nil and presentation.mode == 1 and presentation.holsters ~= nil and
        presentation.holsters.body_active == true
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

-- Hidden while two-handing or aiming down sights, so they never block
-- aiming (user, 15 September evening; they first hid only in line with the
-- reticle). Pure.
function Forearm.hidden_for_aim(two_hand_held, ads_active)
    return two_hand_held == true or ads_active == true
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
        -- Every 300 calls (about five seconds at the input rate): a failed open
        -- on the main thread each poll is where these modules' spikes came
        -- from (docs/LUA-FRAME-PROFILE-2026-09-16.md).
        test_poll = 300
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
        -- Not in the hub, like the wrist display (worn, 15 September evening:
        -- the weapon miniature and its ammo showed there once the holsters
        -- anchored to the controller grip).
        if presentation.current_game_mode_name and presentation.current_game_mode_name() == "hub" then
            return false
        end
        return (mod.get and mod:get("vr_forearm_holsters") == true) or test_flag()
    end
    local function array(v) return v and {Vector3.x(v), Vector3.y(v), Vector3.z(v)} or nil end
    local function eye_of(unit)
        if not presentation.eye_pose then return nil end
        local position, rotation = presentation.eye_pose(unit)
        return position, rotation
    end

    -- The gun hand's controller grip (where the gun's attach node is placed,
    -- darktidevr_gun_aim), the aim's forward at the common weapon pitch and
    -- the roll-free up, or nil. Not the drawn wrist: it comes from the hidden
    -- character's animation, so the holsters moved with the wielded item and
    -- turned and flickered while strafing (worn, 15 September evening). Not
    -- the two-hand aim either (hidden then).
    local function hand_basis()
        local position, grip_rotation = presentation.weapon_grip_target("dominant")
        if not position then return nil end
        local side = presentation.weapon_hand_roles.physical("dominant")
        local _, aim
        if side == "left" and presentation.left_controller_aim_target then
            _, aim = presentation.left_controller_aim_target()
        elseif side == "right" and presentation.controller_aim_target then
            _, aim = presentation.controller_aim_target()
        end
        if aim and presentation.gun_aim and presentation.gun_aim.base_aim then
            local player = Managers and Managers.player and Managers.player:local_player(1)
            aim = presentation.gun_aim.base_aim(player and player.player_unit, aim)
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
            zone.radius = (zone.grab_radius or Forearm.ZONE_RADIUS) / frame.scale
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
        for _, zone in ipairs(zones) do zone.grab_radius = nil end
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
                    if ok and pose and half and Forearm.solid_box(Vector3.x(half), Vector3.y(half), Vector3.z(half)) then
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
            {(low[1] + high[1]) * 0.5, (low[2] + high[2]) * 0.5, (low[3] + high[3]) * 0.5},
            {high[1] - low[1], high[2] - low[2], high[3] - low[3]}
    end
    local Ammo
    local function ammo_text(unit)
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local slot = unit_data and unit_data:read_component("slot_secondary")
        -- A weapon without ammo (a force staff) has no count: it showed 0 / 0
        -- (worn, 15 September evening).
        if not slot or not (type(slot.max_ammunition_reserve) == "number" and slot.max_ammunition_reserve > 0) then
            return nil
        end
        Ammo = Ammo or require("scripts/utilities/ammo")
        local ok, clip = pcall(Ammo.current_ammo_in_clips, slot)
        if not ok or type(clip) ~= "number" then return nil end
        local reserve = slot.current_ammunition_reserve
        return type(reserve) == "number" and string.format("%d / %d", clip, reserve) or tostring(clip)
    end
    local function localized(key)
        if type(key) ~= "string" or key == "" then return nil end
        local ok, text = pcall(Localize, key)
        if ok and type(text) == "string" and text ~= "" and not text:find("<unlocalized", 1, true) then return text end
        return nil
    end
    -- The item's display name; stims, crates and other pocketables have none,
    -- so their pickup's description (the name shown when picking them up)
    -- stands in (worn, 15 September evening: no names on the stim or medkit).
    local Pickups
    local pickup_names
    local function weapon_name(item)
        local name = item and localized(item.display_name)
        if name or not item then return name end
        if not pickup_names then
            pickup_names = {}
            local ok, pickups = pcall(require, "scripts/settings/pickup/pickups")
            Pickups = ok and pickups or nil
            for _, settings in pairs(Pickups and Pickups.by_name or {}) do
                if type(settings) == "table" and settings.inventory_item and settings.description then
                    pickup_names[settings.inventory_item] = settings.description
                end
            end
        end
        return localized(pickup_names[item.name])
    end
    -- The holstered weapon's count: a gun's clip and reserve (or heat), a melee
    -- weapon's special charges, as the ammo count at the hand shows them, but
    -- never peril (user, 15 September evening).
    local NetworkConstants
    local function holstered_text(unit, slot_name)
        local readout = presentation.ammo_readout and presentation.ammo_readout.Readout
        if slot_name == "slot_secondary" then
            local text = ammo_text(unit)
            if text or not readout then return text end
        end
        if not readout then return nil end
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local slot = unit_data and unit_data:read_component(slot_name)
        if not slot then return nil end
        local values
        if slot_name == "slot_primary" then
            local weapon = ScriptUnit.has_extension(unit, "weapon_system")
            local entry = weapon and weapon._weapons and weapon._weapons.slot_primary
            local template = entry and entry.weapon_template
            values = readout.melee_values(slot, template and template.weapon_special_tweak_data)
        else
            Ammo = Ammo or require("scripts/utilities/ammo")
            NetworkConstants = NetworkConstants or require("scripts/network_lookup/network_constants")
            local count = NetworkConstants.clips_in_use and NetworkConstants.clips_in_use.max_size or 1
            values = readout.values(slot, Ammo, count)
        end
        return values and (readout.text(values)) or nil
    end
    local function label(world, key, position, text)
        local overlay = presentation.hand_overlay
        local canvas = overlay and overlay.canvas(world, key, position, Forearm.LABEL_PIXEL_METRES)
        if canvas then canvas.text(text, Forearm.LABEL_FONT, 0, 0, {235, 235, 225, 190}) end
    end
    -- One miniature of item at centre (Vector3), keyed by key: spawned on
    -- demand, fitted to PREVIEW_SIZE once its meshes report a size, turned
    -- about world up to face the eye side-on (fallback_side when the eye is
    -- unknown), grown while hovered and drawn only when visible. on_fitted runs
    -- once with the preview and its fitted scale. Returns the preview and its
    -- shown scale while it is drawn, else nil.
    local function place_preview(world, key, zone_id, slot, item, centre, hovered, visible, eye_array,
            fallback_side, dt, t, on_fitted)
        local preview = previews[key]
        if preview and preview.item ~= item then destroy_preview(preview); previews[key] = nil; preview = nil end
        if not item then return nil end
        if not preview then
            local unit_spawner = UIUnitSpawner:new(world)
            local spawner = UIWeaponSpawner:new("DarktideVRHolster_" .. tostring(key), world, nil, unit_spawner)
            local scale = Forearm.SPAWN_SCALE
            spawner:start_presentation(item, centre, Quaternion.identity(), Vector3(scale, scale, scale), nil, false)
            preview = {item = item, spawner = spawner, unit_spawner = unit_spawner, started_t = t}
            previews[key] = preview
            mod:info("DARKTIDEVR_FOREARM_HOLSTERS preview_start zone=%s item=%s", tostring(zone_id), tostring(item.name))
        end
        preview.spawner:update(dt, t, nil)
        local data = preview.spawner:get_spawn_data()
        if not (data and data.link_unit and Unit.alive(data.link_unit) and
                data.item_unit_3p and Unit.alive(data.item_unit_3p)) then
            return nil
        end
        if not preview.base_scale then
            local extent, boxes, middle, size = model_extent(data)
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
                preview.size = fitted and size or nil
                if on_fitted then on_fitted(preview, fitted) end
                mod:info("DARKTIDEVR_FOREARM_HOLSTERS preview_fitted zone=%s item=%s extent_m=%s boxes=%s scale=%.3f",
                    tostring(zone_id), tostring(item.name), tostring(extent), tostring(boxes), preview.base_scale)
            end
        end
        -- Melee weapons are long along their local z, guns and items along y.
        local position = {Vector3.x(centre), Vector3.y(centre), Vector3.z(centre)}
        local side = eye_array and Forearm.billboard_side(position, eye_array)
        local side_vector = side and Vector3(side[1], side[2], side[3]) or fallback_side
        local rotation = slot == "slot_primary" and Quaternion.look(Vector3.up(), side_vector) or
            Quaternion.look(side_vector, Vector3.up())
        local scale = preview.base_scale and Forearm.shown_scale(preview.base_scale, hovered) or Forearm.SPAWN_SCALE
        -- The bounds' centre, not the item's origin, sits at the holster.
        local middle = preview.middle
        local offset = middle and Quaternion.rotate(rotation, Vector3(middle[1], middle[2], middle[3]) * scale) or
            Vector3(0, 0, 0)
        Unit.set_local_position(data.link_unit, 1, centre - offset)
        Unit.set_local_rotation(data.link_unit, 1, rotation)
        Unit.set_local_scale(data.link_unit, 1, Vector3(scale, scale, scale))
        local shown = preview.base_scale ~= nil and not api.debug_hide and visible
        -- Every frame: the spawner shows the unit once streaming completes.
        Unit.set_unit_visibility(data.item_unit_3p, shown, true)
        -- The world has already updated this frame: without this the
        -- miniature draws at last frame's pose and jitters behind a
        -- moving hand (worn, 15 September evening).
        World.update_unit_and_children(world, data.link_unit)
        if not shown then return nil end
        return preview, scale
    end
    -- Half a shown miniature's height: melee weapons stand along their local
    -- y (turned above), guns and items along z. Using the longest dimension
    -- put the ammo far below the gun (worn, 15 September evening).
    local function half_height(preview, slot, scale)
        local up_axis = slot == "slot_primary" and 2 or 3
        return (preview.size and preview.size[up_axis] * scale or Forearm.PREVIEW_SIZE) * 0.5
    end
    local function destroy_key(key)
        if previews[key] then destroy_preview(previews[key]); previews[key] = nil end
    end
    local function update_previews(world, unit, dt, t)
        local holsters = presentation.holsters
        local frame = holsters and (holsters.draw_frame and holsters.draw_frame(unit) or holsters.frame)
        local forearm_on = api.enabled() and presentation.mode == 1
        local body_on = Forearm.body_models_enabled(mod, presentation, frame)
        if not forearm_on and not body_on then api.destroy(); return end
        if preview_world ~= world then api.destroy(); preview_world = world end
        UIWeaponSpawner = UIWeaponSpawner or require("scripts/managers/ui/ui_weapon_spawner")
        UIUnitSpawner = UIUnitSpawner or require("scripts/managers/ui/ui_unit_spawner")
        local eye = eye_of(unit)
        local eye_array = eye and array(eye)
        local names_on = mod.get and mod:get("vr_holster_counts") == true
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local inventory = unit_data and unit_data:read_component("inventory")
        local wielded = inventory and inventory.wielded_slot
        local grip, forward, up
        if forearm_on then grip, forward, up = hand_basis() end
        if not grip then
            for index in ipairs(zones) do destroy_key(index); zones[index].grab_radius = nil end
            hovered_id = nil
        else
            local support = presentation.weapon_hand_roles.physical("support")
            -- The zone the off hand is in, from the holster state.
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
            local aiming = Forearm.hidden_for_aim(presentation.two_hand and presentation.two_hand.held,
                presentation.ads_active)
            local fallback_side = Vector3.normalize(Vector3.cross(Vector3(forward[1], forward[2], forward[3]), Vector3.up()))
            for index, zone in ipairs(zones) do
                -- This frame's hand position (the grab zones use the same).
                zone.slot, zone.selector = Forearm.assignment(index, wielded)
                zone.world = Forearm.centre(index, grip, forward, up)
                local item = zone.slot and item_in(unit, zone.slot)
                if not item or (previews[index] and previews[index].item ~= item) then zone.grab_radius = nil end
                local centre = Vector3(zone.world[1], zone.world[2], zone.world[3])
                if api.test_front and eye then
                    local _, eye_rotation = eye_of(unit)
                    centre = eye + Quaternion.forward(eye_rotation) * 0.5 + Quaternion.right(eye_rotation) * (0.12 * (index - 2.5))
                end
                local preview, scale = place_preview(world, index, zone.id, zone.slot, item, centre, hover_id == zone.id,
                    not aiming, eye_array, fallback_side, dt, t, function(fitted_preview, fitted)
                        local size = fitted_preview.size
                        zone.grab_radius = fitted and size and
                            Forearm.grab_radius({size[1] * fitted, size[2] * fitted, size[3] * fitted}) or nil
                    end)
                if preview then
                    local half = half_height(preview, zone.slot, scale)
                    -- Every item's name above it on hover, as the weapon's was
                    -- (user, 15 September evening).
                    if names_on and hover_id == zone.id then
                        local name = weapon_name(item)
                        if name then
                            label(world, "forearm_name_" .. index, centre + Vector3.up() * (half + Forearm.LABEL_GAP), name)
                        end
                    end
                    if zone.id == "forearm_weapon" then
                        local text = holstered_text(unit, zone.slot)
                        if text then
                            label(world, "forearm_ammo", centre - Vector3.up() * (half + Forearm.LABEL_GAP), text)
                        end
                    end
                end
            end
        end
        -- Body holsters: a miniature always at each visible holster, so the
        -- player knows where to reach, not for the item already in the hand;
        -- the shoulder holster, out of sight, has none (user, 15 September
        -- evening).
        local body_zones = body_on and holsters.zones or {}
        for _, zone in ipairs(body_zones) do
            local key = "body_" .. tostring(zone.id)
            if Forearm.BODY_MODELS[zone.id] then
                local s, c = frame.scale, zone.centre
                local centre = Vector3(frame.origin[1] + (frame.right[1] * c[1] + frame.forward[1] * c[2]) * s,
                    frame.origin[2] + (frame.right[2] * c[1] + frame.forward[2] * c[2]) * s, frame.origin[3] + c[3] * s)
                local item = zone.slot and wielded ~= zone.slot and item_in(unit, zone.slot) or nil
                local hovered = false
                for _, hand in ipairs({"left", "right"}) do
                    local state = holsters.hands and holsters.hands[hand]
                    if state and state.zone == zone then hovered = true end
                end
                local fallback_side = Vector3(frame.right[1], frame.right[2], 0)
                local preview, scale = place_preview(world, key, zone.id, zone.slot, item, centre, hovered,
                    true, eye_array, fallback_side, dt, t, nil)
                if preview and names_on and hovered then
                    local name = weapon_name(item)
                    if name then
                        label(world, key .. "_name", centre + Vector3.up() * (half_height(preview, zone.slot, scale) +
                            Forearm.LABEL_GAP), name)
                    end
                end
            else
                destroy_key(key)
            end
        end
        if not body_on then
            for key in pairs(previews) do
                if type(key) == "string" then destroy_key(key) end
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
