-- Wrist display (option "vr_wrist_display", default off; diegetic HUD
-- backlog, 15 September): turning the off hand's wrist toward the face, as
-- when checking a watch, shows health (with its number), toughness and
-- stamina bars at the wrist. The panel HUD is unchanged.
--
-- Assumption (to confirm worn): with a controller in hand, the back of the
-- hand faces outward, the left hand's toward its grip frame's -right and the
-- right hand's toward +right. The display sits on that side of the wrist.
local Wrist = {}

Wrist.SHOW_FACING = 0.75
Wrist.HIDE_FACING = 0.6
Wrist.MAX_DISTANCE = 0.7
Wrist.WRIST_BACK = 0.10
Wrist.OUT = 0.05
Wrist.BAR_WIDTH = 0.08
Wrist.BAR_HEIGHT = 0.008
Wrist.BAR_GAP = 0.014
Wrist.TEST_FLAG = "./../mods/darktidevr/darktidevr_wrist_display_test.flag"

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function clamp01(x) return finite(x) and math.max(0, math.min(1, x)) or nil end

-- Whether the display shows: the wrist's outward normal (unit) points at the
-- eye, within reach, with hysteresis. to_eye: unit vector wrist -> eye. Pure.
function Wrist.visible(was_visible, normal, to_eye, distance)
    if type(normal) ~= "table" or type(to_eye) ~= "table" or not finite(distance) then return false end
    if distance > Wrist.MAX_DISTANCE then return false end
    local facing = normal[1] * to_eye[1] + normal[2] * to_eye[2] + normal[3] * to_eye[3]
    if not finite(facing) then return false end
    return facing >= (was_visible and Wrist.HIDE_FACING or Wrist.SHOW_FACING)
end

-- Bars from the sampled values, top to bottom. Pure.
function Wrist.bars(values)
    if type(values) ~= "table" then return {} end
    local bars = {}
    local health = finite(values.health) and finite(values.max_health) and values.max_health > 0 and
        values.health / values.max_health or nil
    if health then
        bars[#bars + 1] = {id = "health", fraction = clamp01(health), color = {230, 90, 80},
            text = string.format("%d", math.floor(values.health + 0.5))}
    end
    if clamp01(values.toughness) then
        bars[#bars + 1] = {id = "toughness", fraction = clamp01(values.toughness), color = {120, 200, 230}}
    end
    if clamp01(values.stamina) then
        bars[#bars + 1] = {id = "stamina", fraction = clamp01(values.stamina), color = {230, 220, 160}}
    end
    return bars
end

function Wrist.install(mod, presentation, observation)
    local api = {visible = false}
    local world, gui, failed, logged = nil, nil, false, false
    local UIFonts
    function api.destroy()
        if gui and world then pcall(World.destroy_gui, world, gui) end
        world, gui = nil, nil
    end
    local function hide() api.visible = false; if gui then Gui.set_visible(gui, false) end end
    local test_poll, test_mode = 0, nil
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_mode end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Wrist.TEST_FLAG, "r")
        if not file then test_mode = nil; return nil end
        local value = file:read("*all"); file:close()
        test_mode = type(value) == "string" and value:match("^%s*(%a+)%s*$") or nil
        if test_mode ~= "enabled" and test_mode ~= "front" then test_mode = nil end
        return test_mode
    end
    local function read_values(unit)
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local health = ScriptUnit.has_extension(unit, "health_system")
        local toughness = ScriptUnit.has_extension(unit, "toughness_system")
        local function field(read) local ok, value = pcall(read); return ok and value or nil end
        return {
            health = health and field(function() return health:current_health() end),
            max_health = health and field(function() return health:max_health() end),
            toughness = toughness and field(function() return toughness:current_toughness_percent() end),
            stamina = unit_data and field(function() return unit_data:read_component("stamina").current_fraction end),
        }
    end
    local function array(v) return {Vector3.x(v), Vector3.y(v), Vector3.z(v)} end
    local function draw(game_world, unit)
        local test = test_flag()
        if not unit or not (test or mod:get("vr_wrist_display")) or presentation.mode ~= 1 or
                presentation.gameplay_context.ui_blocks_gameplay(Managers.ui) then
            hide(); return
        end
        local first_person = ScriptUnit.has_extension(unit, "first_person_system")
        local eye_unit = first_person and first_person:first_person_unit()
        if not eye_unit then hide(); return end
        local eye = Unit.world_position(eye_unit, 1)
        local eye_rotation = Unit.world_rotation(eye_unit, 1)
        local anchor
        if test == "front" then
            anchor = eye + Quaternion.forward(eye_rotation) * 0.45 - Quaternion.up(eye_rotation) * 0.05
            api.visible = true
        else
            local side = presentation.weapon_hand_roles.physical("support")
            if side ~= "left" and side ~= "right" then hide(); return end
            local live = observation[side .. "_grip_tracking_live"] == true
            local position, rotation
            if side == "left" then position, rotation = presentation.left_controller_grip_target()
            else position, rotation = presentation.controller_grip_target() end
            if not live or not position or not rotation then hide(); return end
            local normal = Quaternion.right(rotation) * (side == "left" and -1 or 1)
            anchor = position - Quaternion.forward(rotation) * Wrist.WRIST_BACK + normal * Wrist.OUT
            local offset = eye - anchor
            local distance = Vector3.length(offset)
            local to_eye = distance > 1e-4 and offset / distance or Vector3(0, 0, 1)
            api.visible = Wrist.visible(api.visible, array(normal), array(to_eye), distance)
            if not api.visible then hide(); return end
        end
        local bars = Wrist.bars(read_values(unit))
        if #bars == 0 then hide(); return end
        local to_eye = Vector3.normalize(eye - anchor)
        local right = Vector3.normalize(Vector3.cross(Vector3.up(), to_eye))
        if Vector3.length(right) < 0.5 then right = Quaternion.right(eye_rotation) end
        local up = Vector3.cross(to_eye, right)
        if world ~= game_world then api.destroy(); world = game_world end
        if not gui then gui = World.create_world_gui(world, Matrix4x4.identity(), 1, 1, "immediate") end
        Gui.set_visible(gui, true)
        local function plate(offset_up)
            local tm = Matrix4x4.identity()
            Matrix4x4.set_right(tm, right)
            Matrix4x4.set_up(tm, up)
            Matrix4x4.set_forward(tm, -to_eye)
            Matrix4x4.set_translation(tm, anchor + up * offset_up)
            return tm
        end
        UIFonts = UIFonts or require("scripts/managers/ui/ui_fonts")
        local font = UIFonts.data_by_type("proxima_nova_bold")
        local top = (#bars - 1) * Wrist.BAR_GAP * 0.5
        for i, bar in ipairs(bars) do
            local y = top - (i - 1) * Wrist.BAR_GAP
            local tm = plate(y)
            local c = bar.color
            Gui.rect_3d(gui, tm, Vector2(-Wrist.BAR_WIDTH * 0.5, -Wrist.BAR_HEIGHT * 0.5), 8,
                Vector2(Wrist.BAR_WIDTH, Wrist.BAR_HEIGHT), Color(110, 20, 20, 20))
            Gui.rect_3d(gui, tm, Vector2(-Wrist.BAR_WIDTH * 0.5, -Wrist.BAR_HEIGHT * 0.5), 9,
                Vector2(Wrist.BAR_WIDTH * bar.fraction, Wrist.BAR_HEIGHT), Color(230, c[1], c[2], c[3]))
            if bar.text then
                local size = 0.011
                Gui.slug_text_3d(gui, bar.text, font.path, size, tm,
                    Vector3(Wrist.BAR_WIDTH * 0.5 + 0.004, -size * 0.35, 0), 10, Color(235, c[1], c[2], c[3]),
                    "flags", font.render_flags or 0)
            end
        end
        if not logged then
            logged = true
            mod:info("DARKTIDEVR_WRIST_DISPLAY first_draw bars=%d test=%s", #bars, tostring(test))
        end
    end
    function api.draw(game_world, unit)
        if failed then return end
        local ok, err = pcall(draw, game_world, unit)
        if not ok then
            api.destroy(); failed = true
            mod:warning("DARKTIDEVR_WRIST_DISPLAY error=%s", tostring(err))
        end
    end
    return api
end

return Wrist
