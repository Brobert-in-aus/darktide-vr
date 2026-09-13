local KeyboardMouse=dofile(arg[1])
local text=dofile(arg[2])
local function near(a,b,label) assert(math.abs(a-b)<1e-9,(label or '')..' '..tostring(a)..' ~= '..tostring(b)) end
local dz=math.rad(4)
local options={deadzone=dz,horizontal_only=false}
local s={}
near(select(1,KeyboardMouse.step(s,1,0.1,0,0,options)),0,'entry turns')
near(s.aim_yaw,1); near(s.aim_pitch,0.1) -- The aim starts on the view.

-- Small mouse movements stay inside the keyhole and never turn the camera.
local yaw,pitch=KeyboardMouse.step(s,1,0.1,dz*.5,-dz*.5,options)
near(yaw,0); near(pitch,0); near(s.aim_yaw,1+dz*.5); near(s.aim_pitch,0.1-dz*.5)
-- Past the edge the excess turns the camera and the aim stays on the edge.
yaw=KeyboardMouse.step(s,1,0.1,dz,0,options)
near(yaw,dz*.5,'yaw excess'); near(s.aim_yaw,1+dz*1.5)
-- The next view includes that turn: the aim is still at the edge, not reset.
yaw=KeyboardMouse.step(s,1+dz*.5,0.1,0,0,options)
near(yaw,0); near(s.aim_yaw,1+dz*1.5)
-- Turning the head drags the aim along and never turns the camera.
yaw=KeyboardMouse.step(s,1.5,0.1,0,0,options)
near(yaw,0,'head turned camera'); near(s.aim_yaw,1.5-dz)
yaw=KeyboardMouse.step(s,1.5,0.1,-2*dz,0,options)
near(yaw,-2*dz,'mouse after head'); near(s.aim_yaw,1.5-3*dz)

-- Wrapping across the pi seam behaves like any other angle.
s={}
KeyboardMouse.step(s,math.pi-0.01,0,0,0,options)
yaw=KeyboardMouse.step(s,math.pi-0.01,0,0.02+dz,0,options)
near(yaw,0.02,'seam'); near(KeyboardMouse.wrap(s.aim_yaw-(math.pi-0.01+0.02)),dz)

-- Vertical: full mouselook pitches the camera; horizontal-only stops the aim.
s={}
KeyboardMouse.step(s,0,0,0,0,options)
yaw,pitch=KeyboardMouse.step(s,0,0,0,3*dz,options)
near(pitch,2*dz,'pitch drag'); near(s.camera_pitch,2*dz); near(s.aim_pitch,3*dz)
local h={}
local flat={deadzone=dz,horizontal_only=true}
KeyboardMouse.step(h,0,0,0,0,flat)
yaw,pitch=KeyboardMouse.step(h,0,0,0,3*dz,flat)
near(pitch,0,'horizontal only pitched'); near(h.camera_pitch,0); near(h.aim_pitch,dz)
-- Looking up moves the aim with the head in horizontal-only mode.
KeyboardMouse.step(h,0,0.5,0,0,flat)
near(h.aim_pitch,0.5-dz)
-- Camera pitch is bounded; the aim is bounded by the game's limits.
s={}
KeyboardMouse.step(s,0,0,0,0,options)
KeyboardMouse.step(s,0,0,0,10,options,-1.2,1.2)
assert(s.aim_pitch<=1.2+1e-12 and s.camera_pitch<=KeyboardMouse.max_camera_pitch+1e-12)
near(s.camera_pitch,1.2-dz,'pitch against limit')

-- A zero deadzone is plain mouselook: all movement turns the camera.
s={}
local zero={deadzone=0}
KeyboardMouse.step(s,0,0,0,0,zero)
near(KeyboardMouse.step(s,0,0,0.3,0,zero),0.3); near(s.aim_yaw,0.3)

-- Invalid input cannot poison the aim.
s={}
KeyboardMouse.step(s,0,0,0,0,options)
near(KeyboardMouse.step(s,0/0,0,1,0,options),0); near(s.aim_yaw,0)
near(KeyboardMouse.step(s,0,0,0/0,math.huge,options),0); near(s.aim_yaw,0); near(s.aim_pitch,0)

-- Recentre turns the view onto the aim and levels mouse pitch.
s={aim_yaw=0.5,aim_pitch=0.2,camera_pitch=0.3}
near(KeyboardMouse.recenter(s,-0.25),0.75); near(s.camera_pitch,0)

-- Settings are bounded.
local o=KeyboardMouse.options(function(k) return ({keyboard_mouse_deadzone=100})[k] end)
near(o.deadzone,math.rad(40)); assert(o.horizontal_only==true)
o=KeyboardMouse.options(function(k) return ({keyboard_mouse_deadzone=0/0,keyboard_mouse_horizontal_only=false})[k] end)
near(o.deadzone,math.rad(15)); assert(o.horizontal_only==false)

-- Installed observer: mouse delta comes from the stock orientation minus the
-- last written value; discontinuities, owners and menus never read as mouse.
local settings={keyboard_mouse_mode=true,keyboard_mouse_deadzone=4,keyboard_mouse_horizontal_only=false}
local mod={get=function(_,k) return settings[k] end,info=function() end}
local api=KeyboardMouse.install(mod)
local owner={}
local t,dt=10,1/60
local function frame(game_yaw,game_pitch,head_yaw,head_pitch,frozen,who)
    t=t+dt
    api.touch(who or owner,t,dt)
    return api.observe(who or owner,t,game_yaw,game_pitch,head_yaw,head_pitch,frozen)
end
local wy,wp,turn=frame(3,0,1,0)
near(wy,1); near(wp,0); near(turn,0)
wy,wp,turn=frame(1+dz*2,0,1,0) -- Stock added 2 deadzones of mouse yaw.
near(turn,dz,'observed turn'); near(wy,1+2*dz) -- On the edge of the turned view.
assert(api.live(t))
wy,wp,turn=frame(wy+0.5,(0-0.01)%(2*math.pi),1+dz,0,true) -- A menu: no integration.
near(turn,0); near(wy,1+2*dz)
wy,wp,turn=frame(wy,wp,1+dz,0) -- Restored orientation reads as no movement.
near(turn,0)
t=t+0.1 -- Another orientation class ran for several frames.
wy,wp,turn=frame(wy+1,wp,1+dz,0)
near(turn,0,'discontinuity turned'); near(wy,1+dz)
wy,wp,turn=frame(wy,wp,1+dz,0,false,{})
near(turn,0,'owner change turned')
wy,wp,turn=frame(wy,wp,1+dz,0) -- Back to the stock owner: one quiet frame.
near(turn,0)
wy,wp,turn=frame(wy,(-0.2)%(2*math.pi),1+dz,0) -- Mouse down past the edge pitches.
near(wp,(-0.2)%(2*math.pi)); near(api.state.camera_pitch,-(0.2-dz))
local changed
api.on_mode_changed=function(enabled) changed=enabled end
settings.keyboard_mouse_mode=false
mod.on_setting_changed('keyboard_mouse_mode')
assert(changed==false and api.state.aim_yaw==nil and api.state.camera_pitch==0 and not api.live(t))

-- Cursor movement for melee is the recent mouse delta in view space: yaw grows
-- to the left, so rightward motion is negative yaw.
do
    local deg=math.rad
    local m_settings={keyboard_mouse_mode=true,keyboard_mouse_deadzone=4,keyboard_mouse_horizontal_only=false}
    local m_api=KeyboardMouse.install({get=function(_,k) return m_settings[k] end,info=function() end},function() end)
    local mt,who=50,{}
    local function step(yaw,pitch,gyaw,gpitch)
        mt=mt+1/60; m_api.touch(who,mt,1/60)
        return m_api.observe(who,mt,gyaw,gpitch,yaw,pitch,false)
    end
    local wy,wp=step(0,0,0,0)
    wy,wp=step(0,0,(wy-0.01)%(2*math.pi),(wp+0.004)%(2*math.pi)) -- right and up
    wy,wp=step(0,0,(wy-0.01)%(2*math.pi),wp)
    local dx,dy=m_api.mouse_motion(mt)
    near(dx,0.02,'cursor right'); near(dy,0.004,'cursor up')
    near(select(1,m_api.mouse_motion(mt+0.5)),0,'stale motion counted')
    -- The roll is chosen while idle and held from the attack's first update.
    local weapon,choice={},deg(90)
    local roll,held=m_api.melee_roll(weapon,false,function() return choice end)
    near(roll,deg(90)); assert(not held)
    choice=deg(180)
    roll,held=m_api.melee_roll(weapon,true,function() return choice end)
    near(roll,deg(90),'attack took a new direction'); assert(held)
    roll,held=m_api.melee_roll(weapon,true,function() return choice end)
    near(roll,deg(90)); assert(not held,'hold reported twice')
    near(select(1,m_api.melee_roll(weapon,false,function() return choice end)),deg(180))
    near(select(1,m_api.melee_roll({},true,function() return choice end)),0,'new weapon inherited a roll')
    near(select(1,m_api.melee_roll(nil,false,function() return choice end)),0)
end

-- Third-person hub: the stock mouse orbit turns the view by the same yaw,
-- never across a first sample, a gap or another orientation class.
local orbiter={}
local function orbit(game_yaw,written_yaw,gap)
    t=t+(gap or dt)
    api.touch(orbiter,t,dt)
    return api.orbit_turn(orbiter,t,game_yaw,written_yaw)
end
near(orbit(1.0,0.5),0,'first orbit sample turned')
near(orbit(0.7,0.5),0.2,'orbit did not turn the view')
near(orbit(0.1,2*math.pi-0.1),0.2,'orbit across the seam')
near(orbit(-0.3,0.2),-0.5,'orbit the other way')
near(orbit(1.5,0.5,0.1),0,'orbit after a gap turned')
near(orbit(0.6,0.5),0.1)
near(orbit(0.9,nil),0,'orbit without a written yaw turned')

-- Melee direction follows the cursor. The chosen roll turns the authored swing
-- onto the mouse's direction, in 45-degree steps, for either roll sign.
local deg=math.rad
local function turned(authored,sign,roll) return KeyboardMouse.wrap(authored+sign*roll) end
for _,authored in ipairs({0,deg(180),deg(-30),deg(100)}) do
    for _,sign in ipairs({1,-1}) do
        for step=0,7 do
            local want=deg(45*step)
            local roll=KeyboardMouse.melee_roll(math.cos(want)*0.05,math.sin(want)*0.05,authored,sign)
            assert(roll>=0 and roll<2*math.pi,'roll outside [0, 2pi)')
            near(math.abs(KeyboardMouse.wrap(roll/deg(45)-math.floor(roll/deg(45)+0.5))),0,'roll not a 45-degree step')
            local delta=math.abs(KeyboardMouse.wrap(turned(authored,sign,roll)-want))
            assert(delta<=deg(22.5)+1e-9,('swing %.0f sign %d toward %.0f missed by %.1f'):format(
                math.deg(authored),sign,math.deg(want),math.deg(delta)))
        end
    end
end
-- A right-to-left swing flips for a rightward flick; an upward flick turns it up.
near(KeyboardMouse.melee_roll(0.05,0,deg(180),1),deg(180))
near(turned(deg(180),1,KeyboardMouse.melee_roll(0,0.05,deg(180),1)),deg(90))
-- A still mouse or an unknown swing keeps the stock swing.
near(KeyboardMouse.melee_roll(deg(0.2),0,0,1),0)
near(KeyboardMouse.melee_roll(0.05,0,nil,1),0)
near(KeyboardMouse.melee_roll(0.05,0,0,0),0)
near(KeyboardMouse.melee_roll(0/0,0,0,1),0)
-- A moving cursor gives its own direction; a still one swings from the
-- reticle toward the view centre; a centred still reticle keeps the stock swing.
local mx,my=KeyboardMouse.melee_direction(0.03,-0.01,0.2,0.2)
near(mx,0.03); near(my,-0.01)
mx,my=KeyboardMouse.melee_direction(0,0,0.2,-0.1) -- right of centre, low
near(mx,-0.2); near(my,0.1)
mx,my=KeyboardMouse.melee_direction(deg(0.1),0,-0.1,0.1) -- drift below the threshold
near(mx,0.1); near(my,-0.1)
assert(KeyboardMouse.melee_direction(0,0,deg(0.1),0)==nil)
assert(KeyboardMouse.melee_direction(0/0,0,0/0,0)==nil)
-- The four quadrants of the deadzone, through to a roll for a left-to-right swing.
for _,case in ipairs({{-0.1,0.1,deg(315)},{0.1,0.1,deg(225)},{0.1,-0.1,deg(135)},{-0.1,-0.1,deg(45)}}) do
    local qx,qy=KeyboardMouse.melee_direction(0,0,case[1],case[2])
    near(turned(0,1,KeyboardMouse.melee_roll(qx,qy,0,1)),KeyboardMouse.wrap(case[3]),'quadrant direction')
end
-- The swing basis comes from the unrolled and 45-degree samples.
local authored,sign=KeyboardMouse.swing_basis(-1,0,-math.cos(deg(45)),-math.sin(deg(45)))
near(authored,deg(180)); assert(sign==1)
authored,sign=KeyboardMouse.swing_basis(0,-1,math.sin(deg(45)),-math.cos(deg(45)))
near(authored,deg(-90)); assert(sign==1)
authored,sign=KeyboardMouse.swing_basis(1,0,math.cos(deg(45)),-math.sin(deg(45)))
near(authored,0); assert(sign==-1)
assert(KeyboardMouse.swing_basis(0,0,1,0)==nil and KeyboardMouse.swing_basis(1,0,1,0)==nil)
assert(KeyboardMouse.swing_basis(nil,0,1,0)==nil)

-- Controllers are ignored only inside the mode with Disable controllers on;
-- otherwise both inputs add together.
local function disabled(values,forced)
    return KeyboardMouse.controllers_disabled(function(k) return values[k] end,forced)
end
assert(not disabled({}) and not disabled({keyboard_mouse_disable_controllers=true}))
assert(disabled({keyboard_mouse_mode=true}),'Disable controllers must default on')
assert(not disabled({keyboard_mouse_mode=true,keyboard_mouse_disable_controllers=false}))
assert(disabled({},true) and not disabled({keyboard_mouse_disable_controllers=false},true))

-- KeyboardMouseOn switch: any matching name forces the mode on at launch and
-- for the session; Disable controllers stays the player's own choice.
local patterns={}
local function finder_for(name) return function(pattern) patterns[#patterns+1]=pattern; return name end end
assert(KeyboardMouse.find_switch(finder_for('KeyboardMouseOn.txt'))=='KeyboardMouseOn.txt')
assert(patterns[1]:find('*KeyboardMouseOn*',1,true) and patterns[1]:find('mods\\darktidevr\\',1,true))
assert(KeyboardMouse.find_switch(finder_for(nil))==nil)
assert(KeyboardMouse.find_switch(function() error('no ffi') end,
    {open=function(path) return path:match('KeyboardMouseOn$') and {close=function() end} or nil end})=='KeyboardMouseOn',
    'exact-name fallback missed the renamed switch')
assert(KeyboardMouse.find_switch(nil,{open=function() return nil end})==nil)
local switch_settings={keyboard_mouse_mode=false,keyboard_mouse_disable_controllers=false}
local writes=0
local switch_mod={get=function(_,k) return switch_settings[k] end,
    set=function(_,k,v) writes=writes+1; switch_settings[k]=v end,info=function() end}
local switched=KeyboardMouse.install(switch_mod,finder_for('KeyboardMouseOn'))
assert(switched.switch_file=='KeyboardMouseOn' and switched.enabled())
assert(writes==0 and switch_settings.keyboard_mouse_mode==false,'the switch saved the mode')
assert(not switched.controllers_disabled(),'the switch overrode Disable controllers')
switch_settings.keyboard_mouse_mode=false -- The in-game toggle cannot turn it off.
assert(switched.enabled())
switch_settings.keyboard_mouse_disable_controllers=true -- Disabled in the menu while forced.
assert(switched.controllers_disabled())
-- Renamed back to Off: the next launch follows the saved mode, which the file
-- never set, so controllers work again even with Disable controllers left on.
local plain=KeyboardMouse.install(switch_mod,finder_for(nil))
assert(plain.switch_file==nil and not plain.enabled() and not plain.controllers_disabled(),
    'switching the file off left controllers disabled')
assert(writes==0)

-- Controller cooldown: keyboard or mouse use withholds controller aim and hands
-- until three seconds pass without either.
do
    local saved_vector=Vector3
    Vector3={length_squared=function(v) return v[1]*v[1]+v[2]*v[2] end}
    local function raw(buttons,axes,pressed)
        return {active=function() return true end,any_pressed=function() return pressed==true end,
            num_buttons=function() return #buttons end,button=function(i) return buttons[i+1] end,
            axis_index=function(name) return axes[name] and name or nil end,
            axis=function(name) return axes[name] end}
    end
    local keyboard={device_type='keyboard',_raw_device=raw({0,0,0},{})}
    local mouse={device_type='mouse',_raw_device=raw({0,0},{mouse={0,0},wheel={0,0}})}
    local pad={device_type='xbox_controller',_raw_device=raw({1},{},true)}
    local devices={keyboard,mouse,pad}
    assert(KeyboardMouse.device_activity(pad)==false,'a gamepad counted as keyboard or mouse use')
    local c=KeyboardMouse.install(switch_mod,finder_for(nil))
    assert(not c.recent_input(),'controllers withheld before any keyboard or mouse use')
    assert(not c.sample_devices(devices,10,true) and not c.recent_input(),'idle devices withheld controllers')
    mouse._raw_device=raw({0,0},{mouse={0.2,0},wheel={0,0}})
    assert(c.sample_devices(devices,10.1,true) and c.recent_input(),'mouse movement left controllers aiming')
    mouse._raw_device=raw({0,0},{mouse={0,0},wheel={0,0}})
    assert(not c.sample_devices(devices,13.0,true) and c.recent_input(),'the cooldown ended early')
    -- A held key (walking) keeps the cooldown running.
    keyboard._raw_device=raw({0,1,0},{})
    c.sample_devices(devices,13.05,true)
    keyboard._raw_device=raw({0,0,0},{})
    assert(not c.sample_devices(devices,16.0,true) and c.recent_input())
    assert(c.sample_devices(devices,16.06,true) and not c.recent_input(),'controllers stayed withheld after 3 idle seconds')
    -- Menus do not count: the viewer turns controller pointing into mouse events.
    local click={{device_type='mouse',_raw_device=raw({1},{},true)}}
    assert(not c.sample_devices(click,17,false) and not c.recent_input())
    assert(c.sample_devices(click,17.1,true) and c.recent_input())
    -- A restarted clock does not hold controllers off indefinitely.
    c.sample_devices(devices,1,true)
    assert(not c.recent_input(),'a clock restart froze the cooldown')
    assert(c.controller_cooldown==3)
    Vector3=saved_vector
end

-- Every setting is localized, with the recentre key directly below the toggle
-- and Disable controllers after it.
local widget=KeyboardMouse.widgets(false)
assert(widget.type=='checkbox' and widget.default_value==false and widget.title==nil)
assert(widget.sub_widgets[2].setting_id=='keyboard_mouse_disable_controllers' and
    widget.sub_widgets[2].type=='checkbox' and widget.sub_widgets[2].default_value==true)
assert(widget.sub_widgets[4].setting_id=='keyboard_mouse_deadzone' and widget.sub_widgets[4].default_value==15 and
    widget.sub_widgets[4].range[2]==40,'reticle deadzone is not the larger adjustable default')
assert(widget.sub_widgets[1].setting_id=='keyboard_mouse_recenter_keybind' and
    widget.sub_widgets[1].function_name=='recenter_vr_view')
for _,w in ipairs({widget,unpack(widget.sub_widgets)}) do
    assert(text[w.setting_id] and text[w.setting_id].en,'missing text '..w.setting_id)
    assert(text[w.setting_id..'_description'] and text[w.setting_id..'_description'].en)
    assert(pcall(string.format,text[w.setting_id].en))
    if w.type=='numeric' then assert(w.default_value>=w.range[1] and w.default_value<=w.range[2]) end
end
-- The menu says when the switch file holds the mode on.
local locked=KeyboardMouse.widgets('KeyboardMouseOn')
assert(locked.title=='keyboard_mouse_mode_switch_on' and text[locked.title].en:find('KeyboardMouseOn',1,true))
assert(text[locked.tooltip].en:find('KeyboardMouseOff',1,true))
assert(#locked.sub_widgets==#widget.sub_widgets)
print('keyboard_mouse=pass keyhole head_drag mouse_turn pitch horizontal_only recenter observer controllers switch_file settings')
