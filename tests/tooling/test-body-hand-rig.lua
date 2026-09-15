-- Body-drawn hands (BodyProxy.set_hand_rig): with a full-profile body as the
-- hand rig no glove units exist, every placement records one final wrist pose
-- per physical side, and equipment hand joints follow that pose. The glove
-- fallback returns when the rig dies. Runs the real module with small vector
-- and quaternion stand-ins.
local proxy_path, main_path = assert(arg[1]), assert(arg[2])

local vmt = {}
local function V(x, y, z) return setmetatable({x, y, z}, vmt) end
vmt.__add = function(a, b) return V(a[1] + b[1], a[2] + b[2], a[3] + b[3]) end
vmt.__sub = function(a, b) return V(a[1] - b[1], a[2] - b[2], a[3] - b[3]) end
vmt.__mul = function(a, k) return V(a[1] * k, a[2] * k, a[3] * k) end
vmt.__div = function(a, k) return V(a[1] / k, a[2] / k, a[3] / k) end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function cross(a, b) return V(a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]) end
local function normalize(a) local l = math.sqrt(dot(a, a)); return a / l end

local function Q(x, y, z, w) return {x, y, z, w} end
local function qmul(a, b)
    return Q(a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
        a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
        a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
        a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3])
end
local function qrotate(q, v)
    local r = qmul(qmul(q, Q(v[1], v[2], v[3], 0)), Q(-q[1], -q[2], -q[3], q[4]))
    return V(r[1], r[2], r[3])
end
local function axis_angle(axis, angle)
    local a = normalize(axis); local s = math.sin(angle / 2)
    return Q(a[1] * s, a[2] * s, a[3] * s, math.cos(angle / 2))
end
local function from_matrix(x, y, z)
    local trace = x[1] + y[2] + z[3]
    if trace > 0 then
        local s = 0.5 / math.sqrt(trace + 1)
        return Q((y[3] - z[2]) * s, (z[1] - x[3]) * s, (x[2] - y[1]) * s, 0.25 / s)
    elseif x[1] > y[2] and x[1] > z[3] then
        local s = 2 * math.sqrt(1 + x[1] - y[2] - z[3])
        return Q(s / 4, (x[2] + y[1]) / s, (z[1] + x[3]) / s, (y[3] - z[2]) / s)
    elseif y[2] > z[3] then
        local s = 2 * math.sqrt(1 + y[2] - x[1] - z[3])
        return Q((x[2] + y[1]) / s, s / 4, (y[3] + z[2]) / s, (z[1] - x[3]) / s)
    end
    local s = 2 * math.sqrt(1 + z[3] - x[1] - y[2])
    return Q((z[1] + x[3]) / s, (y[3] + z[2]) / s, s / 4, (x[2] - y[1]) / s)
end

Vector3 = {
    x = function(v) return v[1] end, y = function(v) return v[2] end, z = function(v) return v[3] end,
    length_squared = function(v) return dot(v, v) end, length = function(v) return math.sqrt(dot(v, v)) end,
    normalize = normalize, cross = cross,
    lerp = function(a, b, t) return a + (b - a) * t end,
}
Quaternion = {
    multiply = qmul, rotate = qrotate,
    right = function(q) return qrotate(q, V(1, 0, 0)) end,
    forward = function(q) return qrotate(q, V(0, 1, 0)) end,
    look = function(forward, up)
        local y = normalize(forward); local x = normalize(cross(y, up)); local z = cross(x, y)
        return from_matrix(x, y, z)
    end,
    to_elements = function(q) return q[1], q[2], q[3], q[4] end,
    from_elements = Q,
    lerp = function(a, b, t)
        local d = a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4]
        local k = d < 0 and -1 or 1
        local r = Q(a[1] + (b[1] * k - a[1]) * t, a[2] + (b[2] * k - a[2]) * t,
            a[3] + (b[3] * k - a[3]) * t, a[4] + (b[4] * k - a[4]) * t)
        local l = math.sqrt(r[1] ^ 2 + r[2] ^ 2 + r[3] ^ 2 + r[4] ^ 2)
        return Q(r[1] / l, r[2] / l, r[3] / l, r[4] / l)
    end,
}
local function box(value)
    local b = {value = value}
    function b:store(v) self.value = v end
    function b:unbox() return self.value end
    return b
end
Vector3Box, QuaternionBox = box, box
table.clear = table.clear or function(t) for k in pairs(t) do t[k] = nil end end
table.clone_instance = function(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end
local logs = {}
print = function(line) logs[#logs + 1] = line end

-- Units: nodes carry world poses; a hand node's parent sits at the origin.
local function unit(nodes) return {nodes = nodes} end
Unit = {
    alive = function(u) return u ~= nil and not u.dead end,
    has_node = function(u, name) return u.nodes[name] ~= nil end,
    node = function(u, name) return name end,
    world_position = function(u, n) return u.nodes[n].position end,
    world_rotation = function(u, n) return u.nodes[n].rotation end,
    scene_graph_parent = function(u, n) return u.nodes[n].parent end,
    local_scale = function() return V(1, 1, 1) end,
    local_position = function() return V(0, 0, 0) end,
    local_rotation = function() return Q(0, 0, 0, 1) end,
    set_local_position = function(u, n, p) u.nodes[n].local_position = p end,
    set_local_rotation = function(u, n, q) u.nodes[n].local_rotation = q end,
}
World = {update_unit_and_children = function() end}

local spawns = 0
local spawner = {ignore_slot = function() end, spawn_profile = function() end, update = function() end,
    spawned = function() return false end, destroy = function() end}
require = function(name)
    if name:find('ui_profile_spawner', 1, true) then
        return {new = function() spawns = spawns + 1; return spawner end}
    elseif name:find('ui_unit_spawner', 1, true) then
        return {new = function() return {destroy = function() end} end}
    elseif name:find('master_items', 1, true) then
        return {get_item = function() return {} end}
    end
    return {}
end
local BodyProxy = dofile(proxy_path)

local function near(a, b, what)
    for i = 1, 3 do assert(math.abs(a[i] - b[i]) < 1e-6, what) end
end
local function qnear(a, b, what)
    local d = math.abs(a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4])
    assert(d > 1 - 1e-6, what)
end

-- A rig whose hand joints define a wrist basis (identity hand rotation).
local function rig()
    local nodes = {}
    for _, side in ipairs({'left', 'right'}) do
        local s = side == 'left' and -1 or 1
        nodes['j_' .. side .. 'hand'] = {position = V(0, 0, 0), rotation = Q(0, 0, 0, 1)}
        nodes['j_' .. side .. 'handmiddle1'] = {position = V(0, 0, -0.08)}
        nodes['j_' .. side .. 'handindex1'] = {position = V(0.03 * s, 0, -0.07)}
        nodes['j_' .. side .. 'handpinky1'] = {position = V(-0.03 * s, 0, -0.07)}
    end
    return unit(nodes)
end
local function anatomy_inverse(side)
    local s = side == 'left' and -1 or 1
    local longitudinal = normalize(V(0, 0, -0.08))
    local across = normalize(V(0.06 * s, 0, 0))
    local palm = normalize(cross(across, longitudinal))
    local f = Quaternion.look(palm, across)
    return Q(-f[1], -f[2], -f[3], f[4])
end
local function expected(rotation, side)
    return qmul(Quaternion.look(Quaternion.right(rotation) * -1, Quaternion.forward(rotation)), anatomy_inverse(side))
end

local world, profile = {}, {loadout = {}}
local source = unit({j_righthand = {position = V(0.4, 0.1, 1.2), rotation = axis_angle(V(0, 0, 1), 0.3)}})
local player = {profile = function() return profile end}

-- Rejected rig (no knuckles) leaves the gloves in charge.
assert(BodyProxy.set_hand_rig(unit({})) == false and logs[#logs]:find('rejected', 1, true))

-- Body rig: no glove spawns, the source unit carries the hands path.
local body = rig()
assert(BodyProxy.set_hand_rig(body) == true and logs[#logs]:find('hand_rig=body', 1, true))
assert(BodyProxy.set_hand_rig(body) == true, 'same rig is a no-op')
assert(BodyProxy.update(world, source, player, true, 0.016, 1, true) == source)
assert(spawns == 0, 'body-drawn hands spawned glove units')
assert(BodyProxy.active() and BodyProxy.rigid_hands_active() and BodyProxy.hides_source_slot('slot_body_arms'))

-- Tracked placement records both physical sides; no units are returned.
local lp, rp = V(-0.2, 0.4, 1.3), V(0.25, 0.45, 1.25)
local lr, rr = axis_angle(V(1, 2, 3), 0.7), axis_angle(V(-2, 1, 0.5), -1.1)
local lu, ru, any, lw, rw = BodyProxy.place_rigid_hands(world, lp, lr, rp, rr)
assert(lu == nil and ru == nil and any and lw and rw)
local p, r = BodyProxy.hand_pose('left')
near(p, lp, 'left pose position'); qnear(r, expected(lr, 'left'), 'left anatomical rotation')
p, r = BodyProxy.hand_pose('right')
near(p, rp, 'right pose position'); qnear(r, expected(rr, 'right'), 'right anatomical rotation')
qnear(assert(BodyProxy.equipment_hand_rotation(source, 'right', rr)), expected(rr, 'right'), 'equipment rotation without a glove unit')

-- Two-hand support blends from the recorded tracked pose.
assert(BodyProxy.place_support_hand(world, source, 'left', V(0.2, 0.4, 1.3), lr, false, 0.5))
near((BodyProxy.hand_pose('left')), V(0, 0.4, 1.3), 'support blend from the recorded pose')

-- Handedness: gun alignment onto either physical hand records that side.
local old_p, old_r = V(0.4, 0.1, 1.2), Q(0, 0, 0, 1)
local new_p, new_r = V(0.5, 0.2, 1.1), axis_angle(V(0, 1, 0), 0.4)
for _, destination in ipairs({'right', 'left'}) do
    assert(BodyProxy.align_gun_hand(world, source, old_p, old_r, new_p, new_r, destination), destination)
    local hand = source.nodes.j_righthand
    near((BodyProxy.hand_pose(destination)), new_p + qrotate(new_r, hand.position - old_p), 'aligned ' .. destination)
end

-- Equipment joints follow the recorded pose when there is no glove unit.
local file = assert(io.open(main_path, 'rb')); local main = file:read('*a'); file:close()
local first = assert(main:find('function presentation.sync_equipment_hand_pose(', 1, true))
local last = assert(main:find('\nfunction presentation.sync_tracked_equipment_hand(', first, true))
presentation = {body_proxy = BodyProxy, inverse_quaternion = function(q) return Q(-q[1], -q[2], -q[3], q[4]) end,
    rotate_vector = qrotate}
assert(loadstring(main:sub(first, last - 1)))()
local avatar = unit({root = {position = V(0, 0, 0), rotation = Q(0, 0, 0, 1)},
    j_lefthand = {parent = 'root'}, j_righthand = {parent = 'root'}})
for _, side in ipairs({'left', 'right'}) do
    local name = 'j_' .. side .. 'hand'
    assert(presentation.sync_equipment_hand_to_proxy(avatar, nil, name), name)
    local position, rotation = BodyProxy.hand_pose(side)
    near(avatar.nodes[name].local_position, position, 'equipment ' .. side .. ' position')
    qnear(avatar.nodes[name].local_rotation, rotation, 'equipment ' .. side .. ' rotation')
end
assert(presentation.sync_equipment_hand_to_proxy(avatar, nil, 'j_head') == false)

-- The rig dies: gloves come back (spawned), no stale pose is offered.
body.dead = true
assert(BodyProxy.update(world, source, player, true, 0.016, 2, true) == nil)
assert(spawns == 2, 'glove fallback did not spawn')
assert(not BodyProxy.active() and BodyProxy.hand_pose('left') == nil)
local lost = false
for _, line in ipairs(logs) do lost = lost or line:find('reason=rig_unit_lost', 1, true) ~= nil end
assert(lost)
assert(BodyProxy.set_hand_rig(nil) == false)
print = function(...) io.write(table.concat({...}, ' '), '\n') end
print('body_hand_rig=pass no_glove_units pose_record anatomical_rotation support_blend handedness equipment_follow fallback')
