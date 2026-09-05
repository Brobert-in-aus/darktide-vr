local VisualSettings = {}

local disabled = {
    dof_enabled = true,
    dof_high_quality = true,
    motion_blur_enabled = true,
    lens_quality_enabled = true,
    lens_quality_color_fringe_enabled = true,
    lens_quality_distortion_enabled = true,
    lens_flares_enabled = true,
    sun_flare_enabled = true,
}
local qualities = { dof_quality = true, lens_flare_quality = true }

function VisualSettings.install(mod)
    local function enforce()
        for key in pairs(disabled) do
            Application.set_user_setting("render_settings", key, false)
            Application.set_render_setting(key, "false")
        end
        for key in pairs(qualities) do
            Application.set_user_setting("master_render_settings", key, "off")
        end
    end

    mod:hook(Application, "set_render_setting", function(func, key, value, ...)
        if disabled[key] then value = "false" end
        return func(key, value, ...)
    end)
    mod:hook(Application, "set_user_setting", function(func, location, key, ...)
        local policy = location == "render_settings" and disabled or
            (location == "master_render_settings" and qualities)
        if policy then
            local forced = "off"
            if location == "render_settings" then forced = false end
            if type(key) == "table" then
                local copy = {}
                for name, value in pairs(key) do copy[name] = value end
                for name in pairs(policy) do copy[name] = forced end
                return func(location, copy, ...)
            elseif policy[key] then
                return func(location, key, forced)
            end
        end
        return func(location, key, ...)
    end)
    mod:hook(Application, "apply_user_settings", function(func, ...)
        enforce()
        return func(...)
    end)
    local pending = true
    function VisualSettings.update()
        if pending then
            pending = false
            enforce()
            mod:info("DARKTIDEVR_VISUAL_SETTINGS blur_dof_lens=forced_off")
        end
    end
end

return VisualSettings
