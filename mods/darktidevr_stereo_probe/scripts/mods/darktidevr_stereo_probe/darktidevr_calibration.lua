local UIWidget = require("scripts/managers/ui/ui_widget")
local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local UISoundEvents = require("scripts/settings/ui/ui_sound_events")
local Breeds = require("scripts/settings/breed/breeds")

local calibration = {}

function calibration.install(mod, controller_state, get_head_pose,
        refresh_controller_state)
    if mod.darktidevr_calibration then
        return mod.darktidevr_calibration
    end

    local runtime = {
        controller_state = controller_state,
        get_head_pose = get_head_pose,
        refresh_controller_state = refresh_controller_state,
        mode = nil,
        stage = "choose_mode",
        samples = {},
        result = mod:get("vr_calibration_v1"),
    }
    mod.darktidevr_calibration = runtime

    -- Match the official barber flow: persist an in-range height through the
    -- ProfilesService, then update the live profile only after the backend
    -- accepts it. Calibration never writes an out-of-range value. Any residual
    -- beyond the stock slider remains a local visual presentation correction.
    function runtime:apply_official_character_height(result)
        if not result or result.seated or
                not tonumber(result.floor_eye_height) then
            return false, "standing_height_unavailable"
        end
        local player = Managers.player and Managers.player:local_player(1)
        local profile = player and player:profile()
        local service = Managers.data_service and
            Managers.data_service.profiles
        local character_id = player and player:character_id()
        if not profile or not profile.personal or not service or
                not character_id then
            result.profile_height_status = "service_unavailable"
            return false, result.profile_height_status
        end
        local archetype = profile.archetype
        local breed = archetype and Breeds[archetype.breed]
        local height_range = breed and breed.size_variation_range
        local authored_eye_height = breed and breed.heights and
            tonumber(breed.heights.default)
        if not height_range or not authored_eye_height or
                authored_eye_height <= 0 then
            result.profile_height_status = "breed_height_unavailable"
            return false, result.profile_height_status
        end
        local target_scale = math.max(height_range[1], math.min(
            height_range[2], tonumber(result.floor_eye_height) /
                authored_eye_height))
        target_scale = tonumber(string.format("%.3f", target_scale))
        result.profile_height_previous =
            tonumber(profile.personal.character_height)
        result.profile_height_requested = target_scale
        if result.profile_height_previous and math.abs(
                result.profile_height_previous - target_scale) < 0.0005 then
            result.profile_height_status = "already_current"
            mod:set("vr_calibration_v1", result)
            return true, result.profile_height_status
        end
        result.profile_height_status = "pending"
        mod:set("vr_calibration_v1", result)
        service:set_character_height(character_id, target_scale):next(function()
            profile.personal.character_height = target_scale
            result.profile_height_status = "accepted"
            mod:set("vr_calibration_v1", result)
            mod:info(
                "DARKTIDEVR_CALIBRATION profile_height accepted previous=%s requested=%.3f archetype=%s",
                tostring(result.profile_height_previous), target_scale,
                tostring(archetype.name or archetype.breed))
        end):catch(function()
            result.profile_height_status = "rejected"
            mod:set("vr_calibration_v1", result)
            mod:warning(
                "DARKTIDEVR_CALIBRATION profile_height rejected requested=%.3f archetype=%s",
                target_scale, tostring(archetype.name or archetype.breed))
        end)
        return true, "pending"
    end

    function runtime:sample(request)
        local state = self.controller_state
        if self.refresh_controller_state and
                not self.refresh_controller_state() then
            request.error = "Waiting for a fresh controller pose."
            return
        end
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
            left_tracked = state.left_grip_tracking_live == true,
            right_tracked = state.right_grip_tracking_live == true,
            left_trigger = tonumber(state.left_trigger) or 0,
            right_trigger = tonumber(state.right_trigger) or 0,
            -- Grip samples arrive in Darktide's Z-up body basis (x right,
            -- y forward, z up). The head values are raw OpenXR (y up, z back),
            -- so forward is the negated z component.
            head = {
                tonumber(head[0]), -tonumber(head[2]), tonumber(head[1]),
            },
            floor_eye_height = tonumber(head[24]) or 0,
        }
        if state.left_grip_tracking_live then
            request.sample.left = {
                state.left_grip_x, state.left_grip_y, state.left_grip_z,
            }
        end
        if state.right_grip_tracking_live then
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

    mod:info("DARKTIDEVR_CALIBRATION registered schema=2")
    return runtime
end

return calibration
