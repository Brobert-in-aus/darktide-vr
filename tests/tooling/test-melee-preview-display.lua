local Display=dofile(assert(arg[1]))
assert(not Display.startup_requested(nil))
local closed=0
local function startup(contents)
    return Display.startup_requested({open=function(path,mode)
        assert(path:find('darktidevr_melee_preview.flag',1,true) and mode=='r')
        return {read=function(_,n) assert(n==32);return contents end,
            close=function() closed=closed+1 end}
    end})
end
assert(startup('enabled\n') and not startup('disabled') and not startup('enabled junk'))
assert(closed==3)
local commands={}
local start_hook,logs
local visible,created,destroyed,draws=false,0,0,0
local unit={}
local blocked=false
local extension={_world={},_first_person_component={position={x=0,y=0,z=0}}}
extension._inventory_component={wielded_slot='primary'}
extension._weapons={primary={}}
local context={paths={}} -- Geometry/pose tests live in test-melee-preview.lua.
local context_reads=0
local mod={io_dofile=function() return {context=function()
    context_reads=context_reads+1; return context
end} end, command=function(_,name,_,fn) commands[name]=fn end,
    info=function(_,...) logs={...} end, warning=function() end, echo=function() end,
    hook_safe=function(_,class,method,callback)
        assert(class=='ActionSweep' and method=='start'); start_hook=callback
    end}
Managers={player={local_player_safe=function() return {player_unit=unit} end},ui={},
    time={time=function() return 1 end}}
Unit={alive=function() return true end}
ScriptUnit={has_extension=function() return extension end}
World={create_world_gui=function() created=created+1; return {} end,
    destroy_gui=function() destroyed=destroyed+1; visible=false end}
Matrix4x4={identity=function() return {} end}
Gui={set_visible=function(_,value) visible=value end,
    rect_3d=function() draws=draws+1 end}
local presentation={mode=1,gameplay_context={ui_blocks_gameplay=function() return blocked end}}
local tracking={authoring_enabled=true,right_aim_usable=true}
local api=Display.install(mod,presentation,tracking)
api.update(); assert(context_reads==0 and created==0,'Disabled preview acquired game state')
Mods={lua={io={open=function()
    return {read=function() return 'enabled' end,close=function() end}
end}}}
local requested_api=Display.install(mod,presentation,tracking)
assert(requested_api.enabled,'Explicit launch request did not enable preview')
local ready_player=Managers.player
local premature_queries=0
Managers.player={local_player_safe=function()
    premature_queries=premature_queries+1
    return nil -- Stock safe lookup while the connection is uninitialized.
end,local_player=function() error('Network.peer_id before initialization') end}
presentation.mode=0; requested_api.update()
assert(premature_queries==0,'Loading preview queried the player manager')
presentation.mode=1; requested_api.update()
assert(premature_queries==1 and created==0,'Startup preview did not wait for a player')
Managers.player=ready_player; requested_api.update()
assert(visible and requested_api.last_preview,'Startup wait latched a permanent preview failure')
requested_api.destroy()
created,destroyed,context_reads=0,0,0
Mods=nil
-- Restore callbacks to the default-off instance for the remaining fixture.
api=Display.install(mod,presentation,tracking)
mod.toggle_melee_preview(); assert(api.enabled,'Keyboard/menu toggle did not enable')
mod.toggle_melee_preview(); assert(not api.enabled,'Keyboard/menu toggle did not disable')
commands.dtvr_melee_preview_on(); api.update()
assert(visible and created==1 and context_reads==1)
blocked=true; api.update(); assert(not visible and context_reads==1)
blocked=false; tracking.right_aim_usable=false; api.update(); assert(not visible and context_reads==1)
tracking.right_aim_usable=true; api.update(); assert(visible and created==1)
presentation.weapon_hand_roles={physical=function() return nil end}
local role_reads=context_reads
api.update(); assert(not visible and context_reads==role_reads,'Unknown hand role fell back to right')
presentation.weapon_hand_roles=nil
presentation.mode=2; api.update(); assert(not visible)
presentation.mode=1; context=nil; api.update(); assert(not visible)
context={paths={}}; extension._world={}; api.update()
assert(visible and created==2 and destroyed==1,'World change retained the old GUI')
commands.dtvr_melee_preview_off(); assert(not visible and destroyed==2)
commands.dtvr_melee_preview_on(); api.update(); assert(visible)
Managers.player=nil; api.update(); assert(not visible,'Player loss retained the preview')
Managers.player={local_player_safe=function() error('retiring manager') end}
api.update(); assert(destroyed==3)
local previous=context_reads
api.update(); assert(context_reads==previous,'Failed preview retried each frame')
assert(draws==0)
-- Exercise actual rectangle construction with vector/matrix engine fixtures.
-- This catches degenerate bases and arrow segment mistakes, not headset render.
local vector_meta={}
Vector3=setmetatable({}, {__call=function(_,x,y,z)
    return setmetatable({x=x,y=y,z=z},vector_meta)
end})
vector_meta.__add=function(a,b) return Vector3(a.x+b.x,a.y+b.y,a.z+b.z) end
vector_meta.__sub=function(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
vector_meta.__mul=function(a,n) return Vector3(a.x*n,a.y*n,a.z*n) end
vector_meta.__div=function(a,n) return Vector3(a.x/n,a.y/n,a.z/n) end
Vector3.length=function(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
Vector3.normalize=function(a) return a/Vector3.length(a) end
Vector3.cross=function(a,b) return Vector3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) end
Vector2=function(x,y) return {x=x,y=y} end
Color=function(a,r,g,b) return {a,r,g,b} end
for _,axis in ipairs({'right','up','forward','translation'}) do
    Matrix4x4['set_'..axis]=function(tm,value) tm[axis]=value end
end
local rectangles={}
Gui.rect_3d=function(_,tm,offset,layer,size,color)
    draws=draws+1
    assert(size.x>0 and size.y==.008 and offset.y==-.004 and layer==1)
    for _,axis in ipairs({'right','up','forward'}) do assert(math.abs(Vector3.length(tm[axis])-1)<1e-12) end
    local normal=Vector3.cross(tm.right,tm.forward)
    assert(Vector3.length(normal-tm.up)<1e-12,'Nonorthogonal world GUI basis')
    assert(color[1]==150)
    rectangles[#rectangles+1]={tm=tm,length=size.x}
end
Managers.player={local_player_safe=function() return {player_unit=unit} end}
extension._first_person_component.position=Vector3(0,0,0)
context={action_name='first_light',paths={{{tip={x=0,y=2,z=0}},{tip={x=1,y=2,z=0}},{tip={x=2,y=2,z=0}}}}}
commands.dtvr_melee_preview_on(); api.update()
assert(visible and draws==4,'Path and two arrow wings did not draw')
assert(rectangles[1].length==1 and rectangles[2].length==1)
assert(rectangles[3].tm.translation.x==2 and rectangles[4].tm.translation.x==2)
assert(rectangles[3].tm.right.x<0 and rectangles[4].tm.right.x<0,'Arrow wings face ahead of travel')
logs=nil
local action={_player_unit=unit,_weapon=extension._weapons.primary,_is_server=true}
start_hook(action,{name='first_light'},1.2)
assert(logs and logs[2]=='first_light' and logs[3]=='first_light' and logs[4]=='true')
assert(not api.last_preview,'Preview/action comparison repeated across combo swings')
logs=nil; start_hook(action,{name='first_light'},1.3); assert(not logs)
api.update(); logs=nil
start_hook(action,{name='heavy'},1.2); assert(logs[4]=='false','Different selected attack was reported as matching')
api.update(); logs=nil
start_hook(action,{name='first_light'},2.1); assert(not logs,'Expired prediction was compared')
local prior_draws=draws
blocked=true; api.update(); assert(not visible and draws==prior_draws and not api.last_preview)
print('melee_preview_display=pass opt_in UI tracking action_context world_change disable player_loss failure_latch')
