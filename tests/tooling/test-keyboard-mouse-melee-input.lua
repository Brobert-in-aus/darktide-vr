-- Keyboard and mouse melee roll: never written into the player orientation,
-- applied to the simulated input frame only while an attack runs, as the aim
-- turned about its own look direction.
local file=assert(io.open(arg[1],'r'))
local source=file:read('*all'); file:close()
local KeyboardMouse=dofile(arg[2])
local first=assert(source:find('-- Runs on every orientation update.',1,true))
local last=assert(source:find('\nfunction presentation.keyboard_mouse_view_pitch()',first,true))
local TAU=math.pi*2
local function near(a,b,eps,label) assert(math.abs(a-b)<(eps or 1e-9),(label or '')..' '..tostring(a)..' ~= '..tostring(b)) end

-- Rotation model matching the worn log: yaw/pitch/roll is Z(yaw)*Y(roll)*X(pitch),
-- forward is +Y, and the engine decomposition returns its principal branch.
-- from_yaw_pitch_roll(-1.9991,-0.1220,135 deg) decomposes to 1.1425,3.0196,0.7854,
-- exactly as the log's fp_ypr showed.
local function mat(a) return a end
local function mul(a,b)
    local r={}
    for i=1,3 do r[i]={} for j=1,3 do r[i][j]=a[i][1]*b[1][j]+a[i][2]*b[2][j]+a[i][3]*b[3][j] end end
    return r
end
local function rx(a) local c,s=math.cos(a),math.sin(a) return {{1,0,0},{0,c,-s},{0,s,c}} end
local function ry(a) local c,s=math.cos(a),math.sin(a) return {{c,0,s},{0,1,0},{-s,0,c}} end
local function rz(a) local c,s=math.cos(a),math.sin(a) return {{c,-s,0},{s,c,0},{0,0,1}} end
local function vec(x,y,z) return {x=x,y=y,z=z} end
local convention='measured'
Quaternion={
    from_yaw_pitch_roll=function(y,p,r)
        if convention=='look' then return mul(rz(y),mul(rx(p),ry(r))) end
        return mul(rz(y),mul(ry(r),rx(p)))
    end,
    multiply=mul,
    axis_angle=function(axis,a)
        assert(axis.x==0 and axis.y==1 and axis.z==0,'roll must be about the local look axis'); return ry(a)
    end,
    forward=function(m) return vec(m[1][2],m[2][2],m[3][2]) end,
    up=function(m) return vec(m[1][3],m[2][3],m[3][3]) end,
    to_yaw_pitch_roll=function(m)
        if convention=='look' then
            -- Z*X*Y: M21=sin p.
            local p=math.asin(math.max(-1,math.min(1,m[3][2])))
            return math.atan2(-m[1][2],m[2][2]),p,math.atan2(-m[3][1],m[3][3])
        end
        local r=math.asin(math.max(-1,math.min(1,-m[3][1])))
        return math.atan2(m[2][1],m[1][1]),math.atan2(m[3][2],m[3][3]),r
    end,
}
Vector3=setmetatable({dot=function(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end},
    {__call=function(_,x,y,z) return vec(x,y,z) end})
local function angle(a,b) return math.acos(math.max(-1,math.min(1,Vector3.dot(a,b)))) end
do
    local y,p,r=Quaternion.to_yaw_pitch_roll(Quaternion.from_yaw_pitch_roll(-1.9991,-0.1220,math.rad(135)))
    near(y,1.1425,1e-4,'model yaw'); near(p,3.0196,1e-4,'model pitch'); near(r,0.7854,1e-4,'model roll')
    -- The logged fault: the stock roll moves a pitched aim.
    local f=Quaternion.forward(Quaternion.from_yaw_pitch_roll(-1.9991,-0.1220,math.rad(45)))
    near(math.atan2(-f.x,f.y),-1.9126,5e-3,'model reproduces the logged reticle yaw')
end

-- The real presentation functions.
local logged={}
local presentation={keyboard_mouse=KeyboardMouse.install({get=function() return nil end,info=function() end},function() end)}
presentation.keyboard_mouse_enabled=function() return true end
presentation.hub_third_person_active=function() return false end
presentation.controller_aim_target=function() return nil end
presentation.gameplay_context={local_input_unit=function(handler) return handler.unit end}
local chosen,running,weapon=math.rad(45),false,{name='sword'}
presentation.keyboard_mouse.live=function() return true end
presentation.keyboard_mouse_melee_roll=function()
    return presentation.keyboard_mouse.melee_roll(weapon,running,function() return chosen end)
end
local function hook(handler,dt,t,frame) presentation.apply_keyboard_mouse_roll_input(handler,frame) end
local mod={info=function(_,fmt,...) logged[#logged+1]=string.format(fmt,...) end,
    warning=function(_,fmt,...) error(string.format(fmt,...)) end,
    -- DMF keeps one hook per function per mod: this slice must register none.
    hook_safe=function() error('the melee roll slice registered its own hook') end,
    hook=function() error('the melee roll slice registered its own hook') end}
local env=setmetatable({presentation=presentation,mod=mod,Managers={player={}}},{__index=_G})
setfenv(assert(loadstring(source:sub(first,last-1))),env)()

-- The look roll keeps the aim's direction at every roll and pitch, and the
-- input decomposition reproduces it on a level-range pitch branch.
for _,c in ipairs({{0.4,-7},{-2,12},{1,-40},{2.5,70},{0.2,0}}) do
    for roll_deg=0,315,45 do
        local y,p,r=c[1],math.rad(c[2]),math.rad(roll_deg)
        local aim=Quaternion.from_yaw_pitch_roll(y,p,0)
        local rolled=presentation.keyboard_mouse_look_roll(y,p,r)
        near(angle(Quaternion.forward(rolled),Quaternion.forward(aim)),0,1e-6,'look roll moved the aim')
        local iy,ip,ir,err=presentation.keyboard_mouse_input_euler(rolled)
        assert(iy,'no input branch for pitch '..c[2]..' roll '..roll_deg)
        assert(math.abs(ip)<=math.pi/2+1e-6,'input pitch left the level range')
        near(err,0,1e-6,'input decomposition error')
        local sent=Quaternion.from_yaw_pitch_roll(iy,ip,ir)
        near(angle(Quaternion.forward(sent),Quaternion.forward(aim)),0,1e-6,'sent input does not point along the aim')
    end
end

-- Idle: a roll is chosen, but nothing is written to the orientation or input.
local orientation={_orientation={yaw=1,pitch=0.1,roll=0}}
presentation.apply_keyboard_mouse_melee_roll(orientation,1)
assert(orientation._orientation.roll==0,'the idle roll was written into the player orientation')
assert(presentation.keyboard_mouse_attack_roll==nil,'an idle weapon used the swing roll')
local handler={unit='player',_yaw_index=1,_pitch_index=2,_roll_index=3,
    _buffer_index=function(_,frame) return frame end,_input_cache={{},{},{}}}
local c=handler._input_cache
local function cache(frame,yaw,pitch) c[1][frame],c[2][frame],c[3][frame]=yaw,pitch%TAU,0 end
cache(7,1,math.rad(-10))
hook(handler,0.03,1,7)
assert(c[3][7]==0 and c[1][7]==1,'idle input was changed')

-- Attack: the held roll goes into the input, still pointing along the aim.
running=true
presentation.apply_keyboard_mouse_melee_roll(orientation,1.1)
near(presentation.keyboard_mouse_attack_roll,math.rad(45))
assert(orientation._orientation.roll==0,'the attack roll was written into the player orientation')
chosen=math.rad(180) -- A new choice during the attack is ignored.
presentation.apply_keyboard_mouse_melee_roll(orientation,1.2)
near(presentation.keyboard_mouse_attack_roll,math.rad(45))
cache(8,1,math.rad(-10))
hook(handler,0.03,1.2,8)
local sent=Quaternion.from_yaw_pitch_roll(c[1][8],(c[2][8]+math.pi)%TAU-math.pi,c[3][8])
near(angle(Quaternion.forward(sent),Quaternion.forward(Quaternion.from_yaw_pitch_roll(1,math.rad(-10),0))),0,1e-6,
    'the rolled input does not point along the mouse aim')
assert(c[3][8]~=0,'the attack input was not rolled')
assert(logged[#logged]:find('melee_roll_input deg=45',1,true))
-- An engine whose roll is already about the look direction sends that roll unchanged.
convention='look'
cache(9,1,math.rad(-10))
hook(handler,0.03,1.25,9)
near(c[1][9],1,1e-9); near((c[2][9]+math.pi)%TAU-math.pi,math.rad(-10),1e-9); near(c[3][9],math.rad(45),1e-9)
convention='measured'
-- A controller ray authoring this frame keeps its own aim and roll.
presentation.controller_aim_target=function() return 'hand','rotation' end
cache(10,2,0)
hook(handler,0.03,1.3,10)
assert(c[1][10]==2 and c[3][10]==0,'keyboard and mouse roll overwrote controller aim')
presentation.controller_aim_target=function() return nil end
-- The roll input runs inside the single stock-input fixed_update hook, right
-- after the online-rules capture, where foreign handlers are already rejected.
do
    local capture=assert(source:find('presentation.online_rules.capture(self, frame, dt, t)',1,true))
    local call=assert(source:find('presentation.apply_keyboard_mouse_roll_input(self, frame)',capture,true),
        'the roll input is not applied after the online-rules capture')
    assert(not source:sub(capture,call):find('\nend)',1,true),'the roll input left the fixed_update hook')
end
-- The attack ends: the roll is released.
running=false
presentation.apply_keyboard_mouse_melee_roll(orientation,1.4)
assert(presentation.keyboard_mouse_attack_roll==nil)
cache(12,1,0.2)
hook(handler,0.03,1.4,12)
assert(c[3][12]==0 and c[1][12]==1)
-- Leaving the mode releases it too.
running=true; presentation.apply_keyboard_mouse_melee_roll(orientation,1.5)
presentation.keyboard_mouse_enabled=function() return false end
presentation.apply_keyboard_mouse_melee_roll(orientation,1.6)
assert(presentation.keyboard_mouse_attack_roll==nil)
print('keyboard_mouse_melee_input=pass idle_unrolled attack_roll look_axis_roll level_branch controller_frame look_convention')
