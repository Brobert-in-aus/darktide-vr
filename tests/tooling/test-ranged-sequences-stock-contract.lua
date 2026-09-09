-- Optional cached-source contract: real input formatter, parser, hierarchy and
-- queue with real VR mapper output. No action execution, networking or rendering.
local root,bindings_path=assert(arg[1]),assert(arg[2])
local profile={}
if arg[3] then profile=dofile(arg[3]);assert(type(profile)=='table','invalid saved binding table') end
bit=require('bit')
local Bindings=dofile(bindings_path)
local function read(path)
    local f=assert(io.open(root..'/scripts/'..path..'.lua','rb'))
    local value=f:read('*a');f:close();return value
end
local function section(text,first,last)
    local a=assert(text:find(first,1,true),first)
    local b=assert(text:find(last,a+1,true),last)
    return text:sub(a,b-1)
end
table.keys=function(t)local keys={}for k in pairs(t)do keys[#keys+1]=k end return keys end
table.add_missing=function(target,source)for k,v in pairs(source)do if target[k]==nil then target[k]=v end end end
local modules={}
local env=setmetatable({Script={new_array=function()return {}end},
    NetworkConstants={fixed_time_offset_unset=-1},class=function()return {}end,
    settings=function(_,data)return data end,
    require=function(name)return assert(modules[name],'unexpected dependency '..name)end,
    Log={error=function(...)error('unexpected formatter error')end}}, {__index=_G})
local function load(name)
    local result=setfenv(assert(loadstring(read(name),name)),env)()
    modules['scripts/'..name]=result
    return result
end
local Hierarchy=load('utilities/action/action_input_hierarchy')
-- Wield arbitration is covered separately. Reject a selected profile that
-- activates any wield route during these ranged-only scenarios.
local wield_keys={'quick_wield','wield_scroll_down','wield_scroll_up',
    'wield_1','wield_2','wield_3','wield_3_gamepad','wield_4','wield_5'}
modules['scripts/settings/player_character/player_character_constants']={wield_inputs={}}
modules['scripts/extension_systems/character_state_machine/character_states/utilities/sprint']={}
load('settings/action_input_formatter/action_input_formatter_settings')
load('extension_systems/action_input/action_input_formatter')
local Parser=load('extension_systems/action_input/action_input_parser')
local base_source=read('settings/equipment/weapon_templates/base_template_settings')
local base_env=setmetatable({base_template_settings={},wield_inputs={}}, {__index=_G})
setfenv(assert(loadstring(section(base_source,'base_template_settings.combat_ability_action_inputs =',
    'base_template_settings.combat_ability_actions =')..section(base_source,
    'base_template_settings.action_input_hierarchy =','base_template_settings.generate_grenade_ability_chain_actions ='))),base_env)()
local function template(path)
    local e=setmetatable({weapon_template={},wield_inputs={},BaseTemplateSettings=base_env.base_template_settings,
        ActionInputHierarchy=Hierarchy},{__index=_G})
    setfenv(assert(loadstring(section(read('settings/equipment/weapon_templates/'..path),
        'weapon_template.action_inputs =','weapon_template.actions ='))),e)()
    return e.weapon_template
end
local templates={plasma=template('plasma_rifles/plasmagun_p1_m1'),
    shotgun=template('shotguns/shotgun_p1_m1'),staff=template('force_staffs/forcestaff_p4_m1')}
local function generated_template(kind)
    local e=setmetatable({base_template={},wield_inputs={},BaseTemplateSettings=base_env.base_template_settings,
        ActionInputHierarchy=Hierarchy},{__index=_G})
    local source=read('settings/equipment/weapon_templates/weapon_template_generators/'..kind..'_weapon_template_generator')
    setfenv(assert(loadstring(section(source,'base_template.action_inputs =','base_template.actions ='))),e)()
    return e.base_template
end
local grenade_scenarios={'grenade','grenade_handleless'}
for _,kind in ipairs(grenade_scenarios)do templates[kind]=generated_template(kind)end
for _,variant in ipairs({
    {'expeditions_big_grenade','grenades/expeditions_big_grenade','weapon_template.breed_anim_state_machine_3p ='},
    {'expedition_airstrike','pocketables/expedition_grenade_airstrike_pocketable','weapon_template.breed_anim_state_machine_3p ='},
    {'expedition_artillery','pocketables/expedition_grenade_artillery_strike_pocketable','weapon_template.breed_anim_state_machine_3p ='},
    {'expedition_valkyrie','pocketables/expedition_grenade_valkyrie_hover_pocketable','local actions = weapon_template.actions'},
})do
    local value=generated_template('grenade')
    local e=setmetatable({weapon_template=value},{__index=_G})
    local source=read('settings/equipment/weapon_templates/'..variant[2])
    setfenv(assert(loadstring(section(source,'weapon_template.action_input_hierarchy =',variant[3]))),e)()
    templates[variant[1]]=value
    grenade_scenarios[#grenade_scenarios+1]=variant[1]
end
templates.quick_flash=generated_template('grenade_handleless')
do
    local source=read('settings/equipment/weapon_templates/grenades/quick_flash_grenade')
    local e=setmetatable({weapon_template=templates.quick_flash},{__index=_G})
    setfenv(assert(loadstring(section(source,'local auto_input =','weapon_template.smart_targeting_template ='))),e)()
end
-- Execute the five actual syringe consumers and their complete generator.
-- Resource/targeting tables are placeholders: only input routing and whether
-- the generator creates gift actions are inspected, not target eligibility.
local syringe_base=setmetatable({actions={}},{__index=base_env.base_template_settings})
local syringe_env=setmetatable({base_template_settings=syringe_base},{__index=_G})
setfenv(assert(loadstring(section(base_source,'base_template_settings.generate_grenade_ability_chain_actions =',
    'base_template_settings.generate_action_overrides ='))),syringe_env)()
modules['scripts/settings/equipment/weapon_templates/base_template_settings']=syringe_base
modules['scripts/settings/equipment/footstep/footstep_intervals_templates']={}
modules['scripts/settings/equipment/weapon_templates/pocketables/pockatables_utils']={}
modules['scripts/settings/equipment/smart_targeting_templates']={}
modules['scripts/utilities/breed']={}
modules['scripts/utilities/attack/player_unit_status']={}
load('settings/equipment/weapon_templates/weapon_template_generators/syringe_pocketable_weapon_template_generator')
local syringe_names={}
for _,variant in ipairs({'ability_boost','corruption','power_boost','speed_boost','broker'}) do
    local name='syringe_'..variant
    templates[name]=load('settings/equipment/weapon_templates/pocketables/'..name..'_pocketable')
    if variant~='broker' then
        syringe_names[#syringe_names+1]=name
        assert(templates[name].actions.action_aim_give and templates[name].actions.action_give)
    else
        assert(not templates[name].actions.action_aim_give and not templates[name].actions.action_give)
    end
end
local steps=0
local function scenario(name,toggle)
    local mapper=Bindings.install({get=function(_,key)return profile[key]end})
    mapper.sample(true,0,0,0,true,1,'combat')
    local parser=setmetatable({_ring_buffer_index=1,_sequences={},_action_input_queue={},_hierarchy_position={},
        _action_component={template_name=name},_input_queue_first_entry_became_first_entry_t=0},{__index=Parser})
    parser:_format_and_initialize_action_inputs('weapon',{[name]=templates[name]},
        parser._sequences,parser._action_input_queue,parser._hierarchy_position)
    local sequences,queue,position=parser._sequences[1],parser._action_input_queue[1],parser._hierarchy_position[1]
    parser:_prepare_child_sequences(templates[name].action_input_hierarchy,sequences,0,parser._ACTION_INPUT_NETWORK_LOOKUP[name])
    local raw={}
    parser._input_extension={get=function(_,key)return raw[key] or false end}
    local previous_t=0
    return function(t,actions,expected,enabled,consume)
        local physical,x,y=0,0,0
        for _,action in ipairs(actions or {})do
            local selected=assert(mapper.controls_for_action(action)[1],'unmapped '..action)
            for _,control in ipairs(Bindings.controls)do if control.id==selected then
                if control.axis=='x' then assert(x==0 or x==control.sign);x=control.sign
                elseif control.axis=='y' then assert(y==0 or y==control.sign);y=control.sign
                else physical=bit.bor(physical,control.bit)end
            end end
        end
        if x~=0 and y~=0 then x=x/math.sqrt(2);y=y/math.sqrt(2)end
        local pressed,held,released=mapper.sample(enabled~=false,physical,x,y,true,1,'combat')
        raw={toggle_ads=toggle}
        for _,binding in ipairs(Bindings.actions)do
            for _,phase in ipairs({{'pressed',pressed},{'held',held},{'released',released}})do
                for _,key in ipairs(binding[phase[1]] or {})do raw[key]=bit.band(phase[2],binding.mask)~=0 end
            end
        end
        for _,key in ipairs(wield_keys)do
            assert(not raw[key], 'ranged-only scenario activated excluded wield route '..key)
        end
        parser:_update_sequences(t-previous_t,t,name,position,sequences,queue)
        previous_t=t
        local result=parser:peek_next_input()
        assert(result==expected,name..' t='..t..' expected='..tostring(expected)..' got='..tostring(result))
        if consume~=false then
            if result then parser:consume_next_input(t)end
            assert(parser:peek_next_input()==nil,'unexpected additional queued input')
        end
        steps=steps+1
    end
end
for _,name in ipairs({'plasma','shotgun'})do
    local aim=name=='plasma' and 'brace' or 'zoom'
    for _,toggle in ipairs({false,true})do
        local step=scenario(name,toggle)
        step(.01,{'alternate'},aim)
        step(.02,{'alternate'},nil)
        if toggle then
            step(.03,{},nil);step(.04,{'alternate'},aim..'_release');step(.05,{},nil)
        else step(.03,{},aim..'_release')end
        step(.06,{'reload'},'reload')
        step(.07,{'reload'},nil)
        step(.08,{},nil)
    end
end
do
    local step=scenario('plasma',false)
    step(.01,{'primary'},'shoot_charge')
    step(.02,{'primary','alternate'},'shoot_cancel')
    step(.03,{},nil)
end
do
    local step=scenario('staff',false)
    step(.01,{'alternate'},'charge')
    step(.02,{'alternate'},nil)
    step(.03,{'alternate','primary'},'shoot_charged')
    step(.04,{},nil)
    step(.05,{'alternate'},'charge')
    step(.06,{},'charge_release')
end
do
    local step=scenario('staff',false)
    step(.01,{'alternate'},'charge')
    step(.02,{'alternate','reload'},'vent')
    step(.03,{'reload'},nil)
    step(.04,{},'vent_release')
end
do
    local step=scenario('staff',false)
    step(.01,{'alternate'},'charge')
    step(.02,{'alternate'},'charge_release',false)
    step(.03,{'alternate'},nil)
    step(.04,{},nil)
    step(.05,{'alternate'},'charge')
    step(.06,{},'charge_release')
end
for _,name in ipairs(grenade_scenarios)do
    -- Stock may not consume the aim input immediately. Cancellation must
    -- replace that pending request, rather than sit behind it in the queue.
    local pending=scenario(name,false)
    pending(.01,{'primary'},'aim_hold',true,false)
    pending(.02,{'primary','alternate'},'block_cancel')
    local step=scenario(name,false)
    step(.01,{'primary'},'aim_hold')
    step(.02,{'primary'},nil)
    step(.03,{},'aim_released')
    step=scenario(name,false)
    step(.01,{'primary'},'aim_hold')
    step(.02,{'primary','alternate'},'block_cancel')
    step(.03,{},nil)
    step(.04,{'primary'},'aim_hold')
    step(.05,{},'aim_released')
    step=scenario(name,false)
    step(.01,{'alternate'},'short_hand_aim_hold')
    step(.02,{'alternate','primary'},'short_hand_throw')
    step(.03,{},nil)
    step(.04,{'alternate'},'short_hand_aim_hold')
    step(.05,{},'short_hand_aim_released')
    step=scenario(name,false)
    step(.01,{'primary'},'aim_hold')
    step(.02,{'primary'},'aim_released',false)
    step(.03,{'primary'},nil)
    step(.04,{},nil)
    step(.05,{'primary'},'aim_hold')
    step(.06,{},'aim_released')
end
for _,enabled in ipairs({true,false})do
    local step=scenario('quick_flash',false)
    step(.01,{},'aim_hold',enabled)
    step(.02,{},'aim_released',enabled)
end
for _,name in ipairs(syringe_names) do
    local step=scenario(name,false)
    step(.01,{'primary'},'use_self')
    step(.02,{'primary'},nil)
    step(.03,{},nil)
    step=scenario(name,false)
    step(.01,{'alternate'},'aim')
    step(.02,{'alternate','primary'},'use_ally')
    step(.03,{},nil)
    step=scenario(name,false)
    step(.01,{'alternate'},'aim')
    step(.02,{},'aim_release')
    step=scenario(name,false)
    step(.01,{'special'},'special_action')
    step(.02,{'special'},'aim_give')
    step(.03,{},'aim_give_release')
    step=scenario(name,false)
    step(.01,{'alternate'},'aim')
    step(.02,{'alternate'},'aim_release',false)
    step(.03,{'alternate'},nil)
    step(.04,{},nil)
    step(.05,{'alternate'},'aim')
    step(.06,{},'aim_release')
    step=scenario(name,false)
    step(.01,{'special'},'special_action')
    step(.02,{'special'},'aim_give')
    step(.03,{'special'},'aim_give_release',false)
    step(.04,{'special'},nil)
    step(.05,{},nil)
    step(.06,{'special'},'special_action')
    step(.07,{'special'},'aim_give')
    step(.08,{},'aim_give_release')
end
-- Broker's actual consumer enables automatic self-use. A neutral/disabled VR
-- source can still satisfy that stock input; no gift action is generated.
for _,enabled in ipairs({true,false}) do
    local step=scenario('syringe_broker',false)
    step(.01,{},'use_self',enabled)
end
print('PASS stock combat sequences: '..steps..' observed steps, ranged/grenade variants, five syringe consumers, automatic inputs and tracking-loss rearm')
print('LIMIT: ranged-only stock input hierarchy/queue; immediate consumption except pending-aim cancellation, no wield arbitration, buffer aging, action execution, damage, networking or live acceptance')
