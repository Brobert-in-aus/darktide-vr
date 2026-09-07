-- Optional cached-source contract. Executes the stock device input consumer
-- with real VR binding output. Device algorithms, movement transport, animation,
-- dodge eligibility and weapon execution are fixtures, not live mission proof.
local root,bindings_path=assert(arg[1]),assert(arg[2])
bit=require('bit')
local path=root..'/scripts/extension_systems/character_state_machine/character_states/player_character_state_minigame.lua'
local file=assert(io.open(path,'r')); local source=file:read('*a'); file:close()
local first=assert(source:find('PlayerCharacterStateMinigame._update_input =',1,true))
local last=assert(source:find('\nPlayerCharacterStateMinigame._is_minigame_active =',first,true))
local State={}
local dodge=false
local env=setmetatable({PlayerCharacterStateMinigame=State,
    Dodge={check=function() return dodge end},
    Vector3={zero=function() return {x=0,y=0,z=0} end,
        equal=function(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end}}, {__index=_G})
setfenv(assert(loadstring(source:sub(first,last-1),'@'..path)),env)()
local bindings=dofile(bindings_path).install({get=function() end})
local actions,axes,animations,weapon_frames={},{},{},{}
local wielding,uses_action,uses_axis,blocks,completed=true,true,true,false,false
local override_escape
local device={uses_action=function() return uses_action end,
    action=function(_,held,t) actions[#actions+1]={held=held,t=t}; return held end,
    is_completed=function() return completed end,
    uses_joystick=function() return uses_axis end,
    on_axis_set=function(_,t,x,y) axes[#axes+1]={x=x,y=y,t=t} end,
    escape_action=function(_,pressed) if override_escape~=nil then return override_escape end; return pressed end,
    blocks_weapon_actions=function() return blocks end}
local state=setmetatable({_previous_action_one_hold=false,_previous_interact_hold=false,
    _previous_jump_held=false,_previous_input=false,_minigame=device,
    _is_wielding_minigame_device=function() return wielding end,
    _animation_extension={anim_event_1p=function(_,name) animations[#animations+1]=name end},
    _weapon_extension={update_weapon_actions=function(_,frame) weapon_frames[#weapon_frames+1]=frame end}},
    {__index=State})
local frame=0
local function sample(physical,move)
    frame=frame+1
    local pressed,held,released=bindings.sample(true,physical,0,0,true,1,'combat')
    local values={move=move or {x=0,y=0,z=0}}
    for _,binding in ipairs(bindings.bindings) do
        for _,pair in ipairs({{binding.pressed,pressed},{binding.held,held},{binding.released,released}}) do
            for _,name in ipairs(pair[1]) do values[name]=bit.band(pair[2],binding.mask)~=0 end
        end
    end
    local input={get=function(_,name) assert(values[name]~=nil,'Unexpected stock read '..name); return values[name] end}
    return state:_update_input(frame*.01,frame,input)
end
sample(0)
for _,control in ipairs({1,8,32}) do
    assert(not sample(control) and actions[#actions].held,'Device did not receive a mapped action hold')
    sample(control); assert(actions[#actions].held,'Device action hold was reduced to a press')
    sample(0); assert(not actions[#actions].held,'Device action failed to release')
end
dodge=true
sample(32); assert(not actions[#actions].held,'Jump/dodge bypassed the stock dodge decision')
sample(0); dodge=false
local before=#weapon_frames
assert(sample(2),'Alternate press did not request stock device cancellation')
assert(#weapon_frames==before,'Weapon actions ran after device cancellation')
assert(not sample(2),'Held alternate repeated the pressed cancel action')
sample(0)
override_escape=false
assert(not sample(2),'Adapter bypassed the device escape policy')
sample(0); override_escape=nil
blocks=true; before=#weapon_frames
sample(1); assert(#weapon_frames==before,'Device weapon-action block was ignored')
sample(0); blocks=false
sample(0,{x=.25,y=-.5,z=0})
assert(axes[#axes].x==.25 and axes[#axes].y==-.5 and animations[#animations]=='knob_turn_up')
sample(0,{x=-.25,y=-.5,z=0})
assert(animations[#animations]=='knob_turn_down')
completed=true; sample(1)
assert(animations[#animations-1]=='button_press' and animations[#animations]=='scan_end')
sample(0)
wielding=false; local action_count,axis_count=#actions,#axes; before=#weapon_frames
assert(sample(1) and #actions==action_count and #axes==axis_count and #weapon_frames==before,
    'Lost device ownership still drove device/weapon actions')
wielding=true; sample(0)
uses_action,uses_axis=false,false
action_count,axis_count=#actions,#axes
sample(1,{x=1,y=1,z=0})
assert(#actions==action_count and #axes==axis_count,'Unsupported device input paths were invoked')
print('mission_device_stock=pass mapped_hold release dodge cancel escape_policy weapon_block axes completion wield_loss')
path=root..'/scripts/extension_systems/interaction/interactor_extension.lua'
file=assert(io.open(path,'r')); source=file:read('*a'); file:close()
first=assert(source:find('InteractorExtension._check_current_state =',1,true))
last=assert(source:find('\nInteractorExtension.cancel_interaction =',first,true))
local Interactor={}
local states={waiting_to_interact='waiting',is_interacting='active'}
local results={stopped_holding='released',interaction_cancelled='cancelled',success='success',ongoing='ongoing'}
local unit,target={},{}
local starts,stops,events={},{},{}
local valid_target,hold_required,ui_interaction,finished,start_allowed=true,true,false,false,true
local interactee={hold_required=function() return hold_required end,
    infinite_interaction=function() return false end,ui_interaction=function() return ui_interaction end,
    started=function() end,stopped=function() end}
local interaction={interaction_input=function() return 'interact_pressed' end,type=function() return 'fixture' end,
    start=function(_,world,u,component,t,server) starts[#starts+1]=server; return start_allowed end,
    stop=function(_,world,u,component,t,result,server) stops[#stops+1]={result=result,server=server} end}
env=setmetatable({InteractorExtension=Interactor,interaction_states=states,interaction_results=results,
    ScriptUnit={extension=function(u,name) assert(u==target and name=='interactee_system'); return interactee end},
    Vo={interaction_start_event=function() end},Component={event=function(_,event) events[#events+1]=event end}}, {__index=_G})
setfenv(assert(loadstring(source:sub(first,last-1),'@'..path)),env)()
local component={state='waiting',target_unit=target,type='fixture',done_time=0}
local actor=setmetatable({_unit=unit,_is_server=true,_interaction_component=component,
    interaction=function() return interaction end,
    _consume_conflicting_gamepad_inputs=function() end,
    _start_interaction_timer=function(_,t) component.done_time=t+1 end,
    _check_valid_ongoing_interaction=function() return valid_target end,
    reset_interaction=function() component.state='waiting' end}, {__index=Interactor})
local interact_mapper=dofile(bindings_path).install({get=function(_,key)
    if key=='vr_bind_right_grip' then return 'interact' end
end})
local time=0
local function interact_sample(physical,chosen)
    time=time+.1
    local pressed,held=interact_mapper.sample(true,physical,0,0,true,1,'combat')
    actor._input_extension={get=function(_,name)
        if name=='interact_pressed' then return bit.band(pressed,8)~=0 end
        if name=='interact_hold' then return bit.band(held,8)~=0 end
        assert(name=='finished_interaction'); return finished
    end}
    actor:_check_current_state(unit,.1,time,chosen~=false,component.state)
end
interact_sample(0); interact_sample(8)
assert(component.state=='active' and #starts==1 and #stops==0)
interact_sample(12); interact_sample(4)
assert(component.state=='active' and #starts==1 and #stops==0,'Healthy interaction alias did not retain the hold')
interact_sample(0)
assert(component.state=='waiting' and stops[#stops].result=='released')
interact_sample(8)
valid_target=false; interact_sample(8)
assert(stops[#stops].result=='cancelled','Invalid target retained interaction')
valid_target=true; interact_sample(0); interact_sample(8)
component.target_unit=nil; interact_sample(8)
assert(stops[#stops].result=='cancelled','Missing target retained interaction')
component.target_unit=target; interact_sample(0)
for _,server in ipairs({true,false}) do
    actor._is_server=server
    local previous_events=#events
    interact_sample(8)
    for i=1,12 do interact_sample(8) end
    assert(stops[#stops].result=='success' and stops[#stops].server==server)
    if server then assert(events[#events]=='interaction_success')
    else assert(#events==previous_events,'Client emitted authoritative interaction event') end
    interact_sample(0)
end
start_allowed=false; local previous_stops=#stops
interact_sample(8)
assert(component.state=='waiting' and #stops==previous_stops,'Rejected interaction started its timer')
interact_sample(0); start_allowed=true
ui_interaction=true; hold_required=false
interact_sample(8)
for i=1,12 do interact_sample(0) end
assert(component.state=='active','UI interaction completed without its finished signal')
finished=true; interact_sample(0)
assert(component.state=='waiting' and stops[#stops].result=='success')
local previous_starts=#starts
interact_sample(8,false)
assert(#starts==previous_starts,'Interaction started without a chosen target')
print('mission_hold_stock=pass mapped_hold aliases release target_loss rejected_start timer ui_completion server_event_scope')
print('LIMIT: stock input consumer with engine/device fixtures; no mission completion, tactile or worn acceptance')
