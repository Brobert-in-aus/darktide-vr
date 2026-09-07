local Preview=dofile(assert(arg[1]))
Vector3={x=function(v) return v.x end,y=function(v) return v.y end,z=function(v) return v.z end}
local light={kind='sweep'}
local actions={windup={kind='windup',allowed_chain_actions={light_attack={action_name='light'}}},light=light}
assert(Preview.first_light(actions,'windup')=='light')
assert(not Preview.first_light(actions,'light'))
actions.windup.allowed_chain_actions.light_attack.running_action_state_requirement='charged'
assert(not Preview.first_light(actions,'windup'))
actions.windup.allowed_chain_actions.light_attack.running_action_state_requirement=nil
local reused={}
local instance={_action_settings=light,_weapon_template={},_sweep_splines={{_num_frames=3,
    position_and_rotation=function(_,t,origin,rotation)
        reused.x=origin.x+rotation*t; reused.y=origin.y; reused.z=origin.z
        return reused,rotation
    end}},
    _weapon_half_extents=function() return {x=.1,y=.2,z=.5} end,
    _modify_sweep_position=function(_,p,rotation,extents)
        return {x=p.x,y=p.y+extents.z*rotation,z=p.z}
    end}
local origin={x=10,y=20,z=30}
local result=assert(Preview.sample(instance,origin,1))
local path=result.paths[1]
assert(#path==3 and path[1].base.x==10 and path[2].base.x==10.5 and path[3].base.x==11)
assert(path[1].center.y==20.5 and path[1].tip.y==21)
assert(not result.damage and not result.obstruction_tested)
local rotated=assert(Preview.sample(instance,origin,-1))
assert(rotated.paths[1][3].base.x==9 and rotated.paths[1][1].tip.y==19)
assert(path[1].base.x==10 and origin.x==10,'Temporary reuse mutated earlier preview/root')
instance._sweep_splines[1]._num_frames=257
assert(not Preview.sample(instance,origin,1))
instance._sweep_splines[1]._num_frames=3
origin.x=0/0
assert(not Preview.sample(instance,origin,1))
origin.x=10
instance._first_person_component={position=origin,rotation=-1}
local running,valid,simulated,hand_reads=nil,true,true,0
local extension={_unit={},_inventory_component={wielded_slot='primary'},
    _weapons={primary={weapon_template={actions=actions},actions={light=instance}}},
    condition_func_params=function() return {} end,
    _action_handler={running_action_name=function() return running end,
        _valid_action_from_action_input=function(_,_,input) assert(input=='start_attack'); return 'windup' end,
        _validate_action=function() return valid end}}
local presentation={online_rules={simulation_aim_active=function() return simulated end},
    controller_aim={target=function() hand_reads=hand_reads+1; return {},1 end}}
local context=assert(Preview.context(extension,presentation,1))
assert(context.paths[1][3].base.x==9 and hand_reads==0,'Stock-input preview used raw hand rotation')
simulated=false
context=assert(Preview.context(extension,presentation,1))
assert(context.paths[1][3].base.x==11 and hand_reads==1)
running='block'; assert(not Preview.context(extension,presentation,1))
running=nil; valid=false; assert(not Preview.context(extension,presentation,1))
print('melee_preview=pass route authored_frames root orientation extent_offset copied_samples invalid_data')
