-- Tag what your off hand points at (todo-2026-09-14, "Hand gestures for
-- comms": off-hand pointing plus stick click to tag). Pure: no engine calls.
--
-- The todo asked for the off-hand stick click. The tag control already is a
-- stick click by default (right stick click), and rebinding the off-hand click
-- would have taken sprint, so the gesture only changes *where* the tag looks:
-- point with the off hand and press tag as usual, and the ray leaves that hand
-- instead of the weapon. Everything else about tagging is stock.
--
-- The hand is judged in head-local metres (x right, y forward, z up, relative
-- to the eye), so pointing follows the head.
local Tag = {}

-- The arm has to be out: a hand resting at the hip or tucked in at the chest
-- is not pointing. Forward of the eye and far enough from it.
Tag.MIN_FORWARD = 0.25
Tag.MIN_DISTANCE = 0.35
-- Once pointing, these relax, so a tag is not lost as the arm settles.
Tag.EXIT_FORWARD = 0.15
Tag.EXIT_DISTANCE = 0.25

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function point(v) return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3]) end

-- Whether a hand, in head-local metres, is held out pointing. `engaged` relaxes
-- the thresholds. Pure.
function Tag.pointing(local_hand, engaged)
    if not point(local_hand) then return false end
    local forward = engaged and Tag.EXIT_FORWARD or Tag.MIN_FORWARD
    local reach = engaged and Tag.EXIT_DISTANCE or Tag.MIN_DISTANCE
    if local_hand[2] < forward then return false end
    local x, y, z = local_hand[1], local_hand[2], local_hand[3]
    return math.sqrt(x * x + y * y + z * z) >= reach
end

-- Which hand the tag ray should leave. Pure.
function Tag.role(pointing)
    return pointing and "support" or "dominant"
end

-- Engine side. The pure part above is what the tests exercise.
Tag.TEST_FLAG = "./../mods/darktidevr/darktidevr_tag_test.flag"

function Tag.install(mod, presentation)
    local api = {}
    local pointing, failed, entries = false, false, 0

    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Tag.TEST_FLAG, "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end

    function api.enabled()
        return mod:get("vr_tag_gesture") == true or test_flag()
    end

    local function vector(value)
        if not value then return nil end
        local ok, x, y, z = pcall(Vector3.to_elements, value)
        if not ok or x ~= x then return nil end
        return {x, y, z}
    end

    local function sample(unit, active)
        if not active or not unit or not api.enabled() then return false end
        -- That hand on the gun, or talking into it, is not pointing.
        local bindings = presentation.controller_bindings
        if bindings and bindings.support_grip and bindings.support_grip.held then return false end
        if presentation.comms_gesture and presentation.comms_gesture.engaged then return false end
        local eye, eye_rotation = presentation.eye_pose(unit)
        local grip = presentation.weapon_grip_target("support")
        if not eye or not eye_rotation or not grip then return false end
        local local_hand = vector(presentation.rotate_vector(
            presentation.inverse_quaternion(eye_rotation), grip - eye))
        return Tag.pointing(local_hand, pointing)
    end

    function api.apply(unit, active, t)
        if failed then return end
        local ok, out = pcall(sample, unit, active)
        if not ok then
            failed = true
            pointing = false
            mod:warning("DARKTIDEVR_TAG error=%s", tostring(out):sub(1, 160))
            return
        end
        if out and not pointing then
            entries = entries + 1
            if entries <= 10 then mod:info("DARKTIDEVR_TAG pointing entries=%d", entries) end
        end
        pointing = out == true
    end

    -- Which hand's aim the tag sites should use this frame.
    function api.role()
        return Tag.role(pointing)
    end

    function api.destroy() pointing = false end
    return api
end

return Tag
