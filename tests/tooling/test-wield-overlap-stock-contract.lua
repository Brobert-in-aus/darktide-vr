-- Optional cached-source evidence: raw selector precedence, stock slot resolver
-- and action/extension eligibility. Inventory and ability state are fixtures.
local root,bindings_path=assert(arg[1]),assert(arg[2])
bit=require('bit')
local path=root..'/scripts/extension_systems/action_input/action_input_parser.lua'
local file=assert(io.open(path,'r'));local source=file:read('*a');file:close()
local first=assert(source:find('ActionInputParser._evaluate_input =',1,true))
local last=assert(source:find('\nActionInputParser._progress_input_sequence =',first,true))
local Parser={}
setfenv(assert(loadstring(source:sub(first,last-1),'@'..path)),
    setmetatable({ActionInputParser=Parser},{__index=_G}))()
local settings={vr_action_bind_device=8,vr_action_bind_cycle_pocketables=8,
    vr_action_bind_interact=0,vr_action_bind_reload=0}
local mod={get=function(_,key)return settings[key] end}
local mapper=dofile(bindings_path).install(mod)
local function press(control)
    mapper.sample(true,0,0,0,true,1,'combat')
    local pressed=mapper.sample(true,control,0,0,true,1,'combat')
    local values={}
    for _,binding in ipairs(mapper.bindings) do
        for _,name in ipairs(binding.pressed) do values[name]=bit.band(pressed,binding.mask)~=0 end
    end
    return values
end
local input=press(8)
assert(input.wield_5 and input.wield_3_gamepad)
local cycle={input='wield_3_gamepad',value=true}
local device={input='wield_5',value=true}
local parser=setmetatable({},{__index=Parser})
local valid,selected=parser:_evaluate_input({inputs={cycle,device}},input)
assert(valid and selected=='wield_3_gamepad')
valid,selected=parser:_evaluate_input({inputs={device,cycle}},input)
assert(valid and selected=='wield_5')
-- Independent controls remove the raw-input ordering ambiguity.
settings.vr_action_bind_cycle_pocketables=16
mod.on_setting_changed('vr_action_bind_cycle_pocketables')
input=press(8)
assert(input.wield_5 and not input.wield_3_gamepad)
valid,selected=parser:_evaluate_input({inputs={cycle,device}},input)
assert(valid and selected=='wield_5')
input=press(16)
assert(input.wield_3_gamepad and not input.wield_5)
valid,selected=parser:_evaluate_input({inputs={device,cycle}},input)
assert(valid and selected=='wield_3_gamepad')
print('wield_overlap_stock=pass simultaneous selectors follow array order; separate selectors are unambiguous')

local function read(relative)
    local f=assert(io.open(root..'/scripts/'..relative..'.lua','r'))
    local text=f:read('*a');f:close();return text
end
local function section(text,a,b)
    local first=assert(text:find(a,1,true),a)
    local last=assert(text:find(b,first+1,true),b)
    return text:sub(first,last-1)
end
-- These literal tables are the stock slot map, not a recreated VR slot policy.
local constants=assert(loadstring('return {'..section(read(
    'settings/player_character/player_character_constants'),
    '\tslot_configuration = {','\tplayer_interactions = {')..'}'))()
local Loadout={}
local environment=setmetatable({PlayerUnitVisualLoadout=Loadout,
    slot_configuration=constants.slot_configuration,
    gamepad_pocketable_wield_configuration=constants.gamepad_pocketable_wield_configuration,
    quick_wield_configuration=constants.quick_wield_configuration,
    scroll_wield_order=constants.scroll_wield_order},{__index=_G})
setfenv(assert(loadstring(section(read(
    'extension_systems/visual_loadout/utilities/player_unit_visual_loadout'),
    'PlayerUnitVisualLoadout.slot_name_from_wield_input =',
    'PlayerUnitVisualLoadout.wield_input_from_slot_name ='))),environment)()
local conditions=setfenv(assert(loadstring('return {'..section(read(
    'settings/equipment/weapon_action_handler_data'),
    '\tunwield = function','\tunwield_to_specific = function')..'}')),environment)()
local Weapon,Visual,Ability={},{},{}
environment.PlayerUnitWeaponExtension=Weapon
environment.PlayerUnitVisualLoadoutExtension=Visual
environment.PlayerUnitAbilityExtension=Ability
environment.ability_configuration=constants.ability_configuration
for _,method in ipairs({
    {'extension_systems/weapon/player_unit_weapon_extension','PlayerUnitWeaponExtension',
        'can_be_scroll_wielded'},
    {'extension_systems/visual_loadout/player_unit_visual_loadout_extension','PlayerUnitVisualLoadoutExtension',
        'slot_configuration'},
    {'extension_systems/ability/player_unit_ability_extension','PlayerUnitAbilityExtension',
        'can_be_scroll_wielded'},
}) do
    setfenv(assert(loadstring(section(read(method[1]),method[2]..'.can_wield =',
        method[2]..'.'..method[3]..' ='))),environment)()
end
local checked=0
-- Valid ownership states: a currently wielded pocketable is actually equipped.
local layouts={
    {'slot_primary',false,false,nil},
    {'slot_primary',true,false,'slot_pocketable'},
    {'slot_primary',false,true,'slot_pocketable_small'},
    {'slot_primary',true,true,'slot_pocketable'},
    {'slot_pocketable',true,false,'slot_pocketable_small'},
    {'slot_pocketable',true,true,'slot_pocketable_small'},
    {'slot_pocketable_small',false,true,'slot_pocketable'},
    {'slot_pocketable_small',true,true,'slot_pocketable'},
}
settings.vr_action_bind_cycle_pocketables=8
mod.on_setting_changed('vr_action_bind_cycle_pocketables')
input=press(8)
assert(input.wield_5 and input.wield_3_gamepad)
for _,layout in ipairs(layouts) do
    for _,has_device in ipairs({false,true}) do
        local inventory={wielded_slot=layout[1],
            slot_pocketable=layout[2] and 'large' or 'not_equipped',
            slot_pocketable_small=layout[3] and 'small' or 'not_equipped',
            slot_device=has_device and 'device' or 'not_equipped'}
        assert(Loadout.slot_name_from_wield_input('wield_3_gamepad',inventory)==layout[4])
        assert(Loadout.slot_name_from_wield_input('wield_5',inventory)=='slot_device')
        for _,selectors in ipairs({{cycle,device},{device,cycle}}) do
            local valid,selected=parser:_evaluate_input({inputs=selectors},input)
            assert(valid)
            local expected=selected=='wield_5' and 'slot_device' or layout[4]
            local visits={}
            local weapons={}
            for _,slot in ipairs({'slot_pocketable','slot_pocketable_small','slot_device'}) do
                if inventory[slot]~='not_equipped' then weapons[slot]={weapon_template={}} end
            end
            local function extension(label,class,state)
                state.can_wield=function(self,slot)
                    visits[#visits+1]={label=label,slot=slot}
                    assert(slot==expected,'Stock condition fell back to another selector')
                    return class.can_wield(self,slot)
                end
                return state
            end
            local admitted=conditions.unwield({}, {inventory_read_component=inventory,
                weapon_extension=extension('weapon',Weapon,{_weapons=weapons}),
                visual_loadout_extension=extension('visual',Visual,{_slot_configuration=constants.slot_configuration,
                    _inventory_component=inventory,UNEQUIPPED_SLOT='not_equipped'}),
                ability_extension=extension('ability',Ability,{_equipped_abilities={}})},selected,0,0)
            local available=expected~=nil and inventory[expected]~='not_equipped'
            assert(admitted==available and #visits==(available and 3 or 1))
            assert(visits[1].label=='weapon')
            if available then assert(visits[2].label=='visual' and visits[3].label=='ability') end
            checked=checked+1
        end
    end
end
assert(checked==32)
-- Actual extension guards retain ownership and ability policy beyond presence.
assert(not Weapon.can_wield({_weapons={slot_device={}}},'slot_device'))
assert(not Weapon.can_wield({_weapons={slot_device={weapon_template={not_player_wieldable=true}}}},'slot_device'))
assert(not Visual.can_wield({_slot_configuration=constants.slot_configuration,
    _inventory_component={wielded_slot='slot_device',slot_device='device'},
    UNEQUIPPED_SLOT='not_equipped'},'slot_device'))
for _,depleted in ipairs({false,true}) do
    local calls=0
    local ability={_equipped_abilities={pocketable_ability={can_be_wielded_when_depleted=depleted}},
        can_use_ability=function(_,kind)assert(kind=='pocketable_ability');calls=calls+1;return false end}
    assert(not not Ability.can_wield(ability,'slot_pocketable_small')==depleted and calls==1)
end
-- Each eligibility owner can veto independently; later checks are not called.
for veto=1,3 do
    local visits=0
    local function extension()
        return {can_wield=function(_,slot)
            assert(slot=='slot_device');visits=visits+1;return visits~=veto
        end}
    end
    assert(not conditions.unwield({}, {inventory_read_component={wielded_slot='slot_primary'},
        weapon_extension=extension(),visual_loadout_extension=extension(),
        ability_extension=extension()},'wield_5',0,0))
    assert(visits==veto)
end
print('wield_slot_stock=pass 32 layout/device/order cases; real weapon/visual/ability guards; 3 dispatch vetoes; no selector fallback')
print('LIMIT: constructed inventory/weapon/ability state and can_use_ability result; no action queue, inventory mutation, weapon execution, network or worn acceptance')
