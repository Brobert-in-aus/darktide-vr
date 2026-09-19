-- Body mirror (dev flag darktidevr_body_mirror.flag "mirror"; full-body IK
-- design, milestone 2, 15 September). Spawns a presentation-only copy of the
-- player's whole character profile (every body, gear and material slot, no
-- weapons) with the body proxy's UIProfileSpawner, stops its own animation
-- the moment it is ready (scan2: that freezes the pose), boxes that pose as
-- the rest pose, and every frame starts from it and moves only what the
-- tracking says to move. Since 19 September NOTHING on the copy is read from
-- the avatar's joints: the user's rule is that the base model exists hidden
-- for hit detection, the custom-IK body is the whole of what is drawn, and
-- the two have no relationship beyond the root position (where the player
-- stands) and what the weapon needs. It stands
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
    -- The mirror reflects the body the player actually has, not the one the
    -- game is animating. It carried none of the solve until 18 September --
    -- no tracked arms, no neck scaling, no spine -- so looking into it showed
    -- the CHARACTER going through its animation rather than the person
    -- standing in front of it (user: "the mirror copy should be a mirror of
    -- the best version of my own body, right?"). It should, and now it is the
    -- overlay solve stood in front and turned to face.
    --
    -- Three of the overlay's flags are deliberately NOT here. The first two
    -- are about being INSIDE the body rather than looking at it; the third
    -- would take the player's hands away:
    --   hide_head  -- the overlay hides the head because the player's own is
    --                 in the same place; a mirror without a face is useless.
    --   near_eye   -- hides meshes that would sit inside the eye. Nothing is
    --                 near the eye when the body is three metres away, so it
    --                 would only hide parts of the reflection for nothing.
    --   hand_rig   -- this is not a pose flag. It hands the copy the job of
    --                 BEING the player's hands, and destroys the glove units
    --                 that would otherwise draw them. A reflection three
    --                 metres away cannot be the player's hands, so the mirror
    --                 keeps the gloves and solves its own arms separately.
    --
    -- The order already works: the update solves the copy on the player and
    -- only then turns it about them and stands it ahead.
    mirror = {distance = Mirror.MIRROR_DISTANCE, facing = true, hide_head = false,
        solve_arms = true, follow_neck = true,
        clavicles = true, body_yaw = true,
        protract = true, stretch = true, gait = true, arm_length = {min = 0.6, max = 1.6}},
    overlaycopy = {distance = 0, facing = false, hide_head = true, solve_arms = false, hand_rig = true},
    overlayarms = {distance = 0, facing = false, hide_head = true, solve_arms = true, hand_rig = true},
    overlayfollow = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true, hand_rig = true,
        follow_neck = true},
    -- arm_length: the arm bones stretched or compressed to the calibrated
    -- upper-arm and forearm lengths, on their own bones (user, 19
    -- September: "simply stretch/compress only the arm bones as needed").
    -- The clamp is a sanity bound, not a fit.
    overlay = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true, hand_rig = true,
        follow_neck = true, clavicles = true, body_yaw = true,
        protract = true, stretch = true, gait = true, arm_length = {min = 0.6, max = 1.6}},
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
        arm_length = {min = 0.70, max = 1.20}, gait = true},
    -- ANIMATED LEGS (19 September, dev flag "overlayanimated"): the overlay
    -- with the copy running the game's own third-person state machine for
    -- the wielded weapon, fed the same inputs the game feeds the avatar
    -- (the wield, every third-person event, the move speed each frame), so
    -- its legs walk from the same clips on its own skeleton. Everything
    -- above the hips, and the hips and root, are the solve's: put back over
    -- the machine's output at the render boundary. The gait is the fallback
    -- for any frame the machine is not live.
    overlayanimated = {distance = 0, facing = false, hide_head = true, solve_arms = true, near_eye = true, hand_rig = true,
        follow_neck = true, clavicles = true, body_yaw = true,
        protract = true, stretch = true, gait = true, arm_length = {min = 0.6, max = 1.6}, animated_legs = true},
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
        clavicles = true, body_yaw = true, protract = true, stretch = true, reflect = true,
        gait = true, arm_length = {min = 0.6, max = 1.6}},
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
-- Added to the rest knee along the heading as the leg's bend hint, so a
-- straight rest leg still bends forward (a knee never bends backward).
Mirror.KNEE_HINT_FORWARD = 0.15
-- The ground under a foot: cast from this far above the simulated floor
-- to this far below it (whole-body design, step 6: hip height to 0.6 m
-- below the root), against the static world with the filter the game
-- grounds the player's own hand IK with.
Mirror.GROUND_RAY_UP, Mirror.GROUND_RAY_DOWN = 1.0, 0.6
Mirror.GROUND_FILTER = "filter_player_mover"

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

-- HEIGHT BEYOND THE SETTABLE RANGE (19 September). The copy's scale is the
-- game's own character height for the profile, which the calibration sets
-- within the player-facing range. A player whose calibrated eye height lies
-- outside that range has the difference put into the bones that carry
-- height -- legs, spine, neck -- as a stretch along each bone, never a
-- uniform scale. This is the factor: the ratio of the chain from floor to
-- neck as it should be (as it is, plus the residual) to the chain as it is.
-- residual = calibrated eye height - the character's eye height at its
-- scale; chain = the copy's floor-to-neck height at that scale. Under a
-- centimetre of residual is 1, and the factor is clamped so a bad
-- calibration cannot draw a stick figure. Pure.
Mirror.STRETCH_MIN, Mirror.STRETCH_MAX, Mirror.STRETCH_DEAD_M = 0.80, 1.25, 0.03
function Mirror.height_stretch(calibrated_eye, character_eye, chain)
    if type(calibrated_eye) ~= "number" or type(character_eye) ~= "number" or type(chain) ~= "number" then return 1 end
    if calibrated_eye ~= calibrated_eye or character_eye ~= character_eye or chain ~= chain then return 1 end
    if not (chain > 0.2) or not (calibrated_eye > 0.2) or not (character_eye > 0.2) then return 1 end
    local residual = calibrated_eye - character_eye
    if math.abs(residual) < Mirror.STRETCH_DEAD_M then return 1 end
    return math.max(Mirror.STRETCH_MIN, math.min(Mirror.STRETCH_MAX, (chain + residual) / chain))
end

-- Where the hips sit above the floor when the legs stand: the ankle's own
-- height, plus the lower and upper leg (stretched by k) with the knee
-- softened by KNEE_REST_BEND, so the leg solve always has a little bend to
-- work from and never starts locked straight. Pure.
-- Eight degrees left the knee one per cent of slack: with the feet on the
-- floor the legs locked straight and every step read as a stiff swing
-- (13:02 worn run, "legs just stay straight and swing forwards
-- together"). Twenty gives about six, a visible bend standing and room
-- for the gait's arc.
Mirror.KNEE_REST_BEND = math.rad(20)
-- How far the ball of the foot (j_*toebase) sits above the sole on a
-- standing foot: the ankle's height above the floor is measured from it.
-- Zero: with 1.5 cm the feet still floated (13:02), and on this rig the
-- toe joint sits at the sole.
Mirror.TOE_ABOVE_SOLE_M = 0.0
function Mirror.standing_hips_height(ankle_z, upper, lower, k)
    if type(ankle_z) ~= "number" or type(upper) ~= "number" or type(lower) ~= "number" then return nil end
    if not (upper > 0) or not (lower > 0) or ankle_z ~= ankle_z then return nil end
    local stretch = (type(k) == "number" and k > 0) and k or 1
    return ankle_z + (lower + upper * math.cos(Mirror.KNEE_REST_BEND)) * stretch
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
-- THE TURN LEAK. The copy's joints below the root are copied as LOCAL poses,
-- which are relative to the AVATAR's root. `body_yaw` then replaces the copy's
-- root yaw with the body frame's heading. The avatar's root yaw is never taken
-- out, so it leaks into everything below -- with the wrong sign, because what
-- the animation puts in the spine during a stick turn is the counter-rotation
-- that holds the torso still in the world while the legs turn underneath.
-- The copy inherits that compensation without inheriting the turn it was
-- compensating for, so its torso swings the other way at the full rate of the
-- turn. "The body turns and it turns faster than me."
--
-- The trace proves the term rather than suggesting it. Take
--     d(copy torso) = d(copy root) + d(avatar torso) - d(avatar root)
-- and read it off worn samples (19 September), all in degrees per sample:
--     d_unit=-0.04 d_av_torso=-0.73 d_avatar=-10.53 -> 9.76, measured 10.11
--     d_unit= 1.96 d_av_torso= 4.77 d_avatar=  0.00 -> 6.73, measured  6.60
--     d_unit= 1.55 d_av_torso= 2.32 d_avatar= -7.18 -> 11.05, measured 10.25
--     d_unit= 4.55 d_av_torso= 2.03 d_avatar=  1.16 -> 5.42, measured  4.91
-- The head moved about a degree in each of those. The copy's own root barely
-- moved; the avatar's root is doing all of it.
--
-- So the correction is not a rate limit or a damper -- the error is not a
-- speed, it is an uncancelled term, which is also why the body drifts out of
-- alignment instead of merely lagging. Putting the avatar's root yaw back into
-- the chain below cancels it exactly: the copy's torso then sits where the
-- avatar's torso sits, which is where the game already keeps it relative to
-- the view, and the copy's root keeps the body frame's heading for the hips
-- and legs.
--
-- Both arguments are yaws in radians; the result is the yaw to apply about the
-- vertical to the root's child, wrapped to (-pi, pi]. Pure.
function Mirror.root_yaw_leak(avatar_root_yaw, body_yaw)
    if type(avatar_root_yaw) ~= "number" or type(body_yaw) ~= "number" then return nil end
    if avatar_root_yaw ~= avatar_root_yaw or body_yaw ~= body_yaw then return nil end
    return (avatar_root_yaw - body_yaw + math.pi) % (2 * math.pi) - math.pi
end

-- Where the copy's torso lands, in world yaw, with the leak (corrected false)
-- and without it (corrected true). The arithmetic above, as a function, so a
-- test can run the worn samples through it. Pure.
function Mirror.copy_torso_yaw(avatar_root_yaw, avatar_torso_yaw, copy_root_yaw, corrected)
    local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
    local local_torso = wrap(avatar_torso_yaw - avatar_root_yaw)
    if corrected then return wrap(avatar_root_yaw + local_torso) end
    return wrap(copy_root_yaw + local_torso)
end

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

-- The yaw a TORSO is facing, from its shoulder line. 3-arrays for the two
-- shoulder positions; returns a Stingray yaw, or nil if the two are on top of
-- each other. Pure.
--
-- This exists because the first two passes at "the body turns faster than my
-- view" measured ROOT yaws -- the copy's root, the avatar's root -- and read a
-- root that barely moved as a body that barely moved. The copy's torso is a
-- JOINT, posed from the avatar every frame, so the root says nothing about
-- what the player is looking at. The user was right and the instrument was
-- pointed at the wrong bone.
--
-- Right = (cos yaw, sin yaw) against forward = (-sin yaw, cos yaw), so the
-- shoulder line's yaw is directly comparable with the head's.
function Mirror.torso_yaw(left_shoulder, right_shoulder)
    if type(left_shoulder) ~= "table" or type(right_shoulder) ~= "table" then return nil end
    local rx = right_shoulder[1] - left_shoulder[1]
    local ry = right_shoulder[2] - left_shoulder[2]
    if rx ~= rx or ry ~= ry then return nil end
    if rx * rx + ry * ry < 1e-8 then return nil end
    return math.atan2(ry, rx)
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

-- The distance between two positions (3-arrays), or nil when either is
-- missing or not finite. The motion probe's step. Pure.
function Mirror.step_m(now, before)
    if type(now) ~= "table" or type(before) ~= "table" then return nil end
    local sum = 0
    for i = 1, 3 do
        local a, b = now[i], before[i]
        if type(a) ~= "number" or type(b) ~= "number" or a ~= a or b ~= b then return nil end
        sum = sum + (a - b) ^ 2
    end
    return math.sqrt(sum)
end
-- The avatar's step per frame above which the player counts as moving for
-- the motion probe: a millimetre, well under a walking step (about 4 cm at
-- 90 Hz) and above the sub-millimetre breathing of a standing character.
Mirror.MOTION_MOVING_M = 0.001
-- The motion probe's own line budget when the trace flag is off: about
-- half a minute of movement at 90 Hz.
Mirror.MOTION_MAX_LINES = 3000

-- Which units a drawn copy owns, so their collision can be taken off them.
--
-- The copy is a full character: a root and one unit per equipment slot, plus
-- each slot's attachments. It is spawned on top of the player -- the overlay
-- mode's distance is zero -- and until 18 September 2026 it kept every actor
-- the profile gave it.
--
-- That is why the gun stopped producing bullets. The player's own hitscan
-- starts at their own position, and stock skips the ATTACKER's actors; the
-- copy is a different unit, so nothing skipped it, and every shot terminated
-- on it at distance zero. The log said so plainly once it was asked:
-- `endpoint` equal to `origin`, `distance=0.0000`, and the same unit id
-- reported `self=true` for one actor and `self=false` for another -- two Unit
-- objects printing the same id, which is exactly what a copy looks like.
--
-- The avatar and the source are excluded HERE rather than at the call site,
-- because the failure this could cause is far worse than the one it fixes:
-- disabling the real player's collision would drop them through the world and
-- make them unhittable. Pure, and tested for that above everything else.
function Mirror.collider_units(root, data, avatar)
    local units, seen = {}, {}
    local function add(unit)
        if unit == nil or unit == avatar then return end
        -- Same unit reachable twice (a slot and its own attachment list).
        for index = 1, #units do if units[index] == unit then return end end
        if seen[unit] then return end
        seen[unit] = true
        units[#units + 1] = unit
    end
    add(root)
    for _, slot in pairs(data and data.slots or {}) do
        add(slot.unit_3p)
        local attachments = slot.attachments_by_unit_3p and
            slot.attachments_by_unit_3p[slot.unit_3p]
        for _, attachment in ipairs(attachments or {}) do add(attachment) end
    end
    return units
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
-- Every third frame and twenty-five thousand lines, both raised after the
-- first worn session spent the entire budget inside five minutes and missed
-- the stick turns it was written for. A head in a headset micro-moves
-- constantly, so nearly every sample clears the movement threshold; the answer
-- is a bigger budget rather than a threshold high enough to hide a jitter.
Mirror.TRACE_EVERY = 3
Mirror.TRACE_HEARTBEAT_FRAMES = 120
Mirror.TRACE_MOVED_M = 0.0005
Mirror.TRACE_MOVED_DEG = 0.1
Mirror.TRACE_MAX_LINES = 25000
Mirror.OPTION_MODE = "overlay"
function Mirror.requested_mode(flag_mode, mirror_toggled, in_psykhanium, option_on)
    if flag_mode and Mirror.MODES[flag_mode] then return flag_mode end
    if mirror_toggled == true and in_psykhanium == true then return "mirror" end
    if option_on == true then return Mirror.OPTION_MODE end
    return nil
end

-- Whether a copy running this mode is DRAWING THE PLAYER'S BODY -- standing
-- on them, in place of the stock 3P model, which the visibility code then
-- does not draw at all. A mode that stands the copy away from the player
-- (the mirror) or reflects it out to one (the reflection) is not the
-- player's body however complete its solve is, and the stock model still has
-- to be dealt with by whatever else is running. `has_unit` is false while the
-- profile is still spawning, so the stock model is never taken away before
-- there is something to put in its place. Pure.
-- `drawable` is the third condition and it is not a detail. When the copy's
-- scene graph does not match the avatar's, this module HIDES the copy rather
-- than destroying it (see state.layout_hidden: destroying it here would spawn
-- another next frame) and never poses it. A predicate that looked only at
-- whether the unit was alive would answer true in that state, the stock model
-- would be hidden on the strength of it, and the player would be left with
-- nothing but a floating weapon -- indefinitely, because the copy is not
-- coming back by itself. An Ogryn, or a cosmetic that changes the node count,
-- is enough to reach it. Caught in review before it was ever deployed.
function Mirror.draws_body(mode_name, has_unit, drawable)
    local mode = mode_name and Mirror.MODES[mode_name]
    if not mode or has_unit ~= true or drawable ~= true then return false end
    return mode.distance == 0 and not mode.reflect
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

-- The scene-graph indices under the leg roots (the two upper legs), by
-- walking each index's parents: the joints the animated-legs mode leaves to
-- the copy's own state machine, and the snapshot and restore leave alone.
-- `parent_of(index)` returns the parent index or nil at the root;
-- `roots` is a set of indices. Pure over the lookup.
function Mirror.leg_indices(count, parent_of, roots)
    local legs = {}
    if type(count) ~= "number" or type(parent_of) ~= "function" or type(roots) ~= "table" then return legs end
    for index = 2, count do
        local at, hops = index, 0
        while at and hops < 64 do
            if roots[at] then legs[index] = true; break end
            at = parent_of(at)
            hops = hops + 1
        end
    end
    return legs
end

-- The joints the solve moves by name. A copy without them is hidden rather
-- than posed (see state.layout_hidden). Pure over the lookup.
Mirror.SOLVE_JOINTS = {"j_hips", "j_spine", "j_neck", "j_head", "j_leftshoulder", "j_rightshoulder",
    "j_leftarm", "j_rightarm", "j_leftforearm", "j_rightforearm", "j_lefthand", "j_righthand"}
function Mirror.has_solve_joints(has_node)
    if type(has_node) ~= "function" then return false end
    for _, name in ipairs(Mirror.SOLVE_JOINTS) do
        if has_node(name) ~= true then return false end
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
    -- Forward declarations. The api functions defined above the helpers
    -- (assign_machine, check_before_render) close over these; without the
    -- declaration a call resolved to a nil GLOBAL, and at ready on 19
    -- September (12:52) that took the whole module down for the session:
    -- the copy was destroyed and the worn run looked at the headless stock
    -- fallback instead. test-body-mirror.lua refuses a helper used above
    -- its declaration now.
    local log_once, array, vector
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
            -- The dev flag is gated out of the hub as the option is: the
            -- user runs a worn session with the flag set in the install,
            -- and the hub's own presentation has no combat body to replace.
            wanted = Mirror.requested_mode(game_mode ~= nil and game_mode ~= "hub" and parsed or nil, false, false,
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
            if state.marker_profile_spawner then pcall(state.marker_profile_spawner.destroy, state.marker_profile_spawner) end
            if state.marker_unit_spawner then pcall(state.marker_unit_spawner.destroy, state.marker_unit_spawner) end
        end
        state = nil
    end
    -- The drawn copy and everything hanging off it, for the arm census. The
    -- copy lives in a closure local and had no accessor, so a census built to
    -- find a duplicate body could not see the most obvious candidate.
    -- Whether this instance's copy is standing on the player AND drawing
    -- their body right now -- the question the visibility code asks before it
    -- hides the stock model. False while the copy is still spawning, so a
    -- player is never left with no body at all, and false for the reflection
    -- (its copy is out at the mirror; it draws a reflection, not the body).
    function api.draws_body()
        local has_unit = state ~= nil and state.unit ~= nil and Unit.alive(state.unit) == true
        local drawable = has_unit and state.same_layout == true and
            state.layout_hidden ~= true
        return Mirror.draws_body(mode_name, has_unit, drawable)
    end

    -- ANIMATED LEGS: the copy's own state machine, fed the game's inputs.
    -- `wielded` keeps the local player's current weapon template (the game
    -- picks the third-person machine per weapon, WeaponTemplate.state_machines)
    -- and puts that machine on a live copy the same way the game puts it on
    -- the avatar (blend base layer, then the template's initialization
    -- variables, evaluated for the copy). `forward_anim_event` re-issues each
    -- third-person event the avatar's animation extension sends, with its
    -- variables, on the copy. Both are no-ops unless the mode asks for
    -- animated legs and the copy is ready. Failures fall back to the gait
    -- and are logged once.
    local wielded_template
    local function assign_machine()
        if not state or not state.unit or not Unit.alive(state.unit) then return false end
        if not Mirror.MODES[mode_name] or not Mirror.MODES[mode_name].animated_legs then return false end
        if not wielded_template then log_once("machine_template", "animated_legs=waiting reason=no_wielded_template"); return false end
        local ok, err = pcall(function()
            local WeaponTemplate = require("scripts/utilities/weapon/weapon_template")
            local breed_name = state.profile and state.profile.archetype and state.profile.archetype.breed or "human"
            local machine, _, init = WeaponTemplate.state_machines(wielded_template, breed_name)
            if not machine then error("no third-person machine for " .. tostring(wielded_template.name)) end
            -- The game blends a NEW machine onto a unit that has one
            -- (set_animation_state_machine_blend_base_layer). This copy had
            -- its machine disabled at ready, and that call refused it:
            -- "Unit has no animation state machine" (13:02). The spawner's
            -- own call, set_animation_state_machine, then refused too:
            -- "AnimationStateMachine does not exist" (13:10) -- on a unit
            -- whose machine instance the disable had taken away. So the
            -- machine is enabled again first (the spawner's portrait idle
            -- comes back for a frame), then replaced; both calls are
            -- tried and both errors are kept, so the next log says which.
            pcall(Unit.enable_animation_state_machine, state.unit)
            local had = Unit.has_animation_state_machine and Unit.has_animation_state_machine(state.unit)
            local set_ok, set_err = pcall(Unit.set_animation_state_machine, state.unit, machine)
            if not set_ok then
                local blend_ok, blend_err = pcall(Unit.set_animation_state_machine_blend_base_layer, state.unit, machine, 0)
                if not blend_ok then
                    error(string.format("had_machine=%s set:%s blend:%s", tostring(had),
                        tostring(set_err):sub(1, 90), tostring(blend_err):sub(1, 90)))
                end
            end
            for name, value in pairs(init or {}) do
                local id = Unit.animation_find_variable(state.unit, name)
                if id then
                    Unit.animation_set_variable(state.unit, id, type(value) == "function" and value(state.unit) or value)
                end
            end
            state.machine = machine
            state.machine_variables = {}
            mod:info("DARKTIDEVR_BODY_MIRROR animated_legs=live machine=%s template=%s", tostring(machine),
                tostring(wielded_template.name))
        end)
        if not ok then
            state.machine = nil
            -- The machine was enabled above for the attempt; it goes off
            -- again, and the gait has the legs. The 13:20 worn run decided
            -- what a running machine does to this copy: with the spawner's
            -- idle left running and the whole solved pose written back at
            -- the render boundary, the drawn body stood in the idle, still,
            -- with no hand tracking, while the scene graph held the solve
            -- (17,369 render checks, no drift). A running machine owns the
            -- skin; with it disabled the joints written in post_update are
            -- drawn (the days before, and 14:36).
            pcall(Unit.disable_animation_state_machine, state.unit)
            log_once("machine_" .. tostring(wielded_template and wielded_template.name), "animated_legs=failed error=%s",
                tostring(err):sub(1, 220))
        end
        return ok
    end
    function api.wielded(weapon_template)
        wielded_template = weapon_template
        if state and state.unit then assign_machine() end
    end
    function api.forward_anim_event(event_name, method, ...)
        if not state or not state.machine or not state.unit or not Unit.alive(state.unit) then return end
        local unit = state.unit
        -- The variables, captured here: a closure cannot see the vararg.
        local n, args = select("#", ...), {...}
        local ok = pcall(function()
            if method == "anim_event_with_variable_float" or method == "anim_event_with_variable_int" then
                local name, value = args[1], args[2]
                local id = name and Unit.animation_find_variable(unit, name)
                if id and value ~= nil then Unit.animation_set_variable(unit, id, value) end
            elseif method == "anim_event_with_variable_floats" then
                for i = 1, n, 2 do
                    local name, value = args[i], args[i + 1]
                    local id = name and Unit.animation_find_variable(unit, name)
                    if id and value ~= nil then Unit.animation_set_variable(unit, id, value) end
                end
            end
            Unit.animation_event(unit, event_name)
        end)
        if not ok then log_once("anim_event", "animated_legs=event_failed event=%s", tostring(event_name)) end
    end

    -- THE PRE-RENDER CHECK (19 September). Called from the ScriptWorld.render
    -- hook, the last Lua boundary before the frame is drawn and after the
    -- engine's own world update: reads the copy's root and right hand again
    -- and compares them with what this module left at the end of its own
    -- update. A drift here is a writer this module cannot see -- the engine
    -- re-applying a frozen animation frame, something moving the unit after
    -- the post-update -- and the flicker the probe could not find would be
    -- one. Logs the first 200 drifts of a millimetre or more with the frame
    -- they happened on, and a summary every 600 checks either way, so a
    -- clean result is also written down.
    -- Every call is counted and every early return has a reason, and the
    -- summary is written every 600 CALLS whatever they did: two worn runs
    -- (12:22, 13:02) got silence from this check, the second because it
    -- compared the snapshot's frame number with a counter that increments
    -- AFTER the snapshot, so the equality never held. A stamp taken at the
    -- snapshot and consumed here cannot do that.
    local checks, drifts, drift_lines, calls = 0, 0, 0, 0
    local skipped = {}
    -- The linked children against the skeleton: at the render boundary
    -- (child_render_*) and as the update left them before its children
    -- flush (child_update_*, from state.child_before).
    local child_render_over, child_render_max, child_render_worst = 0, 0, "none"
    local child_update_over, child_update_max = 0, 0
    -- After the render (check_after_render) and between frames
    -- (the top of api.update): how often and how far the copy moved.
    local after_checks, after_moved, after_max = 0, 0, 0
    local between_checks, between_moved, between_max = 0, 0, 0
    -- The eye at the render boundary against the eye the pose was built
    -- on (render_eye_lag in the heartbeat): the view's lag on the copy.
    local eye_lag_checks, eye_lag_over, eye_lag_max = 0, 0, 0
    -- THE CHILDREN (19 September, 13:47 worn run). Everything drawn of the
    -- copy is a child unit: the gear, the hands, the head with its eye
    -- lenses, each linked to the copy's skeleton by the profile spawner
    -- (World.link_unit with a node map). The user: the drawn body flickers
    -- "between exactly two locations, one of which looks like the correct
    -- location"; the recording's eye lenses jump 12 px on average and up to
    -- 82 px at 1920 wide against a background moving 4 px. Every check so
    -- far read the copy's OWN joints, which were always where the solve put
    -- them. This reads the children: for each linked unit that carries one
    -- of the named joints, the distance between its joint and the copy's
    -- same joint. Zero means the child stands where the skeleton is.
    local CHILD_JOINTS = {"j_head", "j_righthand", "j_lefthand", "j_hips", "j_neck"}
    local function collect_children(unit, data)
        local children = {}
        local function consider(slot_name, child)
            if not child or child == unit or not Unit.alive(child) then return end
            for _, name in ipairs(CHILD_JOINTS) do
                if Unit.has_node(child, name) and Unit.has_node(unit, name) then
                    children[#children + 1] = {unit = child, node = Unit.node(child, name), parent_node = Unit.node(unit, name),
                        name = slot_name .. ":" .. name}
                end
            end
        end
        for slot_name, slot in pairs(data and data.slots or {}) do
            consider(slot_name, slot.unit_3p)
            local attachments = slot.unit_3p and slot.attachments_by_unit_3p and slot.attachments_by_unit_3p[slot.unit_3p]
            for _, attachment in ipairs(attachments or {}) do consider(slot_name .. "/attachment", attachment) end
        end
        return children
    end
    local function measure_children(unit, children)
        local worst, worst_name = 0, "none"
        for _, child in ipairs(children or {}) do
            if Unit.alive(child.unit) then
                local d = Vector3.distance(Unit.world_position(child.unit, child.node), Unit.world_position(unit, child.parent_node))
                if d > worst then worst, worst_name = d, child.name end
            end
        end
        return worst, worst_name
    end
    local function skip(reason)
        skipped[reason] = (skipped[reason] or 0) + 1
    end
    local function summary()
        local parts = {}
        for reason, count in pairs(skipped) do parts[#parts + 1] = reason .. "=" .. count end
        table.sort(parts)
        mod:info("DARKTIDEVR_BODY_MIRROR prerender calls=%d checks=%d drifted=%d child_render_over_1mm=%d child_render_max_m=%.4f child_render_worst=%s child_update_over_1mm=%d child_update_max_m=%.4f after_render=%d/%d max_m=%.4f between_frames=%d/%d max_m=%.4f render_eye_lag=%d/%d max_m=%.4f skipped=%s",
            calls, checks, drifts, child_render_over, child_render_max, tostring(child_render_worst),
            child_update_over, child_update_max, after_moved, after_checks, after_max,
            between_moved, between_checks, between_max, eye_lag_over, eye_lag_checks, eye_lag_max,
            #parts > 0 and table.concat(parts, ",") or "none")
    end
    function api.check_before_render(world)
        calls = calls + 1
        if calls % 600 == 0 then summary() end
        if not state or not state.unit then skip("no_copy"); return end
        if not state.render_check then skip("no_snapshot"); return end
        if world ~= state.world then skip("other_world"); return end
        if not Unit.alive(state.unit) then skip("unit_dead"); return end
        if state.render_check.stamp == state.checked_stamp then skip("already_checked"); return end
        state.checked_stamp = state.render_check.stamp
        local unit = state.unit
        -- Nothing is written here any more. Until 13:20 on 19 September the
        -- animated-legs mode put its solved joints back over the machine's
        -- at this boundary; the worn run showed the drawn body ignoring
        -- them (it stood in the idle while these reads held the solve), so
        -- a write here cannot reach the skin, and this is a read-only check
        -- of what happened to the copy between the module's pose in
        -- post_update and the render.
        local root = array(Unit.world_position(unit, 1))
        local hand = array(Unit.world_position(unit, Unit.node(unit, "j_righthand")))
        local d_root = Mirror.step_m(root, state.render_check.root) or 0
        local d_hand = Mirror.step_m(hand, state.render_check.hand) or 0
        checks = checks + 1
        -- The eye now against the eye the copy was posed from: the lag the
        -- view sees between the camera's anchor and the copy's.
        if state.posed_eye and presentation.eye_pose then
            local eye_now = presentation.eye_pose(state.avatar)
            local lag = eye_now and Mirror.step_m(array(eye_now), state.posed_eye) or 0
            eye_lag_checks = eye_lag_checks + 1
            if lag >= 0.005 then eye_lag_over = eye_lag_over + 1 end
            if lag > eye_lag_max then eye_lag_max = lag end
        end
        -- The children, read a third time, after the engine's world update.
        local child_render, child_render_name = measure_children(unit, state.children)
        if child_render >= 0.001 then child_render_over = child_render_over + 1 end
        if child_render > child_render_max then child_render_max, child_render_worst = child_render, child_render_name end
        if (state.child_before or 0) >= 0.001 then child_update_over = child_update_over + 1 end
        if (state.child_before or 0) > child_update_max then child_update_max = state.child_before end
        if d_root >= 0.001 or d_hand >= 0.001 then
            drifts = drifts + 1
            if drift_lines < 200 then
                drift_lines = drift_lines + 1
                mod:info("DARKTIDEVR_BODY_MIRROR prerender_drift frame=%d root_m=%.4f hand_m=%.4f root=%.3f,%.3f,%.3f was=%.3f,%.3f,%.3f",
                    state.frames, d_root, d_hand, root[1], root[2], root[3],
                    state.render_check.root[1], state.render_check.root[2], state.render_check.root[3])
            end
        end
    end

    function api.drawn_units()
        local units = {}
        if not state then return units end
        if state.unit and Unit.alive(state.unit) then
            units[#units + 1] = {label = "mirror_copy", unit = state.unit}
        end
        for slot_name, slot in pairs(state.data and state.data.slots or {}) do
            if slot.unit_3p and Unit.alive(slot.unit_3p) then
                units[#units + 1] = {label = "mirror_slot/" .. tostring(slot_name), unit = slot.unit_3p}
            end
        end
        return units
    end

    function api.destroy()
        destroy_own()
        if reflection then reflection.destroy() end
    end
    function log_once(key, format, ...)
        if logged[key] then return end
        logged[key] = true
        mod:info("DARKTIDEVR_BODY_MIRROR " .. format, ...)
    end
    local function inverse(rotation)
        local x, y, z, w = Quaternion.to_elements(rotation)
        return Quaternion.from_elements(-x, -y, -z, w)
    end
    function array(v) return {Vector3.x(v), Vector3.y(v), Vector3.z(v)} end
    function vector(a) return Vector3(a[1], a[2], a[3]) end
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
    -- THE REST POSE MADE NEUTRAL, AND THE CALIBRATION APPLIED TO IT (19
    -- September). The spawner's first frame is whatever its idle was doing:
    -- the 10:51 worn run froze a crouched combat stance, left foot 18 cm
    -- forward, torso turned right, and everything the copy draws starts
    -- from that frame -- "body is way too large, doesn't sit square". So
    -- at ready, in this order:
    --   1. the legs are measured (bone lengths, the ankle's height off the
    --      floor and its distance to the side) before anything moves;
    --   2. the height beyond the settable range, if any, is stretched into
    --      the leg and spine bones along their own axes (Mirror.height_stretch);
    --   3. the torso is turned square to the root and stood upright, by one
    --      rotation of the hips that takes the shoulder line to the root's
    --      right and the hips-to-neck axis to vertical;
    --   4. the hips are put at standing height for the legs' own lengths
    --      (Mirror.standing_hips_height);
    --   5. every joint moved is boxed back into state.rest, so each frame
    --      starts from the neutral pose, not the frozen stance.
    -- The feet's ideal places are then symmetric: hip-width either side,
    -- neither forward. The copy's SCALE is the game's own character height
    -- for the profile (PlayerHeight, the number the avatar gets), fixed for
    -- the session; nothing here scales the unit. Returns the leg
    -- measurements for the gait, or nil with a reason.
    local function prepare_rest(world, unit, profile)
        local function node(name) return Unit.has_node(unit, name) and Unit.node(unit, name) or nil end
        local hips, neck = node("j_hips"), node("j_neck")
        local left_shoulder, right_shoulder = node("j_leftarm"), node("j_rightarm")
        if not (hips and neck and left_shoulder and right_shoulder) then return nil, "torso_joints_missing" end
        local root_inverse = Matrix4x4.inverse(Unit.world_pose(unit, 1))
        local function root_local(position) return Matrix4x4.transform(root_inverse, position) end
        -- 1. The legs as spawned.
        local legs = {}
        for _, side in ipairs({"left", "right"}) do
            local hip, knee, ankle = node("j_" .. side .. "upleg"), node("j_" .. side .. "leg"), node("j_" .. side .. "foot")
            if not (hip and knee and ankle) then return nil, "leg_joints_missing" end
            local ankle_local = root_local(Unit.world_position(unit, ankle))
            -- The ankle's height above the SOLE, from the rig itself: the
            -- toe joint (j_*toebase, the ball of the foot) sits a known
            -- little above the sole, so ankle minus toe plus that is the
            -- ankle's height with the foot flat on the floor. The spawn
            -- frame's ankle height above the root was 0.101 m with the
            -- feet wherever the idle had them, and the worn run on it had
            -- "feet floating off the ground slightly" and the body "a
            -- little too high" by the same few centimetres, since the hips'
            -- standing height is built on this number too. VRIK anchors the
            -- toes to the footsteps for the same reason.
            local toe = node("j_" .. side .. "toebase")
            local ankle_above_sole = Vector3.z(ankle_local)
            local toe_z = nil
            if toe then
                toe_z = Vector3.z(root_local(Unit.world_position(unit, toe)))
                local from_toe = Vector3.z(ankle_local) - toe_z + Mirror.TOE_ABOVE_SOLE_M
                if from_toe > 0.02 and from_toe < 0.25 then ankle_above_sole = from_toe end
            end
            -- FLOAT (14:05 worn run): with the toe-derived height the toe
            -- joint stood 4.5-5.7 cm above the ground point at rest, where
            -- the spawn pose has it 2.7 cm up, and "the legs float". The
            -- spawn pose stands on the root's plane, so the ankle's height
            -- above the sole IS its height above the root there
            -- (spawn_ankle_z), and the toe's rest pitch below the ankle is
            -- what a flat foot looks like on this rig; both are kept and
            -- the solve restores the pitch each frame (see the gait block).
            local rest_pitch = nil
            if toe then
                local to_toe = Unit.world_position(unit, toe) - Unit.world_position(unit, ankle)
                local flat = math.sqrt(Vector3.x(to_toe) ^ 2 + Vector3.y(to_toe) ^ 2)
                rest_pitch = math.atan2(Vector3.z(to_toe), flat)
            end
            -- 14:20 worn run: the rest pitch read -28 deg and the solved
            -- pitch +4.7 after a correction that should have set it to
            -- the rest; whether the toe joint is under the ankle at all in
            -- this rig's graph is logged with the pitches.
            local toe_under_ankle = toe and Unit.scene_graph_parent(unit, toe) == ankle
            legs[side] = {side = side, hip = hip, knee = knee, ankle = ankle, toe = toe, rest_pitch = rest_pitch,
                toe_under_ankle = toe_under_ankle, toe_parent = toe and Unit.scene_graph_parent(unit, toe),
                upper = Vector3.length(Unit.world_position(unit, knee) - Unit.world_position(unit, hip)),
                lower = Vector3.length(Unit.world_position(unit, ankle) - Unit.world_position(unit, knee)),
                ankle_x = Vector3.x(ankle_local), ankle_z = Vector3.z(ankle_local),
                spawn_ankle_z = Vector3.z(ankle_local), toe_z = toe_z, toe_derived_z = ankle_above_sole}
        end
        local upper = (legs.left.upper + legs.right.upper) / 2
        local lower = (legs.left.lower + legs.right.lower) / 2
        local ankle_z = (legs.left.ankle_z + legs.right.ankle_z) / 2
        local width = (math.abs(legs.left.ankle_x) + math.abs(legs.right.ankle_x)) / 2
        -- The scale the game gives this profile, and the eye height the
        -- game puts its camera at for it (heights.default x scale, the
        -- first-person height). Beside it, the height the CAMERA actually
        -- sits at above the floor right now: this mod anchors the tracked
        -- eye to the avatar's eye, so the two agree and the stretch is 1.
        -- The 11:14 worn run compared the player's real standing eye height
        -- (1.723 m) with the avatar's (1.896 m) instead, compressed the
        -- copy by 11 % to a head the camera was not at, and drew a body
        -- "far too small". The residual that matters is between the copy
        -- and the camera, and it appears only if the camera is ever put
        -- somewhere other than the avatar's eye.
        local scale, character_eye, camera_eye = 1, nil, nil
        local ok_scale = pcall(function()
            local Breeds = require("scripts/settings/breed/breeds")
            local PlayerHeight = require("scripts/utilities/player_height")
            local breed = profile and profile.archetype and Breeds[profile.archetype.breed]
            if breed then
                scale = PlayerHeight.player_character_third_person_scale(breed, profile, nil) or 1
                character_eye = breed.heights and tonumber(breed.heights.default) and
                    tonumber(breed.heights.default) * scale or nil
            end
            local eye_position = avatar and Unit.alive(avatar) and presentation.eye_pose and presentation.eye_pose(avatar)
            if eye_position then
                camera_eye = Vector3.z(eye_position) - Vector3.z(Unit.world_position(avatar, 1))
            end
        end)
        if not ok_scale or not (scale > 0.1) then scale = 1 end
        -- 2. The chain from floor to neck at that scale, and the stretch.
        local chain = Vector3.z(root_local(Unit.world_position(unit, neck)))
        local k = Mirror.height_stretch(camera_eye, character_eye, chain * scale)
        local moved = {}
        -- Applied as the JOINTS' scales, so the skin stretches with the
        -- bones (see apply_arm_scales for why an offset alone will not do):
        -- the spine root carries k and everything above inherits it, with
        -- the head and the two clavicles carrying 1/k so the head and the
        -- arms stay their own size; each hip joint carries k and its foot
        -- 1/k. The hips' own offset from the root is a position below.
        local function scaled(index, factor)
            if index and k ~= 1 then
                Unit.set_local_scale(unit, index, Vector3(factor, factor, factor))
                moved[#moved + 1] = index
            end
        end
        scaled(node("j_spine"), k)
        for _, name in ipairs({"j_head", "j_leftshoulder", "j_rightshoulder"}) do scaled(node(name), 1 / k) end
        for _, leg in pairs(legs) do scaled(leg.hip, k); scaled(leg.ankle, 1 / k) end
        World.update_unit(world, unit)
        -- 3. Square and upright: the shoulder line to the root's right, the
        -- hips-to-neck axis to vertical, in one rotation of the hips.
        local root_rotation = Unit.world_rotation(unit, 1)
        local hips_w = Unit.world_position(unit, hips)
        local up_now = Unit.world_position(unit, neck) - hips_w
        local right_now = Unit.world_position(unit, right_shoulder) - Unit.world_position(unit, left_shoulder)
        local yaw_fix = 0
        if Vector3.length(up_now) > 1e-4 and Vector3.length(right_now) > 1e-4 then
            up_now = Vector3.normalize(up_now)
            right_now = right_now - up_now * Vector3.dot(right_now, up_now)
            if Vector3.length(right_now) > 1e-4 then
                right_now = Vector3.normalize(right_now)
                local q_now = Quaternion.look(Vector3.cross(up_now, right_now), up_now)
                local q_want = Quaternion.look(Quaternion.forward(root_rotation), Vector3.up())
                yaw_fix = math.deg(math.atan2(Vector3.y(right_now) * Vector3.x(Quaternion.right(root_rotation)) -
                    Vector3.x(right_now) * Vector3.y(Quaternion.right(root_rotation)),
                    Vector3.dot(right_now, Quaternion.right(root_rotation))))
                set_world_rotation(unit, hips, Quaternion.multiply(Quaternion.multiply(q_want, inverse(q_now)),
                    Unit.world_rotation(unit, hips)))
                World.update_unit(world, unit)
                moved[#moved + 1] = hips
            end
        end
        -- 4. The hips at standing height for these legs.
        local standing = Mirror.standing_hips_height(ankle_z, upper, lower, k)
        local hips_z_before = Vector3.z(root_local(Unit.world_position(unit, hips)))
        if standing then
            local parent = Unit.scene_graph_parent(unit, hips)
            local parent_rotation = parent and Unit.world_rotation(unit, parent) or root_rotation
            Unit.set_local_position(unit, hips, Unit.local_position(unit, hips) +
                Quaternion.rotate(inverse(parent_rotation), Vector3(0, 0, standing - hips_z_before)))
            World.update_unit(world, unit)
            moved[#moved + 1] = hips
        end
        -- 5. Boxed back as the rest pose.
        for _, index in ipairs(moved) do state.rest[index] = Matrix4x4Box(Unit.local_pose(unit, index)) end
        -- The foot's rest rotation about the root, from the squared pose.
        local root_rotation_inverse = inverse(Unit.world_rotation(unit, 1))
        for _, leg in pairs(legs) do
            leg.rest_foot_rotation = QuaternionBox(Quaternion.multiply(root_rotation_inverse,
                Unit.world_rotation(unit, leg.ankle)))
        end
        mod:info("DARKTIDEVR_BODY_MIRROR rest scale=%.4f character_eye_m=%s camera_eye_m=%s chain_m=%.3f stretch=%.4f " ..
            "torso_yaw_fix_deg=%.1f hips_z_m=%.3f->%.3f upper_m=%.3f lower_m=%.3f ankle_z_m=%.3f spawn_ankle_z_m=%.3f toe_z_m=%s width_m=%.3f",
            scale, character_eye and string.format("%.3f", character_eye) or "none",
            camera_eye and string.format("%.3f", camera_eye) or "none", chain, k, yaw_fix,
            hips_z_before, standing or hips_z_before, upper, lower, ankle_z,
            (legs.left.spawn_ankle_z + legs.right.spawn_ankle_z) / 2,
            legs.left.toe_z and string.format("%.3f", legs.left.toe_z) or "none", width)
        return {legs = legs, scale = scale, stretch = k,
            offsets = {left = {-width, 0, 0}, right = {width, 0, 0}},
            ankle_height = {left = ankle_z, right = ankle_z}}
    end
    -- The three arm joints' scales for an upper-arm factor and a forearm
    -- factor: the upper arm carries su, the forearm sl/su so its world scale
    -- is sl, the hand 1/sl so it is its own size (and so are the fingers
    -- under it). Uniform, so the joints' rotations do not shear anything.
    local function apply_arm_scales(world, unit, arm)
        local su, sl = arm.scale_upper or 1, arm.scale_lower or 1
        if not (su > 1e-3) or not (sl > 1e-3) then return end
        Unit.set_local_scale(unit, arm.arm, Vector3(su, su, su))
        Unit.set_local_scale(unit, arm.forearm, Vector3(sl / su, sl / su, sl / su))
        Unit.set_local_scale(unit, arm.hand, Vector3(1 / sl, 1 / sl, 1 / sl))
        World.update_unit(world, unit)
    end
    local function solve_arm(world, avatar, unit, arm)
        -- The final visible wrist pose (tracked, gun-aligned or on the support
        -- grip), whatever the mode: the gloves record it when they draw the
        -- hands, the rig records it when the copy does. With no pose recorded
        -- the arm stays at rest. Until 19 September the fallback was the
        -- avatar's animated hand joint, which put the stock animation on the
        -- mirror key's copy; nothing on a drawn body follows the animation.
        local target, target_rotation
        if body_proxy() and body_proxy().hand_pose then
            target, target_rotation = body_proxy().hand_pose(arm.side)
        end
        if not target then
            arm.error = nil
            return
        end
        Unit.set_local_position(unit, arm.forearm, arm.rest_forearm:unbox())
        Unit.set_local_position(unit, arm.hand, arm.rest_hand:unbox())
        -- THE BONES ARE SCALED, NOT THEIR OFFSETS (19 September). Until now
        -- a calibrated length moved the child joint along the bone and left
        -- the skin where it was: a forearm bone shortened to the calibration
        -- kept a forearm mesh of the authored length, which overhung the
        -- wrist when the arm was bent ("with my hands close to me the wrist
        -- moves down into the forearm"), and the reach stretch moved the
        -- hand joint past the mesh's end ("when I reach out the hands
        -- disconnect from the forearm and float away"). A joint's SCALE
        -- reaches its skin: the upper arm scaled by su stretches its mesh
        -- and moves the forearm joint with it; the forearm carries sl/su so
        -- it ends at sl; the hand carries 1/sl so it is its own size.
        -- Uniform scales compose whatever the joints' rotations are.
        arm.scale_upper, arm.scale_lower = 1, 1
        local lengths = Mirror.MODES[mode_name].arm_length and state.arm_lengths
        if lengths then
            local config = Mirror.MODES[mode_name].arm_length
            World.update_unit(world, unit)
            local rest_upper = Vector3.length(Unit.world_position(unit, arm.forearm) - Unit.world_position(unit, arm.arm))
            local rest_lower = Vector3.length(Unit.world_position(unit, arm.hand) - Unit.world_position(unit, arm.forearm))
            local function ratio(desired, current)
                if not (current > 1e-4) then return 1 end
                return math.max(config.min, math.min(config.max, desired / current))
            end
            arm.length_ratio_upper, arm.length_ratio_lower = ratio(lengths.upper, rest_upper), ratio(lengths.lower, rest_lower)
            arm.scale_upper, arm.scale_lower = arm.length_ratio_upper, arm.length_ratio_lower
        end
        apply_arm_scales(world, unit, arm)
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
                -- The drawn segments lengthen too, skin and all: the bones'
                -- scales, not their offsets.
                arm.scale_upper, arm.scale_lower = arm.scale_upper * ratio, arm.scale_lower * ratio
                apply_arm_scales(world, unit, arm)
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
        -- How far the drawn hand's rotation is from the recorded wrist pose
        -- after the write, for the log ("not quite correctly aligned with
        -- weapons"): the weapon is placed from the same pose, so a hand
        -- that matches it here and still sits wrong on the gun puts the
        -- difference in the equipment sync, not in this solve.
        local ax, ay, az, aw = Quaternion.to_elements(Unit.world_rotation(unit, arm.hand))
        local bx, by, bz, bw = Quaternion.to_elements(target_rotation)
        local dot = math.min(1, math.abs(ax * bx + ay * by + az * bz + aw * bw))
        arm.angle_error = math.deg(2 * math.acos(dot))
        arm.distance = Vector3.length(target - shoulder)
        if not reachable then
            arm.unreachable = arm.unreachable + 1
            arm.max_stretch = math.max(arm.max_stretch or 0, arm.stretch)
        end
        arm.error = Vector3.length(Unit.world_position(unit, arm.hand) - target)
    end
    -- Take the collision off everything the copy owns. Mirrors what
    -- darktidevr_body_proxy does for its own spawned units, which the mirror
    -- never did -- see Mirror.collider_units for what that cost.
    local function disable_colliders(root, data, avatar)
        local disabled, actors = 0, 0
        for _, unit in ipairs(Mirror.collider_units(root, data, avatar)) do
            if Unit.alive(unit) then
                local count = Unit.num_actors(unit)
                for index = 1, count do
                    local actor = Unit.actor(unit, index)
                    -- Stock deployable/pickup loops also allow empty slots.
                    if actor then
                        Actor.set_collision_enabled(actor, false)
                        Actor.set_scene_query_enabled(actor, false)
                        actors = actors + 1
                    end
                end
                disabled = disabled + 1
            end
        end
        mod:info("DARKTIDEVR_BODY_MIRROR colliders=disabled units=%d actors=%d", disabled, actors)
    end

    -- THE SMOOTH TIMELINE (19 September, from the motion probe). The eye the
    -- copy is placed from is re-based each frame on the body anchor, and the
    -- anchor is the first-person component's position, which the game
    -- writes in its FIXED update: at 140 frames a second it stands still for
    -- two or three frames and then jumps 3-5 cm, and the probe showed the
    -- neck target and the copy's root doing exactly that (smoothness 0.12)
    -- while the avatar's root, which the game interpolates every frame,
    -- moved 1.5 cm every frame (0.87). "The body is alternating between two
    -- positions each frame." The game's first-person UNIT carries the same
    -- point on the smooth timeline (the interpolated root plus the height,
    -- set in update_unit_position), so the difference between the two is
    -- the anchor's lag this frame, and adding it to the eye puts the copy on
    -- the timeline the view is on. It is a read of the avatar's camera
    -- point, not of its animation.
    local function smooth_offset(avatar)
        local first_person = avatar and Unit.alive(avatar) and ScriptUnit.has_extension(avatar, "first_person_system")
        local component = first_person and first_person._first_person_component
        local eye_unit = first_person and first_person.first_person_unit and first_person:first_person_unit()
        if not component or not component.position or not eye_unit or not Unit.alive(eye_unit) then return nil end
        local lag = Unit.world_position(eye_unit, 1) - component.position
        -- A step, not a jump: past this the two are not the same point.
        if Vector3.length(lag) > 0.5 then return nil end
        return lag
    end
    -- Where the copy stands. The avatar's ROOT POSITION is the one thing
    -- the drawn body takes from it: it is the simulated place the player is,
    -- not animation, and the feet have to be there. Its heading is the body
    -- frame's (state.yaw, set below each frame); before the first frame it
    -- keeps the heading it was spawned with. Its scale is its own -- the
    -- neck scale below -- never the avatar's. The user's rule (19
    -- September): the base model exists hidden for hit detection, and there
    -- is no relationship between it and the custom-IK body beyond what the
    -- weapon needs.
    local function place(avatar, unit)
        local mode = Mirror.MODES[mode_name] or Mirror.MODES.mirror
        local rotation = state.yaw and Quaternion(Vector3.up(), state.yaw) or Unit.local_rotation(unit, 1)
        if mode.facing and not state.yaw then
            -- Spawned facing away from the player; the mirror faces them.
            rotation = Quaternion.multiply(rotation, Quaternion(Vector3.up(), math.pi))
        end
        local position = Unit.world_position(avatar, 1) + Quaternion.forward(rotation) * mode.distance
        Unit.set_local_position(unit, 1, position)
        Unit.set_local_rotation(unit, 1, mode.facing and
            Quaternion.multiply(rotation, Quaternion(Vector3.up(), math.pi)) or rotation)
        local s = state.scale or 1
        Unit.set_local_scale(unit, 1, Vector3(s, s, s))
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
        state = {world = world, avatar = avatar, unit_spawner = unit_spawner, profile_spawner = profile_spawner, frames = 0,
            profile = profile}
        mod:info("DARKTIDEVR_BODY_MIRROR spawn mode=%s kept_slots=%d ignored_slots=%d", tostring(mode_name), kept, ignored)
        -- THE MARKER (14:05 worn run), a labelled experiment. The flicker is
        -- on the copy, its hands and the servo-skulls; not on the weapon or
        -- the rigid gloves of the hands-only mode. The gloves are the one
        -- thing the mod draws that is placed by moving a unit's ROOT only,
        -- so one is spawned here the way the hands-only mode spawns them
        -- (a profile with only the glove item, no state machine asked for)
        -- and stood at the copy's head every frame by its root, with the
        -- copy's own numbers. What it tells: if the glove at your head holds
        -- still while the body under it flickers, the pose the module
        -- computes is steady and the fault is in how the linked, machine-
        -- bearing copy is drawn; if the glove flickers with the body, the
        -- pose itself alternates and every Lua check so far has read it at
        -- the wrong moments. Overlay modes only.
        if not Mirror.MODES[mode_name].reflect then
            local ok, err = pcall(function()
                local MasterItems = require("scripts/backend/master_items")
                local item = MasterItems.get_item("content/items/characters/player/human/gear_hands/hmn_gloves_b_left_only")
                if not item then error("glove item unavailable") end
                local marker_unit_spawner = UIUnitSpawner:new(world)
                local marker_spawner = UIProfileSpawner:new("DarktideVRBodyMarker", world, nil, marker_unit_spawner, false)
                for slot_name, settings in pairs(ItemSlotSettings) do
                    if slot_name ~= "slot_gear_upperbody" and slot_name ~= "slot_unarmed" and
                            not settings.ignore_character_spawning then
                        marker_spawner:ignore_slot(slot_name)
                    end
                end
                local marker_profile = table.clone_instance(profile)
                marker_profile.loadout = table.clone_instance(profile.loadout)
                marker_profile.loadout.slot_gear_upperbody = item
                marker_spawner:spawn_profile(marker_profile, Unit.world_position(avatar, 1), rotation,
                    nil, nil, nil, nil, nil, false, false, nil, true)
                state.marker_unit_spawner, state.marker_profile_spawner = marker_unit_spawner, marker_spawner
            end)
            if not ok then log_once("marker", "marker=failed error=%s", tostring(err):sub(1, 160)) end
        end
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
            -- The copy is posed by NAMED joints of its own rig now, never by
            -- index from the avatar, so the avatar's layout is no longer
            -- compared with it (Mirror.same_layout stays for its test). What
            -- has to be true is that the copy carries the joints the solve
            -- moves.
            state.same_layout = Mirror.has_solve_joints(
                function(name) return Unit.has_node(unit, name) end)
            state.count = Unit.num_scene_graph_items(unit)
            state.children = collect_children(unit, data)
            mod:info("DARKTIDEVR_BODY_MIRROR children linked=%d joints=%s", #state.children,
                (function() local names = {}; for _, c in ipairs(state.children) do names[#names + 1] = c.name end
                    table.sort(names); return table.concat(names, ",") end)())
            -- MACHINES (14:05 worn run). The flicker is on the copy, its
            -- hands, and the servo-skulls the mod places; not on the weapon
            -- or the rigid gloves. Which of these units carry an animation
            -- state machine is a fact the engine can be asked for; this
            -- line lists it for the copy, each linked child, and the
            -- avatar's weapon units, so the pattern can be read off.
            if Unit.has_animation_state_machine then
                local parts = {"copy=" .. tostring(Unit.has_animation_state_machine(unit))}
                for slot_name, slot in pairs(data.slots or {}) do
                    if slot.unit_3p and Unit.alive(slot.unit_3p) then
                        parts[#parts + 1] = slot_name .. "=" .. tostring(Unit.has_animation_state_machine(slot.unit_3p))
                    end
                end
                local loadout = ScriptUnit.has_extension(avatar, "visual_loadout_system")
                for _, slot_name in ipairs({"slot_primary", "slot_secondary"}) do
                    local ok, weapon = pcall(function() return loadout and loadout:unit_3p_from_slot(slot_name) end)
                    if ok and weapon and Unit.alive(weapon) then
                        parts[#parts + 1] = "avatar_" .. slot_name .. "=" .. tostring(Unit.has_animation_state_machine(weapon))
                    end
                end
                table.sort(parts)
                mod:info("DARKTIDEVR_BODY_MIRROR machines %s", table.concat(parts, " "))
            end
            capture_arms(unit)
            -- THE REST POSE. Every joint below the root, as the spawner left
            -- it on this frame, boxed once. This is the whole of what the
            -- copy is posed from: the user's instruction (19 September) is
            -- that the drawn body is the new custom IK wholesale, with
            -- nothing on it driven by the stock animation -- not the idle
            -- sway, not the stance shift in the sights, and not the legs
            -- either (the legs-from-the-avatar hybrid in the 15 September
            -- design was never asked for). Each frame starts from this pose
            -- and the solves below move what tracking says to move.
            state.rest = {}
            for index = 2, state.count do
                state.rest[index] = Matrix4x4Box(Unit.local_pose(unit, index))
            end
            -- The rest pose made neutral and the calibration applied (see
            -- prepare_rest); the legs and the gait from what it measured.
            -- The offsets are at scale 1; the gait scales them with the copy.
            state.legs, state.gait, state.scale = nil, nil, 1
            local ok_rest, rest, why = pcall(prepare_rest, world, unit, state.profile)
            if ok_rest and rest then
                local Gait = mod:io_dofile("darktidevr/scripts/mods/darktidevr/darktidevr_body_gait")
                state.scale = rest.scale
                state.legs, state.gait_module = rest.legs, Gait
                state.gait = Gait.new(rest.offsets)
                state.ankle_height = rest.ankle_height
                mod:info("DARKTIDEVR_BODY_MIRROR gait=ready left=%.3f,%.3f,%.3f right=%.3f,%.3f,%.3f",
                    rest.offsets.left[1], rest.offsets.left[2], rest.ankle_height.left,
                    rest.offsets.right[1], rest.offsets.right[2], rest.ankle_height.right)
            else
                log_once("rest", "rest=raw gait=skipped reason=%s", tostring(ok_rest and why or rest):sub(1, 160))
            end
            -- Animated legs: which indices are the legs (left alone by the
            -- snapshot and restore), and the machine if a weapon is known.
            -- The machine is not enabled on the copy until it is assigned:
            -- until then the spawner's disabled idle stays frozen.
            state.machine, state.leg_indices, state.legs_from_avatar = nil, nil, nil
            if Mirror.MODES[mode_name].animated_legs and state.legs then
                local roots = {[state.legs.left.hip] = true, [state.legs.right.hip] = true}
                state.leg_indices = Mirror.leg_indices(state.count,
                    function(index) return Unit.scene_graph_parent(unit, index) end, roots)
                -- LEGS FROM THE STOCK MODEL (begin). The user, 14:44 on 19
                -- September, with the flicker gone: "try re-enabling the
                -- original 3p model legs and attaching them to the torso,
                -- since the custom-ik run animation is really bad". The
                -- legs are the one part of the drawn body that now comes
                -- from the base model's animation: every frame the local
                -- pose of each joint under the two upper legs is copied
                -- from the avatar onto the copy, so the legs hang from the
                -- copy's own hips, wherever the solve has put them, and
                -- run with the game's clips. Nothing above the hips is
                -- read. The copy is spawned from the same profile as the
                -- avatar, so the joints share indices; that is checked here
                -- by name, and a mismatch keeps the gait.
                local probes = {"j_hips", "j_leftupleg", "j_leftleg", "j_leftfoot", "j_lefttoebase",
                    "j_rightupleg", "j_rightleg", "j_rightfoot", "j_righttoebase"}
                local same = Mirror.same_layout(state.count, Unit.num_scene_graph_items(avatar),
                    function(name) return Unit.has_node(unit, name) and Unit.node(unit, name) or nil end,
                    function(name) return Unit.has_node(avatar, name) and Unit.node(avatar, name) or nil end,
                    probes)
                state.legs_from_avatar = same or nil
                if not same then log_once("stock_legs_layout", "stock_legs=refused reason=layout_differs") end
                -- LEGS FROM THE STOCK MODEL (end).
                mod:info("DARKTIDEVR_BODY_MIRROR animated_legs=ready legs=%s leg_joints=%d",
                    same and "stock" or "gait",
                    (function() local n = 0; for _ in pairs(state.leg_indices) do n = n + 1 end; return n end)())
            end
            -- Deferred: see hide_near_eye. The scale eases over about a
            -- second, so the scan waits for it to settle and for a camera.
            state.near_eye_pending = Mirror.MODES[mode_name].near_eye or nil
            -- Only a copy that can be posed takes the hands. A layout
            -- mismatch (below) hides the copy and never poses it; had it
            -- taken the rig first, the gloves would be gone, the source arms
            -- hidden on the rig's account, and the player left with a
            -- floating weapon and no hands at all.
            if Mirror.MODES[mode_name].hand_rig and state.same_layout and body_proxy() and
                    body_proxy().set_hand_rig then
                -- Before the first copy: the wrist basis comes from this spawn pose.
                state.hand_rig = body_proxy().set_hand_rig(unit)
                mod:info("DARKTIDEVR_BODY_MIRROR hand_rig=%s", tostring(state.hand_rig))
            elseif Mirror.MODES[mode_name].hand_rig then
                log_once("hand_rig_layout", "hand_rig=skipped reason=rig_incomplete")
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
            -- Before the copy is ever posed on the player: a single frame of
            -- it holding collision is a frame of shots stopping at range zero.
            local ok_colliders, collider_error = pcall(disable_colliders, unit, data, avatar)
            if not ok_colliders then
                log_once("colliders", "colliders=failed error=%s",
                    tostring(collider_error):sub(1, 120))
            end
            state.colliders_disabled = ok_colliders
            mod:info("DARKTIDEVR_BODY_MIRROR ready mode=%s nodes=%d solve_joints=%s spawned_slots=%d hidden_slots=%s",
                tostring(mode_name), state.count, tostring(state.same_layout), slots,
                #hidden > 0 and table.concat(hidden, ",") or "none")
        end
        local unit = state.unit
        if not Unit.alive(unit) then destroy_own(); return end
        if not state.same_layout then
            log_once("layout", "copy=skipped reason=rig_incomplete mode=%s hidden=%s",
                tostring(mode_name), tostring(Mirror.MODES[mode_name].distance == 0))
            -- A copy this module cannot pose is not left standing where the
            -- player is. Every mode that spawns it on them (distance 0) hides
            -- its head only after the pose is applied, and the reflection is
            -- moved off them only at the end of a posed frame, so a rig
            -- missing a joint the solve moves would otherwise leave a whole
            -- character, head included, inside the player's view. It is
            -- hidden rather than destroyed: destroying it here would spawn
            -- another next frame.
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
        -- Every joint below the root back to the rest pose. Until 19
        -- September this copied the avatar's local pose after its own
        -- animation, which is how the idle sway and the stance shift in the
        -- sights reached the drawn body ("the body still appears to use the
        -- base game animations ... which it was explicitly instructed not
        -- to do"). Nothing is read from the avatar's joints now; the root's
        -- position is the one thing taken from it, in place() below.
        for index = 2, state.count do
            Unit.set_local_pose(unit, index, state.rest[index]:unbox())
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
            -- No turn-leak correction any more (Mirror.root_yaw_leak stays
            -- for the record and its test). The leak was the avatar's
            -- counter-rotation arriving through the COPIED spine; with the
            -- spine at rest there is nothing to cancel, and the torso faces
            -- the body frame's heading because the root does.
            state.root_yaw_leak = nil
            World.update_unit(world, unit)
        end
        -- Everything placed from the frame this frame is shifted onto the
        -- smooth timeline by the anchor's lag (see smooth_offset).
        -- ONE TIMELINE (14:26 worn run, the probe with the solved joints in
        -- it). While the player moves, the eye steps 0 then 6 cm a frame:
        -- it is stored against the fixed-step body anchor, as the recorded
        -- wrist targets are (0 then 6 cm on the same frames), as the camera
        -- is. The weapon and the rigid gloves hold still against the view
        -- because they step with it. The neck target, the eye plus this
        -- morning's "smooth" shift, stepped 3 then 8 cm -- the shift no
        -- longer cancels the eye's step frame by frame -- and the root,
        -- moved to put the neck on that target, stepped with it; the head,
        -- the marker glove, everything above the root alternated against a
        -- view that did not. "The flicker only occurs when moving, not when
        -- looking around or waving the hands." So the shift is off: the
        -- targets are the frame's, on the anchor's timeline, and the root
        -- lands where the neck follow puts it, on that timeline too. The
        -- lag is still measured for the probe (anchor_lag_m), and the probe
        -- gains the root's step against the eye (d_unit_rel_eye_m), which
        -- is what the view sees: near zero while walking straight.
        state.smooth_lag = smooth_offset(avatar)
        -- The eye this pose is built on, for the render check's lag read.
        local posed_eye = presentation.eye_pose and presentation.eye_pose(avatar)
        state.posed_eye = posed_eye and array(posed_eye) or nil
        local neck_target = frame and Mirror.neck_target(frame.neck, frame.head_yaw, frame.scale)
        if Mirror.MODES[mode_name].follow_neck and Unit.has_node(unit, "j_neck") then
            -- NO SCALING TO THE NECK any more (19 September). The copy's
            -- scale is the game's own character height for this profile,
            -- which the calibration sets, applied once at ready (state.scale)
            -- and never changed: "calibration should set the character
            -- height too, so there should be no need to ever do any further
            -- scaling". The `scale_to_neck` mode flag is inert. What chased
            -- the head to the 1.3 cap in the 10:51 worn run was a rest pose
            -- frozen in a crouched combat stance, fixed at ready below, not a
            -- body that needed to be bigger.
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
        -- THE GAIT (19 September). The feet are planted in the world and
        -- step under the root when it leaves them (darktidevr_body_gait);
        -- the legs are then two-bone solved from hip to ankle, the knee
        -- bending the way the rest pose bends it. The root is wherever the
        -- neck follow put it this frame, so room-scale movement and stick
        -- movement both reach the feet through the same root. The ground is
        -- the avatar's root height: the simulated floor under the player, a
        -- root read.
        -- ANIMATED LEGS, when the machine is live: the per-frame inputs the
        -- game writes on the avatar every frame -- the three cached
        -- third-person variables, of which anim_move_speed is the one the
        -- locomotion blend runs on -- are read off the avatar and set on
        -- the copy, and the gait stands down. Events arrive through
        -- api.forward_anim_event. This is a read of the avatar's animation
        -- INPUTS, which the user chose over its pose; the guard's rule on
        -- joints stands.
        local animated = state.machine ~= nil and state.leg_indices ~= nil
        -- LEGS FROM THE STOCK MODEL (begin): see the ready block. The leg
        -- joints' local poses, from the avatar's animation, onto the copy;
        -- the gait stands down. Measured on the periodic line below as
        -- stock_legs: the copy's hips and the avatar's hips above their
        -- roots, and the copy's toes above the avatar's floor.
        if state.legs_from_avatar and state.leg_indices then
            local ok = pcall(function()
                for index in pairs(state.leg_indices) do
                    Unit.set_local_pose(unit, index, Unit.local_pose(avatar, index))
                end
                World.update_unit(world, unit)
            end)
            if ok then animated = true else log_once("stock_legs_copy", "stock_legs=copy_failed") end
            if state.frames % 900 == 0 and Unit.has_node(unit, "j_hips") and Unit.has_node(avatar, "j_hips") then
                local floor = Vector3.z(Unit.world_position(avatar, 1))
                local function toe(side)
                    local name = "j_" .. side .. "toebase"
                    return Unit.has_node(unit, name) and string.format("%.3f", Vector3.z(Unit.world_position(unit, Unit.node(unit, name))) - floor) or "na"
                end
                mod:info("DARKTIDEVR_BODY_MIRROR stock_legs hips_copy_above_floor_m=%.3f hips_avatar_above_floor_m=%.3f toe_above_floor_m=%s/%s stretch=%.4f",
                    Vector3.z(Unit.world_position(unit, Unit.node(unit, "j_hips"))) - floor,
                    Vector3.z(Unit.world_position(avatar, Unit.node(avatar, "j_hips"))) - floor,
                    toe("left"), toe("right"), state.stretch or 1)
            end
        end
        -- LEGS FROM THE STOCK MODEL (end).
        if state.machine ~= nil and state.leg_indices ~= nil then
            local ok = pcall(function()
                for _, name in ipairs({"anim_move_speed", "aim", "climb_time"}) do
                    local ids = state.machine_variables[name]
                    if ids == nil then
                        local from = Unit.animation_find_variable(avatar, name)
                        local to = Unit.animation_find_variable(unit, name)
                        ids = (from and to) and {from, to} or false
                        state.machine_variables[name] = ids
                    end
                    if ids then Unit.animation_set_variable(unit, ids[2], Unit.animation_get_variable(avatar, ids[1])) end
                end
            end)
            if not ok then log_once("machine_variables", "animated_legs=variables_failed") end
        end
        if Mirror.MODES[mode_name].gait and state.legs and state.gait and not animated then
            local Gait = state.gait_module
            local heading = state.yaw or Quaternion.yaw(Unit.world_rotation(unit, 1))
            local ground = Vector3.z(Unit.world_position(avatar, 1))
            local scale = state.scale or 1
            -- The floor where a foot is put down, by raycast: from a metre
            -- above the simulated floor to 0.6 m below it, statics only,
            -- with the filter the game grounds its own hand IK with
            -- (player_character_state_ledge_hanging.lua:322). `closest`
            -- returns result, position, distance, normal, actor -- the order
            -- the skull module learned the hard way. Asked only where a
            -- foot plants or lands, so at most one cast a frame. A failed
            -- cast is logged once and answers nil, which the gait reads as
            -- the simulated floor.
            state.physics_world = state.physics_world or World.physics_world(world)
            local function ground_at(x, y)
                if not state.physics_world then return nil end
                local ok, hit, position = pcall(PhysicsWorld.raycast, state.physics_world,
                    Vector3(x, y, ground + Mirror.GROUND_RAY_UP), Vector3(0, 0, -1),
                    Mirror.GROUND_RAY_UP + Mirror.GROUND_RAY_DOWN, "closest", "types", "statics",
                    "collision_filter", Mirror.GROUND_FILTER)
                if not ok then
                    log_once("ground_ray", "ground_raycast=failed error=%s", tostring(hit):sub(1, 120))
                    return nil
                end
                if not hit or not position then return nil end
                state.ground_hits = (state.ground_hits or 0) + 1
                return Vector3.z(position)
            end
            local feet = Gait.update(state.gait, array(Unit.world_position(unit, 1)), heading, ground, t, dt, scale,
                ground_at)
            if feet then
                local forward = Vector3(-math.sin(heading), math.cos(heading), 0)
                for _, side in ipairs(Gait.SIDES) do
                    local leg, foot = state.legs[side], feet[side]
                    local target = vector(foot.position) + Vector3(0, 0, state.ankle_height[side] * scale)
                    local hip = Unit.world_position(unit, leg.hip)
                    local knee_rest = Unit.world_position(unit, leg.knee)
                    local hint = knee_rest + forward * Mirror.KNEE_HINT_FORWARD
                    local upper = Vector3.length(knee_rest - hip)
                    local lower = Vector3.length(Unit.world_position(unit, leg.ankle) - knee_rest)
                    local knee, ankle = Mirror.elbow(array(hip), array(hint), array(target), upper, lower)
                    if knee then
                        aim_joint(world, unit, leg.hip, leg.knee, vector(knee))
                        aim_joint(world, unit, leg.knee, leg.ankle, vector(ankle))
                        -- Flat, and turned to the foot's planted heading:
                        -- the rest rotation about the root, re-based.
                        -- The foot's pitch on the ankle-to-toe line, at three
                        -- stages: as the knee's aim left it, after the rest
                        -- rotation is re-based to the foot's heading, and
                        -- after the foot is AIMED so the toe points where a
                        -- flat foot's toe points (the rest pitch below the
                        -- ankle, along the foot's heading). The 14:26 run
                        -- read +4.7 deg against a rest of -28 after the
                        -- re-base, and the axis-angle correction turned the
                        -- toes further up ("toes are pointed up even worse
                        -- now"). aim_joint is the knees' own path and turns
                        -- the joint by the swing from the child's direction
                        -- to the target's; the foot uses it now.
                        local function toe_pitch()
                            if not leg.toe then return nil end
                            local to_toe = Unit.world_position(unit, leg.toe) - Unit.world_position(unit, leg.ankle)
                            return math.atan2(Vector3.z(to_toe), math.sqrt(Vector3.x(to_toe) ^ 2 + Vector3.y(to_toe) ^ 2)),
                                Vector3.length(to_toe)
                        end
                        leg.pitch_after_aim = toe_pitch()
                        set_world_rotation(unit, leg.ankle, Quaternion.multiply(
                            Quaternion(Vector3.up(), foot.yaw), leg.rest_foot_rotation:unbox()))
                        World.update_unit(world, unit)
                        leg.pitch_after_rebase = toe_pitch()
                        if leg.toe and leg.rest_pitch then
                            local _, foot_length = toe_pitch()
                            if foot_length and foot_length > 0.01 then
                                local heading = Vector3(-math.sin(foot.yaw), math.cos(foot.yaw), 0)
                                local toe_goal = Unit.world_position(unit, leg.ankle) +
                                    (heading * math.cos(leg.rest_pitch) + Vector3.up() * math.sin(leg.rest_pitch)) * foot_length
                                aim_joint(world, unit, leg.ankle, leg.toe, toe_goal)
                            end
                        end
                        leg.pitch = toe_pitch()
                        leg.error = Vector3.length(Unit.world_position(unit, leg.ankle) - target)
                    else
                        leg.error = nil
                    end
                end
                state.gait_feet = feet
            end
        end
        if Mirror.MODES[mode_name].solve_arms then
            for _, arm in ipairs(state.arms) do solve_arm(world, avatar, unit, arm) end
        end
        -- The fingers, after the arms: the grip curl the gloves had, on the
        -- copy's own hand joints, held per weapon (BodyProxy.pose_rig_fingers).
        if state.hand_rig and body_proxy() and body_proxy().pose_rig_fingers then
            if body_proxy().pose_rig_fingers() then World.update_unit(world, unit) end
        end
        -- The children, measured against the skeleton as the solve left it
        -- (after World.update_unit on the copy alone), then flushed with the
        -- call the rigid gloves have always used, World.update_unit_and_children,
        -- and measured again. The first number says whether update_unit
        -- leaves the linked units behind; the second whether the children
        -- call brings them; the render check reads them a third time after
        -- the engine's world update. The flush is the labelled experiment.
        state.child_before, state.child_before_name = measure_children(unit, state.children)
        World.update_unit_and_children(world, unit)
        state.child_after, state.child_after_name = measure_children(unit, state.children)
        -- The marker glove (see spawn): its root put at the copy's head
        -- joint, nothing else of it touched, the way the rigid gloves move.
        if state.marker_profile_spawner then
            if not state.marker then
                state.marker_profile_spawner:update(dt, t)
                local marker_data = state.marker_profile_spawner:spawned() and state.marker_profile_spawner._character_spawn_data
                local marker = marker_data and marker_data.unit_3p
                if marker and Unit.alive(marker) then
                    state.marker = marker
                    pcall(Unit.disable_animation_state_machine, marker)
                    mod:info("DARKTIDEVR_BODY_MIRROR marker=ready machine=%s",
                        tostring(Unit.has_animation_state_machine and Unit.has_animation_state_machine(marker)))
                end
            elseif Unit.alive(state.marker) and Unit.has_node(unit, "j_head") then
                -- The glove itself (the marker body's left hand joint, where
                -- the glove item hangs) half a metre ahead of the copy's head
                -- at head height: the root is moved by whatever the hand is
                -- off the target, as place_rigid_hand does. The 14:20 run had
                -- the root at the head and the glove where the rest pose
                -- hangs it, above and behind.
                local head = Unit.node(unit, "j_head")
                local goal = Unit.world_position(unit, head) + Quaternion.forward(Unit.world_rotation(unit, 1)) * 0.5
                Unit.set_local_rotation(state.marker, 1, Unit.world_rotation(unit, 1))
                World.update_unit_and_children(world, state.marker)
                local anchor = Unit.has_node(state.marker, "j_lefthand") and Unit.world_position(state.marker, Unit.node(state.marker, "j_lefthand"))
                    or Unit.world_position(state.marker, 1)
                Unit.set_local_position(state.marker, 1, Unit.local_position(state.marker, 1) + goal - anchor)
                World.update_unit_and_children(world, state.marker)
            end
        end
        -- What the copy looks like when this update is done, for the
        -- pre-render check (api.check_before_render): the root and the
        -- right hand. The probe (12:07) showed the root as smooth as the
        -- avatar's after the smooth-timeline shift and the flicker stayed,
        -- so whatever alternates does so after this point or in a joint the
        -- probe does not watch; the check reads the same two points again
        -- at the render boundary, after the engine's own world update.
        if not Mirror.MODES[mode_name].reflect and Unit.has_node(unit, "j_righthand") then
            state.render_check = state.render_check or {}
            state.render_check.root = array(Unit.world_position(unit, 1))
            state.render_check.hand = array(Unit.world_position(unit, Unit.node(unit, "j_righthand")))
            -- A stamp the render check consumes: not the frame counter,
            -- which increments after this point.
            state.render_check.stamp = (state.render_check.stamp or 0) + 1
        end
        if Mirror.MODES[mode_name].reflect then
            -- Posed on the player; now turned about them and stood ahead.
            local root = Unit.local_position(unit, 1)
            local heading = state.yaw or Quaternion.yaw(Unit.local_rotation(unit, 1))
            local pivot = neck_target or array(root)
            local moved = Mirror.reflected_root(array(root), pivot, heading, Mirror.MIRROR_DISTANCE)
            Unit.set_local_position(unit, 1, vector(moved))
            Unit.set_local_rotation(unit, 1, Quaternion.multiply(Quaternion(Vector3.up(), math.pi), Unit.local_rotation(unit, 1)))
            World.update_unit_and_children(world, unit)
        end
        -- The scale is fixed, so nothing waits for it to settle; the scan
        -- still waits a frame for the camera.
        if state.near_eye_pending and state.frames > 0 then
            state.near_eye_pending = nil
            hide_near_eye(unit, state.data)
        end
        -- THE MOTION PROBE (19 September). "It flickers constantly when I
        -- move", and every earlier flicker-while-moving in this mod was the
        -- same shape: a thing drawn from a value that advanced in fixed steps
        -- while the view advanced every frame, so it flicked between two
        -- places at the frame rate (the forearm miniatures, animation audit,
        -- 16 September; the mirror copy placed from the avatar's root, 17
        -- September). Four positions go into where this copy stands -- the
        -- avatar's root (interpolated by the game every frame), the body
        -- frame's neck target (from the eye, which is stored against the
        -- fixed-step body anchor), the tracked eye itself, and the copy's own
        -- root after all of it -- and reading the source has not said which
        -- one steps. So while the player is moving, every frame, the step
        -- each of them took since the previous frame goes in one line. A
        -- value that alternates (0.000, 0.032, 0.000, 0.032) against a view
        -- that does not (0.016, 0.016, ...) is the answer. Every frame
        -- rather than every third, because a two-state alternation sampled
        -- every third frame aliases into a smooth line. It ran under the
        -- trace flag until 19 September, when three deployments in an hour
        -- each wrote that flag `disabled` and three worn runs produced no
        -- lines; now it always runs, with its own budget of MOTION_MAX_LINES
        -- (about half a minute of movement), and the trace flag lifts the
        -- budget to the trace's.
        state.motion_lines = state.motion_lines or 0
        if (trace_flag() and trace_lines < Mirror.TRACE_MAX_LINES) or
                state.motion_lines < Mirror.MOTION_MAX_LINES then
            local ok = pcall(function()
                local root_now = array(Unit.world_position(unit, 1))
                local avatar_now = array(Unit.world_position(avatar, 1))
                local neck_now = neck_target
                local eye_position = presentation.eye_pose and presentation.eye_pose(avatar)
                local eye_now = eye_position and array(eye_position) or nil
                -- THE SOLVED JOINTS (14:20 worn run): the marker glove, a
                -- machine-less unit stood by its root from the copy's head
                -- joint, flickers like the body, while the rigid gloves
                -- stood by their roots from the controller do not. So the
                -- copy's numbers alternate, and the root, the only joint the
                -- probe read, is not where. The head and hand joints after
                -- the solve, the hand's recorded target, and the marker's
                -- root, each stepped against the previous frame: an A-B-A-B
                -- alternation is a large, constant step every frame.
                local head_now = Unit.has_node(unit, "j_head") and array(Unit.world_position(unit, Unit.node(unit, "j_head"))) or nil
                local hand_now = Unit.has_node(unit, "j_righthand") and array(Unit.world_position(unit, Unit.node(unit, "j_righthand"))) or nil
                local target_position = body_proxy() and body_proxy().hand_pose and body_proxy().hand_pose("right")
                local target_now = target_position and array(target_position) or nil
                local marker_now = state.marker and Unit.alive(state.marker) and array(Unit.world_position(state.marker, 1)) or nil
                local m = state.motion
                if m then
                    local d_avatar = Mirror.step_m(avatar_now, m.avatar)
                    if d_avatar and d_avatar > Mirror.MOTION_MOVING_M then
                        trace_lines = trace_lines + 1
                        state.motion_lines = state.motion_lines + 1
                        local function fmt(v) return v and string.format("%.4f", v) or "na" end
                        mod:info("DARKTIDEVR_BODY_MOTION t=%.3f dt=%.4f d_avatar_m=%s d_neck_target_m=%s d_eye_m=%s d_unit_m=%s " ..
                            "anchor_lag_m=%s avatar=%.3f,%.3f,%.3f unit=%.3f,%.3f,%.3f child_before_m=%s child_after_m=%s child=%s " ..
                            "d_head_m=%s d_hand_m=%s d_hand_target_m=%s d_marker_m=%s head=%s hand=%s d_unit_rel_eye_m=%s",
                            type(t) == "number" and t or 0, type(dt) == "number" and dt or 0,
                            fmt(d_avatar), fmt(Mirror.step_m(neck_now, m.neck)), fmt(Mirror.step_m(eye_now, m.eye)),
                            fmt(Mirror.step_m(root_now, m.root)),
                            fmt(state.smooth_lag and Vector3.length(state.smooth_lag) or nil),
                            avatar_now[1], avatar_now[2], avatar_now[3], root_now[1], root_now[2], root_now[3],
                            fmt(state.child_before), fmt(state.child_after), tostring(state.child_before_name),
                            fmt(Mirror.step_m(head_now, m.head)), fmt(Mirror.step_m(hand_now, m.hand)),
                            fmt(Mirror.step_m(target_now, m.target)), fmt(Mirror.step_m(marker_now, m.marker)),
                            head_now and string.format("%.3f,%.3f,%.3f", head_now[1], head_now[2], head_now[3]) or "na",
                            hand_now and string.format("%.3f,%.3f,%.3f", hand_now[1], hand_now[2], hand_now[3]) or "na",
                            fmt(eye_now and m.eye and Mirror.step_m({root_now[1] - eye_now[1], root_now[2] - eye_now[2], root_now[3] - eye_now[3]},
                                {m.root[1] - m.eye[1], m.root[2] - m.eye[2], m.root[3] - m.eye[3]}) or nil))
                    end
                end
                state.motion = {avatar = avatar_now, neck = neck_now, eye = eye_now, root = root_now,
                    head = head_now, hand = hand_now, target = target_now, marker = marker_now}
            end)
            if not ok then log_once("motion_probe", "motion_probe=failed") end
        end
        -- The trace. Yaws and the root's own movement, at half the frame rate,
        -- so a stick turn and a stationary jitter are both readable in the
        -- same lines: during a turn compare the steps, at rest look at whether
        -- root_step_m is oscillating rather than settling.
        if trace_flag() and trace_lines < Mirror.TRACE_MAX_LINES and
                state.frames % Mirror.TRACE_EVERY == 0 then
            local ok = pcall(function()
                local root_world = array(Unit.world_position(unit, 1))
                -- The solver that actually turns the torso (see
                -- presentation.apply_body_heading). The yaws above are the
                -- body FRAME's, which drives the virtual stock and the neck
                -- follow but not the avatar's heading.
                local heading = presentation.body_heading_trace
                -- The torso the player actually looks at, on the drawn copy
                -- and on the avatar it is posed from. Roots are already in the
                -- line above and they were not the answer.
                local function shoulders(of)
                    if not of or not Unit.alive(of) or
                            not Unit.has_node(of, "j_leftarm") or
                            not Unit.has_node(of, "j_rightarm") then return nil end
                    return Mirror.torso_yaw(
                        array(Unit.world_position(of, Unit.node(of, "j_leftarm"))),
                        array(Unit.world_position(of, Unit.node(of, "j_rightarm"))))
                end
                -- The avatar's torso column is gone with the copied spine it
                -- measured: nothing on the copy is posed from it now.
                local torso_yaw, avatar_torso_yaw = shoulders(unit), nil
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
                -- The torso steps, in the same shape as the rest.
                local function degrees_of(value)
                    if type(value) ~= "number" or value ~= value then return nil end
                    return math.deg((value + math.pi) % (2 * math.pi) - math.pi)
                end
                sample.torso = degrees_of(torso_yaw)
                sample.avatar_torso = degrees_of(avatar_torso_yaw)
                for _, name in ipairs({"torso", "avatar_torso"}) do
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
                    "root=%.4f,%.4f,%.4f root_step_m=%s neck_m=%s scale=%.4f why=%s " ..
                    "solver=%s visual=%s solver_head=%s delta=%s still_s=%s conv=%s move_stick=%s turn_deg=%s " ..
                    "torso=%s avatar_torso=%s d_torso=%s d_avatar_torso=%s",
                    type(t) == "number" and t or 0, type(dt) == "number" and dt or 0,
                    degrees("head"), degrees("target"), degrees("frame"),
                    degrees("mirror"), degrees("avatar"), degrees("unit"),
                    step("head"), step("target"), step("frame"),
                    step("mirror"), step("avatar"), step("unit"),
                    root_world[1], root_world[2], root_world[3],
                    root_step and string.format("%.5f", root_step) or "na",
                    state.neck_distance and string.format("%.4f", state.neck_distance) or "na",
                    state.scale or 1, why,
                    heading and tostring(heading.branch) or "na",
                    heading and heading.visual_yaw and string.format("%.2f", math.deg(heading.visual_yaw)) or "na",
                    heading and heading.head_yaw and string.format("%.2f", math.deg(heading.head_yaw)) or "na",
                    heading and heading.delta and string.format("%.2f", math.deg(heading.delta)) or "na",
                    heading and heading.still_seconds and string.format("%.2f", heading.still_seconds) or "na",
                    heading and heading.convergence and string.format("%.1f", heading.convergence) or "na",
                    heading and tostring(heading.stick) or "na",
                    heading and heading.turn_accum and
                        string.format("%.2f", math.deg(heading.turn_accum)) or "na",
                    degrees("torso"), degrees("avatar_torso"),
                    step("torso"), step("avatar_torso"))
                -- Consumed, so each line reports the turn since the last one.
                if heading then heading.turn_accum = 0 end
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
        state.frames = state.frames + 1
        if state.frames == 1 or state.frames % 900 == 0 then
            if state.neck_offset then
                mod:info("DARKTIDEVR_BODY_MIRROR neck_follow offset_m=%.3f,%.3f,%.3f distance_m=%.3f scale=%.4f",
                    state.neck_offset[1], state.neck_offset[2], state.neck_offset[3], state.neck_distance, state.scale or 1)
            end
            if state.spine_neck then
                mod:info("DARKTIDEVR_BODY_MIRROR spine neck_gap_m=%.3f->%.3f", state.spine_neck[1], state.spine_neck[2])
            end
            if state.root_yaw_delta then
                mod:info("DARKTIDEVR_BODY_MIRROR body_yaw delta_from_frame_deg=%.1f root_yaw_leak_deg=%s",
                    state.root_yaw_delta,
                    state.root_yaw_leak and string.format("%.1f", state.root_yaw_leak) or "none")
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
                -- HEIGHT (13:47 worn run): "my eyeline is above the mirrored
                -- model eyeline" and a hand rested on the real shoulder sits
                -- 5-10 cm above the drawn one. The copy's own eyes (the face
                -- unit's j_lefteye/j_righteye, present though hidden), its
                -- neck and its shoulder joints, in the root's frame, against
                -- the camera's eye in the same frame.
                local root_inverse = Matrix4x4.inverse(Unit.world_pose(unit, 1))
                local function root_z(child, name)
                    return child and Unit.alive(child) and Unit.has_node(child, name) and
                        Vector3.z(Matrix4x4.transform(root_inverse, Unit.world_position(child, Unit.node(child, name)))) or nil
                end
                local eye_z
                for _, slot in pairs(state.data and state.data.slots or {}) do
                    local left, right = root_z(slot.unit_3p, "j_lefteye"), root_z(slot.unit_3p, "j_righteye")
                    if left and right then eye_z = (left + right) / 2; break end
                end
                local neck_z, shoulder_left, shoulder_right = root_z(unit, "j_neck"), root_z(unit, "j_leftarm"), root_z(unit, "j_rightarm")
                local function fmt(v) return v and string.format("%.3f", v) or "na" end
                mod:info("DARKTIDEVR_BODY_MIRROR height camera_eye_root_z=%.3f copy_eye_root_z=%s eye_gap_m=%s neck_root_z=%s shoulder_root_z=%s/%s scale=%.4f",
                    Vector3.z(eye), fmt(eye_z), fmt(eye_z and Vector3.z(eye) - eye_z), fmt(neck_z), fmt(shoulder_left), fmt(shoulder_right),
                    state.scale or 1)
            end
            -- How far the hand sits from its forearm joint after the solve
            -- (the stretch). The hand's error against its recorded target is
            -- in the per-arm lines below; nothing here compares the copy with
            -- the avatar any more.
            local unit_hand = Unit.node(unit, "j_righthand")
            local stretch = Unit.has_node(unit, "j_rightforearm") and Vector3.distance(Unit.world_position(unit, unit_hand),
                Unit.world_position(unit, Unit.node(unit, "j_rightforearm"))) or -1
            mod:info("DARKTIDEVR_BODY_MIRROR posed mode=%s frames=%d right_forearm_to_hand_m=%.4f",
                tostring(mode_name), state.frames, stretch)
            local feet = state.gait_feet
            if feet then
                local function err(side)
                    local leg = state.legs and state.legs[side]
                    return leg and leg.error and string.format("%.3f", leg.error) or "na"
                end
                -- FLOAT (13:47 worn run): the drawn toe against the ground
                -- the gait put the foot on, per side. Positive is a toe in
                -- the air above the foot's ground point.
                local function toe_above(side)
                    local name = "j_" .. side .. "toebase"
                    if not Unit.has_node(unit, name) then return "na" end
                    return string.format("%.3f", Vector3.z(Unit.world_position(unit, Unit.node(unit, name))) - feet[side].position[3])
                end
                local function pitch(side)
                    local leg = state.legs and state.legs[side]
                    return leg and leg.pitch and string.format("%.1f", math.deg(leg.pitch)) or "na",
                        leg and leg.rest_pitch and string.format("%.1f", math.deg(leg.rest_pitch)) or "na"
                end
                local left_pitch, left_rest = pitch("left")
                local right_pitch, right_rest = pitch("right")
                local left_leg = state.legs and state.legs.left
                local function deg(v) return v and string.format("%.1f", math.deg(v)) or "na" end
                mod:info("DARKTIDEVR_BODY_MIRROR gait speed_mps=%.3f ground_hits=%d left=%s right=%s ankle_error_m=%s/%s left_foot=%.3f,%.3f,%.3f right_foot=%.3f,%.3f,%.3f toe_above_ground_m=%s/%s foot_pitch_deg=%s/%s rest_pitch_deg=%s/%s left_pitch_stages_deg=aim:%s rebase:%s aimed:%s toe_under_ankle=%s",
                    feet.speed or 0, state.ground_hits or 0,
                    feet.left.swinging and "swinging" or "planted", feet.right.swinging and "swinging" or "planted",
                    err("left"), err("right"),
                    feet.left.position[1], feet.left.position[2], feet.left.position[3],
                    feet.right.position[1], feet.right.position[2], feet.right.position[3],
                    toe_above("left"), toe_above("right"), left_pitch, right_pitch, left_rest, right_rest,
                    deg(left_leg and left_leg.pitch_after_aim), deg(left_leg and left_leg.pitch_after_rebase), deg(left_leg and left_leg.pitch),
                    tostring(left_leg and left_leg.toe_under_ankle))
            end
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
                    mod:info("DARKTIDEVR_BODY_MIRROR arm side=%s upper_m=%.4f lower_m=%.4f world_upper_m=%.4f world_lower_m=%.4f shoulder_to_target_m=%.4f hand_error_m=%.4f hand_angle_deg=%.2f unreachable_frames=%d max_stretch_m=%.4f max_protraction_m=%.4f",
                        arm.side, arm.upper, arm.lower, arm.world_upper or -1, arm.world_lower or -1, arm.distance or -1, arm.error or -1,
                        arm.angle_error or -1, arm.unreachable, arm.max_stretch or 0,
                        arm.max_protraction or 0)
                    if arm.max_stretch_ratio then
                        mod:info("DARKTIDEVR_BODY_MIRROR arm side=%s max_stretch_ratio=%.3f", arm.side, arm.max_stretch_ratio)
                    end
                end
            end
        end
    end
    function api.update(world, avatar, dt, t)
        -- Between frames: the copy as the last render left it against the
        -- copy now, before this frame's pose. A move here is something
        -- other than this module writing the copy between renders.
        if state and state.unit and Unit.alive(state.unit) and state.after_render and Unit.has_node(state.unit, "j_righthand") then
            local root = array(Unit.world_position(state.unit, 1))
            local hand = array(Unit.world_position(state.unit, Unit.node(state.unit, "j_righthand")))
            local d = math.max(Mirror.step_m(root, state.after_render.root) or 0, Mirror.step_m(hand, state.after_render.hand) or 0)
            between_checks = between_checks + 1
            if d >= 0.001 then between_moved = between_moved + 1 end
            if d > between_max then between_max = d end
        end
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
    -- WHEN THE COPY IS POSED (19 September). In the locomotion extension's
    -- post_update, after post.body_ik has refreshed the frame's body anchor
    -- and placed the hands: the same frame's anchor the camera and the
    -- weapon are built on. From 13:38 to 14:36 it was posed from a
    -- WorldManager.update hook, before the world update, on the previous
    -- post_update's inputs; the anchor advances every other frame (the
    -- probe's d_eye_m, 0 then 7 cm), so on the frames it advanced the copy
    -- stood a step behind the view and on the others where it should --
    -- "one of the two locations is definitely the right one, the other
    -- lags behind" -- while the rigid gloves and the weapon, placed in
    -- post_update from the frame's own anchor, held still. The copy has no
    -- state machine (the census, 14:20), so its joints written after the
    -- world update are drawn; the still body at 13:20 was a machine left
    -- running, which is a different thing. The render check reads the eye
    -- again at the render boundary against the eye the copy was posed from
    -- (render_eye_lag); it would have read 7 cm on alternate frames under
    -- the pre-world pose and reads zero when the pose is on the frame's
    -- own inputs.
    -- After the engine's render call for the copy's world: the copy read
    -- once more. A move between check_before_render and here is the render
    -- itself (or something in the render hook) moving the copy.
    function api.check_after_render(world)
        if not state or not state.unit or world ~= state.world or not Unit.alive(state.unit) then return end
        if not Unit.has_node(state.unit, "j_righthand") then return end
        local root = array(Unit.world_position(state.unit, 1))
        local hand = array(Unit.world_position(state.unit, Unit.node(state.unit, "j_righthand")))
        if state.render_check and state.render_check.root then
            local d = math.max(Mirror.step_m(root, state.render_check.root) or 0, Mirror.step_m(hand, state.render_check.hand) or 0)
            after_checks = after_checks + 1
            if d >= 0.001 then after_moved = after_moved + 1 end
            if d > after_max then after_max = d end
        end
        state.after_render = state.after_render or {}
        state.after_render.root, state.after_render.hand = root, hand
    end
    return api
end

return Mirror
