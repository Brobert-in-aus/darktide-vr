local Plan = dofile(arg[1])
local limits = {max_gap=.1, max_translation=1, arc_step=.1, max_segments=64}
local sample = {current_valid=true, previous_valid=true, dt=1/60,
    translation=0, angle=0, radius=2.3}
local function check(overlap, segments, reason)
    local result = Plan.make(sample, limits)
    assert(result.overlap == overlap and result.segments == segments and result.reason == reason,
        "unexpected sweep plan: " .. result.reason .. "/" .. result.segments)
    return result
end
check(true, 1, "continuous") -- stationary contact still queries physics
sample.angle = math.pi/2
local turn = Plan.make(sample, limits)
assert(turn.segments > 1 and turn.overlap and not turn.reset)
assert(sample.radius * sample.angle / turn.segments <= limits.arc_step)
-- A long blade turning around a stationary hilt must receive extra samples.
local short = Plan.make({current_valid=true, previous_valid=true, dt=1/60,
    translation=0, angle=math.pi/2, radius=.3}, limits)
assert(turn.segments > short.segments)
sample.angle = 0
sample.translation = .9
check(true, 1, "continuous") -- linear sweep handles fast translation
sample.translation = 1.01
check(true, 0, "discontinuity")
sample.translation = 0
sample.dt = .11
check(true, 0, "discontinuity")
sample.dt = 0
check(false, 0, "invalid_time")
sample.dt = -1
check(false, 0, "invalid_time")
sample.dt = 1/60
sample.discontinuity = true
check(true, 0, "fresh_pose") -- recenter cannot sweep across the room
sample.discontinuity = false
sample.previous_valid = false
check(true, 0, "fresh_pose")
sample.current_valid = false
check(false, 0, "invalid_tracking")
sample.current_valid, sample.previous_valid = true, true
sample.angle = math.pi
check(true, 0, "query_budget") -- no silent undersampling
sample.angle = 0/0
check(true, 0, "invalid_history")
sample.angle = 4
check(true, 0, "invalid_history")
sample.angle = 0
sample.radius = math.huge
check(true, 0, "invalid_history")
limits.max_segments = 1.5
assert(not pcall(Plan.make, sample, limits))
print("stationary overlap, rotational sampling, discontinuity and bounded query planning passed")
