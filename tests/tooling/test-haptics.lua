-- Haptic pulses: kinds and hands map to the native request, the option gates
-- every pulse, a hand is rate limited, and a failed send does not count.
local Haptics = dofile(assert(arg[1]))

local sent, enabled, deliver = {}, true, true
local api = Haptics.new(function(hands, amplitude, duration_ms, frequency_hz)
    sent[#sent + 1] = {hands, amplitude, duration_ms, frequency_hz}
    return deliver
end, function() return enabled end)

assert(api.pulse("left", "zone", 1.0))
assert(sent[1][1] == 1 and sent[1][2] == Haptics.KINDS.zone.amplitude and
    sent[1][3] == Haptics.KINDS.zone.duration_ms and sent[1][4] == 0)
assert(not api.pulse("left", "grip", 1.03), "pulses on one hand were not rate limited")
assert(api.pulse("right", "grip", 1.03), "the other hand was rate limited")
assert(sent[2][1] == 2 and sent[2][3] == Haptics.KINDS.grip.duration_ms)
assert(api.pulse("left", "grip", 1.0 + Haptics.MIN_INTERVAL), "pulse after the interval dropped")
-- A clock that goes backwards (a new timer) is not rate limited forever.
assert(api.pulse("left", "zone", 0.2))
assert(api.sent == 4 and api.dropped == 1)

-- Unknown hands, kinds and times send nothing.
local before = #sent
assert(not api.pulse("both", "zone", 5) and not api.pulse("left", "rumble", 5))
assert(not api.pulse("left", "zone", nil) and not api.pulse("left", "zone", 0 / 0))
assert(#sent == before)

-- The option gates every pulse.
enabled = false
assert(not api.pulse("right", "zone", 10) and #sent == before, "disabled haptics sent a pulse")
enabled = true
-- A failed send is not counted and does not start the interval.
deliver = false
assert(not api.pulse("right", "zone", 10))
deliver = true
assert(api.pulse("right", "zone", 10.01), "a failed send started the rate limit")

-- Every kind is a playable pulse.
for name, shape in pairs(Haptics.KINDS) do
    assert(shape.amplitude > 0 and shape.amplitude <= 1, name)
    assert(shape.duration_ms >= 1 and shape.duration_ms <= 1000 and shape.duration_ms % 1 == 0, name)
end

print("haptics=pass mapping rate_limit option failed_send kinds")
