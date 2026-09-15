-- Arm length from the height and arm calibration (design:
-- docs/phase1/arm-length-calibration-2026-09-16.md; research notes under
-- docs/phase1/research/). Pure: no engine calls. Positions are the calibration's
-- recentred OpenXR metres with z up; the T-pose sample holds head, left and
-- right grip positions.
--
-- - The grip span predicted from standing eye height comes from ANSUR II
--   (6,068 adults): span = 1.008 x eye - 0.107 m, residual SD 4.4 cm.
-- - Reach (shoulder joint to wrist) = (span - 2 x wrist-to-grip - shoulder
--   width) / 2, aimed REACH_AIM short so the drawn elbow straightens no later
--   than the real one.
-- - Upper arm and forearm split 56/44 (ANSUR, Winter's segment ratios).
local ArmLength = {}

ArmLength.SPAN_PER_EYE_HEIGHT = 1.008
ArmLength.SPAN_OFFSET = -0.107
ArmLength.SPAN_RESIDUAL_SD = 0.044
ArmLength.SHORT_SPAN_SD = 2.5
-- The OpenXR grip pose sits at the palm centroid, about this far past the wrist.
ArmLength.WRIST_TO_GRIP = 0.065
ArmLength.REACH_AIM = 0.97
ArmLength.UPPER_SHARE = 0.56
-- T-pose checks: the grips level within, not lower than the predicted shoulder
-- height by more than, and not forward of the head by more than these.
ArmLength.SHOULDER_HEIGHT_PER_EYE = 0.87
ArmLength.MAX_GRIP_HEIGHT_DIFFERENCE = 0.10
ArmLength.MAX_BELOW_SHOULDER = 0.15
ArmLength.MAX_FORWARD = 0.15
-- The player's shoulder joint width for a standing eye height: the body frame's
-- 0.34 m at a 1.62 m eye height, scaled. The reach formula needs the player's
-- width; a rig scaled to the camera is wider.
ArmLength.SHOULDER_WIDTH_PER_EYE = 0.34 / 1.62
function ArmLength.shoulder_width(eye_height)
    if type(eye_height) ~= "number" or eye_height ~= eye_height or eye_height < 0.8 or eye_height > 2.4 then return nil end
    return ArmLength.SHOULDER_WIDTH_PER_EYE * eye_height
end

-- Per-segment length ratio against the rig's own bone.
ArmLength.MIN_RATIO, ArmLength.MAX_RATIO = 0.85, 1.15

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function point(v) return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3]) end
local function distance(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

-- The grip-to-grip span expected for a standing eye height, or nil. Pure.
function ArmLength.predicted_span(eye_height)
    if not finite(eye_height) or eye_height < 0.8 or eye_height > 2.4 then return nil end
    return ArmLength.SPAN_PER_EYE_HEIGHT * eye_height + ArmLength.SPAN_OFFSET
end

-- Problems with a T-pose sample, as a list of ids (empty when it is usable):
-- "missing", "uneven" (grips at different heights), "low" (a grip well below
-- the predicted shoulder height), "forward" (a grip well forward of the head,
-- arms angled in), "short" (span far below the prediction). eye_height may be
-- nil (seated), which skips the checks that need it. Pure.
function ArmLength.t_pose_problems(t_pose, eye_height)
    if type(t_pose) ~= "table" or not point(t_pose.head) or not point(t_pose.left) or not point(t_pose.right) then
        return {"missing"}
    end
    local problems = {}
    local head, left, right = t_pose.head, t_pose.left, t_pose.right
    if math.abs(left[3] - right[3]) > ArmLength.MAX_GRIP_HEIGHT_DIFFERENCE then problems[#problems + 1] = "uneven" end
    local predicted = ArmLength.predicted_span(eye_height)
    if predicted then
        local shoulder = head[3] - (1 - ArmLength.SHOULDER_HEIGHT_PER_EYE) * eye_height
        if math.min(left[3], right[3]) < shoulder - ArmLength.MAX_BELOW_SHOULDER then problems[#problems + 1] = "low" end
    end
    if math.max(left[2] - head[2], right[2] - head[2]) > ArmLength.MAX_FORWARD then problems[#problems + 1] = "forward" end
    if predicted and predicted - distance(left, right) > ArmLength.SHORT_SPAN_SD * ArmLength.SPAN_RESIDUAL_SD then
        problems[#problems + 1] = "short"
    end
    return problems
end

-- Shoulder joint to wrist for a grip span and the player's shoulder joint
-- width (metres; see ArmLength.shoulder_width), aimed short. nil when
-- unusable. Pure.
function ArmLength.reach(span, shoulder_width)
    if not finite(span) or not finite(shoulder_width) or shoulder_width < 0 then return nil end
    local reach = (span - 2 * ArmLength.WRIST_TO_GRIP - shoulder_width) * 0.5 * ArmLength.REACH_AIM
    if not (reach > 0.2 and reach < 1.2) then return nil end
    return reach
end

-- Upper arm and forearm lengths for a reach. Pure.
function ArmLength.segments(reach)
    return reach * ArmLength.UPPER_SHARE, reach * (1 - ArmLength.UPPER_SHARE)
end

-- The arm for a saved calibration result and the player's shoulder width:
-- reach, upper, lower and the source ("span" from a clean T-pose, "height"
-- from the standing eye height when the T-pose has problems or is missing),
-- plus the T-pose problems. nil reach when neither is usable. Pure.
function ArmLength.from_calibration(result, shoulder_width)
    local eye_height = type(result) == "table" and not result.seated and tonumber(result.floor_eye_height) or nil
    local problems = ArmLength.t_pose_problems(type(result) == "table" and result.t_pose, eye_height)
    local span, source
    if #problems == 0 then
        span, source = distance(result.t_pose.left, result.t_pose.right), "span"
    else
        span, source = ArmLength.predicted_span(eye_height), "height"
    end
    local reach = span and ArmLength.reach(span, shoulder_width)
    if not reach then return {problems = problems} end
    local upper, lower = ArmLength.segments(reach)
    return {reach = reach, upper = upper, lower = lower, source = source, span = span, problems = problems}
end

-- The ratio to apply to one of the rig's bones, clamped. Pure.
function ArmLength.segment_ratio(desired, current)
    if not finite(desired) or not finite(current) or current <= 1e-4 then return 1 end
    return math.max(ArmLength.MIN_RATIO, math.min(ArmLength.MAX_RATIO, desired / current))
end

return ArmLength
