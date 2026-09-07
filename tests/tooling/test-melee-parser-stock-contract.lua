-- Actual stock parser, formatter and melee hierarchy. Engine services and
-- unrelated common-action inputs are fixtures; no action execution or network.
local root=assert(arg[1])
local bindings_path=assert(arg[2])
local cache={}
local raw={}
local input_reader
local function clone(value)
    if type(value)~='table' then return value end
    local result={}; for k,v in pairs(value) do result[k]=clone(v) end; return result
end
local env=setmetatable({}, {__index=_G})
env.Script={new_array=function() return {} end}
env.settings=function(_,value) return value end
env.NetworkConstants={fixed_frame_offset_start_t_5bit={min=-16},fixed_time_offset_unset=-1000}
env.table=setmetatable({clone=clone,clear=function(t) for k in pairs(t) do t[k]=nil end end,
    keys=function(t) local out={}; for k in pairs(t) do out[#out+1]=k end; return out end,
    add_missing=function(dest,src) for k,v in pairs(src) do if dest[k]==nil then dest[k]=v end end end}, {__index=table})
env.class=function()
    local class={}; class.__index=class
    function class:new(...) local self=setmetatable({},class); self:init(...); return self end
    return class
end
env.ferror=function(format,...) error(string.format(format,...)) end
env.Log={debug=function() end,info=function() end,error=function(_,message) error(message) end}
env._debug=function() end
env.Managers={state={game_session={fixed_time_step=.01},player_unit_spawn={owner=function()
    return {is_human_controlled=function() return true end}
end}}}
env.ScriptUnit={extension=function(_,name)
    if name=='input_system' then
        local reader=input_reader
        return {get=function(_,key)
            if reader then return reader(key) end
            return raw[key] or false
        end}
    end
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
env.HumanInputHandler,env.AuthoritativePlayerInputHandler={},{}
local function method(path,first_marker,last_marker)
    local file=assert(io.open(root..'/scripts/'..path..'.lua','r'))
    local source=file:read('*a'); file:close()
    local first=assert(source:find(first_marker,1,true))
    local last=assert(source:find(last_marker,first,true))
    setfenv(assert(loadstring(source:sub(first,last-1),'@'..path)),env)()
end
local human='managers/player/player_game_states/human_input_handler'
for _,pair in ipairs({{'_buffer_index','pre_update'},{'fixed_update','get_orientation'},
        {'update','rpc_player_input_array_ack'}}) do
    method(human,'HumanInputHandler.'..pair[1]..' =','\nHumanInputHandler.'..pair[2]..' =')
end
method('managers/player/player_game_states/authoritative_player_input_handler',
    'AuthoritativePlayerInputHandler.get =','\nAuthoritativePlayerInputHandler.rewind_ms =')
bit=require('bit')
local Bindings=dofile(bindings_path)
local function session(selected_template,corrupt_frame)
    raw={}
    local mapper=Bindings.install({get=function() end})
    local parser=Parser:new('player','weapon_action',{template_name='melee'},
        {action_input_type='weapon',templates={melee=selected_template or template}},1)
    local frame=0
    local names=parser._RAW_INPUTS_NETWORK_LOOKUP
    local column_count=#names-1 -- final formatter sentinel is not an input
    local sender=setmetatable({_frame=0,_last_frame_acknowledged=0,_input_buffer_size=4,
        _send_buffer_size=3,_is_server=false,_input_cache={},_send_array={},
        _yaw_index=column_count+1,_pitch_index=column_count+2,_roll_index=column_count+3,
        _player={local_player_id=function() return 1 end},
        _parse_input=function(_,columns,values,index)
            for i=1,column_count do columns[i][index]=values[names[i]] or false end
        end},{__index=env.HumanInputHandler})
    local receiver=setmetatable({_received_frame=0,_parsed_frame=0,_input_cache={},
        _input_cache_size=column_count+3,_action_lookup={},
        _clock_handler={frame_received=function() end}},{__index=env.AuthoritativePlayerInputHandler})
    for i=1,column_count+3 do sender._input_cache[i]={}; sender._send_array[i]={}; receiver._input_cache[i]={} end
    for i=1,column_count do receiver._action_lookup[names[i]]=i end
    input_reader=function(name) return receiver:get(name,frame) end
    local remote_parser=Parser:new('player','weapon_action',{template_name='melee'},
        {action_input_type='weapon',templates={melee=selected_template or template}},2)
    input_reader=nil
    local game=env.Managers.state.game_session
    game.can_send_session_bound_rpcs=function() return true end
    game.send_rpc_server=function(_,name,player,first,offset,...)
        assert(name=='rpc_player_input_array' and player==1)
        local packet=clone({...})
        receiver:rpc_player_input_array('fixture',player,first,offset,unpack(packet))
        receiver:rpc_player_input_array('fixture',player,first,offset,unpack(packet)) -- duplicate packet
        if frame==corrupt_frame then
            receiver._input_cache[receiver._action_lookup.action_one_hold][frame]=false
        end
    end
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
        sender:fixed_update(.01,frame*.01,frame,raw,.2,-.1,0)
        sender:update()
        sender._last_frame_acknowledged=frame
        parser:fixed_update('player',.01,frame*.01,frame)
        remote_parser:fixed_update('player',.01,frame*.01,frame)
        local action=parser:peek_next_input()
        assert(remote_parser:peek_next_input()==action,'Receiving parser selected a different action')
        assert(remote_parser:last_action_auto_completed()==parser:last_action_auto_completed())
        local local_hierarchy=parser._hierarchy_position[parser._ring_buffer_index]
        local remote_hierarchy=remote_parser._hierarchy_position[remote_parser._ring_buffer_index]
        for i,value in ipairs(local_hierarchy) do assert(remote_hierarchy[i]==value,'Receiving hierarchy disagreed') end
        if action and consume~=false then
            events[#events+1]={action=action,t=frame*.01,auto=parser:last_action_auto_completed()}
            parser:consume_next_input(frame*.01)
            remote_parser:consume_next_input(frame*.01)
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
-- Execute the actual force-sword input setup and per-weapon overrides, stopping
-- before damage profiles and engine resources unrelated to input parsing.
local force_setup=env.require('scripts/settings/equipment/weapon_templates/forcesword_melee_action_input_setup')
for _,variant in ipairs({'forcesword_p1_m1','forcesword_p1_m2','forcesword_p1_m3'}) do
    local file=assert(io.open(root..'/scripts/settings/equipment/weapon_templates/force_swords/'..variant..'.lua','r'))
    local source=file:read('*a'); file:close()
    local first=assert(source:find('local weapon_template = {}',1,true))
    local marker='weapon_template.action_input_hierarchy = action_input_hierarchy'
    local last=assert(source:find(marker,first,true))+#marker-1
    local setup_env=setmetatable({ForceswordMeleeActionInputSetup=force_setup,
        ActionInputHierarchy=env.require('scripts/utilities/action/action_input_hierarchy')},{__index=env})
    local selected=setfenv(assert(loadstring(source:sub(first,last)..'\nreturn weapon_template','@'..variant)),setup_env)()
    tick,events=session(selected)
    assert(tick(1)=='start_attack',variant)
    for _=1,5 do tick(1) end
    assert(tick(0)=='light_attack',variant)
    tick,events=session(selected)
    assert(tick(1)=='start_attack',variant)
    for _=1,35 do tick(1) end
    assert(tick(0)=='heavy_attack',variant)
    tick,events=session(selected)
    assert(tick(8)=='vent',variant)
    for _=1,80 do assert(tick(8)==nil,'Held quell repeated: '..variant) end
    assert(tick(0)=='vent_release',variant)
    assert(#events==2,'Unexpected quell action: '..variant)
    tick,events=session(selected)
    assert(tick(2)=='block',variant); assert(tick(3)=='push',variant)
    for _=1,25 do tick(3) end
    assert(events[3].action=='push_follow_up',variant)
    assert(tick(2)=='find_target_release','Primary release must select stock target-release priority: '..variant)
    tick,events=session(selected)
    assert(tick(2)=='block'); assert(tick(3)=='push')
    for _=1,25 do tick(3) end
    assert(tick(1)==nil,'Alternate-only release incorrectly ended target hold: '..variant)
    assert(tick(0)=='find_target_release','Both released must retain stock release priority: '..variant)
end
local corrupted=session(nil,2)
local ok,reason=pcall(corrupted,1)
assert(not ok and tostring(reason):find('Receiving parser selected a different action',1,true),
    'Deliberate false receiving input did not expose divergence')
print('melee_parser_stock=pass default_fast_mid_slow forcesword_m1_m2_m3_quell_target_release light_release heavy_hold auto_complete block_push_followup_release cancel stock_send_receive duplicate_packet')
print('LIMIT: in-memory RPC, shared input setups, unrelated common inputs, engine services and action consumption are fixtures; no authoritative damage')
