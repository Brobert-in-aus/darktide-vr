-- Gun sights zeroed on the reticle (todo item 4, 15 September).
--
-- The reticle marks where the aim ray hits. In the stock-input route that ray
-- starts at the head (the first-person camera, darktidevr_online_reticle) and
-- runs along the gun's aim, while the drawn gun sits at the tracked hand with
-- its iron sights 11.8 cm above the grip (galvanic rifle). The sights
-- therefore run parallel to the ray and miss the reticle by the head-to-sight
-- offset: with the gun held below and to the right of the eyes, the reticle
-- sits up and to the left of the sights (worn screenshot, 14 September),
-- about 1.5-2 degrees at 10 m for a 30 cm offset, more up close.
--
-- Presentation only, like zeroing a real rifle: the drawn gun is turned about
-- the grip by the small angle that puts its sight line through the reticle
-- point, whichever side the reticle is on. The aim that shoots and the
-- reticle are unchanged. The correction is eased, clamped to a maximum angle,
-- and skipped for very near points.
--
-- It applies only as the sights come to the dominant eye (full within
-- ZEROING_FULL_DISTANCE of the sight line, none past ZEROING_NONE_DISTANCE):
-- raising the gun swept the reticle point from the floor to the distance and
-- swung the gun by up to the cap on the way (worn, 15 September evening).
-- Away from the eye nobody sees the sight picture, so the gun simply follows
-- the hand there.
--
-- The sight line's offset from the grip is (eye - grip) in the muzzle frame
-- (x right, y forward, z up). Its direction is the stock ADS camera's forward
-- in the muzzle frame: authored sights need not be parallel to the muzzle
-- (worn, 15 September evening: the reticle stayed slightly up and left of
-- the sights through both eyes, a constant direction). The eye comes from the hidden first-person
-- rig's stock aim-down-sights pose, where the sights sit on the camera; the
-- grip comes from the placed third-person gun. Both are measured live, and a
-- shipped eye covers a weapon until it is aimed down the sights once.
local Sights = {}

-- Muzzle-frame x and z of the stock ADS eye, by weapon template.
-- Measured in artifacts/unattended/stray-bullet-20260915/sight2 and sight3.
Sights.SHIPPED_EYES = {
    galvanic_rifle_p1_m1 = {x = -0.008, z = 0.032},
}
Sights.ADS_SETTLE_SECONDS = 0.8
Sights.MAX_EYE_OFFSET = 0.15
Sights.MAX_GRIP_OFFSET = 0.25
Sights.MIN_POINT_DISTANCE = 0.75
Sights.MAX_CORRECTION_DEGREES = 5
Sights.EASE_SECONDS = 0.08
Sights.ZEROING_FULL_DISTANCE = 0.06
Sights.ZEROING_NONE_DISTANCE = 0.18
Sights.DOMINANT_EYE_OFFSET = 0.032

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function sub(a, b) return {a[1] - b[1], a[2] - b[2], a[3] - b[3]} end
local function mul(a, b)
    return {a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
        a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
        a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
        a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3]}
end
local function rotate(q, v)
    local r = mul(mul(q, {v[1], v[2], v[3], 0}), {-q[1], -q[2], -q[3], q[4]})
    return {r[1], r[2], r[3]}
end
local function normalize(v)
    local n = 0
    for i = 1, #v do n = n + v[i] * v[i] end
    if not finite(n) or n < 1e-12 then return nil end
    n = math.sqrt(n)
    local out = {}
    for i = 1, #v do out[i] = v[i] / n end
    return out
end
local function slerp(a, b, t)
    local d = a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
    if d < 0 then b = {-b[1], -b[2], -b[3], -b[4]}; d = -d end
    if d > 0.9995 then
        return normalize({a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t})
    end
    local theta = math.acos(d)
    local wa, wb = math.sin((1 - t) * theta) / math.sin(theta), math.sin(t * theta) / math.sin(theta)
    return normalize({wa * a[1] + wb * b[1], wa * a[2] + wb * b[2], wa * a[3] + wb * b[3], wa * a[4] + wb * b[4]})
end
Sights.slerp = slerp

-- Largest accepted angle between the sight line and the muzzle axis.
Sights.MAX_AXIS_DEGREES = 3

-- The sight line's offset from the grip in the muzzle frame, and its unit
-- direction (axis; the muzzle's forward when unmeasured), or nil. Pure.
function Sights.offset(eye, grip)
    if type(eye) ~= "table" or type(grip) ~= "table" or not finite(eye.x) or not finite(eye.z) or
        not finite(grip.x) or not finite(grip.z) then return nil end
    if math.abs(eye.x) > Sights.MAX_EYE_OFFSET or math.abs(eye.z) > Sights.MAX_EYE_OFFSET or
        math.abs(grip.x) > Sights.MAX_GRIP_OFFSET or math.abs(grip.z) > Sights.MAX_GRIP_OFFSET then return nil end
    return {x = eye.x - grip.x, z = eye.z - grip.z, axis = Sights.axis(eye.axis)}
end

-- A measured sight direction in the muzzle frame, or the muzzle's forward
-- when missing or implausible. Pure.
function Sights.axis(direction)
    local d = type(direction) == "table" and normalize({direction[1], direction[2], direction[3]})
    if not d or d[2] < math.cos(math.rad(Sights.MAX_AXIS_DEGREES)) then return {0, 1, 0} end
    return d
end

-- The world rotation q (drawn = q * aim, about the grip) that puts the sight
-- line through point, or nil when it does not apply. Arrays: grip and point
-- {x,y,z}, aim {x,y,z,w} with y forward and z up, offset {x=,z=}. Pure.
function Sights.zeroing(grip, aim, offset, point)
    aim = normalize(aim)
    if not aim or not offset or type(grip) ~= "table" or type(point) ~= "table" then return nil end
    for i = 1, 3 do if not finite(grip[i]) or not finite(point[i]) then return nil end end
    local lever = {offset.x, 0, offset.z}
    local axis = Sights.axis(offset.axis)
    local q = {0, 0, 0, 1}
    -- Turning the gun also moves its sight line a little; two passes settle it.
    for _ = 1, 2 do
        local drawn = mul(q, aim)
        local sight = rotate(drawn, lever)
        local from_sight = sub(point, {grip[1] + sight[1], grip[2] + sight[2], grip[3] + sight[3]})
        local distance = math.sqrt(dot(from_sight, from_sight))
        if not finite(distance) or distance < Sights.MIN_POINT_DISTANCE then return nil end
        local want = normalize(from_sight)
        local have = rotate(drawn, axis)
        local d = math.max(-1, math.min(1, dot(have, want)))
        local axis = {have[2] * want[3] - have[3] * want[2], have[3] * want[1] - have[1] * want[3],
            have[1] * want[2] - have[2] * want[1]}
        local step = normalize({axis[1], axis[2], axis[3], 1 + d})
        if not step then return nil end
        q = normalize(mul(step, q))
    end
    -- Past the cap the gun turns the capped amount toward the point, so the
    -- correction stays continuous as the point comes closer.
    local angle = math.deg(2 * math.acos(math.min(1, math.abs(q[4]))))
    if angle > Sights.MAX_CORRECTION_DEGREES then
        q = slerp({0, 0, 0, 1}, q, Sights.MAX_CORRECTION_DEGREES / angle)
    end
    return q
end

-- How far the eye is from the sight line (perpendicular) and how far behind
-- the sight it is along the aim. Arrays: grip, eye {x,y,z}; aim {x,y,z,w};
-- offset {x=,z=}. Pure.
function Sights.eye_distance(grip, aim, offset, eye)
    aim = normalize(aim)
    if not aim or not offset or type(grip) ~= "table" or type(eye) ~= "table" then return nil end
    local lever = rotate(aim, {offset.x, 0, offset.z})
    local forward = rotate(aim, Sights.axis(offset.axis))
    local to_eye = sub(eye, {grip[1] + lever[1], grip[2] + lever[2], grip[3] + lever[3]})
    local along = dot(to_eye, forward)
    local across = {to_eye[1] - forward[1] * along, to_eye[2] - forward[2] * along, to_eye[3] - forward[3] * along}
    local distance = math.sqrt(dot(across, across))
    if not finite(distance) or not finite(along) then return nil end
    return distance, -along
end

-- How much of the zeroing applies for an eye this far from the sight line and
-- this far behind the sight: 1 at the eye, easing to 0. Pure.
function Sights.zeroing_weight(distance, behind)
    if not finite(distance) or not finite(behind) or behind < 0 then return 0 end
    local span = Sights.ZEROING_NONE_DISTANCE - Sights.ZEROING_FULL_DISTANCE
    local x = math.max(0, math.min(1, (Sights.ZEROING_NONE_DISTANCE - distance) / span))
    return x * x * (3 - 2 * x)
end

function Sights.install(mod, presentation)
    local api = {eyes = {}, grips = {}, correction = {0, 0, 0, 1}}
    for name, eye in pairs(Sights.SHIPPED_EYES) do api.eyes[name] = {x = eye.x, z = eye.z, source = "shipped"} end
    local ads_since, failures, logged = nil, 0, {}

    local function log_failure(message)
        failures = failures + 1
        if failures == 1 then mod:info("DARKTIDEVR_GUN_SIGHTS failed=%s", tostring(message):sub(1, 160)) end
    end

    -- The sight line's offset from the grip for a template, or nil.
    function api.sight_offset(template_name)
        return Sights.offset(api.eyes[template_name], api.grips[template_name])
    end
    -- Gun aim: the drawn rotation for a gun about to be placed at grip.
    local function drawn(unit, template_name, grip, aim, dt)
        local offset = Sights.offset(api.eyes[template_name], api.grips[template_name])
        local aim_state = presentation.controller_aim
        local boxed = aim_state and aim_state.reticle_point_owner == unit and aim_state.reticle_world_point
        local target = {0, 0, 0, 1}
        if offset and boxed then
            local point = boxed:unbox()
            local ax, ay, az, aw = Quaternion.to_elements(aim)
            local grip_array = {Vector3.x(grip), Vector3.y(grip), Vector3.z(grip)}
            target = Sights.zeroing(grip_array, {ax, ay, az, aw}, offset,
                {Vector3.x(point), Vector3.y(point), Vector3.z(point)}) or target
            -- Only as the sights reach the dominant eye; without a known eye,
            -- the full correction as before.
            local eye, head
            if presentation.eye_pose then eye, head = presentation.eye_pose(unit) end
            if eye and head then
                local roles = presentation.weapon_hand_roles
                local side = roles and roles.physical("dominant") == "left" and -1 or 1
                eye = eye + Quaternion.right(head) * (Sights.DOMINANT_EYE_OFFSET * side)
                local distance, behind = Sights.eye_distance(grip_array, {ax, ay, az, aw}, offset,
                    {Vector3.x(eye), Vector3.y(eye), Vector3.z(eye)})
                target = slerp({0, 0, 0, 1}, target, Sights.zeroing_weight(distance, behind)) or {0, 0, 0, 1}
            end
        end
        local weight = (not finite(dt) or dt <= 0) and 1 or 1 - math.exp(-dt / Sights.EASE_SECONDS)
        api.correction = slerp(api.correction, target, weight) or {0, 0, 0, 1}
        if offset and not logged[template_name] then
            logged[template_name] = true
            mod:info("DARKTIDEVR_GUN_SIGHTS zeroing template=%s sight_above_grip_m=%.4f sight_right_of_grip_m=%.4f",
                template_name, offset.z, offset.x)
        end
        return Quaternion.multiply(Quaternion.from_elements(unpack(api.correction)), aim)
    end
    function api.drawn_rotation(unit, template_name, grip, aim, dt)
        local ok, result = pcall(drawn, unit, template_name, grip, aim, dt)
        if ok and result then return result end
        if not ok then log_failure(result) end
        return aim
    end

    -- Gun aim reports where the placed gun's muzzle is relative to the grip.
    function api.observe_grip(template_name, muzzle_pose, grip_position)
        local ok, message = pcall(function()
            local local_grip = Matrix4x4.transform(Matrix4x4.inverse(muzzle_pose), grip_position)
            local x, z = Vector3.x(local_grip), Vector3.z(local_grip)
            if not finite(x) or not finite(z) then return end
            if not api.grips[template_name] then
                mod:info("DARKTIDEVR_GUN_SIGHTS grip template=%s grip_in_muzzle=%.4f,%.4f", template_name, x, z)
            end
            api.grips[template_name] = {x = x, z = z}
        end)
        if not ok then log_failure(message) end
    end

    local function measure(unit, t)
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local alternate = unit_data and unit_data:read_component("alternate_fire")
        local weapon = ScriptUnit.has_extension(unit, "weapon_system")
        local template = weapon and weapon:weapon_template()
        if not template or not presentation.gun_aim or not presentation.gun_aim.is_gun(template) or
            not alternate or not alternate.is_active then ads_since = nil; return end
        ads_since = ads_since or t
        local eye = api.eyes[template.name]
        if t - ads_since < Sights.ADS_SETTLE_SECONDS or (eye and eye.source == "measured") then return end
        local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
        local inventory = unit_data:read_component("inventory")
        local muzzle_name = template.fx_sources and template.fx_sources._muzzle
        local first_person = ScriptUnit.has_extension(unit, "first_person_system")
        local camera = first_person and first_person:first_person_unit()
        if not loadout or not muzzle_name or not camera then return end
        local unit_1p, node_1p = loadout:unit_and_node_from_node_name(inventory.wielded_slot, muzzle_name)
        if not unit_1p or not node_1p then return end
        local muzzle_pose = Unit.world_pose(unit_1p, node_1p)
        local local_eye = Matrix4x4.transform(Matrix4x4.inverse(muzzle_pose), Unit.world_position(camera, 1))
        -- The stock ADS camera looks along the sight line.
        local muzzle_rotation = Unit.world_rotation(unit_1p, node_1p)
        local mx, my, mz, mw = Quaternion.to_elements(muzzle_rotation)
        local look = Quaternion.rotate(Quaternion.from_elements(-mx, -my, -mz, mw), Quaternion.forward(Unit.world_rotation(camera, 1)))
        local measured = {x = Vector3.x(local_eye), z = Vector3.z(local_eye), source = "measured",
            axis = {Vector3.x(look), Vector3.y(look), Vector3.z(look)}}
        if not Sights.offset(measured, {x = 0, z = 0}) then return end
        api.eyes[template.name] = measured
        local axis = Sights.axis(measured.axis)
        mod:info("DARKTIDEVR_GUN_SIGHTS eye template=%s eye_in_muzzle=%.4f,%.4f axis_right_deg=%.3f axis_up_deg=%.3f axis_used=%s previous=%s",
            template.name, measured.x, measured.z, math.deg(math.atan2(measured.axis[1], measured.axis[2])),
            math.deg(math.atan2(measured.axis[3], measured.axis[2])), tostring(axis[2] < 1),
            eye and string.format("%.4f,%.4f", eye.x, eye.z) or "none")
    end

    function api.update(unit, t)
        local ok, message = pcall(measure, unit, t)
        if not ok then log_failure(message) end
    end
    return api
end

return Sights
