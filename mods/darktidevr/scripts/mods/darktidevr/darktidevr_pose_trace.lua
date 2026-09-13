-- Pose trace recorder for the whole-body IK solver's offline tests (design:
-- docs/phase1/whole-body-ik-design-2026-09-14.md). While the request file
-- darktidevr_pose_trace.flag contains "record", every 1/30 s of gameplay
-- appends one CSV row to darktidevr_pose_trace.csv beside it. Players never
-- have the file.
--
-- Columns and frames:
--   head_*       the viewer's shared head pose, unconverted OpenXR local space
--                (y up), plus floor_eye_height (metres);
--   left_*/right_* the controller grip poses in the mod's body basis (z up,
--                relative to the recentered head), and their tracking;
--   root_*, vel_* the gameplay avatar's root position and velocity (world,
--                z up); body_yaw the body presentation's yaw (radians);
--   state, crouch the character state machine and the crouch input.
local Trace = {}

Trace.FLAG = "./../mods/darktidevr/darktidevr_pose_trace.flag"
Trace.OUTPUT = "./../mods/darktidevr/darktidevr_pose_trace.csv"
Trace.INTERVAL = 1 / 30
Trace.FLUSH_ROWS = 30
Trace.COLUMNS = {
    "t", "game_mode", "state", "crouch",
    "root_x", "root_y", "root_z", "vel_x", "vel_y", "vel_z", "body_yaw",
    "head_x", "head_y", "head_z", "head_qx", "head_qy", "head_qz", "head_qw", "floor_eye_height",
    "left_live", "left_x", "left_y", "left_z", "left_qx", "left_qy", "left_qz", "left_qw",
    "right_live", "right_x", "right_y", "right_z", "right_qx", "right_qy", "right_qz", "right_qw",
}

local function field(value)
    if value == nil then return "" end
    if type(value) == "boolean" then return value and "1" or "0" end
    if type(value) == "number" then
        if value ~= value or math.abs(value) == math.huge then return "" end
        if value == math.floor(value) and math.abs(value) < 1e9 then return string.format("%d", value) end
        return string.format("%.5f", value)
    end
    return (tostring(value):gsub("[,\r\n]", "_"))
end

function Trace.header()
    return table.concat(Trace.COLUMNS, ",")
end

-- One CSV row from a sample table keyed by column name.
function Trace.row(sample)
    local fields = {}
    for i, name in ipairs(Trace.COLUMNS) do fields[i] = field(sample[name]) end
    return table.concat(fields, ",")
end

function Trace.install(mod, presentation, observation)
    local api = {rows = 0, recording = false}
    local buffer, next_t, poll, header_written = {}, nil, 0, false
    local head = {}
    local function files() return Mods and Mods.lua and Mods.lua.io end
    local function flush()
        if #buffer == 0 then return end
        local io_api = files()
        local file = io_api and io_api.open(Trace.OUTPUT, "a")
        if not file then buffer = {}; return end
        if not header_written then
            file:write(Trace.header(), "\n")
            header_written = true
        end
        file:write(table.concat(buffer, "\n"), "\n")
        file:close()
        buffer = {}
    end
    local function requested()
        poll = poll - 1
        if poll > 0 then return api.recording end
        poll = 60
        local io_api = files()
        local file = io_api and io_api.open(Trace.FLAG, "r")
        local value = file and file:read("*all")
        if file then file:close() end
        return type(value) == "string" and value:match("^%s*record%s*$") ~= nil
    end
    local function sample(unit, t)
        local s = {t = t, game_mode = presentation.current_game_mode_name and presentation.current_game_mode_name()}
        local machine = ScriptUnit.has_extension(unit, "character_state_machine_system")
        s.state = machine and machine:current_state_name()
        local bindings = presentation.controller_bindings
        s.crouch = bindings and type(bindings.held) == "number" and bit.band(bindings.held, 64) ~= 0
        local root = Unit.world_position(unit, 1)
        s.root_x, s.root_y, s.root_z = Vector3.x(root), Vector3.y(root), Vector3.z(root)
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local locomotion = unit_data and unit_data:read_component("locomotion")
        local velocity = locomotion and locomotion.velocity_current
        if velocity then s.vel_x, s.vel_y, s.vel_z = Vector3.x(velocity), Vector3.y(velocity), Vector3.z(velocity) end
        s.body_yaw = observation.body_visual_yaw
        if presentation.head_pose_raw and presentation.head_pose_raw(head) then
            s.head_x, s.head_y, s.head_z = head[1], head[2], head[3]
            s.head_qx, s.head_qy, s.head_qz, s.head_qw = head[4], head[5], head[6], head[7]
            s.floor_eye_height = head[8]
        end
        for _, side in ipairs({"left", "right"}) do
            s[side .. "_live"] = observation[side .. "_grip_tracking_live"] == true
            for _, axis in ipairs({"x", "y", "z", "qx", "qy", "qz", "qw"}) do
                s[side .. "_" .. axis] = observation[side .. "_grip_" .. axis]
            end
        end
        return s
    end
    function api.sample(unit, t)
        local ok, err = pcall(function()
            local want = requested()
            if want ~= api.recording then
                if not want then flush() end
                api.recording = want
                mod:info("DARKTIDEVR_POSE_TRACE recording=%s rows=%d output=%s", tostring(want), api.rows, Trace.OUTPUT)
            end
            if not api.recording or not unit or type(t) ~= "number" then return end
            if next_t and t < next_t then return end
            next_t = t + Trace.INTERVAL
            buffer[#buffer + 1] = Trace.row(sample(unit, t))
            api.rows = api.rows + 1
            if #buffer >= Trace.FLUSH_ROWS then flush() end
        end)
        if not ok and not api.failure_logged then
            api.failure_logged = true
            mod:info("DARKTIDEVR_POSE_TRACE error=%s", tostring(err):sub(1, 160))
        end
    end
    function api.flush() pcall(flush) end
    return api
end

return Trace
