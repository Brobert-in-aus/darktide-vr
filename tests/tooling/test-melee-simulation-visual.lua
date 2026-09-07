-- Execute the actual stock-melee branch of body IK with the real aim module.
-- Engine skeleton transforms are sinks; this verifies which pose owns visuals.
require=function() return {} end
local aim=dofile(assert(arg[2]))
local unit,proxy,world={},{},{}
local simulated,hand={name='simulated'},{name='hand'}
local online=true
local first_person={_unit=unit,_is_local_unit=true,_first_person_component={rotation=simulated}}
Managers={player={local_player=function() return {player_unit=unit} end}}
Unit={alive=function() return true end}
ScriptUnit={has_extension=function(owner,name)
    assert(owner==unit and name=='first_person_system'); return first_person
end}
local observed,syncs=nil,0
local presentation={online_rules={simulation_aim_active=function(owner) return online and owner==unit end},
    is_controller_aim_mode=function() return not online end,
    controller_aim_target=function() return {},hand end,
    update_body_ik_presentation_gate=function() end,is_first_person_body_mode=function() return true end,
    body_proxy={rigid_hands_active=function() return true end,
        follow_gameplay_hands=function(_,rotation) observed=rotation; return true,{},{} end},
    sync_equipment_hand_to_proxy=function(owner) assert(owner==unit); syncs=syncs+1 end}
local state={authoring_enabled=true,body_ik_presentation_enabled=true,
    body_ik_presentation_update_frame=0,stock_melee_animation_active=true}
local mod={hook=function() end,hook_safe=function() end,command=function() end,info=function() end}
presentation.controller_aim=aim.install(mod,presentation,state)
World={update_unit_and_children=function() end}
local file=assert(io.open(arg[1],'r')); local source=file:read('*a'); file:close()
local first=assert(source:find('function presentation.apply_body_ik(',1,true))
local last=assert(source:find('\nfunction presentation.update_stock_melee_animation_owner(',first,true))
local env=setmetatable({presentation=presentation,controller_observation=state,mod=mod,
    active_game_mode_name=function() return 'shooting_range' end},{__index=_G})
setfenv(assert(loadstring(source:sub(first,last-1))),env)()
presentation.apply_body_ik(proxy,1,world,unit)
assert(observed==simulated,'Stock-input animated hands did not use simulated melee aim')
assert(syncs==2,'Stock-input animated equipment did not follow the resolved hands')
online=false; observed=nil
presentation.apply_body_ik(proxy,2,world,unit)
assert(observed==hand and syncs==4,'Local hand-aim animation changed')
online=true
first_person._unit={}
assert(not aim.melee_visual_rotation(unit),'Foreign first-person owner supplied simulated aim')
first_person._unit=unit; first_person._is_local_unit=false
assert(not aim.melee_visual_rotation(unit),'Nonlocal first-person extension supplied aim')
first_person._is_local_unit=true; first_person._first_person_component=nil
assert(not aim.melee_visual_rotation(unit),'Missing simulation pose fell back to current tracking')
ScriptUnit.has_extension=function() error('retiring extension') end
assert(not aim.melee_visual_rotation(unit),'Retiring extension leaked an exception/raw fallback')
-- Exercise the actual aim-constraint hook too, keeping non-melee behavior.
first_person._first_person_component={rotation=simulated}
ScriptUnit.has_extension=function() return first_person end
local hook
mod.hook_safe=function(_,_,_,callback) hook=callback end
first=assert(source:find('mod:hook_safe(\n    require("scripts/extension_systems/aim/player_unit_aim_extension"),',1,true))
last=assert(source:find('\nmod:hook_safe(',first+1,true))
setfenv(assert(loadstring(source:sub(first,last-1))),env)()
local mt={}
local function v(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
mt.__add=function(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
mt.__mul=function(a,b) if type(a)=='number' then a,b=b,a end; return v(a.x*b,a.y*b,a.z*b) end
Vector3={up=function() return v(0,0,1) end}
Unit.local_position=function() return v(0,0,0) end
Unit.animation_set_constraint_target=function() end
local head,used_rotation={name='head'}
Quaternion={axis_angle=function() return head end,
    forward=function(rotation) used_rotation=rotation; return v(1,0,0) end}
state.body_head_yaw=.1
local aim_extension={_aim_constraint_variable=1,_aim_contraint_distance=2,
    _first_person_extension={extrapolated_character_height=function() return 1 end}}
hook(aim_extension,unit)
assert(used_rotation==simulated,'Melee constraint ignored simulated aim')
online=false; hook(aim_extension,unit); assert(used_rotation==hand)
online=true; state.stock_melee_animation_active=false
hook(aim_extension,unit); assert(used_rotation==head,'Non-melee constraint behavior changed')
print('melee_simulation_visual=pass simulated_aim local_hand_aim equipment_sync')
