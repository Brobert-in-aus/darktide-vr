-- Wrist display (option "vr_wrist_display", default off; diegetic HUD
-- backlog, 15 September): health (white, with its number), toughness (the
-- HUD's toughness blue) and stamina bars at the off hand's wrist, always
-- shown while the hand is tracked (user, 15 September evening; it first
-- showed only with the wrist turned toward the face). The panel HUD is
-- unchanged.
--
-- The panel sits above the wrist in world up, so it stays put as the wrist
-- rolls (like the ammo counter). Moving it toward the eye made it large and
-- close (worn, 15 September evening); staying visible is a rendering matter.
local Wrist = {}

-- Inside the glove's cuff, just past the wrist: it draws in front of
-- everything, so it no longer needs to clear the hand (user, 15 September
-- evening; it sat 7 cm above the wrist). The wrist is about 8 cm behind the
-- controller grip, back along the controller's aim (the forearm): back along
-- the grip pose's own forward, which tilts with the handle, it sat well below
-- the wrist (worn screenshot 19:50).
Wrist.WRIST_BACK = 0.12
Wrist.OUT = 0.0
-- ui_toughness_default in the game's colour table (the HUD toughness bar).
Wrist.HEALTH_COLOR = {255, 255, 255}
Wrist.TOUGHNESS_COLOR = {108, 187, 196}
Wrist.STAMINA_COLOR = {230, 220, 160}
-- At 100 % size. 1.5 times the first size, then 25 % smaller (worn, 15
-- September evening: "a little bigger", then "too big").
Wrist.BAR_WIDTH = 0.09
Wrist.BAR_HEIGHT = 0.009
Wrist.BAR_GAP = 0.01575
Wrist.TEXT_SIZE = 0.012375
Wrist.TEXT_GAP = 0.003
-- Overlay panel scale: metres per panel pixel, scaled with the size so the
-- bars and numbers keep their pixel layout inside one overlay cell (at a
-- finer scale the numbers fell outside it and showed as a dash).
Wrist.PIXEL_METRES = 0.0002625
-- The bars sit left of the anchor so the numbers to their right stay inside.
Wrist.BARS_LEFT = 0.01875
-- Half the layout's width at size 1: the bars' left end is BARS_LEFT +
-- BAR_WIDTH / 2 = 0.06375 m left of the anchor (the numbers end nearer on
-- the right). The panel scale is coarsened until that fits the overlay
-- cell: at a 2112-wide eye target the cell is 528 px and 0.0002625 fits
-- (243 px of 264); at Virtual Desktop's 90 per cent FOV tangent the target
-- is 1908 wide, the cell 477 px, and the bars' left ends spilled 4 px into
-- the ammo count's cell (worn, 16 and 17 September).
Wrist.LAYOUT_HALF_WIDTH = 0.066

-- Metres per panel pixel at size 1 for an overlay cell this many pixels
-- wide. Pure.
function Wrist.pixel_metres(cell_width)
    cell_width = tonumber(cell_width)
    if not cell_width or not (cell_width > 8) then return Wrist.PIXEL_METRES end
    return math.max(Wrist.PIXEL_METRES, Wrist.LAYOUT_HALF_WIDTH / (cell_width * 0.5 - 2))
end

-- The size factor from the "vr_wrist_display_scale" percentage (50-200,
-- default 100). Pure.
function Wrist.size(percent)
    percent = tonumber(percent)
    if not percent or percent ~= percent then return 1 end
    return math.max(50, math.min(200, percent)) / 100
end
Wrist.TEST_FLAG = "./../mods/darktidevr/darktidevr_wrist_display_test.flag"

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function clamp01(x) return finite(x) and math.max(0, math.min(1, x)) or nil end

-- Bars from the sampled values, top to bottom. Pure.
function Wrist.bars(values)
    if type(values) ~= "table" then return {} end
    local bars = {}
    local health = finite(values.health) and finite(values.max_health) and values.max_health > 0 and
        values.health / values.max_health or nil
    if health then
        bars[#bars + 1] = {id = "health", fraction = clamp01(health), color = Wrist.HEALTH_COLOR,
            text = string.format("%d", math.floor(values.health + 0.5))}
    end
    if clamp01(values.toughness) then
        bars[#bars + 1] = {id = "toughness", fraction = clamp01(values.toughness), color = Wrist.TOUGHNESS_COLOR,
            text = finite(values.toughness_value) and string.format("%d", math.floor(values.toughness_value + 0.5)) or nil}
    end
    if clamp01(values.stamina) then
        bars[#bars + 1] = {id = "stamina", fraction = clamp01(values.stamina), color = Wrist.STAMINA_COLOR}
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
        -- Every 300 calls (about five seconds at the input rate): a failed open
        -- on the main thread each poll is where these modules' spikes came
        -- from (docs/LUA-FRAME-PROFILE-2026-09-16.md).
        test_poll = 300
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
            toughness_value = toughness and field(function() return toughness:remaining_toughness() end),
            stamina = unit_data and field(function() return unit_data:read_component("stamina").current_fraction end),
        }
    end
    local function array(v) return {Vector3.x(v), Vector3.y(v), Vector3.z(v)} end
    local function draw(game_world, unit)
        local test = test_flag()
        -- Not in the hub (worn, 15 September evening: shown there once it
        -- stopped needing the wrist turned toward the face).
        local in_hub = presentation.current_game_mode_name and presentation.current_game_mode_name() == "hub"
        if not unit or not (test or mod:get("vr_wrist_display")) or presentation.mode ~= 1 or in_hub or
                presentation.gameplay_context.ui_blocks_gameplay(Managers.ui) then
            hide(); return
        end
        local eye, eye_rotation
        if presentation.eye_pose then eye, eye_rotation = presentation.eye_pose(unit) end
        if not eye or not eye_rotation then hide(); return end
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
            local _, aim
            if side == "left" and presentation.left_controller_aim_target then
                _, aim = presentation.left_controller_aim_target()
            elseif side == "right" and presentation.controller_aim_target then
                _, aim = presentation.controller_aim_target()
            end
            rotation = aim or rotation
            anchor = position - Quaternion.forward(rotation) * Wrist.WRIST_BACK + Vector3.up() * Wrist.OUT
            api.visible = true
        end
        local bars = Wrist.bars(read_values(unit))
        if #bars == 0 then hide(); return end
        -- In front of the scene: 2D UI on the hand overlay's panel at the
        -- anchor (darktidevr_hand_overlay), in metres, x to the viewer's right.
        world = game_world
        local overlay = presentation.hand_overlay
        local k = Wrist.size(mod:get("vr_wrist_display_scale"))
        local pixel_metres = Wrist.pixel_metres(overlay and overlay.cell_width and overlay.cell_width())
        local canvas = overlay and overlay.canvas(game_world, "wrist_display", anchor, pixel_metres * k)
        if not canvas then hide(); return end
        local width, height, gap = Wrist.BAR_WIDTH * k, Wrist.BAR_HEIGHT * k, Wrist.BAR_GAP * k
        local top = (#bars - 1) * gap * 0.5
        for i, bar in ipairs(bars) do
            local y = top - (i - 1) * gap
            local c = bar.color
            local x = -Wrist.BARS_LEFT * k
            canvas.rect(x, y, width, height, {110, 20, 20, 20})
            local filled = width * bar.fraction
            if filled > 0 then
                canvas.rect(x - width * 0.5 + filled * 0.5, y, filled, height, {230, c[1], c[2], c[3]})
            end
            if bar.text then
                canvas.text(bar.text, Wrist.TEXT_SIZE / pixel_metres, x + width * 0.5 + Wrist.TEXT_GAP * k, y,
                    {235, c[1], c[2], c[3]}, "left")
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
