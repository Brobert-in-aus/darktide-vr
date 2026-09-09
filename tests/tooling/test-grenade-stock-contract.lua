-- Optional: luajit test-grenade-stock-contract.lua <grenade-module> <stock-root>
-- Actual stock aim/throw/preview methods; engine trajectory/physics are stubs.
local root='scripts/extension_systems/weapon/actions/'
local effects='scripts/extension_systems/visual_loadout/wieldable_slot_scripts/aim_projectile_effects'
ActionAimProjectile,ActionThrowGrenade,AimProjectileEffects={},{},{}
local classes={[root..'action_aim_projectile']=ActionAimProjectile,
    [root..'action_throw_grenade']=ActionThrowGrenade,[effects]=AimProjectileEffects,
    ['scripts/extension_systems/visual_loadout/wieldable_slot_scripts/aim_luggable_effects']={},
    ['scripts/utilities/action/action']={current_action_settings_from_component=function(_,actions) return actions.aim end}}
for path,class in pairs(classes) do local value=class; package.preload[path]=function() return value end end
local function method(path,first,last)
    local file=assert(io.open(arg[2]..'/'..path..'.lua')); local source=file:read('*all'); file:close()
    local a=assert(source:find(first,1,true)); local b=assert(source:find(last,a,true))
    assert(loadstring(source:sub(a,b-1)))()
end
method(root..'action_aim_projectile','ActionAimProjectile.fixed_update =','\nActionAimProjectile._existing_unit =')
method(root..'action_throw_grenade','ActionThrowGrenade.start =','\nActionThrowGrenade.finish =')
method(root..'action_throw_grenade','ActionThrowGrenade.finish =','\nreturn ActionThrowGrenade')
method(effects,'AimProjectileEffects._update_trajectory =','\nAimProjectileEffects.update_first_person_mode =')
local body={position=10,rotation=20}
local template={keywords={'grenade'}}
local locomotion={integrator_parameters={radius=.4},trajectory_parameters={throw={aim_max_iterations=10}}}
local projectile={name='grenade',locomotion_template=locomotion}
local hooks,spawns,charges,rewind={},{},0,0
Managers={player={local_player=function() return {player_unit='local'} end},state={unit_spawner={
    spawn_network_unit=function(_,...) spawns[#spawns+1]={...} end}}}
Unit={world_position=function() return 900 end,world_rotation=function() return 800 end}
local native_position,native_rotation=Unit.world_position,Unit.world_rotation
ActionUtility={projectile_template=function() return projectile end}
Vo={throwing_item_event=function() end}
LagCompensation={rewind_ms=function() return rewind end}
locomotion_states={manual_physics='manual'}
AimProjectile={aim_parameters=function(position,rotation,look_rotation)
    return {position=position+1,rotation=look_rotation+2,direction=look_rotation+3,speed=30}
end,check_throw_position=function(position,look_position,_,radius)
    assert(position==look_position+1 and radius==.4); return position
end,get_spawn_parameters_from_current_aim=function(_,position,rotation)
    return position,rotation,rotation+3,40,50
end}
local integrated
ProjectileIntegrationData={mass_radius=function() return 4,.4 end,
    fill_integration_data=function(_,_,_,_,_,_,position,rotation,direction,speed,momentum)
        integrated={position,rotation,direction,speed,momentum}
    end}
MAX_NUMBER_OF_SPLINE=2
math.clamp=function(v,a,b) return math.max(a,math.min(b,v)) end
Vector3={zero=function() return 0 end}
PlayerUnitStatus={is_stunned=function() return false end}
dofile(arg[1]).install({hook=function(_,class,name,hook)
    hooks[class]=hooks[class] or {}; hooks[class][name]=hook
end},{target=function() return nil end},function() return body.position,body.rotation end)
local aim_settings={kind='aim_projectile',throw_type='throw'}
local action={_player_unit='local',_weapon_template=template,_first_person_component=body,
    _action_settings=aim_settings,_action_aim_projectile_component={momentum=77},
    _existing_unit=function() end,_locomotion_template=function() return locomotion end,
    _check_for_critical_strike=function() end,_set_haptic_trigger_template=function() end,
    _use_ability_charge=function() charges=charges+1 end,
    _weapon={item='item'},_wielded_slot='slot_grenade',_is_server=true,
    _side_system={side_by_unit={}},_critical_strike_component={is_active=false},
    _buff_extension={stat_buffs=function() return {extra_grenade_throw_chance=0} end}}
action._spawn_projectile=function(self)
    return hooks[ActionThrowGrenade]._spawn_projectile(ActionThrowGrenade._spawn_projectile,self)
end
hooks[ActionAimProjectile].fixed_update(ActionAimProjectile.fixed_update,action,.01,9,.4)
local cached=action._action_aim_projectile_component
assert(cached.position==11 and cached.rotation==22 and cached.direction==23 and cached.speed==30)
-- Move after aim was cached. Stock release refreshes origin/direction while
-- retaining cached rotation/speed/momentum; the online visual arc must match.
body.position,body.rotation=30,40
local effect={_is_local_unit=true,_first_person_unit='fp',_weapon_template=template,
    _weapon_action_component={},_weapon_actions={aim=aim_settings},_fx_sources={},
    _can_update_trajectory_spline=function() return true end,
    _trajectory_is_active_spline=function() return true end,
    _get_trajectory_data=function() return {},0,0,{} end,
    _set_trajectory_positions_spline=function(_,_,_,offset) assert(offset==0) end}
local trajectory={rotation=cached.rotation,speed=cached.speed,momentum=cached.momentum,
    projectile_locomotion_template=locomotion,throw_type='throw',radius=.4,mass=4,
    start_offset='cosmetic',arc_vfx_spawner_name='weapon'}
hooks[AimProjectileEffects]._update_trajectory(AimProjectileEffects._update_trajectory,effect,trajectory,.01,10)
assert(integrated[1]==31 and integrated[2]==22 and integrated[3]==43 and integrated[4]==30 and integrated[5]==77)
assert(Unit.world_position==native_position and Unit.world_rotation==native_rotation)
assert(trajectory.start_offset=='cosmetic' and action._first_person_component==body)
action._action_settings={kind='throw_grenade',throw_type='throw',spawn_at_time=.5,use_ability_charge=true}
ActionThrowGrenade.start(action,action._action_settings,10)
ActionThrowGrenade.fixed_update(action,.01,10.5,.5); assert(#spawns==0 and charges==0)
ActionThrowGrenade.fixed_update(action,.01,10.51,.51)
local spawned=assert(spawns[1])
assert(spawned[3]==31 and spawned[4]==22 and spawned[9]==43 and spawned[10]==30 and spawned[11]==77)
for i,index in ipairs({3,4,9,10,11}) do assert(spawned[index]==integrated[i],'Preview/release references disagree') end
ActionThrowGrenade.fixed_update(action,.01,10.6,.6); assert(#spawns==1 and charges==1)
-- Preserve stock half-rewind timing and client prediction ownership.
rewind=100
ActionThrowGrenade.start(action,action._action_settings,20)
ActionThrowGrenade.fixed_update(action,.01,20.44,.44); assert(#spawns==1)
ActionThrowGrenade.fixed_update(action,.01,20.46,.46); assert(#spawns==2 and charges==2)
action._is_server=false
ActionThrowGrenade.start(action,action._action_settings,30)
ActionThrowGrenade.fixed_update(action,.01,30.6,.6); assert(#spawns==2 and charges==3)
-- Expedition big/artillery grenades consume one unit and request removal when
-- no usable ammunition remains. Run the real Ammo helpers with one fixture
-- clip; stock action eligibility and the superclass finish remain outside this
-- contract. Never force an empty weapon through an assumed eligibility gate.
package.preload['scripts/settings/dialogue/dialogue_settings']=function()return {}end
NetworkConstants={ammunition_clip_array={max_size=1},clips_in_use={max_size=1}}
table.clear=function(t)for key in pairs(t)do t[key]=nil end end
math.sign=function(value)return value<0 and -1 or (value>0 and 1 or 0)end
Ammo=dofile(arg[2]..'/scripts/utilities/ammo.lua')
local finishes=0
ActionThrowGrenade.super={finish=function()finishes=finishes+1 end}
action._current_ammo=ActionThrowGrenade._current_ammo
rewind=0
local cases=0
for _,server in ipairs({true,false})do
    for _,initial in ipairs({1,2})do
        for _,released in ipairs({true,false})do
            local slot={current_ammunition_clip={initial},max_ammunition_clip={2},
                current_ammunition_clips_in_use={true}}
            action._inventory_slot_component=slot
            action._is_server=server
            action._action_settings={kind='throw_grenade',throw_type='throw',spawn_at_time=.22,
                ammunition_usage=1,remove_item_from_inventory=true,use_ability_charge=false}
            local before_spawns,before_charges=#spawns,charges
            ActionThrowGrenade.start(action,action._action_settings,40)
            local deadline=action._spawn_at_time
            ActionThrowGrenade.fixed_update(action,.01,deadline,.22)
            assert(#spawns==before_spawns and Ammo.current_ammo_in_clips(slot)==initial)
            assert(slot.last_ammunition_usage==nil)
            if released then
                ActionThrowGrenade.fixed_update(action,.001,deadline+.001,.221)
                assert(#spawns==before_spawns+(server and 1 or 0))
                assert(Ammo.current_ammo_in_clips(slot)==initial-1)
                assert(slot.last_ammunition_usage==deadline+.001)
                ActionThrowGrenade.fixed_update(action,.01,deadline+.01,.23)
                assert(Ammo.current_ammo_in_clips(slot)==initial-1,'ammunition consumed twice')
                assert(#spawns==before_spawns+(server and 1 or 0),'projectile spawned twice')
            end
            ActionThrowGrenade.finish(action,'fixture_end',nil,deadline+.01,.23)
            assert(not not slot.unequip_slot==(released and initial==1),'incorrect inventory removal request')
            assert(Ammo.current_ammo_in_clips(slot)==initial-(released and 1 or 0))
            assert(charges==before_charges,'ammo route also consumed ability charge')
            cases=cases+1
        end
    end
end
assert(finishes==cases)
print('PASS: '..cases..' stock grenade ammunition/finish cases; delay boundary, one consumption, last-charge removal request, pre-release finish and client/server ownership')
print('PASS: stock grenade aim, online preview/release references, delayed once-only spawn, charge and server ownership')
print('LIMIT: one fixture ammo clip; eligibility/superclass finish and trajectory/physics substituted, no real collision, inventory teardown, networking or worn acceptance')
