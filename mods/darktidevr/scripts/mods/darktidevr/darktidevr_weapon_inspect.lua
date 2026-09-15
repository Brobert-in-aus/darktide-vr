-- Inspect by bringing the weapon to the face (todo-2026-09-14). Pure: no
-- engine calls.
--
-- Stock inspect is a held action (`weapon_inspect_hold`) that no VR control is
-- bound to by default. Here the gesture holds it: bring the weapon up to your
-- face and turn it to look at it, and the stock inspect animation runs for as
-- long as you keep it there.
--
-- Turning it matters. Sight-to-eye ADS also brings the weapon to the eye, but
-- with the gun pointing where you look; a weapon you are looking *at* is
-- across your view. The angle between the gun's forward and your look
-- direction separates the two, and keeps this off while aiming down sights.
local Inspect = {}

-- Enter with the weapon this close to the eye, leave when it is this far: the
-- gap keeps a weapon held at the boundary from flickering in and out.
Inspect.ENTER_DISTANCE = 0.32
Inspect.EXIT_DISTANCE = 0.42
-- The gun must be turned at least 55 degrees from the look direction to start,
-- or it is being aimed rather than looked at, and it keeps the inspection
-- until it comes back within 40 degrees. Stored as cosines: a larger cosine is
-- a smaller angle, so the exit value is the more forgiving one.
Inspect.ENTER_COS = math.cos(math.rad(55))
Inspect.EXIT_COS = math.cos(math.rad(40))
-- Held this long before it engages: a weapon swung past the face is not an
-- inspection.
Inspect.DWELL_SECONDS = 0.35

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function point(v) return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3]) end
local function distance(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

-- Whether the weapon is in the inspect pose, given the eye, the look
-- direction, the gun's position and the gun's forward, and whether it is
-- already engaged (which widens both thresholds). Pure.
function Inspect.in_pose(eye, look, gun, gun_forward, engaged)
    if not point(eye) or not point(look) or not point(gun) or not point(gun_forward) then return false end
    local reach = engaged and Inspect.EXIT_DISTANCE or Inspect.ENTER_DISTANCE
    if distance(eye, gun) > reach then return false end
    local turned = engaged and Inspect.EXIT_COS or Inspect.ENTER_COS
    return dot(look, gun_forward) < turned
end

-- The engaged state after a sample. `state` is carried between calls:
-- {engaged = bool, since = number}. Returns the new state and whether it is
-- engaged now. A pose held for DWELL_SECONDS engages; losing the pose
-- disengages at once, so putting the weapon down ends the inspection. Pure.
function Inspect.step(state, in_pose, t)
    state = type(state) == "table" and state or {}
    if not finite(t) then return {engaged = false}, false end
    if not in_pose then return {engaged = false}, false end
    if state.engaged then return {engaged = true, since = state.since}, true end
    local since = finite(state.since) and state.since or t
    -- Time running backwards (a level change) restarts the dwell.
    if t < since then since = t end
    local engaged = t - since >= Inspect.DWELL_SECONDS
    return {engaged = engaged, since = since}, engaged
end

-- Engine side. The pure part above is what the tests exercise.
Inspect.TEST_FLAG = "./../mods/darktidevr/darktidevr_inspect_test.flag"

function Inspect.install(mod, presentation)
    local api = {}
    local state, failed, entries = {}, false, 0
    -- The stock inspect action's mask in the bindings' catalogue.
    local INSPECT_MASK = 16384

    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Inspect.TEST_FLAG, "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end

    function api.enabled()
        return mod:get("vr_weapon_inspect") == true or test_flag()
    end

    local function vector(value)
        if not value then return nil end
        local ok, x, y, z = pcall(Vector3.to_elements, value)
        if not ok or x ~= x then return nil end
        return {x, y, z}
    end

    local function sample(unit, active, t)
        if not active or not unit or not api.enabled() then return false end
        -- Aiming down the sights is the other way a weapon comes to the eye.
        if presentation.sight_ads and presentation.sight_ads.engaged then return false end
        local eye, eye_rotation = presentation.eye_pose(unit)
        local look = eye_rotation and vector(Quaternion.forward(eye_rotation))
        -- The controller holding the weapon, not the drawn gun: this runs at
        -- input time, where the gun's own pose for the frame is not placed yet.
        local grip, grip_rotation = presentation.weapon_grip_target("dominant")
        if not grip or not grip_rotation then return false end
        local aim = presentation.gun_aim and presentation.gun_aim.base_aim
        if aim then
            local ok, corrected = pcall(aim, unit, grip_rotation)
            if ok and corrected then grip_rotation = corrected end
        end
        return Inspect.in_pose(vector(eye), look, vector(grip),
            vector(Quaternion.forward(grip_rotation)), state.engaged == true)
    end

    function api.apply(unit, active, t)
        if failed then return end
        local ok, in_pose = pcall(sample, unit, active, t)
        if not ok then
            failed = true
            state = {}
            mod:warning("DARKTIDEVR_INSPECT error=%s", tostring(in_pose):sub(1, 160))
            in_pose = false
        end
        local engaged
        state, engaged = Inspect.step(state, in_pose == true, t)
        local bindings = presentation.controller_bindings
        if engaged and bindings then
            bindings.forced = bit.bor(tonumber(bindings.forced) or 0, INSPECT_MASK)
        end
        if engaged and not api.engaged then
            entries = entries + 1
            if entries <= 10 then mod:info("DARKTIDEVR_INSPECT enter entries=%d", entries) end
            if presentation.haptics and type(t) == "number" then
                pcall(presentation.haptics.pulse, "right", "zone", t)
            end
        end
        api.engaged = engaged
    end

    function api.destroy() state = {} end
    return api
end

return Inspect
