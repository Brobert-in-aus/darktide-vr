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
ui_native_capture = {dtvr_commit_gameplay_generation = function() return 0 end}
mod = {info = function() end}
head_pose_last_sequence = 1
assert(loadstring(source:sub(first, last - 1)))()
local owner = {_orientation = {yaw = math.pi / 2, pitch = 0, roll = 0}}
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
print("gameplay_heading=pass")
