-- Inspect by bringing the weapon to the face: the pose test (near the eye and
-- turned across the view, with hysteresis) and the dwell before it engages.
local Inspect = dofile(assert(arg[1]))

local EYE = {0, 0, 1.7}
local LOOK = {0, 1, 0}
-- A weapon held up at the face, turned across the view to be looked at.
local function gun(distance, degrees)
    local radians = math.rad(degrees)
    return {0, distance, 1.7}, {math.sin(radians), math.cos(radians), 0}
end

local held, forward = gun(0.25, 90)
assert(Inspect.in_pose(EYE, LOOK, held, forward, false), 'close and turned side on')
-- Aimed, not inspected: at the eye but pointing where the player looks. This
-- is what sight-to-eye ADS looks like.
assert(not Inspect.in_pose(EYE, LOOK, gun(0.25, 0)), 'pointing down the view is aiming')
assert(not Inspect.in_pose(EYE, LOOK, gun(0.25, 30)), 'barely turned is still aiming')
-- Turned but out at arm's length: carried, not inspected.
assert(not Inspect.in_pose(EYE, LOOK, gun(0.6, 90)), 'too far from the face')

-- Hysteresis: it takes 55 degrees and 0.32 m to start, and holds until the
-- weapon comes back within 40 degrees or past 0.42 m, so a weapon held at the
-- boundary does not flicker.
local edge, edge_forward = gun(0.38, 45)
assert(not Inspect.in_pose(EYE, LOOK, edge, edge_forward, false), 'outside the entry thresholds')
assert(Inspect.in_pose(EYE, LOOK, edge, edge_forward, true), 'inside the exit thresholds once engaged')

assert(not Inspect.in_pose(nil, LOOK, held, forward, false))
assert(not Inspect.in_pose(EYE, LOOK, {0, 0 / 0, 1.7}, forward, false), 'non-finite')

-- Dwell: a weapon swung past the face is not an inspection.
local state, engaged = Inspect.step(nil, true, 10.0)
assert(not engaged, 'the dwell has not run yet')
state, engaged = Inspect.step(state, true, 10.0 + Inspect.DWELL_SECONDS - 0.01)
assert(not engaged)
state, engaged = Inspect.step(state, true, 10.0 + Inspect.DWELL_SECONDS + 0.01)
assert(engaged, 'engages once the pose has been held long enough')
-- Once engaged it stays without re-running the dwell.
state, engaged = Inspect.step(state, true, 10.5)
assert(engaged)
-- Losing the pose ends it at once: putting the weapon down stops the animation.
state, engaged = Inspect.step(state, false, 10.6)
assert(not engaged and state.engaged == false)
-- And the dwell starts again from there.
state, engaged = Inspect.step(state, true, 10.7)
assert(not engaged, 'the dwell restarts')

-- A swing past the face: in the pose for less than the dwell, then out.
local swing = nil
for _, at in ipairs({20.0, 20.1, 20.2}) do swing = (Inspect.step(swing, true, at)) end
assert(swing.engaged == false, 'a 0.2 s pass does not inspect')

-- Time running backwards (a level change) restarts rather than engaging.
local back = Inspect.step({engaged = false, since = 100}, true, 5)
assert(back.engaged == false and back.since == 5)
assert(select(2, Inspect.step({}, true, 0 / 0)) == false, 'no time, no engage')

print('weapon_inspect=pass pose hysteresis dwell')
