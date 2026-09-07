-- Optional source contract: real ActionHandler scale/chain methods and stock
-- gameplay caps. Engine network bounds and action contexts are supplied.
-- Usage: luajit test-melee-timing-stock-contract.lua <stock-root> <melee-timing.lua>
local function source(path)
    local f=assert(io.open(arg[1]..'/scripts/'..path..'.lua','r'))
    local s=f:read('*all'); f:close(); return s
end
local handler_source=source('utilities/action/action_handler')
local function extract(first,last)
    local a=assert(handler_source:find(first,1,true)); local b=assert(handler_source:find(last,a,true))
    assert(loadstring(handler_source:sub(a,b-1)))()
end
ActionHandler={}; EMPTY_TABLE={}
buff_stat_buffs={wield_speed='wield_speed'}
NetworkConstants={action_time_scale={min=.25,max=4}} -- Supplied engine type_info bounds.
math.clamp=function(v,a,b) return math.max(a,math.min(v,b)) end
local settings_chunk=assert(loadstring(source('settings/action/action_handler_settings')))
setfenv(settings_chunk,{settings=function(_,value) return value end})
ActionHandlerSettings=settings_chunk()
extract('local WIELD_ACTION_KINDS =','\nActionHandler._anim_event =')
extract('ActionHandler._validate_single_chain_action =','\nActionHandler._valid_action_from_action_input =')
local handling=1
local buffs={attack_speed=1,melee_attack_speed=1,wield_speed=1}
local target_available=true
local current={current_action_name='light'}
local handler=setmetatable({_weapon_extension={weapon_handling_template=function() return {time_scale=handling} end},
    _buff_extension={stat_buffs=function() return buffs end},
    _action_context={weapon_action_component=current},_action_kinds_with_inverted_timescale={},
    _validate_action=function(_,action,params,t,elapsed,used)
        assert(action and params=='context' and t==100 and elapsed>=0 and used=='recorded_input')
        return target_available
    end},{__index=ActionHandler})
local Timing=dofile(arg[2])
local actions={light={kind='sweep',time_scale_stat_buffs={'attack_speed','melee_attack_speed'},
        allowed_chain_actions={start_attack={action_name='windup',chain_time=.55}}},
    windup={kind='windup',allowed_chain_actions={light_attack={action_name='light',chain_time=0},
        heavy_attack={action_name='heavy',chain_time=.5}}},heavy={kind='sweep'}}
local function near(a,b) assert(math.abs(a-b)<1e-10,tostring(a)..' ~= '..tostring(b)) end
local function scale(action) return handler:_calculate_time_scale(action) end
near(scale(actions.light),1)
handling=1.2; buffs.attack_speed=1.1; buffs.melee_attack_speed=1.2
near(scale(actions.light),1.56) -- Additive listed buffs, then weapon handling.
buffs.melee_attack_speed=nil; near(scale(actions.light),1.32)
buffs.unrelated=99; near(scale(actions.light),1.32)
buffs.attack_speed=nil; near(scale(actions.light),1.2)
handling=100; near(scale(actions.light),ActionHandlerSettings.gameplay_time_scale_limits.sweep)
near(scale(actions.windup),4)
handling=.001; near(scale(actions.light),.25)
handling=1
local cases=0
for _,modifier in ipairs({.5,1,1.5,3}) do
    handling=modifier
    for _,inverted in ipairs({false,true}) do
        handler._action_kinds_with_inverted_timescale={sweep=inverted,windup=inverted}
        for _,name in ipairs({'light','windup'}) do
            current.current_action_name=name
            local alias=name=='light' and 'start_attack' or 'heavy_attack'
            local chain=actions[name].allowed_chain_actions[alias]
            local duration,destination=Timing.resolve(actions,{{action=name,input=alias}},scale,
                handler._action_kinds_with_inverted_timescale)
            assert(duration and destination==chain.action_name)
            local time_scale=scale(actions[name])
            assert(not handler:_validate_single_chain_action(chain,100,duration-1e-6,time_scale,actions,
                'context','recorded_input',nil),'Stock admitted before the resolved chain threshold')
            local valid,selected=handler:_validate_single_chain_action(chain,100,duration,time_scale,actions,
                'context','recorded_input',nil)
            assert(valid and selected==destination,'Resolver disagreed with stock chain admission')
            cases=cases+1
        end
    end
end
-- Timed-out early alternatives and running state requirements are conservatively
-- rejected by the offline route, even though stock can admit a specific state.
handling=1; current.current_action_name='light'
local chain=actions.light.allowed_chain_actions.start_attack
chain.chain_until=.1
assert(handler:_validate_single_chain_action(chain,100,.05,1,actions,'context','recorded_input',nil))
assert(not Timing.resolve(actions,{{action='light',input='start_attack'}},scale))
chain.chain_until=nil; chain.running_action_state_requirement={ready=true}
assert(not handler:_validate_single_chain_action(chain,100,1,1,actions,'context','recorded_input',nil))
assert(handler:_validate_single_chain_action(chain,100,1,1,actions,'context','recorded_input','ready'))
assert(not Timing.resolve(actions,{{action='light',input='start_attack'}},scale))
chain.running_action_state_requirement=nil; target_available=false
assert(not handler:_validate_single_chain_action(chain,100,1,1,actions,'context','recorded_input',nil))
print('PASS: '..cases..' actual stock timing boundaries, additive buffs, handling, caps and conditional admission')
