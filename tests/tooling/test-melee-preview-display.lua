local Display=dofile(assert(arg[1]))
local commands={}
local visible,created,destroyed,draws=false,0,0,0
local unit={}
local blocked=false
local extension={_world={},_first_person_component={position={x=0,y=0,z=0}}}
local context={paths={}} -- Geometry/pose tests live in test-melee-preview.lua.
local context_reads=0
local mod={io_dofile=function() return {context=function()
    context_reads=context_reads+1; return context
end} end, command=function(_,name,_,fn) commands[name]=fn end,
    info=function() end, warning=function() end}
Managers={player={local_player=function() return {player_unit=unit} end},ui={},
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
commands.dtvr_melee_preview_on(); api.update()
assert(visible and created==1 and context_reads==1)
blocked=true; api.update(); assert(not visible and context_reads==1)
blocked=false; tracking.right_aim_usable=false; api.update(); assert(not visible and context_reads==1)
tracking.right_aim_usable=true; api.update(); assert(visible and created==1)
presentation.mode=2; api.update(); assert(not visible)
presentation.mode=1; context=nil; api.update(); assert(not visible)
context={paths={}}; extension._world={}; api.update()
assert(visible and created==2 and destroyed==1,'World change retained the old GUI')
commands.dtvr_melee_preview_off(); assert(not visible and destroyed==2)
commands.dtvr_melee_preview_on(); api.update(); assert(visible)
Managers.player=nil; api.update(); assert(not visible,'Player loss retained the preview')
Managers.player={local_player=function() error('retiring manager') end}
api.update(); assert(destroyed==3)
local previous=context_reads
api.update(); assert(context_reads==previous,'Failed preview retried each frame')
assert(draws==0)
print('melee_preview_display=pass opt_in UI tracking action_context world_change disable player_loss failure_latch')
