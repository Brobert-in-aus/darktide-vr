package.loaded["scripts/managers/ui/ui_renderer"] = {}
package.loaded["scripts/managers/ui/ui_widget"] = {}
package.loaded["scripts/foundation/utilities/script_world"] = {}
local panel = dofile(arg[1])
local hooks, values, previous_calls = {}, {}, 0
local mod = {
    hook=function(_, _, name, fn) hooks[name]=fn end,
    get=function(_, name) return values[name] end,
    localize=function(_, name) return name end,
    info=function() end,
    on_setting_changed=function() previous_calls=previous_calls+1 end,
}
panel.install(mod)
assert(panel.scale==0.63 and panel.distance==2 and panel.object_scale==2.08)
local baseline_angle=panel.height*panel.scale/panel.distance
local state
for i=1,20 do
    local name,value=debug.getupvalue(panel.enabled,i)
    if name=='state' then state=value; break end
end
assert(state)
local refreshed,dirty,spatial_refreshed=0,0,0
local saved_position={123,456}
local fixed={__class_name='HudElementPlayerHealth',position=saved_position,
    on_resolution_modified=function() refreshed=refreshed+1 end,
    set_dirty=function() dirty=dirty+1 end}
local spatial={__class_name='HudElementWorldMarkers',
    on_resolution_modified=function() spatial_refreshed=spatial_refreshed+1 end}
local owner={_elements_array={fixed,spatial}}
local resource,target={},{}
state.owner,state.resource_renderer,state.display_target=owner,resource,target
state.enabled,state.flag_last_poll_t,state.editor_was_open=true,math.huge,false
local function update(t)
    hooks.update(function(self)
        assert(self==owner)
    end,owner,0.01,t,{})
end
values.hud_distance=4
mod.on_setting_changed('hud_distance')
assert(panel.distance==4 and math.abs(panel.height*panel.scale/panel.distance-baseline_angle)<1e-12)
update(1)
assert(refreshed==0 and dirty==0,'distance reauthored the internal layout')
values.hud_size=125
mod.on_setting_changed('hud_size')
assert(math.abs(panel.scale-0.63*1.25)<1e-12)
update(2)
assert(refreshed==0 and dirty==0,'size reauthored the internal layout')
values.hud_internal_scale=120
mod.on_setting_changed('hud_internal_scale')
assert(math.abs(panel.object_scale-2.08*1.2)<1e-12)
update(3); update(4)
assert(refreshed==1 and dirty==1 and spatial_refreshed==0)
assert(state.resource_renderer==resource and state.display_target==target,'reallocated GPU owner')
assert(fixed.position==saved_position and saved_position[1]==123 and saved_position[2]==456)
mod.on_setting_changed('movement_reference')
assert(previous_calls==4,'replaced an existing settings callback')
assert(panel.distance==4)
panel.apply_settings(1000,-1,0)
assert(panel.scale==0.945 and panel.distance==0.75 and panel.object_scale==1.04)
panel.apply_settings(0/0,math.huge,'bad')
assert(panel.scale==0.63 and panel.distance==2 and panel.object_scale==2.08)
assert(not panel.apply_settings(100,2,100),'default settings are not idempotent')
get_mod=function() return mod end
local data=dofile(arg[2])
local text=dofile(arg[3])
local options=data.options.widgets[1]
assert(options.setting_id=='hud_options' and options.type=='group')
assert(#options.sub_widgets==3)
for _,widget in ipairs(options.sub_widgets) do
    assert(widget.type=='numeric' and widget.default_value>=widget.range[1] and
        widget.default_value<=widget.range[2])
    assert(text[widget.setting_id].en and text[widget.setting_id..'_description'].en)
    assert(pcall(string.format,text[widget.setting_id].en))
    assert(pcall(string.format,text[widget.setting_id..'_description'].en))
end
assert(string.format(text.hud_size.en)=='HUD size (%)')
print('hud_options=pass defaults=accepted angular_distance=preserved fixed_refresh=once')
