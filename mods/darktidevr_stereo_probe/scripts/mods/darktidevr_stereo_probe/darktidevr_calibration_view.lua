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

DarktideVRCalibrationView.init = function(self, settings, context)
    self._runtime = {
        mode = nil,
        stage = "choose_mode",
        samples = {},
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
    self:_bind("capture", "cb_capture")
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
    self:_refresh_text()
end

DarktideVRCalibrationView.cb_capture = function(self)
    local stage = self._runtime.stage
    if stage == "ready_t_pose" then
        self._runtime.stage = "capture_t_pose"
        self._runtime.samples = {}
    elseif stage == "ready_sides" then
        self._runtime.stage = "capture_sides"
        self._runtime.samples = {}
    end
    self:_refresh_text()
end

DarktideVRCalibrationView.cb_retry = function(self)
    if self._runtime.stage == "complete" or
            string.find(self._runtime.stage, "sides") then
        self._runtime.stage = "ready_sides"
    elseif self._runtime.mode then
        self._runtime.stage = "ready_t_pose"
    end
    self._runtime.samples = {}
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
    else
        runtime.sides = means
        local result = {
            schema = 1,
            mode = runtime.mode,
            seated = mode.seated,
            bilateral = mode.left and mode.right,
            source_space = "recentered_openxr_metres",
            sample_frames = SAMPLE_FRAMES,
            recenter_generation = samples[1].generation,
            t_pose = runtime.t_pose,
            sides = runtime.sides,
        }
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
        runtime.result = result
        runtime.stage = "complete"
        mod:set("vr_calibration_v1", result)
        mod:info(
            "DARKTIDEVR_CALIBRATION complete mode=%s hand_span=%s single_arm_distance=%s generation=%d",
            runtime.mode, tostring(result.hand_span),
            tostring(result.single_arm_head_distance),
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
            ". Hold the tracked arm(s) straight out in a comfortable T-pose, then select Capture Pose."
    elseif stage == "capture_t_pose" then
        instruction = "Capturing T-pose. Hold still."
    elseif stage == "ready_sides" then
        instruction = "Relax the tracked arm(s) naturally at your sides, then select Capture Pose."
    elseif stage == "capture_sides" then
        instruction = "Capturing neutral pose. Hold still."
    elseif stage == "complete" then
        instruction = "Calibration saved. Physical source measurements remain separate from the selected operative rig."
    end
    self._widgets_by_name.instruction.content.text = instruction
    local count = #(runtime.samples or {})
    self._widgets_by_name.status.content.text = runtime.sample_error or
        (string.find(stage, "capture") and
            string.format("Stable samples: %d / %d", count, SAMPLE_FRAMES) or
            (runtime.result and "Saved calibration schema 1" or
                "No calibration saved this session."))
end

DarktideVRCalibrationView.update = function(self, dt, t, input_service)
    local stage = self._runtime.stage
    if stage == "capture_t_pose" or stage == "capture_sides" then
        local sample, error_message = self:_sample()
        if sample then
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
        else
            self._runtime.samples = {}
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
