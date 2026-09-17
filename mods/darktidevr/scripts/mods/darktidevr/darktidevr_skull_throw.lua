-- Grab and throw the servo skull's flamethrower (option "vr_skull_throw",
-- default off; user, 15 September evening; Skitarius with the flamethrower
-- skull talented).
--
-- Visible: the flamethrower skull's first-person rest position is brought
-- forward (stock hovers it 15 cm behind the eye, out of view); its side and
-- height offsets stay stock. The stock follow code places it from that table
-- every frame on the owner's client, local or husk, so this is presentation.
--
-- Grab: while the skull follows, a grab zone at its drawn position is offered
-- to the off hand through the holster grip request with the blitz selector,
-- as the belt blitz holster does: grip holds the stock blitz input (aim the
-- order), releasing it issues the order.
--
-- Throw animation (user, 15 September evening): the stock order flies the
-- skull straight at 10 m/s to the aimed point lowered by 1 m
-- (CompanionServoSkullAbility.start_flamethrower_ability,
-- FlyingCompanionMovementExtension.post_update), so the flight time T is the
-- distance divided by 10 m/s. For the first FREE_FRACTION of T the drawn skull
-- flies freely from the hand at the release velocity; then it blends into the
-- real skull's position, fully there by T. The drawing moves a child node of
-- the skull, never its root, so the flight itself stays the game's.
local Skull = {}

Skull.RULE = "cryptic_servo_skull_flamethrower"
Skull.FORWARD = 0.30
Skull.GRAB_RADIUS = 0.12
Skull.SPEED = 10
Skull.TARGET_DROP = 1
Skull.FREE_FRACTION = 0.4
-- A release counts as the throw that started a flight this soon after it.
Skull.RELEASE_WINDOW = 0.75
Skull.MAX_THROW_SECONDS = 4
Skull.ARRIVED_METRES = 0.15
-- The skulls' sides swapped (user, 16 September worn): stock rests the
-- flamethrower skull on the right, beside the gun hand's forearm holster,
-- so the off hand reaching for it found the holster's zone first; the
-- medical and regular skulls rest on the left. Mirroring the rest table's
-- side axis puts the throwable one at the off hand and the others away.
Skull.TEST_FLAG = "./../mods/darktidevr/darktidevr_skull_throw_test.flag"
Skull.MIRROR_SIDE = true
-- The drawn skull follows its real position smoothly, as the HUD follows
-- the head, instead of sitting rigidly on the body: a time constant, and a
-- distance beyond which it snaps (a respawn, a teleport). The same
-- follower carries it across the jump when an order sends the server's
-- skull from the server's own rest, and back again when it returns.
Skull.FOLLOW_TAU = 0.2
Skull.FOLLOW_SNAP = 2.0
-- When an order sends the skull, the drawn one bridges from where the
-- follower had it to the real flight over this long, then the real skull
-- is drawn as it is (a chase at 10 m/s would trail by metres); when it
-- returns, the follower resumes from the flight's last real position.
Skull.BRIDGE_SECONDS = 0.35
-- Worn, 17 September: neither the swapped sides nor the follower showed. The
-- first-person body deliberately reports third person to the equipment code,
-- so the stock movement reads each rule's third_person table (flamethrower
-- 0.55 m to the right, the medical skull to the left), not the first_person
-- one that was mirrored: both are mirrored now. And the stock skull is placed
-- from the head's look rotation, so a drawn skull chasing it 0.2 s behind
-- still read as locked to the head. The drawn skull now keeps its place
-- relative to a lazy heading (the head's yaw behind a dead zone, as the body
-- frame's is), follows the head's position exactly as the HUD does, and
-- leans up to LEAD_METRES ahead along the player's run so it is easy to find
-- (user: "try to stay ~0.3m ahead of me as I run").
Skull.YAW_DEAD_ZONE = math.rad(20)
Skull.YAW_SETTLED = math.rad(2)
Skull.YAW_CATCH_UP_SECONDS = 0.35
Skull.OFFSET_TAU = 0.25
Skull.LEAD_METRES = 0.3
Skull.LEAD_FULL_SPEED = 4.0
Skull.LEAD_MIN_SPEED = 0.5

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end

-- The flight time from one point to another at speed. 3-arrays. Pure.
function Skull.flight_time(from, to, speed)
    if type(from) ~= "table" or type(to) ~= "table" then return nil end
    local dx, dy, dz = to[1] - from[1], to[2] - from[2], to[3] - from[3]
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    speed = speed or Skull.SPEED
    if not finite(distance) or not (speed > 0) then return nil end
    return distance / speed
end

-- How far the drawn skull has blended into the real one: 0 during the free
-- flight (the first free_fraction of total), rising to 1 at total. Pure.
function Skull.blend_weight(elapsed, total, free_fraction)
    free_fraction = free_fraction or Skull.FREE_FRACTION
    if not finite(elapsed) or not finite(total) or total <= 0 then return 1 end
    local free = total * free_fraction
    if elapsed <= free then return 0 end
    if elapsed >= total then return 1 end
    return (elapsed - free) / (total - free)
end

-- The drawn position: the free flight from the release blended into the real
-- position by weight. 3-arrays. Pure.
function Skull.drawn_position(release, velocity, elapsed, real, weight)
    local free = {release[1] + velocity[1] * elapsed, release[2] + velocity[2] * elapsed,
        release[3] + velocity[3] * elapsed}
    return {free[1] + (real[1] - free[1]) * weight, free[2] + (real[2] - free[2]) * weight,
        free[3] + (real[3] - free[3]) * weight}
end

-- The rest offsets with the forward offset replaced, x and z kept. position:
-- {name = {x, y, z}}. Pure.
function Skull.forward_offsets(position, forward)
    local result = {}
    for name, offset in pairs(position) do result[name] = {offset[1], forward, offset[3]} end
    return result
end

-- The rest offsets for one skull rule: the side (x) mirrored when asked, the
-- forward offset (y) replaced when given, height kept. Pure.
function Skull.rest_offsets(position, forward, mirror)
    local result = {}
    for name, offset in pairs(position) do
        result[name] = {mirror and -offset[1] or offset[1], forward or offset[2], offset[3]}
    end
    return result
end

-- The drawn position on the bridge from `from` to the real one: linear in
-- time over duration, the real position from then on. 3-arrays. Pure.
function Skull.bridge_position(from, real, elapsed, duration)
    duration = duration or Skull.BRIDGE_SECONDS
    if type(from) ~= "table" or not (duration > 0) then return {real[1], real[2], real[3]}, true end
    if not finite(elapsed) or elapsed <= 0 then return {from[1], from[2], from[3]}, false end
    if elapsed >= duration then return {real[1], real[2], real[3]}, true end
    local w = elapsed / duration
    return {from[1] + (real[1] - from[1]) * w, from[2] + (real[2] - from[2]) * w,
        from[3] + (real[3] - from[3]) * w}, false
end

local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end

-- The lazy heading after a frame: it holds while the head stays within the
-- dead zone of it, then catches the head up and settles. state is
-- {yaw, turning} or nil; returns the new state. Stingray yaw. Pure.
function Skull.lazy_yaw(state, head_yaw, dt)
    if not finite(head_yaw) then return state end
    if type(state) ~= "table" or not finite(state.yaw) or not finite(dt) or dt < 0 or dt > 0.5 then
        return {yaw = head_yaw, turning = false}
    end
    local yaw, turning = state.yaw, state.turning == true
    local diff = wrap(head_yaw - yaw)
    if math.abs(diff) > Skull.YAW_DEAD_ZONE then turning = true end
    if turning then
        yaw = wrap(yaw + diff * (1 - math.exp(-dt / Skull.YAW_CATCH_UP_SECONDS)))
        if math.abs(wrap(head_yaw - yaw)) < Skull.YAW_SETTLED then turning = false end
    end
    return {yaw = yaw, turning = turning}
end

-- Where the drawn skull wants to be relative to the eye: the real skull's
-- offset from the eye turned from the head's yaw to the lazy heading (about
-- the vertical), plus a lead along the player's horizontal velocity that
-- grows to LEAD_METRES at a run. 3-arrays (velocity may be nil). Pure.
function Skull.follow_offset(real, eye, head_yaw, heading, velocity)
    local a = (finite(head_yaw) and finite(heading)) and wrap(heading - head_yaw) or 0
    local dx, dy = real[1] - eye[1], real[2] - eye[2]
    local c, s = math.cos(a), math.sin(a)
    local x, y = dx * c - dy * s, dx * s + dy * c
    if type(velocity) == "table" and finite(velocity[1]) and finite(velocity[2]) then
        local speed = math.sqrt(velocity[1] * velocity[1] + velocity[2] * velocity[2])
        if speed > Skull.LEAD_MIN_SPEED then
            local lead = Skull.LEAD_METRES * math.min(1, speed / Skull.LEAD_FULL_SPEED) / speed
            x, y = x + velocity[1] * lead, y + velocity[2] * lead
        end
    end
    return {x, y, real[3] - eye[3]}
end

-- The drawn position smoothed toward the real one: exponential with the
-- time constant, snapping when there is no drawn position yet, no time has
-- passed since a snap is harmless, or the two are further apart than snap.
-- 3-arrays. Pure.
function Skull.smoothed(drawn, real, dt, tau, snap)
    tau, snap = tau or Skull.FOLLOW_TAU, snap or Skull.FOLLOW_SNAP
    if type(drawn) ~= "table" or not finite(dt) or dt < 0 then return {real[1], real[2], real[3]} end
    local dx, dy, dz = real[1] - drawn[1], real[2] - drawn[2], real[3] - drawn[3]
    if dx * dx + dy * dy + dz * dz > snap * snap then return {real[1], real[2], real[3]} end
    local alpha = 1 - math.exp(-dt / tau)
    return {drawn[1] + dx * alpha, drawn[2] + dy * alpha, drawn[3] + dz * alpha}
end

-- One writer (worn, 17 September, second round: with the follower writing the
-- skull's root after the stock extension had, the skull's own physics parts
-- flickered while the player moved, as every double-written position has).
-- The stock extension places a following skull from three inputs: the
-- owner's look rotation, the first-person position, and a rest offset
-- {x, y, z} used as position - right * x + forward * y, z up. The module
-- now feeds it those inputs for the local player's skulls, for the length of
-- its update only, and writes nothing itself: the lazy heading in place of
-- the look rotation, and offsets that carry the swapped side, the throwable
-- skull's forward rest, the lead along the run and, while the off hand
-- holds the skull, the hand.

-- A world offset (3-array, from the first-person position) as the stock
-- rest offset for a heading (Stingray yaw): x is to the LEFT. Pure.
function Skull.stock_offset(delta, heading)
    local c, s = math.cos(heading), math.sin(heading)
    local right_x, right_y, forward_x, forward_y = c, s, -s, c
    return {-(delta[1] * right_x + delta[2] * right_y), delta[1] * forward_x + delta[2] * forward_y, delta[3]}
end

-- The lead along the player's horizontal velocity, a world 3-array: none
-- below LEAD_MIN_SPEED, LEAD_METRES at LEAD_FULL_SPEED and beyond. Pure.
function Skull.lead(velocity)
    if type(velocity) ~= "table" or not finite(velocity[1]) or not finite(velocity[2]) then return {0, 0, 0} end
    local speed = math.sqrt(velocity[1] * velocity[1] + velocity[2] * velocity[2])
    if speed <= Skull.LEAD_MIN_SPEED then return {0, 0, 0} end
    local k = Skull.LEAD_METRES * math.min(1, speed / Skull.LEAD_FULL_SPEED) / speed
    return {velocity[1] * k, velocity[2] * k, 0}
end

-- The rest offset the stock extension is given for one skull this frame.
-- rest: the stock offset {x, y, z}; mirror and forward as Skull.rest_offsets;
-- lead a world 3-array and heading the lazy yaw. Pure.
function Skull.fed_offset(rest, mirror, forward, lead, heading)
    local l = Skull.stock_offset(lead or {0, 0, 0}, heading)
    return {(mirror and -rest[1] or rest[1]) + l[1], (forward or rest[2]) + l[2], rest[3]}
end

-- While the off hand holds the skull it sits just above the hand.
Skull.HOLD_UP = 0.07

function Skull.install(mod, presentation)
    local api = {}
    local zone = {id = "skull", selector = "blitz", centre = {0, 0, 0}, radius = Skull.GRAB_RADIUS}
    local zones = {zone}
    local Settings, States
    local throw, pending
    local hand_track = {}
    local logged = {}

    local function now() return Managers.time and Managers.time:has_timer("main") and Managers.time:time("main") or nil end
    local function array(v) return v and {Vector3.x(v), Vector3.y(v), Vector3.z(v)} or nil end

    -- The unattended test flag turns the option on for a run, as the other
    -- hand displays' flags do, polled every 300 calls.
    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        test_poll = 300
        local file = Mods and Mods.lua and Mods.lua.io and Mods.lua.io.open(Skull.TEST_FLAG, "r")
        if not file then test_enabled = false; return false end
        local value = file:read(32) or ""
        file:close()
        test_enabled = value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end
    function api.enabled()
        local on = (mod.get and mod:get("vr_skull_throw") == true) or test_flag()
        if not on or presentation.mode ~= 1 then return false end
        return not (presentation.current_game_mode_name and presentation.current_game_mode_name() == "hub")
    end

    local function local_player_unit()
        local player = Managers.player and Managers.player:local_player(1)
        return player and player.player_unit
    end

    -- The local player's flamethrower skull, or nil without the talent.
    local function companion(unit)
        local talent = unit and ScriptUnit.has_extension(unit, "talent_system")
        if not talent or not talent:has_special_rule(Skull.RULE) then return nil end
        local spawner = ScriptUnit.has_extension(unit, "companion_spawner_system")
        local skull = spawner and spawner:spawned_unit_lookup(Skull.RULE)
        return skull and Unit.alive(skull) and skull or nil
    end

    local function state_name(extension)
        States = States or require("scripts/settings/companion/companion_servo_skull_settings").STATES
        local session, id = extension._game_session, extension._game_object_id
        if not session or not id or not GameSession.game_object_exists(session, id) then return nil end
        return States[GameSession.game_object_field(session, id, "state")]
    end

    -- The grab zone in the holster frame for the off hand this input frame,
    -- or nil while the skull is not following at the player's side.
    api.following = false
    function api.local_zones(unit, frame, Holsters)
        if not api.enabled() or not frame then return nil end
        local side = presentation.weapon_hand_roles and presentation.weapon_hand_roles.physical("support")
        local position
        if side == "left" then position = presentation.left_controller_grip_target()
        elseif side == "right" then position = presentation.controller_grip_target() end
        local t = now()
        if position and t then
            local previous = hand_track.position
            if previous and hand_track.t and t > hand_track.t then
                local dt = t - hand_track.t
                local p = array(position)
                hand_track.velocity = {(p[1] - previous[1]) / dt, (p[2] - previous[2]) / dt, (p[3] - previous[3]) / dt}
            end
            hand_track.position, hand_track.t = array(position), t
        end
        local skull = companion(unit)
        if not skull or not api.following then return nil end
        zone.centre = Holsters.local_point(frame, array(Unit.world_position(skull, 1)))
        zone.radius = Skull.GRAB_RADIUS / frame.scale
        return zones
    end

    -- The holsters say each input frame whether the off hand holds the
    -- skull's grab; it lapses by itself if they stop saying so.
    local held_until
    function api.set_held(held)
        local t = now()
        held_until = held and t and t + 0.25 or nil
    end
    local function held(t) return held_until ~= nil and t ~= nil and t <= held_until end

    -- The off hand let go of a skull grab: the throw, if an order starts.
    function api.released(unit)
        held_until = nil
        local t = now()
        if not t or not hand_track.position then return end
        local unit_data = unit and ScriptUnit.has_extension(unit, "unit_data_system")
        local finder = unit_data and unit_data:read_component("action_module_position_finder")
        local target = finder and finder.position_valid and array(finder.position)
        if target then target[3] = target[3] - Skull.TARGET_DROP end
        pending = {t = t, position = hand_track.position, velocity = hand_track.velocity or {0, 0, 0}, target = target}
        mod:info("DARKTIDEVR_SKULL_THROW released target=%s", target and "valid" or "none")
    end

    -- Every node directly under the skull's root: the parts are nine
    -- siblings there (log, 17 September: nodes=27 root_children=9), so moving
    -- the first alone, as the throw did, moved nothing anyone could see.
    local function child_nodes(skull)
        local nodes = {}
        local ok, count = pcall(Unit.num_scene_graph_items, skull)
        if not ok or not count then return nodes end
        for node = 2, count do
            if Unit.scene_graph_parent(skull, node) == 1 then nodes[#nodes + 1] = node end
        end
        return nodes
    end
    -- A drawn placement through the root's children, for the flight only
    -- (where the root is the network's or the locomotion's, not ours to
    -- feed): base is each node's own local position (re-read whenever
    -- something else wrote it), written the last this module wrote.
    local function place(extension, skull, record, drawn)
        record.nodes = record.nodes or child_nodes(skull)
        record.base, record.written = record.base or {}, record.written or {}
        local root_pose = Unit.world_pose(skull, 1)
        local local_offset = Matrix4x4.transform(Matrix4x4.inverse(root_pose), Vector3(drawn[1], drawn[2], drawn[3]))
        for _, node in ipairs(record.nodes) do
            local current = Unit.local_position(skull, node)
            local written = record.written[node]
            if not record.base[node] or not written or Vector3.distance(current, written:unbox()) >= 1e-5 then
                record.base[node] = Vector3Box(current)
            end
            local desired = record.base[node]:unbox() + local_offset
            Unit.set_local_position(skull, node, desired)
            record.written[node] = Vector3Box(desired)
        end
        World.update_unit_and_children(extension._world, skull)
    end
    local function unplace(record, skull)
        if not record or not record.nodes or not record.base or not skull or not Unit.alive(skull) then return end
        for _, node in ipairs(record.nodes) do
            local written, base = record.written and record.written[node], record.base[node]
            if written and base and Vector3.distance(Unit.local_position(skull, node), written:unbox()) < 1e-5 then
                Unit.set_local_position(skull, node, base:unbox())
            end
        end
        record.base, record.written = nil, nil
    end

    -- One record per skull of the local player.
    local records = setmetatable({}, {__mode = "k"})
    local function record_of(skull)
        local record = records[skull]
        if not record then record = {boxes = {}}; records[skull] = record end
        return record
    end
    local function unplace_all()
        for skull, record in pairs(records) do
            if Unit.alive(skull) then unplace(record.bridge_nodes, skull) end
        end
        local owner = local_player_unit()
        local thrower = owner and companion(owner)
        if throw and thrower then unplace(throw, thrower) end
        throw = nil
        records = setmetatable({}, {__mode = "k"})
    end

    -- The owner's lazy heading and lead this frame, shared by their skulls.
    local heading_state, shared, shared_t
    local function owner_frame(owner, t)
        if shared_t == t then return shared end
        local dt = shared_t and t - shared_t or nil
        shared_t, shared = t, nil
        local first_person = ScriptUnit.has_extension(owner, "first_person_system")
        if not first_person then heading_state = nil; return nil end
        -- The class's own look rotation (this module shadows the instance's
        -- method only for the length of a skull's update).
        local forward = Quaternion.forward(first_person:extrapolated_rotation())
        local fx, fy = Vector3.x(forward), Vector3.y(forward)
        local head_yaw = (fx * fx + fy * fy > 0.04) and math.atan2(-fx, fy) or (heading_state and heading_state.head_yaw)
        if not head_yaw then return nil end
        heading_state = Skull.lazy_yaw(heading_state, head_yaw, dt)
        heading_state.head_yaw = head_yaw
        local velocity
        local unit_data = ScriptUnit.has_extension(owner, "unit_data_system")
        local locomotion = unit_data and unit_data:read_component("locomotion")
        if locomotion and locomotion.velocity_current then velocity = array(locomotion.velocity_current) end
        shared = {first_person = first_person, heading = heading_state.yaw, lead = Skull.lead(velocity)}
        return shared
    end

    -- Feed the stock update: returns what to undo afterwards, or nil.
    local function feed(extension, skull, record, owner, t, thrower)
        local frame = owner_frame(owner, t)
        if not frame then return nil end
        local roles = presentation.weapon_hand_roles
        -- Stock rests the throwable skull on the right: the off-hand side
        -- already for a left-handed player.
        local mirror = Skull.MIRROR_SIDE and not (roles and roles.physical and roles.physical("support") == "right")
        local first_person_unit = frame.first_person:first_person_unit()
        local origin = first_person_unit and array(Unit.world_position(first_person_unit, 1))
        local hold
        if thrower and held(t) and hand_track.position and origin then
            hold = Skull.stock_offset({hand_track.position[1] - origin[1], hand_track.position[2] - origin[2],
                hand_track.position[3] + Skull.HOLD_UP - origin[3]}, frame.heading)
        end
        local undo = {first_person = frame.first_person, tables = {}}
        for _, field in ipairs({"_first_person_movement_settings", "_third_person_movement_settings"}) do
            local settings = extension[field]
            local position = type(settings) == "table" and settings.position
            if type(position) == "table" then
                local saved = {}
                record.boxes[field] = record.boxes[field] or {}
                for name, box in pairs(position) do
                    saved[name] = box
                    local v = box:unbox()
                    local fed = hold or Skull.fed_offset({Vector3.x(v), Vector3.y(v), Vector3.z(v)}, mirror,
                        thrower and Skull.FORWARD or nil, frame.lead, frame.heading)
                    local mine = record.boxes[field][name]
                    if not mine then mine = Vector3Box(0, 0, 0); record.boxes[field][name] = mine end
                    mine:store(Vector3(fed[1], fed[2], fed[3]))
                end
                for name in pairs(saved) do position[name] = record.boxes[field][name] end
                undo.tables[#undo.tables + 1] = {position = position, saved = saved}
            end
        end
        -- Held: the stock smoothing of the offset would trail the hand by
        -- half a second; its state is put on the hand.
        local smoothing = extension._companion_position_offset
        if hold and smoothing and smoothing.store then smoothing:store(Vector3(hold[1], hold[2], hold[3])) end
        local heading = frame.heading
        undo.shadowed = rawget(frame.first_person, "extrapolated_rotation")
        rawset(frame.first_person, "extrapolated_rotation", function() return Quaternion(Vector3.up(), heading) end)
        if not record.logged then
            record.logged = true
            mod:info("DARKTIDEVR_SKULL_THROW feed thrower=%s mirror=%s tables=%d root_children=%d", tostring(thrower),
                tostring(mirror), #undo.tables, #child_nodes(skull))
        end
        if hold and not record.hold_logged then
            record.hold_logged = true
            mod:info("DARKTIDEVR_SKULL_THROW held offset=%.2f,%.2f,%.2f", hold[1], hold[2], hold[3])
        end
        return undo
    end
    local function unfeed(undo)
        if not undo then return end
        rawset(undo.first_person, "extrapolated_rotation", undo.shadowed)
        for _, entry in ipairs(undo.tables) do
            for name, box in pairs(entry.saved) do entry.position[name] = box end
        end
    end

    -- After the stock update: the flight's drawn placement (the throw's arc
    -- from the hand; the bridge from where the skull was drawn to a flight
    -- that starts from the server's own rest).
    local function after_movement(extension, skull, record, thrower, following, name, t)
        if not thrower then return end
        local flying = name == "flamethrower"
        if pending and flying and not throw and t - pending.t <= Skull.RELEASE_WINDOW then
            local from = array(Unit.world_position(skull, 1))
            local total = pending.target and Skull.flight_time(from, pending.target)
            if total and total > 0.05 then
                throw = {start = t, total = total, release = pending.position, velocity = pending.velocity,
                    target = pending.target}
                mod:info("DARKTIDEVR_SKULL_THROW flight predicted_s=%.2f distance_m=%.2f nodes=%d", total,
                    total * Skull.SPEED, #child_nodes(skull))
            end
            pending = nil
        elseif pending and t - pending.t > Skull.RELEASE_WINDOW then
            pending = nil
        end
        local real = array(Unit.world_position(skull, 1))
        if not throw then
            record.bridge_nodes = record.bridge_nodes or {}
            if following then
                unplace(record.bridge_nodes, skull)
                record.bridge, record.position = nil, real
            else
                if record.position and not record.bridge then
                    record.bridge = {start = t, from = record.position}
                    record.position = nil
                end
                if record.bridge then
                    local drawn, done = Skull.bridge_position(record.bridge.from, real, t - record.bridge.start)
                    if done then unplace(record.bridge_nodes, skull) else place(extension, skull, record.bridge_nodes, drawn) end
                end
            end
            return
        end
        -- A throw takes over from the bridge cleanly.
        if record.bridge_nodes then unplace(record.bridge_nodes, skull) end
        record.bridge, record.position = nil, nil
        local elapsed = t - throw.start
        if not throw.arrived and throw.target then
            local dx, dy, dz = real[1] - throw.target[1], real[2] - throw.target[2], real[3] - throw.target[3]
            if dx * dx + dy * dy + dz * dz <= Skull.ARRIVED_METRES * Skull.ARRIVED_METRES then
                throw.arrived = elapsed
                mod:info("DARKTIDEVR_SKULL_THROW arrived predicted_s=%.2f actual_s=%.2f", throw.total, elapsed)
            end
        end
        local weight = Skull.blend_weight(elapsed, throw.total)
        if not flying or elapsed > Skull.MAX_THROW_SECONDS or weight >= 1 then
            unplace(throw, skull); throw = nil
            return
        end
        place(extension, skull, throw, Skull.drawn_position(throw.release, throw.velocity, elapsed, real, weight))
    end

    local failed = false
    local function hook_class(class)
        if not class or logged[class] then return end
        logged[class] = true
        -- One hook (a mod's second hook on a method is ignored): it wraps the
        -- stock update so the fed inputs are in place for its length only.
        mod:hook(class, "post_update", function(func, self, unit, ...)
            if failed then return func(self, unit, ...) end
            local owner = local_player_unit()
            local t = now()
            if not owner or not t or self._owner_unit ~= owner then return func(self, unit, ...) end
            local ok_state, name = pcall(state_name, self)
            if not ok_state then name = nil end
            local following = name == "following" or name == "following_shooting" or name == "following_shooting_ability"
            local thrower = companion(owner) == unit
            if thrower then api.following = following end
            if not api.enabled() then
                if records[unit] or (thrower and throw) then pcall(unplace_all); pending = nil end
                return func(self, unit, ...)
            end
            local record = record_of(unit)
            local undo
            if following then
                local ok, result = pcall(feed, self, unit, record, owner, t, thrower)
                if ok then undo = result else
                    failed = true
                    mod:warning("DARKTIDEVR_SKULL_THROW feed_error=%s", tostring(result))
                end
            end
            -- The stock update runs under pcall only so the fed inputs are
            -- always taken back; its own error goes on as it would have.
            local ok, err = pcall(func, self, unit, ...)
            pcall(unfeed, undo)
            if not ok then error(err, 0) end
            if failed then pcall(unplace_all); return end
            local ok_after, after_err = pcall(after_movement, self, unit, record, thrower, following, name, t)
            if not ok_after then
                failed = true
                pcall(unplace_all)
                mod:warning("DARKTIDEVR_SKULL_THROW error=%s", tostring(after_err))
            end
        end)
    end
    if mod.hook_require then
        mod:hook_require("scripts/extension_systems/flying_companion_movement/flying_companion_movement_extension", hook_class)
        mod:hook_require("scripts/extension_systems/flying_companion_movement/flying_companion_husk_movement_extension", hook_class)
    end

    function api.destroy()
        pcall(unplace_all)
        pending = nil; throw = nil; heading_state = nil; shared = nil; shared_t = nil; held_until = nil
    end
    return api
end

return Skull
