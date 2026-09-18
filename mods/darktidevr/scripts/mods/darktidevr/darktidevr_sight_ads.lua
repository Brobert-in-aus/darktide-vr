-- Sight-to-eye aim down sights (option "vr_sight_ads", default off; backlog
-- item, 15 September): bringing a gun's sight line to the dominant eye holds
-- the alternate-fire input, and moving it away lets go. Only for guns whose
-- alternate is the stock aim (Support.ads_supported). The player's own
-- trigger keeps working alongside.
--
-- The sight line comes from darktidevr_gun_sights: it runs parallel to the
-- aim, offset from the grip in the muzzle frame. The eye is the headset eye
-- (first-person camera) moved SIGHT_EYE_OFFSET toward the gun hand's side,
-- on the assumption that the dominant eye is on the dominant hand's side.
local SightAds = {}

SightAds.SIGHT_EYE_OFFSET = 0.032
-- Worn, 15 September evening: works, wants a slightly larger area and a
-- short grace before letting go.
SightAds.ENTER_DISTANCE = 0.06
SightAds.EXIT_DISTANCE = 0.09
-- Was 0.3 s. Worn on 18 September the grace was the thing people noticed:
-- "remove the delay in ending ads when moving your hand out of the zone". It
-- was added on 15 September against a flicker at the boundary, but the
-- hysteresis between ENTER_DISTANCE and EXIT_DISTANCE already covers that --
-- the gun has to travel 3 cm further out than it came in before the sights
-- drop -- so the timer was a second defence that cost a visible lag on every
-- exit. Zero means the release is immediate; `hold` still handles it, so the
-- grace can be put back by this number alone if the flicker returns.
SightAds.RELEASE_GRACE_SECONDS = 0
SightAds.MIN_BEHIND = 0.03   -- the eye is behind the grip plane along the aim
SightAds.MAX_BEHIND = 0.6
SightAds.ENTER_FACING = math.cos(math.rad(25))
SightAds.EXIT_FACING = math.cos(math.rad(35))
SightAds.ALTERNATE_BIT = 2

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function valid3(v) return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3]) end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

-- Geometry of the eye against the sight line. grip, eye: 3-arrays; forward,
-- up, right: the aim's unit axes; offset {x=, z=} in the muzzle frame;
-- head_forward: unit 3-array. Returns distance from the line, how far the eye
-- is behind the grip plane, and the facing dot. Pure.
function SightAds.measure(grip, forward, up, right, offset, eye, head_forward)
    if not valid3(grip) or not valid3(forward) or not valid3(up) or not valid3(right) or
        not valid3(eye) or not valid3(head_forward) or type(offset) ~= "table" or
        not finite(offset.x) or not finite(offset.z) then return nil end
    local sight = {grip[1] + right[1] * offset.x + up[1] * offset.z,
        grip[2] + right[2] * offset.x + up[2] * offset.z,
        grip[3] + right[3] * offset.x + up[3] * offset.z}
    local to_eye = {eye[1] - sight[1], eye[2] - sight[2], eye[3] - sight[3]}
    local along = dot(to_eye, forward)
    local across = {to_eye[1] - forward[1] * along, to_eye[2] - forward[2] * along, to_eye[3] - forward[3] * along}
    return math.sqrt(dot(across, across)), -along, dot(forward, head_forward)
end

-- Whether the sight is at the eye, with hysteresis. Pure.
function SightAds.engaged(was_engaged, distance, behind, facing)
    if not finite(distance) or not finite(behind) or not finite(facing) then return false end
    if behind < SightAds.MIN_BEHIND or behind > SightAds.MAX_BEHIND then return false end
    if was_engaged then
        return distance <= SightAds.EXIT_DISTANCE and facing >= SightAds.EXIT_FACING
    end
    return distance <= SightAds.ENTER_DISTANCE and facing >= SightAds.ENTER_FACING
end

-- Engaged after the release grace: stays engaged until the sights have been
-- away for RELEASE_GRACE_SECONDS. Returns engaged, seconds away. Pure.
function SightAds.hold(was_engaged, at_eye, away, dt)
    if at_eye then return true, 0 end
    if not was_engaged then return false, 0 end
    away = (away or 0) + ((type(dt) == "number" and dt == dt and dt > 0) and dt or 0)
    return away < SightAds.RELEASE_GRACE_SECONDS, away
end

-- Input edges for one frame: held stays set while engaged. Hold mode presses
-- on entry and releases on exit; toggle mode presses once on entry and once on
-- exit. Returns pressed, held, released booleans. Pure.
function SightAds.edges(was_engaged, engaged, toggle)
    if toggle then
        return engaged ~= was_engaged, false, false
    end
    return engaged and not was_engaged, engaged, was_engaged and not engaged
end

function SightAds.install(mod, presentation, observation)
    local api = {engaged = false, entries = 0}
    SightAds.ads_supported = SightAds.ads_supported or
        mod:io_dofile("darktidevr/scripts/mods/darktidevr/darktidevr_two_hand_support").ads_supported
    local failures = 0
    local function vector(v) return v and {Vector3.x(v), Vector3.y(v), Vector3.z(v)} or nil end
    -- Unattended runs: darktidevr_sight_ads_test.flag "enabled" turns it on
    -- and logs the measurement about once a second; players never have it.
    local test_poll, test_enabled, test_frames = 0, false, 0
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        -- Every 300 calls (about five seconds at the input rate): a failed open
        -- on the main thread each poll is where these modules' spikes came
        -- from (docs/LUA-FRAME-PROFILE-2026-09-16.md).
        test_poll = 300
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open("./../mods/darktidevr/darktidevr_sight_ads_test.flag", "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end
    local function enabled()
        return (mod.get and mod:get("vr_sight_ads") == true) or test_flag()
    end
    local function current(handler, unit)
        if not enabled() or not observation.gameplay_input_active or not unit then return false end
        local weapon = ScriptUnit.has_extension(unit, "weapon_system")
        local template = weapon and weapon:weapon_template()
        if not template or not presentation.gun_aim or not presentation.gun_aim.is_gun(template) then return false end
        if not SightAds.ads_supported or not SightAds.ads_supported(template) then return false end
        local offset = presentation.gun_sights and presentation.gun_sights.sight_offset(template.name)
        if not offset then return false end
        local grip = presentation.weapon_grip_target and presentation.weapon_grip_target("dominant")
        local _, aim = presentation.weapon_aim_target("dominant")
        -- The tracked headset eye (presentation.eye_pose): the first-person
        -- unit misses head translation and never met the sights (worn, 15
        -- September).
        local eye_position, head
        if presentation.eye_pose then eye_position, head = presentation.eye_pose(unit) end
        if not grip or not aim or not eye_position or not head then return false end
        local dominant = presentation.weapon_hand_roles.physical("dominant")
        local side = dominant == "left" and -1 or 1
        local eye = eye_position + Quaternion.right(head) * (SightAds.SIGHT_EYE_OFFSET * side)
        local distance, behind, facing = SightAds.measure(vector(grip), vector(Quaternion.forward(aim)),
            vector(Quaternion.up(aim)), vector(Quaternion.right(aim)), offset, vector(eye), vector(Quaternion.forward(head)))
        local at_eye = SightAds.engaged(api.engaged, distance, behind, facing)
        local now = Managers.time and Managers.time:time("main") or 0
        local dt = api.last_t and now - api.last_t or 0
        api.last_t = now
        local engaged
        engaged, api.away = SightAds.hold(api.engaged, at_eye, api.away, dt)
        if test_enabled then
            test_frames = test_frames + 1
            if test_frames % 90 == 1 then
                mod:info("DARKTIDEVR_SIGHT_ADS measure template=%s distance_m=%s behind_m=%s facing=%s engaged=%s",
                    template.name, tostring(distance), tostring(behind), tostring(facing), tostring(engaged))
            end
        end
        if engaged and not api.engaged then
            api.entries = api.entries + 1
            -- A tick in the gun hand as the sights meet the eye.
            if presentation.haptics and presentation.haptics.pulse and (dominant == "left" or dominant == "right") then
                pcall(presentation.haptics.pulse, dominant, "zone", Managers.time and Managers.time:time("main") or 0)
            end
            if api.entries <= 10 then
                mod:info("DARKTIDEVR_SIGHT_ADS enter template=%s distance_m=%.3f behind_m=%.3f facing=%.3f entries=%d",
                    template.name, distance, behind, facing, api.entries)
            end
        end
        return engaged
    end
    -- After the native gameplay input read: add the alternate-fire edges.
    function api.apply(handler, unit)
        local ok, engaged = pcall(current, handler, unit)
        if not ok then
            failures = failures + 1
            if failures == 1 then mod:info("DARKTIDEVR_SIGHT_ADS failed=%s", tostring(engaged):sub(1, 160)) end
            engaged = false
        end
        local settings = handler and handler._input_settings_table
        local toggle = settings and settings.toggle_ads == true
        local pressed, held, released = SightAds.edges(api.engaged, engaged == true, toggle)
        if (pressed or held or released) and observation.gameplay_held then
            local bit_value = SightAds.ALTERNATE_BIT
            if pressed then observation.gameplay_pressed[0] = bit.bor(tonumber(observation.gameplay_pressed[0]) or 0, bit_value) end
            if held then observation.gameplay_held[0] = bit.bor(tonumber(observation.gameplay_held[0]) or 0, bit_value) end
            -- The player's own held trigger keeps the aim: no release under it.
            local own_hold = bit.band(tonumber(observation.gameplay_held[0]) or 0, bit_value) ~= 0
            if released and not own_hold then
                observation.gameplay_released[0] = bit.bor(tonumber(observation.gameplay_released[0]) or 0, bit_value)
            end
        end
        if api.engaged and not engaged and api.entries <= 10 then
            mod:info("DARKTIDEVR_SIGHT_ADS exit entries=%d", api.entries)
        end
        api.engaged = engaged == true
    end
    return api
end

return SightAds
