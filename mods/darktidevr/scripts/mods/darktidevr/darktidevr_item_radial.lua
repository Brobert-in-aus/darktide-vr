-- Item radial (todo-2026-09-14: "Holding the carried-items button shows a
-- radial at the hand; flick the stick to pick scanner, stim or carried item").
-- Pure: no engine calls.
--
-- Stock, the carried-items control cycles through what you have, so reaching a
-- particular item means pressing it until the right one comes up. Held, this
-- shows the three as sectors at the off hand and the stick picks one directly;
-- released, it wields what was picked. Tapping it without moving the stick
-- falls through to the stock cycle, so the control keeps its old behaviour for
-- anyone who does not want the radial.
--
-- It overlaps the virtual holsters, which put the same three items on the
-- body. It is not redundant while those are withheld from release, and the two
-- can be run together: the holsters are reached for, this is chosen.
local Radial = {}

-- The stock wield inputs behind each sector, in the bindings' catalogue.
Radial.OPTIONS = {
    {id = "pocketable", mask = 65536, label = "Item"},
    {id = "stim", mask = 131072, label = "Stim"},
    {id = "device", mask = 262144, label = "Device"},
}
-- The stick has to leave the centre by this much to pick anything, so a held
-- button with a resting thumb still falls through to the stock cycle.
Radial.DEADZONE = 0.5
-- Sectors are placed from straight up, clockwise.

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end

-- Which sector a stick position picks, or nil inside the deadzone. `count`
-- defaults to the number of options. Pure.
function Radial.select(x, y, count)
    count = count or #Radial.OPTIONS
    if not finite(x) or not finite(y) or count < 1 then return nil end
    if math.sqrt(x * x + y * y) < Radial.DEADZONE then return nil end
    -- Straight up is the middle of the first sector; clockwise from there.
    local angle = math.atan2(x, y)
    if angle < 0 then angle = angle + math.pi * 2 end
    local step = math.pi * 2 / count
    return math.floor(angle / step + 0.5) % count + 1
end

-- Where a sector's label sits, in metres from the radial's centre, for a
-- radius and a count. Straight up is the first. Pure.
function Radial.label_offset(index, count, radius)
    count = count or #Radial.OPTIONS
    if type(index) ~= "number" or index < 1 or index > count then return nil end
    local angle = (index - 1) * math.pi * 2 / count
    return math.sin(angle) * radius, math.cos(angle) * radius
end

-- The state after a frame: {open, index, deliver}. `held` is the carried-items
-- control, `index` the current selection. `deliver` is set on the frame the
-- control is released with something picked, and is the mask to hold for one
-- frame; releasing with nothing picked delivers nothing, so the stock cycle
-- runs instead. Pure.
function Radial.step(state, held, index)
    state = type(state) == "table" and state or {}
    if held then
        return {open = true, index = index or state.index}, nil
    end
    if state.open and state.index then
        local option = Radial.OPTIONS[state.index]
        return {open = false}, option and option.mask or nil
    end
    return {open = false}, nil
end

-- Engine side. The pure part above is what the tests exercise.
Radial.TEST_FLAG = "./../mods/darktidevr/darktidevr_item_radial_test.flag"
-- The ring's radius at the hand, and the label size. Small enough to sit in
-- front of the off hand without covering the view.
Radial.RADIUS = 0.055
Radial.LABEL_PX = 26
Radial.PIXEL_METRES = 0.00055
Radial.FORWARD = 0.06

function Radial.install(mod, presentation, observation)
    local api = {}
    local state, failures, opened = {}, 0, 0

    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Radial.TEST_FLAG, "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end

    function api.enabled()
        return mod:get("vr_item_radial") == true or test_flag()
    end

    -- Sampled before the bindings, so the stick claim is known in time: this
    -- asks the raw physical bits which control carries the carried-items
    -- action, the way the communication wheel does.
    local function sample(active, physical, mode)
        if not active or not api.enabled() then return false end
        local bindings = presentation.controller_bindings
        if not bindings or not bindings.physical_hold then return false end
        local held = bindings.physical_hold("pocketable_device", physical, mode) == true
        local index
        if held and observation.right_aim_usable then
            index = Radial.select(observation.right_stick_x, observation.right_stick_y)
        end
        local deliver
        state, deliver = Radial.step(state, held, index)
        if state.open and opened < 10 and not api.was_open then
            opened = opened + 1
            mod:info("DARKTIDEVR_ITEM_RADIAL open entries=%d", opened)
        end
        api.was_open = state.open
        if deliver then
            bindings.forced = bit.bor(tonumber(bindings.forced) or 0, deliver)
            mod:info("DARKTIDEVR_ITEM_RADIAL wield mask=%d", deliver)
        end
        -- The stick belongs to the radial while it is open, so it neither
        -- turns the player nor fires a stick binding.
        return state.open == true
    end

    function api.sample(active, physical, mode)
        local ok, claim = pcall(sample, active, physical, mode)
        if ok then return claim == true end
        failures = failures + 1
        state = {}
        if failures <= 3 then
            mod:warning("DARKTIDEVR_ITEM_RADIAL error=%s failures=%d", tostring(claim):sub(1, 160), failures)
        end
        return false
    end

    -- Drawn at the off hand, in the draw pass.
    local function draw(world, unit)
        if not state.open or not api.enabled() then return end
        local grip, grip_rotation = presentation.weapon_grip_target("support")
        if not grip or not grip_rotation then return end
        local centre = grip + Quaternion.forward(grip_rotation) * Radial.FORWARD
        local overlay = presentation.hand_overlay
        local canvas = overlay and overlay.canvas(world, "item_radial", centre, Radial.PIXEL_METRES)
        if not canvas then return end
        for index, option in ipairs(Radial.OPTIONS) do
            local x, y = Radial.label_offset(index, #Radial.OPTIONS, Radial.RADIUS)
            local chosen = state.index == index
            canvas.text(option.label, Radial.LABEL_PX, x, y,
                chosen and {255, 255, 245, 210} or {170, 210, 210, 200})
        end
    end

    function api.draw(world, unit)
        local ok, err = pcall(draw, world, unit)
        if not ok then
            failures = failures + 1
            if failures <= 3 then
                mod:warning("DARKTIDEVR_ITEM_RADIAL draw_error=%s", tostring(err):sub(1, 160))
            end
        end
    end

    function api.destroy() state = {} end
    return api
end

return Radial
