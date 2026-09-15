-- Tracked eye relative to the body anchor: a read after the anchor moved (the
-- locomotion post-update, before the camera stores this frame's eye) follows
-- the anchor; a read with the anchor unchanged returns the stored eye.
local file = assert(io.open(assert(arg[1]), 'rb')); local main = file:read('*a'); file:close()
local first = assert(main:find('presentation.TRACKED_EYE_MAX_AGE = 0.25', 1, true))
local tail = assert(main:find('return Unit.world_position(eye_unit, 1), Unit.world_rotation(eye_unit, 1)', first, true))
local last = assert(main:find('\nend', tail, true))

local vmeta = {}
local function V(x, y, z) return setmetatable({x, y, z}, vmeta) end
vmeta.__add = function(a, b) return V(a[1] + b[1], a[2] + b[2], a[3] + b[3]) end
vmeta.__sub = function(a, b) return V(a[1] - b[1], a[2] - b[2], a[3] - b[3]) end
vmeta.__mul = function(a, s) return V(a[1] * s, a[2] * s, a[3] * s) end
local Vector3 = setmetatable({dot = function(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end},
    {__call = function(_, x, y, z) return V(x, y, z) end})
-- Yaw-only quaternions: {yaw}.
local Quaternion = {
    from_elements = function(_, _, z, w) return {2 * math.atan2(z, w)} end,
    right = function(q) return V(math.cos(q[1]), math.sin(q[1]), 0) end,
    forward = function(q) return V(-math.sin(q[1]), math.cos(q[1]), 0) end,
    up = function() return V(0, 0, 1) end,
    multiply = function(a, b) return {a[1] + b[1]} end,
    inverse = function(q) return {-q[1]} end,
}
local function box(value) local held = value; return {store = function(_, v) held = v end, unbox = function() return held end} end
local time = 10
local observation = {}
local presentation = {rotate_vector = function(q, v)
    return Quaternion.right(q) * v[1] + Quaternion.forward(q) * v[2] + Quaternion.up(q) * v[3]
end}
local env = setmetatable({presentation = presentation, controller_observation = observation, Vector3 = Vector3,
    Quaternion = Quaternion, Vector3Box = box, QuaternionBox = box,
    Managers = {time = {time = function() return time end}}}, {__index = _G})
local chunk = assert(loadstring(main:sub(first, last + 3)))
setfenv(chunk, env); chunk()

local function set_anchor(x, y, z, yaw)
    observation.body_anchor_x, observation.body_anchor_y, observation.body_anchor_z = x, y, z
    observation.body_anchor_qx, observation.body_anchor_qy = 0, 0
    observation.body_anchor_qz, observation.body_anchor_qw = math.sin(yaw / 2), math.cos(yaw / 2)
end
local function near(a, b, m) assert(math.abs(a - b) < 1e-9, (m or 'mismatch') .. ': ' .. tostring(a)) end

-- Stored at the camera update with the anchor it wrote.
set_anchor(1, 2, 1.6, 0.3)
presentation.store_tracked_eye(V(1.1, 2.4, 1.7), {0.5})
local p, r = presentation.eye_pose(nil)
near(p[1], 1.1, 'unchanged anchor: stored eye'); near(p[2], 2.4); near(p[3], 1.7); near(r[1], 0.5)
-- A fixed step moved the player 8 cm sideways before the next post-update.
set_anchor(1.08, 2, 1.6, 0.3)
p, r = presentation.eye_pose(nil)
near(p[1], 1.18, 'the eye follows this frame\'s anchor'); near(p[2], 2.4); near(r[1], 0.5)
-- A snap turn about the anchor carries the eye round with it.
set_anchor(1, 2, 1.6, 0.3 + math.pi / 2)
p, r = presentation.eye_pose(nil)
near(p[1], 1 - 0.4, 'turned with the anchor'); near(p[2], 2 + 0.1); near(r[1], 0.5 + math.pi / 2)
-- Without an anchor the stored eye is returned as before.
for key in pairs(observation) do observation[key] = nil end
presentation.store_tracked_eye(V(3, 4, 5), {0})
p = presentation.eye_pose(nil)
near(p[1], 3, 'no anchor: stored eye'); near(p[3], 5)
set_anchor(9, 9, 9, 0)
p = presentation.eye_pose(nil)
near(p[1], 3, 'stored without an anchor stays world-fixed')
-- Stale: falls through to the first-person unit path (none here).
time = 20
assert(presentation.eye_pose(nil) == nil, 'stale eye not returned')
print('tracked_eye_anchor=pass unchanged step snap_turn no_anchor stale')
