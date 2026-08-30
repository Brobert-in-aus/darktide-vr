local UIWidget = require("scripts/managers/ui/ui_widget")
local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local UISoundEvents = require("scripts/settings/ui/ui_sound_events")

local calibration = {}

function calibration.install(mod, controller_state, get_head_pose)
    if mod.darktidevr_calibration then
        return mod.darktidevr_calibration
    end

    local runtime = {
        controller_state = controller_state,
        get_head_pose = get_head_pose,
        mode = nil,
        stage = "choose_mode",
        samples = {},
        result = mod:get("vr_calibration_v1"),
    }
    mod.darktidevr_calibration = runtime

    function runtime:sample(request)
        local state = self.controller_state
        local head = self.get_head_pose and self.get_head_pose()
        if not head then
            request.error = "Waiting for a valid headset pose."
            return
        end
        if request.left and not state.left_grip_tracking_live then
            request.error = "Waiting for left controller tracking."
            return
        end
        if request.right and not state.right_grip_tracking_live then
            request.error = "Waiting for right controller tracking."
            return
        end
        request.sample = {
            generation = state.head_recenter_generation or 0,
            head = {
                tonumber(head[0]), tonumber(head[2]), tonumber(head[1]),
            },
        }
        if request.left then
            request.sample.left = {
                state.left_grip_x, state.left_grip_y, state.left_grip_z,
            }
        end
        if request.right then
            request.sample.right = {
                state.right_grip_x, state.right_grip_y, state.right_grip_z,
            }
        end
    end
    Managers.event:register(
        runtime, "event_darktidevr_calibration_sample", "sample")

    local view_path =
        "darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_calibration_view"
    mod:add_require_path(view_path)
    mod:register_view({
        view_name = "darktidevr_calibration_view",
        view_settings = {
            init_view_function = function()
                return true
            end,
            state_bound = true,
            path = view_path,
            class = "DarktideVRCalibrationView",
            disable_game_world = false,
            load_always = true,
            load_in_hub = true,
            enter_sound_events = { UISoundEvents.system_menu_enter },
            exit_sound_events = { UISoundEvents.system_menu_exit },
        },
        view_transitions = {},
        view_options = {
            close_all = false,
            close_previous = false,
        },
    })

    local MainMenuView = require(
        "scripts/ui/views/main_menu_view/main_menu_view")
    mod:hook_safe(MainMenuView, "init", function(self)
        local definitions = self._definitions
        definitions.scenegraph_definition.dtvr_calibration_button = {
            parent = "screen",
            horizontal_alignment = "center",
            vertical_alignment = "top",
            size = { 360, 54 },
            position = { 0, 35, 200 },
        }
        definitions.widget_definitions.dtvr_calibration_button =
            UIWidget.create_definition(
                ButtonPassTemplates.terminal_button,
                "dtvr_calibration_button",
                { original_text = "VR CALIBRATION" })
    end)
    mod:hook_safe(MainMenuView, "on_enter", function(self)
        local widget = self._widgets_by_name and
            self._widgets_by_name.dtvr_calibration_button
        if widget and widget.content and widget.content.hotspot then
            widget.content.hotspot.pressed_callback = function()
                if not Managers.ui:view_instance(
                        "darktidevr_calibration_view") then
                    Managers.ui:open_view(
                        "darktidevr_calibration_view", nil, nil, nil, nil,
                        {})
                end
            end
        end
        mod:info(
            "DARKTIDEVR_CALIBRATION main_menu_entry widget=%s",
            tostring(widget ~= nil))
    end)

    mod:command("dtvr_calibration", "Open VR body calibration", function()
        if not Managers.ui:view_instance("darktidevr_calibration_view") then
            Managers.ui:open_view(
                "darktidevr_calibration_view", nil, nil, nil, nil,
                {})
        end
    end)

    mod:info("DARKTIDEVR_CALIBRATION registered schema=1")
    return runtime
end

return calibration
