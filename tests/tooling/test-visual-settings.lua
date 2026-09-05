local module = dofile(arg[1])
local hooks, safe, settings, render = {}, {}, {}, {}
local ui = {}
require = function() return ui end
Application = {
    set_user_setting = function(location, key, value)
        settings[location] = settings[location] or {}
        if type(key) == 'table' then settings[location] = key
        else settings[location][key] = value end
    end,
    set_render_setting = function(key, value) render[key] = value end,
    apply_user_settings = function() return 'applied' end,
}
local mod = {
    hook = function(self, target, name, fn)
        local original = target[name]
        target[name] = function(...) return fn(original, ...) end
    end,
    hook_safe = function(self, target, name, fn) safe[name] = fn end,
    info = function() end,
}
module.install(mod)
safe.update()
assert(render.dof_enabled == 'false')
local preset = { dof_enabled = true, motion_blur_enabled = true, unrelated = 7 }
Application.set_user_setting('render_settings', preset)
assert(preset.dof_enabled == true, 'do not mutate the shared preset')
assert(settings.render_settings.dof_enabled == false)
assert(settings.render_settings.unrelated == 7)
Application.set_user_setting('master_render_settings', 'dof_quality', 'high')
assert(settings.master_render_settings.dof_quality == 'off')
Application.set_render_setting('sun_flare_enabled', 'true')
assert(render.sun_flare_enabled == 'false')
Application.set_render_setting('unrelated', 'true')
assert(render.unrelated == 'true')
settings.render_settings.lens_quality_enabled = true
assert(Application.apply_user_settings() == 'applied')
assert(settings.render_settings.lens_quality_enabled == false)
print('VR visual settings: startup, presets, direct writes and apply passed')
