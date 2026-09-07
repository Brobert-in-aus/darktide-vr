-- Exercise the real orientation seam independently of the game runtime.
local file = assert(io.open(arg[1], "r"))
local source = file:read("*all")
file:close()
local first = assert(source:find("function presentation.observe_controller_aim", 1, true))
local last = assert(source:find("\nmod:hook_safe(", first, true))
presentation = {mode = 1, sequence = 1, current_game_mode_name = function() return "hub" end}
controller_observation = {
    authoring_last_check_t = 0, authoring_enabled = true,
    head_aim_yaw = 0, head_aim_pitch = 0, physical_head_yaw = 0,
    first_person_seam_last_sequence = -1, authoring_writes = 0,
    first_person_seam_last_log_t = 0
}
local commits,commit_result = {},0
local owner
ui_native_capture = {dtvr_commit_gameplay_generation = function(generation)
    assert(presentation.mode == 1, "committed gameplay while loading/menu camera owns presentation")
    assert(math.abs(owner._orientation.yaw-controller_observation.head_aim_yaw%(2*math.pi))<1e-6,
        "generation committed before authoritative heading was restored")
    commits[#commits+1] = generation
    return commit_result
end}
mod = {info = function() end}
head_pose_last_sequence = 1
assert(loadstring(source:sub(first, last - 1)))()
owner = {_orientation = {yaw = math.pi / 2, pitch = 0, roll = 0}}
local function observe(yaw)
    controller_observation.head_aim_yaw = yaw
    head_pose_last_sequence = head_pose_last_sequence + 1
    presentation.observe_controller_aim(owner, 0.1, "fixture")
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " != " .. expected)
end
observe(0)
near(owner._orientation.yaw, 0) -- Discard 90-degree spawn mismatch immediately.
observe(-math.pi / 2)
near(owner._orientation.yaw, math.pi * 1.5)
observe(0.3)
near(owner._orientation.yaw, 0.3) -- Consecutive samples must not be throttled.
owner = {_orientation = {yaw = 2.5, pitch = 0, roll = 0}}
observe(0.3)
near(owner._orientation.yaw, 0.3) -- A new map/owner must not seed a new offset.
presentation.mode = 5
owner._orientation.yaw = 1.7
observe(0.8)
near(owner._orientation.yaw, 1.7) -- Leave the modal camera alone.
near(controller_observation.gameplay_yaw, 0.8)
presentation.mode = 1
observe(0.9)
near(owner._orientation.yaw, 0.9) -- Modal exit follows the XR scene anchor.
local before_loading = #commits
presentation.mode,presentation.sequence = 2,40
owner = {_orientation={yaw=2.1,pitch=.2,roll=0}}
observe(.4)
observe(.5)
assert(#commits==before_loading and controller_observation.gameplay_generation_pending,
    "owner created during loading lost the deferred gameplay generation")
presentation.mode,presentation.sequence = 1,45
observe(.6)
assert(#commits==before_loading+1 and commits[#commits]==45 and
    not controller_observation.gameplay_generation_pending)
observe(.7)
assert(#commits==before_loading+1,"ordinary gameplay repeatedly committed generations")
-- Same-owner loading paths also need a resume generation. A transient native
-- failure must retain the pending commit, with no arbitrary timeout bypass.
presentation.mode,presentation.sequence = 2,50
observe(.8)
presentation.mode,presentation.sequence = 1,55
commit_result=-1
observe(.9)
assert(controller_observation.gameplay_generation_pending)
commit_result=0
observe(1)
assert(commits[#commits]==55 and not controller_observation.gameplay_generation_pending)
print("gameplay_heading=pass")

-- Run the actual locomotion log with engine-style userdata vectors. The
-- reference direction must not shadow the numeric forward input cache value.
local log_first=assert(source:find('                        local movement_rotation, movement_reference =',1,true))
local log_end=assert(source:find('Vector3.z(player_position))',log_first,true))+#'Vector3.z(player_position))'-1
local vector=newproxy(true)
local logged
local environment={
    presentation={movement_reference_rotation=function() return {},'head' end},
    controller_observation={left_stick_x=0,left_stick_y=.6,right_stick_x=0,right_stick_y=0},
    Quaternion={forward=function() return vector end,yaw=function() return 0 end},
    Vector3={zero=function() return vector end,x=function() return 0 end,
        y=function() return 1 end,z=function() return 0 end},
    mod={info=function(_,format,...) logged=string.format(format,...) end},
    frame=60,state_name='walking',move_x=0,move_y=.6,existing_x=0,existing_y=0,
    combined_x=0,combined_y=.6,stick_active=true,movement_right=0,movement_left=0,
    movement_forward=.6,movement_backward=0,player_position=vector,
}
setmetatable(environment,{__index=_G})
local log_chunk=assert(loadstring(source:sub(log_first,log_end)))
setfenv(log_chunk,environment); log_chunk()
assert(logged:find('cache=0.000,0.000,0.600,0.000',1,true),logged)
print('locomotion_log=pass vector_reference numeric_input_cache')
