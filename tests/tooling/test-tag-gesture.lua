-- Tag what the off hand points at: when a hand counts as pointing, and which
-- hand the tag ray then leaves.
local Tag = dofile(assert(arg[1]))

-- Head-local metres: x right, y forward, z up, relative to the eye.
assert(Tag.pointing({-0.20, 0.45, -0.25}), 'off arm held out ahead')
assert(Tag.pointing({0.10, 0.50, 0.05}), 'and up at something high')

-- Not pointing: hand at the hip, tucked at the chest, or out to the side.
assert(not Tag.pointing({-0.25, 0.05, -0.60}), 'down at the hip')
assert(not Tag.pointing({-0.10, 0.15, -0.20}), 'tucked in at the chest')
assert(not Tag.pointing({-0.55, 0.05, -0.10}), 'out to the side, not ahead')
assert(not Tag.pointing(nil) and not Tag.pointing({0, 0 / 0, 0}), 'nothing usable')

-- Once pointing, the arm may settle without losing the tag.
local settling = {-0.15, 0.20, -0.20}
assert(not Tag.pointing(settling, false), 'not enough to start pointing')
assert(Tag.pointing(settling, true), 'enough to keep pointing')

-- Which hand the ray leaves.
assert(Tag.role(true) == 'support', 'the pointing hand')
assert(Tag.role(false) == 'dominant', 'otherwise the weapon, as stock VR tagging does')

-- Linger: a tag is a press, not a hold, and it lands a moment after the arm
-- has started to come down. Run gest3 showed the pose falling in and out
-- several times a second as a moving arm crossed the thresholds.
local state, out = Tag.step(nil, true, 100)
assert(out and state.pointing)
state, out = Tag.step(state, false, 100 + Tag.LINGER_SECONDS - 0.05)
assert(out, 'the press just after the arm drops still goes to the hand')
state, out = Tag.step(state, false, 100 + Tag.LINGER_SECONDS + 0.05)
assert(not out and state.pointing == false, 'and then it lets go')
-- Re-entering while lingering keeps it, with the linger pushed out.
local again = select(1, Tag.step(select(1, Tag.step(nil, true, 200)), true, 200.2))
assert(again.until_t == 200.2 + Tag.LINGER_SECONDS, 'the linger follows the last pose')
-- Time running backwards drops it rather than lingering forever.
assert(select(2, Tag.step({pointing = true, until_t = 500}, false, 5)) == false)
assert(select(2, Tag.step({pointing = true, until_t = 500}, false, 0 / 0)) == false)

print('tag_gesture=pass pointing hysteresis role linger')
