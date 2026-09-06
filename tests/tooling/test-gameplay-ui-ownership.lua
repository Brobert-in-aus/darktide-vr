-- Exercise the real adapter seam and mapper without game or desktop input.
bit=require('bit')
local file=assert(io.open(arg[1],'r'))
local source=file:read('*all'); file:close()
local first=assert(source:find('function presentation.inject_ephemeral_action_names',1,true))
local last=assert(source:find('\nmod:hook_safe(',first,true))
local settings={}
mod={get=function(_,key) return settings[key] end,info=function() end}
presentation={mode=1,gameplay_context=dofile(arg[2]),
    is_first_person_body_mode=function(mode) return mode=='hub' end,
    apply_controller_turning=function() end}
presentation.controller_bindings=dofile(arg[3]).install(mod)
presentation.gameplay_input_bindings=presentation.controller_bindings.bindings
controller_observation={gameplay_input_enabled=true,gameplay_input_last_check_t=0,
    gameplay_pressed={[0]=0},gameplay_held={[0]=0},gameplay_released={[0]=0},
    gameplay_sequence={[0]=1},gameplay_movement={[0]=0,[1]=0},
    right_stick_x=0,right_stick_y=0,right_aim_usable=true,last_transport_generation=1}
Mods={lua={io={}}}
active_game_mode_name=function() return 'hub' end
local owns,physical,native_active,native_result=false,0,nil,0
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
local player={input_handler=owner}
owner._player=player
Managers.player={local_player=function(_,index) assert(index==1); return player end}
local function sample(value)
    physical=value
    owner._ephemeral_action_cache={false,false,true}
    presentation.inject_gameplay_input(owner,.1)
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
local fixed_hook
mod.hook_safe=function(_,class,method,callback)
    if method=='fixed_update' then fixed_hook=callback end
end
local saved_require=require
require=function() return {} end
local hook_end=assert(source:find('\nfunction presentation.log_unit_pose',last,true))
assert(loadstring(source:sub(last,hook_end-1)))()
require=saved_require
local scans,captures=0,0
presentation.scan_movement_inventory=function() scans=scans+1 end
presentation.online_rules={capture=function() captures=captures+1 end}
fixed_hook(foreign,0,0,1)
fixed_hook(retired,0,0,1)
assert(scans==0 and captures==0)
fixed_hook(owner,0,0,1)
assert(scans==1 and captures==1)
local unsampled={_player=player}
player.input_handler=unsampled
fixed_hook(unsampled,0,0,1)
assert(scans==1 and captures==1,'Unsampled replacement inherited previous fixed input state')
local primary_first=assert(source:find('function presentation.inject_primary_action',1,true))
local primary_last=assert(source:find('\npresentation.controller_bindings =',primary_first,true))
assert(loadstring(source:sub(primary_first,primary_last-1)))()
Mods.lua.io.open=function() error('Foreign handler consumed synthetic test request') end
presentation.inject_primary_action(foreign,1)
print('gameplay_ui_ownership=pass real_adapter overlay_cancel failed_read_cancel neutral_resume stock_cache scanner retiring_owner')
