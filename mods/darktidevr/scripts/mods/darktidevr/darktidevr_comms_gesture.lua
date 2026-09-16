-- Push to talk by putting your off hand in front of your mouth
-- (todo-2026-09-14, "Hand gestures for comms"; user, 16 September: at the
-- mouth rather than at the ear, which sits at the edge of the headset's
-- tracking volume, and the off hand rather than the left, so it follows the
-- handedness setting). Pure: no engine calls.
--
-- Push to talk is a held action with no default VR control, so the gesture
-- holds it through the bindings' forced-action channel, the same one the
-- weapon inspect gesture uses. The stock chat manager sees an ordinary held
-- action and opens the microphone for as long as the hand stays there.
--
-- The hand is judged in head-local metres (x right, y forward, z up, relative
-- to the eye), so it follows the head rather than the world: speaking into
-- your hand works whichever way you are facing or leaning.
local Comms = {}

-- The mouth, a little forward of and below the eye, with room for the hand
-- held out in front of it. The grip pose is the palm, so a hand cupped at the
-- mouth reads a few centimetres further out than the lips.
Comms.MOUTH = {0, 0.16, -0.12}
Comms.ENTER_RADIUS = 0.20
Comms.EXIT_RADIUS = 0.28
-- Held this long before the microphone opens. Longer than the other gestures:
-- opening a microphone by accident is worse than missing a word.
Comms.DWELL_SECONDS = 0.5

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function point(v) return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3]) end

-- Whether a hand, in head-local metres, is in front of the mouth. `engaged`
-- widens the radius so a hand held there does not flicker. Pure.
function Comms.at_mouth(local_hand, engaged)
    if not point(local_hand) then return false end
    local radius = engaged and Comms.EXIT_RADIUS or Comms.ENTER_RADIUS
    local x = local_hand[1] - Comms.MOUTH[1]
    local y = local_hand[2] - Comms.MOUTH[2]
    local z = local_hand[3] - Comms.MOUTH[3]
    return math.sqrt(x * x + y * y + z * z) <= radius
end

-- The engaged state after a sample, carried between calls as
-- {engaged = bool, since = number}: a hand held at the mouth for
-- DWELL_SECONDS opens the microphone, and dropping it closes it at once. Pure.
function Comms.step(state, at_mouth, t)
    state = type(state) == "table" and state or {}
    if not finite(t) or not at_mouth then return {engaged = false}, false end
    if state.engaged then return {engaged = true, since = state.since}, true end
    local since = finite(state.since) and state.since or t
    if t < since then since = t end
    local engaged = t - since >= Comms.DWELL_SECONDS
    return {engaged = engaged, since = since}, engaged
end

-- Engine side. The pure part above is what the tests exercise.
Comms.TEST_FLAG = "./../mods/darktidevr/darktidevr_comms_test.flag"

function Comms.install(mod, presentation)
    local api = {}
    local state, failures, entries = {}, 0, 0
    -- The push-to-talk action's mask in the bindings' catalogue.
    local TALK_MASK = 8388608

    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Comms.TEST_FLAG, "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end

    function api.enabled()
        return mod:get("vr_comms_gesture") == true or test_flag()
    end

    local function vector(value)
        if not value then return nil end
        local ok, x, y, z = pcall(Vector3.to_elements, value)
        if not ok or x ~= x then return nil end
        return {x, y, z}
    end

    local function sample(unit, active, t)
        if not active or not unit or not api.enabled() then return false end
        -- The support hand on the gun is holding a weapon, not talking.
        local bindings = presentation.controller_bindings
        if bindings and bindings.support_grip and bindings.support_grip.held then return false end
        local eye, eye_rotation = presentation.eye_pose(unit)
        -- The off hand, so this follows the handedness setting.
        local grip = presentation.weapon_grip_target("support")
        if not eye or not eye_rotation or not grip then return false end
        local local_hand = vector(presentation.rotate_vector(
            presentation.inverse_quaternion(eye_rotation), grip - eye))
        return Comms.at_mouth(local_hand, state.engaged == true)
    end

    function api.apply(unit, active, t)
        local ok, at_mouth = pcall(sample, unit, active, t)
        if not ok then
            -- Keep going, and never leave the microphone held: at_mouth false
            -- closes it through Comms.step below.
            failures = failures + 1
            state = {}
            if failures <= 3 then
                mod:warning("DARKTIDEVR_COMMS error=%s failures=%d",
                    tostring(at_mouth):sub(1, 160), failures)
            end
            at_mouth = false
        end
        local engaged
        state, engaged = Comms.step(state, at_mouth == true, t)
        local bindings = presentation.controller_bindings
        if engaged and bindings then
            bindings.forced = bit.bor(tonumber(bindings.forced) or 0, TALK_MASK)
        end
        if engaged and not api.engaged then
            entries = entries + 1
            if entries <= 10 then mod:info("DARKTIDEVR_COMMS talk entries=%d", entries) end
            local side = presentation.weapon_hand_roles and
                presentation.weapon_hand_roles.physical("support")
            if presentation.haptics and type(t) == "number" and side then
                pcall(presentation.haptics.pulse, side, "zone", t)
            end
        end
        api.engaged = engaged
    end

    function api.destroy() state = {} end
    return api
end

return Comms
