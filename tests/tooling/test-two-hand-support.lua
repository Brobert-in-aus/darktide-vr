bit=require('bit')
local Support=dofile(assert(arg[1]))
local Pose=dofile(assert(arg[2]))
local Bindings=dofile(assert(arg[3]))
local api=Support.new(Pose)
local mapper=Bindings.install({get=function() end})
local profile={socket={0,.3,0},acquire=.1,release=.2,smoothing=0,ads=true}
api.profiles.example=profile
local frame={active=true,live=true,weapon={},unit={},generation=1,recenter=0,side='left',
    dt=.01,rotation={0,0,0,1},primary={0,0,0},support={0,.3,0},template='example',toggle_ads=false,ads_supported=true}
local function sample(physical,pressed,held,released,owned)
    local request=api.prepare(frame)
    local p,h,r=mapper.sample(frame.active,physical,0,0,true,frame.generation,'combat',request)
    api.finish(mapper.support_grip)
    assert(p==pressed and h==held and r==released,
        string.format('support integration got %d,%d,%d expected %d,%d,%d',p,h,r,pressed,held,released))
    assert(mapper.support_grip.held==owned)
end
sample(0,0,0,0,false)
sample(512,2048,2048,0,false) -- Disabled by default, even with a registered socket: left grip is the class ability.
sample(0,0,0,2048,false)
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
sample(512,2048,2048,0,false) -- No guessed generic socket for another gun/staff.
sample(0,0,0,2048,false)
frame.template='example'; profile.socket={0,0,0}
sample(512,2048,2048,0,false)
print('two_hand_support=pass mapper pose live_tracking identity profiles toggle_guard')

-- Exercise the installed adapter against engine-shaped owners and deliberately
-- retained presentation poses. Live flags, not usable cached wrists, authorize it.
Vector3=setmetatable({x=function(v) return v[1] end,y=function(v) return v[2] end,z=function(v) return v[3] end},
    {__call=function(_,...) return {...} end})
Quaternion={to_elements=function(q) return unpack(q) end,from_elements=function(...) return {...} end}
local unit,equipped={},{}
local primary,secondary={0,0,0},{0,.3,0}
local template={name='example',gun=true,alternate_fire_settings={},
    actions={zoom={kind='aim',start_input='zoom'},unzoom={kind='unaim',start_input='unzoom'}},
    action_inputs={zoom={input_sequence={{input='action_two_hold',value=true}}},
        unzoom={input_sequence={{input='action_two_hold',value=false}}}}}
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
    left_grip_usable=true,right_grip_usable=true,right_aim_usable=true,left_aim_usable=true,
    last_transport_generation=1,head_recenter_generation=0}
local support_side='left'
local presentation={
    online_rules={simulation_aim_active=function(u) return u==unit end},
    weapon_hand_roles={physical=function(role)
        if role=='support' then return support_side end
        return support_side=='left' and 'right' or 'left'
    end},
    gun_aim={is_gun=function(t) return t.gun end,base_aim=function(_,q) return q end},
    controller_aim_target=function() return primary,{0,0,0,1} end,
    left_controller_aim_target=function() return primary,{0,0,0,1} end,
    weapon_grip_target=function(role) return role=='dominant' and primary or secondary,{0,0,0,1} end}
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
assert(not installed.stock_active,'Stock enabled without an explicit measured profile')
Unit={world_position=function(u,node) assert(u==unit and node==1); return {0,0,0} end}
Quaternion.yaw=function(q) return 2*math.atan2(q[3],q[4]) end
presentation.body_alignment_unit=unit
observations.body_visual_yaw=0
observations.body_anchor_qx,observations.body_anchor_qy=0,0
observations.body_anchor_qz,observations.body_anchor_qw=0,1
installed.profiles.example.stock={shoulder={.05,-.25,0},offset={0,-.25,0},radius=.2,strength=.5}
local _,stock_hold=installed_sample(512)
assert(stock_hold==0 and not installed.stock_active,'Adding a stock profile retained the old grip gesture')
installed_sample(0); installed_sample(512)
assert(installed.stock_active)
local mounted=installed.resolve(unit,{0,0,0,1})
assert(math.abs(mounted[3])>0,'Production stock did not influence supported aim')
observations.body_visual_yaw=math.pi/2
for i=1,120 do
    installed_sample(512)
    local current=installed.resolve(unit,{0,0,0,1})
    for axis=1,4 do assert(math.abs(current[axis]-mounted[axis])<1e-8,'Head-only body catch-up steered mounted stock') end
end
installed.profiles.example.stock.strength=.3
installed_sample(512)
assert(not installed.held and not installed.stock_active,'In-place stock tuning retained ownership')
observations.body_visual_yaw=0
installed_sample(0); installed_sample(512)
assert(installed.stock_active)
presentation.body_alignment_unit={}
installed_sample(512)
assert(installed.held and not installed.stock_active,'Missing owned body frame did not fall back to two-hand aim')
presentation.body_alignment_unit=unit
installed_sample(512); assert(installed.stock_active)
installed.profiles.example.stock=nil
installed_sample(512); installed_sample(0); installed_sample(512)
assert(installed.held and not installed.stock_active)
print('virtual_stock_adapter=pass opt_in body_owner head_glance tuning_cancel fallback')
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
assert(installed_sample(512)==2048,'dead state claimed the support grip')
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
installed.clear(true)
assert(installed.capture_pending,'Fixed chat ownership cancelled the initial calibration wait')
installed_sample(0)
local deadline=installed.capture_pending.at
while t<deadline-.02 do installed_sample(0) end
assert(installed.profiles.example==saved,'Capture occurred before countdown')
while installed.capture_pending do installed_sample(0) end
local captured=installed.profiles.example
assert(captured.side=='left','Measured grip did not retain its physical hand owner')
local calibrated_weapon=equipped
for i=1,3 do assert(math.abs(captured.socket[i]-secondary[i])<1e-8) end
assert(not installed.enabled)
commands.dtvr_two_hand_on(); installed_sample(0)
assert(installed_sample(512)==2,'Calibrated grip did not acquire')
local hand_writes=0
presentation.body_proxy={place_support_hand=function(world,u,side,position,rotation)
    assert(world=='world' and u==unit and side=='left')
    for i=1,3 do assert(math.abs(position[i]-captured.socket[i])<1e-8) end
    assert(math.abs(rotation[4]-1)<1e-8)
    hand_writes=hand_writes+1; return true
end}
assert(installed.place_hand('world',unit,primary,{0,0,0,1}) and hand_writes==1)
installed_sample(0)
assert(not installed.place_hand('world',unit,primary,{0,0,0,1}) and hand_writes==1,
    'Released support hand stayed constrained')
equipped={}
assert(installed_sample(512)==2048 and not real_mapper.support_grip.held,
    'A different item with the same template inherited a measured grip')
installed_sample(0); equipped=calibrated_weapon
support_side='right'; installed_sample(0)
assert(installed_sample(4)==4 and not real_mapper.support_grip.held,
    'Opposite support hand inherited the other hand measured socket')
installed_sample(0); support_side='left'; installed_sample(0)
assert(installed_sample(512)==2 and real_mapper.support_grip.held,'Original measured hand could not reacquire')
installed_sample(0)
commands.dtvr_two_hand_off()
assert(not installed.enabled and not installed.capture_pending)
installed_sample(0)
for _,transition in ipairs({'menu','fixed_menu','weapon','recenter','generation','tracking','reload','role','timeout'}) do
    state_name='walking'; action=nil; support_side='left'
    assert(installed.arm_capture(unit))
    installed_sample(0)
    if transition=='menu' then installed.sample(unit,false,t+.01,handler)
    elseif transition=='fixed_menu' then installed.clear(true)
    elseif transition=='weapon' then equipped={}
    elseif transition=='recenter' then observations.head_recenter_generation=observations.head_recenter_generation+1
    elseif transition=='generation' then observations.last_transport_generation=observations.last_transport_generation+1
    elseif transition=='tracking' then observations.left_grip_tracking_live=false
    elseif transition=='reload' then action={kind='reload'}
    elseif transition=='role' then support_side='right'
    elseif transition=='timeout' then t=t+31 end
    installed_sample(0)
    assert(not installed.capture_pending and installed.profiles.example==captured,
        'Capture survived '..transition)
    observations.left_grip_tracking_live=true
end
print('two_hand_calibration=pass countdown explicit_enable interruption identity expiry')
-- Execute the actual visual-root entry point; it must not move gameplay bones
-- or a foreign player's hands, and anatomical alignment stays in its helper.
local file=assert(io.open(assert(arg[4]),'rb')); local source=file:read('*a'); file:close()
local first=assert(source:find('function BodyProxy.place_support_hand(',1,true))
local last=assert(source:find('\nfunction BodyProxy.follow_gameplay_hands(',first,true))
local roots={left={},right={}}
local proxy={rigid_hands_active=function() return true end}
local placed
local chunk=assert(loadstring(source:sub(first,last-1)))
setfenv(chunk,{BodyProxy=proxy,state={source_unit=unit},rigid_hands=roots,
    Unit={alive=function(u) return u==unit end},
    place_rigid_hand=function(world,hand,position,rotation,authored)
        assert(world=='world' and hand==roots.left and position==primary and rotation==frame.rotation and authored==nil)
        placed=true; return true
    end}); chunk()
assert(proxy.place_support_hand('world',unit,'left',primary,frame.rotation) and placed)
assert(not proxy.place_support_hand('world',{},'left',primary,frame.rotation))
assert(not proxy.place_support_hand('world',unit,'unknown',primary,frame.rotation))
print('two_hand_visual=pass calibrated_pose release anatomical_boundary local_owner')
assert(Support.ads_supported(template))
local aim_step=template.action_inputs.zoom.input_sequence[1]
aim_step.input_setting={input='action_two_pressed',value=true,setting='toggle_ads',setting_value=true}
assert(Support.ads_supported(template))
aim_step.input_setting.setting='another_preference'
assert(not Support.ads_supported(template))
aim_step.input_setting=nil
template.actions.zoom.kind='charge'
assert(not Support.ads_supported(template),'A charge action was classified as ADS')
state_name='walking'; action=nil; installed.enabled=true; equipped=calibrated_weapon
installed_sample(0)
local unsupported_p,unsupported_h=installed_sample(512)
assert(unsupported_p==0 and unsupported_h==0 and real_mapper.support_grip.held and installed.ads_unavailable,
    'Unsupported secondary action was requested by support grip')
installed_sample(0)
template.actions.zoom.kind='aim'
template.action_inputs.zoom.input_sequence[2]={input='action_one_hold',value=true}
assert(not Support.ads_supported(template),'A compound weapon gesture was classified as plain ADS')
print('two_hand_ads_route=pass canonical_hold toggle_override charge compound unknown_setting')
