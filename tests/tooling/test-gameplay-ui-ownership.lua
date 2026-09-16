-- Exercise the real adapter seam and mapper without game or desktop input.
bit=require('bit')
local file=assert(io.open(arg[1],'r'))
local source=file:read('*all'); file:close()
local first=assert(source:find('function presentation.inject_ephemeral_action_names',1,true))
local last=assert(source:find('\nmod:hook_safe(',first,true))
local settings={}
local wheel_hooks,chat_hooks={},{}
mod={get=function(_,key) return settings[key] end,info=function() end,
    io_dofile=function(_,path)
        return dofile(assert(arg[1]:match('^(.*[/\\])'))..assert(path:match('([^/]+)$'))..'.lua')
    end,
    hook=function(_,class,name,fn)
        if class=='ChatManager' then chat_hooks[name]=fn
        else assert(class=='HudElementSmartTagging');wheel_hooks[name]=fn end
    end}
-- The input block times each sampler through the frame profiler; off, a
-- section is a pass-through.
presentation={mode=1,gameplay_context=dofile(arg[2]),
    frame_profile={section=function(_,fn,...) return fn(...) end,frame=function() end},
    is_first_person_body_mode=function(mode) return mode=='hub' end,
    apply_controller_turning=function() end,
    keyboard_mouse_enabled=function() return false end,controllers_disabled=function() return false end}
presentation.controller_bindings=dofile(arg[3]).install(mod)
presentation.gameplay_input_bindings=presentation.controller_bindings.bindings
controller_observation={gameplay_input_enabled=true,gameplay_input_last_check_t=0,
    gameplay_pressed={[0]=0},gameplay_held={[0]=0},gameplay_released={[0]=0},
    gameplay_sequence={[0]=1},gameplay_movement={[0]=0,[1]=0},
    right_stick_x=0,right_stick_y=0,right_aim_usable=true,last_transport_generation=1}
Mods={lua={io={}}}
active_game_mode_name=function() return 'hub' end
local owns,physical,native_active,native_result=false,0,nil,0
local input_service={is_null_service=function() return false end}
Managers={ui={using_input=function(self,...)
    assert(self==Managers.ui and select('#',...)==0,'UI owners must not be ignored')
    return owns
end,inputs_in_use=function() error('key filter is not an ownership API') end}}
ui_native_capture={dtvr_read_gameplay_input=function(active,p,h,r,sequence,movement)
    native_active=active
    h[0]=active==1 and physical or 0
    return native_result
end}
local ui_active
presentation.gameplay_ui={sample=function(active) ui_active=active end}
assert(loadstring(source:sub(first,last-1)))()
local owner={_ephemeral_actions={'action_one_pressed','action_one_release','stock_action'},
    _ephemeral_action_cache={}}
local player={input_handler=owner,player_unit='first_character'}
Unit={alive=function(unit) return unit~=nil and unit~='dead_character' end}
owner._player=player
Managers.player={local_player=function(_,index) assert(index==1); return player end}
local function sample(value)
    physical=value
    owner._ephemeral_action_cache={false,false,true}
    presentation.inject_gameplay_input(owner,.1,input_service)
    assert(owner._ephemeral_action_cache[3],'Stock keyboard cache was changed')
    return owner._ephemeral_action_cache
end
sample(0)
sample(0) -- First handler frame drains previous native/semantic ownership.
assert(sample(1)[1] and native_active==1 and ui_active)
owns=true -- Chat/overlay opens while RT is held.
local blocked=sample(1)
assert(native_active==0 and not ui_active and presentation.controller_bindings.held==0)
assert(not blocked[1] and not blocked[2],'UI cancellation injected a charged-release edge')
owns=false
assert(not sample(1)[1],'Held attack leaked out of UI')
sample(0)
assert(sample(1)[1],'Released control did not rearm')
assert(sample(0)[2],'Ordinary gameplay release was lost')
-- Scanner display reports no input ownership: stock gameplay controls survive.
assert(native_active==1 and ui_active)
-- HumanGameplay also uses its null service for cinematics and ImGui ownership,
-- independently of ordinary UI ownership and the current stereo mode.
for _,service in ipairs({{is_null_service=function() return true end},{},
        {is_null_service=function() return nil end},
        setmetatable({}, {__index=function() error('input service retired') end})}) do
    sample(0); assert(sample(1)[1])
    input_service=service
    local cancelled=sample(1)
    assert(native_active==0 and not ui_active and not cancelled[1] and not cancelled[2],
        'Stock-disabled input was replaced with fresh controller actions')
    input_service={is_null_service=function() return false end}
    assert(not sample(1)[1],'Stock input recovery inherited an old controller hold')
    sample(0); assert(sample(1)[1] and sample(0)[2])
end
-- A failed native read cancels the mapper just like UI ownership does. Its
-- synthetic release must not enter the game's charged attack/throw cache.
for _,failure in ipairs({1,-1,2,3}) do
  for _,failed_level in ipairs({0,1}) do
    sample(0)
    assert(sample(1)[1])
    native_result=failure
    local lost=sample(failed_level)
    assert(native_active==1 and not ui_active and presentation.controller_bindings.held==0)
    assert(not lost[1] and not lost[2], 'Tracking/read failure injected a charged-release edge')
    native_result=0
    assert(not sample(1)[1], 'Reconnect reactivated an inherited held attack')
    sample(0)
    assert(sample(1)[1], 'Neutral controller failed to rearm after read recovery')
    assert(sample(0)[2], 'Normal release after recovery was lost')
  end
end
-- Remapping and an observed publisher generation change are cancellation,
-- even if the current native read succeeded. They must not finish a charge.
sample(0)
assert(sample(1)[1])
mod.on_setting_changed('vr_bind_right_trigger')
local remapped=sample(1)
assert(not remapped[1] and not remapped[2], 'Remap injected a charged-release edge')
sample(0)
assert(sample(1)[1])
controller_observation.last_transport_generation=2
local restarted=sample(1)
assert(not restarted[1] and not restarted[2], 'Observed publisher restart injected a charged-release edge')
assert(not sample(1)[1], 'Publisher restart must require a neutral sample before rearming')
sample(0)
assert(sample(1)[1] and sample(0)[2])
-- An obsolete/foreign handler must not read shared controller input, reset the
-- current mapper or consume a press. A replacement current handler starts cold.
local foreign={_player={},_ephemeral_actions=owner._ephemeral_actions,_ephemeral_action_cache={false,false,true}}
native_active='not_read'
presentation.inject_gameplay_input(foreign,.1)
assert(native_active=='not_read' and not foreign._ephemeral_action_cache[1], 'Foreign handler consumed controller input')
sample(0)
assert(sample(1)[1])
local retired=owner
owner={_player=player,_ephemeral_actions=retired._ephemeral_actions,_ephemeral_action_cache={}}
player.input_handler=owner
native_active='not_read'
presentation.inject_gameplay_input(retired,.1)
assert(native_active=='not_read', 'Retired handler still consumed controller input')
local replaced=sample(1)
assert(not replaced[1] and not replaced[2] and not ui_active, 'Replacement handler inherited a held attack')
assert(not sample(1)[1])
sample(0)
assert(sample(1)[1] and sample(0)[2])
-- HumanGameplay can replace player_unit while retaining this input handler.
sample(0)
assert(sample(1)[1])
player.player_unit='replacement_character'
local respawned=sample(1)
assert(not respawned[1] and not respawned[2] and not ui_active and
    presentation.controller_bindings.held==0, 'Replacement character inherited a held attack')
assert(not sample(1)[1])
sample(0)
assert(sample(1)[1] and sample(0)[2])
player.player_unit='dead_character'
assert(not sample(1)[1] and not ui_active and presentation.controller_bindings.held==0,
    'Dead character admitted new controller input')
player.player_unit=nil
assert(not sample(1)[1] and not ui_active)
player.player_unit='next_character'
assert(not sample(1)[1] and not ui_active)
assert(not sample(1)[1])
sample(0)
assert(sample(1)[1] and sample(0)[2])
for _,ui in ipairs({{}, {using_input=function() error('retiring') end},
        {using_input=function() return {} end}, {using_input=function() return nil end},
        17,true,setmetatable({}, {__index=function() error('retired proxy lookup') end})}) do
    Managers.ui=ui
    assert(not sample(1)[1] and native_active==0 and not ui_active)
end
Managers.ui=nil
assert(not sample(1)[1] and native_active==0)
-- The fixed-frame hook must enforce the same owner before touching history or
-- running diagnostics, including a new handler not yet sampled by pre-update.
local fixed_hook,pre_hook
mod.hook_safe=function(_,class,method,callback)
    if method=='fixed_update' then fixed_hook=callback end
    if method=='pre_update' then pre_hook=callback end
end
local saved_require=require
require=function() return {} end
local hook_end=assert(source:find('\nfunction presentation.log_unit_pose',last,true))
assert(loadstring(source:sub(last,hook_end-1)))()
require=saved_require
local scans,captures=0,0
presentation.scan_movement_inventory=function() scans=scans+1 end
presentation.online_rules={capture=function() captures=captures+1 end}
-- Keyboard and mouse melee roll input follows each capture in the same hook.
local roll_inputs=0
presentation.apply_keyboard_mouse_roll_input=function(handler) assert(handler==owner); roll_inputs=roll_inputs+1 end
fixed_hook(foreign,0,0,1)
fixed_hook(retired,0,0,1)
assert(scans==0 and captures==0 and roll_inputs==0)
fixed_hook(owner,0,0,1,input_service)
assert(scans==1 and captures==1 and roll_inputs==1)
player.player_unit='unsampled_character'
fixed_hook(owner,0,0,1)
assert(scans==1 and captures==1,'Replacement character inherited previous fixed input state')
local unsampled={_player=player}
player.input_handler=unsampled
fixed_hook(unsampled,0,0,1)
assert(scans==1 and captures==1,'Unsampled replacement inherited previous fixed input state')
-- Fixed-cache movement must preserve neutral keyboard channels and combine
-- active stick input without altering unrelated/older entries or held actions.
player.input_handler=owner
player.player_unit='next_character'
Managers.ui={using_input=function() return owns end}
owns=false
sample(0)
controller_observation.gameplay_locomotion_last_frame=0
presentation.rotate_controller_movement=function(x,y) return x,y end
owner._buffer_index=function() return 1 end
owner._action_lookup={move_right=1,move_left=2,move_forward=3,move_backward=4,action_one_hold=5}
local function movement(x,y,initial,wanted)
    owner._input_cache={{initial[1],91},{initial[2],92},{initial[3],93},{initial[4],94},{false,95}}
    controller_observation.gameplay_movement[0],controller_observation.gameplay_movement[1]=x,y
    fixed_hook(owner,0,0,2,input_service)
    for i=1,4 do
        assert(math.abs(owner._input_cache[i][1]-wanted[i])<1e-6,'Mixed keyboard/stick cache changed')
        assert(owner._input_cache[i][2]==90+i,'Movement rewrote a different cached frame')
    end
end
movement(0,0,{.8,.5,.2,.1},{.8,.5,.2,.1})
assert(not controller_observation.gameplay_stick_active)
movement(.9,-.8,{.8,.5,.2,.1},{1,0,0,.7})
movement(-.9,.2,{.8,.5,.2,.1},{0,.6,.3,0})
assert(controller_observation.gameplay_stick_active)
assert(sample(1)[1])
movement(0,0,{.8,.5,.2,.1},{.8,.5,.2,.1})
assert(owner._input_cache[5][1] and owner._input_cache[5][2]==95,'Neutral stick lost held attack or changed older input')
owner._action_lookup.move_left=nil
movement(-.6,.8,{.4,.5,.5,0},{0,.5,1,0}) -- Missing channel remains untouched.
owner._action_lookup.move_left=2
owns=true; sample(1)
movement(1,1,{.8,.5,.2,.1},{.8,.5,.2,.1})
assert(not owner._input_cache[5][1] and not controller_observation.gameplay_stick_active,
    'Inactive input merged movement or holds')
-- Stock selects input again for each fixed update. A cinematic/null service
-- can arrive after an ordinary pre-update sample; cancel before history writes.
for _,service in ipairs({{is_null_service=function() return true end},{},false,
        setmetatable({}, {__index=function() error('fixed service retired') end})}) do
    owns=false; sample(0); assert(sample(1)[1])
    local captures_before=captures
    owner.get=function() return false end
    controller_observation.primary_action_sequence=1
    controller_observation.primary_action_injected=true
    controller_observation.primary_action_stage='press'
    controller_observation.gameplay_stick_active=true
    input_service=service or nil
    movement(1,1,{.8,.5,.2,.1},{.8,.5,.2,.1})
    assert(not owner._input_cache[5][1] and captures==captures_before,
        'Fixed null service admitted controller holds or aim capture')
    assert(not controller_observation.gameplay_input_active and not controller_observation.gameplay_stick_active and
        not controller_observation.primary_action_injected and not ui_active and presentation.controller_bindings.held==0)
    input_service={is_null_service=function() return false end}
    -- Recovery without another render sample must also leave old holds disabled.
    movement(1,1,{.8,.5,.2,.1},{.8,.5,.2,.1})
    assert(not owner._input_cache[5][1])
    assert(not sample(1)[1],'Fixed service recovery inherited the held attack')
    sample(0); assert(sample(1)[1] and sample(0)[2])
end
local primary_first=assert(source:find('function presentation.inject_primary_action',1,true))
local primary_last=assert(source:find('\npresentation.controller_bindings =',primary_first,true))
assert(loadstring(source:sub(primary_first,primary_last-1)))()
Mods.lua.io.open=function() error('Foreign handler consumed synthetic test request') end
presentation.inject_primary_action(foreign,1)
-- The registered hook must forward stock's actual service to both consumers.
local real_primary=presentation.inject_primary_action
presentation.inject_primary_action=function(self,t,input)
    assert(self==owner and t==.1 and input==input_service)
end
owns=false; physical=0
pre_hook(owner,0,.1,input_service)
assert(native_active==1 and ui_active,'Registered hook lost the stock service')
presentation.inject_primary_action=real_primary
pre_hook(owner,0,.1,{is_null_service=function() return true end})
assert(native_active==0 and not ui_active,'Null service reached gameplay or synthetic test input')
print('gameplay_ui_ownership=pass real_adapter overlay_cancel failed_read_cancel neutral_resume stock_cache scanner retiring_owner')
-- Verify contextual ownership reaches the actual pre-update mapper and is
-- retired by a stock service change in fixed_update, before another sample.
local support_owner={}
local support_finished,support_cleared
presentation.two_hand={sample=function(unit,active,t,handler)
    assert(unit==player.player_unit and handler==owner and t==.1)
    if active then return {control='left_grip',owner=support_owner,acquire=true,retain=true,action='alternate'} end
end,finish=function(grip) support_finished=grip.held end,
clear=function(interrupted) support_cleared=interrupted==true end}
owner._ephemeral_actions={'action_two_pressed','action_two_release','stock_action'}
owns=false; input_service={is_null_service=function() return false end}
sample(0); sample(0)
assert(sample(512)[1] and support_finished,'Production mapper did not acquire contextual grip')
input_service={is_null_service=function() return true end}
movement(0,0,{0,0,0,0},{0,0,0,0})
assert(support_cleared and presentation.controller_bindings.held==0,
    'Fixed service cancellation retained two-hand state')
input_service={is_null_service=function() return false end}
assert(not sample(512)[1] and not support_finished,'Support rearmed before neutral after fixed cancellation')
sample(0)
assert(sample(512)[1] and support_finished)
assert(sample(0)[2] and not support_finished)
print('two_hand_production_input=pass pre_update fixed_cancel stock_cache')

-- Execute the real production pre-update seam with the real wheel adapter.
-- Its claim must reach turning before the mapper consumes a stick sector.
presentation.two_hand=nil
owner._ephemeral_actions={'action_one_pressed','action_one_release','stock_action'}
settings.vr_action_bind_communication_wheel=256
settings.vr_hub_action_bind_communication_wheel=-1
settings.vr_action_bind_primary=1+2048
settings.vr_hub_action_bind_primary=-1
mod.on_setting_changed('vr_action_bind_communication_wheel')
mod.on_setting_changed('vr_action_bind_primary')
local turn_claim,turn_calls
presentation.apply_controller_turning=function(_,claim)turn_claim=claim;turn_calls=(turn_calls or 0)+1 end
local real_sample=presentation.controller_bindings.sample
presentation.controller_bindings.sample=function(...)
    assert(turn_calls==1 and select(9,...)==turn_claim,'Production mapper ran before/shared a different claim from turning')
    turn_calls=0
    return real_sample(...)
end
sample(0);sample(0)
controller_observation.right_stick_y=1
assert(not sample(256)[1] and turn_claim==true,'Wheel start also fired a directional action')
assert(not sample(256)[1] and turn_claim==true)
assert(not sample(0)[1],'Unadmitted HUD release surrendered a deflected stick')
controller_observation.right_stick_y=0;sample(0);sample(0)
controller_observation.right_stick_y=1
assert(sample(0)[1] and turn_claim==false,'Directional action failed after neutral')
assert(wheel_hooks.update and wheel_hooks.destroy and wheel_hooks._on_com_wheel_stop)
presentation.controller_bindings.sample=real_sample
print('communication_production_input=pass real_load preclaim turning mapper and neutral_rearm')

-- PTT reads the real semantic hold after mapping, without touching audio APIs.
controller_observation.right_stick_y=0
settings.vr_action_bind_communication_wheel=0
settings.vr_action_bind_push_to_talk=256
settings.vr_hub_action_bind_push_to_talk=-1
mod.on_setting_changed('vr_action_bind_communication_wheel')
mod.on_setting_changed('vr_action_bind_push_to_talk')
local keyboard,chat_blocked=false,false
local chat_source={get=function(_,name)assert(name=='voip_push_to_talk');return keyboard end,
    has=function(_,name)return name=='voip_push_to_talk'end,is_null_service=function()return chat_blocked end}
local chat={_input_service=chat_source}
local function talk()
    local held=chat_hooks.update(function(self)return self._input_service:get('voip_push_to_talk')end,chat)
    assert(chat._input_service==chat_source)
    return held
end
sample(256);assert(not talk(),'Remap inherited a held PTT button')
sample(0);sample(256);assert(talk(),'Production semantic hold never reached stock chat')
sample(0);assert(not talk(),'Physical release left PTT held')
sample(256);assert(talk())
owns=true;assert(not talk(),'UI ownership change between sample and chat update leaked PTT')
keyboard=true;assert(talk(),'Keyboard PTT was swallowed by VR routing loss');keyboard=false
sample(256);owns=false;sample(256);assert(not talk(),'UI recovery inherited the hold')
sample(0);sample(256);assert(talk())
owns=true;assert(not talk());owns=false
assert(not talk(),'A previously blocked PTT owner revived without a new sample')
sample(256);assert(not talk(),'An uninterrupted semantic hold bypassed route-loss rearm')
sample(0);sample(256);assert(talk())
Managers.imgui={using_input=function()return true end};assert(not talk())
Managers.imgui=nil
controller_observation.last_transport_generation=controller_observation.last_transport_generation+1;assert(not talk())
sample(256);assert(not talk());sample(0);sample(256);assert(talk())
mod.on_setting_changed('vr_action_bind_push_to_talk');assert(not talk())
sample(256);assert(not talk());sample(0);sample(256);assert(talk())
local retained
chat_hooks.update(function(self)
    retained=self._input_service;assert(retained:get('voip_push_to_talk'))
    sample(0);assert(not retained:get('voip_push_to_talk'),'Old chat sample revived after release')
end,chat)
sample(256);assert(talk() and not retained:get('voip_push_to_talk'))
chat_blocked=true;assert(not talk());chat_blocked=false
assert(not talk(),'Cached chat service recovery revived a cancelled hold')
sample(256);assert(not talk());sample(0);sample(256);assert(talk())
input_service={is_null_service=function()return true end}
movement(0,0,{0,0,0,0},{0,0,0,0});assert(not talk(),'Fixed null-service cancellation retained PTT')
input_service={is_null_service=function()return false end}
sample(256);assert(not talk());sample(0);sample(256);assert(talk())
presentation.push_to_talk.cancel();assert(not talk())
print('push_to_talk_production_input=pass semantic hold remap generations UI ImGui fixed cancellation and keyboard coexistence; audio mocked')
