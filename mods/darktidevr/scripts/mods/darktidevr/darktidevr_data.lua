local mod = get_mod("darktidevr")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = false,
    options = {
        widgets = {
            {
                setting_id = "movement_reference",
                type = "dropdown",
                default_value = "head",
                options = {
                    {
                        text = "movement_reference_head",
                        value = "head",
                    },
                    {
                        text = "movement_reference_left_hand",
                        value = "left_hand",
                    },
                },
            },
            {
                setting_id = "vr_crosshair_scale", type = "numeric",
                default_value = 70, range = {25, 150}, decimals_number = 0, step_size_value = 5,
            },
            {
                setting_id = "vr_aim_stabilization", type = "numeric",
                default_value = 75, range = {0, 100}, decimals_number = 0, step_size_value = 5,
            },
            {
                setting_id = "ads_focus",
                type = "checkbox",
                default_value = true,
            },
            {
                setting_id = "melee_preview_toggle",
                type = "button",
                button_text = "melee_preview_toggle_button",
                button_trigger = "pressed",
                function_name = "toggle_melee_preview",
            },
            {
                setting_id = "melee_preview_keybind",
                type = "keybind",
                default_value = {"f6"},
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                keybind_global = true,
                function_name = "toggle_melee_preview",
            },
            {
                setting_id = "scanner_test_keybind",
                type = "keybind",
                default_value = {"f7"},
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                keybind_global = true,
                function_name = "toggle_scanner_test",
            },
            {
                setting_id = "vr_gun_pitch",
                type = "numeric",
                default_value = -10,
                range = {-45, 45},
                decimals_number = 0,
                step_size_value = 1,
            },
            {
                setting_id = "hud_options",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "hud_visible",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "hud_editor",
                        type = "button",
                        button_text = "hud_editor_button",
                        button_trigger = "pressed",
                        function_name = "toggle_vr_hud_editor",
                    },
                    {
                        setting_id = "hud_size",
                        type = "numeric",
                        default_value = 100,
                        range = {50, 150},
                        decimals_number = 0,
                        step_size_value = 5,
                    },
                    {
                        setting_id = "hud_distance",
                        type = "numeric",
                        default_value = 2,
                        range = {0.75, 4},
                        decimals_number = 2,
                        step_size_value = 0.25,
                    },
                    {
                        setting_id = "hud_internal_scale",
                        type = "numeric",
                        default_value = 100,
                        range = {50, 150},
                        decimals_number = 0,
                        step_size_value = 5,
                    },
                    {
                        setting_id = "focus_warning",
                        type = "checkbox",
                        default_value = true,
                    },
                },
            },
            {
                setting_id = "mode_options",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "hub_third_person",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "spectate_third_person",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "marker_plane",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "stereo_cinematics",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "psykhanium_online_rules",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "remote_mission_input",
                        type = "checkbox",
                        default_value = true,
                    },
                },
            },
            mod:io_dofile("darktidevr/scripts/mods/darktidevr/darktidevr_turning").widgets(),
            mod:io_dofile("darktidevr/scripts/mods/darktidevr/darktidevr_controller_bindings").widgets(mod),
        },
    },
}
