-- Gun sights zeroed on the reticle (todo item 4, 15 September).
--
-- The reticle marks where the aim ray hits. The drawn gun is held at the
-- tracked grip with its bore along that aim, so its iron sights, which sit
-- above the bore, run parallel to the ray instead of through the reticle.
-- On the galvanic rifle the sight line is 11.8 cm above the grip. Looking
-- through the sights, the reticle sat below them: 0.66 degrees at 10 m, more
-- up close.
--
-- Presentation only, like zeroing a real rifle: the drawn gun is turned about
-- the grip by the small angle that puts its sight line through the reticle
-- point. The aim that shoots and the reticle are unchanged. The correction is
-- capped, eased, and skipped for very near points.
--
-- The sight line's offset from the grip is (eye - grip) in the muzzle frame
-- (x right, y forward, z up). The eye comes from the hidden first-person
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

-- The sight line's offset from the grip in the muzzle frame, or nil. Pure.
function Sights.offset(eye, grip)
    if type(eye) ~= "table" or type(grip) ~= "table" or not finite(eye.x) or not finite(eye.z) or
        not finite(grip.x) or not finite(grip.z) then return nil end
    if math.abs(eye.x) > Sights.MAX_EYE_OFFSET or math.abs(eye.z) > Sights.MAX_EYE_OFFSET or
        math.abs(grip.x) > Sights.MAX_GRIP_OFFSET or math.abs(grip.z) > Sights.MAX_GRIP_OFFSET then return nil end
    return {x = eye.x - grip.x, z = eye.z - grip.z}
end

-- The world rotation q (drawn = q * aim, about the grip) that puts the sight
-- line through point, or nil when it does not apply. Arrays: grip and point
-- {x,y,z}, aim {x,y,z,w} with y forward and z up, offset {x=,z=}. Pure.
function Sights.zeroing(grip, aim, offset, point)
    aim = normalize(aim)
    if not aim or not offset or type(grip) ~= "table" or type(point) ~= "table" then return nil end
    for i = 1, 3 do if not finite(grip[i]) or not finite(point[i]) then return nil end end
    local lever = {offset.x, 0, offset.z}
    local q = {0, 0, 0, 1}
    -- Turning the gun also moves its sight line a little; two passes settle it.
    for _ = 1, 2 do
        local drawn = mul(q, aim)
        local sight = rotate(drawn, lever)
        local from_sight = sub(point, {grip[1] + sight[1], grip[2] + sight[2], grip[3] + sight[3]})
        local distance = math.sqrt(dot(from_sight, from_sight))
        if not finite(distance) or distance < Sights.MIN_POINT_DISTANCE then return nil end
        local want = normalize(from_sight)
        local have = rotate(drawn, {0, 1, 0})
        local d = math.max(-1, math.min(1, dot(have, want)))
        local axis = {have[2] * want[3] - have[3] * want[2], have[3] * want[1] - have[1] * want[3],
            have[1] * want[2] - have[2] * want[1]}
        local step = normalize({axis[1], axis[2], axis[3], 1 + d})
        if not step then return nil end
        q = normalize(mul(step, q))
    end
    local angle = math.deg(2 * math.acos(math.min(1, math.abs(q[4]))))
    if angle > Sights.MAX_CORRECTION_DEGREES then return nil end
    return q
end

function Sights.install(mod, presentation)
    local api = {eyes = {}, grips = {}, correction = {0, 0, 0, 1}}
    for name, eye in pairs(Sights.SHIPPED_EYES) do api.eyes[name] = {x = eye.x, z = eye.z, source = "shipped"} end
    local ads_since, failures, logged = nil, 0, {}

    local function log_failure(message)
        failures = failures + 1
        if failures == 1 then mod:info("DARKTIDEVR_GUN_SIGHTS failed=%s", tostring(message):sub(1, 160)) end
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
            target = Sights.zeroing({Vector3.x(grip), Vector3.y(grip), Vector3.z(grip)}, {ax, ay, az, aw}, offset,
                {Vector3.x(point), Vector3.y(point), Vector3.z(point)}) or target
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
        local local_eye = Matrix4x4.transform(Matrix4x4.inverse(Unit.world_pose(unit_1p, node_1p)),
            Unit.world_position(camera, 1))
        local measured = {x = Vector3.x(local_eye), z = Vector3.z(local_eye), source = "measured"}
        if not Sights.offset(measured, {x = 0, z = 0}) then return end
        api.eyes[template.name] = measured
        mod:info("DARKTIDEVR_GUN_SIGHTS eye template=%s eye_in_muzzle=%.4f,%.4f previous=%s", template.name,
            measured.x, measured.z, eye and string.format("%.4f,%.4f", eye.x, eye.z) or "none")
    end

    function api.update(unit, t)
        local ok, message = pcall(measure, unit, t)
        if not ok then log_failure(message) end
    end
    return api
end

return Sights
