-- The procedural gait, run as the mirror runs it: the copy's root every
-- frame, and the feet it returns. Asserts the constraints a gait has to
-- hold rather than the numbers chosen: planted feet do not slide, one foot
-- in the air at a time, a foot never left farther behind than a leg can
-- reach, small movements answered with small steps, and a turn on the spot
-- re-planting the feet.
local Gait = dofile(assert(arg[1]))
local rest = {left = {-0.11, 0.02, 0.09}, right = {0.11, -0.02, 0.09}}
local DT = 1 / 90

local function run(state, path, dt, ground_at)
    -- path(t) -> root, yaw; steps the gait and records everything.
    local t, frames, out = 0, {}, nil
    while true do
        local root, yaw, done = path(t)
        if done then break end
        out = assert(Gait.update(state, root, yaw, 0, t, dt or DT, 1, ground_at))
        frames[#frames + 1] = {t = t, root = root, yaw = yaw, out = out, planted = {
            left = {state.feet.left.planted[1], state.feet.left.planted[2]},
            right = {state.feet.right.planted[1], state.feet.right.planted[2]}}}
        t = t + (dt or DT)
    end
    return frames
end
local function dist(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end

-- Standing still: the feet plant at their rest places and never step.
local state = Gait.new(rest)
local frames = run(state, function(t) return {1, 2, 0.95}, 0.3, t > 2 end)
for _, f in ipairs(frames) do
    assert(not f.out.left.swinging and not f.out.right.swinging, 'a step while standing still')
end
local ideal_left = Gait.ideal({1, 2, 0.95}, 0.3, rest.left, 0, 1)
assert(dist(frames[#frames].out.left.position, ideal_left) < 1e-9, 'planted at the rest place')
assert(frames[#frames].out.left.position[3] == 0, 'planted on the ground')

-- A drift under the trigger is not a step; one over it is a small step,
-- taken as soon as the trigger is crossed, landing near where the ideal
-- place went, with a proportionally low arc. The drifts are gradual, as a
-- lean or a shuffle across the room is (a jump is the teleport case below).
state = Gait.new(rest)
run(state, function(t) return {0, 0, 1}, 0, t > 0.5 end)
frames = run(state, function(t) return {math.min(0.05, 0.1 * t), 0, 1}, 0, t > 1.5 end)
for _, f in ipairs(frames) do assert(not f.out.left.swinging and not f.out.right.swinging, 'a 5 cm drift stepped') end
state = Gait.new(rest)
run(state, function(t) return {0, 0, 1}, 0, t > 0.5 end)
frames = run(state, function(t) return {math.min(0.10, 0.2 * t), 0, 1}, 0, t > 2.5 end)
local started, max_lift = nil, 0
for i, f in ipairs(frames) do
    if not started and (f.out.left.stepped or f.out.right.stepped) then started = f.t end
    max_lift = math.max(max_lift, f.out.left.position[3], f.out.right.position[3])
end
assert(started and started < 0.5, 'a 10 cm drift did not step as the trigger was crossed: ' .. tostring(started))
local last = frames[#frames]
assert(not last.out.left.swinging and not last.out.right.swinging, 'the small step never landed')
for _, side in ipairs({'left', 'right'}) do
    assert(dist(last.out[side].position, Gait.ideal({0.10, 0, 1}, 0, rest[side], 0, 1)) < 0.05,
        side .. ' foot settled off its ideal place')
end
assert(max_lift > 0 and max_lift < Gait.ARC_M * 0.6, 'a small step should lift a little, not the full arc: ' .. max_lift)

-- Walking: constant 1.2 m/s for three seconds. One foot in the air at a
-- time, planted feet never slide, no foot ever farther from its ideal than
-- a step can cover, and the two feet share the work.
state = Gait.new(rest)
local speed = 1.2
frames = run(state, function(t) return {0, speed * t, 1}, 0, t > 3 end)
local steps, worst = {left = 0, right = 0}, 0
for i, f in ipairs(frames) do
    assert(not (f.out.left.swinging and f.out.right.swinging), 'both feet in the air at frame ' .. i)
    for _, side in ipairs({'left', 'right'}) do
        if f.out[side].stepped then steps[side] = steps[side] + 1 end
        if not f.out[side].swinging and i > 1 and not frames[i - 1].out[side].swinging then
            assert(dist(f.out[side].position, frames[i - 1].out[side].position) < 1e-9, side .. ' foot slid while planted at frame ' .. i)
        end
        -- The drawn foot, not the planted record: a swinging foot's record
        -- is its take-off place until it lands.
        worst = math.max(worst, dist(f.out[side].position, Gait.ideal(f.root, f.yaw, rest[side], 0, 1)))
    end
end
assert(steps.left >= 3 and steps.right >= 3, 'too few steps: ' .. steps.left .. '/' .. steps.right)
assert(math.abs(steps.left - steps.right) <= 1, 'the feet did not alternate: ' .. steps.left .. '/' .. steps.right)
assert(worst < Gait.MAX_STEP_M, 'a foot was left ' .. worst .. ' m behind')
-- The landing leads the body: at speed, a step lands ahead of the ideal
-- place it was measured against.
local a_step
for i, f in ipairs(frames) do if i > 90 and f.out.left.stepped then a_step = f; break end end
assert(a_step, 'no step found once walking')
local landing = state and nil
for i, f in ipairs(frames) do
    if f.t > a_step.t and not f.out.left.swinging and frames[i - 1].out.left.swinging then landing = f; break end
end
assert(landing, 'the step never landed')
local ideal_at_start = Gait.ideal(a_step.root, a_step.yaw, rest.left, 0, 1)
assert(landing.out.left.position[2] > ideal_at_start[2] + 0.1, 'the step did not lead the body')
-- Duration shortens with speed and is clamped.
assert(math.abs(Gait.duration(0) - Gait.DURATION_S) < 1e-9 and Gait.duration(10) == Gait.MIN_DURATION_S)
assert(Gait.duration(2) < Gait.duration(0), 'faster is not quicker')

-- A run: 4 m/s for three seconds. The feet keep up (no drawn foot ever
-- farther from its ideal than a step can cover), both may be in the air
-- but never the same foot twice, each swing lands before that foot steps
-- again, and there are more steps per second than at a walk.
state = Gait.new(rest)
-- A sprint start: 0 to 4 m/s over half a second, then 4 m/s.
frames = run(state, function(t)
    local y = t < 0.5 and 4 * t * t or 1 + 4 * (t - 0.5)
    return {0, y, 1}, 0, t > 3
end)
local run_steps, run_worst, both_in_air = 0, 0, false
for i, f in ipairs(frames) do
    if f.out.left.swinging and f.out.right.swinging then both_in_air = true end
    for _, side in ipairs({'left', 'right'}) do
        if f.out[side].stepped then
            run_steps = run_steps + 1
            -- A foot may land and step again in one frame; it may not
            -- abandon a swing. If it was in the air last frame it must
            -- have been within a frame of landing.
            local before = i > 1 and frames[i - 1].out[side] or nil
            assert(not before or not before.swinging or before.progress == nil or
                before.progress >= 1 - DT / Gait.MIN_DURATION_S, side .. ' stepped again while in the air at frame ' .. i)
        end
        run_worst = math.max(run_worst, dist(f.out[side].position, Gait.ideal(f.root, f.yaw, rest[side], 0, 1)))
    end
end
assert(run_worst < Gait.MAX_STEP_M, 'at a run a foot was left ' .. run_worst .. ' m behind')
assert(both_in_air, 'a run should have a flight phase')
-- Over the same three seconds, more steps than the walk took.
assert(run_steps > steps.left + steps.right, 'a run should step more often than a walk: ' .. run_steps .. ' vs ' .. (steps.left + steps.right))

-- A swing lifts in the middle and lands exactly on its target.
state = Gait.new(rest)
run(state, function(t) return {0, 0, 1}, 0, t > 0.3 end)
frames = run(state, function(t) return {0, 0.4, 1}, 0, t > 1.5 end)
local mid_lift, landed_exactly = 0, false
for i, f in ipairs(frames) do
    local foot = state.feet.left
    if f.out.left.swinging and f.out.left.progress and math.abs(f.out.left.progress - 0.5) < 0.03 then
        mid_lift = math.max(mid_lift, f.out.left.position[3])
    end
end
assert(mid_lift > Gait.ARC_M * 0.9, 'no lift at mid swing: ' .. mid_lift)
-- Every landing is exactly the swing's target (no slide on touchdown).
for i = 2, #frames do
    for _, side in ipairs({'left', 'right'}) do
        if frames[i - 1].out[side].swinging and not frames[i].out[side].swinging then
            assert(frames[i].out[side].position[3] == 0, side .. ' landed above the ground')
            landed_exactly = true
        end
    end
end
assert(landed_exactly, 'nothing landed')

-- Turning on the spot past the trigger re-plants both feet to the new
-- heading; under it, nothing moves.
state = Gait.new(rest)
run(state, function(t) return {0, 0, 1}, 0, t > 0.3 end)
frames = run(state, function(t) return {0, 0, 1}, math.rad(30), t > 1 end)
for _, f in ipairs(frames) do assert(not f.out.left.swinging and not f.out.right.swinging, 'a 30 degree turn stepped') end
frames = run(state, function(t) return {0, 0, 1}, math.rad(50), t > 2 end)
last = frames[#frames]
assert(math.abs(last.out.left.yaw - math.rad(50)) < 1e-9 and math.abs(last.out.right.yaw - math.rad(50)) < 1e-9, 'feet did not turn with the body')
assert(not last.out.left.swinging and not last.out.right.swinging)

-- A root that jumps (a respawn, a teleport) did not walk there: the feet
-- re-plant under it on that frame, no step is led by the jump, and the
-- velocity does not carry the jump into the next step.
state = Gait.new(rest)
run(state, function(t) return {0, 0, 1}, 0, t > 0.3 end)
frames = run(state, function(t) return {3, 0, 1}, 0, t > 1 end)
local first = frames[1]
assert(not first.out.left.swinging and not first.out.right.swinging, 'a jump was stepped rather than re-planted')
assert(dist(first.out.left.position, Gait.ideal({3, 0, 1}, 0, rest.left, 0, 1)) < 1e-9, 'feet not under the root after a jump')
for _, f in ipairs(frames) do
    assert(not f.out.left.swinging and not f.out.right.swinging, 'the jump leaked into a step at t=' .. f.t)
end
assert(state.velocity[1] == 0 and state.velocity[2] == 0, 'the jump was read as velocity')
-- Under the teleport distance a jump is a (large) step, capped at the reach.
state = Gait.new(rest)
run(state, function(t) return {0, 0, 1}, 0, t > 0.3 end)
frames = run(state, function(t) return {0.45, 0, 1}, 0, t > 1.5 end)
local longest = 0
for i = 2, #frames do
    for _, side in ipairs({'left', 'right'}) do
        if frames[i - 1].out[side].swinging and not frames[i].out[side].swinging then
            longest = math.max(longest, dist(frames[i].out[side].position, frames[i - 1].planted[side]))
        end
    end
end
assert(longest > 0 and longest <= Gait.MAX_STEP_M + 1e-6, 'a step longer than the cap, or none: ' .. longest)

-- Ground. Each foot is put down at the height the floor has where it
-- lands, and keeps it while planted; the swing carries the foot between
-- the heights it leaves and lands at; with no answer under a foot the
-- simulated floor is used. A slope, then a step.
local function slope(x, y) return 0.2 * x end
state = Gait.new(rest)
frames = run(state, function(t) return {0.8 * t, 0, 1}, 0, t > 3 end, nil, slope)
local on_slope, checked = true, 0
for i, f in ipairs(frames) do
    for _, side in ipairs({'left', 'right'}) do
        local foot = f.out[side]
        if not foot.swinging then
            checked = checked + 1
            if math.abs(foot.position[3] - slope(foot.position[1], foot.position[2])) > 1e-9 then on_slope = false end
        end
    end
end
assert(checked > 0 and on_slope, 'a planted foot left the slope')
assert(frames[1].out.left.position[3] == slope(frames[1].out.left.position[1], 0), 'the first plant ignored the ground')
-- The swing never dips below the lower of its two ends: the arc is on top
-- of the climb, not instead of it.
for i, f in ipairs(frames) do
    for _, side in ipairs({'left', 'right'}) do
        local foot = f.out[side]
        if foot.swinging then
            local sw = state.feet[side].swing
            local floor_from = slope(foot.position[1], 0) - 0.16 -- a step of 0.8 m at 0.2 rise is 0.16 m
            assert(foot.position[3] >= floor_from - 1e-9, side .. ' swung below the slope at frame ' .. i)
        end
    end
end
-- A 0.3 m step at x = 1: feet before it are on the floor, feet after it are
-- on the step, and a foot planted on the step stays there while the other
-- is still on the floor.
local function stepped_floor(x, y) return x > 1 and 0.3 or 0 end
state = Gait.new(rest)
frames = run(state, function(t) return {0.8 * t, 0, 1}, 0, t > 3 end, nil, stepped_floor)
local mixed = false
for _, f in ipairs(frames) do
    for _, side in ipairs({'left', 'right'}) do
        local foot = f.out[side]
        if not foot.swinging then
            assert(foot.position[3] == stepped_floor(foot.position[1], 0), side .. ' planted at the wrong height at x=' .. foot.position[1])
        end
    end
    -- One foot planted on the step while the other is still below it,
    -- planted on the floor or on its way up.
    for _, pair in ipairs({{'left', 'right'}, {'right', 'left'}}) do
        local up, other = f.out[pair[1]], f.out[pair[2]]
        if not up.swinging and up.position[3] == 0.3 and other.position[3] < 0.3 then mixed = true end
    end
end
assert(mixed, 'no frame had one foot on the step and one on the floor')
-- The planted records, since a foot may be mid-swing on the last frame.
assert(state.feet.left.planted[3] == 0.3 and state.feet.right.planted[3] == 0.3, 'both feet should end on the step')
-- No answer from the ground: the simulated floor.
state = Gait.new(rest)
frames = run(state, function(t) return {0.8 * t, 0, 1}, 0, t > 1 end, nil, function() return nil end)
for _, f in ipairs(frames) do
    if not f.out.left.swinging then assert(f.out.left.position[3] == 0, 'no ground answer should fall back to the floor') end
end

-- Bad input is refused rather than stepped on.
assert(Gait.update(state, nil, 0, 0, 1, DT, 1) == nil)
assert(Gait.update(state, {0 / 0, 0, 0}, 0, 0, 1, DT, 1) == nil)
assert(Gait.update(state, {0, 0, 0}, 0 / 0, 0, 1, DT, 1) == nil)

print('body_gait=pass standing small_step walk lead duration arc landing turn cap ground input')
