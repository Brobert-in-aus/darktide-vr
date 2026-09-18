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
-- The fallback builds a position with + and *, so the stub vectors need them.
local vec_meta = {}
local function vec(x, y, z) return setmetatable({x = x, y = y, z = z}, vec_meta) end
vec_meta.__add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
vec_meta.__mul = function(a, k)
    if type(a) == 'number' then a, k = k, a end
    return vec(a.x * k, a.y * k, a.z * k)
end
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

-- The worn correction (user, 18 September): the measured anchor reads as 5 cm
-- too low and 5 cm too far back, so the correction is added to the capture.
-- Forward is +y and up is +z in this frame, so a sign slip here would push the
-- eyes further into the head rather than out of it.
--
-- Asserted against the CONSTANTS, not against 0.05. The next worn answer sizes
-- this again, and a test that pins today's centimetres turns every later
-- adjustment into an argument with the harness. What must not move is the
-- wiring, the axis each constant lands on, and the sign; the number itself
-- lives in the constant's own comment and in the day's document.
assert(type(presentation.eye_anchor_correction) == 'function', 'the slice defines the correction')
local FORWARD = presentation.EYE_ANCHOR_FORWARD_M
local UP = presentation.EYE_ANCHOR_UP_M
assert(FORWARD > 0 and FORWARD < 0.5, 'a plausible correction in metres, not centimetres or a typo')
assert(UP > 0 and UP < 0.5, 'a plausible correction in metres, not centimetres or a typo')
local corrected = assert(presentation.eye_anchor_correction(vec(0, DEPTH, HEIGHT)))
near(Vector3.x(corrected), 0, 1e-9, 'the correction is not lateral')
near(Vector3.y(corrected), DEPTH + FORWARD, 1e-9, 'forward by the forward constant')
near(Vector3.z(corrected), HEIGHT + UP, 1e-9, 'up by the up constant')
assert(Vector3.y(corrected) > DEPTH, 'forward, not back')
assert(Vector3.z(corrected) > HEIGHT, 'up, not down')
assert(presentation.eye_anchor_correction(nil) == nil, 'no capture, no correction')

-- Which constant lands on which axis cannot be measured while the two are
-- equal: swapping them is arithmetically invisible today and wrong the moment
-- one of them is re-sized on its own. So the pairing is held on the source.
local correction_body = source:sub(
    (assert(source:find('function presentation.eye_anchor_correction(', 1, true))))
correction_body = correction_body:sub(1, (assert(correction_body:find('\nend', 1, true))))
-- Patterns, not exact text: what must hold is that the forward constant is
-- added to a y term and the up constant to a z term. [^,\n] keeps the match
-- inside one argument, so a swap cannot reach across the comma to the term
-- above it and read as correct.
assert(correction_body:find('y[^,\n]-%+%s*presentation%.EYE_ANCHOR_FORWARD_M'),
    'forward is added to y')
assert(correction_body:find('z[^,\n]-%+%s*presentation%.EYE_ANCHOR_UP_M'),
    'up is added to z')

-- It must not be folded into the stored capture: applying it to its own result
-- doubles it, which is what a correction written into the stored offset would
-- do on every later read.
local twice = presentation.eye_anchor_correction(corrected)
near(Vector3.y(twice), DEPTH + 2 * presentation.EYE_ANCHOR_FORWARD_M, 1e-9,
    'applying twice doubles, so it is applied once')

-- A correction that is written but never called is the failure this whole
-- change is most likely to ship as, and no amount of testing the helper in
-- isolation would see it. The anchor's own return must read the capture
-- through it. Checked on the source because body_camera_anchor needs the
-- engine, which this slice deliberately does not have.
-- find returns TWO values; each of these takes only the first, or sub() reads
-- the match's end as its own end and slices away everything being checked.
local function slice(text, from, to)
    local start = assert(text:find(from, 1, true), 'missing: ' .. from)
    local stop = assert(text:find(to, start, true), 'missing: ' .. to)
    return text:sub(start, stop)
end
--
-- Sliced from the RETURN BACKWARDS, not from the function forwards. A review
-- on 18 September got three mutations past the forward-slicing version: a
-- correction applied one line above the slice's start, a dead
-- `local _unused = eye_anchor_correction(...)` next to an uncorrected return,
-- and an assertion on `body_camera_eye_offset_x` that held whatever the return
-- read, because that name also appears twice earlier in the same slice. All
-- three are the same mistake -- checking that the correction appears SOMEWHERE
-- rather than that it is what the anchor returns.
local anchor_body = slice(source, '\nfunction presentation.body_camera_anchor(',
    'stable_first_person_cyclopean_offset')
-- The LAST assignment to local_offset before the return: anything earlier is
-- not what the return reads.
local last_assignment
local search = 1
while true do
    local at = anchor_body:find('local local_offset = ', search, true)
    if not at then break end
    last_assignment, search = at, at + 1
end
assert(last_assignment, 'the anchor assigns the offset it returns')
local return_statement = anchor_body:sub(last_assignment)
assert(return_statement:find('presentation.eye_anchor_correction(', 1, true),
    'the offset the anchor returns is the corrected one')
assert(return_statement:find('body_camera_eye_offset_x', 1, true),
    'and the correction is applied to the stored capture')
assert(return_statement:find('head_position %+ presentation%.rotate_vector%(basis, local_offset%)'),
    'and that offset is what the returned position is built from')
-- The stored capture stays raw: correcting it anywhere in the capture block
-- would add the offset once when it is written and again on every read.
-- The slice starts at the MEASUREMENT, not at the store, because a fold-in
-- placed between the two is still a fold-in.
local store = slice(source, 'local local_offset, refused = presentation.cyclopean_eye_offset(',
    'DARKTIDEVR_ANCHOR eye_capture')
assert(not store:find('eye_anchor_correction', 1, true), 'the stored capture is the raw measurement')
-- By name or by constant: either way it is the correction.
assert(not store:find('EYE_ANCHOR_FORWARD_M', 1, true), 'nor is the forward constant folded in')
assert(not store:find('EYE_ANCHOR_UP_M', 1, true), 'nor the up constant')

-- The fallback carries the correction as well. Correcting only the captured
-- path grows the jump between them from 8.6 cm to 14.8 cm, and bounding that
-- jump is the entire reason EYE_CAPTURE_DEADLINE exists (review, 18 Sept).
assert(type(presentation.eye_anchor_fallback) == 'function', 'the slice defines the fallback')
local fallback_body = slice(source, 'function presentation.eye_anchor_fallback(', '\nend')
assert(fallback_body:find('presentation.eye_anchor_correction(', 1, true),
    'the fallback is corrected too')
assert(not source:find('head_position + Vector3.up() * 0.05', 1, true),
    'no uncorrected 5 cm fallback survives anywhere')
-- Run it, rather than spot the call: a fallback that computes the correction
-- and then returns something else passes any search for the name.
local guessed = presentation.eye_anchor_fallback(vec(0, 0, 0), {yaw = 0, pitch = 0})
near(Vector3.y(guessed), FORWARD, 1e-9, 'the fallback carries the forward correction')
near(Vector3.z(guessed), presentation.EYE_ANCHOR_FALLBACK_UP_M + UP, 1e-9,
    'and the up correction on top of its own guess')
near(Vector3.x(guessed), 0, 1e-9, 'and is not lateral either')
-- Without a basis there is no forward to apply, but the height still applies.
local flat = presentation.eye_anchor_fallback(vec(0, 0, 0), nil)
near(Vector3.z(flat), presentation.EYE_ANCHOR_FALLBACK_UP_M + UP, 1e-9,
    'the basis-less fallback still rises by the correction')
assert(presentation.eye_anchor_fallback(nil, nil) == nil, 'no head position, no guess')

-- The deadline's timer has to be cleared when the capture lands, and at every
-- reset that can cause a SECOND capture. Left set, the next capture is overdue
-- on its first frame, waives MAX_EYE_CAPTURE_PITCH, and bakes whatever pitch
-- the player happened to be holding into the height -- which is the same fault
-- this correction exists to fix, arriving by another door (review, 18 Sept).
assert(store:find('body_camera_eye_offset_since = nil', 1, true),
    'a successful capture clears the wait it started')
-- Every site that clears the capture clears its timer. Walked by POSITION,
-- not by matched text: the two reset sites are character for character
-- identical, so searching the file for each line's text finds the first one
-- twice and never looks at the second. That is how the calibration reset --
-- the likeliest cause of a second capture there is -- got past the first cut.
local reset_marker = 'controller_observation.body_camera_eye_offset_unit = nil'
local sites, at = 0, 1
while true do
    local found = source:find(reset_marker, at, true)
    if not found then break end
    sites = sites + 1
    local window = source:sub(found, found + 700)
    assert(window:find('body_camera_eye_offset_since = nil', 1, true),
        'the reset at character ' .. found .. ' leaves the capture timer behind')
    at = found + #reset_marker
end
assert(sites >= 2, 'both reset sites are checked, found ' .. sites)

print('eye_anchor_offset=pass aim_frame cyclopean pitch_defers deadline worn_correction wired timer')
