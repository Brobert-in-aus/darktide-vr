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

function Skull.install(mod, presentation)
    local api = {}
    local zone = {id = "skull", selector = "blitz", centre = {0, 0, 0}, radius = Skull.GRAB_RADIUS}
    local zones = {zone}
    local Settings, States
    local originals
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

    -- Every skull's rest positions while the option is on: sides mirrored,
    -- the flamethrower's brought forward; restored when it is off. The stock
    -- movement extensions read the same table every frame. The server keeps
    -- its own table, so an order sends the real skull from the server's rest;
    -- the follower below carries the drawn one across.
    local applied_mirror
    local function apply_forward(on)
        Settings = Settings or require("scripts/settings/companion/companion_servo_skull_movement_settings")
        local rules = Settings.movement_settings
        if type(rules) ~= "table" then return end
        -- Stock rests the throwable skull on the right: the off-hand side
        -- already for a left-handed player, so the sides swap only when the
        -- support hand is the left one. A change of handedness re-applies.
        local roles = presentation.weapon_hand_roles
        local mirror = Skull.MIRROR_SIDE and not (roles and roles.physical and roles.physical("support") == "right")
        if on and originals and applied_mirror ~= mirror then
            apply_forward(false)
        end
        if on and not originals then
            applied_mirror = mirror
            originals = {}
            local seen = {}
            local tables = 0
            for rule, entry in pairs(rules) do
                originals[rule] = {}
                -- Both views' tables: the stock extension picks one by
                -- is_in_first_person_mode(), which the first-person body
                -- reports as third person.
                for _, view in ipairs({"first_person", "third_person"}) do
                    local position = type(entry) == "table" and entry[view] and entry[view].position
                    -- Two rules sharing one table would be mirrored twice.
                    if type(position) == "table" and not seen[position] then
                        seen[position] = true
                        local saved, plain = {}, {}
                        for name, box in pairs(position) do
                            saved[name] = box
                            local v = box:unbox()
                            plain[name] = {Vector3.x(v), Vector3.y(v), Vector3.z(v)}
                        end
                        originals[rule][view] = saved
                        local forward = rule == Skull.RULE and Skull.FORWARD or nil
                        for name, offset in pairs(Skull.rest_offsets(plain, forward, mirror)) do
                            position[name] = Vector3Box(offset[1], offset[2], offset[3])
                        end
                        tables = tables + 1
                    end
                end
            end
            mod:info("DARKTIDEVR_SKULL_THROW rest_forward=%.2f mirror=%s tables=%d", Skull.FORWARD,
                tostring(mirror), tables)
        elseif not on and originals then
            for rule, views in pairs(originals) do
                local entry = rules[rule]
                for view, saved in pairs(views) do
                    local position = type(entry) == "table" and entry[view] and entry[view].position
                    if type(position) == "table" then
                        for name, box in pairs(saved) do position[name] = box end
                    end
                end
            end
            originals = nil
        end
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
        local on = api.enabled()
        apply_forward(on)
        if not on or not frame then return nil end
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

    -- The off hand let go of a skull grab: the throw, if an order starts.
    function api.released(unit)
        local t = now()
        if not t or not hand_track.position then return end
        local unit_data = unit and ScriptUnit.has_extension(unit, "unit_data_system")
        local finder = unit_data and unit_data:read_component("action_module_position_finder")
        local target = finder and finder.position_valid and array(finder.position)
        if target then target[3] = target[3] - Skull.TARGET_DROP end
        pending = {t = t, position = hand_track.position, velocity = hand_track.velocity or {0, 0, 0}, target = target}
        mod:info("DARKTIDEVR_SKULL_THROW released target=%s", target and "valid" or "none")
    end

    -- The skull's first child node, which the throw animation moves.
    local function child_node(skull)
        local ok, count = pcall(Unit.num_scene_graph_items, skull)
        if not ok or not count then return nil end
        for node = 2, count do
            if Unit.scene_graph_parent(skull, node) == 1 then return node end
        end
    end
    -- A drawn placement through the child node: base is the node's own local
    -- position (re-read whenever something else wrote the node), written the
    -- last position this module wrote. Shared by the throw and the follower.
    local function place(extension, skull, record, drawn)
        local root_pose = Unit.world_pose(skull, 1)
        local local_offset = Matrix4x4.transform(Matrix4x4.inverse(root_pose), Vector3(drawn[1], drawn[2], drawn[3]))
        local current = Unit.local_position(skull, record.node)
        if not record.base or not record.written or Vector3.distance(current, record.written:unbox()) >= 1e-5 then
            record.base = Vector3Box(current)
        end
        local desired = record.base:unbox() + local_offset
        Unit.set_local_position(skull, record.node, desired)
        record.written = Vector3Box(desired)
        World.update_unit_and_children(extension._world, skull)
    end
    local function unplace(record, skull)
        if record and record.node and record.base and skull and Unit.alive(skull) then
            local current = Unit.local_position(skull, record.node)
            if record.written and Vector3.distance(current, record.written:unbox()) < 1e-5 then
                Unit.set_local_position(skull, record.node, record.base:unbox())
            end
        end
    end
    -- One follower record per skull of the local player (the flamethrower
    -- skull's also carries the bridge to and from a flight).
    local followers = setmetatable({}, {__mode = "k"})
    local function follower(skull)
        local record = followers[skull]
        if not record then record = {}; followers[skull] = record end
        return record
    end
    local function restore(skull, keep_throw)
        if not keep_throw then
            unplace(throw, skull)
            throw = nil
        end
        unplace(followers[skull], skull)
        followers[skull] = nil
    end

    -- The owner's eye, head yaw and horizontal velocity this frame, shared by
    -- every skull: {eye, head_yaw, heading, velocity}, or nil without a head.
    local heading_state, shared, shared_t
    local function owner_frame(owner, t)
        if shared_t == t then return shared end
        local dt = shared_t and t - shared_t or nil
        shared_t, shared = t, nil
        local eye, rotation
        if presentation.eye_pose then eye, rotation = presentation.eye_pose(owner) end
        if not eye or not rotation then heading_state = nil; return nil end
        local forward = Quaternion.forward(rotation)
        local fx, fy = Vector3.x(forward), Vector3.y(forward)
        local head_yaw = (fx * fx + fy * fy > 0.04) and math.atan2(-fx, fy) or (heading_state and heading_state.head_yaw)
        if not head_yaw then return nil end
        heading_state = Skull.lazy_yaw(heading_state, head_yaw, dt)
        heading_state.head_yaw = head_yaw
        local velocity
        local unit_data = ScriptUnit.has_extension(owner, "unit_data_system")
        local locomotion = unit_data and unit_data:read_component("locomotion")
        if locomotion and locomotion.velocity_current then
            velocity = array(locomotion.velocity_current)
        end
        shared = {eye = array(eye), head_yaw = head_yaw, heading = heading_state.yaw, velocity = velocity}
        return shared
    end

    -- The follower for one skull while it follows at the player's side.
    local function follow_skull(extension, skull, follow, owner, t, name)
        local real = array(Unit.world_position(skull, 1))
        local dt = follow.t and t - follow.t or 0
        follow.t = t
        follow.node = follow.node or child_node(skull)
        -- A bridge left on the child node when the skull came back: undone.
        if follow.base then unplace(follow, skull); follow.base, follow.written = nil, nil end
        local frame = owner_frame(owner, t)
        if not frame then return real end
        local eye = frame.eye
        -- Back from a flight it resumes from the flight's last real position,
        -- so the return to the mirrored rest is a glide, not a jump.
        if not follow.offset and follow.last_real then
            follow.offset = {follow.last_real[1] - eye[1], follow.last_real[2] - eye[2], follow.last_real[3] - eye[3]}
        end
        follow.last_real, follow.bridge = nil, nil
        local target = Skull.follow_offset(real, eye, frame.head_yaw, frame.heading, frame.velocity)
        follow.offset = Skull.smoothed(follow.offset, target, dt, Skull.OFFSET_TAU)
        follow.position = {eye[1] + follow.offset[1], eye[2] + follow.offset[2], eye[3] + follow.offset[3]}
        -- The root itself, not the child node the throw moves: that node was
        -- never seen to move the skull (worn, 17 September: "still locked to
        -- my head" with the follower logging its placements). While the
        -- skull follows, both stock extensions compute its position from
        -- scratch and write the root just before this hook, so this write
        -- lasts one frame and needs no undoing; the grab zone, read from the
        -- root at the next input frame, is where the skull is drawn.
        Unit.set_local_position(skull, 1, Vector3(follow.position[1], follow.position[2], follow.position[3]))
        World.update_unit_and_children(extension._world, skull)
        if not follow.logged then
            follow.logged = true
            local ok, count = pcall(Unit.num_scene_graph_items, skull)
            local children = 0
            if ok and count then
                for node = 2, count do
                    if Unit.scene_graph_parent(skull, node) == 1 then children = children + 1 end
                end
            end
            mod:info("DARKTIDEVR_SKULL_THROW follow=root state=%s thrower=%s nodes=%s root_children=%d child_node=%s",
                tostring(name), tostring(follow.thrower == true), tostring(ok and count or nil), children,
                tostring(follow.node))
        end
        return real
    end

    -- After the stock movement extension placed the skull this frame.
    local function after_movement(extension, skull)
        -- Every frame, so turning the option off restores the stock offsets.
        apply_forward(api.enabled())
        local owner = local_player_unit()
        if not owner or extension._owner_unit ~= owner then return end
        local name = state_name(extension)
        local following = name == "following" or name == "following_shooting" or name == "following_shooting_ability"
        -- The husk extension keeps no rule field: match the owner's skull unit.
        local thrower = companion(owner) == skull
        if thrower then api.following = following end
        if not api.enabled() then
            restore(skull, not thrower)
            if thrower then pending = nil end
            return
        end
        local t = now()
        if not t then return end
        local follow = follower(skull)
        follow.thrower = thrower
        if not thrower then
            -- The medical and regular skulls: the follower only; away on an
            -- order they are drawn as they are.
            if following then
                follow_skull(extension, skull, follow, owner, t, name)
            else
                unplace(follow, skull)
                followers[skull] = nil
            end
            return
        end
        local flying = name == "flamethrower"
        if pending and flying and not throw and t - pending.t <= Skull.RELEASE_WINDOW then
            local from = array(Unit.world_position(skull, 1))
            local total = pending.target and Skull.flight_time(from, pending.target)
            if total and total > 0.05 then
                throw = {start = t, total = total, release = pending.position, velocity = pending.velocity,
                    target = pending.target, node = child_node(skull)}
                mod:info("DARKTIDEVR_SKULL_THROW flight predicted_s=%.2f distance_m=%.2f node=%s", total,
                    total * Skull.SPEED, tostring(throw.node))
            end
            pending = nil
        elseif pending and t - pending.t > Skull.RELEASE_WINDOW then
            pending = nil
        end
        if not throw then
            if api.following then
                follow_skull(extension, skull, follow, owner, t, name)
            else
                -- Sent, or on its way back: a short bridge from where the
                -- follower had it to the real flight, then the real skull as
                -- it is. The last real position seeds the follower's return.
                local real = array(Unit.world_position(skull, 1))
                follow.t = t
                follow.node = follow.node or child_node(skull)
                follow.last_real = real
                if follow.position and not follow.bridge then
                    follow.bridge = {start = t, from = follow.position}
                    follow.position, follow.offset = nil, nil
                end
                if follow.bridge and follow.node then
                    local drawn, done = Skull.bridge_position(follow.bridge.from, real, t - follow.bridge.start)
                    if done then
                        unplace(follow, skull)
                        follow.bridge, follow.base, follow.written = nil, nil, nil
                    else
                        place(extension, skull, follow, drawn)
                    end
                end
            end
            return
        end
        -- A throw takes over from the follower cleanly.
        if follow.base then unplace(follow, skull); followers[skull] = nil end
        local elapsed = t - throw.start
        local real = array(Unit.world_position(skull, 1))
        if not throw.arrived and throw.target then
            local dx, dy, dz = real[1] - throw.target[1], real[2] - throw.target[2], real[3] - throw.target[3]
            if dx * dx + dy * dy + dz * dz <= Skull.ARRIVED_METRES * Skull.ARRIVED_METRES then
                throw.arrived = elapsed
                mod:info("DARKTIDEVR_SKULL_THROW arrived predicted_s=%.2f actual_s=%.2f", throw.total, elapsed)
            end
        end
        local weight = Skull.blend_weight(elapsed, throw.total)
        if not flying or elapsed > Skull.MAX_THROW_SECONDS or weight >= 1 or not throw.node then
            restore(skull); return
        end
        local drawn = Skull.drawn_position(throw.release, throw.velocity, elapsed, real, weight)
        place(extension, skull, throw, drawn)
    end

    -- Every child-node placement undone (a bridge or a throw); the
    -- follower's root writes undo themselves at the next stock update.
    local function unplace_all()
        for skull, record in pairs(followers) do
            if Unit.alive(skull) then unplace(record, skull) end
        end
        followers = setmetatable({}, {__mode = "k"})
        local owner = local_player_unit()
        local thrower = owner and companion(owner)
        if throw and thrower then unplace(throw, thrower) end
        throw = nil
    end

    local failed = false
    local function hook_class(class)
        if not class or logged[class] then return end
        logged[class] = true
        mod:hook_safe(class, "post_update", function(self, unit)
            if failed then return end
            local ok, err = pcall(after_movement, self, unit)
            if not ok then
                failed = true
                pcall(unplace_all)
                mod:warning("DARKTIDEVR_SKULL_THROW error=%s", tostring(err))
            end
        end)
    end
    if mod.hook_require then
        mod:hook_require("scripts/extension_systems/flying_companion_movement/flying_companion_movement_extension", hook_class)
        mod:hook_require("scripts/extension_systems/flying_companion_movement/flying_companion_husk_movement_extension", hook_class)
    end

    function api.destroy()
        pcall(unplace_all)
        pending = nil; throw = nil; heading_state = nil; shared = nil; shared_t = nil
        apply_forward(false)
    end
    return api
end

return Skull
