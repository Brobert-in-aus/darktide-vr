bit = require("bit")
local Bindings = dofile(arg[1])
local settings, callbacks = {}, 0
local mod = {get=function(_,key) return settings[key] end,
    on_setting_changed=function() callbacks=callbacks+1 end}
local mapper = Bindings.install(mod)
local function sample(active,physical,p,h,r)
    local ap,ah,ar=mapper.sample(active,physical)
    assert(ap==p and ah==h and ar==r,
        string.format("got %d,%d,%d expected %d,%d,%d",ap,ah,ar,p,h,r))
end
sample(true,0,0,0,0)
sample(true,1,1,1,0)
sample(true,1,0,1,0)
sample(true,0,0,0,1)
sample(true,8+32,4104+8224,4104+8224,0) -- Original paired controls.
sample(false,8+32,0,0,4104+8224)
sample(true,8+32,0,0,0)
sample(true,0,0,0,0)
sample(true,256+1024,1280,1280,0)
sample(true,0,0,0,1280)

-- A live remap releases the old action, suppresses its replacement and leaves
-- keyboard/UI callbacks intact. Each held physical control rearms separately.
sample(true,1,1,1,0)
settings.vr_bind_right_trigger='combat_ability'
mod.on_setting_changed('vr_bind_right_trigger')
assert(callbacks==1)
sample(true,1,0,0,1)
sample(true,1+4,4,4,0)
sample(true,4,0,4,0)
sample(true,1+4,2048,2052,0)
sample(true,0,0,0,2052)

-- Aliases aggregate at the semantic action level, including combined/split
-- actions: a second hold cannot retrigger or release a still-held first action.
settings.vr_bind_a='jump'
settings.vr_bind_b='jump_dodge'
mod.on_setting_changed('vr_bind_a')
sample(true,0,0,0,0)
sample(true,32,32,32,0)
sample(true,32+64,8192,8224,0)
sample(true,64,0,8224,0)
sample(true,0,0,0,8224)
settings.vr_bind_a='reload'
settings.vr_bind_x='interact_reload'
mod.on_setting_changed('vr_bind_a')
sample(true,0,0,0,0)
sample(true,32,4096,4096,0)
sample(true,40,8,4104,0)
sample(true,8,0,4104,0)
sample(true,0,0,0,4104)

settings.vr_bind_right_trigger='unbound'
settings.vr_bind_left_trigger='invalid_old_setting'
mod.on_setting_changed('vr_bind_right_trigger')
sample(true,0,0,0,0)
sample(true,3,2,2,0)
mod.on_setting_changed('hud_size') -- Unrelated setting must not quarantine fire.
sample(true,3,0,2,0)
sample(false,0,0,0,2)
sample(true,3,0,0,0)
sample(true,0,0,0,0)
sample(true,3,2,2,0)

-- Options/defaults/localization and actual game input names share the catalog.
local text=dofile(arg[2])
local stock=dofile(arg[3])
local names={}
for _,name in ipairs(stock.actions) do names[name]='held' end
for _,name in ipairs(stock.ephemeral_actions) do names[name]='edge' end
for _,binding in ipairs(mapper.bindings) do
    for _,name in ipairs(binding.held) do assert(names[name]=='held',name) end
    for _,kind in ipairs({'pressed','released'}) do
        for _,name in ipairs(binding[kind]) do assert(names[name]=='edge',name) end
    end
end
local widgets=Bindings.widgets()
assert(#widgets.sub_widgets==11)
local used={}
for _,widget in ipairs(widgets.sub_widgets) do
    assert(not used[widget.setting_id]); used[widget.setting_id]=true
    assert(pcall(string.format,text[widget.setting_id].en))
    local found=false
    for _,option in ipairs(widget.options) do
        assert(pcall(string.format,text[option.text].en))
        found=found or option.value==widget.default_value
    end
    assert(found)
end
print('controller_bindings=pass defaults aliases remap_release context_handoff stock_names options')
