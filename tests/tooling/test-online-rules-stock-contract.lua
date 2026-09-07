-- Optional source integration: execute stock first-person and walking methods
-- after the real VR cache adapter. Engine math is isolated; no live XR/network.
local vector_meta={}
Vector3=setmetatable({}, {__call=function(_,x,y,z) return setmetatable({x,y,z},vector_meta) end})
vector_meta.__add=function(a,b) return Vector3(a[1]+b[1],a[2]+b[2],a[3]+b[3]) end
vector_meta.__unm=function(a) return Vector3(-a[1],-a[2],-a[3]) end
vector_meta.__mul=function(a,b)
    if type(a)=='number' then a,b=b,a end
    return Vector3(a[1]*b,a[2]*b,a[3]*b)
end
Vector3.x=function(v) return v[1] end; Vector3.y=function(v) return v[2] end
Vector3.to_elements=function(v) return unpack(v) end
Vector3.dot=function(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
Vector3.length_squared=function(v) return Vector3.dot(v,v) end
Vector3.length=function(v) return math.sqrt(Vector3.length_squared(v)) end
Vector3.normalize=function(v) local n=Vector3.length(v); return n>0 and v*(1/n) or Vector3(0,0,0) end
Vector3.flat=function(v) return Vector3(v[1],v[2],0) end
Vector3.up=function() return Vector3(0,0,1) end
Quaternion={from_yaw_pitch_roll=function(y,p,r) return {yaw=y,pitch=p,roll=r} end,
    yaw=function(q) return q.yaw end,pitch=function(q) return q.pitch end,
    inverse=function(q) return {yaw=-q.yaw,pitch=0,roll=0} end,
    forward=function(q) return Vector3(-math.sin(q.yaw),math.cos(q.yaw),0) end,
    look=function(v) return {yaw=math.atan2(-v[1],v[2]),pitch=0,roll=0} end,
    rotate=function(q,v) return Vector3(math.cos(q.yaw)*v[1]-math.sin(q.yaw)*v[2],
        math.sin(q.yaw)*v[1]+math.cos(q.yaw)*v[2],v[3]) end}
math.lerp=function(a,b,t) return a+(b-a)*t end
local root=arg[3]..'/scripts/'
local function source(path)
    local f=assert(io.open(root..path..'.lua','r')); local s=f:read('*all'); f:close(); return s
end
local fp_source=source('extension_systems/first_person/player_unit_first_person_extension')
local function extract(first,last)
    local a=assert(fp_source:find(first,1,true)); local b=assert(fp_source:find(last,a,true))
    return fp_source:sub(a,b-1)
end
-- Stock height interpolation is included; this fixture uses settled height.
local height_source=extract('local function _calculate_base_player_height(',
    '\nlocal half_pi ='):gsub('local function','function',1)
assert(loadstring(height_source))()
PlayerUnitFirstPersonExtension={}
assert(loadstring(extract('PlayerUnitFirstPersonExtension.fixed_update =',
    '\nPlayerUnitFirstPersonExtension.server_correction_occurred =')))()
Recoil={first_person_offset=function() return .02,.01 end}
GameSession={set_game_object_field=function() end}
local walking=assert(loadstring(source('extension_systems/character_state_machine/character_states/utilities/accelerated_local_space_movement')))()
local player={player_unit='local'}
Managers={state={game_session={is_server=function() return true end}},
    player={local_player=function() return player end},ui={using_input=function() return false end,
        communication_wheel_wants_camera_control=function() return false end,
        emote_wheel_wants_camera_control=function() return false end}}
Unit={alive=function() return true end}
ScriptUnit={has_extension=function() return {current_state_name=function() return 'walking' end} end}
Network={pack_unpack=function(_,value) return value end} -- Engine quantization not covered here.
package.preload['scripts/settings/player_character/player_orientation_settings']=function()
    return {default={min_pitch=-math.pi*.45,max_pitch=math.pi*.45}}
end
local aim=Quaternion.from_yaw_pitch_roll(math.pi/2,.3,0)
local view=Quaternion.from_yaw_pitch_roll(0,.1,0)
local presentation={mode=1,gameplay_context=dofile(arg[2]),
    flat_movement_rotation=function(y) return Quaternion.from_yaw_pitch_roll(y,0,0) end,
    controller_aim_target=function() return Vector3(99,88,77),aim end}
HumanGameplay={}
local gameplay_source=source('managers/player/player_game_states/human_gameplay')
local selection_start=assert(gameplay_source:find('HumanGameplay._player_orientation_class =',1,true))
local selection_end=assert(gameplay_source:find('\nHumanGameplay._cb_player_activate_emote =',selection_start,true))
assert(loadstring(gameplay_source:sub(selection_start,selection_end-1)))()
local orientation_class=HumanGameplay
ALIVE={['local']=true}
PlayerUnitStatus={is_ledge_hanging=function(component) return component.hanging end}
SweepStickyness={is_sticking_to_unit=function(component) return component.sticking end}
local rules=dofile(arg[1]).install({get=function() return true end,info=function() end,warning=function() end,
    hook_require=function(_,path,callback) callback(orientation_class) end,
    hook=function(_,class,name,callback)
        local original=class[name]; class[name]=function(...) return callback(original,...) end
    end},
    presentation,{authoring_enabled=true,gameplay_input_active=true},function() return 'shooting_range' end)
local h={_player=player,_input_cache={{0},{0},{1},{0},{0},{0},{0}},
    _action_lookup={move_right=1,move_left=2,move_forward=3,move_backward=4},
    _pack_unpack_action_to_network_type_index={move_right=1,move_left=1,move_forward=1,move_backward=1},
    _yaw_index=5,_pitch_index=6,_roll_index=7,_buffer_index=function() return 1 end}
player.input_handler=h
local gameplay={_player=player,_player_unit='local',_default_player_orientation={},
    _weapon_lock_view_component={state='none'},_force_look_rotation_component={},
    _character_state_component={},_action_sweep_component={},
    _forced_player_orientation={},_ledge_hanging_player_orientation={},
    _weapon_lock_view_player_orientation={},_weapon_force_view_player_orientation={},
    _smooth_force_view_player_orientation={},_communication_wheel_orientation={},_dead_player_orientation={}}
assert(orientation_class._player_orientation_class(gameplay)==gameplay._default_player_orientation)
rules.capture(h,1); assert(rules.frames==1)
local input={get_orientation=function() return h._input_cache[5][1],h._input_cache[6][1],h._input_cache[7][1] end,
    get=function(_,name) assert(name=='move'); return Vector3(h._input_cache[1][1]-h._input_cache[2][1],
        h._input_cache[3][1]-h._input_cache[4][1],0) end}
local component={wanted_height=1.7,height_change_start_time=0,height_change_duration=0,rotation=view}
local fp={_first_person_component=component,_locomotion_component={position=Vector3(10,20,0)},
    _inair_state_component={on_ground=true},_input_extension=input,_is_server=true,
    _weapon_extension={recoil_template=function() end,running_action_settings=function() return {} end},
    _peeking_component={is_peeking=false},_update_first_person_forced_rotation=function() end}
PlayerUnitFirstPersonExtension.fixed_update(fp,'local',.02,10,1)
assert(component.position[1]==10 and component.position[2]==20 and component.position[3]==1.7,
    'Stock body/height firing origin was replaced by hand origin')
assert(math.abs(component.rotation.yaw-(aim.yaw+.01))<1e-12)
assert(math.abs(component.rotation.pitch-(aim.pitch+.02))<1e-12)
assert(component.previous_rotation==view and view.yaw==0 and view.pitch==.1)
-- Stock local rendering and camera root use the original orientation owner,
-- independently of the hand-directed fixed simulation component.
assert(loadstring(extract('PlayerUnitFirstPersonExtension._update_rotation =',
    '\nPlayerUnitFirstPersonExtension.spectated_aim_rotation =')))()
local rendered_rotation
Unit.set_local_rotation=function(unit,node,rotation)
    assert(unit=='first_person' and node==1); rendered_rotation=rotation
end
fp._is_local_unit=true
fp._first_person_unit='first_person'
fp._player={get_orientation=function() return view end}
PlayerUnitFirstPersonExtension._update_rotation(fp,'local',.02,10)
assert(math.abs(rendered_rotation.yaw-.01)<1e-12 and math.abs(rendered_rotation.pitch-.12)<1e-12)
assert(math.abs(component.rotation.yaw-(math.pi/2+.01))<1e-12)
CameraHandler={}; CameraModes={observer='observer'}
local camera_source=source('managers/player/player_game_states/camera_handler')
local camera_first=assert(camera_source:find('CameraHandler._camera_root_orientation =',1,true))
local camera_last=assert(camera_source:find('\nCameraHandler._switch_follow_target =',camera_first,true))
assert(loadstring(camera_source:sub(camera_first,camera_last-1)))()
local camera_yaw,camera_pitch=CameraHandler._camera_root_orientation({_mode='first_person'},
    {orientation=function() return view.yaw,view.pitch,view.roll end,
     orientation_offset=function() return .01,.02,0 end})
assert(camera_yaw==rendered_rotation.yaw and camera_pitch==rendered_rotation.pitch)
-- Run real shot preparation against the stock pose produced above. Tag the
-- engine-dependent weapon operations to verify ownership/order, not their math.
local shooting_source=source('extension_systems/weapon/actions/action_shoot')
local shot_start=assert(shooting_source:find('ActionShoot._prepare_shooting =',1,true))
local shot_end=assert(shooting_source:find('\nActionShoot._spend_ammunition =',shot_start,true))
ActionShoot={}
assert(loadstring(shooting_source:sub(shot_start,shot_end-1)))()
local operations,gamepad={},false
local function stage(name,rotation)
    operations[#operations+1]=name
    return {stage=name,previous=rotation}
end
Recoil.apply_weapon_recoil_rotation=function(_,_,_,_,_,rotation) return stage('recoil',rotation) end
Recoil.add_recoil=function() operations[#operations+1]='add_recoil' end
Sway={apply_sway_rotation=function(_,_,rotation) return stage('sway',rotation) end,
    add_immediate_sway=function() operations[#operations+1]='add_sway' end}
Spread={add_immediate_spread_from_shooting=function() operations[#operations+1]='add_spread' end}
SmartTargeting={smart_targeting_template=function() return 'stock_targeting' end}
MultiFireModes={simultaneous='simultaneous'}
DevParameters={disable_aim_assist=false}
Managers.input={is_using_gamepad=function() return gamepad end}
local shot={_first_person_component=component,
    _action_component={current_fire_config=1,num_shots_fired=0},
    _shooting_status_component={num_shots=0},_multi_fire_mode='simultaneous',
    _base_fire_configurations={{},{}},_is_server=true,
    _weapon_extension={recoil_template=function() return 'recoil' end,
        sway_template=function() return 'sway' end,spread_template=function() return 'spread' end},
    _weapon_spread_extension={randomized_spread=function(_,rotation) return stage('spread',rotation) end},
    _smart_targeting_extension={assisted_hitscan_trajectory=function(_,_,_,rotation) return stage('assist',rotation) end},
    _fire_configurations=function() return {{}} end,_prepare_fire_config=function() return .6 end,
    _set_charge_animation_variable=function() end,_update_sound_reflection=function() end,
    _play_muzzle_flash_vfx=function() end}
ActionShoot._prepare_shooting(shot,.02,1)
local shot_component=shot._action_component
local shot_rotation=shot_component.shooting_rotation
assert(shot_component.shooting_position==component.position and component.position[1]==10,
    'Shot origin must come from simulated body pose, not tracked hand origin')
assert(shot_component.shooting_charge_level==.6)
assert(shot_rotation.stage=='spread' and shot_rotation.previous.stage=='sway' and
    shot_rotation.previous.previous.stage=='recoil' and
    shot_rotation.previous.previous.previous==component.rotation)
assert(table.concat(operations,',')=='recoil,sway,spread,add_sway,add_spread,add_recoil')
-- A second simultaneous bullet retains the prepared group sample; it must not
-- reread a later live/controller pose or add recoil/spread a second time.
local original_pose=component.rotation
component.rotation={later_pose=true}
ActionShoot._prepare_shooting(shot,.02,1.02)
assert(shot_component.shooting_rotation==shot_rotation and #operations==6)
assert(shot._shooting_status_component.num_shots==1 and shot_component.num_shots_fired==2)
component.rotation=original_pose
gamepad=true; operations={}
ActionShoot._prepare_shooting(shot,.02,1.04)
assert(table.concat(operations,',')=='recoil,sway,assist,spread,add_sway,add_spread,add_recoil')
assert(shot._shooting_status_component.num_shots==2)
gamepad=false
-- Stock sweeps use successive simulation references and their authored damage
-- window. No visible weapon/hand node is sampled by these orchestration methods.
do
    local saved_aim,saved_cache=aim,h._input_cache
    local saved_world_position,saved_world_rotation=Unit.world_position,Unit.world_rotation
    local sweep_source=source('extension_systems/weapon/actions/action_sweep')
    ActionSweep={}
    local function method(name,next_name)
        local first=assert(sweep_source:find('ActionSweep.'..name..' =',1,true))
        local last=assert(sweep_source:find('\nActionSweep.'..next_name..' =',first,true))
        assert(loadstring(sweep_source:sub(first,last-1)))()
    end
    method('_reset_sweep_component','_calculate_max_hit_mass')
    method('_update_sweep','_any_sweep_aborted')
    method('_any_sweep_aborted','_abort_sweep') -- Includes all/individual masks.
    method('_is_within_damage_window','_exit_damage_window')
    bit=require('bit')
    Vector3.zero=function() return Vector3(0,0,0) end
    Log={debug=function() end}
    local samples,overlaps,exits,procs,frame={},{},0,0,100
    local sweep=setmetatable({_first_person_component=component,
        _weapon_action_component={time_scale=1},_action_sweep_component={},
        _all_sweeps_aborted_mask=3,_num_hit_enemies=0,
        _sweep_splines={},_is_currently_sticky=function() return false end,
        _exit_damage_window=function() exits=exits+1 end,
        _handle_exit_procs=function() procs=procs+1 end}, {__index=ActionSweep})
    for index=1,2 do
        sweep._sweep_splines[index]={position_and_rotation=function(_,fraction,position,rotation)
            samples[#samples+1]={index=index,fraction=fraction,position=position,rotation=rotation}
            return position,rotation
        end}
    end
    sweep._do_overlap=function(_,t,p0,r0,p1,r1,final,settings,index)
        overlaps[#overlaps+1]={p0=p0,r0=r0,p1=p1,r1=r1,final=final,index=index}
    end
    Unit.world_position=function() error('sweep read rendered hand position') end
    Unit.world_rotation=function() error('sweep read rendered hand rotation') end
    sweep:_reset_sweep_component()
    local settings={damage_window_start=.2,damage_window_end=.5}
    local previous_position,previous_rotation=component.position,component.rotation
    local function tick(time,dt,yaw)
        aim=Quaternion.from_yaw_pitch_roll(yaw,.2,0)
        h._input_cache={{0},{0},{0},{0},{view.yaw},{view.pitch},{0}}
        frame=frame+1
        rules.capture(h,frame)
        fp._locomotion_component.position=Vector3(10+time,20,0)
        PlayerUnitFirstPersonExtension.fixed_update(fp,'local',dt,10+time,1)
        local before=#overlaps
        sweep:_update_sweep(dt,10+time,time,settings)
        for i=before+1,#overlaps do
            local overlap=overlaps[i]
            assert(overlap.p0==previous_position and overlap.r0==previous_rotation)
            assert(overlap.p1==component.position and overlap.r1==component.rotation)
            assert(overlap.p1[3]==1.7 and math.abs(overlap.r1.yaw-(yaw+.01))<1e-12)
        end
        previous_position,previous_rotation=component.position,component.rotation
        assert(sweep._action_sweep_component.reference_position==component.position)
        return #overlaps-before
    end
    assert(tick(.1,.1,.4)==0 and #samples==0)
    assert(tick(.2,.1,.5)==2 and samples[1].fraction==0 and samples[2].fraction==0)
    assert(tick(.35,.15,.6)==2 and math.abs(samples[6].fraction-.5)<1e-12)
    assert(tick(.5,.15,.7)==2 and samples[10].fraction==1)
    assert(tick(.6,.1,.8)==2 and overlaps[#overlaps].final and samples[#samples].fraction==1)
    assert(exits==1 and procs==1 and sweep._action_sweep_component.sweep_state=='after_damage_window')
    assert(tick(.7,.1,.9)==0 and exits==1)
    -- An aborted spline stays excluded without suppressing the remaining one.
    sweep:_reset_sweep_component()
    sweep._action_sweep_component.sweep_aborted_bit_array=1
    assert(tick(.3,.01,1)==1 and overlaps[#overlaps].index==2)
    sweep._action_sweep_component.sweep_aborted_bit_array=3
    assert(tick(.31,.01,1.1)==0)
    -- Stock time scale/offset policy and no-window fallback are retained.
    local inside,fraction,before,total=sweep:_is_within_damage_window(.125,
        {damage_window_start=.2,damage_window_end=.5,action_time_offset=.1},2)
    assert(inside and math.abs(fraction-.5)<1e-12 and not before and math.abs(total-.15)<1e-12)
    assert(not sweep:_is_within_damage_window(1,{},1))
    aim,h._input_cache=saved_aim,saved_cache
    Unit.world_position,Unit.world_rotation=saved_world_position,saved_world_rotation
end
-- Flame target acquisition is separate from ordinary shot preparation. Run
-- its real ray loop, obstruction and ownership policy with supplied ray hits.
do
    local saved_aim,saved_cache=aim,h._input_cache
    Vector3.distance=function(a,b)
        return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2+(a[3]-b[3])^2)
    end
    for _,burst in ipairs({false,true}) do
        local class_name=burst and 'ActionFlamerGasBurst' or 'ActionFlamerGas'
        local flame_source=source('extension_systems/weapon/actions/'..
            (burst and 'action_flamer_gas_burst' or 'action_flamer_gas'))
        local class={}; local hits,rays,spread_calls,hit_counts={},0,0,{}
        local friendly=false
        local positions={['local']=Vector3(10,20,0),enemy=Vector3(10,24,0),
            ally=Vector3(10,22,0),buff_only=Vector3(10,23,0)}
        local side={is_ally=function(_,_,unit) return unit=='ally' end}
        local env=setmetatable({[class_name]=class,POSITION_LOOKUP=positions,
            INDEX_POSITION=1,INDEX_NORMAL=3,INDEX_ACTOR=4,
            Managers={state={extension={system=function(_,name) assert(name=='side_system'); return side end}}},
            Actor={unit=function(actor) return actor.unit end},
            HitZone={get_name=function(_,actor) return actor.zone end,hit_zone_names={afro='afro'}},
            FriendlyFire={is_enabled=function() return friendly end},
            ScriptUnit={has_extension=function(unit,name)
                if name=='shield_system' then
                    if unit=='shield' then return {can_block_from_position=function(_,p)
                        assert(p==positions['local']); return true end} end
                elseif unit~='wall' and unit~='shield' and
                        not (unit=='buff_only' and name=='health_system') then return {} end
            end},
            math=setmetatable({random_seed=function() return 123 end},{__index=math}),
            table=setmetatable({clear=function(t) for k in pairs(t) do t[k]=nil end end},{__index=table}),
            Unit={world_position=function() error('flame read rendered weapon origin') end,
                world_rotation=function() error('flame read rendered weapon direction') end},
        },{__index=_G})
        local function method(name,next_name)
            local a=assert(flame_source:find(class_name..'.'..name..' =',1,true))
            local b=assert(flame_source:find('\n'..class_name..'.'..next_name..' =',a,true))
            setfenv(assert(loadstring(flame_source:sub(a,b-1))),env)()
        end
        method('_is_unit_blocking',burst and '_damage_and_burn_targets' or '_hit_target')
        local function check_spread(rotation)
            assert(rotation==component.rotation); spread_calls=spread_calls+1
            return rotation -- Distribution is an engine-dependent substitute.
        end
        env.Spread={uniform_circle=check_spread,target_style_spread=function(rotation,i,count,rings,bullseye)
            assert(i==rays+1 and count==8 and rings==2 and bullseye)
            return check_spread(rotation)
        end}
        env.HitScan={raycast=function(world,position,direction,range,unused,filter,rewind)
            rays=rays+1
            assert(world=='physics' and position==component.position and range==12 and unused==nil)
            assert(filter=='filter_player_character_shooting_raycast' and rewind==37)
            assert(math.abs(direction[1]+math.sin(component.rotation.yaw))<1e-12 and
                math.abs(direction[2]-math.cos(component.rotation.yaw))<1e-12)
            return hits
        end}
        local function hit(unit,zone)
            return {Vector3(10,23,1),0,Vector3(0,-1,0),{unit=unit,zone=zone or 'torso'}}
        end
        for _,server in ipairs({false,true}) do
            aim=Quaternion.from_yaw_pitch_roll(server and 1.2 or -.8,.2,0)
            h._input_cache={{0},{0},{0},{0},{view.yaw},{view.pitch},{0}}
            rules.capture(h,200)
            PlayerUnitFirstPersonExtension.fixed_update(fp,'local',.02,20,1)
            local action=setmetatable({_is_server=server,_is_local_unit=not server,
                _player_unit='local',_player='player',_physics_world='physics',
                _first_person_component=component,_spread_angle=.2,_range=12,
                _action_module_position_finder_component={},_targets={},_target_actors={},_dot_targets={},
                _rewind_ms=function(_,is_local,player,position,direction,range)
                    assert(is_local==not server and player=='player' and position==component.position and range==12)
                    return 37
                end,_hit_target=function(_,unit) hit_counts[unit]=(hit_counts[unit] or 0)+1 end},
                {__index=class})
            rays,spread_calls,hit_counts=0,0,{}
            hits={hit('local'),hit('afro','afro'),hit('ally'),hit('enemy'),hit('enemy'),
                hit('buff_only'),hit('wall'),hit('behind')}
            action:_acquire_targets(20)
            assert(rays==(server and 8 or 1))
            assert(spread_calls==(burst and rays or rays-1))
            local finder=action._action_module_position_finder_component
            assert(finder.position_valid and finder.position==hits[7][1] and finder.normal==hits[7][3])
            assert(action._target_actors.enemy==(server and hits[4][4] or nil))
            assert((action._dot_targets.enemy~=nil)==server and
                (action._dot_targets.buff_only~=nil)==server)
            assert(action._target_actors.ally==nil and action._target_actors['local']==nil and
                action._target_actors.afro==nil and action._target_actors.behind==nil)
            if burst then
                assert(action._targets.enemy==(server and (20+4/12*.5) or nil))
            else assert(hit_counts.enemy==(server and 1 or nil)) end
            -- A shield ends the ray before any enemy; friendly fire remains a
            -- stock decision, and no-hit frames clear the central preview flag.
            rays,spread_calls,hit_counts=0,0,{}
            action._targets={}; action._target_actors={}; action._dot_targets={}
            hits={hit('shield'),hit('enemy')}; action:_acquire_targets(21)
            assert(finder.position==hits[1][1] and action._target_actors.enemy==nil and hit_counts.enemy==nil)
            rays,spread_calls=0,0; friendly=true
            hits={hit('ally')}; action:_acquire_targets(22)
            assert(action._target_actors.ally==(server and hits[1][4] or nil))
            assert(not finder.position_valid)
            rays,spread_calls=0,0; friendly=false; hits={}; action:_acquire_targets(23)
            assert(not finder.position_valid)
            -- Execute the real fixed-update authority branch with damage/burn
            -- sinks. No local prediction branch may apply those effects.
            local parent_updates,damage,burns=0,0,0
            class.super={fixed_update=function() parent_updates=parent_updates+1 end}
            method('fixed_update',burst and '_shoot' or '_is_unit_blocking')
            action._flamer_gas_template={}
            action._acquire_targets=function() end
            action._damage_targets=function() damage=damage+1 end
            action._burn_targets=function() burns=burns+1 end
            action._damage_and_burn_targets=function() damage=damage+1; burns=burns+1 end
            action:fixed_update(.02,24,1,200)
            assert(parent_updates==1 and damage==(server and 1 or 0) and burns==damage)
        end
    end
    aim,h._input_cache=saved_aim,saved_cache
end
-- Smart targeting selects a target before the attack module locks it. Its
-- stock resimulation guard must keep a later live aim sample out of replay.
do
    local saved_aim,saved_cache=aim,h._input_cache
    aim=Quaternion.from_yaw_pitch_roll(1.1,.2,0)
    h._input_cache={{0},{0},{0},{0},{view.yaw},{view.pitch},{0}}
    rules.capture(h,300)
    PlayerUnitFirstPersonExtension.fixed_update(fp,'local',.02,30,1)
    local selected='enemy_a'; local auto_aim,human=false,true
    local calls,stages={},{}
    local template={precision_target={max_range=8},precision_target_auto_aim={}}
    local targets={}; local data={is_resimulating=false}
    local env=setmetatable({PlayerUnitSmartTargetingExtension={},
        EMPTY_TABLE={},SMART_TAG_TARGETING_DELAY=.2,DEDICATED_SERVER=false,
        SmartTargeting={smart_targeting_template=function() return template end},
        HEALTH_ALIVE={enemy_a=true,enemy_b=true,edge=true},
        POSITION_LOOKUP={['local']=Vector3(0,0,0),enemy_a=Vector3(0,3,0),
            enemy_b=Vector3(0,4,0),edge=Vector3(0,8,0)},
        table=setmetatable({clear=function(t) for k in pairs(t) do t[k]=nil end end},{__index=table}),
        Quaternion=setmetatable({right=function(q) return Vector3(math.cos(q.yaw),math.sin(q.yaw),0) end,
            up=function() return Vector3(0,0,1) end},{__index=Quaternion}),
        Vector3=setmetatable({distance_squared=function(a,b) return Vector3.distance(a,b)^2 end},{__index=Vector3}),
        Recoil={apply_weapon_recoil_rotation=function(_,_,_,_,_,rotation)
            assert(rotation==component.rotation); stages[#stages+1]='recoil'
            return {yaw=rotation.yaw+.03,pitch=rotation.pitch,roll=0}
        end},
        Sway={apply_sway_rotation=function(_,_,rotation)
            assert(math.abs(rotation.yaw-(component.rotation.yaw+.03))<1e-12)
            stages[#stages+1]='sway'; return {yaw=rotation.yaw+.04,pitch=rotation.pitch,roll=0}
        end},
    },{__index=_G})
    local function methods(path,class_name,first_name,next_name)
        local text=source(path)
        local a=assert(text:find(class_name..'.'..first_name..' =',1,true))
        local b=assert(text:find('\n'..class_name..'.'..next_name..' =',a,true))
        setfenv(assert(loadstring(text:sub(a,b-1))),env)()
    end
    methods('extension_systems/smart_targeting/player_unit_smart_targeting_extension',
        'PlayerUnitSmartTargetingExtension','fixed_update','_update_proximity')
    local function finder(kind)
        return {update_precision_target=function(_,unit,settings,origin,forward,right,up,out,frame)
            calls[#calls+1]=kind
            assert(unit=='local' and settings==template and origin==component.position)
            assert(math.abs(forward[1]+math.sin(component.rotation.yaw+.07))<1e-12)
            assert(math.abs(right[1]-math.cos(component.rotation.yaw))<1e-12 and up[3]==1)
            out.unit=selected
        end}
    end
    local targeting=setmetatable({_unit_data_extension=data,_targeting_data=targets,
        _smart_tag_targeting_data={unit='old_tag'},_smart_tag_targeting_time=1000,
        _player={is_human_controlled=function() return human end},
        _first_person_component=component,_weapon_extension={recoil_template=function() end,sway_template=function() end},
        _buff_extension={has_keyword=function(_,key) assert(key=='enable_auto_aim'); return auto_aim end},
        _precision_target_aim_assist=finder('assist'),_precision_target_auto_aim=finder('auto'),
        _line_of_sight_cache={expired=.01,retained=.1},_visibility_cache={},_visibility_check_frame={},
        _update_proximity=function() end,_is_local_unit=true,_is_social_hub=false},
        {__index=env.PlayerUnitSmartTargetingExtension})
    targeting:fixed_update('local',.02,30,301)
    assert(targets.unit=='enemy_a' and calls[1]=='assist' and table.concat(stages,',')=='recoil,sway')
    assert(targeting._line_of_sight_cache.expired==nil and targeting._line_of_sight_cache.retained==.08)
    auto_aim=true; selected='enemy_b'; targeting:fixed_update('local',.02,30.02,302)
    assert(targets.unit=='enemy_b' and calls[2]=='auto')
    local before=#calls; human=false; targeting:fixed_update('local',.02,30.04,303)
    assert(#calls==before); human=true
    -- Both Psyker modules retain their recorded target while resimulating;
    -- the targeting extension itself clears transient target-selection data.
    for _,single in ipairs({false,true}) do
        local class_name=single and 'PsykerChainLightningSingleTargetingActionModule' or 'PsykerSmiteTargetingActionModule'
        local path='extension_systems/weapon/actions/modules/'..
            (single and 'psyker_chain_lightning_single_targeting_action_module' or 'psyker_smite_targeting_action_module')
        env[class_name]={}
        methods(path,class_name,'fixed_update','finish')
        local locked={}
        local lock=setmetatable({_component=locked,_unit_data_extension=data,_action_settings={sticky_targeting=true},
            _player_unit='local',_first_person_component=component,
            _smart_targeting_extension={targeting_data=function() return targets end}}, {__index=env[class_name]})
        targets.unit='enemy_a'; lock:fixed_update(.02,31)
        assert(locked.target_unit_1=='enemy_a')
        targets.unit='enemy_b'; lock:fixed_update(.02,31.02)
        assert(locked.target_unit_1=='enemy_a','Sticky charge retargeted after aim changed')
        lock._action_settings.sticky_targeting=false; lock:fixed_update(.02,31.04)
        assert(locked.target_unit_1=='enemy_b')
        targets.unit='edge'; lock:fixed_update(.02,31.06)
        assert(locked.target_unit_1==nil,'Stock strict range boundary changed')
        targets.unit='enemy_a'; lock:fixed_update(.02,31.08)
        data.is_resimulating=true
        targeting:fixed_update('local',.02,31.1,304)
        assert(targets.unit==nil and targeting._smart_tag_targeting_data.unit==nil and #calls==before)
        lock:fixed_update(.02,31.1)
        assert(locked.target_unit_1=='enemy_a','Resimulation discarded recorded target')
        data.is_resimulating=false
    end
    aim,h._input_cache=saved_aim,saved_cache
end
-- With zero recoil, the actual walking method reconstructs the intended head-
-- relative direction from the transformed input. Its own backward penalty stays.
local constants={acceleration=1000,deceleration=1000,backward_move_scale=.5,
    move_speed=5,crouch_move_speed=2,slide_move_speed_threshold=2}
local function move(yaw)
    return walking.wanted_movement(constants,input,{local_move_x=0,local_move_y=0},
        {player_speed_scale=1},{rotation=Quaternion.from_yaw_pitch_roll(yaw,0,0)},
        false,Vector3(0,0,0),1)
end
local direction,speed=move(aim.yaw)
assert(math.abs(direction[1])<1e-12 and math.abs(direction[2]-1)<1e-12 and speed==5)
aim=Quaternion.from_yaw_pitch_roll(math.pi,0,0)
h._input_cache={{0},{0},{1},{0},{0},{0},{0}}
rules.capture(h,2)
direction,speed=move(aim.yaw)
assert(math.abs(direction[1])<1e-12 and math.abs(direction[2]-1)<1e-12)
assert(math.abs(speed-2.5)<1e-12,'Stock backward penalty must remain')
-- Verify through actual walking, including rotated diagonals that exceed the
-- stock square. All headings keep the desired direction at settled input.
for step=0,11 do
    for _,wanted in ipairs({{1,1},{1,.5},{-1,1},{-.3,-.8}}) do
        aim=Quaternion.from_yaw_pitch_roll(step*math.pi/6,0,0)
        local x,y=wanted[1],wanted[2]
        h._input_cache={{math.max(x,0)},{math.max(-x,0)},
            {math.max(y,0)},{math.max(-y,0)},{0},{0},{0}}
        rules.capture(h,step+3)
        direction=move(aim.yaw)
        local length=math.sqrt(x*x+y*y)
        assert(math.abs(direction[1]-x/length)<1e-12 and
            math.abs(direction[2]-y/length)<1e-12,'Stock walking direction changed after aim conversion')
        for index=1,4 do assert(h._input_cache[index][1]>=0 and h._input_cache[index][1]<=1) end
    end
end
-- Execute the actual stock selector for forced look, weapon lock, melee
-- stickiness, ledge hanging, communication/emote wheels and dead ownership.
local selected_cases={
    function() gameplay._force_look_rotation_component.use_force_look_rotation=true end,
    function() gameplay._force_look_rotation_component.use_force_look_rotation=false; gameplay._character_state_component.hanging=true end,
    function() gameplay._character_state_component.hanging=false; gameplay._weapon_lock_view_component.state='weapon_lock' end,
    function() gameplay._weapon_lock_view_component.state='weapon_lock_no_lerp' end,
    function() gameplay._weapon_lock_view_component.state='force_look' end,
    function() gameplay._weapon_lock_view_component.state='none'; gameplay._action_sweep_component.sticking=true end,
    function() gameplay._action_sweep_component.sticking=false; Managers.ui.communication_wheel_wants_camera_control=function() return true end end,
    function() Managers.ui.communication_wheel_wants_camera_control=function() return false end; Managers.ui.emote_wheel_wants_camera_control=function() return true end end,
    function() Managers.ui.emote_wheel_wants_camera_control=function() return false end; ALIVE['local']=false end,
}
for i,select_case in ipairs(selected_cases) do
    select_case()
    assert(orientation_class._player_orientation_class(gameplay)~=gameplay._default_player_orientation)
    h._input_cache={{0},{0},{1},{0},{0},{0},{0}}
    rules.capture(h,i+10)
    assert(h._input_cache[5][1]==0 and h._input_cache[3][1]==1,'Overrode forced stock orientation')
end
print('PASS: actual stock pose keeps body origin/recoil; actual walking preserves direction and backward penalty')
print('PASS: actual stock orientation selector retains forced look, weapon locks, sticky melee, ledges, wheels and death')
print('PASS: actual stock local rendering and camera root retain independent view orientation')
print('PASS: actual stock shot preparation retains body origin, charge, recoil/sway/assist/spread order and grouped-shot sample')
print('PASS: actual stock sweeps retain simulation references, damage-window edges/final drain, abort masks and time scaling')
print('PASS: actual stock flame loops retain simulation rays, obstructions, target filtering, rewind and server-only damage/burn calls')
print('PASS: actual stock targeting retains simulation aim/recoil/sway, assist ownership, sticky charges, strict range and resimulation targets')
print('LIMIT: isolated engine math, no real quantization, live network or worn acceptance')
