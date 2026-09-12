local Startup = {}
local root = "./../mods/darktidevr/"

function Startup.read(open)
    local function present(name)
        local file = open(root .. "bin/" .. name, "r")
        if not file then return false end
        file:close()
        return true
    end
    local function enabled(name)
        local file = open(root .. name, "r")
        if not file then return false end
        local text = file:read("*all")
        file:close()
        -- Match the bootstrap's bounded ASCII flag grammar, including case.
        return type(text) == "string" and #text <= 31 and
            text:lower():match("^[ \t\r\n]*enabled[ \t\r\n]*$") ~= nil
    end
    local dump = present("darktidevr_vertex_shader_dump.flag")
    local diagnostics = present("darktidevr_diagnostic_render_hooks.flag")
    local pass_trace = enabled("darktidevr_performance_pass_trace.flag")
    local draw_census = enabled("darktidevr_billboard_draw_census.flag")
    return {
        diagnostic_hooks = diagnostics or dump or pass_trace or draw_census,
        draw_census = draw_census,
        vertex_dump = dump,
        substitution = present("darktidevr_billboard_shader_substitution.flag"),
        pixel_probe = enabled("darktidevr_billboard_pixel_shader_probe.flag"),
        pass_trace = pass_trace,
        performance_profile = enabled("darktidevr_performance_profile.flag") or pass_trace,
        offline_dual_view = enabled("darktidevr_offline_dual_view.flag"),
    }
end

return Startup
