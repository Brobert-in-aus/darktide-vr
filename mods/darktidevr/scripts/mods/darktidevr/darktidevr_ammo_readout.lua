-- Diegetic ammo count: a small world-space readout beside the dominant hand
-- while a ranged weapon is wielded (clip and reserve, or heat), instead of on
-- the HUD panel. Option "vr_ammo_readout", default off. Reads the same slot
-- component fields as the stock HudElementPlayerWeapon; draws after the hand
-- pose in the same world GUI style as the crosshair feedback.
local Readout = {}

Readout.OFFSET_UP = 0.09        -- metres above the grip
Readout.OFFSET_INWARD = 0.05    -- towards the body's midline
Readout.PIXEL_METRES = 0.0011   -- world size of one font pixel
Readout.FONT_SIZE = 30
Readout.TEST_FLAG = "./../mods/darktidevr/darktidevr_ammo_readout_test.flag"

-- Ammo and heat of a slot component. nil when the slot shows neither.
function Readout.values(slot, Ammo, clip_count)
    if type(slot) ~= "table" then return nil end
    local result = {}
    local max_reserve = slot.max_ammunition_reserve
    if Ammo and type(max_reserve) == "number" and max_reserve > 0 then
        local in_use = {}
        if Ammo.clips_in_use(slot, in_use) then
            local clip, clip_max = 0, 0
            for i = 1, clip_count or 1 do
                if in_use[i] then
                    clip = clip + (Ammo.current_ammo_in_clips(slot, i) or 0)
                    clip_max = clip_max + (Ammo.max_ammo_in_clips(slot, i) or 0)
                end
            end
            result.clip, result.clip_max = clip, clip_max
            result.reserve, result.reserve_max = slot.current_ammunition_reserve or 0, max_reserve
        end
    end
    local heat = slot.overheat_current_percentage
    if type(heat) == "number" and heat > 0 then result.heat = math.min(heat, 1) end
    if not result.clip and not result.heat then return nil end
    return result
end

-- Display text and colour: white, amber from 20 % left (stock's low-ammo
-- threshold) or 75 % heat, red when the clip is empty or heat is past 90 %.
function Readout.text(values)
    if not values then return nil end
    local parts = {}
    if values.clip then parts[#parts + 1] = string.format("%d | %d", values.clip, values.reserve) end
    if values.heat then parts[#parts + 1] = string.format("%d%%", math.floor(values.heat * 100 + 0.5)) end
    local level = "normal"
    local total_max = (values.clip_max or 0) + (values.reserve_max or 0)
    if values.clip and total_max > 0 and (values.clip + values.reserve) / total_max <= 0.2 then level = "low" end
    if values.heat and values.heat >= 0.75 then level = "low" end
    if (values.clip and values.clip == 0) or (values.heat and values.heat >= 0.9) then level = "critical" end
    return table.concat(parts, "  "), level
end

Readout.COLORS = {normal = {230, 235, 245, 240}, low = {235, 255, 190, 60}, critical = {235, 255, 70, 50}}

function Readout.install(mod, presentation, observation)
    local api = {}
    local world, gui, failed, logged
    local UIFonts, Ammo, NetworkConstants
    local test_poll, test_mode = 0, nil
    function api.destroy()
        if gui and world then pcall(World.destroy_gui, world, gui) end
        world, gui = nil, nil
    end
    local showing_t
    local function hide() showing_t = nil; if gui then Gui.set_visible(gui, false) end end
    -- The panel's ranged weapon element stays hidden while its count shows at
    -- the hand (one frame of grace for draw order).
    if mod.hook then
        mod:hook("HudElementPlayerWeapon", "draw", function(func, self, ...)
            local now = Managers and Managers.time and Managers.time:time("main")
            if showing_t and now and now - showing_t < 0.1 and self._slot_name == "slot_secondary" then
                return
            end
            return func(self, ...)
        end)
    end
    local function read_test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_mode end
        test_poll = 60
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Readout.TEST_FLAG, "r")
        if not file then test_mode = nil; return nil end
        local value = file:read("*all"); file:close()
        test_mode = type(value) == "string" and value:match("^%s*front%s*$") and "front" or nil
        return test_mode
    end
    local function slot_values(unit)
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local inventory = unit_data and unit_data:read_component("inventory")
        if not inventory or inventory.wielded_slot ~= "slot_secondary" then return nil end
        Ammo = Ammo or require("scripts/utilities/ammo")
        NetworkConstants = NetworkConstants or require("scripts/network_lookup/network_constants")
        local count = NetworkConstants.clips_in_use and NetworkConstants.clips_in_use.max_size or 1
        return Readout.values(unit_data:read_component("slot_secondary"), Ammo, count)
    end
    local function draw(game_world, unit)
        local test = read_test_flag()
        if not unit or (not test and not mod:get("vr_ammo_readout")) or presentation.mode ~= 1 or
                presentation.gameplay_context.ui_blocks_gameplay(Managers.ui) then
            hide(); return
        end
        local values = slot_values(unit)
        if not values and test then values = {clip = 12, clip_max = 40, reserve = 180, reserve_max = 400} end
        local text, level = Readout.text(values)
        if not text then hide(); return end
        local first_person = ScriptUnit.has_extension(unit, "first_person_system")
        local eye_unit = first_person and first_person:first_person_unit()
        if not eye_unit then hide(); return end
        local eye = Unit.world_position(eye_unit, 1)
        local eye_rotation = Unit.world_rotation(eye_unit, 1)
        local anchor
        if test then
            anchor = eye + Quaternion.forward(eye_rotation) * 0.5
        else
            local side = presentation.weapon_hand_roles.physical("dominant")
            local grip = presentation.weapon_grip_target("dominant")
            if not grip then hide(); return end
            local flat_right = Quaternion.right(eye_rotation)
            local inward = side == "left" and flat_right or -flat_right
            anchor = grip + Vector3.up() * Readout.OFFSET_UP + inward * Readout.OFFSET_INWARD
        end
        -- Face the eye, text upright: local x to the viewer's right, y up.
        local to_eye = Vector3.normalize(eye - anchor)
        local right = Vector3.normalize(Vector3.cross(Vector3.up(), to_eye))
        if Vector3.length(right) < 0.5 then right = Quaternion.right(eye_rotation) end
        local up = Vector3.cross(to_eye, right)
        if world ~= game_world then api.destroy(); world = game_world end
        if not gui then gui = World.create_world_gui(world, Matrix4x4.identity(), 1, 1, "immediate") end
        Gui.set_visible(gui, true)
        UIFonts = UIFonts or require("scripts/managers/ui/ui_fonts")
        local font = UIFonts.data_by_type("proxima_nova_bold")
        local ps = Readout.PIXEL_METRES
        local size = Readout.FONT_SIZE * ps
        local tm = Matrix4x4.identity()
        Matrix4x4.set_right(tm, right)
        Matrix4x4.set_up(tm, up)
        Matrix4x4.set_forward(tm, -to_eye)
        Matrix4x4.set_translation(tm, anchor)
        local width = #text * size * 0.5
        local c = Readout.COLORS[level] or Readout.COLORS.normal
        Gui.slug_text_3d(gui, text, font.path, size, tm, Vector3(-width * 0.5, -size * 0.5, 0), 10,
            Color(c[1], c[2], c[3], c[4]), "flags", font.render_flags or 0)
        showing_t = not test and Managers.time:time("main") or nil
        if not logged then
            logged = true
            mod:info("DARKTIDEVR_AMMO_READOUT first_draw text=%s level=%s test=%s", text, level, tostring(test))
        end
    end
    function api.draw(game_world, unit)
        if failed then return end
        local ok, err = pcall(draw, game_world, unit)
        if not ok then
            api.destroy(); failed = true
            mod:warning("DARKTIDEVR_AMMO_READOUT error=%s", tostring(err))
        end
    end
    return api
end

return Readout
