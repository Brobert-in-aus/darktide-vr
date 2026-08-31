local mod = get_mod("darktidevr_stereo_probe")

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
        },
    },
}
