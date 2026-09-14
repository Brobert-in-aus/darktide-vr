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
-- Grip zone: entered at the acquire radius, left ZONE_EXIT_MARGIN further out;
-- the glove blend eases up while in the zone and back down after.
do
    frame.support={0,.3,0}; sample(0,0,0,0,false)
    assert(api.in_zone and api.snap>0,'hand at the grip was not in the zone')
    frame.support={.11,.3,0}; sample(0,0,0,0,false); assert(api.in_zone,'left the zone inside the exit margin')
    frame.support={.12,.3,0}; sample(0,0,0,0,false); assert(not api.in_zone,'stayed in the zone beyond the margin')
    frame.support={.105,.3,0}; sample(0,0,0,0,false); assert(not api.in_zone,'re-entered outside the acquire radius')
    for _=1,11 do sample(0,0,0,0,false) end
    assert(api.snap==0 and api.hand_pose(frame.unit,{0,0,0},{0,0,0,1})==nil,'glove blend outlived the zone')
    frame.support={0,.3,0}
    for _=1,11 do sample(0,0,0,0,false) end
    local _,_,_,weight=api.hand_pose(frame.unit,{0,0,0},{0,0,0,1})
    assert(api.snap==1 and weight==1,'glove did not reach the grip within SNAP_SECONDS')
    assert(Support.snap_ease(.5)==.5 and Support.snap_ease(0)==0 and Support.snap_ease(2)==1)
    assert(Support.snap_ease(.25)<.25 and Support.snap_ease(.75)>.75,'blend is not eased')
    frame.live=false; sample(0,0,0,0,false); frame.live=true
    assert(api.snap==0 and not api.in_zone,'lost tracking kept the glove on the grip')
end
-- Held grips keep any hand spacing; hands brought together end them.
do
    sample(0,0,0,0,false)
    sample(512,2,2,0,true)
    for _,spacing in ipairs({.6,1.2,.2}) do frame.support={0,spacing,0}; sample(512,0,2,0,true) end
    frame.support={.02,.03,0}
    sample(512,0,0,0,false) -- hands together: no direction
    frame.support={0,.3,0}
    sample(0,0,0,0,false)
end
-- Toggle grip: a press takes the grip, letting go keeps it, the next press
-- ends it without reaching the bound action; moving away still cancels.
do
    sample(0,0,0,0,false)
    api.grip_toggle=function() return true end
    sample(512,2,2,0,true)
    sample(0,0,2,0,true)
    sample(0,0,2,0,true)
    sample(512,0,0,2,false) -- ending press: no class ability
    sample(512,0,0,0,false)
    sample(0,0,0,0,false) -- and no release edge for it
    sample(512,2,2,0,true)
    sample(0,0,2,0,true)
    frame.support={.3,.9,.2}
    sample(0,0,2,0,true) -- hands far apart keep a toggled grip
    frame.support={0,-.3,0}
    sample(0,0,0,0,false) -- crossed behind the gun hand: no direction, released
    frame.support={0,.3,0}
    sample(0,0,0,0,false)
    sample(512,2,2,0,true)
    api.grip_toggle=function() return false end
    sample(0,0,0,2,false) -- switching to hold mode releases on let-go
    sample(0,0,0,0,false)
end
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
local infos={}
local installed=Support.install({io_dofile=function() return Pose end,
    info=function(_,format,...) infos[#infos+1]=string.format(format,...) end,
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
-- Losing the hold logs the largest aim correction applied while held.
local released=infos[#infos]
local steer=tonumber(released:match('^DARKTIDEVR_TWO_HAND released source=calibrated mode=hold ended=cancelled max_steer_degrees=([%d.]+) steered_frames=%d+ steadying=classic virtual_stock=false stock_frames=0 stock_min_distance_m=none$'))
assert(steer and steer>15 and steer<25,'release log: '..tostring(released))
assert(installed.resolve(unit,frame.rotation)==frame.rotation)
observations.left_grip_tracking_live=true; secondary={0,.3,0}
installed_sample(0); assert(installed_sample(512)==2)
-- Reloading and bashing keep the grip; inspecting ends it.
for _,kind in ipairs({'sweep','push','windup'}) do
    action={kind=kind}
    local _,bash_held=installed_sample(512)
    assert(bash_held==2 and real_mapper.support_grip.held,kind..' released the support grip')
end
action={kind='reload_state'}
assert(installed.resolve(unit,frame.rotation)~=frame.rotation,'reload dropped two-hand support')
do local _,reload_held=installed_sample(512); assert(reload_held==2 and real_mapper.support_grip.held,'reload released the support grip') end
action={kind='inspect'}
assert(installed.resolve(unit,frame.rotation)==frame.rotation,'mid-frame inspect retained support')
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
local weights={}
presentation.body_proxy={place_support_hand=function(world,u,side,position,rotation,authored,weight)
    assert(world=='world' and u==unit and side=='left')
    assert(weight>0 and weight<=1); weights[#weights+1]=weight
    for i=1,3 do assert(math.abs(position[i]-captured.socket[i])<1e-8) end
    assert(math.abs(rotation[4]-1)<1e-8)
    hand_writes=hand_writes+1; return true
end}
assert(installed.place_hand('world',unit,primary,{0,0,0,1}) and hand_writes==1)
-- Released with the hand still at the grip: the glove stays there.
installed_sample(0)
assert(installed.place_hand('world',unit,primary,{0,0,0,1}) and hand_writes==2,
    'Glove left the grip while the hand was still in the zone')
-- Hand away: the glove eases back to the tracked hand, then is left alone.
local at_grip=secondary
secondary={at_grip[1]+.3,at_grip[2],at_grip[3]}
local previous=weights[#weights]
for _=1,math.ceil(Support.SNAP_SECONDS/.01)+1 do
    installed_sample(0)
    if installed.place_hand('world',unit,primary,{0,0,0,1}) then
        assert(weights[#weights]<previous,'glove did not ease back'); previous=weights[#weights]
    end
end
assert(not installed.place_hand('world',unit,primary,{0,0,0,1}),
    'Released support hand stayed constrained')
secondary=at_grip
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
        assert(world=='world' and hand==roots.left and position==primary and rotation==frame.rotation and
            authored==(placed=='expect_authored'))
        placed=true; return true
    end}); chunk()
assert(proxy.place_support_hand('world',unit,'left',primary,frame.rotation) and placed)
-- An authored grip passes the stock joint rotation through unconverted.
placed='expect_authored'
assert(proxy.place_support_hand('world',unit,'left',primary,frame.rotation,true) and placed==true)
assert(not proxy.place_support_hand('world',{},'left',primary,frame.rotation))
assert(not proxy.place_support_hand('world',unit,'unknown',primary,frame.rotation))
-- A blend weight eases from the glove's already placed (tracked) pose toward
-- the grip; a calibrated rotation is converted to the joint first.
do
    local glove={}
    roots.left.ready,roots.left.unit=true,glove
    local env=getfenv(chunk)
    env.Unit={alive=function(u) return u==unit or u==glove end,has_node=function() return true end,
        node=function() return 7 end,world_position=function() return {0,0,0} end,
        world_rotation=function() return 'tracked' end}
    env.Vector3={lerp=function(a,b,w) return {a[1]+(b[1]-a[1])*w,a[2]+(b[2]-a[2])*w,a[3]+(b[3]-a[3])*w} end}
    env.Quaternion={lerp=function(a,b,w) return {a,b,w} end}
    env.anatomical_hand_rotation=function(u,side) assert(u==glove and side=='left'); return 'joint' end
    local written
    env.place_rigid_hand=function(_,hand,position,rotation,authored)
        assert(hand==roots.left); written={position,rotation,authored}; return true
    end
    assert(proxy.place_support_hand('world',unit,'left',{1,2,3},'controller',false,.25))
    assert(math.abs(written[1][1]-.25)<1e-9 and math.abs(written[1][3]-.75)<1e-9)
    assert(written[2][1]=='tracked' and written[2][2]=='joint' and written[2][3]==.25 and written[3]==true)
    assert(proxy.place_support_hand('world',unit,'left',{1,2,3},'stock',true,.5) and written[2][2]=='stock')
    written=nil
    assert(not proxy.place_support_hand('world',unit,'left',{1,2,3},'stock',true,0) and written==nil,
        'zero weight moved the glove')
end
print('two_hand_visual=pass calibrated_pose release anatomical_boundary local_owner zone_blend')
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

-- Authored grips per template: shipped and stored grips are ready at once,
-- the draw's settled hand gives one before the weapon is steady, and the
-- steady average replaces it (never mid-hold), is stored, then sampling stops.
do
    local left={-.03,.35,-.04}
    local rig={}
    local rig_reads=0
    Unit={alive=function(u) return u==rig end,has_node=function() return true end,
        node=function(_,name) return name end,
        world_position=function(_,node) rig_reads=rig_reads+1; return node=='j_lefthand' and left or {0,0,0} end,
        world_rotation=function() return {0,0,0,1} end}
    local grip_action={kind='wield'}
    local gun={name='gun_p1_m1'}
    local owner={}
    local item={}
    ScriptUnit={has_extension=function(u,name)
        assert(u==owner)
        if name=='first_person_system' then return {_first_person_unit=rig} end
        if name=='weapon_system' then return {running_action_settings=function() return grip_action end} end
    end}
    -- Every shipped grip is a plausible authored socket with a unit rotation.
    for name,grip in pairs(Support.SHIPPED_GRIPS) do
        local s,h,limits=grip.socket,grip.hand_rotation,Pose.AUTHORED_LIMITS
        assert(s[2]>=limits.min_forward and math.abs(s[1])<=limits.max_lateral and
            math.abs(s[3])<=limits.max_vertical,'implausible shipped grip '..name)
        assert(math.abs(h[1]^2+h[2]^2+h[3]^2+h[4]^2-1)<1e-3,'shipped hand rotation not unit '..name)
    end
    assert(Support.SHIPPED_GRIPS.galvanic_rifle_p1_m1)
    Support.SHIPPED_GRIPS={shipped_p1_m1={socket={0,.3,0},hand_rotation={0,0,0,1}},
        stored_p1_m1={socket={0,.3,0},hand_rotation={0,0,0,1}}}
    local saved,lines={stored_p1_m1={socket={.01,.31,0},hand_rotation={0,0,0,1}},
        broken_p1_m1={socket={0/0,0,0},hand_rotation={0,0,0,1}}},{}
    local sets=0
    local grips=Support.install({io_dofile=function() return Pose end,
        info=function(_,format,...) lines[#lines+1]=string.format(format,...) end,
        get=function(_,key) return key==Support.STORE_KEY and saved or nil end,
        set=function(_,key,value) assert(key==Support.STORE_KEY); saved=value; sets=sets+1 end},
        presentation,observations)
    Support.SHIPPED_GRIPS={}
    assert(grips.authored_profile({template='shipped_p1_m1'}).source=='shipped')
    local stored=grips.authored_profile({template='stored_p1_m1'})
    assert(stored.source=='stored' and stored.socket[1]==.01,'stored grip did not override the shipped one')
    assert(grips.authored_profile({template='broken_p1_m1'})==nil,'invalid stored grip accepted')
    local function observe(n) for _=1,n do grips.observe_authored(owner,item,gun,{0,0,0,1}) end end
    -- During the draw: nothing until the hand has settled for SETTLE_FRAMES.
    observe(Support.SETTLE_FRAMES-1)
    assert(grips.authored_profile({template='gun_p1_m1'})==nil,'grip before the hand settled')
    observe(1)
    local settled=assert(grips.authored_profile({template='gun_p1_m1'}),'settled hand gave no grip')
    assert(settled.source=='settled' and settled.weapon==nil and sets==0)
    for i=1,3 do assert(math.abs(settled.socket[i]-left[i])<1e-9) end
    assert(lines[#lines]:find('source=settled',1,true) and lines[#lines]:find('frames_after_wield=6',1,true))
    -- Steady frames: the average completes while held and waits for release.
    grip_action=nil
    grips.held=true
    observe(Support.AUTHORED_SAMPLES+5)
    assert(grips.authored_profile({template='gun_p1_m1'})==settled and sets==0,'grip swapped mid-hold')
    grips.held=false
    observe(1)
    local measured=grips.authored_profile({template='gun_p1_m1'})
    assert(measured.source=='measured' and sets==1 and saved.gun_p1_m1 and saved.stored_p1_m1,
        'measured grip not stored beside earlier grips')
    local reads=rig_reads
    observe(50)
    assert(rig_reads==reads,'sampling continued after the grip was final')
    -- A one-handed weapon: a resting hand during the draw is dropped once the
    -- steady hand is off the weapon, and nothing is stored.
    local pistol={name='pistol_p1_m1'}
    grip_action={kind='wield'}
    for _=1,Support.SETTLE_FRAMES do grips.observe_authored(owner,item,pistol,{0,0,0,1}) end
    assert(grips.authored_profile({template='pistol_p1_m1'}).source=='settled')
    grip_action=nil; left={-.3,.05,-.3}
    for _=1,120 do grips.observe_authored(owner,item,pistol,{0,0,0,1}) end
    assert(grips.authored_profile({template='pistol_p1_m1'})==nil and sets==1,'one-handed grip kept')
    assert(lines[#lines]:find('authored_grip=none template=pistol_p1_m1',1,true))
    -- A stored grip within STORE_TOLERANCE of the measurement is kept as is.
    left={.01,.31,0}; grip_action=nil
    local stored_gun={name='stored_p1_m1'}
    for _=1,Support.AUTHORED_SAMPLES do grips.observe_authored(owner,item,stored_gun,{0,0,0,1}) end
    assert(grips.authored_profile({template='stored_p1_m1'})==stored and sets==1,'unchanged stored grip rewritten')
    print('two_hand_authored_grips=pass shipped stored settled deferred_swap store stop one_handed unchanged')
end
-- Steadying option: classic passes no steady table; hands line passes the
-- frame's scene basis to the pose filter.
do
    local seen={}
    local SpyPose=setmetatable({new=function()
        local inner=Pose.new()
        local wrapper=setmetatable({},{__index=inner})
        function wrapper.update(...)
            local steady=select(11,...)
            seen[#seen+1]=steady and {mode=steady.mode,scene=steady.scene} or false
            local result=inner.update(...)
            wrapper.owner=inner.owner
            return result
        end
        function wrapper.reset() inner.reset(); wrapper.owner=nil end
        return wrapper
    end},{__index=Pose})
    local spy=Support.new(SpyPose)
    spy.enabled=true
    spy.profiles.example={socket={0,.3,0},acquire=.1,release=.2,smoothing=.07,ads=false}
    local spy_mapper=Bindings.install({get=function() end})
    local f={active=true,live=true,weapon={},unit={},generation=1,recenter=0,side='left',dt=.01,
        rotation={0,0,0,1},primary={0,0,0},support={0,.3,0},template='example',toggle_ads=false,ads_supported=true,
        scene_rotation={0,0,math.sin(.3),math.cos(.3)}}
    local function step(physical)
        local request=spy.prepare(f)
        spy_mapper.sample(true,physical,0,0,true,f.generation,'combat',request)
        spy.finish(spy_mapper.support_grip)
    end
    step(0) -- a grip starts from neutral input
    step(512)
    assert(spy_mapper.support_grip.held and seen[#seen]==false,'classic passed a steady table')
    function spy.steadying() return 'hands_line' end
    step(512)
    local last=seen[#seen]
    assert(last and last.mode=='hands_line' and last.scene==f.scene_rotation,'hands line did not receive the scene basis')
    assert(spy_mapper.support_grip.held,'grip not held')
    assert(spy.held,'hands line hold not owned')
end
print('two_hand_steadying=pass classic hands_line scene_basis')
-- Virtual stock (option): a butt near the body-frame shoulder engages the stock.
do
    local stock_api=Support.new(Pose)
    stock_api.enabled=true
    stock_api.profiles.example={socket={0,.3,0},acquire=.1,release=.2,smoothing=0,ads=false}
    local stock_mapper=Bindings.install({get=function() end})
    local f={active=true,live=true,weapon={},unit={},generation=1,recenter=0,side='left',dt=.01,
        rotation={0,0,0,1},primary={0,0,0},support={.05,.3,0},template='example',toggle_ads=false,ads_supported=true}
    local function step(physical)
        local request=stock_api.prepare(f)
        stock_mapper.sample(true,physical,0,0,true,f.generation,'combat',request)
        stock_api.finish(stock_mapper.support_grip)
    end
    local butt=Support.STOCK.offset
    -- Option off: no stock even with an anchor.
    f.stock_anchor={butt[1]+.02,butt[2],butt[3]}
    step(0); step(512)
    assert(stock_api.held and not stock_api.stock_active,'stock engaged with the option off')
    function stock_api.virtual_stock() return true end
    step(512)
    -- The swing toward the off-axis front hand moves the butt a few cm; still in contact.
    assert(stock_api.stock_active and stock_api.stock_weight>0,'butt at the shoulder did not engage')
    assert(stock_api.stock_distance<Support.STOCK.radius,'distance '..tostring(stock_api.stock_distance))
    -- Aim now follows shoulder -> support hand, not grip -> support hand.
    local plain=Pose.correction(f.rotation,f.primary,f.support,{0,.3,0})
    local steered=stock_api.rotation(f.unit,f.rotation)
    assert(math.abs(steered[3]-plain[3])>1e-4,'stock did not change the aim')
    -- Anchor far away: no contact.
    f.stock_anchor={1,1,1}
    step(512)
    assert(stock_api.held and not stock_api.stock_active and stock_api.stock_weight==0,'far anchor engaged')
    -- No anchor (no body frame): ordinary two-handing.
    f.stock_anchor=nil
    step(512)
    assert(stock_api.held and not stock_api.stock_active,'engaged without an anchor')
end
print('two_hand_virtual_stock=pass option_off contact aim far none')
