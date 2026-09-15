-- Holster counts (option "vr_holster_counts", default off; diegetic HUD
-- backlog, 15 September): while a hand rests in a holster zone, a small label
-- at the zone says what it holds: blitz charges at the belt, the stim or
-- carried item's name at the chest, the ranged weapon's ammo at the
-- shoulder, the melee weapon and device names at the hips; "empty" when the
-- slot has nothing. Needs holsters on (the zones and hand tracking live there).
local Counts = {}

Counts.FONT_SIZE = 18
Counts.PIXEL_METRES = 0.0009

-- The label for a zone, or nil. data: blitz = {charges, max}; names by slot
-- (false for an empty slot); ammo = {clip, reserve}. Pure.
function Counts.label(zone, data)
    if type(zone) ~= "table" or type(data) ~= "table" then return nil end
    if zone.id == "belt" then
        local blitz = data.blitz
        if type(blitz) ~= "table" or type(blitz[1]) ~= "number" or type(blitz[2]) ~= "number" or blitz[2] <= 0 then
            return nil
        end
        return string.format("%d/%d", blitz[1], blitz[2])
    end
    if zone.slot == "slot_secondary" and type(data.ammo) == "table" and type(data.ammo[1]) == "number" then
        return type(data.ammo[2]) == "number" and string.format("%d / %d", data.ammo[1], data.ammo[2]) or
            tostring(data.ammo[1])
    end
    local name = zone.slot and data.names and data.names[zone.slot]
    if name == false then return "empty" end
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

function Counts.install(mod, presentation)
    local api = {}
    local world, gui, failed, logged = nil, nil, false, {}
    local UIFonts
    function api.destroy()
        if gui and world then pcall(World.destroy_gui, world, gui) end
        world, gui = nil, nil
    end
    local function hide() if gui then Gui.set_visible(gui, false) end end
    -- Unattended runs: darktidevr_holster_counts_test.flag "enabled".
    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open("./../mods/darktidevr/darktidevr_holster_counts_test.flag", "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end
    local function slot_name(loadout, inventory, slot)
        local item = inventory[slot]
        if item == nil or item == "not_equipped" then return false end
        local equipment = loadout and loadout._equipment and loadout._equipment[slot]
        local display = equipment and equipment.item and equipment.item.display_name
        if type(display) == "string" and display ~= "" then
            local ok, text = pcall(Localize, display)
            if ok and type(text) == "string" and not text:find("<unlocalized", 1, true) then return text end
        end
        return nil
    end
    local function data_for(unit, zone)
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local inventory = unit_data and unit_data:read_component("inventory")
        if not inventory then return nil end
        local data = {names = {}}
        if zone.id == "belt" then
            local ability = ScriptUnit.has_extension(unit, "ability_system")
            if ability then
                data.blitz = {ability:remaining_ability_charges("grenade_ability"), ability:max_ability_charges("grenade_ability")}
            end
        elseif zone.slot == "slot_secondary" then
            local secondary = unit_data:read_component("slot_secondary")
            if secondary then
                local Ammo = require("scripts/utilities/ammo")
                data.ammo = {Ammo.current_ammo_in_clips(secondary), secondary.current_ammunition_reserve}
            end
        elseif zone.slot then
            local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
            data.names[zone.slot] = slot_name(loadout, inventory, zone.slot)
        end
        return data
    end
    local function draw(game_world, unit)
        local holsters = presentation.holsters
        if not unit or not (mod:get("vr_holster_counts") or test_flag()) or presentation.mode ~= 1 or not holsters or
                not holsters.frame or presentation.gameplay_context.ui_blocks_gameplay(Managers.ui) then
            hide(); return
        end
        local zone
        for _, hand in ipairs({"right", "left"}) do
            local state = holsters.hands and holsters.hands[hand]
            if state and state.zone then zone = state.zone; break end
        end
        local label = zone and Counts.label(zone, data_for(unit, zone))
        if not label then hide(); return end
        local frame = holsters.frame
        local s, c = frame.scale, zone.centre
        local anchor = Vector3(frame.origin[1] + (frame.right[1] * c[1] + frame.forward[1] * c[2]) * s,
            frame.origin[2] + (frame.right[2] * c[1] + frame.forward[2] * c[2]) * s, frame.origin[3] + c[3] * s)
        -- In front of the scene: 2D UI on the hand overlay's panel at the zone
        -- (darktidevr_hand_overlay); it was hidden behind the glove.
        world = game_world
        local overlay = presentation.hand_overlay
        local canvas = overlay and overlay.canvas(game_world, "holster_counts", anchor, Counts.PIXEL_METRES)
        if not canvas then hide(); return end
        canvas.text(label, Counts.FONT_SIZE, 0, 0, {235, 235, 225, 190})
        if not logged[zone.id] then
            logged[zone.id] = true
            mod:info("DARKTIDEVR_HOLSTER_COUNTS first_draw zone=%s label=%s", zone.id, label)
        end
    end
    function api.draw(game_world, unit)
        if failed then return end
        local ok, err = pcall(draw, game_world, unit)
        if not ok then
            api.destroy(); failed = true
            mod:warning("DARKTIDEVR_HOLSTER_COUNTS error=%s", tostring(err))
        end
    end
    return api
end

return Counts
