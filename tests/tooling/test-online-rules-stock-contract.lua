-- Optional source integration: execute stock first-person and walking methods
-- after the real VR cache adapter. Engine math is isolated; no live XR/network.
local vector_meta={}
Vector3=setmetatable({}, {__call=function(_,x,y,z) return setmetatable({x,y,z},vector_meta) end})
vector_meta.__add=function(a,b) return Vector3(a[1]+b[1],a[2]+b[2],a[3]+b[3]) end
vector_meta.__sub=function(a,b) return Vector3(a[1]-b[1],a[2]-b[2],a[3]-b[3]) end
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
-- Execute actual projectile firing and stock spawn-parameter ownership after
-- the preparation above. Trajectory math/procs/network creation are sinks.
do
    local projectile_class,projectile_aim={},{}
    local spawns,procs,parameters={},{},{}
    local current_position=shot_component.shooting_position
    local current_rotation=shot_component.shooting_rotation
    local initial_rotation={identity=true}
    local launch_position=current_position+Vector3(0,.2,0)
    local launch_rotation,launch_direction={launch=true},{direction=true}
    local zero_momentum,initial_momentum=Vector3(0,0,0),Vector3(1,2,3)
    local cached={position=Vector3(800,900,700),rotation={cached=true},
        direction={cached_direction=true},speed=55,momentum=Vector3(8,9,10)}
    local throw_config={}
    local locomotion={trajectory_parameters={throw=throw_config}}
    local projectile={name='stock_projectile',locomotion_template=locomotion}
    projectile_aim.aim_parameters=function(position,initial,rotation,configuration,throw_type,time)
        assert(position==current_position and initial==initial_rotation and rotation==current_rotation,
            'Projectile ignored its prepared shot or read a rendered pose')
        assert(configuration==locomotion and throw_type=='throw' and time==0)
        parameters[#parameters+1]={position,rotation}
        return {position=launch_position,rotation=launch_rotation,direction=launch_direction,speed=40}
    end
    local function load_methods(path,first_marker,last_marker,environment)
        local text=source(path)
        local first=assert(text:find(first_marker,1,true)); local last=assert(text:find(last_marker,first,true))
        local chunk=assert(loadstring(text:sub(first,last-1),'@'..path))
        setfenv(chunk,setmetatable(environment,{__index=_G})); chunk()
    end
    load_methods('utilities/aim_projectile','AimProjectile.get_spawn_parameters_from_current_aim =',
        '\nAimProjectile.check_throw_position =',
        {AimProjectile=projectile_aim,Quaternion={identity=function() return initial_rotation end},
         Vector3={zero=function() return zero_momentum end}})
    local proc_enabled=true
    local buffs={request_proc_event_param_table=function() return proc_enabled and {} or nil end,
        add_proc_event=function(_,event,params)
            assert(event=='shoot_projectile'); procs[#procs+1]=params
        end}
    load_methods('extension_systems/weapon/actions/action_shoot_projectile',
        'ActionShootProjectile._shoot =','\nreturn ActionShootProjectile',
        {ActionShootProjectile=projectile_class,AimProjectile=projectile_aim,
         proc_events={on_shoot_projectile='shoot_projectile'},locomotion_states={manual_physics='manual'},
         ScriptUnit={extension=function(unit,system) assert(unit=='local' and system=='buff_system'); return buffs end},
         Managers={state={unit_spawner={spawn_network_unit=function(_,...) spawns[#spawns+1]={...} end}}}})
    local action=setmetatable({_player_unit='local',_action_component=shot_component,
        _action_settings={throw_type='throw',fire_configuration={inventory_item_name='payload'}},
        _item_definitions={payload='projectile_item'},_weapon={item='weapon_item'},
        _action_aim_projectile_component=cached,_combo_count=3,
        _critical_strike_component={is_active=true},_inventory_component={wielded_slot='slot_secondary'},
        _side_system={side_by_unit={['local']={name=function() return 'heroes' end}}}},
        {__index=projectile_class})
    for _,server in ipairs({false,true}) do
        for _,skip in ipairs({false,true}) do
            for _,explicit in ipairs({false,true}) do
                action._is_server=server
                throw_config.locomotion_state=explicit and 'ballistic' or nil
                throw_config.initial_angular_velocity=explicit and {unbox=function() return initial_momentum end} or nil
                projectile.unit_template_name=explicit and 'explicit_projectile' or nil
                local prior_spawns,prior_procs=#spawns,#procs
                action:_shoot(Vector3(900,800,700),{unrelated_argument=true},999,.8,10,
                    {projectile=projectile,skip_aiming=skip})
                assert(#spawns==prior_spawns+(server and 1 or 0),'Client spawned an authoritative projectile')
                assert(#procs==prior_procs+1)
                local proc=procs[#procs]
                assert(proc.attacking_unit=='local' and proc.projectile_template_name=='stock_projectile' and
                    proc.num_shots_fired==shot_component.num_shots_fired and proc.combo_count==3)
                if server then
                    local spawn=spawns[#spawns]
                    assert(spawn[1]==nil and spawn[2]==(explicit and 'explicit_projectile' or 'item_projectile'))
                    assert(spawn[3]==launch_position and spawn[9]==launch_direction,
                        'Cached aim replaced the fresh prepared origin/direction')
                    assert(spawn[4]==(skip and launch_rotation or cached.rotation))
                    assert(spawn[5]==nil and spawn[6]=='projectile_item' and spawn[7]==projectile)
                    assert(spawn[8]==(explicit and 'ballistic' or 'manual'))
                    assert(spawn[10]==(skip and 40 or 55))
                    assert(spawn[11]==(skip and (explicit and initial_momentum or zero_momentum) or cached.momentum))
                    assert(spawn[12]=='local' and spawn[13]==true and spawn[14]=='slot_secondary')
                    assert(spawn[18]=='weapon_item' and spawn[20]=='heroes')
                end
            end
        end
    end
    assert(#parameters==8 and #spawns==4 and #procs==8)
    proc_enabled=false
    action:_shoot(nil,nil,1,0,11,{projectile=projectile,skip_aiming=true})
    assert(#spawns==5 and #procs==8,'Missing optional proc table blocked server spawning')
    assert(shot_component.shooting_position==current_position and shot_component.shooting_rotation==current_rotation)
end
do
    -- Deployables must use the same simulated pose as weapons. Execute stock
    -- placement selection and timed inventory/spawn routing with collision and
    -- final pickup services supplied; no engine geometry or real item mutation.
    local base,pickup,utility={},{},{}
    local rays,responses,spawns,events={},{},{},{}
    local target,placed={},{}
    local registered=true
    local v=setmetatable({down=function() return Vector3(0,0,-1) end,
        zero=function() return Vector3(0,0,0) end},{__index=Vector3})
    local env=setmetatable({Vector3=v,Unit={world_position=function() error('rendered placement origin read') end},
        Actor={unit=function(actor) assert(actor==target); return target end},
        PhysicsWorld={raycast=function(world,position,direction,distance,...)
            assert(world=='placement_world')
            assert(table.concat({...},'|')=='closest|types|both|collision_filter|filter_player_place_deployable')
            rays[#rays+1]={position,direction,distance}
            local result=assert(responses[#rays],'unexpected placement ray')
            return result.hit,result.position,1,result.normal,result.actor
        end},Managers={state={unit_spawner={
            game_object_id=function() return registered and 8 or nil end,
            level_index=function() return nil end}}}}, {__index=_G})
    local placement=setfenv(assert(loadstring(source('extension_systems/weapon/actions/utilities/aim_placement'))),env)()
    local function methods(path,first,last,scope)
        local text=source(path)
        local a=assert(text:find(first,1,true)); local b=assert(text:find(last,a,true))
        setfenv(assert(loadstring(text:sub(a,b-1),'@'..path)),setmetatable(scope,{__index=_G}))()
    end
    methods('extension_systems/weapon/actions/utilities/action_utility',
        'local EPSILON =','\nActionUtility.projectile_template =',
        {ActionUtility=utility,FixedFrame={clamp_to_fixed_time=function(t) return t end}})
    local function record(name,...) events[#events+1]={name,...} end
    methods('extension_systems/weapon/actions/action_place_base',
        'ActionPlaceBase.fixed_update =','\nreturn ActionPlaceBase',
        {ActionPlaceBase=base,AimPlacement=placement,ActionUtility=utility,
         Ammo={current_ammo_in_clips=function(slot) return slot.ammo end,
            set_current_ammo_in_clips=function(slot,ammo) slot.ammo=ammo end},
         PlayerUnitVisualLoadout={wield_previous_weapon_slot=function(...) record('wield',...) end,
            unequip_item_from_slot=function(...) record('unequip',...) end}})
    local pickup_owner={session_id=function() return 'fixture_session' end}
    local has_owner=true
    local pickup_system={player_spawn_pickup=function(_,...) spawns[#spawns+1]={...}; return placed end,
        spawn_pickup=function(_,...) spawns[#spawns+1]={...}; return placed end,
        dropped=function(_,unit) assert(unit==placed); record('dropped',unit) end}
    local game_mode='shooting_range'
    methods('extension_systems/weapon/actions/action_place_pickup',
        'ActionPlacePickup._place_unit =','\nreturn ActionPlacePickup',
        {ActionPlacePickup=pickup,TRAINING_GROUNDS_GAME_MODE_NAME='training_grounds',
         Pickups={by_name={crate={on_drop_func=function(unit) assert(unit==placed); record('on_drop',unit) end}}},
         Managers={state={player_unit_spawn={owner=function(_,unit) assert(unit=='local'); return has_owner and pickup_owner or nil end},
             extension={system=function(_,name) assert(name=='pickup_system'); return pickup_system end},
             game_mode={game_mode_name=function() return game_mode end}},
             event={trigger=function(_,...) record('event',...) end}}})
    local action=setmetatable({_first_person_component=component,_physics_world='placement_world',
        _action_component={},_player_unit='local',_weapon_template={pickup_name='crate'},
        _inventory_component={wielded_slot='slot_pocketable'},_inventory_slot_component={ammo=1},
        _weapon_action_component={time_scale=2},_place_unit=pickup._place_unit,
        _register_stats_and_telemetry=function(_,...) record('stats',...) end,
        trigger_anim_event=function(_,...) record('anim',...) end}, {__index=base})
    local config={distance=3}
    local floor=Vector3(4,5,0)
    local function result(hit,normal)
        return {hit=hit,position=hit and floor or nil,normal=normal or Vector3(0,0,1),actor=hit and target or nil}
    end
    local function calculate(results)
        rays,responses={},results
        action._action_settings={place_configuration=config,total_time=1,place_time=.4,
            remove_item_from_inventory=true,ammunition_usage=1,can_drop_anim_event='can_drop'}
        action:_update_place_data(20)
        assert(rays[1][1]==component.position and rays[1][3]==3)
        assert(Vector3.dot(rays[1][2],Quaternion.forward(component.rotation))>.999)
        return action._action_component
    end
    local cached=calculate({result(true)})
    assert(cached.can_place and cached.position==floor and cached.placed_on_unit==target and cached.can_place_time==20)
    assert(cached.rotation.yaw==Quaternion.look(Vector3.flat(Quaternion.forward(component.rotation))).yaw)
    for _,server in ipairs({false,true}) do
        events,spawns={},{}
        action._is_server=server; action._inventory_slot_component.ammo=1
        action:fixed_update(.1,20.1,.1)
        assert(#spawns==0 and action._inventory_slot_component.ammo==1)
        action:fixed_update(.1,20.2,.2)
        assert(action._inventory_slot_component.ammo==0 and action._inventory_slot_component.last_ammunition_usage==20.2)
        assert(events[1][1]=='wield' and events[2][1]=='unequip')
        assert(#spawns==(server and 1 or 0),'Client spawned a deployable')
        if server then
            local spawn=spawns[1]
            assert(spawn[1]=='crate' and spawn[2]==floor and spawn[3]==cached.rotation)
            assert(spawn[4]==pickup_owner and spawn[5]=='fixture_session' and spawn[6]==target)
            assert(events[3][1]=='on_drop' and events[4][1]=='dropped' and events[5][1]=='stats' and #events==5)
        end
        action:fixed_update(.1,20.3,.3)
        assert(#spawns==(server and 1 or 0),'Deployable repeated after trigger time')
    end
    -- Cached origin survives current first-person changes, but insufficient ammo
    -- still prevents both predicted consumption and server placement.
    local pose=action._first_person_component
    action._first_person_component=setmetatable({}, {__index=function() error('cached placement reread live pose') end})
    action:fixed_update(.1,20.2,.2)
    assert(#spawns==1)
    action._inventory_slot_component.ammo=1
    action:fixed_update(.1,20.2,.2)
    assert(#spawns==2 and spawns[2][2]==floor and spawns[2][3]==cached.rotation)
    action._action_settings.use_aim_data=true
    action:_update_place_data(21)
    assert(cached.position==floor and cached.can_place_time==21 and #rays==1)
    action._first_person_component=pose
    calculate({result(false),result(true)})
    assert(#rays==2 and rays[2][3]==3 and rays[2][2][3]==-1)
    local fallback=component.position+Quaternion.forward(component.rotation)*3
    assert(Vector3.length(rays[2][1]-fallback)<1e-12)
    config.allow_aim_upwards_deployment=true
    calculate({result(false),result(true)})
    assert(rays[2][3]==15)
    config.force_place=true
    calculate({result(true,Vector3(0,0,.7)),result(true)})
    assert(#rays==2 and rays[2][1]==component.position and rays[2][2][3]==-1 and rays[2][3]==3)
    config.force_place=false
    calculate({result(true,Vector3(0,0,.7))})
    assert(not cached.can_place,'Stock slope threshold was relaxed')
    events={}; assert(action:fixed_update(.1,20.2,.2)==true and #events==0)
    action._action_settings.try_until_placed=true
    responses[#rays+1]=result(true)
    local before_spawns=#spawns
    assert(action:fixed_update(.1,21,.2)==false and cached.can_place and cached.can_place_time==21)
    assert(#spawns==before_spawns and #events==1 and events[1][1]=='anim' and events[1][2]=='can_drop')
    registered=false
    calculate({result(true)})
    assert(cached.can_place and cached.placed_on_unit==nil,'Unregistered hit unit became a network attachment')
    has_owner=false; game_mode='training_grounds'; events,spawns={},{}
    action._inventory_slot_component.ammo=1
    action:fixed_update(.1,20.2,.2)
    assert(#spawns==1 and spawns[1][4]==nil and spawns[1][5]==nil)
    assert(events[#events][1]=='event' and events[#events][2]=='tg_on_pickup_placed')
end
do
    local give,ally,utility={},{},{}
    local events={}
    local recipient,other={},{}
    local target_data={unit=recipient}
    local targets={}
    local alive={[recipient]=true,[other]=true}
    local human,equipped,item_available=true,false,true
    local function record(name,...) events[#events+1]={name,...} end
    local loadout={slot_equipped=function() return equipped end,
        wield_previous_weapon_slot=function(...) record('wield',...) end,
        unequip_item_from_slot=function(...) record('unequip',...) end,
        equip_item_to_slot=function(...) record('equip',...) end}
    local target_player={is_human_controlled=function() return human end}
    local target_inventory={}
    local extensions={unit_data_system={read_component=function(_,name) assert(name=='inventory'); return target_inventory end},
        visual_loadout_system={},fx_system={trigger_exclusive_gear_wwise_event=function(_,event,properties)
            assert(event=='recieve_gifted_item' and properties.pocketable_name=='crate')
            record('fx',event)
        end}}
    local env=setmetatable({ALIVE=alive,ActionGivePocketable=give,ActionTargetAlly=ally,ActionUtility=utility,
        PlayerUnitVisualLoadout=loadout,
        Managers={state={player_unit_spawn={owner=function(_,unit) return unit==recipient and target_player or nil end}}},
        ScriptUnit={extension=function(unit,name) assert(unit==recipient); return assert(extensions[name]) end},
        require=function(path)
            assert(path=='scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout')
            return loadout
        end}, {__index=_G})
    local slots=setfenv(assert(loadstring(source('settings/equipment/weapon_templates/pocketables/pockatables_utils'))),env)()
    env.PocketableUtils=slots
    env.Pickups={by_name={crate={inventory_item='crate_item',inventory_slot_name='slot_pocketable'}}}
    env.Pocketable={item_from_name=function(name) assert(name=='crate_item'); return item_available and 'item' or nil end}
    env.PlayerAssistNotifications={show_notification=function(...) record('assist',...) end}
    env.Vo={on_demand_vo_event=function(...) record('voice',...) end}
    env.RECIEVE_GIFTED_ITEM_ALIAS='recieve_gifted_item'
    env.FixedFrame={clamp_to_fixed_time=function(t) return t end}
    env.table=setmetatable({clear=function(t) for k in pairs(t) do t[k]=nil end end},{__index=table})
    local function methods(path,first,last)
        local text=source(path)
        local a=assert(text:find(first,1,true)); local b=assert(text:find(last,a,true))
        setfenv(assert(loadstring(text:sub(a,b-1),'@'..path)),env)()
    end
    methods('extension_systems/weapon/actions/utilities/action_utility','local EPSILON =','\nActionUtility.projectile_template =')
    methods('extension_systems/weapon/actions/action_give_pocketable','local external_properties =','\nreturn ActionGivePocketable')
    methods('extension_systems/weapon/actions/action_target_ally','ActionTargetAlly.start =','\nreturn ActionTargetAlly')
    local super={start=function() end,finish=function() end}
    give.super,ally.super=super,super
    local unit_data={is_resimulating=false}
    local targeting=setmetatable({_player_unit='local',_unit_data_extension=unit_data,
        _action_module_target_finder_component=targets,
        _smart_targeting_extension={targeting_data=function() return target_data end},
        _action_settings={validate_target_func=slots.validate_give_pocketable_target_func,
            clear_on_hold_release=true,has_target_anim_event='has_target',no_target_anim_event='no_target'},
        trigger_anim_event=function(_,event) record('anim',event) end}, {__index=ally})
    local action=setmetatable({_player_unit='local',_unit_data_extension=unit_data,
        _action_module_target_finder_component=targets,_inventory_component={wielded_slot='slot_pocketable'},
        _weapon_template={give_pickup_name='crate'},_weapon_action_component={time_scale=2},
        _action_settings={total_time=.7,give_time=.7,assist_notification_type='gifted',
            voice_event_data={voice_tag_concept='concept',voice_tag_id='take_this'}}}, {__index=give})
    targeting:start()
    targeting:fixed_update(.05,10,0)
    assert(targets.target_unit_1==recipient and events[1][2]=='has_target')
    targeting:finish('new_interrupting_action',nil,10,0)
    assert(targets.target_unit_1==recipient,'Giving chain discarded the acquired recipient')
    for _,server in ipairs({false,true}) do
        action._is_server=server; events={}
        action:fixed_update(.05,10,.3)
        assert(#events==0)
        action:fixed_update(.05,10,.35)
        assert(events[1][1]=='wield' and events[2][1]=='unequip')
        if server then
            assert(#events==6 and events[3][1]=='assist' and events[4][1]=='equip' and events[5][1]=='fx' and events[6][1]=='voice')
            assert(events[3][2]==recipient and events[4][2]==recipient and events[4][3]=='item' and events[4][4]=='slot_pocketable')
        else assert(#events==2,'Client equipped or notified the recipient') end
        local before=#events
        action:fixed_update(.05,10,.4)
        assert(#events==before,'Transfer repeated after its stock trigger time')
    end
    -- Target validation is repeated when transfer fires, even if the slot was
    -- free when aim began. Invalid stock targeting data may retain its unit;
    -- it must not cause item removal/equip at the action boundary.
    for _,failure in ipairs({'dead','bot','occupied','unowned','no_item','no_target'}) do
        alive[recipient]=failure~='dead'; human=failure~='bot'; equipped=failure=='occupied'
        item_available=failure~='no_item'; targets.target_unit_1=failure=='unowned' and other or recipient
        if failure=='no_target' then targets.target_unit_1=nil end
        events={}; action:fixed_update(.05,10,.35)
        assert(#events==((failure=='no_item' or failure=='no_target') and 0 or 1),failure)
        if #events>0 then assert(events[1][1]=='wield',failure) end
    end
    alive[recipient],human,equipped,item_available=true,true,false,true
    targets.target_unit_1=recipient
    unit_data.is_resimulating=true
    target_data.unit=other; events={}
    targeting:fixed_update(.05,11,0); action:fixed_update(.05,11,.35)
    assert(targets.target_unit_1==recipient and #events==0,'Replay reacquired or retransferred a pocketable')
    unit_data.is_resimulating=false
    target_data.unit='local'; targeting:fixed_update(.05,11,0)
    assert(targets.target_unit_1==nil,'Self-target survived ally selection')
    targets.target_unit_1,targets.target_unit_2,targets.target_unit_3=recipient,other,recipient
    targeting:finish('hold_input_released',nil,11,0)
    assert(targets.target_unit_1==nil and targets.target_unit_2==nil and targets.target_unit_3==nil)
    targets.target_unit_1=recipient; action:finish('action_complete',nil,11,.7)
    assert(targets.target_unit_1==nil)
end
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
-- Blocking consumes the same single simulation direction as attacks. Execute
-- stock eligibility/cost and Psyker warp-charge conversion without damage.
do
    local saved_aim,saved_cache=aim,h._input_cache
    aim=Quaternion.from_yaw_pitch_roll(1.3,.2,0)
    h._input_cache={{0},{0},{0},{0},{view.yaw},{view.pitch},{0}}
    rules.capture(h,400); PlayerUnitFirstPersonExtension.fixed_update(fp,'local',.02,40,1)
    local original_index=vector_meta.__index
    vector_meta.__index=function(value,key) return value[({x=1,y=2,z=3})[key]] end
    local positions={['local']=Vector3(10,20,0)}
    local flags,stats={}, {block_cost_multiplier=.5,block_cost_modifier=.8,
        block_cost_ranged_multiplier=1,block_cost_ranged_modifier=1,warp_charge_block_cost=1}
    local pieces={first_person=component,block={is_blocking=true,is_perfect_blocking=false},
        weapon_action={},interaction={state='none'},stamina={},warp_charge={current_percentage=.9}}
    local stamina_template={block_cost_melee={inner=2,outer=6},block_cost_ranged={inner=3,outer=7}}
    local weapon={name='fixture_weapon',block_angles={default={inner=.3,outer=1.1}}}
    local action_setting
    local drained,stuns,rpcs,events=0,0,0,0
    local depleted,current_stamina=false,20
    local unit_data={breed=function() return 'player' end,
        read_component=function(_,name) return assert(pieces[name]) end,
        write_component=function(_,name) return assert(pieces[name]) end,
        archetype=function() return {stamina={}} end}
    local buff={has_keyword=function(_,key) return flags[key]==true end,
        stat_buffs=function() return stats end,request_proc_event_param_table=function() end}
    local extensions={unit_data_system=unit_data,buff_system=buff,
        weapon_system={stamina_template=function() return stamina_template end}}
    local names=setmetatable({}, {__index=function(_,key) return key end})
    local dependencies={
        ['scripts/utilities/action/action']={current_action=function() return nil,action_setting end},
        ['scripts/settings/damage/attack_settings']={attack_types={melee='melee',ranged='ranged'}},
        ['scripts/utilities/breed']={is_player=function(breed) return breed=='player' end},
        ['scripts/settings/buff/buff_settings']={keywords=names,proc_events=names,stat_buffs=names},
        ['scripts/settings/interaction/interaction_settings']={states={is_interacting='active'}},
        ['scripts/utilities/attack/stamina']={current_and_max_value=function() return current_stamina,20 end,
            drain=function(unit,cost,t) assert(unit=='local' and t==40); drained=cost; return 0,depleted end},
        ['scripts/utilities/attack/stun']={apply=function(unit,kind)
            assert(unit=='local' and kind=='block_broken'); stuns=stuns+1 end},
    }
    local env=setmetatable({POSITION_LOOKUP=positions,
        require=function(path) return assert(dependencies[path],path) end,
        ScriptUnit={has_extension=function(unit,name) assert(unit=='local'); return extensions[name] end,
            extension=function(unit,name) assert(unit=='local'); return assert(extensions[name]) end},
        Quaternion=setmetatable({right=function(rotation)
            assert(rotation==component.rotation,'Block read the rendered head/hand pose')
            return Vector3(math.cos(rotation.yaw),math.sin(rotation.yaw),0)
        end},{__index=Quaternion}),
        Vector3=setmetatable({down=function() return Vector3(0,0,-1) end,
            cross=function(a,b) return Vector3(a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]) end,
            angle=function(a,b) return math.acos(math.max(-1,math.min(1,Vector3.dot(a,b)))) end},{__index=Vector3}),
        Unit={world_rotation=function() error('Block read rendered unit rotation') end},
        Managers={state={extension={latest_fixed_t=function() return 40 end},
            unit_spawner={game_object_id=function(_,unit) return unit=='local' and 1 or 2 end},
            game_session={send_rpc_clients=function(_,rpc,unit,attacker,position,broken,template,attack)
                assert(rpc=='rpc_player_blocked_attack' and unit==1 and attacker==2 and template==7)
                assert(attack==8 or attack==9); rpcs=rpcs+1
            end}}},NetworkLookup={weapon_templates={fixture_weapon=7},attack_types={melee=8,ranged=9}},
    },{__index=_G})
    local block=setfenv(assert(loadstring(source('utilities/attack/block'))),env)()
    block.player_blocked_attack=function(_,_,_,_,_,_,cost) assert(cost==drained); events=events+1 end
    local function attacker(angle)
        local yaw=component.rotation.yaw+angle
        positions.attacker=positions['local']+Vector3(-math.sin(yaw),math.cos(yaw),0)*3
    end
    local function attempt(kind)
        return block.attempt_block_break('local','attacker',Vector3(0,0,0),kind,
            Vector3(0,1,0),weapon,{block_cost_multiplier=1.5})
    end
    for _,case in ipairs({{0,true,1.2},{.5,true,3.6},{1.2,false},{math.pi,false}}) do
        attacker(case[1])
        assert(block.is_blocking('local','attacker','melee',weapon,true)==case[2])
        if case[2] then assert(not attempt('melee') and math.abs(drained-case[3])<1e-12) end
    end
    attacker(0)
    assert(not block.is_blocking('local','attacker','ranged',weapon,true))
    flags.can_block_ranged=true
    assert(block.is_blocking('local','attacker','ranged',weapon,true))
    assert(not attempt('ranged') and math.abs(drained-1.8)<1e-12)
    flags.can_block_ranged=nil
    pieces.block.is_blocking=false; pieces.interaction={state='active',type='revive'}
    assert(block.is_blocking('local','attacker','melee',weapon,true))
    assert(not block.is_blocking('local','attacker','melee',weapon,false),'Client invented server auto-block')
    current_stamina=0
    assert(not block.is_blocking('local','attacker','melee',weapon,true))
    current_stamina=20; pieces.block.is_blocking=true; pieces.interaction.state='none'
    attacker(.5); flags.block_gives_warp_charge=true
    assert(not attempt('melee') and math.abs(drained-2.2)<1e-12)
    assert(pieces.warp_charge.current_percentage==.97 and pieces.warp_charge.last_charge_at_t==40)
    assert(not attempt('melee') and math.abs(drained-3.6)<1e-12,'Warp cap replaced stock stamina cost')
    flags.block_gives_warp_charge=nil; depleted=true
    assert(attempt('melee') and stuns==1)
    flags.stun_immune_block_broken=true
    assert(attempt('melee') and stuns==1)
    assert(events==rpcs and events==7,'Block outcomes did not follow stock notification path')
    vector_meta.__index=original_index
    aim,h._input_cache=saved_aim,saved_cache
end
-- Actual interaction state/timer and revive completion, with supplied collision
-- results. The same simulated pose supplies acquisition and ongoing validity.
do
    local saved_aim,saved_cache=aim,h._input_cache
    aim=Quaternion.from_yaw_pitch_roll(.8,0,0)
    h._input_cache={{0},{0},{1},{0},{0},{0},{0}}
    rules.capture(h,39); PlayerUnitFirstPersonExtension.fixed_update(fp,'local',.02,39,39)
    local text=source('extension_systems/interaction/interactor_extension')
    local states={waiting_to_interact='waiting',is_interacting='active'}
    local results={success='success',stopped_holding='released',interaction_cancelled='cancelled',ongoing='ongoing'}
    local ext,revive={},{}
    local supplied,events,stops,starts={}, {}, {}, 0
    local held,pressed,finished,valid,obstructed,infinite,ui,allow_start=true,true,false,true,false,false,false,true
    local assisted,knocked={},{}
    local interactee={hold_required=function() return true end,ui_interaction=function() return ui end,
        infinite_interaction=function() return infinite end,started=function() starts=starts+1 end,
        stopped=function(_,result) stops[#stops+1]=result end}
    local target_data={write_component=function(_,name)
        if name=='assisted_state_input' then return assisted end
        assert(name=='knocked_down_state_input'); return knocked
    end}
    local env=setmetatable({InteractorExtension=ext,interaction_states=states,interaction_results=results,
        ONGOING_INTERACTION_LEEWAY=1.2,INDEX_DISTANCE=2,INDEX_ACTOR=4,
        INTERACTABLE_FILTER='filter_interactable_overlap',LINE_OF_SIGHT_FILTER='filter_interactable_line_of_sight_check',
        NetworkConstants={fixed_time_offset_unset=-1},ALIVE={target=true},
        Component={event=function(_,name) events[#events+1]=name end},
        Vo={interaction_start_event=function() end},
        ScriptUnit={extension=function(unit,name)
            assert(unit=='target')
            if name=='interactee_system' then return interactee end
            assert(name=='unit_data_system'); return target_data
        end},
        Actor={unit=function(actor) assert(actor=='target_actor'); return 'target' end,
            world_bounds=function() return component.position+Quaternion.forward(component.rotation),{} end},
        Unit={actor=function() return 'target_actor' end},
        PhysicsWorld={raycast=function(world,position,forward,distance,kind,_,filter)
            assert(world=='physics' and position==component.position and math.abs(distance-3)<1e-12)
            assert(Vector3.length(forward-Quaternion.forward(component.rotation))<1e-12)
            assert(math.abs(component.rotation.yaw-.81)<1e-12,'Interaction used rendered/head aim')
            if kind=='all' then
                assert(filter=='filter_interactable_overlap'); return {{nil,1,nil,'target_actor'}}
            end
            assert(kind=='closest' and filter=='filter_interactable_line_of_sight_check')
            return obstructed,nil,.5
        end},
    },{__index=_G})
    local function methods(first,last)
        local a=assert(text:find('InteractorExtension.'..first..' =',1,true))
        local b=assert(text:find('\nInteractorExtension.'..last..' =',a,true))
        setfenv(assert(loadstring(text:sub(a,b-1))),env)()
    end
    methods('reset_interaction','extensions_ready')
    methods('_check_current_state','_find_object_in_direct_line_of_sight')
    methods('_find_interaction_object','_max_interaction_distance')
    local revive_env=setmetatable({class=function() return revive end,require=function(path)
        if path:find('buff_settings',1,true) then return {proc_events={on_revive='revive'}} end
        if path:find('interaction_settings',1,true) then return {results=results} end
        return {}
    end},{__index=env})
    setfenv(assert(loadstring(source('extension_systems/interaction/interactions/revive_interaction'))),revive_env)()
    local buffs,stats=0,0
    revive._handle_buffs=function() buffs=buffs+1 end
    revive._record_stats_and_telemetry=function() stats=stats+1 end
    local stopped_result
    local interaction={interaction_input=function() return 'interact_pressed' end,type=function() return 'revive' end,
        start=function() return allow_start end,
        stop=function(_,world,unit,piece,t,result,server)
            stopped_result=result; revive.stop(revive,world,unit,piece,t,result,server)
        end}
    local actor=setmetatable({_unit='local',_world='world',_physics_world='physics',_first_person_component=component,
        _input_extension={get=function(_,name)
            if name=='interact_pressed' then return pressed end
            if name=='interact_hold' then return held end
            assert(name=='finished_interaction'); return finished
        end},interaction=function() return interaction end,
        _consume_conflicting_gamepad_inputs=function() end,
        _check_valid_interaction_target=function() return valid end,
        _max_interaction_distance=function() return 2.5 end,
        _check_collision_clear=function(_,position) assert(position==component.position); return not obstructed end,
        _find_object_in_direct_line_of_sight=function(_,unit,position,forward)
            assert(unit=='local' and position==component.position)
            assert(Vector3.length(forward-Quaternion.forward(component.rotation))<1e-12)
            return unpack(supplied,1,4)
        end,
        _find_object_near_line_of_sight=function() return 'near',4,'near_focus',5 end,
    },{__index=ext})
    supplied={'target',2,'focus',3}
    local target,node,focus,focus_node=actor:_find_interaction_object('local')
    assert(target=='target' and node==2 and focus=='focus' and focus_node==3)
    supplied={nil,nil,'direct_focus',6}
    target,node,focus,focus_node=actor:_find_interaction_object('local')
    assert(target=='near' and node==4 and focus=='direct_focus' and focus_node==6)
    local function prepare(server)
        actor._is_server=server
        actor._interaction_component={target_unit='target',target_actor_node_index=2,type='revive',
            state=states.waiting_to_interact,duration=2}
        held,pressed,finished,valid,obstructed,infinite,ui,allow_start=true,true,false,true,false,false,false,true
        assisted,knocked={success=false},{knock_down=true}
        stopped_result=nil; events={}; stops={}; starts=0; buffs=0; stats=0
        env.ALIVE.target=true
    end
    local function step(t,chosen)
        actor:_check_current_state('local',.02,t,chosen,actor._interaction_component.state)
    end
    for _,server in ipairs({false,true}) do
        prepare(server); step(10,true)
        assert(starts==1 and actor._interaction_component.state==states.is_interacting)
        assert(actor._interaction_component.start_time==10 and actor._interaction_component.done_time==12)
        pressed=false; step(11.99,true)
        assert(not stopped_result and not assisted.success)
        step(12,true)
        assert(stopped_result==results.success and actor._interaction_component.target_unit==nil)
        assert(assisted.success==server and knocked.knock_down==not server)
        assert(buffs==(server and 1 or 0) and stats==buffs)
        assert(#events==(server and 2 or 0) and #stops==(server and 1 or 0))
        if server then assert(events[2]=='interaction_success') end
        for _,cancel in ipairs({'release','obstruction','invalid','dead','missing'}) do
            prepare(server); step(20,true); pressed=false
            if cancel=='release' then held=false
            elseif cancel=='obstruction' then obstructed=true
            elseif cancel=='invalid' then valid=false
            elseif cancel=='dead' then env.ALIVE.target=false
            else actor._interaction_component.target_unit=nil end
            step(22,true) -- Cancellation wins even at the completion boundary.
            assert(stopped_result==(cancel=='release' and results.stopped_holding or results.interaction_cancelled))
            assert(not assisted.success and knocked.knock_down and buffs==0 and stats==0)
        end
    end
    prepare(true); pressed=false; step(1,true); assert(starts==0)
    prepare(true); step(1,false); assert(starts==0)
    prepare(true); allow_start=false; step(1,true); assert(starts==0)
    prepare(true); infinite=true; step(1,true); pressed=false; step(100,true)
    assert(not stopped_result and actor._interaction_component.done_time==0)
    ui=true; finished=true; step(101,true)
    assert(stopped_result==results.success and assisted.success)
    -- Stock node-zero interactions deliberately bypass spatial validity.
    assert(actor:_check_valid_ongoing_interaction(nil,0))
    aim,h._input_cache=saved_aim,saved_cache
end
-- Air steering reconstructs the world direction before applying stock drag,
-- acceleration and jump gravity. Sliding admission still depends on aim facing.
do
    local saved_aim,saved_cache,saved_extension=aim,h._input_cache,ScriptUnit.has_extension
    local saved_index,saved_newindex,saved_angle=vector_meta.__index,vector_meta.__newindex,Vector3.angle
    local keys={x=1,y=2,z=3}
    vector_meta.__index=function(v,key) return keys[key] and v[keys[key]] end
    vector_meta.__newindex=function(v,key,value) rawset(v,keys[key] or key,value) end
    Vector3.angle=function(a,b)
        local lengths=Vector3.length(a)*Vector3.length(b)
        assert(lengths>0,'This fixture does not substitute zero-vector angle policy')
        return math.acos(math.max(-1,math.min(1,Vector3.dot(a,b)/lengths)))
    end
    local character='jumping'
    ScriptUnit.has_extension=function() return {current_state_name=function() return character end} end
    local base,jump,fall,slide={},{},{},{}
    local damage_checks,weapon_updates,ability_updates=0,0,0
    local env=setmetatable({PlayerCharacterStateBase=base,PlayerCharacterStateJumping=jump,
        PlayerCharacterStateFalling=fall,PlayerCharacterStateSliding=slide,
        math=setmetatable({clamp01=function(v) return math.max(0,math.min(1,v)) end},{__index=math}),
        Fall={check_damage=function() damage_checks=damage_checks+1 end},
        Crouch={check=function() return true end},PlayerUnitPeeking={fixed_update=function() end},
        SPEED_EPSILON=.001,buff_keywords={knock_down_on_slide='knock',zero_slide_friction='zero'},
    },{__index=_G})
    local function method(class,file,first,last)
        local text=source('extension_systems/character_state_machine/character_states/'..file)
        local a=assert(text:find(class..'.'..first..' =',1,true))
        local b=assert(text:find('\n'..class..'.'..last..' =',a,true))
        setfenv(assert(loadstring(text:sub(a,b-1))),env)()
    end
    method('PlayerCharacterStateBase','player_character_state_base','_air_movement','_is_colliding_with_gameplay_collision_box')
    method('PlayerCharacterStateJumping','player_character_state_jumping','fixed_update','_check_transition')
    method('PlayerCharacterStateFalling','player_character_state_falling','fixed_update','_update_falling_sound')
    method('PlayerCharacterStateSliding','player_character_state_sliding','fixed_update','_do_material_query')
    local constants={move_speed=5,air_acceleration=3,air_directional_speed_scale_angle=.8,
        air_move_speed_scale=1.1,air_drag_angle=1.2,gravity=9.81,sprint_jump_speed_threshold_sq=9,
        slide_commit_time=.25,slide_friction_function=function() return 2 end,
        sprint_slide_friction_function=function() return 4 end}
    local actor=setmetatable({_constants=constants,_first_person_component=component,_input_extension=input,
        _locomotion_component={},_locomotion_steering_component={},_movement_settings_component={player_speed_scale=1},
        _sprint_character_state_component={},_character_state_component={entered_t=0},
        _slide_character_state_component={friction_function='default'},
        _weapon_extension={update_weapon_actions=function() weapon_updates=weapon_updates+1 end,
            move_speed_modifier=function() return .8 end,weapon_template=function() return {} end},
        _ability_extension={update_ability_actions=function() ability_updates=ability_updates+1 end},
        _update_falling_sound=function() end,_update_likely_stuck_hack=function() end,
        _check_transition=function() return 'stock_transition' end,
        _fx_extension={run_looping_sound=function() end},_buff_extension={has_keyword=function() return false end},
    },{__index=base})
    local baseline=Quaternion.from_yaw_pitch_roll(.01,.02,0)
    local dt=.02
    for _,state_name in ipairs({'jumping','falling'}) do
        character=state_name
        for step=0,5 do
            for _,direction in ipairs({{.4,1},{-.6,.2},{0,-1}}) do
                for _,velocity in ipairs({Vector3(1,2,3),Vector3(7,-1,-2),Vector3(-3,1,0)}) do
                    aim=Quaternion.from_yaw_pitch_roll(step*math.pi/3,.25,0)
                    local x,y=unpack(direction)
                    h._input_cache={{math.max(x,0)},{math.max(-x,0)},{math.max(y,0)},{math.max(-y,0)},{0},{0},{0}}
                    rules.capture(h,40); PlayerUnitFirstPersonExtension.fixed_update(fp,'local',dt,40,40)
                    actor._locomotion_component.velocity_current=velocity
                    actor._is_server=step%2==0
                    actor._movement_settings_component.player_speed_scale=step%2==0 and .7 or 1.2
                    actor._sprint_character_state_component={is_sprint_jumping=true,wants_sprint_camera=true}
                    local expected=base._air_movement(actor,velocity,x,y,baseline,4,
                        actor._movement_settings_component.player_speed_scale,dt)
                    if state_name=='jumping' then expected.z=expected.z-constants.gravity*dt end
                    local selected=state_name=='jumping' and jump or fall
                    local checks_before=damage_checks
                    assert(selected.fixed_update(actor,'local',dt,40,{},40)=='stock_transition')
                    assert(Vector3.length(actor._locomotion_steering_component.velocity_wanted-expected)<1e-10,
                        'Aim basis changed stock air acceleration/drag/gravity')
                    assert(damage_checks-checks_before==((state_name=='falling' and actor._is_server) and 1 or 0))
                    assert(actor._sprint_character_state_component.is_sprint_jumping==
                        (Vector3.length_squared(Vector3.flat(velocity))>=9))
                end
            end
        end
    end
    assert(weapon_updates==ability_updates and weapon_updates==108)
    -- Slide entry is a forward-velocity test, not just a crouch button. Looking
    -- the simulated aim sideways/backwards can prevent entry under stock rules.
    local walk_constants={acceleration=1000,deceleration=1000,backward_move_scale=.5,
        move_speed=5,crouch_move_speed=2,slide_move_speed_threshold=2}
    character='walking'
    for _,case in ipairs({{0,true},{math.pi/2,false},{math.pi,false}}) do
        aim=Quaternion.from_yaw_pitch_roll(case[1],0,0)
        h._input_cache={{0},{0},{1},{0},{0},{0},{0}}
        rules.capture(h,41); PlayerUnitFirstPersonExtension.fixed_update(fp,'local',dt,41,41)
        local result={walking.wanted_movement(walk_constants,input,{local_move_x=0,local_move_y=0},
            {player_speed_scale=1},component,true,Vector3(0,5,0),dt)}
        assert(result[8]==case[2],'Stock slide facing gate changed')
        -- Once sliding, existing world velocity/friction is not rotated by aim.
        for _,friction in ipairs({'default','sprint'}) do
            actor._slide_character_state_component.friction_function=friction
            actor._locomotion_component.velocity_current=Vector3(0,5,0)
            assert(slide.fixed_update(actor,'local',dt,41,{},41)=='stock_transition')
            local expected=Vector3(0,5-(friction=='default' and 2 or 4)*dt,0)
            assert(Vector3.length(actor._locomotion_steering_component.velocity_wanted-expected)<1e-12)
        end
    end
    aim,h._input_cache,ScriptUnit.has_extension=saved_aim,saved_cache,saved_extension
    vector_meta.__index,vector_meta.__newindex,Vector3.angle=saved_index,saved_newindex,saved_angle
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
print('PASS: actual stock projectile launch retains prepared origin/direction, cached ballistic branches, proc metadata and server-only spawn ownership')
print('PASS: stock deployables retain simulated placement rays, slope/attachment validation, timed ammo consumption and server-only pickup spawning')
print('PASS: stock pocketable transfer revalidates recipient inventory, retains chain/release rules and suppresses transfer during replay')
print('PASS: actual stock sweeps retain simulation references, damage-window edges/final drain, abort masks and time scaling')
print('PASS: actual stock flame loops retain simulation rays, obstructions, target filtering, rewind and server-only damage/burn calls')
print('PASS: actual stock targeting retains simulation aim/recoil/sway, assist ownership, sticky charges, strict range and resimulation targets')
print('PASS: actual stock block angles/costs, ranged keyword, revive authority, warp-charge cap and break notifications retained')
print('PASS: actual stock interaction acquisition/holds/cancellation uses simulation pose; revive completion remains server-owned')
print('PASS: actual stock jumping/falling preserve air steering, drag, gravity and authority; slide entry facing and world friction remain stock')
print('LIMIT: isolated engine math, no real quantization, live network or worn acceptance')
