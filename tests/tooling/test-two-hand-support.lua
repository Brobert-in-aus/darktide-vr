bit=require('bit')
local Support=dofile(assert(arg[1]))
local Pose=dofile(assert(arg[2]))
local Bindings=dofile(assert(arg[3]))
local api=Support.new(Pose)
local mapper=Bindings.install({get=function() end})
local profile={socket={0,.3,0},acquire=.1,release=.2,smoothing=0,ads=true}
api.profiles.example=profile
local frame={active=true,live=true,weapon={},unit={},generation=1,recenter=0,side='left',
    dt=.01,rotation={0,0,0,1},primary={0,0,0},support={0,.3,0},template='example',toggle_ads=false}
local function sample(physical,pressed,held,released,owned)
    local request=api.prepare(frame)
    local p,h,r=mapper.sample(frame.active,physical,0,0,true,frame.generation,'combat',request)
    api.finish(mapper.support_grip)
    assert(p==pressed and h==held and r==released,
        string.format('support integration got %d,%d,%d expected %d,%d,%d',p,h,r,pressed,held,released))
    assert(mapper.support_grip.held==owned)
end
sample(0,0,0,0,false)
sample(512,512,512,0,false) -- Disabled by default, even with a registered socket.
sample(0,0,0,512,false)
api.enabled=true
sample(512,2,2,0,true)
frame.support={.1,.3,0}
sample(512,0,2,0,true)
assert(math.abs(api.rotation(frame.unit,frame.rotation)[3])>.1,'support did not steer')
assert(api.rotation({},frame.rotation)==frame.rotation,'foreign unit received support aim')
frame.live=false
sample(512,0,0,0,false)
assert(api.rotation(frame.unit,frame.rotation)==frame.rotation,'lost tracking retained aim')
frame.live=true; frame.support={0,.3,0}
sample(512,0,0,0,false)
sample(0,0,0,0,false)
for _,transition in ipairs({'recenter','generation','weapon','unit','profile','socket','radius','role','menu'}) do
    frame.side='left'; frame.active=true
    sample(0,0,0,0,false)
    sample(512,2,2,0,true)
    if transition=='recenter' then frame.recenter=frame.recenter+1
    elseif transition=='generation' then frame.generation=frame.generation+1
    elseif transition=='weapon' then frame.weapon={}
    elseif transition=='unit' then frame.unit={}
    elseif transition=='profile' then
        profile={socket={0,.3,0},acquire=.1,release=.2,smoothing=0,ads=true}; api.profiles.example=profile
    elseif transition=='socket' then profile.socket[3]=.01
    elseif transition=='radius' then profile.acquire=.11
    elseif transition=='role' then frame.side='right'
    elseif transition=='menu' then frame.active=false end
    sample(512,0,0,0,false)
    sample(0,0,0,0,false)
end
frame.active=true; frame.side='left'; frame.toggle_ads=true
sample(0,0,0,0,false)
sample(512,0,0,0,true)
assert(api.ads_unavailable,'toggle ADS limitation was hidden')
sample(0,0,0,0,false)
frame.template='unregistered'
sample(512,512,512,0,false) -- No guessed generic socket for another gun/staff.
sample(0,0,0,512,false)
frame.template='example'; profile.socket={0,0,0}
sample(512,512,512,0,false)
print('two_hand_support=pass mapper pose live_tracking identity profiles toggle_guard')

-- Exercise the installed adapter against engine-shaped owners and deliberately
-- retained presentation poses. Live flags, not usable cached wrists, authorize it.
Vector3={x=function(v) return v[1] end,y=function(v) return v[2] end,z=function(v) return v[3] end}
Quaternion={to_elements=function(q) return unpack(q) end,from_elements=function(...) return {...} end}
local unit,equipped={},{}
local primary,secondary={0,0,0},{0,.3,0}
local template={name='example',gun=true}
local action,retired=nil,false
local state_name='walking'
local weapon={weapon_template=function() return template end,
    running_action_settings=function() return action end,
    _wielded_weapon=function() if retired then error('retired') end; return equipped end}
ScriptUnit={has_extension=function(u,name)
    assert(u==unit)
    if name=='weapon_system' then return weapon end
    return {current_state_name=function() return state_name end}
end}
local observations={left_grip_tracking_live=true,right_grip_tracking_live=true,
    left_grip_usable=true,right_grip_usable=true,right_aim_usable=true,
    last_transport_generation=1,head_recenter_generation=0}
local presentation={
    online_rules={simulation_aim_active=function(u) return u==unit end},
    weapon_hand_roles={physical=function(role) return role=='dominant' and 'right' or 'left' end},
    gun_aim={is_gun=function(t) return t.gun end,base_aim=function(_,q) return q end},
    controller_aim_target=function() return primary,{0,0,0,1} end,
    weapon_grip_target=function(role) return role=='dominant' and primary or secondary end}
local commands={}
local installed=Support.install({io_dofile=function() return Pose end,info=function() end,
    command=function(_,name,_,callback) commands[name]=callback end,echo=function() end},presentation,observations)
installed.profiles.example={socket={0,.3,0},acquire=.1,release=.2,smoothing=0,ads=true}
installed.enabled=true
local handler={_input_settings_table={toggle_ads=false}}
local real_mapper=Bindings.install({get=function() end})
local t=0
local function installed_sample(bits)
    t=t+.01
    local req=installed.sample(unit,true,t,handler)
    local p,h,r=real_mapper.sample(true,bits,0,0,true,1,'combat',req)
    installed.finish(real_mapper.support_grip)
    return p,h,r
end
installed_sample(0)
assert(installed_sample(512)==2)
secondary={.1,.3,0}; installed_sample(512)
assert(math.abs(installed.resolve(unit,{0,0,0,1})[3])>.1)
observations.left_grip_tracking_live=false
local p,h,r=installed_sample(512)
assert(p==0 and h==0 and r==0 and observations.left_grip_usable)
assert(installed.resolve(unit,frame.rotation)==frame.rotation)
observations.left_grip_tracking_live=true; secondary={0,.3,0}
installed_sample(0); assert(installed_sample(512)==2)
action={kind='reload'}
assert(installed.resolve(unit,frame.rotation)==frame.rotation,'mid-frame reload retained support')
p,h,r=installed_sample(512); assert(p==0 and h==0 and r==0)
action=nil; installed_sample(0); assert(installed_sample(512)==2)
equipped={}
assert(installed.resolve(unit,frame.rotation)==frame.rotation,'mid-frame weapon switch retained support')
installed_sample(512); installed_sample(0); assert(installed_sample(512)==2)
retired=true
p,h,r=installed_sample(512); assert(p==0 and h==0 and r==0)
assert(installed.failure_logged)
retired=false; installed_sample(0)
state_name='dead'
assert(installed_sample(512)==512,'dead state claimed the support grip')
print('two_hand_support_adapter=pass cached_tracking reload weapon_switch retirement death')
-- Explicit calibration waits for chat to close, then samples real tracked
-- positions after the countdown. It never enables support by itself.
Managers={player={local_player=function() return {player_unit=unit} end}}
state_name='walking'; installed_sample(0)
secondary={.02,.35,-.03}
commands.dtvr_two_hand_calibrate()
assert(installed.capture_pending and not installed.enabled)
local saved=installed.profiles.example
t=t+.1; installed.sample(unit,false,t,handler)
assert(installed.capture_pending and not installed.capture_pending.at)
installed_sample(0)
local deadline=installed.capture_pending.at
while t<deadline-.02 do installed_sample(0) end
assert(installed.profiles.example==saved,'Capture occurred before countdown')
while installed.capture_pending do installed_sample(0) end
local captured=installed.profiles.example
for i=1,3 do assert(math.abs(captured.socket[i]-secondary[i])<1e-8) end
assert(not installed.enabled)
commands.dtvr_two_hand_on(); installed_sample(0)
assert(installed_sample(512)==2,'Calibrated grip did not acquire')
commands.dtvr_two_hand_off()
assert(not installed.enabled and not installed.capture_pending)
installed_sample(0)
for _,transition in ipairs({'menu','weapon','recenter','generation','tracking','reload','timeout'}) do
    state_name='walking'; action=nil
    assert(installed.arm_capture(unit))
    installed_sample(0)
    if transition=='menu' then installed.sample(unit,false,t+.01,handler)
    elseif transition=='weapon' then equipped={}
    elseif transition=='recenter' then observations.head_recenter_generation=observations.head_recenter_generation+1
    elseif transition=='generation' then observations.last_transport_generation=observations.last_transport_generation+1
    elseif transition=='tracking' then observations.left_grip_tracking_live=false
    elseif transition=='reload' then action={kind='reload'}
    elseif transition=='timeout' then t=t+31 end
    installed_sample(0)
    assert(not installed.capture_pending and installed.profiles.example==captured,
        'Capture survived '..transition)
    observations.left_grip_tracking_live=true
end
print('two_hand_calibration=pass countdown explicit_enable interruption identity expiry')
