local module = dofile(arg[1])
local hooks, settings, render = {}, {}, {}
local ui = {update=function() return 'updated' end}
require = function() return ui end
local applied
ShadingEnvironment = {
    set_scalar = function(environment, key, value) environment[key] = value end,
    apply = function(environment, marker)
        -- Inspect at the original function boundary, not after application.
        assert(environment.dof_enabled == 0 and environment.fullscreen_blur_enabled == 0)
        assert(environment.fullscreen_blur_amount == 0)
        applied = environment
        return marker, nil, 'applied_environment'
    end,
}
Application = {
    set_user_setting = function(location, key, value)
        if value == nil and type(key) ~= 'table' then
            settings[location] = key
            return
        end
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
assert(settings.fullscreen == false and settings.borderless_fullscreen == false)
assert(settings.screen_mode == 'window')
Application.set_user_setting('fullscreen', true)
Application.set_user_setting('screen_mode', 'fullscreen')
assert(settings.fullscreen == false and settings.screen_mode == 'window')
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
local scene = {dof_enabled=1, fullscreen_blur_enabled=1, fullscreen_blur_amount=.8,
    exposure_compensation=2, ui_bloom_enabled=1, grey_scale_enabled=1}
local marker, middle, last = ShadingEnvironment.apply(scene, 'scene')
assert(marker == 'scene' and middle == nil and last == 'applied_environment')
assert(applied == scene and scene.exposure_compensation == 2 and scene.ui_bloom_enabled == 1)
assert(scene.grey_scale_enabled == 1, 'unrelated environment effect was changed')
-- Simulate a subsequent mood blend replacing scalar values without going
-- through set_render_setting, followed by a camera's direct DOF write.
scene.fullscreen_blur_enabled, scene.fullscreen_blur_amount = 1, .5
ShadingEnvironment.set_scalar(scene, 'dof_enabled', 1)
ShadingEnvironment.apply(scene)
local second_scene = {dof_enabled=1, exposure_compensation=-1}
ShadingEnvironment.apply(second_scene)
assert(second_scene.exposure_compensation == -1, 'second viewport lighting changed')
print('VR visual settings: startup, presets, direct writes, apply and environment bypasses passed')
