local mod = get_mod("darktidevr_stereo_probe")
local definitions = mod:io_dofile(
    "darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_calibration_view_definitions")

DarktideVRCalibrationView = class(
    "DarktideVRCalibrationView", "BaseView")

local MODE_SETTINGS = {
    standing_bilateral = {
        seated = false,
        left = true,
        right = true,
        label = "standing / both arms",
    },
    seated_bilateral = {
        seated = true,
        left = true,
        right = true,
        label = "seated / both arms",
    },
    standing_left = {
        seated = false,
        left = true,
        right = false,
        label = "standing / left arm",
    },
    standing_right = {
        seated = false,
        left = false,
        right = true,
        label = "standing / right arm",
    },
}

local SAMPLE_FRAMES = 45
local MAX_SAMPLE_SPREAD = 0.015
local TRIGGER_PULL_THRESHOLD = 0.75
local TRIGGER_RELEASE_THRESHOLD = 0.25

local function distance(a, b)
    local x = a[1] - b[1]
    local y = a[2] - b[2]
    local z = a[3] - b[3]
    return math.sqrt(x * x + y * y + z * z)
end

local function average(samples, key)
    local result = { 0, 0, 0 }
    for i = 1, #samples do
        local value = samples[i][key]
        result[1] = result[1] + value[1]
        result[2] = result[2] + value[2]
        result[3] = result[3] + value[3]
    end
    result[1] = result[1] / #samples
    result[2] = result[2] / #samples
    result[3] = result[3] / #samples
    return result
end

local function maximum_spread(samples, key, mean)
    local maximum = 0
    for i = 1, #samples do
        maximum = math.max(maximum, distance(samples[i][key], mean))
    end
    return maximum
end

local function average_number(samples, key)
    local total = 0
    for i = 1, #samples do
        total = total + (tonumber(samples[i][key]) or 0)
    end
    return total / #samples
end

DarktideVRCalibrationView.init = function(self, settings, context)
    self._runtime = {
        mode = nil,
        stage = "choose_mode",
        samples = {},
        trigger_armed = false,
        preview_origin = nil,
        result = mod:get("vr_calibration_v1"),
    }
    DarktideVRCalibrationView.super.init(
        self, definitions, settings, context)
end

DarktideVRCalibrationView.on_enter = function(self)
    DarktideVRCalibrationView.super.on_enter(self)
    self:_bind("standing_bilateral", "cb_select_mode")
    self:_bind("seated_bilateral", "cb_select_mode")
    self:_bind("standing_left", "cb_select_mode")
    self:_bind("standing_right", "cb_select_mode")
    self:_bind("retry", "cb_retry")
    self:_bind("back", "_on_back_pressed")
    self:_refresh_text()
end

DarktideVRCalibrationView._bind = function(self, name, callback_name)
    local widget = self._widgets_by_name[name]
    widget.content.hotspot.pressed_callback = callback(self, callback_name, name)
end

DarktideVRCalibrationView.cb_select_mode = function(self, mode)
    self._runtime.mode = mode
    self._runtime.stage = "ready_t_pose"
    self._runtime.samples = {}
    self._runtime.trigger_armed = false
    self._runtime.sample_error = nil
    self._runtime.preview_origin = nil
    self:_refresh_text()
end

DarktideVRCalibrationView.cb_retry = function(self)
    if self._runtime.stage == "complete" or
            string.find(self._runtime.stage, "forward") then
        self._runtime.stage = "ready_forward"
    elseif string.find(self._runtime.stage, "sides") then
        self._runtime.stage = "ready_sides"
    elseif self._runtime.mode then
        self._runtime.stage = "ready_t_pose"
    end
    self._runtime.samples = {}
    self._runtime.trigger_armed = false
    self._runtime.sample_error = nil
    self:_refresh_text()
end

DarktideVRCalibrationView._sample = function(self)
    local runtime = self._runtime
    local mode = MODE_SETTINGS[runtime.mode]
    if not mode then
        return nil, "Choose a calibration mode."
    end
    local request = { left = mode.left, right = mode.right }
    Managers.event:trigger("event_darktidevr_calibration_sample", request)
    return request.sample, request.error or
        "Tracking sample provider is unavailable."
end

DarktideVRCalibrationView._required_triggers = function(self, sample,
        threshold, require_above)
    local mode = MODE_SETTINGS[self._runtime.mode]
    if not mode then
        return false
    end
    local left_ok = not mode.left or
        (require_above and sample.left_trigger >= threshold or
            not require_above and sample.left_trigger <= threshold)
    local right_ok = not mode.right or
        (require_above and sample.right_trigger >= threshold or
            not require_above and sample.right_trigger <= threshold)
    return left_ok and right_ok
end

DarktideVRCalibrationView._refresh_pose_preview = function(self, sample)
    if not sample or not self._ui_scenegraph then
        return
    end
    local head = sample.head
    local scale = 260
    local runtime = self._runtime
    if not runtime.preview_origin then
        runtime.preview_origin = { head[1], head[2], head[3] }
    end
    local origin = runtime.preview_origin
    local head_x = math.max(-250,
        math.min(250, (head[1] - origin[1]) * scale))
    local head_y = math.max(35,
        math.min(210, 80 - (head[3] - origin[3]) * scale))
    self:_set_scenegraph_position("pose_head", head_x, head_y)
    local forward = string.find(runtime.stage, "forward")
    local sides = string.find(runtime.stage, "sides") or
        runtime.stage == "complete"
    self:_set_scenegraph_position(
        "target_left", forward and -75 or (sides and -85 or -250),
        forward and 185 or (sides and 360 or 175))
    self:_set_scenegraph_position(
        "target_right", forward and 75 or (sides and 85 or 250),
        forward and 185 or (sides and 360 or 175))
    local mode = MODE_SETTINGS[runtime.mode]
    self._widgets_by_name.target_left.content.visible =
        mode and mode.left or false
    self._widgets_by_name.target_right.content.visible =
        mode and mode.right or false
    local function place(name, hand)
        local widget = self._widgets_by_name[name]
        widget.content.visible = hand ~= nil
        if not hand then
            return
        end
        self:_set_scenegraph_position(
            name,
            math.max(-250,
                math.min(250, (hand[1] - origin[1]) * scale)),
            math.max(45,
                math.min(430, 145 - (hand[3] - origin[3]) * scale)))
    end
    place("pose_left", sample.left)
    place("pose_right", sample.right)
end

DarktideVRCalibrationView._update_ready_stage = function(self, sample)
    local runtime = self._runtime
    self:_refresh_pose_preview(sample)
    if not runtime.trigger_armed then
        runtime.trigger_armed = self:_required_triggers(
            sample, TRIGGER_RELEASE_THRESHOLD, false)
    elseif self:_required_triggers(
            sample, TRIGGER_PULL_THRESHOLD, true) then
        runtime.stage = runtime.stage == "ready_t_pose" and
            "capture_t_pose" or
            (runtime.stage == "ready_sides" and
                "capture_sides" or "capture_forward")
        runtime.samples = {}
        runtime.sample_error = nil
    end
end

DarktideVRCalibrationView._finish_capture = function(self)
    local runtime = self._runtime
    local mode = MODE_SETTINGS[runtime.mode]
    local samples = runtime.samples
    local means = { head = average(samples, "head") }
    local spread = maximum_spread(samples, "head", means.head)
    if mode.left then
        means.left = average(samples, "left")
        spread = math.max(spread,
            maximum_spread(samples, "left", means.left))
    end
    if mode.right then
        means.right = average(samples, "right")
        spread = math.max(spread,
            maximum_spread(samples, "right", means.right))
    end
    if spread > MAX_SAMPLE_SPREAD then
        runtime.samples = {}
        runtime.sample_error = string.format(
            "Hold still - tracking spread was %.1f mm.", spread * 1000)
        return
    end
    runtime.sample_error = nil
    if runtime.stage == "capture_t_pose" then
        runtime.t_pose = means
        runtime.stage = "ready_sides"
        runtime.trigger_armed = false
    elseif runtime.stage == "capture_sides" then
        runtime.sides = means
        runtime.stage = "ready_forward"
        runtime.trigger_armed = false
    else
        runtime.forward_pose = means
        local result = {
            schema = 3,
            mode = runtime.mode,
            seated = mode.seated,
            bilateral = mode.left and mode.right,
            source_space = "recentered_openxr_metres",
            sample_frames = SAMPLE_FRAMES,
            recenter_generation = samples[1].generation,
            t_pose = runtime.t_pose,
            sides = runtime.sides,
            forward_pose = runtime.forward_pose,
        }
        if not mode.seated then
            result.floor_eye_height = average_number(
                samples, "floor_eye_height")
            if result.floor_eye_height < 0.2 then
                result.floor_eye_height = nil
            end
        end
        if mode.left and mode.right then
            result.hand_span = distance(
                runtime.t_pose.left, runtime.t_pose.right)
        else
            local hand = mode.left and runtime.t_pose.left or
                runtime.t_pose.right
            result.single_arm_head_distance = distance(
                runtime.t_pose.head, hand)
            result.single_arm_side = mode.left and "left" or "right"
        end
        local forward_total = 0
        local forward_count = 0
        if mode.left then
            result.left_forward_reach = distance(
                runtime.forward_pose.head, runtime.forward_pose.left)
            forward_total = forward_total + result.left_forward_reach
            forward_count = forward_count + 1
        end
        if mode.right then
            result.right_forward_reach = distance(
                runtime.forward_pose.head, runtime.forward_pose.right)
            forward_total = forward_total + result.right_forward_reach
            forward_count = forward_count + 1
        end
        result.forward_reach = forward_total / forward_count
        runtime.result = result
        if mod.darktidevr_calibration then
            mod.darktidevr_calibration.result = result
        end
        runtime.stage = "complete"
        mod:set("vr_calibration_v1", result)
        if mod.darktidevr_calibration and
                mod.darktidevr_calibration.apply_official_character_height then
            mod.darktidevr_calibration:apply_official_character_height(result)
        end
        mod:info(
            "DARKTIDEVR_CALIBRATION complete mode=%s floor_eye_height=%s hand_span=%s single_arm_distance=%s forward_reach=%s generation=%d",
            runtime.mode, tostring(result.floor_eye_height),
            tostring(result.hand_span),
            tostring(result.single_arm_head_distance),
            tostring(result.forward_reach),
            result.recenter_generation)
    end
    runtime.samples = {}
end

DarktideVRCalibrationView._refresh_text = function(self)
    local runtime = self._runtime
    local stage = runtime.stage
    local instruction = "Choose standing, seated, bilateral or single-arm calibration."
    if stage == "ready_t_pose" then
        instruction = "Selected: " .. MODE_SETTINGS[runtime.mode].label ..
            ". Hold a comfortable T-pose, release the required trigger(s), then pull them to capture."
    elseif stage == "capture_t_pose" then
        instruction = "Capturing T-pose. Hold still."
    elseif stage == "ready_sides" then
        instruction = "Relax the tracked arm(s) at your sides, release the required trigger(s), then pull them to capture."
    elseif stage == "capture_sides" then
        instruction = "Capturing neutral pose. Hold still."
    elseif stage == "ready_forward" then
        instruction = "Extend the tracked arm(s) comfortably straight forward at shoulder height, release the required trigger(s), then pull them to capture."
    elseif stage == "capture_forward" then
        instruction = "Capturing forward reach. Keep the elbow straight and hold still."
    elseif stage == "complete" then
        local result = runtime.result or {}
        local arm = result.hand_span and string.format(
            "Arm span %.1f cm", result.hand_span * 100) or
            string.format("Head-to-hand reach %.1f cm",
                (result.single_arm_head_distance or 0) * 100)
        local height = result.floor_eye_height and string.format(
            "standing eye height %.1f cm", result.floor_eye_height * 100) or
            "standing eye height unavailable"
        local profile_height = result.profile_height_requested and
            string.format("; official height %.3f (%s)",
                result.profile_height_requested,
                result.profile_height_status or "pending") or ""
        local forward = string.format("forward reach %.1f cm",
            (result.forward_reach or 0) * 100)
        instruction = "Calibration saved. " .. arm .. "; " .. forward ..
            "; " .. height ..
            profile_height ..
            ". Height is applied before residual arm retargeting."
    end
    self._widgets_by_name.instruction.content.text = instruction
    local count = #(runtime.samples or {})
    self._widgets_by_name.status.content.text = runtime.sample_error or
        (string.find(stage, "capture") and
            string.format("Stable samples: %d / %d", count, SAMPLE_FRAMES) or
            (string.find(stage, "ready") and
                (runtime.trigger_armed and
                    "Tracking live - pull the required trigger(s)." or
                    "Tracking live - release the required trigger(s) to arm capture.") or
            (runtime.result and "Saved calibration schema 3" or
                "No calibration saved this session.")))
end

DarktideVRCalibrationView.update = function(self, dt, t, input_service)
    local stage = self._runtime.stage
    if stage == "ready_t_pose" or stage == "ready_sides" or
            stage == "ready_forward" or stage == "capture_t_pose" or
            stage == "capture_sides" or stage == "capture_forward" then
        local sample, error_message = self:_sample()
        if sample then
            self._runtime.sample_error = nil
            self:_refresh_pose_preview(sample)
            if stage == "ready_t_pose" or stage == "ready_sides" or
                    stage == "ready_forward" then
                self:_update_ready_stage(sample)
            else
                local samples = self._runtime.samples
                if #samples == 0 or
                        samples[1].generation == sample.generation then
                    samples[#samples + 1] = sample
                    if #samples >= SAMPLE_FRAMES then
                        self:_finish_capture()
                    end
                else
                    self._runtime.samples = {}
                    self._runtime.sample_error =
                        "View was reset; the stable sample window restarted."
                end
            end
        else
            if string.find(stage, "capture") then
                self._runtime.samples = {}
            end
            self._runtime.sample_error = error_message
        end
        self:_refresh_text()
    end
    return DarktideVRCalibrationView.super.update(self, dt, t, input_service)
end

DarktideVRCalibrationView._on_back_pressed = function(self)
    Managers.ui:close_view(self.view_name)
end

return DarktideVRCalibrationView
