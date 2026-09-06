-- Exercise the real adapter seam and mapper without game or desktop input.
bit=require('bit')
local file=assert(io.open(arg[1],'r'))
local source=file:read('*all'); file:close()
local first=assert(source:find('function presentation.inject_ephemeral_action_names',1,true))
local last=assert(source:find('\nmod:hook_safe(',first,true))
mod={get=function() end,info=function() end}
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
local function sample(value)
    physical=value
    owner._ephemeral_action_cache={false,false,true}
    presentation.inject_gameplay_input(owner,.1)
    assert(owner._ephemeral_action_cache[3],'Stock keyboard cache was changed')
    return owner._ephemeral_action_cache
end
sample(0)
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
for _,failure in ipairs({1,-1,2}) do
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
for _,ui in ipairs({{}, {using_input=function() error('retiring') end},
        {using_input=function() return {} end}, {using_input=function() return nil end},
        17,true,setmetatable({}, {__index=function() error('retired proxy lookup') end})}) do
    Managers.ui=ui
    assert(not sample(1)[1] and native_active==0 and not ui_active)
end
Managers.ui=nil
assert(not sample(1)[1] and native_active==0)
print('gameplay_ui_ownership=pass real_adapter overlay_cancel failed_read_cancel neutral_resume stock_cache scanner retiring_owner')
