local EyeTargets = {}

-- Opt-in gameplay output isolation. The world graph and its final colour
-- texture have separate resources, matching the established UI viewport path.
function EyeTargets.install(mod, script_world, extent)
    local worlds = {}
    local names = { player1 = "left", darktidevr_right_eye = "right" }

    local function release(entry)
        Renderer.destroy_resource(entry.back_buffer)
        Renderer.destroy_resource(entry.output_target)
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
            shading, callback, mood, targets)
        local side = names[name]
        local owned = worlds[world]
        -- The primary gameplay camera establishes ownership. Never redirect
        -- arbitrary UI viewports or replace a caller's explicit target mapping.
        if not side or targets or
                (side == "left" and template ~= "default") or
                (side == "right" and not (owned and owned.player1)) then
            return func(world, name, template, layer, camera_unit, position,
                rotation, shadow, shading, callback, mood, targets)
        end
        assert(not (owned and owned[name]), "gameplay eye viewport already owns targets")
        local width, height
        if side == "right" then
            width, height = owned.player1.width, owned.player1.height
        else
            width, height = extent()
        end
        assert(type(width) == "number" and type(height) == "number" and
            width >= 640 and height >= 640 and width <= 7680 and height <= 7680 and
            width == math.floor(width) and height == math.floor(height),
            "gameplay eye extent is unavailable or invalid")
        local entry = { width = width, height = height }
        entry.output_target = create("darktidevr_" .. side .. "_eye_output", width, height)
        local ok, final = pcall(create, "darktidevr_" .. side .. "_eye_final", width, height)
        if not ok then
            Renderer.destroy_resource(entry.output_target)
            error(final, 0)
        end
        entry.back_buffer = final
        local mapping = { output_target = entry.output_target, back_buffer = final }
        local created, viewport = pcall(func, world, name, template, layer,
            camera_unit, position, rotation, shadow, shading, callback, mood, mapping)
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
