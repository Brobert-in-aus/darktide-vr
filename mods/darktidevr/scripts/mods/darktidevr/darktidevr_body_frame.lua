-- Shared body frame (two-hand aim design and full-body IK design, 15 September):
-- one estimate of body yaw, neck and shoulders from the headset and both
-- hands. The virtual stock anchors to the dominant shoulder; full-body IK is
-- to read the same shoulders. Data flows one way, from this estimate to its
-- users, so the stock behaves the same with or without a drawn body.
--
-- World space, Z up, Stingray yaw (forward = (-sin yaw, cos yaw, 0)).
-- Starting values from the research notes (docs/phase1/research):
-- - yaw: head yaw, pitch-safe past 50 degrees, biased 0.7 toward the hands
--   in front, within 60 degrees of the head, with a 20 degree dead zone and
--   0.15 s catch-up;
-- - neck: 7 cm behind and 8 cm below the eye, turning with the head;
-- - shoulders: 17 cm either side of the neck and 8 cm below it, on body yaw;
-- - all lengths scale with eye height / 1.62 m.
local BodyFrame = {}

BodyFrame.HAND_BIAS = 0.7
BodyFrame.MAX_HAND_YAW = math.rad(60)
BodyFrame.DEAD_ZONE = math.rad(20)
BodyFrame.SETTLED = math.rad(2)
BodyFrame.CATCH_UP_SECONDS = 0.15
-- Inside the dead zone the body used to stop dead and stay there, so a glance
-- held for a minute left the torso permanently askew under the head: "the
-- torso also doesn't slowly recenter if I'm still for a bit" (user, worn, 18
-- September). It now drifts toward the head the whole time, on a time constant
-- slow enough that a glance still reads as a glance -- about 1.4 s to close
-- half the gap, against CATCH_UP_SECONDS' tenth of a second once a real turn
-- has been declared. The dead zone is what makes a glance free; this is what
-- stops "free" meaning "for ever".
BodyFrame.RECENTRE_SECONDS = 2.0
BodyFrame.PITCH_SAFE_FROM = math.rad(50)
BodyFrame.NECK_BACK, BodyFrame.NECK_DOWN = 0.07, 0.08
BodyFrame.SHOULDER_SIDE, BodyFrame.SHOULDER_DOWN = 0.17, 0.08
BodyFrame.REFERENCE_EYE_HEIGHT = 1.62

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function valid3(v) return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3]) end
local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
local function yaw_of(x, y) return math.atan2(-x, y) end

-- Head yaw that does not flip when looking straight down or up: past
-- PITCH_SAFE_FROM the flattened up vector (down) or its reverse (up) takes over.
function BodyFrame.head_yaw(forward, up)
    if not valid3(forward) or not valid3(up) then return nil end
    local pitch = math.asin(math.max(-1, math.min(1, forward[3])))
    local fx, fy = forward[1], forward[2]
    local blend = math.max(0, math.min(1, (math.abs(pitch) - BodyFrame.PITCH_SAFE_FROM) /
        (math.pi / 2 - BodyFrame.PITCH_SAFE_FROM)))
    if blend > 0 then
        local sign = pitch < 0 and 1 or -1
        fx = fx * (1 - blend) + up[1] * sign * blend
        fy = fy * (1 - blend) + up[2] * sign * blend
    end
    if fx * fx + fy * fy < 1e-10 then return nil end
    return yaw_of(fx, fy)
end

-- The yaw the body wants: head yaw pulled toward the hands in front. Pure.
function BodyFrame.target_yaw(head_yaw, eye, hands)
    local sx, sy, count = 0, 0, 0
    local fx, fy = -math.sin(head_yaw), math.cos(head_yaw)
    for _, hand in ipairs(hands or {}) do
        if valid3(hand) then
            local dx, dy = hand[1] - eye[1], hand[2] - eye[2]
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0.15 and (dx * fx + dy * fy) / length > 0.2 then
                sx, sy, count = sx + dx / length, sy + dy / length, count + 1
            end
        end
    end
    if count == 0 or sx * sx + sy * sy < 1e-10 then return head_yaw end
    local offset = wrap(yaw_of(sx, sy) - head_yaw) * BodyFrame.HAND_BIAS
    offset = math.max(-BodyFrame.MAX_HAND_YAW, math.min(BodyFrame.MAX_HAND_YAW, offset))
    return wrap(head_yaw + offset)
end

function BodyFrame.new()
    local state = {yaw = nil, turning = false}
    function state.reset() state.yaw = nil; state.turning = false end
    -- input: eye, head_forward, head_up (3-arrays), hands = {left, right}
    -- (3-arrays or nil), eye_height (metres, already times the character
    -- scale). Returns the frame, or nil for invalid input.
    function state.update(input, dt)
        if type(input) ~= "table" or not valid3(input.eye) then state.reset(); return nil end
        local head_yaw = BodyFrame.head_yaw(input.head_forward, input.head_up)
        if not head_yaw then state.reset(); return nil end
        local target = BodyFrame.target_yaw(head_yaw, input.eye, input.hands)
        if not state.yaw or not finite(dt) or dt < 0 or dt > 0.5 then
            state.yaw, state.turning = target, false
        else
            local diff = wrap(target - state.yaw)
            if math.abs(diff) > BodyFrame.DEAD_ZONE then state.turning = true end
            -- Turning: catch up quickly. Not turning: drift, rather than
            -- freeze. Both are the same exponential, and which time constant
            -- applies is the only difference between them.
            local tau = state.turning and BodyFrame.CATCH_UP_SECONDS or
                BodyFrame.RECENTRE_SECONDS
            state.yaw = wrap(state.yaw + diff * (1 - math.exp(-dt / tau)))
            if state.turning and
                    math.abs(wrap(target - state.yaw)) < BodyFrame.SETTLED then
                state.turning = false
            end
        end
        local eye_height = finite(input.eye_height) and input.eye_height > 0.5 and input.eye_height or
            BodyFrame.REFERENCE_EYE_HEIGHT
        local s = eye_height / BodyFrame.REFERENCE_EYE_HEIGHT
        local e, f, u = input.eye, input.head_forward, input.head_up
        local neck = {e[1] - f[1] * BodyFrame.NECK_BACK * s - u[1] * BodyFrame.NECK_DOWN * s,
            e[2] - f[2] * BodyFrame.NECK_BACK * s - u[2] * BodyFrame.NECK_DOWN * s,
            e[3] - f[3] * BodyFrame.NECK_BACK * s - u[3] * BodyFrame.NECK_DOWN * s}
        local rx, ry = math.cos(state.yaw), math.sin(state.yaw)
        local side, down = BodyFrame.SHOULDER_SIDE * s, BodyFrame.SHOULDER_DOWN * s
        -- target_yaw is reported so a trace can tell "the target moved too
        -- far" from "the smoothing overshot it". They are the two halves of
        -- the body turning faster than the view, and without both the line
        -- says only that it did.
        return {yaw = state.yaw, head_yaw = head_yaw, target_yaw = target, scale = s, neck = neck,
            shoulder_left = {neck[1] - rx * side, neck[2] - ry * side, neck[3] - down},
            shoulder_right = {neck[1] + rx * side, neck[2] + ry * side, neck[3] - down}}
    end
    return state
end

-- Live adapter: world eye and head axes from the tracked eye, both tracked grips, and the player's eye
-- height times the character scale. Sampled at most once per game time.
function BodyFrame.install(mod, presentation, observation)
    local api = {}
    local frame_state = BodyFrame.new()
    local last_t, last_frame, failures, last_main = nil, nil, 0, nil
    local function vector(v) return v and {Vector3.x(v), Vector3.y(v), Vector3.z(v)} or nil end
    local function sample(unit, t)
        -- The tracked eye (presentation.eye_pose), not the first-person unit:
        -- that misses head translation, and the virtual stock's shoulder
        -- anchored to it wobbled (worn, 15 September).
        local eye_position, rotation
        if presentation.eye_pose then eye_position, rotation = presentation.eye_pose(unit) end
        if not eye_position or not rotation then frame_state.reset(); return nil end
        local hands = {}
        if observation.left_grip_tracking_live and presentation.left_controller_grip_target then
            hands[#hands + 1] = vector(presentation.left_controller_grip_target())
        end
        if observation.right_grip_tracking_live and presentation.controller_grip_target then
            hands[#hands + 1] = vector(presentation.controller_grip_target())
        end
        local player = Managers.player and Managers.player:local_player(1)
        local scale = presentation.calibrated_character_scale and presentation.calibrated_character_scale(player) or 1
        -- The CALIBRATED standing eye height sizes the frame, not the live
        -- headset height (19 September, 17:30: a seated start read 1.2 m
        -- and scaled the frame to 0.75 for the whole session).
        local eye_height = presentation.calibrated_eye_height and presentation.calibrated_eye_height() or
            (presentation.physical_eye_height and presentation.physical_eye_height())
        -- The gap since the last ADVANCE, on the same clock `t` now is.
        local dt = last_main and t - last_main or nil
        return frame_state.update({eye = vector(eye_position),
            head_forward = vector(Quaternion.forward(rotation)), head_up = vector(Quaternion.up(rotation)),
            hands = hands, eye_height = eye_height and eye_height * (tonumber(scale) or 1) or nil}, dt)
    end
    -- ONE WRITER (19 September). The frame's smoothing state (its yaw, its
    -- "turning") advances ONCE per rendered frame, on the game's main clock,
    -- and every sample taken in that frame -- whoever asks and whatever
    -- time they pass -- gets the same frame back. Until now "sampled at most
    -- once per game time" meant once per DISTINCT t, and three callers
    -- passed three: the drawn body its frame's t, the two-hand stock the
    -- previous frame's, the holsters their draw t. A sample with a t other
    -- than the last one re-ran the smoothing with that gap as dt, and a
    -- negative or oversized gap snaps the yaw to its target (state.update).
    -- So the copy's root was set from a snapped heading one frame and a
    -- smoothed one the next: "the body is alternating between two positions
    -- each frame ... and the hands, which are part of the body, not the
    -- weapon" -- the weapon rides the avatar, which never reads this. The
    -- caller's t is kept for the log only.
    function api.sample(unit, t)
        local now = Managers and Managers.time and Managers.time.has_timer and
            Managers.time:has_timer("main") and Managers.time:time("main") or t
        if now ~= nil and now == last_main then return last_frame end
        local ok, frame = pcall(sample, unit, now)
        if not ok then
            failures = failures + 1
            if failures == 1 then mod:info("DARKTIDEVR_BODY_FRAME failed=%s", tostring(frame):sub(1, 160)) end
            frame = nil
            frame_state.reset()
        end
        last_main, last_t, last_frame = now, t, frame
        return frame
    end
    return api
end

return BodyFrame
