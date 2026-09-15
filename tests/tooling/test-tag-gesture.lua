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

print('tag_gesture=pass pointing hysteresis role')
