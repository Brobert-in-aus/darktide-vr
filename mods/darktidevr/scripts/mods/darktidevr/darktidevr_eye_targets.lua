local EyeTargets = {}

-- Opt-in gameplay final-output isolation. Keep the engine-owned internal
-- output_target: with DLSS it depends on dummy_upscaling, not the eye extent.
-- Overriding it with a full-size texture misaligns depth/lighting/history passes.
function EyeTargets.install(mod, script_world, extent)
    local worlds = {}
    local names = { player1 = "left", darktidevr_right_eye = "right" }

    local function release(entry)
        Renderer.destroy_resource(entry.back_buffer)
        Renderer.destroy_resource(entry.hudless_color)
    end

    local function create(name, width, height)
        ResourceReferenceContext.push("DarktideVR:gameplay_stereo")
        ResourceReferenceContext.push(name)
        local ok, resource = pcall(Renderer.create_resource,
            "render_target", "R8G8B8A8", nil, width, height, name)
        ResourceReferenceContext.pop(name)
        ResourceReferenceContext.pop("DarktideVR:gameplay_stereo")
        if not ok then error(resource, 0) end
        assert(resource, "gameplay eye target allocation returned nil")
        return resource
    end

    mod:hook(script_world, "create_viewport", function(func, world, name,
            template, layer, camera_unit, position, rotation, shadow,
            shading, callback, mood, targets, ...)
        local side = names[name]
        local owned = worlds[world]
        -- The primary gameplay camera establishes ownership. Never redirect
        -- arbitrary UI viewports or replace a caller's explicit target mapping.
        if not side or targets or
                (side == "left" and template ~= "default") or
                (side == "right" and not (owned and owned.player1)) then
            return func(world, name, template, layer, camera_unit, position,
                rotation, shadow, shading, callback, mood, targets, ...)
        end
        assert(not (owned and owned[name]), "gameplay eye viewport already owns targets")
        local width, height
        if side == "right" then
            width, height = owned.player1.width, owned.player1.height
        else
            width, height = extent()
        end
        if not (type(width) == "number" and type(height) == "number" and
                width >= 640 and height >= 640 and width <= 7680 and height <= 7680 and
                width == math.floor(width) and height == math.floor(height)) then
            -- No usable extent: stock owns this viewport rather than the
            -- game crashing. Logged once per install.
            if not names.extent_missing_logged then
                names.extent_missing_logged = true
                mod:info("DARKTIDEVR_STEREO eye_targets viewport=%s action=stock reason=extent_invalid",
                    tostring(name))
            end
            return func(world, name, template, layer, camera_unit, position,
                rotation, shadow, shading, callback, mood, targets, ...)
        end
        local entry = { width = width, height = height }
        entry.back_buffer = create("darktidevr_" .. side .. "_eye_final", width, height)
        -- The frame-generation colour allocation otherwise follows the real
        -- wide swapchain even when this viewport has a private final image.
        local ok, hudless = pcall(create,
            "darktidevr_" .. side .. "_eye_hudless", width, height)
        if not ok then
            Renderer.destroy_resource(entry.back_buffer)
            error(hudless, 0)
        end
        entry.hudless_color = hudless
        local mapping = { back_buffer = entry.back_buffer, hudless_color = hudless }
        local created, viewport = pcall(func, world, name, template, layer,
            camera_unit, position, rotation, shadow, shading, callback, mood, mapping, ...)
        if not created or not viewport then
            release(entry)
            error(created and "gameplay viewport creation returned nil" or viewport, 0)
        end
        owned = owned or {}
        worlds[world] = owned
        owned[name] = entry
        mod:info("DARKTIDEVR_EYE_TARGET side=%s size=%dx%d isolated=1", side, width, height)
        return viewport
    end)

    mod:hook(script_world, "destroy_viewport", function(func, world, name, ...)
        -- Engine must release its viewport references before our resources.
        func(world, name, ...)
        local owned = worlds[world]
        if owned and owned[name] then
            local entry = owned[name]
            owned[name] = nil
            release(entry)
            if not next(owned) then worlds[world] = nil end
        end
    end)
    mod:hook(Application, "release_world", function(func, world, ...)
        func(world, ...)
        local owned = worlds[world]
        worlds[world] = nil
        if owned then
            for _, entry in pairs(owned) do release(entry) end
        end
    end)
end

return EyeTargets
