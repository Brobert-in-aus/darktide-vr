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
local first = {position={0,0,0},rotation={0,0,0,2}}
local last = {position={1,0,0},rotation={0,0,math.sin(math.pi/4),math.cos(math.pi/4)}}
local trajectory = assert(Plan.trajectory(first,last))
assert(math.abs(trajectory.angle-math.pi/2) < 1e-12 and trajectory.translation == 1)
first.position[1], last.rotation[4] = 100, 0 -- Snapshots must not follow reused inputs.
local middle = Plan.pose_at(trajectory,.5)
assert(middle.position[1] == .5 and math.abs(middle.rotation[3]-math.sin(math.pi/8)) < 1e-12)
-- A long blade's tip follows the sampled arc even with a stationary hilt.
trajectory = assert(Plan.trajectory({position={0,0,0},rotation={0,0,0,1}},
    {position={0,0,0},rotation={0,0,1,0}}))
local previous_tip
for i=0,32 do
    local pose = Plan.pose_at(trajectory,i/32)
    local z,w = pose.rotation[3],pose.rotation[4]
    local tip = {2*(1-2*z*z), 4*z*w}
    if previous_tip then
        local dx,dy = tip[1]-previous_tip[1],tip[2]-previous_tip[2]
        assert(math.sqrt(dx*dx+dy*dy) <= 2*trajectory.angle/32 + 1e-12)
    end
    previous_tip = tip
end
local equivalent = assert(Plan.trajectory({position={0,0,0},rotation={0,0,0,1}},
    {position={0,0,0},rotation={0,0,0,-1}}))
assert(equivalent.angle == 0 and Plan.pose_at(equivalent,.5).rotation[4] == 1)
assert(not Plan.trajectory({position={0,0,0},rotation={0,0,0,0}},last))
assert(not Plan.pose_at(equivalent,1.01))
print("stationary overlap, rotational sampling, discontinuity and bounded query planning passed")
