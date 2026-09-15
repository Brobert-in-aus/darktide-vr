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
    keyboard_mouse_aim_rotation=function() end,
    controller_aim_target=function() return {},hand end,
    keyboard_mouse_hands=function() return false end,
    update_body_ik_presentation_gate=function() end,is_first_person_body_mode=function() return true end,
    refresh_body_anchor_from_avatar=function(owner) assert(owner==unit); anchor_refreshes=(anchor_refreshes or 0)+1 end,
    body_proxy={rigid_hands_active=function() return true end,
        follow_gameplay_hands=function(_,rotation,offset,pivot) observed=rotation; observed_offset=offset; observed_pivot=pivot; return true,{},{} end},
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
assert(observed_offset==nil and observed_pivot==nil,'controller melee hands were moved by the keyboard and mouse placement')
assert(syncs==2,'Stock-input animated equipment did not follow the resolved hands')
assert(anchor_refreshes==1,'Stock melee animation path did not refresh the body anchor')
online=false; observed=nil
presentation.apply_body_ik(proxy,2,world,unit)
assert(observed==hand and syncs==4,'Local hand-aim animation changed')
-- Keyboard and mouse without a tracked controller: the hands follow the stock
-- animation all the time, turned onto the mouse aim, with the equipment moved
-- to them, and the tracked arms never run.
local mouse_aim={name='mouse_aim'}
presentation.keyboard_mouse_hands=function() return true end
presentation.keyboard_mouse_aim_rotation=function() return mouse_aim end
local hand_offset={name='hand_offset'}
presentation.keyboard_mouse_hand_offset=function() return hand_offset end
local hand_pivot={name='camera_anchor'}
presentation.keyboard_mouse_hand_pivot=function(owner) assert(owner==unit); return hand_pivot end
presentation.apply_tracked_arms=function() error('tracked arms ran without a tracked controller') end
state.stock_melee_animation_active=false; observed=nil
presentation.apply_body_ik(proxy,3,world,unit)
assert(observed==mouse_aim and syncs==6 and state.body_ik_presentation_block_reason=='keyboard_mouse',
    'keyboard and mouse hands did not follow the animation onto the mouse aim')
assert(observed_offset==hand_offset,'keyboard and mouse hands stayed beside the head')
assert(observed_pivot==hand_pivot,'keyboard and mouse hands were not hung from the camera anchor')
state.stock_melee_animation_active=true; observed=nil
presentation.apply_body_ik(proxy,4,world,unit)
assert(observed==mouse_aim and syncs==8,'an attack left the mouse aim')
-- A tracked controller in keyboard and mouse play keeps the tracked arms.
local tracked=0
presentation.keyboard_mouse_hands=function() return false end
presentation.apply_tracked_arms=function() tracked=tracked+1 end
state.stock_melee_animation_active=false
presentation.apply_body_ik(proxy,5,world,unit)
assert(tracked==1 and syncs==8)
presentation.keyboard_mouse_aim_rotation=function() end
state.stock_melee_animation_active=true
presentation.controllers_disabled=function() return false end
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
-- The real gates: controllers are withheld while disabled or during the
-- keyboard and mouse cooldown, and the hands animate unless a controller is
-- tracked and allowed.
do
    local gate_first=assert(source:find('function presentation.controllers_suppressed()',1,true))
    local hands=assert(source:find('function presentation.keyboard_mouse_hands()',gate_first,true))
    local gate_last=assert(source:find('\nfunction presentation.',hands+1,true))
    local g={}; local obs={}
    local flags={enabled=false,disabled=false,recent=false,mode=1}
    g.keyboard_mouse_enabled=function() return flags.enabled end
    g.controllers_disabled=function() return flags.disabled end
    local sampled
    g.keyboard_mouse={recent_input=function() return flags.recent end,controller_cooldown=3,
        sample_devices=function(devices,t,sampling) sampled={devices,t,sampling}; return false end}
    local input_hook
    local gate_mod={hook_safe=function(_,class,name,callback)
        assert(class=='InputManager' and name=='_update_devices'); input_hook=callback end,info=function() end}
    setfenv(assert(loadstring(source:sub(gate_first,gate_last-1))),
        setmetatable({presentation=g,controller_observation=obs,mod=gate_mod},{__index=_G}))()
    g.mode=1
    local manager={_all_input_devices={'devices'}}
    input_hook(manager,0.01,5)
    assert(sampled==nil,'controller play sampled keyboard and mouse use')
    assert(not g.controllers_suppressed() and not g.keyboard_mouse_hands(),'controller play used animated hands')
    flags.enabled=true
    input_hook(manager,0.01,6)
    assert(sampled[1]==manager._all_input_devices and sampled[2]==6 and sampled[3]==true)
    g.mode=5; input_hook(manager,0.01,7)
    assert(sampled[3]==false,'menu mouse events counted as gameplay use')
    assert(g.keyboard_mouse_hands(),'untracked controllers froze keyboard and mouse hands')
    obs.right_grip_tracking_live=true
    assert(not g.controllers_suppressed() and not g.keyboard_mouse_hands(),'an idle keyboard and mouse withheld the arms')
    flags.recent=true
    assert(g.controllers_suppressed() and g.keyboard_mouse_hands(),'mouse use left the tracked arms on')
    flags.recent=false; flags.disabled=true
    assert(g.controllers_suppressed() and g.keyboard_mouse_hands(),'disabled controllers still drove the arms')
    sampled=nil; input_hook(manager,0.01,8)
    assert(sampled==nil,'disabled controllers still ran the cooldown')
end
print('melee_simulation_visual=pass simulated_aim local_hand_aim equipment_sync')
