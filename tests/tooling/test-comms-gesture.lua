-- Push to talk with the off hand in front of the mouth: where the hand counts,
-- and the dwell before the microphone opens.
local Comms = dofile(assert(arg[1]))

-- Head-local metres: x right, y forward, z up, relative to the eye. The mouth
-- sits a little forward of and below the eye.
assert(Comms.at_mouth({0, 0.16, -0.12}), 'right at the mouth')
assert(Comms.at_mouth({0.05, 0.25, -0.15}), 'a cupped hand held out in front of it')
assert(Comms.at_mouth({-0.08, 0.10, -0.05}), 'and drawn in close')

-- Not at the mouth: at the eye, at the ear, down at the chest, or out in front.
assert(not Comms.at_mouth({0, 0.16, 0.10}), 'up at the eyes')
assert(not Comms.at_mouth({0.25, -0.05, -0.10}), 'out at the ear, where tracking is poor')
assert(not Comms.at_mouth({0, 0.20, -0.45}), 'down at the chest')
assert(not Comms.at_mouth({0, 0.50, -0.12}), "held out at arm's length")
assert(not Comms.at_mouth(nil) and not Comms.at_mouth({0, 0 / 0, 0}), 'nothing usable')

-- Hysteresis: a hand that drifts out keeps the microphone open rather than
-- chopping the sentence in half.
-- (The zone is a third smaller since 17 September: 0.135 m in, 0.19 m out.)
local drifting = {0, 0.32, -0.16}
assert(not Comms.at_mouth(drifting, false), 'outside the entry radius')
assert(Comms.at_mouth(drifting, true), 'inside the exit radius once talking')

-- Dwell: half a second, so a hand passing the face does not open the mic.
local state, engaged = Comms.step(nil, true, 5.0)
assert(not engaged)
state, engaged = Comms.step(state, true, 5.0 + Comms.DWELL_SECONDS - 0.05)
assert(not engaged, 'still waiting')
state, engaged = Comms.step(state, true, 5.0 + Comms.DWELL_SECONDS + 0.01)
assert(engaged, 'the microphone opens')
-- Dropping the hand closes it at once, and the dwell starts again.
state, engaged = Comms.step(state, false, 6.0)
assert(not engaged)
state, engaged = Comms.step(state, true, 6.1)
assert(not engaged, 'the dwell restarts')

-- A hand sweeping past the face, well under the dwell.
local sweep = nil
for _, at in ipairs({30.0, 30.1, 30.2, 30.3}) do sweep = (Comms.step(sweep, true, at)) end
assert(sweep.engaged == false, 'a 0.3 s pass does not open the microphone')

-- The dwell is longer than the other gestures: an accidental microphone is
-- worse than a missed word.
local Inspect = dofile(assert(arg[2]))
assert(Comms.DWELL_SECONDS > Inspect.DWELL_SECONDS, 'slower to open than to inspect')

-- The mouth zone does reach up towards the chin and nose, which is where a
-- hand held out to speak into actually sits. What keeps this clear of the
-- weapon inspect gesture is the hand, not the zone: inspecting is the weapon
-- in the dominant hand, talking is the off hand.
assert(Comms.at_mouth({0, 0.20, 0.0}), 'up at the nose still counts')

assert(Comms.ENTER_RADIUS == 0.135 and Comms.EXIT_RADIUS == 0.19)
print('comms_gesture=pass at_mouth hysteresis dwell')
