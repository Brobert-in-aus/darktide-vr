-- Weapon hand holsters (option "vr_forearm_holsters", default off; user
-- request, 15 September): small holsters along the gun hand's forearm. The
-- off hand reaches into one and presses grip to wield what it holds, through
-- the same grip request as the body holsters (darktidevr_holsters.lua). Each
-- occupied holster shows a miniature of its item while the off hand is near.
--
-- Layout, from the wrist toward the elbow, in the gun hand's grip frame
-- (forward along the controller, up on top). Starting values to tune worn:
-- the first zone ZONE_START behind the grip, ZONE_SPACING apart, ZONE_HEIGHT
-- above the forearm line, ZONE_RADIUS each.
--   1. the other weapon (ranged while the melee weapon is out, and back)
--   2. stim, 3. carried item, 4. device
local Forearm = {}

Forearm.ZONE_START = 0.10
Forearm.ZONE_SPACING = 0.065
Forearm.ZONE_HEIGHT = 0.035
Forearm.ZONE_RADIUS = 0.04
Forearm.PREVIEW_SIZE = 0.05
Forearm.PREVIEW_NEAR = 0.30
Forearm.TEST_FLAG = "./../mods/darktidevr/darktidevr_forearm_holsters_test.flag"

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

-- A zone centre in world space from the gun hand's grip position and axes
-- (3-arrays). Pure.
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
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end
    function api.enabled()
        return (mod.get and mod:get("vr_forearm_holsters") == true) or test_flag()
    end
    local function array(v) return v and {Vector3.x(v), Vector3.y(v), Vector3.z(v)} or nil end

    -- Zones in the holster body frame (x right, y forward, z up, divided by
    -- the frame scale) for the off hand this frame, or nil.
    function api.local_zones(unit, frame, Holsters, inventory)
        local position, rotation = presentation.weapon_grip_target("dominant")
        if not position or not rotation or not frame then return nil end
        local grip, forward, up = array(position), array(Quaternion.forward(rotation)), array(Quaternion.up(rotation))
        for index, zone in ipairs(zones) do
            local world = Forearm.centre(index, grip, forward, up)
            zone.world = world
            zone.slot, zone.selector = Forearm.assignment(index, inventory and inventory.wielded_slot)
            local point = Holsters.local_point(frame, world)
            zone.centre = point
            zone.radius = Forearm.ZONE_RADIUS / frame.scale
            local_zones[index] = zone
        end
        api.grip, api.forward, api.up = grip, forward, up
        return local_zones
    end

    -- Miniature previews: one UIWeaponSpawner per zone, respawned when the
    -- zone's item changes, posed each frame, hidden while the off hand is far.
    local UIWeaponSpawner, UIUnitSpawner
    local previews, preview_world, failed = {}, nil, false
    local function destroy_preview(preview)
        if preview.spawner then pcall(preview.spawner.destroy, preview.spawner) end
        if preview.unit_spawner then pcall(preview.unit_spawner.destroy, preview.unit_spawner) end
    end
    function api.destroy()
        for index, preview in pairs(previews) do destroy_preview(preview); previews[index] = nil end
        preview_world = nil
    end
    local function item_in(unit, slot)
        local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
        local equipment = loadout and loadout._equipment and loadout._equipment[slot]
        return equipment and equipment.item or nil
    end
    local function update_previews(world, unit, dt, t)
        if not api.enabled() or not api.grip or presentation.mode ~= 1 then api.destroy(); return end
        if preview_world ~= world then api.destroy(); preview_world = world end
        UIWeaponSpawner = UIWeaponSpawner or require("scripts/managers/ui/ui_weapon_spawner")
        UIUnitSpawner = UIUnitSpawner or require("scripts/managers/ui/ui_unit_spawner")
        local support = presentation.weapon_hand_roles.physical("support")
        local hand = support == "left" and presentation.left_controller_grip_target() or presentation.controller_grip_target()
        local middle = Forearm.centre(2.5, api.grip, api.forward, api.up)
        local near = hand and Vector3.distance(hand, Vector3(middle[1], middle[2], middle[3])) <= Forearm.PREVIEW_NEAR
        local rotation = Quaternion.look(Vector3(api.forward[1], api.forward[2], api.forward[3]),
            Vector3(api.up[1], api.up[2], api.up[3]))
        for index, zone in ipairs(zones) do
            local item = zone.slot and item_in(unit, zone.slot)
            local preview = previews[index]
            if preview and preview.item ~= item then destroy_preview(preview); previews[index] = nil; preview = nil end
            if item and not preview then
                local unit_spawner = UIUnitSpawner:new(world)
                local spawner = UIWeaponSpawner:new("DarktideVRForearm_" .. index, world, nil, unit_spawner)
                local position = Vector3(zone.world[1], zone.world[2], zone.world[3])
                spawner:start_presentation(item, position, rotation, Vector3(0.2, 0.2, 0.2), nil, false)
                preview = {item = item, spawner = spawner, unit_spawner = unit_spawner, started_t = t}
                previews[index] = preview
                mod:info("DARKTIDEVR_FOREARM_HOLSTERS preview_start zone=%s item=%s", zone.id, tostring(item.name))
            end
            if preview then
                preview.spawner:update(dt, t, nil)
                local data = preview.spawner:get_spawn_data()
                if data and not preview.spawn_logged then
                    preview.spawn_logged = true
                    mod:info("DARKTIDEVR_FOREARM_HOLSTERS preview_spawned zone=%s after_s=%.2f item_unit=%s link=%s",
                        zone.id, t - (preview.started_t or t), tostring(data.item_unit_3p), tostring(data.link_unit))
                elseif not data and not preview.wait_logged and t - (preview.started_t or t) > 5 then
                    preview.wait_logged = true
                    mod:info("DARKTIDEVR_FOREARM_HOLSTERS preview_waiting zone=%s seconds=5", zone.id)
                end
                if data and data.link_unit and Unit.alive(data.link_unit) then
                    -- Fit the item's largest extent to PREVIEW_SIZE once it exists.
                    if not preview.fitted and data.item_unit_3p and Unit.alive(data.item_unit_3p) then
                        local ok, _, extents = pcall(Unit.box, data.item_unit_3p)
                        local largest = ok and extents and math.max(Vector3.x(extents), Vector3.y(extents), Vector3.z(extents)) or 0
                        if largest <= 1e-4 and not preview.box_logged then
                            preview.box_logged = true
                            mod:info("DARKTIDEVR_FOREARM_HOLSTERS preview_box zone=%s ok=%s extents=%s", zone.id,
                                tostring(ok), tostring(ok and extents or _))
                        end
                        if largest > 1e-4 then
                            local current = Vector3.x(Unit.local_scale(data.link_unit, 1))
                            local fitted = current * (Forearm.PREVIEW_SIZE * 0.5) / largest
                            Unit.set_local_scale(data.link_unit, 1, Vector3(fitted, fitted, fitted))
                            preview.fitted = true
                            mod:info("DARKTIDEVR_FOREARM_HOLSTERS preview zone=%s item=%s scale=%.3f",
                                zone.id, tostring(item.name), fitted)
                        end
                    end
                    Unit.set_local_position(data.link_unit, 1, Vector3(zone.world[1], zone.world[2], zone.world[3]))
                    Unit.set_local_rotation(data.link_unit, 1, rotation)
                    -- Every frame: the spawner shows the unit once streaming completes.
                    if data.item_unit_3p and Unit.alive(data.item_unit_3p) then
                        preview.visible = near and preview.fitted == true
                        Unit.set_unit_visibility(data.item_unit_3p, preview.visible, true)
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
