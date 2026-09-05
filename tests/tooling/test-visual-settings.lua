local module = dofile(arg[1])
local hooks, settings, render = {}, {}, {}
local ui = {update=function() return 'updated' end}
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
mod = {
    hook = function(self, target, name, fn)
        local original = target[name]
        hooks[target] = hooks[target] or {}
        assert(not hooks[target][name], 'DMF rejects duplicate hooks from one mod')
        hooks[target][name] = true
        target[name] = function(...) return fn(original, ...) end
    end,
    hook_safe = function() error('Register startup through the existing UI update hook') end,
    info = function() end,
}
module.install(mod)
if arg[2] then
    local file = assert(io.open(arg[2], 'r'))
    local source = file:read('*all')
    file:close()
    local first = assert(source:find('mod:hook(\n    require("scripts/managers/ui/ui_manager"),\n    "update",', 1, true))
    local last = assert(source:find('\n-- Darktide', first, true))
    local noop = function() end
    presentation = {
        visual_settings=module, begin_menu_pointer_frame=noop,
        reconcile_fullscreen_views=noop, update_system_menu_test=noop,
        update_vendor_menu_test=noop, update_psykhanium=noop,
    }
    assert(loadstring(source:sub(first,last-1)))()
    assert(ui.update({}, .01, 1) == 'updated')
else
    module.update()
end
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
