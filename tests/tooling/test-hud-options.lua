package.loaded["scripts/managers/ui/ui_renderer"] = {}
package.loaded["scripts/managers/ui/ui_widget"] = {}
package.loaded["scripts/foundation/utilities/script_world"] = {}
local panel = dofile(arg[1])
local hooks, values, previous_calls = {}, {}, 0
local mod = {
    hook=function(_, _, name, fn) hooks[name]=fn end,
    get=function(_, name) return values[name] end,
    set=function(_, name, value) values[name]=value end,
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
mod.io_dofile=function(_,path)
    return dofile((arg[4]:gsub("darktidevr_controller_bindings.lua$",path:match("[^/]+$")..".lua")))
end
local data=dofile(arg[2])
local text=dofile(arg[3])
local groups={}
for _,widget in ipairs(data.options.widgets) do
    assert(not groups[widget.setting_id], 'duplicate setting: '..widget.setting_id)
    groups[widget.setting_id]=widget
end
local options=assert(groups.hud_options, 'missing HUD settings')
assert(groups.vr_turning and groups.vr_turning.type=='group')
assert(groups.controller_bindings and groups.controller_bindings.type=='group')
assert(options.setting_id=='hud_options' and options.type=='group')
assert(#options.sub_widgets==6)
assert(options.sub_widgets[6].setting_id=='focus_warning' and
    options.sub_widgets[6].type=='checkbox' and options.sub_widgets[6].default_value==true)
assert(options.sub_widgets[1].setting_id=='hud_visible' and options.sub_widgets[1].type=='checkbox' and
    options.sub_widgets[1].default_value==true and text.hud_visible.en and text.hud_visible_description.en)
assert(text.focus_warning.en and text.focus_warning_description.en and text.hud_focus_notice.en)
for _,widget in ipairs(options.sub_widgets) do
    if widget.type == 'numeric' then
    assert(widget.type=='numeric' and widget.default_value>=widget.range[1] and
        widget.default_value<=widget.range[2])
    assert(text[widget.setting_id].en and text[widget.setting_id..'_description'].en)
    assert(pcall(string.format,text[widget.setting_id].en))
    assert(pcall(string.format,text[widget.setting_id..'_description'].en))
    end
end
assert(string.format(text.hud_size.en)=='HUD size (%)')
assert(options.sub_widgets[2].type=='button' and
    options.sub_widgets[2].function_name=='toggle_vr_hud_editor')
local custom, toggles, blocked = nil, 0, true
get_mod=function(name) return name=='custom_hud' and custom or nil end
assert(not panel.request_editor())
custom={is_customizing=false,is_enabled=function() return true end,
    toggle_hud_customization=function(self) toggles=toggles+1; self.is_customizing=not self.is_customizing end}
state.display_ready=false
assert(not panel.request_editor())
state.display_ready=true
Managers={ui={_view_handler={using_input=function() return blocked end}}}
assert(panel.request_editor())
panel.update_editor_request(owner)
assert(toggles==0 and state.editor_requested)
assert(panel.request_editor()) -- Cancel before closing menus.
blocked=false
panel.update_editor_request(owner)
assert(toggles==0)
assert(panel.request_editor())
panel.update_editor_request(owner); panel.update_editor_request(owner)
assert(toggles==1 and panel.editing() and not state.editor_requested)
local drawn, rects = {}, 0
Vector3=function(x,y,z) return {x,y,z} end
Color=function(...) return {...} end
local api=package.loaded["scripts/managers/ui/ui_renderer"]
api.draw_rect=function(self) assert(self.scale==1); rects=rects+1 end
api.draw_text=function(self, value, size, font, position, dimensions)
    assert(self.scale==1 and self.gui==resource.gui)
    drawn[#drawn+1]={text=value,size=size,position=position,dimensions=dimensions}
end
state.target_width,state.target_height=2496,1404
resource.gui={}
panel.draw_editor_notice(resource); panel.draw_editor_notice(resource)
assert(#drawn==2 and rects==2 and drawn[1].text=='hud_editor_notice')
assert(resource.scale==nil and resource.render_settings==nil,'notice mutated renderer pass state')
custom.is_customizing=false
panel.draw_editor_notice(resource)
assert(#drawn==2,'editor instruction persisted after close')
assert(panel.request_editor())
custom.is_enabled=function() return false end
panel.update_editor_request(owner)
assert(not state.editor_requested and toggles==1)
custom.is_enabled=function() return true end
-- A queued request must not cross a HUD replacement before draw retires the
-- old resources, or open against a display that stopped being ready.
for _,transition in ipairs({'display_lost','owner_replaced','foreign_update'}) do
    state.owner,state.display_ready=owner,true
    blocked=true
    assert(panel.request_editor())
    panel.update_editor_request(owner)
    blocked=false
    local update_owner=owner
    if transition=='display_lost' then state.display_ready=false
    elseif transition=='owner_replaced' then state.owner={}
    else update_owner={} end
    if transition=='foreign_update' then
        hooks.update(function(self) assert(self==update_owner) end,update_owner,0.01,5,{})
    else
        panel.update_editor_request(update_owner)
    end
    assert(toggles==1 and not state.editor_requested,
        'queued HUD editor request survived '..transition)
    state.owner,state.display_ready=owner,true
    panel.update_editor_request(owner)
    assert(toggles==1,'cancelled editor request returned with its old owner')
end
print('hud_options=pass defaults=accepted angular_distance=preserved fixed_refresh=once')
