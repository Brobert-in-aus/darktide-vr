local Diagnostics, Simulation, Planner = dofile(arg[1]), dofile(arg[2]), dofile(arg[3])
Vector3 = function(...) return {...} end
Quaternion = {from_elements=function(...) return {...} end}
local calls, fail = 0, false
local probe = {overlap=function()
    calls = calls + 1
    if fail then error("injected physics failure") end
    return {actors={},actor_count=0,capacity_verified=false}
end, contact_scan=function()
    calls = calls + 1
    return {contacts={{actor="stationary_contact"}},saturated=false}
end, sweep=function(_,_,a,b,rotation)
    calls = calls + 1
    assert(a[1] == 0 and b[1] == 0) -- Tip-only turn, stationary hilt.
    local norm = 0
    for i=1,4 do norm = norm + rotation[i]*rotation[i] end
    assert(math.abs(norm-1) < 1e-12)
    return {contacts={{actor={}}},saturated=true}
end}
local state = Diagnostics.new(Simulation,Planner,probe)
local key = {}
local request = {history_key=key, world={},filter="fixture",rewind_ms=0,max_hits=20,
    volume={shape="oobb",corner_radius=2},
    limits={max_gap=.1,max_translation=1,arc_step=.2,max_segments=64}}
local function sample(frame,time,angle,tracking,resimulating)
    request.step = {frame=frame,time=time,tracking_valid=tracking,resimulating=resimulating}
    request.pose = {position={0,0,0},rotation={0,0,math.sin(angle/2),math.cos(angle/2)}}
    return Diagnostics.sample(state,request)
end
local first = assert(sample(0,0,0,true,false))
assert(first.query_count == 2 and first.plan.reason == "fresh_pose")
assert(first.contacts[1].actor == "stationary_contact")
local turn = assert(sample(1,.02,math.pi/2,true,false))
assert(turn.plan.segments > 1 and turn.query_count == 2+2*turn.plan.segments)
assert(#turn.contacts == 1+2*turn.plan.segments and turn.saturated)
local before = calls
assert(not sample(1,.02,math.pi/2,true,false) and calls == before)
assert(not sample(2,.04,math.pi/2,true,true) and calls == before)
assert(not sample(2,.04,math.pi/2,false,false) and calls == before)
local recovered = assert(sample(3,.06,math.pi/2,true,false))
assert(recovered.query_count == 2)
request.history_key = {}
assert(sample(4,.08,math.pi/2,true,false).query_count == 2)
assert(sample(5,1,math.pi/2,true,false).plan.reason == "discontinuity")
fail = true
local failed, reason = sample(6,1.02,math.pi/2,true,false)
assert(not failed and reason == "query_error" and state.previous == nil)
before = calls
assert(not sample(6,1.02,math.pi/2,true,false) and calls == before)
fail = false
assert(sample(7,1.04,math.pi/2,true,false).query_count == 2)
before = calls
assert(not sample(8,1.06,0,true,true) and calls == before)
local after_correction = assert(sample(8,1.06,0,true,false))
assert(after_correction.plan.reason == "fresh_pose" and after_correction.query_count == 2,
    "Correction replay retained a trajectory across the simulation pose change")
before = calls
assert(not sample(8,1.06,0,true,false) and calls == before,
    "Correction recovery reset the already claimed simulation tick")
print("non-damaging melee query orchestration, arc sampling and history recovery passed")
