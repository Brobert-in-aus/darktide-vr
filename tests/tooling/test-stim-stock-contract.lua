-- Optional cached-source syringe lifecycle contract. Effects and unit state
-- are doubles; no game, buff, item, notification or network call is made.
local root=assert(arg[1])
local function source(path)
    local f=assert(io.open(root..'/scripts/'..path..'.lua','r'))
    local text=f:read('*a');f:close();return text
end
local function section(text,first,last)
    local a=assert(text:find(first,1,true),first)
    local b=assert(text:find(last,a+1,true),last)
    return text:sub(a,b-1)
end
local player,recipient={player=true,health=.5},{player=true,health=.5}
local events={}
local function record(name,...)events[#events+1]={name,...}end
local function count(name)
    local n=0;for _,event in ipairs(events)do if event[1]==name then n=n+1 end end;return n
end
local owner_buff={request_proc_event_param_table=function()return {}end,
    add_proc_event=function(_,kind)assert(kind=='syringe_used');record('proc')end}
local function extension(unit,name)
    if not unit then return nil end
    if name=='unit_data_system' then return {read_component=function(_,component)
        assert(component=='character_state');return {disabled=unit.disabled}
    end} end
    if name=='health_system' then
        if unit.no_health then return nil end
        return {current_health_percent=function()return unit.health end}
    end
    if name=='buff_system' then
        if unit.no_buff then return nil end
        return {add_internally_controlled_buff=function(_,buff,t,key,owner)
            assert(key=='owner_unit' and owner==player);record('buff',unit,buff,t)
        end}
    end
    if name=='fx_system' then return {trigger_exclusive_wwise_event=function()record('sound',unit)end} end
    error('unexpected extension '..name)
end
local dependencies={
    ['scripts/utilities/breed']={unit_breed_or_nil=function(unit)return unit end,
        is_player=function(unit)return unit and unit.player end},
    ['scripts/utilities/attack/player_unit_status']={is_disabled=function(state)return state.disabled end},
}
local env=setmetatable({
    ScriptUnit={has_extension=extension,extension=function(unit,name)
        if unit==player and name=='buff_system' then return owner_buff end
        return assert(extension(unit,name))
    end},
    Managers={state={game_session={fixed_time_step=1/60}},player={player_by_unit=function()return nil end}},
    ALIVE={[player]=true,[recipient]=true},
    math=setmetatable({round=function(value)return math.floor(value+.5)end},{__index=math}),
    require=function(path)return assert(dependencies[path],'unexpected dependency '..path)end,
}, {__index=_G})
env.FixedFrame=setfenv(assert(loadstring(source('utilities/fixed_frame'))),env)()
env.ActionUtility={}
setfenv(assert(loadstring(section(source('extension_systems/weapon/actions/utilities/action_utility'),
    'local EPSILON =','ActionUtility.projectile_template ='))),env)()
local Action={super={start=function()end,finish=function()end}}
env.ActionUseSyringe=Action
env.special_rules={buff_target_buff_name_override_one='one',buff_target_buff_name_override_two='two'}
env.BuffSettings={proc_events={on_syringe_used='syringe_used'}}
env.PlayerAssistNotifications={show_notification=function(target,owner)
    assert(owner==player);record('assist',target)
end}
env.PlayerUnitVisualLoadout={wield_previous_weapon_slot=function()record('wield')end}
env.Vo={play_combat_ability_event=function()record('voice')end}
setfenv(assert(loadstring(section(source('extension_systems/weapon/actions/action_use_syringe'),
    'ActionUseSyringe.start =','ActionUseSyringe._report_use_to_stat_system ='))),env)()
local generator_source=source('settings/equipment/weapon_templates/weapon_template_generators/syringe_pocketable_weapon_template_generator')
local settings_source='return {'..section(generator_source,'\t\taction_use_self = {',
    '\t\taction_flair = {')..section(generator_source,'\t\taction_use_ally = {',
    '\t\taction_inspect_3p = {')..'}'
dependencies['scripts/settings/equipment/weapon_templates/weapon_template_generators/syringe_pocketable_weapon_template_generator']=
    function(buff,validate,icon,pickup,assist,voice,consume,givable,charge)
        local settings_env=setmetatable({buff_name=buff,validate_target_func=validate,
            consume_on_use=consume,use_ability_charge=charge,assist_notification_type=assist},{__index=env})
        return {actions=setfenv(assert(loadstring(settings_source)),settings_env)(),keywords={}}
    end
local templates={}
for _,name in ipairs({'ability_boost','corruption','power_boost','speed_boost','broker'})do
    templates[name]=setfenv(assert(loadstring(source('settings/equipment/weapon_templates/pocketables/syringe_'..name..'_pocketable'))),env)()
end
local function action_for(settings,server,scale)
    local target_component={target_unit_1=recipient,target_unit_2=recipient,target_unit_3=recipient}
    local action=setmetatable({_player_unit=player,_action_settings=settings,
        _is_server=server,_unit_data_extension={is_resimulating=false},
        _weapon_action_component={time_scale=scale},_action_module_target_finder_component=target_component,
        _inventory_slot_component={},_inventory_component={},
        _talent_extension={has_special_rule=function()return false end},
        trigger_anim_event=function()record('start_anim')end,
        _use_ability_charge=function(_,value)assert(value==1);record('charge')end,
        _report_use_to_stat_system=function(_,target)record('stat',target)end,
        _play_hit_react_anim=function(_,_,target)record('reaction',target)end}, {__index=Action})
    action:start(settings,10,scale,{})
    return action,target_component
end
local cases=0
for name,template in pairs(templates)do
    for _,kind in ipairs({'action_use_self','action_use_ally'})do
        for _,server in ipairs({false,true})do
            for _,scale in ipairs({1,1.3})do
                local settings=template.actions[kind]
                local action,targets=action_for(settings,server,scale)
                local target=settings.self_use and player or recipient
                local trigger=env.FixedFrame.clamp_to_fixed_time(settings.use_time/scale)
                events={}
                action:fixed_update(1/60,10+trigger-1/60,trigger-1/60)
                assert(not action._did_use and #events==0,'Syringe used before stock trigger')
                action:fixed_update(1/60,10+trigger,trigger)
                assert(action._did_use and count('buff')==((server or settings.self_use) and 1 or 0))
                assert(count('charge')==(settings.use_ability_charge and 1 or 0))
                assert(count('assist')==((server and settings.assist_notification_type) and 1 or 0))
                assert(count('proc')==1 and count('stat')==1)
                assert(count('reaction')==((server or settings.self_use) and 1 or 0))
                for _,event in ipairs(events)do
                    if event[1]=='buff' then assert(event[2]==target and event[3]==settings.buff_name)end
                end
                assert(not targets.target_unit_1 and not targets.target_unit_2 and not targets.target_unit_3)
                local event_count=#events
                action:fixed_update(1/60,10+trigger+1/60,trigger+1/60)
                assert(#events==event_count,'Syringe applied twice after trigger')
                action._unit_data_extension.is_resimulating=true
                action:fixed_update(1/60,12,settings.total_time)
                assert(#events==event_count,'Replay repeated syringe cleanup/effects')
                action._unit_data_extension.is_resimulating=false
                action:fixed_update(1/60,12,settings.total_time)
                assert(count('wield')==1)
                action:finish('action_complete',nil,12,settings.total_time)
                assert(action._inventory_slot_component.unequip_slot==(settings.remove_item_from_inventory and true or nil))
                assert(action._inventory_slot_component.unwield_slot==(not settings.remove_item_from_inventory and true or nil))
                cases=cases+1
            end
        end
    end
end
assert(cases==40)
for name,template in pairs(templates)do
    for _,failure in ipairs({'missing','not_player','disabled','resimulation','interrupted'})do
        local action,targets=action_for(template.actions.action_use_ally,true,1)
        recipient.player=failure~='not_player';recipient.disabled=failure=='disabled'
        if failure=='missing' then targets.target_unit_1=nil end
        action._unit_data_extension.is_resimulating=failure=='resimulation'
        events={}
        if failure~='interrupted' then action:fixed_update(1/60,10.1,.1)end
        assert(not action._did_use and #events==0,name..' '..failure)
        action:finish('interrupted',nil,10.1,.1)
        assert(not action._inventory_slot_component.unequip_slot and not action._inventory_slot_component.unwield_slot)
        assert(not targets.target_unit_1 and not targets.target_unit_2 and not targets.target_unit_3)
        recipient.player,recipient.disabled=true,false
    end
end
for _,failure in ipairs({'full_health','missing_health'})do
    recipient.health=1;recipient.no_health=failure=='missing_health'
    local action=action_for(templates.corruption.actions.action_use_ally,true,1)
    events={};action:fixed_update(1/60,10.1,.1)
    assert(not action._did_use and #events==0,'Corruption syringe accepted invalid health state')
    action:finish('interrupted',nil,10.1,.1)
    assert(not action._inventory_slot_component.unequip_slot)
end
recipient.health,recipient.no_health=.5,false
do
    local settings=templates.speed_boost.actions.action_use_ally
    local action,targets=action_for(settings,true,1)
    targets.target_unit_1=nil;events={}
    assert(not action:fixed_update(1/60,11,settings.minimum_time))
    assert(action:fixed_update(1/60,11,settings.minimum_time+1/60)==true)
    action:finish('action_complete',nil,11,settings.minimum_time+1/60)
    assert(not action._did_use and not action._inventory_slot_component.unequip_slot and #events==0)
end
print('stim_stock=pass 40 variant/self/ally/client/server/time-scale cases, 25 interruption/target/replay cases, 2 corruption-health guards')
print('stim_timing=pass actual fixed-frame clamp at constructed 60Hz, post-use replay suppression, targetless minimum-time exit')
print('LIMIT: constructed units/state; effect, notification, stats, superclass and inventory calls are doubles; no input-to-action integration, live buffs, networking or worn acceptance')
