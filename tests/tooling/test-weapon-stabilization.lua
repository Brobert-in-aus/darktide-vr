local Filter=dofile(assert(arg[1]))
local function yaw(degrees)
    local half=math.rad(degrees)/2
    return {0,0,math.sin(half),math.cos(half)}
end
local function degrees(q) return math.deg(2*math.atan2(q[3],q[4])) end
local function near(a,b) assert(math.abs(a-b)<1e-5,string.format('%g != %g',a,b)) end
local function same(a,b)
    local d=0;for i=1,4 do d=d+a[i]*b[i] end
    assert(math.abs(d)>1-1e-8,'orientation differs')
end
for _,hz in ipairs({90,120}) do
    local state,raw_power,filtered_power={},0,0
    for i=1,hz*4 do
        local raw=.4*math.sin(2*math.pi*12*i/hz)
        local filtered=degrees(Filter.step(state,yaw(raw),i,1+i/hz,1,75,true))
        if i>hz then raw_power=raw_power+raw^2;filtered_power=filtered_power+filtered^2 end
    end
    local ratio=math.sqrt(filtered_power/raw_power)
    assert(ratio<.4,'insufficient tremor reduction')
    state={};local lag=0
    for i=1,hz do
        local raw=180*i/hz
        local filtered=degrees(Filter.step(state,yaw(raw),i,1+i/hz,1,75,true))
        lag=math.max(lag,math.abs(raw-filtered))
    end
    assert(lag<=3.001,'quick aiming exceeds lag bound')
    print(string.format('%d Hz: tremor RMS %.1f%% of raw, fast-turn maximum lag %.3f degrees',hz,ratio*100,lag))
end
local state={}
Filter.step(state,yaw(0),1,1,1,75,true)
local filtered=Filter.step(state,yaw(1),2,1.01,1,75,true)
assert(degrees(filtered)>0 and degrees(filtered)<1)
same(Filter.step(state,yaw(9),2,1.01,1,75,true),filtered) -- multiple consumers
same(Filter.step(state,yaw(20),3,1.02,2,75,true),yaw(20)) -- reconnect
same(Filter.step(state,yaw(30),4,2,2,75,true),yaw(30)) -- stale sample
same(Filter.step(state,yaw(40),2,2.01,2,75,true),yaw(40)) -- sequence rollback
same(Filter.step(state,yaw(50),3,2,2,75,true),yaw(50)) -- clock rollback
same(Filter.step(state,yaw(55),4,2.01,2,0,true),yaw(55)) -- off
same(Filter.step(state,yaw(56),5,2.02,2,75,true),yaw(56)) -- setting change
same(Filter.step(state,yaw(150),6,2.03,2,75,true),yaw(150)) -- discontinuity
assert(Filter.step(state,{0,0,0,0},7,2.04,2,75,true)==nil)
same(Filter.step(state,yaw(0),8,2.05,2,75,true),yaw(0))
same(Filter.step(state,{0,0,0,-1},9,2.06,2,75,true),yaw(0)) -- antipodal quaternion
assert(Filter.step(state,yaw(5),10,2.07,2,75,false)==nil)
assert(Filter.step(state,{0,0,0,0/0},11,2.08,2,75,true)==nil)

-- Exercise the installed wrapper with the game's quaternion and ownership API.
local function mul(a,b)
    return {a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],
        a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],
        a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],
        a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}
end
Quaternion={multiply=mul,inverse=function(q) return {-q[1],-q[2],-q[3],q[4]} end,
    from_elements=function(...) return {...} end,to_elements=function(q) return unpack(q) end}
local unit,weapon,position={},{},{}
local template={keywords={'ranged','force_staff'}}
local extension={weapon_template=function() return template end,
    _inventory_component={wielded_slot='secondary'},_weapons={secondary=weapon}}
Managers={player={local_player_safe=function() return {player_unit=unit} end},ui={}}
Unit={alive=function(u) return not u.dead end}
ScriptUnit={has_extension=function(u,name) assert(u==unit and name=='weapon_system');return extension end}
local side,blocked,raw,strength='right',false,yaw(0),75
local tracking={authoring_enabled=true,right_aim_usable=true,left_aim_usable=true,
    body_anchor_qx=0,body_anchor_qy=0,body_anchor_qz=0,body_anchor_qw=1,
    last_sequence=1,last_transport_generation=1,timestamp_ns={[0]=1e9}}
local presentation={mode=1,weapon_hand_roles={physical=function() return side end},
    gameplay_context={ui_blocks_gameplay=function() return blocked end},
    weapon_aim_target=function() return position,raw end}
Filter.install({get=function() return strength end},presentation,tracking)
local function sample(angle)
    tracking.last_sequence=tracking.last_sequence+1
    tracking.timestamp_ns[0]=tracking.timestamp_ns[0]+1e7
    raw=yaw(angle)
    local pos,q=presentation.weapon_aim_target('dominant')
    assert(pos==position,'hand position must stay unfiltered')
    return q
end
sample(0);assert(degrees(sample(1))<1,'staff aim must be damped')
same(select(2,presentation.weapon_aim_target('support')),raw)
-- Body turning must remain immediate even when the tracked hand sample is cached.
tracking.body_anchor_qz,tracking.body_anchor_qw=yaw(45)[3],yaw(45)[4]
raw=yaw(46)
local turned=select(2,presentation.weapon_aim_target('dominant'))
assert(degrees(turned)>45 and degrees(turned)<46)
tracking.body_anchor_qz,tracking.body_anchor_qw=0,1
blocked=true;same(sample(5),yaw(5));blocked=false;same(sample(6),yaw(6))
tracking.right_aim_usable=false;same(sample(7),yaw(7))
tracking.right_aim_usable=true;same(sample(8),yaw(8))
extension._weapons.secondary={};same(sample(9),yaw(9))
unit={};same(sample(10),yaw(10))
side='left';same(sample(11),yaw(11));assert(degrees(sample(12))<12)
template={keywords={'melee'}};same(sample(20),yaw(20))
template={keywords={'ranged'}};same(sample(21),yaw(21))
presentation.mode=0;same(sample(22),yaw(22))
presentation.mode=1;same(sample(23),yaw(23))
strength=0;same(sample(24),yaw(24))
print('Weapon ownership, staff support, body turning, tracking/UI resets and raw positions pass')
