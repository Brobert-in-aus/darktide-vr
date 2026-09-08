local mod = get_mod("darktidevr_stereo_probe")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = false,
    options = {
        widgets = {
            {
                setting_id = "vr_crosshair_scale", type = "numeric",
                default_value = 70, range = {25, 150}, decimals_number = 0, step_size_value = 5,
            },
            {
                setting_id = "vr_aim_stabilization", type = "numeric",
                default_value = 75, range = {0, 100}, decimals_number = 0, step_size_value = 5,
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
                },
            },
            mod:io_dofile("darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_turning").widgets(),
            mod:io_dofile("darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_bindings").widgets(mod),
            {
                setting_id = "psykhanium_online_rules",
                type = "checkbox",
                default_value = true,
            },
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
        },
    },
}
