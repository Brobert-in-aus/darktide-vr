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
                        -- The value is kept as it was so saved settings
                        -- survive; the label and the code behind it name the
                        -- off hand (docs/phase1/handedness-audit-2026-09-16.md).
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
                setting_id = "vr_sway_cancel", type = "numeric",
                default_value = 0, range = {0, 100}, decimals_number = 0, step_size_value = 10,
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
                        setting_id = "stereo_cinematics",
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
            -- The last group before the controller bindings. Setting ids are
            -- unchanged when a setting moves here, so saved values carry over.
            {
                setting_id = "experimental_options",
                type = "group",
                sub_widgets = {
                    mod:io_dofile("darktidevr/scripts/mods/darktidevr/darktidevr_keyboard_mouse").widgets(),
                    {
                        setting_id = "marker_plane",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "psykhanium_online_rules",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "vr_two_hand_support",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "vr_two_hand_grip_mode",
                        type = "dropdown",
                        default_value = "hold",
                        options = {
                            {text = "vr_two_hand_grip_hold", value = "hold"},
                            {text = "vr_two_hand_grip_toggle", value = "toggle"},
                        },
                    },
                    {
                        setting_id = "vr_virtual_stock",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "vr_full_body_experimental",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "vr_forearm_holsters",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "vr_skull_throw",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "vr_comms_gesture",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "vr_tag_gesture",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        -- One display for a melee weapon's special charges
                        -- (user, 16 September: the count and the bars showed
                        -- the same thing in two places).
                        setting_id = "vr_weapon_charge_style",
                        type = "dropdown",
                        default_value = "count",
                        options = {
                            {text = "vr_weapon_charge_style_count", value = "count"},
                            {text = "vr_weapon_charge_style_bars", value = "bars"},
                            {text = "vr_weapon_charge_style_off", value = "off"},
                        },
                    },
                    {
                        setting_id = "vr_item_radial",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "vr_wrist_display",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "vr_wrist_display_scale", type = "numeric",
                        default_value = 100, range = {50, 200}, decimals_number = 0, step_size_value = 5,
                    },
                    {
                        setting_id = "vr_teammate_status",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "vr_holster_counts",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "vr_sight_ads",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "vr_haptics_mode",
                        type = "dropdown",
                        default_value = "off",
                        options = {
                            {text = "vr_haptics_off", value = "off"},
                            {text = "vr_haptics_informative", value = "informative"},
                            {text = "vr_haptics_immersive", value = "immersive"},
                        },
                    },
                    {
                        setting_id = "vr_haptics_strength", type = "numeric",
                        default_value = 100, range = {25, 200}, decimals_number = 0, step_size_value = 5,
                    },
                    {
                        setting_id = "vr_ammo_readout",
                        type = "checkbox",
                        default_value = false,
                    },
                },
            },
            mod:io_dofile("darktidevr/scripts/mods/darktidevr/darktidevr_controller_bindings").widgets(mod),
        },
    },
}
