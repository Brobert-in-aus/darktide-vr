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
-- Where the throwable skull rests, relative to stock. FORWARD replaces the
-- stock forward offset outright (stock hovers it 15 cm BEHIND the eye);
-- SIDE_RIGHT and DOWN are added to the stock side and height.
--
-- Sized worn, 18 September: "the flamethrower skull needs to come forward,
-- right and down 30cm each". FORWARD was 0.30, so 30 cm further forward is
-- 0.60; the other two axes were stock and now carry the offset.
Skull.FORWARD = 0.60
Skull.SIDE_RIGHT = 0.30
Skull.DOWN = 0.30
Skull.GRAB_RADIUS = 0.12
-- Held: the hand-to-centre distance the grab keeps, so the palm sits on the
-- skull's side (its drawn radius is about 12 cm) wherever it was taken from.
Skull.GRAB_HOLD_MIN, Skull.GRAB_HOLD_MAX = 0.10, 0.16

-- A rotation's axis (3-array, unit) and angle from quaternion elements, for
-- the placement's world axis and angle; nil axis and zero angle for the
-- identity. Pure.
function Skull.axis_angle(x, y, z, w)
    local sine = math.sqrt(x * x + y * y + z * z)
    if sine < 1e-6 then return nil, 0 end
    local angle = 2 * math.atan2(sine, w)
    if angle > math.pi then angle = angle - 2 * math.pi end
    return {x / sine, y / sine, z / sine}, angle
end
Skull.SPEED = 10
Skull.TARGET_DROP = 1
Skull.FREE_FRACTION = 0.4
-- ...but never longer than this, however far the throw goes. The free flight
-- is a straight line along the hand's release velocity with no gravity and no
-- relation to the target, so its length is how far the drawn skull can end up
-- from the real one before the blend takes over. At FREE_FRACTION alone a 20 m
-- throw gives 0.8 s of it, and a natural downward follow-through at 3 m/s puts
-- the drawn skull two and a half metres below the hand -- through the floor,
-- most likely -- before it is pulled back (review, 18 September). A quarter of
-- a second is long enough to read as a throw and short enough that it cannot
-- go somewhere absurd. Short throws are unaffected: below about 0.6 s of
-- flight the fraction is already the smaller of the two.
Skull.FREE_MAX_SECONDS = 0.25
-- The free flight arcs and tumbles (user, worn: "can we have the skull tumble
-- and follow a ballistic arc rather than moving in a straight line?").
--
-- Only the DRAWN skull does either. The real one still flies straight to its
-- target at SPEED, because that is the game's order and this module has never
-- touched it; the arc is what the throw looks like for the quarter second
-- before the blend takes over, and the blend still lands on the real position.
-- Over FREE_MAX_SECONDS the drop is about 30 cm, which reads as a throw
-- without the skull appearing to be falling out of the air.
Skull.GRAVITY = 9.81
-- Radians per second per metre per second: a hard throw spins faster than a
-- gentle one, which is most of what makes a tumble read as thrown rather than
-- as animated. Capped so a fast throw does not turn into a blur.
Skull.TUMBLE_PER_SPEED = 1.1
Skull.TUMBLE_MAX_RATE = 14
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
    local free = math.min(total * free_fraction, Skull.FREE_MAX_SECONDS)
    if elapsed <= free then return 0 end
    if elapsed >= total then return 1 end
    return (elapsed - free) / (total - free)
end

-- The free flight is stepped rather than evaluated, because it now has to be
-- swept against the world: a thrown skull that paths through the floor and out
-- the other side of a wall is worse than one that flew straight (user, 18
-- September: "it should bounce off the ground and not path through solid
-- objects"). A closed-form position cannot be collided; a step can.
--
-- One step of the free flight: gravity applied to the velocity, then the
-- velocity to the position. Returns the new position and velocity. Pure.
function Skull.step(position, velocity, dt)
    if type(position) ~= "table" or type(velocity) ~= "table" then return position, velocity end
    local d = finite(dt) and dt or 0
    if d <= 0 then return position, velocity end
    local vz = velocity[3] - Skull.GRAVITY * d
    return {position[1] + velocity[1] * d,
            position[2] + velocity[2] * d,
            position[3] + vz * d},
           {velocity[1], velocity[2], vz}
end

-- The velocity after bouncing off a surface: reflected about the normal and
-- damped. A skull is bone rather than rubber, so most of the energy goes.
-- Velocity into the surface only -- a glancing pass that is already leaving
-- must not be flipped back into it, which is what makes a resting object
-- jitter. 3-arrays. Pure.
-- How many consecutive errors stand the module down. One used to, which is how
-- a bug in the cosmetic bounce also cost the skull side mirroring and the hold
-- pose for a whole session (worn, 18 September).
Skull.MAX_CONSECUTIVE_FAILURES = 3
Skull.RESTITUTION = 0.35
Skull.FRICTION = 0.7
function Skull.bounce(velocity, normal, restitution)
    if type(velocity) ~= "table" or type(normal) ~= "table" then return velocity end
    local nx, ny, nz = normal[1], normal[2], normal[3]
    local length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if not finite(length) or length < 1e-6 then return velocity end
    nx, ny, nz = nx / length, ny / length, nz / length
    local into = velocity[1] * nx + velocity[2] * ny + velocity[3] * nz
    -- Already moving away from the surface: nothing to bounce off.
    if into >= 0 then return velocity end
    local e = finite(restitution) and restitution or Skull.RESTITUTION
    -- Split into the part along the normal (bounces, damped by restitution)
    -- and the part across it (slides, damped by friction).
    local along = {into * nx, into * ny, into * nz}
    local across = {velocity[1] - along[1], velocity[2] - along[2], velocity[3] - along[3]}
    return {across[1] * Skull.FRICTION - along[1] * e,
            across[2] * Skull.FRICTION - along[2] * e,
            across[3] * Skull.FRICTION - along[3] * e}
end

-- Where the free flight has got to: the release velocity plus gravity. The
-- vertical is Stingray's +z, so gravity subtracts from it. 3-array. Pure.
function Skull.ballistic(release, velocity, elapsed)
    if type(release) ~= "table" or type(velocity) ~= "table" then return release end
    local e = finite(elapsed) and elapsed or 0
    if e < 0 then e = 0 end
    return {release[1] + velocity[1] * e,
        release[2] + velocity[2] * e,
        release[3] + velocity[3] * e - 0.5 * Skull.GRAVITY * e * e}
end

-- A uniformly random unit axis from two uniform numbers in [0, 1). Uniform on
-- the sphere rather than uniform in the angles, which would crowd the poles.
-- Taking the randomness as arguments keeps it pure and lets the test pin it.
function Skull.random_axis(r1, r2)
    local a = (finite(r1) and r1 or 0) % 1
    local b = (finite(r2) and r2 or 0) % 1
    local z = 2 * a - 1
    local theta = 2 * math.pi * b
    local ring = math.sqrt(math.max(0, 1 - z * z))
    return {ring * math.cos(theta), ring * math.sin(theta), z}
end

-- How fast this throw tumbles, in radians a second: harder throws spin faster,
-- capped so a hard one does not blur. nil when there is nothing to spin --
-- a dead stop. The AXIS is chosen once per throw (Skull.random_axis) rather
-- than derived from the velocity: a skull is not aerodynamic and has no reason
-- to prefer an axis, and a derived one made every throw the same animation.
-- Pure.
function Skull.tumble_rate(velocity)
    if type(velocity) ~= "table" then return nil end
    local vx, vy, vz = velocity[1], velocity[2], velocity[3]
    if not (finite(vx) and finite(vy) and finite(vz)) then return nil end
    local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
    if not (speed > 1e-4) then return nil end
    return math.min(Skull.TUMBLE_PER_SPEED * speed, Skull.TUMBLE_MAX_RATE)
end

-- The angle after another `dt` at `rate`, eased out by the blend so the spin
-- stops as the drawn skull settles onto the real one. Only ever grows. Pure.
function Skull.tumbled_angle(angle, rate, weight, dt)
    local a = finite(angle) and angle or 0
    if not finite(rate) or not finite(dt) or dt <= 0 then return a end
    local w = finite(weight) and math.max(0, math.min(1, weight)) or 0
    return a + rate * (1 - w) * dt
end

-- The drawn position: a free-flight position blended into the real one by
-- weight. `free` is now stepped and swept by the caller rather than evaluated
-- here, so that it can bounce; `Skull.ballistic` remains for the closed form.
-- 3-arrays. Pure.
function Skull.drawn_position(release, velocity, elapsed, real, weight, free_override)
    local free = free_override or Skull.ballistic(release, velocity, elapsed)
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

-- How a release is turned into a throw. A hand's velocity measured across a
-- SINGLE frame is the wrong instrument for this: at 120 Hz it is an 8 ms
-- finite difference of tracked data, it is dominated by tracker noise, and at
-- the moment someone lets go of a button their hand is decelerating -- so the
-- number it reports is close to zero however hard the throw was. That is what
-- "throwing it has no physics, it just floats where released" is: the free
-- flight ran with a velocity of nearly nothing, so the skull sat where it was
-- released until the blend pulled it to its destination.
--
-- Measured across a window instead, which is what the hand actually did.
-- Capped, so a tracking glitch cannot fling the drawn skull off somewhere the
-- real one never goes.
Skull.THROW_WINDOW_SECONDS = 0.15
-- The shortest span a speed may be measured over. Below this it is tracker
-- noise divided by a very small number.
Skull.THROW_MIN_SPAN_SECONDS = 0.04
-- Raised from 12: a hard throw is faster than that, and the cap was quietly
-- doing some of the work the averaging was doing.
Skull.THROW_MAX_SPEED = 18

-- The velocity a release carries. `samples` is {t, x, y, z} entries, oldest
-- first; `t` is the release time. Returns a world 3-array, zero when there is
-- nothing usable to measure. Pure.
function Skull.release_velocity(samples, t)
    if type(samples) ~= "table" or not finite(t) then return {0, 0, 0} end
    local newest = samples[#samples]
    if type(newest) ~= "table" or not finite(newest[1]) then return {0, 0, 0} end
    -- The oldest sample still inside the window. Walking back from the newest
    -- stops at the first one outside it, so a stale entry left over from
    -- before a gap cannot widen the window and understate the speed.
    local oldest
    for index = #samples, 1, -1 do
        local sample = samples[index]
        if type(sample) ~= "table" or not finite(sample[1]) or
                t - sample[1] > Skull.THROW_WINDOW_SECONDS then break end
        oldest = sample
    end
    if not oldest or oldest == newest then return {0, 0, 0} end
    -- The FASTEST span in the window, not the whole window's average.
    --
    -- Averaging across the whole 150 ms was the first cut and it threw far too
    -- softly (user, worn: "still way too slow for how fast I'm throwing"). A
    -- throw accelerates, peaks, and then decelerates into the release -- the
    -- hand is already slowing when the button comes up -- so the mean over the
    -- window is roughly half the peak. What the skull should leave the hand
    -- with is the peak.
    --
    -- Still a span rather than a frame pair: MIN_SPAN_SECONDS keeps it long
    -- enough that tracker noise cannot manufacture a speed, which is the thing
    -- the window existed to fix in the first place.
    -- Between ANY pair inside the window, not only pairs ending at the
    -- release. The peak of a throw is in the middle of the motion -- the hand
    -- is already slowing by the time the button comes up -- so every span that
    -- ends at the release drags the follow-through into its average. What the
    -- skull should leave with is how fast the hand was going at its fastest.
    -- About twenty samples, once per throw, so the pairs are free.
    local best, speed = nil, 0
    local first = 1
    while first <= #samples and t - samples[first][1] > Skull.THROW_WINDOW_SECONDS do
        first = first + 1
    end
    for i = first, #samples do
        for j = i + 1, #samples do
            local a, b = samples[i], samples[j]
            if type(a) == "table" and type(b) == "table" and finite(a[1]) and finite(b[1]) then
                local span = b[1] - a[1]
                if span >= Skull.THROW_MIN_SPAN_SECONDS then
                    local candidate = {(b[2] - a[2]) / span, (b[3] - a[3]) / span,
                        (b[4] - a[4]) / span}
                    local magnitude = math.sqrt(candidate[1] * candidate[1] +
                        candidate[2] * candidate[2] + candidate[3] * candidate[3])
                    if finite(magnitude) and magnitude > speed then best, speed = candidate, magnitude end
                end
            end
        end
    end
    -- Nothing spanned the minimum: fall back to the whole window rather than
    -- reporting a standstill, which is how a short flick would read otherwise.
    if not best then
        local span = newest[1] - oldest[1]
        if not (span > 0) then return {0, 0, 0} end
        best = {(newest[2] - oldest[2]) / span, (newest[3] - oldest[3]) / span,
            (newest[4] - oldest[4]) / span}
        speed = math.sqrt(best[1] * best[1] + best[2] * best[2] + best[3] * best[3])
    end
    local v = best
    if not finite(speed) or speed <= 0 then return {0, 0, 0} end
    if speed > Skull.THROW_MAX_SPEED then
        local k = Skull.THROW_MAX_SPEED / speed
        v[1], v[2], v[3] = v[1] * k, v[2] * k, v[3] * k
    end
    return v
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
-- lead a world 3-array and heading the lazy yaw. The stock update multiplies
-- a rest offset's x by the player's field-of-view setting over the default
-- (fov, 1 when unset): the stock rest keeps that, the lead is an exact
-- world distance and is divided by it first. Pure.
-- `forward` is given only for the throwable skull, so it is also what says
-- whether the worn side and height offsets apply: the other skulls keep their
-- stock rest exactly. x is to the LEFT, so moving right subtracts, and it is
-- divided by fov for the same reason the lead is -- it is an exact world
-- distance, and the stock update multiplies x by fov afterwards. Height is
-- not scaled, because stock does not scale it.
function Skull.fed_offset(rest, mirror, forward, lead, heading, fov)
    fov = (finite(fov) and fov > 0.1) and fov or 1
    local l = Skull.stock_offset(lead or {0, 0, 0}, heading)
    local thrown = forward ~= nil
    return {(mirror and -rest[1] or rest[1]) + l[1] / fov -
            (thrown and Skull.SIDE_RIGHT / fov or 0),
        (forward or rest[2]) + l[2],
        rest[3] - (thrown and Skull.DOWN or 0)}
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
        -- Before the sampling, not after: without the talent there is no skull
        -- to throw, and the window below allocates on the input thread every
        -- frame. `api.following` is deliberately NOT checked here -- it goes
        -- false while the off hand holds the skull, which is exactly when the
        -- throw is being wound up.
        local skull = companion(unit)
        if not skull then return nil end
        local t = now()
        if position and t then
            local p = array(position)
            -- The window the throw is measured over. Trimmed here rather than
            -- at the release so the list cannot grow while the skull is held.
            local samples = hand_track.samples
            if not samples then samples = {} hand_track.samples = samples end
            if hand_track.t == nil or t > hand_track.t then
                samples[#samples + 1] = {t, p[1], p[2], p[3]}
                local keep = 1
                while keep < #samples and t - samples[keep][1] > Skull.THROW_WINDOW_SECONDS do
                    keep = keep + 1
                end
                -- One sample older than the window is kept: it is what makes
                -- the window a full THROW_WINDOW_SECONDS rather than however
                -- much of it happens to have landed inside.
                if keep > 2 then
                    local shifted = {}
                    for index = keep - 1, #samples do shifted[#shifted + 1] = samples[index] end
                    hand_track.samples = shifted
                end
            end
            hand_track.position, hand_track.t = p, t
            -- The hand's rotation too (the visible wrist's, from the body
            -- proxy), for the grab: the skull turns with the hand.
            local proxy = presentation.body_proxy
            if proxy and proxy.hand_pose then
                local _, rotation = proxy.hand_pose(side)
                if rotation then
                    if hand_track.rotation then hand_track.rotation:store(rotation) else hand_track.rotation = QuaternionBox(rotation) end
                end
            end
        end
        if not api.following then return nil end
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
        local velocity = Skull.release_velocity(hand_track.samples, t)
        pending = {t = t, position = hand_track.position, velocity = velocity, target = target}
        mod:info("DARKTIDEVR_SKULL_THROW released target=%s speed=%.2f samples=%d",
            target and "valid" or "none",
            math.sqrt(velocity[1] * velocity[1] + velocity[2] * velocity[2] + velocity[3] * velocity[3]),
            hand_track.samples and #hand_track.samples or 0)
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
    -- `axis` and `angle` tumble the drawn skull about its own centre. The
    -- rotation is applied to the same child nodes the translation moves, and
    -- about the mean of their placed positions, so the skull spins in place
    -- rather than orbiting the root -- the root is the game's and is never
    -- touched, which is the rule this whole module is built on.
    -- One step of the free flight, swept against the world so the drawn skull
    -- bounces off the ground instead of pathing through it. A ray along the
    -- step rather than a shape sweep: the skull is small, the steps are short,
    -- and a ray is what this module can reach. Returns the new position and
    -- velocity, and whether it bounced.
    --
    -- Everything here is guarded and falls back to the unswept step: a
    -- diagnostic-grade collision failing must not stop the throw being drawn.
    local function sweep_free_flight(extension, from, velocity, dt)
        local stepped, next_velocity = Skull.step(from, velocity, dt)
        local physics_world = extension and extension._physics_world
        if not physics_world or not dt or dt <= 0 then return stepped, next_velocity, false end
        local dx = stepped[1] - from[1]
        local dy = stepped[2] - from[2]
        local dz = stepped[3] - from[3]
        local travelled = math.sqrt(dx * dx + dy * dy + dz * dz)
        if not finite(travelled) or travelled < 1e-4 then return stepped, next_velocity, false end
        -- `closest` returns five values in this order, which is not the
        -- table-of-hits shape the `all` mode returns:
        --     result, hit_position, hit_distance, normal, actor
        -- The first cut read it as a hit list and compared the POSITION
        -- against a number -- "attempt to compare userdata with number" -- and
        -- that error did not just lose the bounce. It propagated to the
        -- caller's pcall, which sets `failed`, and `failed` turns this whole
        -- module into a passthrough for the rest of the session: the throw
        -- glitched mid-flight AND the skulls went back to their stock sides,
        -- because the side mirroring is fed by the same module (worn, 18
        -- September). Verified against stock: beast_of_nurgle.lua:198,
        -- bt_beast_of_nurgle_consume_action.lua:528.
        local ok, result, point, _, normal = pcall(PhysicsWorld.raycast, physics_world,
            Vector3(from[1], from[2], from[3]),
            Vector3(dx / travelled, dy / travelled, dz / travelled),
            travelled, "closest", "types", "statics",
            "collision_filter", "filter_player_character_shooting_raycast")
        if not ok or not result or not point or not normal then
            return stepped, next_velocity, false
        end
        local n = array(normal)
        local p = array(point)
        if not n or not p then return stepped, next_velocity, false end
        local bounced = Skull.bounce(next_velocity, n, Skull.RESTITUTION)
        -- Off the surface by a hair, or the next sweep starts inside it and
        -- the skull sticks.
        return {p[1] + n[1] * 0.02, p[2] + n[2] * 0.02, p[3] + n[3] * 0.02},
            bounced, true
    end

    -- The sweep is cosmetic and must never be able to take the module with it.
    --
    -- The caller's pcall sets `failed` on any error, and `failed` is permanent
    -- for the session -- so a bug in a bounce cost the player their skull side
    -- mirroring and their throw animation until they restarted. Nothing about
    -- drawing an arc is worth that, so this swallows its own failures and
    -- degrades to the unswept step.
    local sweep_failures = 0
    local function swept_step(extension, from, velocity, dt)
        local ok, position, next_velocity, bounced =
            pcall(sweep_free_flight, extension, from, velocity, dt)
        if ok then return position, next_velocity, bounced end
        sweep_failures = sweep_failures + 1
        if sweep_failures == 1 then
            mod:info("DARKTIDEVR_SKULL_THROW sweep_unavailable=%s", tostring(position):sub(1, 140))
        end
        local stepped, stepped_velocity = Skull.step(from, velocity, dt)
        return stepped, stepped_velocity, false
    end

    local skull_motion_lines = 0
    -- The anchor's lag: where the first-person unit stands (the game's
    -- interpolated timeline) minus the fixed-step component position the
    -- view is built on, as the body mirror measures it. A 3-array, or nil.
    local function anchor_lag(owner)
        if not owner or not Unit.alive(owner) then return nil end
        local first_person = ScriptUnit.has_extension(owner, "first_person_system")
        local component = first_person and first_person._first_person_component
        local eye_unit = first_person and first_person.first_person_unit and first_person:first_person_unit()
        if not component or not component.position or not eye_unit or not Unit.alive(eye_unit) then return nil end
        -- The view's anchor is whatever presentation.anchor_head_position
        -- says (15:10, 19 September: the first-person unit's interpolated
        -- position; before that, the fixed-step component's). The lag is
        -- the interpolated point minus that anchor: zero when the view is
        -- on the interpolated timeline. The 15:26 worn run had this
        -- subtracting the component lag after the anchor had moved to the
        -- unit, which put the skulls back on the fixed-step timeline
        -- against a smooth view: "skulls are flickering again, but less".
        local anchor = presentation.anchor_head_position and presentation.anchor_head_position(first_person) or component.position
        local lag = Unit.world_position(eye_unit, 1) - anchor
        if Vector3.length(lag) > 0.5 then return nil end
        return {Vector3.x(lag), Vector3.y(lag), Vector3.z(lag)}
    end
    local function place(extension, skull, record, drawn, axis, angle)
        record.nodes = record.nodes or child_nodes(skull)
        record.base, record.written = record.base or {}, record.written or {}
        local root_pose = Unit.world_pose(skull, 1)
        local root_inverse = Matrix4x4.inverse(root_pose)
        local local_offset = Matrix4x4.transform(root_inverse, Vector3(drawn[1], drawn[2], drawn[3]))
        -- The tumble arrives as a world axis; the nodes are posed in the
        -- skull's frame, so it has to be taken there first.
        local rotation
        if axis and angle and angle ~= 0 then
            local ok, local_axis = pcall(Matrix4x4.transform_without_translation,
                root_inverse, Vector3(axis[1], axis[2], axis[3]))
            if ok and local_axis and Vector3.length(local_axis) > 1e-6 then
                local spun = pcall(function()
                    rotation = Quaternion.axis_angle(Vector3.normalize(local_axis), angle)
                end)
                if not spun then rotation = nil end
            end
        end
        -- The centre to spin about: the mean of where the parts are going.
        local pivot, counted = Vector3(0, 0, 0), 0
        if rotation then
            for _, node in ipairs(record.nodes) do
                local base = record.base[node]
                if base then pivot = pivot + base:unbox() + local_offset; counted = counted + 1 end
            end
            if counted > 0 then pivot = pivot / counted else rotation = nil end
        end
        for _, node in ipairs(record.nodes) do
            local current = Unit.local_position(skull, node)
            local written = record.written[node]
            if not record.base[node] or not written or Vector3.distance(current, written:unbox()) >= 1e-5 then
                record.base[node] = Vector3Box(current)
            end
            -- The rest ROTATION is captured once and never re-read, which is
            -- NOT the same terms as the position. Position is re-read because
            -- by then it is someone else's value; nothing but this code writes
            -- these nodes' local rotation, so a re-read returns our own
            -- previous frame's product. Re-capturing it compounded the spin
            -- into a blur and left `unplace` restoring a rotated "rest"
            -- (review, 18 September).
            record.base_rotation = record.base_rotation or {}
            if not record.base_rotation[node] then
                record.base_rotation[node] = QuaternionBox(Unit.local_rotation(skull, node))
            end
            local desired = record.base[node]:unbox() + local_offset
            if rotation then
                desired = pivot + Quaternion.rotate(rotation, desired - pivot)
                local rest = record.base_rotation and record.base_rotation[node]
                if rest then
                    Unit.set_local_rotation(skull, node,
                        Quaternion.multiply(rotation, rest:unbox()))
                end
            end
            Unit.set_local_position(skull, node, desired)
            record.written[node] = Vector3Box(desired)
        end
        World.update_unit_and_children(extension._world, skull)
        -- THE MOTION PROBE (19 September, 14:44: "skulls are still
        -- flickering" after the body's flicker was found to be two
        -- timelines -- the view on the fixed-step body anchor, the copy on
        -- the avatar's interpolated root). While the owner moves, the
        -- step since the previous frame of: the companion's own root (the
        -- game's), the drawn offset this module adds, the eye the view is
        -- built on, and the owner's root. The one whose cadence differs
        -- from the eye's (0 then a double step on alternate frames) is on
        -- the other timeline. Budgeted; nothing else changes.
        local owner = local_player_unit()
        local eye = owner and presentation.eye_pose and presentation.eye_pose(owner)
        if owner and eye and skull_motion_lines < 2000 then
            local root_now = Unit.world_position(skull, 1)
            local owner_now = Unit.world_position(owner, 1)
            local drawn_now = Vector3(drawn[1], drawn[2], drawn[3])
            local probe = record.probe
            if probe then
                local d_owner = Vector3.distance(owner_now, probe.owner:unbox())
                if d_owner > 0.005 then
                    skull_motion_lines = skull_motion_lines + 1
                    mod:info("DARKTIDEVR_SKULL_MOTION d_owner_root_m=%.4f d_eye_m=%.4f d_skull_root_m=%.4f d_drawn_m=%.4f d_skull_rel_eye_m=%.4f",
                        d_owner, Vector3.distance(eye, probe.eye:unbox()), Vector3.distance(root_now, probe.root:unbox()),
                        Vector3.distance(drawn_now, probe.drawn:unbox()),
                        Vector3.distance(root_now + drawn_now - eye, probe.root:unbox() + probe.drawn:unbox() - probe.eye:unbox()))
                end
                probe.owner:store(owner_now); probe.eye:store(eye); probe.root:store(root_now); probe.drawn:store(drawn_now)
            else
                record.probe = {owner = Vector3Box(owner_now), eye = Vector3Box(eye), root = Vector3Box(root_now), drawn = Vector3Box(drawn_now)}
            end
        end
    end
    local function unplace(record, skull)
        if not record or not record.nodes or not record.base or not skull or not Unit.alive(skull) then return end
        for _, node in ipairs(record.nodes) do
            local written, base = record.written and record.written[node], record.base[node]
            -- The rotation goes back FIRST and outside the position test.
            -- A skipped position restore self-heals, because whatever moved it
            -- keeps driving it; a skipped rotation restore does not, because
            -- nothing else writes it -- the skull would stay visibly cocked
            -- for the rest of the mission. The first cut had this inside the
            -- guard with a comment claiming it was outside (review, 18 Sept).
            local rest = record.base_rotation and record.base_rotation[node]
            if rest then Unit.set_local_rotation(skull, node, rest:unbox()) end
            if written and base and Vector3.distance(Unit.local_position(skull, node), written:unbox()) < 1e-5 then
                Unit.set_local_position(skull, node, base:unbox())
            end
        end
        record.base, record.written, record.base_rotation = nil, nil, nil
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
        if throw and not thrower then
            -- The skull is gone and the record goes with it, but say so: with
            -- a tumble in play this is the one path that could strand a
            -- rotation on a unit nobody can reach any more.
            mod:info("DARKTIDEVR_SKULL_THROW dropped=record reason=no_companion")
        end
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

    -- Feed the stock update. What is changed is written into `undo` as it is
    -- changed, so the caller can take everything back even when this errors
    -- half way (the settings tables are shared by every player's skulls).
    local function feed(extension, skull, record, owner, t, thrower, undo)
        local frame = owner_frame(owner, t)
        if not frame then return end
        local fov = tonumber(extension._fov_multiplier)
        fov = (fov and fov > 0.1) and fov or 1
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
        for _, field in ipairs({"_first_person_movement_settings", "_third_person_movement_settings"}) do
            local settings = extension[field]
            local position = type(settings) == "table" and settings.position
            if type(position) == "table" then
                local saved = {}
                record.boxes[field] = record.boxes[field] or {}
                for name, box in pairs(position) do
                    saved[name] = box
                    local v = box:unbox()
                    local fed = hold and {hold[1] / fov, hold[2], hold[3]} or
                        Skull.fed_offset({Vector3.x(v), Vector3.y(v), Vector3.z(v)}, mirror,
                            thrower and Skull.FORWARD or nil, frame.lead, frame.heading, fov)
                    local mine = record.boxes[field][name]
                    if not mine then mine = Vector3Box(0, 0, 0); record.boxes[field][name] = mine end
                    mine:store(Vector3(fed[1], fed[2], fed[3]))
                end
                -- Recorded before the swap, so an error during it is undone too.
                undo.tables[#undo.tables + 1] = {position = position, saved = saved}
                for name in pairs(saved) do position[name] = record.boxes[field][name] end
            end
        end
        -- Held: the stock smoothing of the offset would trail the hand by
        -- half a second, and its smoothing of the heading would swing the
        -- offset off the hand whenever the lazy heading moves; both states
        -- are put where they would settle (the offset's is kept after the
        -- field-of-view factor, so it is not divided).
        local heading = frame.heading
        local smoothing = extension._companion_position_offset
        if hold and smoothing and smoothing.store then
            smoothing:store(Vector3(hold[1], hold[2], hold[3]))
            extension.smoothed_forward = Vector3Box(Vector3(-math.sin(heading), math.cos(heading), 0))
        end
        undo.first_person = frame.first_person
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
    end
    local function unfeed(undo)
        if not undo then return end
        if undo.first_person then rawset(undo.first_person, "extrapolated_rotation", undo.shadowed) end
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
                -- One axis per throw, drawn here so it is steady for its whole
                -- flight rather than re-rolled every frame.
                tumble_axis = Skull.random_axis(math.random(), math.random()),
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
                -- ONE TIMELINE WITH THE VIEW (19 September, 14:57 probe: the
                -- companion's own root steps 8 cm every frame, the eye 0
                -- then 4 cm on alternate frames -- the view is on the
                -- fixed-step body anchor and the skull on the game's
                -- interpolated root, and "skulls are still flickering").
                -- The drawn skull is the real one pulled back by the
                -- anchor's lag this frame (first-person unit minus the
                -- fixed-step component position), so it steps with the
                -- view as the hands and the weapon do. The real root is
                -- untouched; the bridge still starts from it.
                local lag = anchor_lag(local_player_unit())
                -- AN ACTUAL GRAB (user, 17:45, 19 September: "grabbing the
                -- flamer skull [should] be an actual grab ... it should be
                -- against the side of the skull and the skull should turn
                -- with the hand"). While the off hand holds it, the skull
                -- is rigid to the hand: on the frame the hold begins, the
                -- vector from the hand to the skull's drawn centre is taken
                -- in the hand's frame and set to the skull's radius, so the
                -- palm sits on its side wherever it was grabbed from, and
                -- the hand's rotation is taken as the zero. Every held
                -- frame after: centre = hand + hand_rotation * that vector,
                -- and the skull turns by hand_rotation * inverse(zero)
                -- about its centre. The stock movement is still fed the
                -- hold (feed), so the real root follows; the drawn parts
                -- are what the hand holds. Released, the grab is dropped
                -- and the throw or the bridge takes over.
                local grabbed = false
                if thrower and held(t) and hand_track.position and hand_track.rotation then
                    local hand = Vector3(hand_track.position[1], hand_track.position[2], hand_track.position[3])
                    local hand_rotation = hand_track.rotation:unbox()
                    if not record.grab then
                        local centre = lag and Vector3(real[1] - lag[1], real[2] - lag[2], real[3] - lag[3]) or Vector3(real[1], real[2], real[3])
                        local in_hand = Quaternion.rotate(Quaternion.inverse(hand_rotation), centre - hand)
                        local length = Vector3.length(in_hand)
                        if length < 1e-3 then in_hand = Vector3(0, 0, Skull.GRAB_RADIUS); length = Skull.GRAB_RADIUS end
                        in_hand = in_hand * (math.max(Skull.GRAB_HOLD_MIN, math.min(Skull.GRAB_HOLD_MAX, length)) / length)
                        record.grab = {offset = Vector3Box(in_hand), zero = QuaternionBox(hand_rotation)}
                        mod:info("DARKTIDEVR_SKULL_THROW grabbed offset_m=%.3f,%.3f,%.3f", Vector3.x(in_hand), Vector3.y(in_hand), Vector3.z(in_hand))
                    end
                    local centre = hand + Quaternion.rotate(hand_rotation, record.grab.offset:unbox())
                    local delta = Quaternion.multiply(hand_rotation, Quaternion.inverse(record.grab.zero:unbox()))
                    local x, y, z, w = Quaternion.to_elements(delta)
                    local axis, angle = Skull.axis_angle(x, y, z, w)
                    place(extension, skull, record.bridge_nodes, {Vector3.x(centre), Vector3.y(centre), Vector3.z(centre)},
                        axis and Vector3(axis[1], axis[2], axis[3]) or nil, angle)
                    grabbed = true
                else
                    record.grab = nil
                end
                if not grabbed then
                    if lag then
                        place(extension, skull, record.bridge_nodes, {real[1] - lag[1], real[2] - lag[2], real[3] - lag[3]})
                    else
                        unplace(record.bridge_nodes, skull)
                    end
                end
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
        -- The tumble eases out with the blend: a skull still spinning as it
        -- settles onto its real position reads as broken rather than thrown.
        -- Integrated rather than scaled, so the angle only ever grows, and on
        -- the axis drawn when this throw started so it is steady for it.
        local dt = throw.tumble_t and (t - throw.tumble_t) or 0
        throw.tumble_t = t
        local rate = Skull.tumble_rate(throw.velocity)
        if rate and throw.tumble_axis then
            throw.tumble_angle = Skull.tumbled_angle(throw.tumble_angle, rate, weight, dt)
        end
        -- Step the free flight and sweep it. The first frame starts it at the
        -- release with the release velocity; after that it carries its own
        -- state, because a bounce cannot be recovered from a closed form.
        if not throw.free_position then
            throw.free_position = {throw.release[1], throw.release[2], throw.release[3]}
            throw.free_velocity = {throw.velocity[1], throw.velocity[2], throw.velocity[3]}
        end
        local bounced
        throw.free_position, throw.free_velocity, bounced =
            swept_step(extension, throw.free_position, throw.free_velocity, dt)
        if bounced and not throw.bounce_logged then
            throw.bounce_logged = true
            mod:info("DARKTIDEVR_SKULL_THROW bounced elapsed_s=%.3f speed=%.2f", elapsed,
                math.sqrt(throw.free_velocity[1] ^ 2 + throw.free_velocity[2] ^ 2 +
                    throw.free_velocity[3] ^ 2))
        end
        place(extension, skull, throw,
            Skull.drawn_position(throw.release, throw.velocity, elapsed, real, weight,
                throw.free_position),
            throw.tumble_axis, throw.tumble_angle)
    end

    -- One error used to switch this module off for the rest of the session,
    -- and that is how a bug in a purely cosmetic bounce cost a player their
    -- skull side mirroring as well as their throw (worn, 18 September). The
    -- mirroring and the hold pose are the parts people actually rely on; the
    -- drawn flight is decoration.
    --
    -- So: three strikes rather than one, and a level load gives it another
    -- chance -- the same shape as the re-armed displays, which were switched
    -- off permanently by a single error until 18 September for the same
    -- reason. A run of errors still stands the module down, because a module
    -- erroring every frame is worse than one that is off.
    local failures, failed = 0, false
    local function note_failure()
        failures = failures + 1
        if failures >= Skull.MAX_CONSECUTIVE_FAILURES then
            failed = true
            mod:warning("DARKTIDEVR_SKULL_THROW stood_down after=%d consecutive errors", failures)
        end
    end
    local function note_success()
        failures = 0
    end
    -- A level load re-arms it: whatever the errors were about is gone with the
    -- world they happened in.
    function api.rearm()
        if failed then mod:info("DARKTIDEVR_SKULL_THROW rearmed=level_load") end
        failures, failed = 0, false
    end
    local function hook_class(class)
        if not class or logged[class] then return end
        logged[class] = true
        -- One hook (a mod's second hook on a method is ignored): it wraps the
        -- stock update so the fed inputs are in place for its length only.
        mod:hook(class, "post_update", function(func, self, unit, ...)
            -- As the stock update's own first line: the system still calls
            -- it for a unit already dead, and engine calls on one assert.
            if failed or not ALIVE[unit] then return func(self, unit, ...) end
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
            local undo = {tables = {}}
            if following then
                local ok, feed_err = pcall(feed, self, unit, record, owner, t, thrower, undo)
                if not ok then
                    -- Taken back at once: the stock update then runs unfed.
                    pcall(unfeed, undo)
                    undo = {tables = {}}
                    note_failure()
                    mod:warning("DARKTIDEVR_SKULL_THROW feed_error=%s", tostring(feed_err))
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
                note_failure()
                pcall(unplace_all)
                mod:warning("DARKTIDEVR_SKULL_THROW error=%s", tostring(after_err))
            else
                note_success()
            end
        end)
    end
    if mod.hook_require then
        mod:hook_require("scripts/extension_systems/flying_companion_movement/flying_companion_movement_extension", hook_class)
        mod:hook_require("scripts/extension_systems/flying_companion_movement/flying_companion_husk_movement_extension", hook_class)
    end

    function api.destroy()
        pcall(unplace_all)
        -- The teardown between levels is also the re-arm: whatever the errors
        -- were about went with the world they happened in, and standing the
        -- module down for the rest of the SESSION costs the side mirroring and
        -- the hold pose, which are the parts people rely on.
        api.rearm()
        pending = nil; throw = nil; heading_state = nil; shared = nil; shared_t = nil; held_until = nil
    end
    return api
end

return Skull
