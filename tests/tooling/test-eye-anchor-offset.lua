-- Animation audit item K: the one-time model-eye offset is measured in the
-- avatar's own aim yaw frame, not in the recenter basis, so the eye's forward
-- depth survives an avatar that faces across the basis. A cyclopean camera has
-- no lateral offset, and a pitched aim defers the capture.
local file = assert(io.open(arg[1], 'r'))
local source = file:read('*all'); file:close()
local first = assert(source:find('presentation.MAX_EYE_CAPTURE_PITCH = math.rad(15)', 1, true))
local last = assert(source:find('\nfunction presentation.body_camera_anchor(', first, true))

local function near(a, b, eps, label)
    assert(math.abs(a - b) < (eps or 1e-9), (label or 'mismatch') .. ': ' .. tostring(a) .. ' vs ' .. tostring(b))
end

-- Engine stubs: z up, +y forward, yaw about z. A rotation is {yaw, pitch}.
local function vec(x, y, z) return {x = x, y = y, z = z} end
Vector3 = setmetatable({
    x = function(v) return v.x end, y = function(v) return v.y end, z = function(v) return v.z end,
    up = function() return vec(0, 0, 1) end,
}, {__call = function(_, x, y, z) return vec(x, y, z) end})
Quaternion = {
    yaw = function(r) return r.yaw end,
    pitch = function(r) return r.pitch end,
    from_yaw_pitch_roll = function(y, p, _) return {yaw = y, pitch = p} end,
}

local presentation = {}
presentation.rotate_vector = function(rotation, v)
    -- Yaw only: these stubs never rotate about anything else.
    local c, s = math.cos(rotation.yaw), math.sin(rotation.yaw)
    return vec(c * v.x - s * v.y, s * v.x + c * v.y, v.z)
end
presentation.inverse_quaternion = function(r) return {yaw = -r.yaw, pitch = -r.pitch} end

local chunk = assert(loadstring(source:sub(first, last), 'eye_anchor_slice'))
setfenv(chunk, setmetatable({presentation = presentation}, {__index = _G}))()
assert(type(presentation.cyclopean_eye_offset) == 'function', 'the slice defines the offset helper')

-- The measured Psykhanium pose: the eye sits 8.52 cm forward of and 6 cm above
-- the first-person position. Facing along the basis, it reads as depth.
local DEPTH, HEIGHT = 0.0852, 0.06
local function offset_for(facing)
    local c, s = math.cos(facing), math.sin(facing)
    return vec(-s * DEPTH, c * DEPTH, HEIGHT)
end

for _, facing in ipairs({0, math.pi / 2, -math.pi / 2, math.pi, 2.3}) do
    local local_offset = assert(presentation.cyclopean_eye_offset({yaw = facing, pitch = 0}, offset_for(facing)),
        'measurable at any facing')
    near(Vector3.x(local_offset), 0, 1e-9, 'cyclopean: no lateral offset')
    near(Vector3.y(local_offset), DEPTH, 1e-9, 'depth survives the facing')
    near(Vector3.z(local_offset), HEIGHT, 1e-9, 'height survives the facing')
end

-- The old basis-relative measurement lost the depth at 90 degrees: it is the
-- component that landed on the basis' lateral axis and was zeroed there.
local across = offset_for(math.pi / 2)
near(math.abs(Vector3.x(across)), DEPTH, 1e-9, 'facing across the basis puts depth on lateral X')

-- A real lateral offset (one eye, or a rig leaning) is still removed.
local leaning = presentation.cyclopean_eye_offset({yaw = 0, pitch = 0}, vec(0.03, DEPTH, HEIGHT))
near(Vector3.x(leaning), 0, 1e-9, 'lateral always centred')
near(Vector3.y(leaning), DEPTH, 1e-9)

-- A pitched aim defers the capture rather than baking a look-down into the height.
local refused, reason = presentation.cyclopean_eye_offset({yaw = 0, pitch = math.rad(40)}, offset_for(0))
assert(refused == nil and reason == 'aim_pitched', 'looking down defers')
assert(presentation.cyclopean_eye_offset({yaw = 0, pitch = math.rad(-40)}, offset_for(0)) == nil, 'looking up defers')
assert(presentation.cyclopean_eye_offset({yaw = 0, pitch = math.rad(10)}, offset_for(0)) ~= nil, 'a small pitch is fine')
assert(select(2, presentation.cyclopean_eye_offset(nil, offset_for(0))) == 'aim_unavailable')
assert(select(2, presentation.cyclopean_eye_offset({yaw = 0, pitch = 0 / 0}, offset_for(0))) == 'aim_unavailable')

-- A capture deferred too long takes whatever pitch it can get: the fallback
-- origin is about 8.5 cm behind the real one, and the jump when the player
-- finally looks up is a world translation, which is visible in a headset.
local late = presentation.cyclopean_eye_offset({yaw = 0, pitch = math.rad(40)}, offset_for(0), true)
assert(late ~= nil, 'past the deadline the pitch gate is waived')
near(Vector3.x(late), 0, 1e-9, 'still cyclopean when waived')
assert(presentation.EYE_CAPTURE_DEADLINE > 0 and presentation.EYE_CAPTURE_DEADLINE <= 5,
    'a couple of seconds, not a minute')
-- Waiving the pitch gate does not waive the checks that mean "no usable aim".
assert(presentation.cyclopean_eye_offset(nil, offset_for(0), true) == nil)
assert(presentation.cyclopean_eye_offset({yaw = 0, pitch = 0 / 0}, offset_for(0), true) == nil)

print('eye_anchor_offset=pass aim_frame cyclopean pitch_defers deadline')
