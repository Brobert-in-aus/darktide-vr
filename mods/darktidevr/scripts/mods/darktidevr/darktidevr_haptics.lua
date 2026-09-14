-- Controller vibration requested by gameplay features. The capture library
-- forwards each pulse to the viewer on the presentation packet
-- (dtvr_request_haptic_v1); the viewer plays it with xrApplyHapticFeedback.
-- Option "vr_haptics" (Experimental, default off).
local Haptics = {}

Haptics.HANDS = {left = 1, right = 2}
-- Pulse shapes by feedback kind. Amplitude 0 to 1, duration in milliseconds.
Haptics.KINDS = {
    -- A hand reaches a place where a grip press does something (a gun's
    -- foregrip, an armed holster).
    zone = {amplitude = 0.3, duration_ms = 15},
    -- A grip takes hold (two-hand support).
    grip = {amplitude = 0.55, duration_ms = 30},
}
-- Pulses on one hand closer together than this are dropped: requests between
-- two viewer frames coalesce anyway, and a buzzing hand is no feedback.
Haptics.MIN_INTERVAL = 0.06
Haptics.TEST_FLAG = "./../mods/darktidevr/darktidevr_haptics_test.flag"
Haptics.LOGGED_PULSES = 20

-- send(hands, amplitude, duration_ms, frequency_hz) returns true once the
-- request is on its way. enabled() gates every pulse.
function Haptics.new(send, enabled)
    local api = {last = {}, sent = 0, dropped = 0}
    function api.pulse(hand, kind, t)
        local bits, shape = Haptics.HANDS[hand], Haptics.KINDS[kind]
        if not bits or not shape or type(t) ~= "number" or t ~= t then return false end
        if enabled and not enabled() then return false end
        local last = api.last[hand]
        if last and t >= last and t - last < Haptics.MIN_INTERVAL then
            api.dropped = api.dropped + 1
            return false
        end
        if not send(bits, shape.amplitude, shape.duration_ms, 0) then return false end
        api.last[hand] = t
        api.sent = api.sent + 1
        return true
    end
    return api
end

function Haptics.install(mod, presentation, send)
    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Haptics.TEST_FLAG, "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
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
        return mod:get("vr_haptics") == true or test_flag()
    end)
    local pulse = api.pulse
    -- Callers without a frame time use the main clock.
    function api.pulse(hand, kind, t)
        if t == nil then
            local time = Managers and Managers.time
            t = time and time:has_timer("main") and time:time("main") or nil
        end
        return pulse(hand, kind, t)
    end
    return api
end

return Haptics
