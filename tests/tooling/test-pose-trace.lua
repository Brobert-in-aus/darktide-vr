-- Pose trace recorder: CSV header and rows, request-file gating, 30 Hz
-- sampling, buffered appends, and its wiring after the hand pose.
local Trace = dofile(assert(arg[1]))

-- Rows: every column in order; numbers fixed precision, integers plain,
-- booleans 1/0, missing and non-finite values empty, commas escaped.
assert(Trace.header():sub(1, 25) == "t,game_mode,state,crouch,")
local row = Trace.row({t = 12.5, game_mode = "shooting_range", state = "walking", crouch = false,
    root_x = 1, head_qw = 0.70710678, left_live = true, right_x = 0 / 0, floor_eye_height = 1.7})
local fields = {}
for value in (row .. ","):gmatch("([^,]*),") do fields[#fields + 1] = value end
assert(#fields == #Trace.COLUMNS, "column count " .. #fields)
local index = {}
for i, name in ipairs(Trace.COLUMNS) do index[name] = i end
assert(fields[index.t] == "12.50000" and fields[index.game_mode] == "shooting_range")
assert(fields[index.crouch] == "0" and fields[index.left_live] == "1")
assert(fields[index.root_x] == "1" and fields[index.head_qw] == "0.70711")
assert(fields[index.right_x] == "" and fields[index.vel_x] == "", "non-finite or missing not empty")
assert(Trace.row({state = "a,b"}):find("a_b", 1, true), "comma not escaped")

-- Live recorder with stubs.
local files = {}
Mods = {lua = {io = {open = function(path, mode)
    if mode == "r" then
        if not files[path] then return nil end
        return {read = function() return files[path] end, close = function() end}
    end
    files[path] = files[path] or ""
    return {write = function(_, ...) for _, s in ipairs({...}) do files[path] = files[path] .. s end end,
        close = function() end}
end}}}
ScriptUnit = {has_extension = function(unit, name)
    if name == "character_state_machine_system" then return {current_state_name = function() return "walking" end} end
    if name == "unit_data_system" then
        return {read_component = function() return {velocity_current = {x = 1, y = 0, z = 0}} end}
    end
end}
Unit = {world_position = function() return {x = 5, y = 6, z = 7} end}
Vector3 = {x = function(v) return v.x end, y = function(v) return v.y end, z = function(v) return v.z end}
bit = {band = function(a, b) return (math.floor(a / b) % 2) * b end}
local infos = {}
local mod = {info = function(_, f, ...) infos[#infos + 1] = string.format(f, ...) end}
local presentation = {current_game_mode_name = function() return "shooting_range" end,
    controller_bindings = {held = 64},
    head_pose_raw = function(out) for i = 1, 8 do out[i] = i / 10 end; return out end}
local observation = {body_visual_yaw = 1.5, right_grip_tracking_live = true, right_grip_x = 0.2}
local api = Trace.install(mod, presentation, observation)

-- No request file: nothing recorded.
for frame = 1, 120 do api.sample("player", frame / 60) end
assert(files[Trace.OUTPUT] == nil and api.rows == 0 and #infos == 0)
-- "record": starts at the next poll, samples at 30 Hz, appends every 30 rows.
files[Trace.FLAG] = "record\n"
for frame = 121, 300 do api.sample("player", frame / 60) end
assert(api.recording and infos[1]:find("recording=true", 1, true), infos[1])
-- 180 frames at 60 Hz is 3 s: about 90 rows at 30 Hz.
assert(api.rows >= 88 and api.rows <= 91, "rows " .. api.rows)
-- Stop: the remainder is flushed once, with a single header.
files[Trace.FLAG] = "stop"
for frame = 301, 420 do api.sample("player", frame / 60) end
assert(not api.recording and infos[#infos]:find("recording=false", 1, true))
local text = files[Trace.OUTPUT]
local lines = {}
for line in text:gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
assert(lines[1] == Trace.header(), "header missing")
assert(#lines == api.rows + 1, "rows lost in the flush: " .. #lines .. " vs " .. api.rows)
local first = {}
for value in (lines[2] .. ","):gmatch("([^,]*),") do first[#first + 1] = value end
assert(first[index.state] == "walking" and first[index.crouch] == "1" and first[index.root_z] == "7")
assert(first[index.vel_x] == "1" and first[index.head_qw] == "0.70000" and first[index.floor_eye_height] == "0.80000")
assert(first[index.right_live] == "1" and first[index.right_x] == "0.20000" and first[index.left_live] == "0")
assert(first[index.body_yaw] == "1.50000")

-- The clock restarting lower (a new level) resumes recording at once.
files[Trace.FLAG] = "record"
for frame = 421, 540 do api.sample("player", frame / 60) end
local before_reset = api.rows
for frame = 1, 30 do api.sample("player", frame / 60) end
assert(api.rows > before_reset + 10, "recording waited for the old clock")
-- A second launch appending to the same file writes no second header.
api.flush()
local again = Trace.install(mod, presentation, observation)
for frame = 1, 240 do again.sample("player", frame / 60) end
again.flush()
local headers = 0
for line in files[Trace.OUTPUT]:gmatch("([^\n]*)\n") do if line == Trace.header() then headers = headers + 1 end end
assert(headers == 1, "headers in the file: " .. headers)

-- Wired after the hand pose, flushed when a level unloads.
local file = assert(io.open(assert(arg[2]), "rb")); local main = file:read("*a"); file:close()
-- The draw pass times each display through the frame profiler, so the
-- anchor is the wrapped call; the ordering it checks is unchanged.
local ik = assert(main:find("presentation.frame_profile.section(\"draw.gun_aim\", presentation.gun_aim.update, self._world, player_unit)", 1, true))
local call = assert(main:find("presentation.pose_trace.sample(player_unit, t)", 1, true))
assert(call > ik)
local state = assert(main:find("mod.on_game_state_changed = function", 1, true))
assert(main:find("presentation.pose_trace.flush()", state, true))
print("pose_trace=pass columns rows gating 30hz buffered_flush single_header wiring")
