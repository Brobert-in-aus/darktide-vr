-- Body mirror (dev flag darktidevr_body_mirror.flag "mirror"; full-body IK
-- design, milestone 2, 15 September). Spawns a presentation-only copy of the
-- player's whole character profile (every body, gear and material slot, no
-- weapons) with the body proxy's UIProfileSpawner, stops its own animation
-- the moment it is ready (scan2: that freezes the pose), and every frame
-- copies every joint's local pose from the gameplay avatar onto it. It stands
-- MIRROR_DISTANCE ahead of the avatar, facing it, so an eye render shows
-- whether the full profile spawns with its cosmetics and follows the avatar's
-- pose. Nothing else changes: the avatar, gloves, proxy and visibility code
-- are untouched. Players never have the flag.
--
-- Flag "overlaycopy" (milestone 2 proper, no IK): the same copy stands exactly
-- on the avatar, facing its way, with the head, face and headgear slots hidden
-- so the eye cameras are not inside them. In the default hands mode the
-- avatar already hides every body slot, so this shows whether the full
-- profile reads as the player's own body with no double body. The plain copy
-- stretches the sleeves to the gloves (overlay2: 0.6-0.8 m from forearm to
-- hand against a 0.275 m bone).
--
-- Flag "overlay": the same, then each arm is re-solved as two bones of their
-- spawned lengths so the hand reaches the avatar's hand (which carries the
-- weapon and sits on the glove), bending toward the stock animated elbow.
-- Swing only: the forearm roll joints are not twisted yet. It also hides the
-- meshes near the eye (design, "What the player sees in first person"):
-- overlay5 looking down showed the empty collar ring where the hidden head
-- was. "overlayarms" is the arm solve without that hiding, for A/B.
--
-- Overlay modes make the copy the hand rig (BodyProxy.set_hand_rig): the
-- glove units are removed, every hand placement records one final wrist pose
-- per side, and both the weapons' hand joints and the copy's arms follow
-- that pose, so there is one pair of hands and the hand stays on the gun
-- (user, 15 September). Out of reach, the arm straightens and the hand is
-- still put on the pose, stretching the wrist.
--
-- "overlay" also moves the copy so its neck sits at the body frame's neck (7
-- cm behind and 8 cm below the eye): overlay6 found the camera about 21 cm
-- above the copy's head, looking down into the collar, which is part of the
-- torso mesh and cannot be hidden alone. The root never lifts: overlay7
-- lifted it 27-48 cm to reach a camera taller than the model and put the eye
-- inside the hood and cloak. It moves sideways and down only, so the feet
-- stay on the floor or sink (crouch) until the legs are solved (milestone 3).
--
-- "overlay" also scales the copy up (uniformly, about its root on the floor)
-- until its neck reaches the body frame's neck height: overlay8 looking down
-- still showed the open collar ring of the chest armour, because the camera
-- sat about 27 cm above the model's neck; collapsing the neck joint's scale
-- (overlay9) did not close it. The ratio eases toward its target, never
-- shrinks below the avatar's own scale (a crouch lowers instead) and is
-- capped. "overlayfollow" is the same without scaling, for A/B.
--
-- With the neck at eye height the eye sits inside the hood and cloak, which
-- are part of the torso mesh (overlay10). Collapsing the head (overlay11) or
-- neck (overlay12) joint's scale did not fold the cowl, which is skinned to
-- the spine. overlay14 put the neck a further 15 cm back to keep the eye in
-- front of the cowl; the user chose the proper camera place instead ("players
-- can switch equipment"), so the neck sits at the body frame's own neck.
local Mirror = {}

Mirror.FLAG = "./../mods/darktidevr/darktidevr_body_mirror.flag"
Mirror.MIRROR_DISTANCE = 2.5
Mirror.KEPT_SLOT_TYPES = {body = true, gear = true, material = true}
Mirror.MODES = {
    mirror = {distance = Mirror.MIRROR_DISTANCE, facing = true, hide_head = false},
    overlaycopy = {distance = 0, facing = false, hide_head = true, solve_arms = false, hand_rig = true},
    overlayarms = {distance = 0, facing = false, hide_head = true, solve_arms = true, hand_rig = true},
    overlayfollow = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true, hand_rig = true,
        follow_neck = true},
    overlay = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true, hand_rig = true,
        follow_neck = true, scale_to_neck = true, clavicles = true, body_yaw = true,
        protract = true, stretch = true},
    -- Milestone 3, spine (step 3): "overlay" with the spine bent so the neck
    -- reaches the body frame's neck, instead of moving the whole copy there;
    -- the root stays over the avatar's feet.
    overlayspine = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true,
        hand_rig = true, follow_neck = true, scale_to_neck = true, clavicles = true, body_yaw = true,
        spine_bend = true},
    -- "overlay" with a 45 degree clavicle cap: with tracked input the 30 degree
    -- cap bound on both sides (follow3: 13 cm gaps), for A/B.
    overlayreach = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true,
        hand_rig = true, follow_neck = true, scale_to_neck = true, clavicles = true, body_yaw = true,
        clavicle_max = math.rad(45)},
    -- Arm length from the calibration (arm length design, step 3): "overlay"
    -- with the forearm and hand bones moved to the calibrated upper arm and
    -- forearm lengths after the uniform scale. The clamp is wider than the
    -- design default so the effect shows past the scale to the neck.
    overlayarmlength = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true,
        hand_rig = true, follow_neck = true, scale_to_neck = true, clavicles = true, body_yaw = true,
        arm_length = {min = 0.70, max = 1.15}},
    -- Arm length design step 4: "overlay" with the clavicle swing toward the
    -- estimated shoulders replaced by FRIK-style protraction toward the hand
    -- near full reach.
    overlayprotract = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true,
        hand_rig = true, follow_neck = true, scale_to_neck = true, body_yaw = true, protract = true, stretch = true},
    -- "overlay" with the clavicle swing only, for A/B of protraction and the
    -- soft stretch (both4 against follow3).
    overlayswing = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true,
        hand_rig = true, follow_neck = true, scale_to_neck = true, clavicles = true, body_yaw = true},
    -- The body at the player's own proportions (18 September). No uniform
    -- scale at all: the spine bends to bring the neck to the head, so the
    -- shoulders stay where the player's shoulders are, and the arms take
    -- their calibrated lengths. Scaling the whole copy 1.21 to 1.30 to reach
    -- the neck is what put its shoulders where no true arm could reach the
    -- hands (unattended-results-2026-09-18.md), so the two changes only make
    -- sense together. Dev flag only, for measurement.
    overlaytrue = {distance = 0, facing = false, hide_head = true, solve_arms = true,
        near_eye = true, hand_rig = true, follow_neck = true, clavicles = true,
        body_yaw = true, spine_bend = true, protract = true, stretch = true,
        arm_length = {min = 0.70, max = 1.20}},
    -- "overlay" with clavicles but the avatar's root yaw, for A/B of the body yaw.
    overlayrootyaw = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true,
        hand_rig = true, follow_neck = true, scale_to_neck = true, clavicles = true},
    -- The mirror key's copy (user, 17 September worn: the first one "doesn't
    -- mirror my IK except the hands ... it should match my IK identically, a
    -- true mirror", and it "glitches around when I move"). It is posed by the
    -- whole overlay pipeline (the neck, the scale, the clavicles, the arms
    -- solved to the same wrist poses), so it is the body the overlay draws,
    -- head included, and only then turned about the player and stood
    -- MIRROR_DISTANCE ahead (Mirror.reflected_root). It is placed from the
    -- tracked head through the body frame, as the overlay is, not from the
    -- avatar's root, whose fixed-step position is what jumped about. It is
    -- never the hand rig: it runs beside the overlay, in its own instance of
    -- this module.
    reflection = {distance = 0, facing = false, hide_head = false, solve_arms = true, follow_neck = true,
        scale_to_neck = true, clavicles = true, body_yaw = true, protract = true, stretch = true, reflect = true},
    -- "overlay" without the clavicle swing, for A/B (milestone 3).
    overlaystock = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true,
        hand_rig = true, follow_neck = true, scale_to_neck = true},
}
-- Milestone 3, clavicles (full-body design, "Solve per frame", step 5): each
-- clavicle (j_leftshoulder, j_rightshoulder) swings its upper arm root toward
-- the body frame's estimated shoulder, by at most CLAVICLE_MAX, before the arm
-- solve. rig1 showed the stock animated shoulders leave the support arm up to
-- 0.31 m short.
Mirror.CLAVICLE_MAX = math.rad(30)
-- Protraction (arm length design, step 4; FRIK moves the shoulder up to 8 % of
-- arm length toward the hand): none below PROTRACT_START of the arm's length
-- from shoulder to hand, rising to PROTRACT_SHARE of it by PROTRACT_FULL.
Mirror.PROTRACT_START, Mirror.PROTRACT_FULL, Mirror.PROTRACT_SHARE = 0.9, 1.1, 0.08
-- Soft stretch (arm length design, step 4; FRIK and VRIK stretch, CHI 2024):
-- past full reach both segments lengthen in proportion, by at most
-- STRETCH_SHARE of the arm's length; the wrist takes the rest.
Mirror.STRETCH_SHARE = 0.20
-- The spine chain bent toward the body frame's neck, lowest joint first, with
-- the design's share of the bend per joint and a per-joint cap.
Mirror.SPINE = {{"j_spine", 0.2}, {"j_spine1", 0.3}, {"j_spine2", 0.5}}
Mirror.SPINE_JOINT_MAX = math.rad(30)
-- Milestone 3, root yaw (step 1): the copy faces the body frame's yaw instead
-- of the avatar root's, which follows the aim. clav1 showed the left shoulder
-- 0.23 m from its estimate against 0.10 m on the right, a turn between them.
-- Near-eye mesh hiding, in the character root's frame at the spawn pose.
Mirror.NEAR_EYE_RADIUS = 0.25
Mirror.EYE_ABOVE_HEAD = 0.07
Mirror.EYE_FORWARD_OF_HEAD = 0.08
-- A box this large (largest half extent) is a whole garment such as the
-- torso: hiding it would remove the body, so it is kept and logged.
Mirror.NEAR_EYE_MAX_HALF_EXTENT = 0.30
-- Largest root move toward the body frame's neck.
Mirror.NECK_FOLLOW_MAX = 0.5
Mirror.MAX_BODY_SCALE_RATIO = 1.3
-- Per second: the fraction of the remaining scale change applied.
Mirror.BODY_SCALE_RATE = 1.0

-- The body scale ratio that brings the copy's neck height (above its root)
-- to the target neck height, from 1 (never smaller) to the cap, eased from
-- the previous ratio by dt. Pure.
function Mirror.scale_ratio(previous, neck_height, target_height, dt)
    local target = 1
    if neck_height > 0.1 and target_height > 0 then
        target = math.max(1, math.min(Mirror.MAX_BODY_SCALE_RATIO, target_height / neck_height))
    end
    if not previous then return target end
    local k = math.max(0, math.min(1, (dt or 0) * Mirror.BODY_SCALE_RATE))
    return previous + (target - previous) * k
end

-- The root move that puts the copy's neck on the target neck, never upward
-- unless allow_lift, capped in length. Arrays. Returns offset, uncapped
-- length. Pure.
function Mirror.neck_offset(neck, target, allow_lift)
    local offset = {target[1] - neck[1], target[2] - neck[2], target[3] - neck[3]}
    if not allow_lift and offset[3] > 0 then offset[3] = 0 end
    local length = math.sqrt(offset[1] ^ 2 + offset[2] ^ 2 + offset[3] ^ 2)
    if length > Mirror.NECK_FOLLOW_MAX then
        local k = Mirror.NECK_FOLLOW_MAX / length
        offset = {offset[1] * k, offset[2] * k, offset[3] * k}
    end
    return offset, length
end

-- Whether a mesh is hidden as near the eye: its box centre within the radius
-- of the eye and above the shoulder line, and the box not a whole garment.
-- Arrays in the root frame (z up). Returns hide, distance, reason. Pure.
function Mirror.near_eye(centre, half_extents, eye, shoulder_height)
    local distance = math.sqrt((centre[1] - eye[1]) ^ 2 + (centre[2] - eye[2]) ^ 2 + (centre[3] - eye[3]) ^ 2)
    if distance > Mirror.NEAR_EYE_RADIUS then return false, distance, "far" end
    if centre[3] < shoulder_height then return false, distance, "below_shoulders" end
    if math.max(half_extents[1], half_extents[2], half_extents[3]) > Mirror.NEAR_EYE_MAX_HALF_EXTENT then
        return false, distance, "too_large"
    end
    return true, distance, "near_eye"
end
Mirror.ARM_SIDES = {"left", "right"}
-- Added to the stock elbow as the bend hint, so a straight stock arm still
-- bends downward.
Mirror.ELBOW_HINT_DOWN = 0.10

local function sub(a, b) return {a[1] - b[1], a[2] - b[2], a[3] - b[3]} end
local function add(a, b) return {a[1] + b[1], a[2] + b[2], a[3] + b[3]} end
local function scale(a, k) return {a[1] * k, a[2] * k, a[3] * k} end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function length(a) return math.sqrt(dot(a, a)) end

-- Two-bone arm: where the elbow goes so the upper and lower bones keep their
-- lengths and the hand reaches the target, bending toward the hint. Out of
-- reach the arm points at the target and the hand stops at full reach.
-- Returns elbow, hand, reachable (arrays), or nil for degenerate input. Pure.
function Mirror.elbow(shoulder, hint, target, upper, lower)
    if not (upper > 0 and lower > 0) then return nil end
    local to_target = sub(target, shoulder)
    local distance = length(to_target)
    if distance < 1e-6 then return nil end
    local direction = scale(to_target, 1 / distance)
    local near, far = math.abs(upper - lower) + 1e-4, (upper + lower) * 0.999
    local reachable = distance >= near and distance <= far
    local d = math.max(near, math.min(far, distance))
    local cosine = math.max(-1, math.min(1, (upper * upper + d * d - lower * lower) / (2 * upper * d)))
    local sine = math.sqrt(1 - cosine * cosine)
    local offset = sub(hint, shoulder)
    local bend = sub(offset, scale(direction, dot(offset, direction)))
    if length(bend) < 1e-6 then
        bend = sub({0, 0, -1}, scale(direction, -direction[3]))
        if length(bend) < 1e-6 then bend = {1, 0, 0} end
    end
    bend = scale(bend, 1 / length(bend))
    local elbow = add(shoulder, add(scale(direction, upper * cosine), scale(bend, upper * sine)))
    return elbow, add(shoulder, scale(direction, d)), reachable
end

-- The swing that turns a clavicle so its upper arm root moves toward the
-- target shoulder: a unit axis and an angle, at most max_angle. nil when
-- nothing to turn. 3-arrays. Pure.
function Mirror.clavicle_swing(clavicle, arm, target, max_angle)
    local from, to = sub(arm, clavicle), sub(target, clavicle)
    local from_length, to_length = length(from), length(to)
    if from_length < 1e-6 or to_length < 1e-6 then return nil end
    from, to = scale(from, 1 / from_length), scale(to, 1 / to_length)
    local axis = {from[2] * to[3] - from[3] * to[2], from[3] * to[1] - from[1] * to[3], from[1] * to[2] - from[2] * to[1]}
    local sine = length(axis)
    if sine < 1e-7 then return nil end
    local angle = math.atan2(sine, dot(from, to))
    return scale(axis, 1 / sine), math.min(angle, max_angle or Mirror.CLAVICLE_MAX)
end

-- How far the shoulder moves toward the hand, metres, for the shoulder-to-hand
-- distance and the arm's length. Pure.
function Mirror.protraction(distance, arm_length)
    if not (arm_length > 1e-4) or not (distance == distance) then return 0 end
    local t = (distance / arm_length - Mirror.PROTRACT_START) / (Mirror.PROTRACT_FULL - Mirror.PROTRACT_START)
    return math.max(0, math.min(1, t)) * Mirror.PROTRACT_SHARE * arm_length
end

-- The upper and lower segment ratios that stretch an arm toward a target
-- distance: 1 within reach, otherwise both scaled by the same factor, capped
-- at 1 + STRETCH_SHARE. Pure.
function Mirror.stretch_ratio(distance, upper, lower)
    local length = upper + lower
    if not (length > 1e-4) or not (distance == distance) or distance <= length then return 1 end
    return math.min(1 + Mirror.STRETCH_SHARE, distance / length)
end

-- The fraction of the remaining swing each joint of a chain takes, lowest
-- first, so the shares add up to the weights: w_i / (w_i + ... + w_n). Pure.
function Mirror.chain_fractions(chain)
    local fractions, remaining = {}, 0
    for i = #chain, 1, -1 do
        remaining = remaining + chain[i][2]
        fractions[i] = remaining > 0 and chain[i][2] / remaining or 0
    end
    return fractions
end

-- Where the copy's j_neck goes. The body frame's neck (7 cm behind and 8 cm
-- below the eye, along the head's own axes) is the skull's pivot, which suits
-- the shoulders of the virtual stock; the rig's j_neck is the base of the
-- neck, lower and further back. Matching one to the other stood the body
-- about 10 cm too high and 5 cm too far forward (user, 17 September worn:
-- "eyes are a bit too low, need to come up maybe 10cm, and forward maybe 5";
-- the log's scale ratios of 1.2 to 1.3 are the same error, the copy enlarged
-- to reach a neck that was too high). The extra is level and vertical, not
-- along the head's axes: the base of the neck does not swing with a nod.
-- Both scale with the frame's size. Pure.
Mirror.NECK_EXTRA_BACK, Mirror.NECK_EXTRA_DOWN = 0.05, 0.10
function Mirror.neck_target(neck, head_yaw, scale)
    if type(neck) ~= "table" then return nil end
    local s = (type(scale) == "number" and scale > 0) and scale or 1
    local fx, fy = 0, 0
    if type(head_yaw) == "number" and head_yaw == head_yaw then fx, fy = -math.sin(head_yaw), math.cos(head_yaw) end
    return {neck[1] - fx * Mirror.NECK_EXTRA_BACK * s, neck[2] - fy * Mirror.NECK_EXTRA_BACK * s,
        neck[3] - Mirror.NECK_EXTRA_DOWN * s}
end

-- The copy's heading eased toward the body frame's, which moves in steps (a
-- 20 degree dead zone, then a 0.15 s catch-up: right for the stock's
-- shoulders, a snap when it turns a whole drawn body; user, 17 September:
-- "snap turns as I turn rather than following smoothly"). A jump beyond
-- YAW_SNAP (a stick snap turn, a respawn) is taken at once. Pure.
Mirror.YAW_TAU, Mirror.YAW_SNAP = 0.3, math.rad(75)
function Mirror.smooth_yaw(previous, target, dt)
    if type(previous) ~= "number" or type(dt) ~= "number" or not (dt > 0) or dt > 0.5 then return target end
    local diff = (target - previous + math.pi) % (2 * math.pi) - math.pi
    if math.abs(diff) > Mirror.YAW_SNAP then return target end
    return (previous + diff * (1 - math.exp(-dt / Mirror.YAW_TAU)) + math.pi) % (2 * math.pi) - math.pi
end

-- One sample of the yaw chain, as degrees, for the trace below. Every yaw a
-- frame of the body passes through, in the order it passes through them:
--
--   head    the headset's own yaw, which is what the player sees turn
--   target  the body frame's target (head yaw pulled toward the hands)
--   frame   the body frame's smoothed yaw, after its dead zone and catch-up
--   mirror  after Mirror.smooth_yaw, which is what the copy's root is set to
--   avatar  the game character's yaw, which the copy is posed from
--   unit    the copy's root after everything, read back from the world
--
-- "Turning with stick turns the body faster than my view" has to be one of
-- these moving more per frame than `head` does. Reading the source has not
-- found which, twice, so the chain is measured instead. Pure.
function Mirror.yaw_sample(head, target, frame, mirror, avatar, unit)
    local function degrees(value)
        if type(value) ~= "number" or value ~= value then return nil end
        return math.deg((value + math.pi) % (2 * math.pi) - math.pi)
    end
    return {head = degrees(head), target = degrees(target), frame = degrees(frame),
        mirror = degrees(mirror), avatar = degrees(avatar), unit = degrees(unit)}
end

-- Whether this sample is worth a line: anything moved, or the heartbeat is
-- due. `steps` is a list of yaw steps in degrees (nil entries ignored) and
-- `root_step` the root's travel in metres (nil on the first sample, which is
-- always worth a line because it is the baseline every later step is read
-- against). Pure.
function Mirror.trace_due(steps, root_step, frames_since_line)
    if (frames_since_line or 0) >= Mirror.TRACE_HEARTBEAT_FRAMES then return true, "heartbeat" end
    if root_step == nil then return true, "first" end
    if root_step > Mirror.TRACE_MOVED_M then return true, "moved" end
    for _, step in ipairs(steps or {}) do
        if type(step) == "number" and step == step and
                math.abs(step) > Mirror.TRACE_MOVED_DEG then
            return true, "turned"
        end
    end
    return false, nil
end

-- The signed difference between two of those degree values, wrapped, or nil
-- when either is missing. The trace prints steps rather than absolutes because
-- the fault is a RATE: a body that turns faster than the view is one whose
-- step is bigger, and comparing absolutes across a wrap is how that gets
-- missed. Pure.
function Mirror.yaw_step(now, before)
    if type(now) ~= "number" or type(before) ~= "number" then return nil end
    return (now - before + 180) % 360 - 180
end

-- The root of a copy turned half a turn about the vertical through pivot and
-- stood distance ahead of it along heading (Stingray yaw): {x, y, z}, the
-- height kept. Its yaw is the copy's plus pi. 3-arrays. Pure.
function Mirror.reflected_root(root, pivot, heading, distance)
    local fx, fy = -math.sin(heading), math.cos(heading)
    return {2 * pivot[1] - root[1] + fx * distance, 2 * pivot[2] - root[2] + fy * distance, root[3]}
end

-- The mode to run: the dev flag's when it names one; else the mirror while
-- its key has toggled it on (Psykhanium only); else the full overlay while
-- the "Full body (experimental)" option is on; else none. The option used to
-- turn on the older headless third-person body, whose head floats above a
-- body of the character's own height (worn, 17 September); the overlay is
-- the body scaled so its neck reaches the player's head. Pure.
-- The yaw/position trace (below) is off unless this file says "enabled".
-- Players never have it; it is written by the unattended tooling and by hand
-- for a worn session that is meant to answer the body questions.
Mirror.TRACE_FLAG = "./../mods/darktidevr/darktidevr_body_trace.flag"
-- Every second frame while something is MOVING, and a heartbeat otherwise.
-- A flat every-Nth-frame trace spends its whole budget on the first hundred
-- seconds of standing in the hub, and the two things being looked for -- a
-- stick turn and a jitter -- may not have happened yet. The thresholds are
-- deliberately below what a person can see: half a millimetre of root travel
-- and a tenth of a degree of yaw, so a jitter too small to describe is still
-- above the line.
Mirror.TRACE_EVERY = 2
Mirror.TRACE_HEARTBEAT_FRAMES = 120
Mirror.TRACE_MOVED_M = 0.0005
Mirror.TRACE_MOVED_DEG = 0.1
Mirror.TRACE_MAX_LINES = 6000
Mirror.OPTION_MODE = "overlay"
function Mirror.requested_mode(flag_mode, mirror_toggled, in_psykhanium, option_on)
    if flag_mode and Mirror.MODES[flag_mode] then return flag_mode end
    if mirror_toggled == true and in_psykhanium == true then return "mirror" end
    if option_on == true then return Mirror.OPTION_MODE end
    return nil
end

-- The flag's mode, or nil. Pure.
function Mirror.parse_mode(value)
    local name = type(value) == "string" and value:match("^%s*(%a+)%s*$")
    return name and Mirror.MODES[name] and name or nil
end

-- Whether a spawned slot is hidden in this mode: head slots in overlay only,
-- from the caller's head slot lookup. Pure.
function Mirror.hides_slot(mode_name, slot_name, head_lookup)
    local mode = Mirror.MODES[mode_name]
    return mode ~= nil and mode.hide_head and type(head_lookup) == "table" and head_lookup[slot_name] == true
end

-- Whether the mirror spawns a slot: body, gear and material slots, plus the
-- unarmed slot the spawner needs for its wielded-slot plumbing. Pure.
function Mirror.keeps_slot(slot_name, settings)
    if slot_name == "slot_unarmed" then return true end
    if slot_name == "slot_companion_gear_full" then return false end
    return type(settings) == "table" and Mirror.KEPT_SLOT_TYPES[settings.slot_type] == true and
        not settings.ignore_character_spawning
end

-- Node correspondence between the avatar and the mirror: by index when both
-- rigs have the same node count and the probe joints sit at the same indices,
-- otherwise nil (the caller copies nothing and logs why). Pure over lookups.
function Mirror.same_layout(count_a, count_b, index_of_a, index_of_b, probes)
    if count_a ~= count_b or count_a < 2 then return false end
    for _, name in ipairs(probes) do
        if index_of_a(name) ~= index_of_b(name) then return false end
    end
    return true
end

function Mirror.install(mod, presentation, options)
    local api = {}
    -- The mirror key's copy is a second instance with its own state, run by
    -- the first: it only ever runs the "reflection" mode.
    local is_reflection = type(options) == "table" and options.reflection == true
    local reflection = not is_reflection and Mirror.install(mod, presentation, {reflection = true}) or nil
    local ArmLength
    local poll, enabled, mode_name = 0, false, nil
    local state
    -- This instance's own copy torn down (a mode change, a lost avatar, an
    -- error); api.destroy also takes the reflection's down.
    local destroy_own
    local logged = {}
    local mirror_toggled = false
    -- Polled like the other modules' test flags: a failed open on the main
    -- thread every frame is where these modules' spikes came from
    -- (docs/LUA-FRAME-PROFILE-2026-09-16.md).
    local trace_poll, trace_enabled, trace_lines, trace_previous = 0, false, 0, nil
    local trace_since_line = 0
    local function trace_flag()
        trace_poll = trace_poll - 1
        if trace_poll > 0 then return trace_enabled end
        trace_poll = 300
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Mirror.TRACE_FLAG, "r")
        if not file then trace_enabled = false; return false end
        local value = file:read(32) or ""
        file:close()
        trace_enabled = value:match("^%s*enabled%s*$") ~= nil
        return trace_enabled
    end
    local function in_psykhanium()
        local name = presentation.current_game_mode_name and presentation.current_game_mode_name()
        return name == "shooting_range" or name == "training_grounds"
    end
    local function flag()
        poll = poll - 1
        if poll > 0 then return enabled end
        poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = not is_reflection and io_api and io_api.open(Mirror.FLAG, "r")
        local parsed
        if file then
            local value = file:read("*all"); file:close()
            parsed = Mirror.parse_mode(value)
        end
        -- The mirror does not come back by itself on the next visit.
        if mirror_toggled and not in_psykhanium() then mirror_toggled = false end
        -- Not in the hub, whose own presentation (first or third person) is
        -- decided elsewhere and has no combat body to replace.
        local game_mode = presentation.current_game_mode_name and presentation.current_game_mode_name()
        local wanted
        if is_reflection then
            wanted = mirror_toggled and in_psykhanium() and "reflection" or nil
        else
            wanted = Mirror.requested_mode(parsed, false, false,
                mod.get and mod:get("vr_full_body_experimental") == true and game_mode ~= nil and game_mode ~= "hub")
        end
        if state and wanted ~= mode_name then destroy_own() end
        if wanted ~= mode_name then
            mod:info("DARKTIDEVR_BODY_MIRROR mode=%s flag=%s toggled=%s", tostring(wanted), tostring(parsed),
                tostring(mirror_toggled))
        end
        mode_name = wanted
        enabled = wanted ~= nil
        return enabled
    end
    -- The mirror key (F8 by default): a copy of your character standing ahead
    -- of you, facing you, in the Psykhanium. Returns the new state, or nil
    -- outside the Psykhanium.
    function api.toggle_mirror()
        if reflection then return reflection.toggle_mirror() end
        if not in_psykhanium() then return nil end
        mirror_toggled = not mirror_toggled
        poll = 0
        return mirror_toggled
    end
    local function body_proxy() return presentation.body_proxy end
    function destroy_own()
        if state and state.hand_rig and body_proxy() then body_proxy().set_hand_rig(nil) end
        if state then
            if state.profile_spawner then pcall(state.profile_spawner.destroy, state.profile_spawner) end
            if state.unit_spawner then pcall(state.unit_spawner.destroy, state.unit_spawner) end
        end
        state = nil
    end
    function api.destroy()
        destroy_own()
        if reflection then reflection.destroy() end
    end
    local function log_once(key, format, ...)
        if logged[key] then return end
        logged[key] = true
        mod:info("DARKTIDEVR_BODY_MIRROR " .. format, ...)
    end
    local function inverse(rotation)
        local x, y, z, w = Quaternion.to_elements(rotation)
        return Quaternion.from_elements(-x, -y, -z, w)
    end
    local function array(v) return {Vector3.x(v), Vector3.y(v), Vector3.z(v)} end
    local function vector(a) return Vector3(a[1], a[2], a[3]) end
    local function set_world_rotation(unit, index, rotation)
        local parent = Unit.scene_graph_parent(unit, index)
        local parent_rotation = parent and Unit.world_rotation(unit, parent) or Quaternion.identity()
        Unit.set_local_rotation(unit, index, Quaternion.multiply(inverse(parent_rotation), rotation))
    end
    -- Swing joint so the child joint points at the target position.
    local function aim_joint(world, unit, joint, child, target)
        local origin = Unit.world_position(unit, joint)
        local from, to = Unit.world_position(unit, child) - origin, target - origin
        local from_length, to_length = Vector3.length(from), Vector3.length(to)
        if from_length < 1e-6 or to_length < 1e-6 then return end
        from, to = from / from_length, to / to_length
        local axis = Vector3.cross(from, to)
        local sine = Vector3.length(axis)
        if sine < 1e-7 then return end
        local swing = Quaternion(axis / sine, math.atan2(sine, Vector3.dot(from, to)))
        set_world_rotation(unit, joint, Quaternion.multiply(swing, Unit.world_rotation(unit, joint)))
        World.update_unit(world, unit)
    end
    -- Hide near-eye meshes of every spawned slot unit and its attachments,
    -- logging each decision so a worn test can name wrong ones.
    --
    -- The eye is the player's real camera, not an estimate hung off the
    -- copy's head joint. The estimate was about 20 cm forward of where the
    -- camera actually is (`live_eye_root_local` in this module's own log),
    -- against a 0.25 m radius, and it was taken in the spawn pose before the
    -- copy was scaled and moved to the neck: every recorded run since the
    -- mode was built logged `hidden=0`, all 348 mesh decisions `far`. The
    -- scan is also deferred until the scale has settled (`ready_frames`),
    -- because before then the copy is still its spawned size.
    local function hide_near_eye(unit, data)
        if not (Unit.has_node(unit, "j_head") and Unit.has_node(unit, "j_leftarm")) then
            log_once("near_eye_nodes", "near_eye=skipped reason=nodes_missing")
            return
        end
        local root_inverse = Matrix4x4.inverse(Unit.world_pose(unit, 1))
        local function root_local(position) return array(Matrix4x4.transform(root_inverse, position)) end
        local head = root_local(Unit.world_position(unit, Unit.node(unit, "j_head")))
        local eye = {head[1], head[2] + Mirror.EYE_FORWARD_OF_HEAD, head[3] + Mirror.EYE_ABOVE_HEAD}
        local eye_source = "head_estimate"
        local first_person = state.avatar and ScriptUnit.has_extension(state.avatar, "first_person_system")
        local camera = first_person and first_person:first_person_unit()
        if camera and Unit.alive(camera) then
            eye = root_local(Unit.world_position(camera, 1))
            eye_source = "camera"
        end
        local shoulder_height = root_local(Unit.world_position(unit, Unit.node(unit, "j_leftarm")))[3]
        local hidden, total = 0, 0
        local function scan(slot_name, slot_unit)
            local pose = Unit.world_pose(slot_unit, 1)
            for index = 1, Unit.num_meshes(slot_unit) do
                local ok, box_pose, half = pcall(Mesh.box, Unit.mesh(slot_unit, index))
                if ok and box_pose and half then
                    total = total + 1
                    local centre = root_local(Matrix4x4.transform(pose, Matrix4x4.translation(box_pose)))
                    local hide, distance, reason = Mirror.near_eye(centre, array(half), eye, shoulder_height)
                    if hide then
                        Unit.set_mesh_visibility(slot_unit, index, false)
                        hidden = hidden + 1
                    end
                    if distance <= Mirror.NEAR_EYE_RADIUS * 2 then
                        mod:info("DARKTIDEVR_BODY_MIRROR near_eye slot=%s unit=%s mesh=%d centre=%.3f,%.3f,%.3f half=%.3f,%.3f,%.3f eye_m=%.3f decision=%s",
                            slot_name, tostring(Unit.get_data(slot_unit, "unit_name") or slot_unit), index,
                            centre[1], centre[2], centre[3], Vector3.x(half), Vector3.y(half), Vector3.z(half), distance, reason)
                    end
                end
            end
        end
        for slot_name, slot in pairs(data.slots or {}) do
            local slot_unit = slot.unit_3p
            if slot_unit and Unit.alive(slot_unit) then
                scan(slot_name, slot_unit)
                local attachments = slot.attachments_by_unit_3p and slot.attachments_by_unit_3p[slot_unit]
                for _, attachment in ipairs(attachments or {}) do
                    if Unit.alive(attachment) then scan(slot_name .. "/attachment", attachment) end
                end
            end
        end
        mod:info("DARKTIDEVR_BODY_MIRROR near_eye eye=%.3f,%.3f,%.3f source=%s head=%.3f,%.3f,%.3f shoulder_z=%.3f meshes=%d hidden=%d",
            eye[1], eye[2], eye[3], eye_source, head[1], head[2], head[3], shoulder_height, total, hidden)
    end
    local function capture_arms(unit)
        state.arms = {}
        for _, side in ipairs(Mirror.ARM_SIDES) do
            local names = {"j_" .. side .. "arm", "j_" .. side .. "forearm", "j_" .. side .. "hand"}
            if Unit.has_node(unit, names[1]) and Unit.has_node(unit, names[2]) and Unit.has_node(unit, names[3]) then
                local arm = {side = side, arm = Unit.node(unit, names[1]), forearm = Unit.node(unit, names[2]),
                    hand = Unit.node(unit, names[3]), unreachable = 0,
                    clavicle = Unit.has_node(unit, "j_" .. side .. "shoulder") and Unit.node(unit, "j_" .. side .. "shoulder") or nil}
                arm.rest_forearm = Vector3Box(Unit.local_position(unit, arm.forearm))
                arm.rest_hand = Vector3Box(Unit.local_position(unit, arm.hand))
                arm.upper = Vector3.length(arm.rest_forearm:unbox())
                arm.lower = Vector3.length(arm.rest_hand:unbox())
                state.arms[#state.arms + 1] = arm
            end
        end
    end
    local function solve_arm(world, avatar, unit, arm)
        -- The final visible wrist pose (tracked, gun-aligned or on the support
        -- grip); the avatar's hand joint only when no pose is recorded.
        local target, target_rotation
        if (state.hand_rig or Mirror.MODES[mode_name].reflect) and body_proxy() and body_proxy().hand_pose then
            target, target_rotation = body_proxy().hand_pose(arm.side)
        end
        if not target then
            target, target_rotation = Unit.world_position(avatar, arm.hand), Unit.world_rotation(avatar, arm.hand)
        end
        Unit.set_local_position(unit, arm.forearm, arm.rest_forearm:unbox())
        Unit.set_local_position(unit, arm.hand, arm.rest_hand:unbox())
        World.update_unit(world, unit)
        local lengths = Mirror.MODES[mode_name].arm_length and state.arm_lengths
        if lengths then
            local config = Mirror.MODES[mode_name].arm_length
            local rest_upper = Vector3.length(Unit.world_position(unit, arm.forearm) - Unit.world_position(unit, arm.arm))
            local rest_lower = Vector3.length(Unit.world_position(unit, arm.hand) - Unit.world_position(unit, arm.forearm))
            local function ratio(desired, current)
                if not (current > 1e-4) then return 1 end
                return math.max(config.min, math.min(config.max, desired / current))
            end
            arm.length_ratio_upper, arm.length_ratio_lower = ratio(lengths.upper, rest_upper), ratio(lengths.lower, rest_lower)
            Unit.set_local_position(unit, arm.forearm, arm.rest_forearm:unbox() * arm.length_ratio_upper)
            Unit.set_local_position(unit, arm.hand, arm.rest_hand:unbox() * arm.length_ratio_lower)
            World.update_unit(world, unit)
        end
        if Mirror.MODES[mode_name].protract and arm.clavicle then
            local shoulder_position = Unit.world_position(unit, arm.arm)
            local forearm_position = Unit.world_position(unit, arm.forearm)
            local length = Vector3.length(forearm_position - shoulder_position) +
                Vector3.length(Unit.world_position(unit, arm.hand) - forearm_position)
            local to_target = target - shoulder_position
            local distance = Vector3.length(to_target)
            local amount = Mirror.protraction(distance, length)
            arm.protraction = amount
            if amount > 1e-4 and distance > 1e-4 then
                local desired = shoulder_position + to_target * (amount / distance)
                local axis, angle = Mirror.clavicle_swing(array(Unit.world_position(unit, arm.clavicle)),
                    array(shoulder_position), array(desired), math.huge)
                if axis then
                    set_world_rotation(unit, arm.clavicle, Quaternion.multiply(Quaternion(vector(axis), angle),
                        Unit.world_rotation(unit, arm.clavicle)))
                    World.update_unit(world, unit)
                end
                arm.max_protraction = math.max(arm.max_protraction or 0, amount)
            end
        end
        local hint = Unit.world_position(unit, arm.forearm) - Vector3(0, 0, Mirror.ELBOW_HINT_DOWN)
        local shoulder = Unit.world_position(unit, arm.arm)
        -- World bone lengths: the character root carries a visual scale
        -- (overlay3: 0.294 m world against a 0.275 m local forearm).
        local upper = Vector3.length(Unit.world_position(unit, arm.forearm) - shoulder)
        local lower = Vector3.length(Unit.world_position(unit, arm.hand) - Unit.world_position(unit, arm.forearm))
        arm.world_upper, arm.world_lower = upper, lower
        if Mirror.MODES[mode_name].stretch then
            local ratio = Mirror.stretch_ratio(Vector3.length(target - shoulder), upper, lower)
            if ratio > 1 then
                -- The drawn segments lengthen too (joint offsets along their bones),
                -- not only the solve's lengths.
                Unit.set_local_position(unit, arm.forearm, Unit.local_position(unit, arm.forearm) * ratio)
                Unit.set_local_position(unit, arm.hand, Unit.local_position(unit, arm.hand) * ratio)
                World.update_unit(world, unit)
                upper, lower = upper * ratio, lower * ratio
                arm.max_stretch_ratio = math.max(arm.max_stretch_ratio or 1, ratio)
            end
        end
        local elbow, hand, reachable = Mirror.elbow(array(shoulder), array(hint), array(target), upper, lower)
        if not elbow then return end
        aim_joint(world, unit, arm.arm, arm.forearm, vector(elbow))
        aim_joint(world, unit, arm.forearm, arm.hand, vector(hand))
        -- The hand always lands on the pose (the gun stays in it); out of reach
        -- the wrist stretches the remainder.
        local parent = Unit.scene_graph_parent(unit, arm.hand)
        if parent then
            Unit.set_local_position(unit, arm.hand, Matrix4x4.transform(Matrix4x4.inverse(Unit.world_pose(unit, parent)), target))
            World.update_unit(world, unit)
        end
        arm.stretch = Vector3.length(target - vector(hand))
        set_world_rotation(unit, arm.hand, target_rotation)
        World.update_unit(world, unit)
        arm.distance = Vector3.length(target - shoulder)
        if not reachable then
            arm.unreachable = arm.unreachable + 1
            arm.max_stretch = math.max(arm.max_stretch or 0, arm.stretch)
        end
        arm.error = Vector3.length(Unit.world_position(unit, arm.hand) - target)
    end
    local function place(avatar, unit)
        local mode = Mirror.MODES[mode_name] or Mirror.MODES.mirror
        local rotation = Unit.world_rotation(avatar, 1)
        local position = Unit.world_position(avatar, 1) + Quaternion.forward(rotation) * mode.distance
        Unit.set_local_position(unit, 1, position)
        Unit.set_local_rotation(unit, 1, mode.facing and
            Quaternion.multiply(rotation, Quaternion(Vector3.up(), math.pi)) or rotation)
        Unit.set_local_scale(unit, 1, Unit.local_scale(avatar, 1))
    end
    local function spawn(world, avatar)
        local UIProfileSpawner = require("scripts/managers/ui/ui_profile_spawner")
        local UIUnitSpawner = require("scripts/managers/ui/ui_unit_spawner")
        local ItemSlotSettings = require("scripts/settings/item/item_slot_settings")
        local player = Managers.player and Managers.player:local_player(1)
        local profile = player and player:profile()
        if not profile then return end
        local unit_spawner = UIUnitSpawner:new(world)
        local profile_spawner = UIProfileSpawner:new("DarktideVRBodyMirror", world, nil, unit_spawner, false)
        local kept, ignored = 0, 0
        for slot_name, settings in pairs(ItemSlotSettings) do
            if Mirror.keeps_slot(slot_name, settings) then kept = kept + 1
            else profile_spawner:ignore_slot(slot_name); ignored = ignored + 1 end
        end
        local rotation = Unit.world_rotation(avatar, 1)
        profile_spawner:spawn_profile(profile, Unit.world_position(avatar, 1) + Quaternion.forward(rotation) * Mirror.MODES[mode_name].distance,
            rotation, nil, nil, nil, nil, nil, false, false, nil, true)
        state = {world = world, avatar = avatar, unit_spawner = unit_spawner, profile_spawner = profile_spawner, frames = 0}
        mod:info("DARKTIDEVR_BODY_MIRROR spawn mode=%s kept_slots=%d ignored_slots=%d", tostring(mode_name), kept, ignored)
    end
    local function update(world, avatar, dt, t)
        if not flag() or not world or not avatar or not Unit.alive(avatar) then destroy_own(); return end
        if state and (state.world ~= world or state.avatar ~= avatar) then destroy_own() end
        if not state then spawn(world, avatar); return end
        if not state.unit then
            state.profile_spawner:update(dt, t)
            local data = state.profile_spawner:spawned() and state.profile_spawner._character_spawn_data
            local unit = data and data.unit_3p
            if not unit then return end
            state.unit = unit
            state.data = data
            Unit.disable_animation_state_machine(unit)
            local probes = {"j_hips", "j_spine2", "j_head", "j_lefthand", "j_righthand", "j_leftfoot", "j_rightfoot"}
            state.same_layout = Mirror.same_layout(Unit.num_scene_graph_items(avatar), Unit.num_scene_graph_items(unit),
                function(name) return Unit.has_node(avatar, name) and Unit.node(avatar, name) end,
                function(name) return Unit.has_node(unit, name) and Unit.node(unit, name) end, probes)
            state.count = Unit.num_scene_graph_items(unit)
            capture_arms(unit)
            -- Deferred: see hide_near_eye. The scale eases over about a
            -- second, so the scan waits for it to settle and for a camera.
            state.near_eye_pending = Mirror.MODES[mode_name].near_eye or nil
            if Mirror.MODES[mode_name].hand_rig and body_proxy() and body_proxy().set_hand_rig then
                -- Before the first copy: the wrist basis comes from this spawn pose.
                state.hand_rig = body_proxy().set_hand_rig(unit)
                mod:info("DARKTIDEVR_BODY_MIRROR hand_rig=%s", tostring(state.hand_rig))
            end
            local slots, hidden = 0, {}
            for slot_name, slot in pairs(data.slots or {}) do
                slots = slots + 1
                if Mirror.hides_slot(mode_name, slot_name, presentation.headless_body_hidden_slot_lookup) and
                        slot.unit_3p and Unit.alive(slot.unit_3p) then
                    Unit.set_unit_visibility(slot.unit_3p, false, true)
                    local attachments = slot.attachments_by_unit_3p and slot.attachments_by_unit_3p[slot.unit_3p]
                    for _, attachment in ipairs(attachments or {}) do
                        if Unit.alive(attachment) then Unit.set_unit_visibility(attachment, false, true) end
                    end
                    hidden[#hidden + 1] = slot_name
                end
            end
            table.sort(hidden)
            mod:info("DARKTIDEVR_BODY_MIRROR ready mode=%s nodes=%d avatar_nodes=%d same_layout=%s spawned_slots=%d hidden_slots=%s",
                tostring(mode_name), state.count, Unit.num_scene_graph_items(avatar), tostring(state.same_layout), slots,
                #hidden > 0 and table.concat(hidden, ",") or "none")
        end
        local unit = state.unit
        if not Unit.alive(unit) then destroy_own(); return end
        if not state.same_layout then
            log_once("layout", "copy=skipped reason=layout_mismatch mode=%s hidden=%s",
                tostring(mode_name), tostring(Mirror.MODES[mode_name].distance == 0))
            -- A copy this module cannot pose is not left standing where the
            -- player is. Every mode that spawns it on them (distance 0) hides
            -- its head only after the pose is copied, and the reflection is
            -- moved off them only at the end of a posed frame, so a rig whose
            -- node layout does not match (an Ogryn, a cosmetic that changes
            -- the node count) would otherwise leave a whole character, head
            -- included, inside the player's view. It is hidden rather than
            -- destroyed: destroying it here would spawn another next frame.
            if Mirror.MODES[mode_name].distance == 0 and not state.layout_hidden then
                state.layout_hidden = true
                pcall(Unit.set_unit_visibility, unit, false, true)
                for _, slot in pairs(state.data and state.data.slots or {}) do
                    if slot.unit_3p and Unit.alive(slot.unit_3p) then
                        pcall(Unit.set_unit_visibility, slot.unit_3p, false, true)
                        local attachments = slot.attachments_by_unit_3p and
                            slot.attachments_by_unit_3p[slot.unit_3p]
                        for _, attachment in ipairs(attachments or {}) do
                            if Unit.alive(attachment) then
                                pcall(Unit.set_unit_visibility, attachment, false, true)
                            end
                        end
                    end
                end
            end
            if not state.layout_hidden then place(avatar, unit) end
            return
        end
        -- Every joint below the root: the avatar's local pose after its own
        -- animation and the mod's hand writes this frame.
        for index = 2, state.count do
            Unit.set_local_pose(unit, index, Unit.local_pose(avatar, index))
        end
        place(avatar, unit)
        World.update_unit(world, unit)
        local frame = Mirror.MODES[mode_name].follow_neck and presentation.body_frame and
            presentation.body_frame.sample(avatar, t)
        if Mirror.MODES[mode_name].body_yaw and frame and type(frame.yaw) == "number" then
            state.root_yaw_delta = math.deg(math.atan2(math.sin(frame.yaw - Quaternion.yaw(Unit.world_rotation(unit, 1))),
                math.cos(frame.yaw - Quaternion.yaw(Unit.world_rotation(unit, 1)))))
            state.yaw = Mirror.smooth_yaw(state.yaw, frame.yaw, dt)
            Unit.set_local_rotation(unit, 1, Quaternion(Vector3.up(), state.yaw))
            World.update_unit(world, unit)
        end
        local neck_target = frame and Mirror.neck_target(frame.neck, frame.head_yaw, frame.scale)
        if Mirror.MODES[mode_name].follow_neck and Unit.has_node(unit, "j_neck") then
            if neck_target and Mirror.MODES[mode_name].scale_to_neck then
                local base = Unit.world_position(unit, 1)
                local neck_height = Vector3.z(Unit.world_position(unit, Unit.node(unit, "j_neck"))) - Vector3.z(base)
                state.scale_ratio = Mirror.scale_ratio(state.scale_ratio, neck_height, neck_target[3] - Vector3.z(base), dt)
                Unit.set_local_scale(unit, 1, Unit.local_scale(avatar, 1) * state.scale_ratio)
                World.update_unit(world, unit)
            end
            if neck_target and not Mirror.MODES[mode_name].spine_bend then
                local offset, length = Mirror.neck_offset(array(Unit.world_position(unit, Unit.node(unit, "j_neck"))), neck_target)
                Unit.set_local_position(unit, 1, Unit.local_position(unit, 1) + vector(offset))
                World.update_unit(world, unit)
                state.neck_offset, state.neck_distance = offset, length
            elseif neck_target then
                local neck = Unit.node(unit, "j_neck")
                local target = vector(neck_target)
                local before = Vector3.length(Unit.world_position(unit, neck) - target)
                local fractions = Mirror.chain_fractions(Mirror.SPINE)
                for i, entry in ipairs(Mirror.SPINE) do
                    if Unit.has_node(unit, entry[1]) then
                        local joint = Unit.node(unit, entry[1])
                        local axis, angle = Mirror.clavicle_swing(array(Unit.world_position(unit, joint)),
                            array(Unit.world_position(unit, neck)), neck_target, math.huge)
                        if axis then
                            angle = math.min(angle * fractions[i], Mirror.SPINE_JOINT_MAX)
                            set_world_rotation(unit, joint, Quaternion.multiply(Quaternion(vector(axis), angle),
                                Unit.world_rotation(unit, joint)))
                            World.update_unit(world, unit)
                        end
                    end
                end
                state.spine_neck = {before, Vector3.length(Unit.world_position(unit, neck) - target)}
            end
        end
        -- Calibrated arm lengths for this frame, from the rig's shoulder width
        -- after the uniform scale (arm length design).
        state.arm_lengths = nil
        if Mirror.MODES[mode_name].arm_length and Unit.has_node(unit, "j_leftarm") and Unit.has_node(unit, "j_rightarm") then
            ArmLength = ArmLength or mod:io_dofile("darktidevr/scripts/mods/darktidevr/darktidevr_arm_length")
            local calibration = mod.darktidevr_calibration and mod.darktidevr_calibration.result or
                (mod.get and mod:get("vr_calibration_v1"))
            local width = Vector3.length(Unit.world_position(unit, Unit.node(unit, "j_leftarm")) -
                Unit.world_position(unit, Unit.node(unit, "j_rightarm")))
            -- The player's shoulder width, not the rig's: the rig is scaled up to
            -- reach the camera's neck (armlen3: 0.47 m apart), and subtracting
            -- that width left the arms 0.50 m long and out of reach.
            local eye = calibration and not calibration.seated and tonumber(calibration.floor_eye_height)
            local derived = ArmLength.from_calibration(calibration, ArmLength.shoulder_width(eye) or width)
            if derived.reach then
                state.arm_lengths = derived
                state.arm_shoulder_width = width
            end
        end
        if Mirror.MODES[mode_name].clavicles and frame and frame.shoulder_left then
            for _, side in ipairs({"left", "right"}) do
                local clavicle_name, arm_name = "j_" .. side .. "shoulder", "j_" .. side .. "arm"
                -- The estimated shoulders hang from the frame's neck, so they take
                -- the same extra as the copy's neck, or the clavicles would shrug
                -- up toward shoulders 10 cm above the lowered body's.
                local target = Mirror.neck_target(frame["shoulder_" .. side], frame.head_yaw, frame.scale)
                if target and Unit.has_node(unit, clavicle_name) and Unit.has_node(unit, arm_name) then
                    local clavicle, arm = Unit.node(unit, clavicle_name), Unit.node(unit, arm_name)
                    local before = Vector3.length(Unit.world_position(unit, arm) - vector(target))
                    local axis, angle = Mirror.clavicle_swing(array(Unit.world_position(unit, clavicle)),
                        array(Unit.world_position(unit, arm)), target,
                        Mirror.MODES[mode_name].clavicle_max or Mirror.CLAVICLE_MAX)
                    if axis then
                        set_world_rotation(unit, clavicle, Quaternion.multiply(Quaternion(vector(axis), angle),
                            Unit.world_rotation(unit, clavicle)))
                        World.update_unit(world, unit)
                    end
                    state["shoulder_gap_" .. side] = {before, Vector3.length(Unit.world_position(unit, arm) - vector(target))}
                end
            end
        end
        if Mirror.MODES[mode_name].solve_arms then
            for _, arm in ipairs(state.arms) do solve_arm(world, avatar, unit, arm) end
        end
        if Mirror.MODES[mode_name].reflect then
            -- Posed on the player; now turned about them and stood ahead.
            local root = Unit.local_position(unit, 1)
            local heading = state.yaw or Quaternion.yaw(Unit.local_rotation(unit, 1))
            local pivot = neck_target or array(root)
            local moved = Mirror.reflected_root(array(root), pivot, heading, Mirror.MIRROR_DISTANCE)
            Unit.set_local_position(unit, 1, vector(moved))
            Unit.set_local_rotation(unit, 1, Quaternion.multiply(Quaternion(Vector3.up(), math.pi), Unit.local_rotation(unit, 1)))
            World.update_unit(world, unit)
        end
        if state.near_eye_pending and (state.scale_ratio == nil or
                (state.last_scale_ratio and math.abs(state.scale_ratio - state.last_scale_ratio) < 0.002)) then
            state.near_eye_pending = nil
            hide_near_eye(unit, state.data)
        end
        -- The trace. Yaws and the root's own movement, at half the frame rate,
        -- so a stick turn and a stationary jitter are both readable in the
        -- same lines: during a turn compare the steps, at rest look at whether
        -- root_step_m is oscillating rather than settling.
        if trace_flag() and trace_lines < Mirror.TRACE_MAX_LINES and
                state.frames % Mirror.TRACE_EVERY == 0 then
            local ok = pcall(function()
                local root_world = array(Unit.world_position(unit, 1))
                local sample = Mirror.yaw_sample(
                    frame and frame.head_yaw,
                    frame and frame.target_yaw,
                    frame and frame.yaw,
                    state.yaw,
                    Quaternion.yaw(Unit.world_rotation(avatar, 1)),
                    Quaternion.yaw(Unit.world_rotation(unit, 1)))
                local previous = trace_previous
                -- Two shapes of the same numbers: by name for the line, as a
                -- list for the due rule. Built explicitly rather than by
                -- appending to the same table, where a nil step would have
                -- silently shortened the list the rule walks.
                local raw, moved = {}, {}
                for _, name in ipairs({"head", "target", "frame", "mirror", "avatar", "unit"}) do
                    local value = previous and Mirror.yaw_step(sample[name], previous[name])
                    raw[name] = value
                    if value then moved[#moved + 1] = value end
                end
                local function step(name)
                    return raw[name] and string.format("%.2f", raw[name]) or "na"
                end
                local root_step = previous and previous.root and
                    math.sqrt((root_world[1] - previous.root[1]) ^ 2 +
                        (root_world[2] - previous.root[2]) ^ 2 +
                        (root_world[3] - previous.root[3]) ^ 2)
                local due, why = Mirror.trace_due(moved, root_step, trace_since_line)
                if not due then
                    trace_since_line = trace_since_line + 1
                    sample.root = root_world
                    trace_previous = sample
                    return
                end
                trace_since_line = 0
                local function degrees(name)
                    return sample[name] and string.format("%.2f", sample[name]) or "na"
                end
                trace_lines = trace_lines + 1
                mod:info("DARKTIDEVR_BODY_TRACE t=%.3f dt=%.4f head=%s target=%s frame=%s mirror=%s avatar=%s unit=%s " ..
                    "d_head=%s d_target=%s d_frame=%s d_mirror=%s d_avatar=%s d_unit=%s " ..
                    "root=%.4f,%.4f,%.4f root_step_m=%s neck_m=%s scale=%.4f why=%s",
                    type(t) == "number" and t or 0, type(dt) == "number" and dt or 0,
                    degrees("head"), degrees("target"), degrees("frame"),
                    degrees("mirror"), degrees("avatar"), degrees("unit"),
                    step("head"), step("target"), step("frame"),
                    step("mirror"), step("avatar"), step("unit"),
                    root_world[1], root_world[2], root_world[3],
                    root_step and string.format("%.5f", root_step) or "na",
                    state.neck_distance and string.format("%.4f", state.neck_distance) or "na",
                    state.scale_ratio or 1, why)
                sample.root = root_world
                trace_previous = sample
            end)
            if not ok then
                -- One diagnostic that cannot be taken must not become a
                -- repeating mod error in front of the player.
                trace_lines = Mirror.TRACE_MAX_LINES
                log_once("trace", "trace=unavailable")
            end
        end
        state.last_scale_ratio = state.scale_ratio
        state.frames = state.frames + 1
        if state.frames == 1 or state.frames % 900 == 0 then
            if state.neck_offset then
                mod:info("DARKTIDEVR_BODY_MIRROR neck_follow offset_m=%.3f,%.3f,%.3f distance_m=%.3f scale_ratio=%.3f",
                    state.neck_offset[1], state.neck_offset[2], state.neck_offset[3], state.neck_distance, state.scale_ratio or 1)
            end
            if state.spine_neck then
                mod:info("DARKTIDEVR_BODY_MIRROR spine neck_gap_m=%.3f->%.3f", state.spine_neck[1], state.spine_neck[2])
            end
            if state.root_yaw_delta then
                mod:info("DARKTIDEVR_BODY_MIRROR body_yaw delta_from_avatar_deg=%.1f", state.root_yaw_delta)
            end
            if state.shoulder_gap_left and state.shoulder_gap_right then
                mod:info("DARKTIDEVR_BODY_MIRROR clavicles gap_left_m=%.3f->%.3f gap_right_m=%.3f->%.3f",
                    state.shoulder_gap_left[1], state.shoulder_gap_left[2],
                    state.shoulder_gap_right[1], state.shoulder_gap_right[2])
            end
            local first_person = ScriptUnit.has_extension(avatar, "first_person_system")
            local camera = first_person and first_person:first_person_unit()
            if camera and Mirror.MODES[mode_name].near_eye then
                local eye = Matrix4x4.transform(Matrix4x4.inverse(Unit.world_pose(unit, 1)), Unit.world_position(camera, 1))
                mod:info("DARKTIDEVR_BODY_MIRROR live_eye_root_local=%.3f,%.3f,%.3f", Vector3.x(eye), Vector3.y(eye), Vector3.z(eye))
            end
            local unit_hand, avatar_hand = Unit.node(unit, "j_righthand"), Unit.node(avatar, "j_righthand")
            local hand = Vector3.distance(Unit.local_position(unit, unit_hand), Unit.local_position(avatar, avatar_hand))
            -- Overlay: how far the copied hand lands from the avatar's (which
            -- carries the weapon), and how far the hand sits from its forearm
            -- joint: the stretch a plain copy leaves where the gloves pull the
            -- avatar's hands.
            local world_hand = Vector3.distance(Unit.world_position(unit, unit_hand), Unit.world_position(avatar, avatar_hand))
            local stretch = Unit.has_node(unit, "j_rightforearm") and Vector3.distance(Unit.world_position(unit, unit_hand),
                Unit.world_position(unit, Unit.node(unit, "j_rightforearm"))) or -1
            mod:info("DARKTIDEVR_BODY_MIRROR copying mode=%s frames=%d right_hand_local_error_m=%.6f right_hand_world_error_m=%.4f right_forearm_to_hand_m=%.4f",
                tostring(mode_name), state.frames, hand, world_hand, stretch)
            if Mirror.MODES[mode_name].solve_arms then
                if state.arm_lengths then
                    local l = state.arm_lengths
                    mod:info("DARKTIDEVR_BODY_MIRROR arm_length source=%s span_m=%.3f shoulder_width_m=%.3f reach_m=%.3f upper_m=%.3f lower_m=%.3f problems=%s ratio_left=%.3f/%.3f ratio_right=%.3f/%.3f",
                        tostring(l.source), l.span or -1, state.arm_shoulder_width or -1, l.reach, l.upper, l.lower,
                        table.concat(l.problems or {}, ","),
                        state.arms[1] and state.arms[1].length_ratio_upper or -1, state.arms[1] and state.arms[1].length_ratio_lower or -1,
                        state.arms[2] and state.arms[2].length_ratio_upper or -1, state.arms[2] and state.arms[2].length_ratio_lower or -1)
                end
                for _, arm in ipairs(state.arms) do
                    mod:info("DARKTIDEVR_BODY_MIRROR arm side=%s upper_m=%.4f lower_m=%.4f world_upper_m=%.4f world_lower_m=%.4f shoulder_to_target_m=%.4f hand_error_m=%.4f unreachable_frames=%d max_stretch_m=%.4f max_protraction_m=%.4f",
                        arm.side, arm.upper, arm.lower, arm.world_upper or -1, arm.world_lower or -1, arm.distance or -1, arm.error or -1, arm.unreachable, arm.max_stretch or 0,
                        arm.max_protraction or 0)
                    if arm.max_stretch_ratio then
                        mod:info("DARKTIDEVR_BODY_MIRROR arm side=%s max_stretch_ratio=%.3f", arm.side, arm.max_stretch_ratio)
                    end
                end
            end
        end
    end
    function api.update(world, avatar, dt, t)
        local ok, err = pcall(update, world, avatar, dt, t)
        if not ok then
            log_once("failure", "failed=%s", tostring(err):sub(1, 200))
            destroy_own()
            enabled = false; poll = 1e9
        end
        -- After the overlay, whose final wrist poses the reflection's arms
        -- are solved to this frame.
        if reflection then reflection.update(world, avatar, dt, t) end
    end
    return api
end

return Mirror
