-- Actual stock parser, formatter and melee hierarchy. Engine services and
-- unrelated common-action inputs are fixtures; no action execution or network.
local root=assert(arg[1])
local bindings_path=assert(arg[2])
local cache={}
local raw={}
local function clone(value)
    if type(value)~='table' then return value end
    local result={}; for k,v in pairs(value) do result[k]=clone(v) end; return result
end
local env=setmetatable({}, {__index=_G})
env.Script={new_array=function() return {} end}
env.settings=function(_,value) return value end
env.NetworkConstants={fixed_frame_offset_start_t_5bit={min=-16},fixed_time_offset_unset=-1000}
env.table=setmetatable({clone=clone,keys=function(t) local out={}; for k in pairs(t) do out[#out+1]=k end; return out end,
    add_missing=function(dest,src) for k,v in pairs(src) do if dest[k]==nil then dest[k]=v end end end}, {__index=table})
env.class=function()
    local class={}; class.__index=class
    function class:new(...) local self=setmetatable({},class); self:init(...); return self end
    return class
end
env.ferror=function(format,...) error(string.format(format,...)) end
env.Log={info=function() end,error=function(_,message) error(message) end}
env.Managers={state={game_session={fixed_time_step=.01},player_unit_spawn={owner=function()
    return {is_human_controlled=function() return true end}
end}}}
env.ScriptUnit={extension=function(_,name)
    if name=='input_system' then return {get=function(_,key) return raw[key] or false end} end
    assert(name=='unit_data_system')
    return {read_component=function() return {cooldown=0} end}
end}
cache['scripts/settings/player_character/player_character_constants']={wield_inputs={}}
cache['scripts/extension_systems/character_state_machine/character_states/utilities/sprint']={is_sprinting=function() return false end}
local common={action_inputs={},action_input_hierarchy={}}
for _,name in ipairs({'wield','combat_ability','grenade_ability'}) do
    common.action_inputs[name]={input_sequence={{input='fixture_never',value=true}}}
end
cache['scripts/settings/equipment/weapon_templates/base_template_settings']=common
env.require=function(path)
    if cache[path] then return cache[path] end
    local chunk=assert(loadfile(root..'/'..path..'.lua'))
    local result=setfenv(chunk,env)(); cache[path]=result; return result
end
local template=env.require('scripts/settings/equipment/weapon_templates/default_melee_action_input_setup')
local Parser=env.require('scripts/extension_systems/action_input/action_input_parser')
bit=require('bit')
local Bindings=dofile(bindings_path)
local function session(selected_template)
    raw={}
    local mapper=Bindings.install({get=function() end})
    local parser=Parser:new('player','weapon_action',{template_name='melee'},
        {action_input_type='weapon',templates={melee=selected_template or template}},1)
    local frame=0
    local events={}
    local function tick(mask,consume)
        frame=frame+1
        local pressed,held,released=mapper.sample(true,mask,0,0,true,1,'combat')
        raw={}
        for _,binding in ipairs(mapper.bindings) do
            for _,pair in ipairs({{binding.pressed,pressed},{binding.held,held},{binding.released,released}}) do
                for _,name in ipairs(pair[1]) do raw[name]=bit.band(pair[2],binding.mask)~=0 end
            end
        end
        parser:fixed_update('player',.01,frame*.01,frame)
        local action=parser:peek_next_input()
        if action and consume~=false then
            events[#events+1]={action=action,t=frame*.01,auto=parser:last_action_auto_completed()}
            parser:consume_next_input(frame*.01)
        end
        return action
    end
    tick(0)
    return tick,events,parser
end
local tick,events=session()
assert(tick(1)=='start_attack')
for _=1,5 do tick(1) end
assert(tick(0)=='light_attack')
assert(#events==2)
tick,events=session()
assert(tick(1)=='start_attack')
for _=1,35 do tick(1) end
assert(tick(0)=='heavy_attack')
assert(#events==2)
local parser
tick,events,parser=session()
assert(tick(2)=='block')
assert(tick(3)=='push')
for _=1,35 do tick(3) end
assert(events[3] and events[3].action=='push_follow_up')
local released_action=tick(0)
assert(events[4].action=='block' and released_action=='block_release',
    'Held block should re-enter the stock block hierarchy after push follow-up')
for _,entry in ipairs(parser._hierarchy_position[parser._ring_buffer_index]) do
    assert(entry==parser._NO_ACTION_INPUT,'Release did not return the stock hierarchy to base')
end
tick,events,parser=session()
assert(tick(2)=='block'); assert(tick(3)=='push')
for _=1,25 do tick(3) end
assert(events[3].action=='push_follow_up')
assert(tick(0)==nil,'Immediate nonqueued follow-up release produced an action')
for _,entry in ipairs(parser._hierarchy_position[parser._ring_buffer_index]) do
    assert(entry==parser._NO_ACTION_INPUT,'Immediate follow-up release did not return to base')
end
tick,events=session()
assert(tick(1)=='start_attack')
assert(tick(3)=='attack_cancel')
tick,events=session()
assert(tick(1)=='start_attack')
for _=1,185 do tick(1) end
local heavy_count=0
for _,event in ipairs(events) do if event.action=='heavy_attack' then heavy_count=heavy_count+1 end end
assert(heavy_count==1,'Held heavy did not auto-complete once within the tested window')
for _,variant in ipairs({{name='fast',hold=.3},{name='mid',hold=.35},{name='slow',hold=.45}}) do
    local selected=env.require('scripts/settings/equipment/weapon_templates/melee_action_input_setup_'..variant.name)
    tick,events=session(selected)
    assert(tick(1)=='start_attack')
    for _=1,5 do tick(1) end
    assert(tick(0)=='light_attack',variant.name)
    tick,events=session(selected)
    assert(tick(1)=='start_attack')
    for _=1,60 do tick(1) end
    assert(tick(0)=='heavy_attack',variant.name)
    tick,events=session(selected)
    assert(tick(1)=='start_attack')
    for _=1,160 do tick(1) end
    local completed
    for _,event in ipairs(events) do
        if event.action=='heavy_attack' then
            assert(not completed,'Repeated heavy auto-completion: '..variant.name)
            completed=event
        end
    end
    assert(completed and completed.auto and completed.t>.02+variant.hold+1 and
        completed.t<=.02+variant.hold+1+.03,'Stock heavy auto-completion timing: '..variant.name)
end
assert(template.action_inputs.heavy_attack.input_sequence[1].duration==.25,'Variant fixture mutated default setup')
print('melee_parser_stock=pass default_fast_mid_slow light_release heavy_hold auto_complete block_push_followup_release cancel')
print('LIMIT: shared stock input setups; unrelated common inputs, engine services and action consumption are fixtures')
