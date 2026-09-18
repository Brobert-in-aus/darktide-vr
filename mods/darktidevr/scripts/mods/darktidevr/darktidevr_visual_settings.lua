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
local environment_disabled = {
    dof_enabled = true,
    fullscreen_blur_enabled = true,
    fullscreen_blur_amount = true,
}

function VisualSettings.install(mod)
    -- Camera mood blends and several menus bypass render-settings writes.
    -- Clamp at the final apply boundary, after those blends/direct writes,
    -- rather than altering the shared mood resources or other lighting values.
    mod:hook(ShadingEnvironment, "apply", function(func, environment, ...)
        for key in pairs(environment_disabled) do
            ShadingEnvironment.set_scalar(environment, key, 0)
        end
        return func(environment, ...)
    end)
    local function enforce()
        -- Startup reconciliation can replace the launcher's windowed setting.
        -- Keep the VR mirror in window mode at the engine apply boundary too.
        Application.set_user_setting("fullscreen", false)
        Application.set_user_setting("borderless_fullscreen", false)
        Application.set_user_setting("screen_mode", "window")
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
        if location == "fullscreen" or location == "borderless_fullscreen" then
            if key == true then
                mod:info("DARKTIDEVR_DISPLAY rejected %s=true", location)
            end
            return func(location, false)
        elseif location == "screen_mode" then
            return func(location, "window")
        end
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
                -- arity: deliberate. The tail begins at the value being
                -- replaced, so forwarding it would pass the very setting this
                -- is overriding back to the engine.
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
            Application.apply_user_settings()
            mod:info("DARKTIDEVR_DISPLAY windowed=forced fullscreen=%s",
                tostring(Application.is_fullscreen and Application.is_fullscreen()))
            mod:info("DARKTIDEVR_VISUAL_SETTINGS blur_dof_lens=forced_off")
            if Application.settings then
                local ok, settings = pcall(Application.settings)
                if ok and type(settings) == "table" then
                    local streamer = settings.feedback_streamer_settings
                    mod:info("DARKTIDEVR_STREAMING texture_pool_limit=%s workers=%s",
                        tostring(type(streamer) == "table" and
                            streamer.max_texture_pool_size or "unavailable"),
                        tostring(settings.max_worker_threads or "unavailable"))
                end
            end
        end
    end
end

return VisualSettings
