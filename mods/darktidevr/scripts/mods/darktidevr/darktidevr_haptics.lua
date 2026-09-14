-- Controller vibration requested by gameplay features. The capture library
-- forwards each pulse to the viewer on the presentation packet
-- (dtvr_request_haptic_v1); the viewer plays it with xrApplyHapticFeedback.
-- Option "vr_haptics_mode" (Experimental): off (default), informative or
-- immersive. Each kind lists the modes that play it: some in both (a grip in
-- reach, the clip running dry), some only informative (notices such as low
-- ammo), some only immersive (the feel of actions such as every shot). The
-- catalogue and plan: docs/phase1/haptics-2026-09-14.md.
local Haptics = {}

Haptics.HANDS = {left = 1, right = 2, both = 3}
Haptics.MODES = {off = true, informative = true, immersive = true}
local BOTH = {informative = true, immersive = true}
-- Pulse shapes by feedback kind: the modes that play it, whether it is a
-- notice (never dropped for a feel pulse), amplitude 0 to 1 and duration in
-- milliseconds.
Haptics.KINDS = {
    -- A hand reaches a place where a grip press does something (a gun's
    -- foregrip, an armed holster).
    zone = {modes = BOTH, notice = true, amplitude = 0.3, duration_ms = 15},
    -- A grip takes hold (two-hand support).
    grip = {modes = BOTH, notice = true, amplitude = 0.55, duration_ms = 30},
    -- The last round in the clip was fired.
    clip_empty = {modes = BOTH, notice = true, amplitude = 0.8, duration_ms = 90},
    -- A reload put the clip back to full (or used the last of the reserve).
    reload = {modes = BOTH, notice = true, amplitude = 0.5, duration_ms = 45},
    -- Clip and reserve together fell to the stock low-ammo share (20 %).
    low_ammo = {modes = {informative = true}, notice = true, amplitude = 0.4, duration_ms = 25},
    -- A shot left the gun (continuous weapons pulse at the rate limit).
    shot = {modes = {immersive = true}, amplitude = 0.65, duration_ms = 20},
}
Haptics.LOW_AMMO_SHARE = 0.2
-- Pulses on one hand closer together than this are dropped: requests between
-- two viewer frames coalesce anyway, and a buzzing hand is no feedback.
-- A notice is never dropped for a feel pulse.
Haptics.MIN_INTERVAL = 0.06
Haptics.TEST_FLAG = "./../mods/darktidevr/darktidevr_haptics_test.flag"
Haptics.LOGGED_PULSES = 20

-- Whether a kind plays in a mode (an unset or foreign mode plays nothing).
function Haptics.plays(kind, mode)
    local shape = Haptics.KINDS[kind]
    return shape ~= nil and type(mode) == "string" and shape.modes[mode] == true
end

-- send(hands, amplitude, duration_ms, frequency_hz) returns true once the
-- request is on its way. mode() returns the current mode name.
function Haptics.new(send, mode)
    local api = {last = {}, sent = 0, dropped = 0}
    function api.pulse(hand, kind, t)
        local bits, shape = Haptics.HANDS[hand], Haptics.KINDS[kind]
        if not bits or not shape or type(t) ~= "number" or t ~= t then return false end
        if not Haptics.plays(kind, mode and mode()) then return false end
        local notice = shape.notice == true
        for name, bit in pairs(Haptics.HANDS) do
            local last = api.last[name]
            if name ~= "both" and bits % (bit * 2) >= bit and last and t >= last.t and
                    t - last.t < Haptics.MIN_INTERVAL and not (notice and not last.notice) then
                api.dropped = api.dropped + 1
                return false
            end
        end
        if not send(bits, shape.amplitude, shape.duration_ms, 0) then return false end
        for name, bit in pairs(Haptics.HANDS) do
            if name ~= "both" and bits % (bit * 2) >= bit then api.last[name] = {t = t, notice = notice} end
        end
        api.sent = api.sent + 1
        return true
    end
    return api
end

-- Ammo feedback from two readings of the wielded gun ({weapon, clip,
-- clip_max, reserve, reserve_max}): the clip reaching 0; a reload (clip up
-- while the reserve went down, so a pickup is not a reload) that fills the
-- clip or empties the reserve, so a shell-by-shell reload pulses once when
-- full; and clip plus reserve falling to LOW_AMMO_SHARE of their capacity.
function Haptics.ammo_events(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table" or previous.weapon ~= current.weapon or
            type(previous.clip) ~= "number" or type(current.clip) ~= "number" then
        return nil
    end
    if previous.clip > 0 and current.clip == 0 then return "clip_empty" end
    if current.clip > previous.clip and type(previous.reserve) == "number" and
            type(current.reserve) == "number" and current.reserve < previous.reserve and
            (current.clip >= (current.clip_max or math.huge) or current.reserve == 0) then
        return "reload"
    end
    local capacity = (current.clip_max or 0) + (current.reserve_max or 0)
    if capacity > 0 and type(previous.reserve) == "number" and type(current.reserve) == "number" then
        local before = (previous.clip + previous.reserve) / capacity
        local after = (current.clip + current.reserve) / capacity
        if before > Haptics.LOW_AMMO_SHARE and after <= Haptics.LOW_AMMO_SHARE then return "low_ammo" end
    end
    return nil
end

function Haptics.install(mod, presentation, send)
    local test_poll, test_mode = 0, nil
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_mode end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Haptics.TEST_FLAG, "r")
        if not file then test_mode = nil; return nil end
        local value = file:read("*all"); file:close()
        value = type(value) == "string" and value:match("^%s*(%a+)%s*$")
        test_mode = value == "enabled" and "immersive" or (Haptics.MODES[value] and value) or nil
        return test_mode
    end
    local logged = 0
    local function logged_send(hands, amplitude, duration_ms, frequency_hz)
        local ok, delivered = pcall(send, hands, amplitude, duration_ms, frequency_hz)
        delivered = ok and delivered == true
        if logged < Haptics.LOGGED_PULSES then
            logged = logged + 1
            mod:info("DARKTIDEVR_HAPTICS pulse hands=%d amplitude=%.2f duration_ms=%d delivered=%s",
                hands, amplitude, duration_ms, tostring(delivered))
        end
        return delivered
    end
    local api = Haptics.new(logged_send, function()
        return test_flag() or mod:get("vr_haptics_mode")
    end)
    local pulse = api.pulse
    local function now()
        local time = Managers and Managers.time
        return time and time:has_timer("main") and time:time("main") or nil
    end
    -- Callers without a frame time use the main clock.
    function api.pulse(hand, kind, t)
        return pulse(hand, kind, t == nil and now() or t)
    end
    local counts = {}
    local function count(kind)
        counts[kind] = (counts[kind] or 0) + 1
        if counts[kind] == 1 or counts[kind] % 50 == 0 then
            mod:info("DARKTIDEVR_HAPTICS event=%s count=%d", kind, counts[kind])
        end
    end
    -- The gun hand, and both hands while the support hand holds the foregrip.
    local function gun_hands()
        local roles = presentation.weapon_hand_roles
        local dominant = roles and roles.physical("dominant")
        if dominant ~= "left" and dominant ~= "right" then return nil end
        return presentation.two_hand and presentation.two_hand.held and "both" or dominant
    end
    -- From the stock shot dispatch (local player, not resimulating).
    function api.shot()
        local hands = gun_hands()
        if hands and api.pulse(hands, "shot") then count("shot") end
    end
    local previous
    -- Once per gameplay frame, after input.
    function api.sample_weapon(unit)
        local mode = test_flag() or mod:get("vr_haptics_mode")
        if not unit or (mode ~= "informative" and mode ~= "immersive") then
            previous = nil; return
        end
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local inventory = unit_data and unit_data:read_component("inventory")
        if not inventory or inventory.wielded_slot ~= "slot_secondary" then previous = nil; return end
        local values = presentation.ammo_readout and presentation.ammo_readout.slot_values and
            presentation.ammo_readout.slot_values(unit)
        local current = values and values.clip and {weapon = inventory.slot_secondary, clip = values.clip,
            clip_max = values.clip_max, reserve = values.reserve, reserve_max = values.reserve_max} or nil
        local event = Haptics.ammo_events(previous, current)
        previous = current
        local hands = event and gun_hands()
        if hands and api.pulse(hands, event) then count(event) end
    end
    return api
end

return Haptics
