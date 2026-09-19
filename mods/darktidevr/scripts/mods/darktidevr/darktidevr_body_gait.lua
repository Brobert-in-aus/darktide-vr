-- Procedural gait for the drawn body (whole-body IK design, 14 September,
-- step 6; asked for on 19 September once the legs stopped following the
-- stock animation: "write a gait, and add things like a small step where
-- needed for small movements. Make sure 6dof still works too").
--
-- Pure. World space, Z up, Stingray yaw (forward = (-sin yaw, cos yaw, 0),
-- right = (cos yaw, sin yaw, 0)); positions are 3-arrays. The adapter in
-- darktidevr_body_mirror measures the rest offsets and the leg lengths from
-- the copy's own rig, feeds the copy's root each frame, and moves the leg
-- joints to the feet this returns. Nothing here reads the game.
--
-- How it walks. Each foot has a PLANTED world position and yaw and an IDEAL
-- place: the rest offset (hip-width to the side, a little forward or back)
-- turned to the root's heading and put on the ground. While a foot is
-- planted it stays put -- that is what makes the body walk rather than
-- slide. When a planted foot is farther from its ideal than STEP_TRIGGER_M,
-- or the root has turned more than TURN_TRIGGER from the foot's yaw, and
-- the other foot is not mid-step, it steps: to the ideal place pushed along
-- the root's velocity by LEAD_S, so it lands where the body will be rather
-- than where it was. One foot at a time, the farther one first; a foot that
-- has just landed leaves the other one the farther, so they alternate. The
-- swing eases in and out over a duration that shortens with speed, lifting
-- in an arc whose height scales with the step so a shuffle stays low.
--
-- Small movements. The design's trigger was a 0.18 m radius about the
-- midpoint of the feet, which would have let the root wander that far --
-- half a metre between the feet's stances -- before anything moved. The
-- trigger here is per foot and 0.08 m, so an 8 cm drift of the root (a
-- lean, a shuffle, a step across the room) is answered with an 8 cm step,
-- and the arc is proportionally low. That is also what makes six degrees of
-- freedom work: room-scale movement reaches the copy's root through the
-- neck follow immediately (the collider follows through recorded inputs
-- later), so the feet step under it exactly as they step under stick
-- locomotion, from the same root motion, with no separate path.
--
-- Ground. The design raycasts for it; this takes the ground height it is
-- given (the avatar's root, the simulated floor under the player), so on a
-- slope or a step the feet will float or sink by the height difference.
-- Written down as a limit rather than a surprise.
local Gait = {}

-- Per foot: farther than this from its ideal place, it steps.
Gait.STEP_TRIGGER_M = 0.08
-- Root heading this far from the foot's yaw: it re-plants (turning on the spot).
Gait.TURN_TRIGGER = math.rad(40)
-- The step lands where the ideal place will be this far ahead at the root's
-- velocity.
Gait.LEAD_S = 0.25
-- Swing duration at rest, its shortening per metre per second of speed, and
-- the clamp (design step 6).
Gait.DURATION_S, Gait.DURATION_PER_MPS = 0.35, 0.03
Gait.MIN_DURATION_S, Gait.MAX_DURATION_S = 0.18, 0.40
-- Lift at the middle of a full step, and the step length that earns it; a
-- shorter step lifts in proportion.
Gait.ARC_M, Gait.ARC_FULL_AT_M = 0.08, 0.30
-- No single step longer than this: the leg cannot reach it.
Gait.MAX_STEP_M = 0.80
-- Root velocity smoothing time constant, and the speed the lead is capped
-- at: a sprint is under this, and a spike above it is not a speed.
Gait.VELOCITY_TAU_S = 0.10
Gait.LEAD_MAX_MPS = 3.0
-- A root that moved this far in one frame did not walk there (a respawn, a
-- teleport, the first frame after a spawn): the feet re-plant under it and
-- the velocity starts again, rather than a step being led by the jump.
Gait.TELEPORT_M = 0.50
Gait.SIDES = {"left", "right"}

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function valid3(v) return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3]) end
local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end

-- The rest offsets are in the root's frame: x to the right, y forward, z
-- up, in metres at scale 1.
function Gait.new(rest_offsets)
    local state = {feet = {}, velocity = {0, 0, 0}, rest = {}}
    for _, side in ipairs(Gait.SIDES) do
        local offset = rest_offsets and rest_offsets[side]
        state.rest[side] = valid3(offset) and {offset[1], offset[2], offset[3]} or {side == "left" and -0.1 or 0.1, 0, 0}
        state.feet[side] = {planted = nil, yaw = nil, swing = nil}
    end
    return state
end

-- A foot's ideal place on the ground for this root, heading and scale.
function Gait.ideal(root, yaw, offset, ground_z, scale)
    local s = finite(scale) and scale > 0 and scale or 1
    local c, sn = math.cos(yaw), math.sin(yaw)
    local x, y = offset[1] * s, offset[2] * s
    return {root[1] + c * x - sn * y, root[2] + sn * x + c * y, ground_z}
end

function Gait.duration(speed)
    local d = Gait.DURATION_S - Gait.DURATION_PER_MPS * math.max(0, speed or 0)
    return math.max(Gait.MIN_DURATION_S, math.min(Gait.MAX_DURATION_S, d))
end

function Gait.ease(p)
    p = math.max(0, math.min(1, p))
    return p * p * (3 - 2 * p)
end

-- Lift above the ground at swing progress p for a step of this length.
function Gait.arc(p, length)
    local share = math.max(0, math.min(1, (length or 0) / Gait.ARC_FULL_AT_M))
    return Gait.ARC_M * share * math.sin(math.pi * math.max(0, math.min(1, p)))
end

local function planar_distance(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
end

-- One frame. root: the copy's root (3-array, world); yaw: its heading;
-- ground_z: the floor under the player; scale: the copy's uniform scale.
-- Returns, per side, {position = {x,y,z}, yaw, swinging, progress, stepped}
-- where `stepped` is true on the frame a step started.
function Gait.update(state, root, yaw, ground_z, t, dt, scale)
    if not valid3(root) or not finite(yaw) or not finite(ground_z) or not finite(t) then return nil end
    -- Root velocity, smoothed, planar. A jump of TELEPORT_M or more in one
    -- frame is not motion: the feet re-plant under the new root and the
    -- velocity starts from nothing.
    local teleported = false
    if state.root_previous then
        local jump = planar_distance(root, state.root_previous)
        if jump >= Gait.TELEPORT_M then
            teleported = true
            state.velocity = {0, 0, 0}
        elseif finite(dt) and dt > 0 then
            local vx, vy = (root[1] - state.root_previous[1]) / dt, (root[2] - state.root_previous[2]) / dt
            local k = 1 - math.exp(-dt / Gait.VELOCITY_TAU_S)
            state.velocity[1] = state.velocity[1] + (vx - state.velocity[1]) * k
            state.velocity[2] = state.velocity[2] + (vy - state.velocity[2]) * k
        end
    end
    state.root_previous = {root[1], root[2], root[3]}
    local speed = math.sqrt(state.velocity[1] ^ 2 + state.velocity[2] ^ 2)
    -- The lead is along the velocity, at most LEAD_MAX_MPS of it.
    local lead_x, lead_y = state.velocity[1], state.velocity[2]
    if speed > Gait.LEAD_MAX_MPS then
        lead_x, lead_y = lead_x * Gait.LEAD_MAX_MPS / speed, lead_y * Gait.LEAD_MAX_MPS / speed
    end
    local out, swinging_side = {}, nil
    -- Advance any swing, land it when done.
    for _, side in ipairs(Gait.SIDES) do
        local foot = state.feet[side]
        local ideal = Gait.ideal(root, yaw, state.rest[side], ground_z, scale)
        if not foot.planted or teleported then foot.planted, foot.yaw, foot.swing = ideal, yaw, nil end
        local swing = foot.swing
        if swing then
            local p = (t - swing.t0) / swing.duration
            if p >= 1 then
                foot.planted, foot.yaw, foot.swing = swing.to, swing.to_yaw, nil
            else
                swinging_side = side
                local e = Gait.ease(p)
                out[side] = {position = {swing.from[1] + (swing.to[1] - swing.from[1]) * e,
                    swing.from[2] + (swing.to[2] - swing.from[2]) * e,
                    ground_z + Gait.arc(p, swing.length)},
                    yaw = swing.to_yaw, swinging = true, progress = p, stepped = false}
            end
        end
        foot.ideal = ideal
    end
    -- Start a step: the farther foot, if either is out of place and no foot
    -- is mid-air.
    if not swinging_side then
        local best, best_error = nil, -1
        for _, side in ipairs(Gait.SIDES) do
            local foot = state.feet[side]
            local error = planar_distance(foot.ideal, foot.planted)
            local turned = math.abs(wrap(yaw - foot.yaw)) > Gait.TURN_TRIGGER
            if (error > Gait.STEP_TRIGGER_M or turned) and error > best_error then
                best, best_error = side, error
            end
        end
        if best then
            local foot = state.feet[best]
            local to = {foot.ideal[1] + lead_x * Gait.LEAD_S,
                foot.ideal[2] + lead_y * Gait.LEAD_S, ground_z}
            local length = planar_distance(to, foot.planted)
            if length > Gait.MAX_STEP_M then
                local k = Gait.MAX_STEP_M / length
                to = {foot.planted[1] + (to[1] - foot.planted[1]) * k,
                    foot.planted[2] + (to[2] - foot.planted[2]) * k, ground_z}
                length = Gait.MAX_STEP_M
            end
            foot.swing = {from = {foot.planted[1], foot.planted[2], ground_z}, to = to, to_yaw = yaw,
                t0 = t, duration = Gait.duration(speed), length = length}
            out[best] = {position = {foot.planted[1], foot.planted[2], ground_z}, yaw = yaw,
                swinging = true, progress = 0, stepped = true}
        end
    end
    for _, side in ipairs(Gait.SIDES) do
        local foot = state.feet[side]
        if not out[side] then
            out[side] = {position = {foot.planted[1], foot.planted[2], ground_z}, yaw = foot.yaw,
                swinging = false, progress = nil, stepped = false}
        end
    end
    out.speed = speed
    return out
end

return Gait
