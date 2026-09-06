-- Optional source-snapshot integration check. Pass the mod module followed by
-- the local Darktide source root. This executes stock methods with isolated
-- engine stubs; no game, network, real controller or headset is involved.
local root='scripts/extension_systems/weapon/actions/'
local aim_class,throw_class={},{}
local hooks={}
local paths={
    [root..'action_aim_projectile']=aim_class,
    [root..'action_throw_grenade']={},
    ['scripts/extension_systems/visual_loadout/wieldable_slot_scripts/aim_projectile_effects']={},
    ['scripts/extension_systems/visual_loadout/wieldable_slot_scripts/aim_luggable_effects']={},
    ['scripts/utilities/action/action']={},
}
for path,value in pairs(paths) do
    local class=value; package.preload[path]=function() return class end
end
local function method(path,start_marker,end_marker)
    local file=assert(io.open(arg[2]..'/'..path..'.lua','r'))
    local text=file:read('*all'); file:close()
    local first=assert(text:find(start_marker,1,true),start_marker)
    local last=assert(text:find(end_marker,first, true),end_marker)
    assert(loadstring(text:sub(first,last-1)))()
end
ActionAimProjectile,ActionThrowLuggable=aim_class,throw_class
method(root..'action_aim_projectile','ActionAimProjectile.fixed_update =',
    '\nActionAimProjectile._existing_unit =')
method(root..'action_throw_luggable','ActionThrowLuggable._throw_unit =',
    '\nreturn ActionThrowLuggable')
method(root..'action_throw_luggable','ActionThrowLuggable.fixed_update =',
    '\nActionThrowLuggable._throw_unit =')
local dropped,physical,unwielded=0,{},0
local original={position=1,rotation=2}
local locomotion={}
local physics={switch_to_manual_physics=function(_,...) physical[#physical+1]={...} end}
ScriptUnit={extension=function(unit,system)
    assert(unit=='item' and system=='locomotion_system'); return physics
end}
Unit={get_data=function() return nil end}
Pickups={by_name={}}
Managers={player={local_player=function() return {player_unit='local'} end},
    state={extension={system=function(_,name)
        assert(name=='pickup_system'); return {dropped=function(_,unit)
            assert(unit=='item'); dropped=dropped+1
        end}
    end}}}
local drop_count=0
Luggable={enable_physics=function(fp,lc,unit)
    assert(fp==original and lc==locomotion and unit=='item','Stock drop pose changed')
    drop_count=drop_count+1
end}
PlayerUnitVisualLoadout={unequip_item_from_slot=function() unwielded=unwielded+1 end,
    wield_slot=function() end}
AimProjectile={aim_parameters=function(position,rotation,look,template,kind,time)
    assert(rotation==look and template=='physics' and kind=='throw' and time==.4)
    return {position=position+1,rotation=rotation+2,direction=rotation+3,speed=30}
end,check_throw_position=function(position,look,template,radius,world)
    assert(position==look+1 and radius==.4 and world=='world'); return position
end}
ProjectileIntegrationData={mass_radius=function(template,extension)
    assert(template=='physics' and extension==physics); return 4,.4
end}
local hand_position,hand_rotation=100,200
dofile(arg[1]).install({hook=function(_,class,name,hook)
    hooks[class]=hooks[class] or {}; hooks[class][name]=hook
end},{target=function() return hand_position,hand_rotation end})
local action={_player_unit='local',_weapon_template={name='luggable',keywords={'luggable'}},
    _action_settings={kind='aim_projectile',throw_type='throw'},
    _first_person_component=original,_locomotion_component=locomotion,
    _physics_world='world',_action_aim_projectile_component={momentum=77},
    _existing_unit=function() return 'item',physics end,
    _locomotion_template=function() return 'physics' end}
hooks[aim_class].fixed_update(aim_class.fixed_update,action,.01,42,.4)
local cached=action._action_aim_projectile_component
assert(cached.position==101 and cached.rotation==202 and cached.direction==203)
assert(cached.speed==30 and cached.momentum==77 and action._first_person_component==original)
-- The actual stock delayed release consumes the captured aim once; later
-- hand movement must not silently redefine the game's release semantics.
hand_position,hand_rotation=900,800
action._is_server=true
action._player={remote=false}
action._action_settings={kind='throw_luggable',throw_type='throw',throw_time=.32,total_time=.5}
action._weapon_action_component={time_scale=1}
action._action_throw_luggable_component={thrown=false,slot_to_wield='slot_primary'}
action._inventory_slot_component={existing_unit_3p='item'}
action._inventory_component={wielded_slot='slot_luggable'}
action._throw_unit=throw_class._throw_unit
throw_class.fixed_update(action,.01,42,.1)
assert(#physical==0)
throw_class.fixed_update(action,.01,42,.32)
local values=assert(physical[1])
assert(values[1]==101 and values[2]==202 and values[3]==203 and values[4]==30 and values[5]==77)
throw_class.fixed_update(action,.01,42,.4)
assert(#physical==1 and dropped==1 and unwielded==0)
throw_class.fixed_update(action,.01,42,.5)
assert(unwielded==1 and #physical==1)
throw_class._throw_unit(action,'item','drop')
assert(drop_count==1 and #physical==1)
action._is_server=false
throw_class._throw_unit(action,'item','throw')
throw_class._throw_unit(action,'item','drop')
assert(drop_count==1 and #physical==1 and dropped==2,'Client applied luggable physics')
print('luggable_stock_contract=pass stock_aim collision_parameters cached_delayed_release once_only server_authority stock_drop')
