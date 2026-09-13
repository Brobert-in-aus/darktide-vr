-- Execute the actual headset-relative melee direction from darktidevr.lua with
-- vector fixtures: +X right, +Y forward, +Z up. A quaternion fixture is simply
-- its basis vectors.
local file=assert(io.open(arg[1],'r'))
local source=file:read('*all'); file:close()
local first=assert(source:find('function presentation.keyboard_mouse_swing_roll',1,true))
local last=assert(source:find('\nfunction presentation.',first+1,true))
local KeyboardMouse=dofile(arg[2])
local mt={}
local function v(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
mt.__add=function(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
mt.__mul=function(a,b) if type(a)=='number' then a,b=b,a end return v(a.x*b,a.y*b,a.z*b) end
local function basis(roll_left)
    -- Roll about forward: positive leans the head's up toward -X (left).
    local c,s=math.cos(roll_left),math.sin(roll_left)
    return {right=v(c,0,s),up=v(-s,0,c),forward=v(0,1,0)}
end
local head=basis(0)
Vector3={dot=function(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end}
Quaternion={
    from_elements=function() return head end,
    from_yaw_pitch_roll=function() return basis(0) end,
    right=function(q) return q.right end,up=function(q) return q.up end,forward=function(q) return q.forward end,
}
local motion={0,0}
local api=KeyboardMouse.install({get=function() end,info=function() end},function() end)
api.state.aim_yaw,api.state.aim_pitch=0,0
api.mouse_motion=function() return motion[1],motion[2] end
presentation={keyboard_mouse=api}
controller_observation={head_aim_qx=0,head_aim_qy=0,head_aim_qz=0,head_aim_qw=1}
assert(loadstring(source:sub(first,last-1)))()
local function near(a,b,label) assert(math.abs(KeyboardMouse.wrap(a-b))<1e-9,(label or '')..' '..math.deg(a)..' ~= '..math.deg(b)) end
local deg=math.rad
-- Level head, authored left-to-right swing, roll turns it counter-clockwise.
motion={0.05,0}; near(presentation.keyboard_mouse_swing_roll(1,0,1),0,'left to right')
motion={0,0.05}; near(presentation.keyboard_mouse_swing_roll(1,0,1),deg(90),'bottom to top')
motion={-0.05,0}; near(presentation.keyboard_mouse_swing_roll(1,0,1),deg(180),'right to left')
-- Head leaned 45 degrees left: a headset left-to-right sweep swings up-right.
head=basis(deg(45))
motion={0.05,0}; near(presentation.keyboard_mouse_swing_roll(1,0,1),deg(45),'leaned sweep')
motion={0,0.05}; near(presentation.keyboard_mouse_swing_roll(1,0,1),deg(135),'leaned upward sweep')
-- A right-to-left authored swing with the opposite roll sign reaches the same world direction.
motion={0.05,0}
local roll=presentation.keyboard_mouse_swing_roll(1,deg(180),-1)
near(deg(180)-roll,deg(45),'reversed swing basis')
-- Still mouse: swing from the reticle toward the headset's view centre. The aim
-- sits up and to the right of a level head's centre, so the swing goes down-left.
head=basis(0)
motion={0,0}
Quaternion.from_yaw_pitch_roll=function() return {right=v(1,0,0),up=v(0,0,1),forward=v(0.1,1,0.1)} end
near(presentation.keyboard_mouse_swing_roll(1,0,1),deg(225),'toward centre')
-- Nothing measurable, or no swing basis: the stock swing.
Quaternion.from_yaw_pitch_roll=function() return basis(0) end
assert(presentation.keyboard_mouse_swing_roll(1,0,1)==0)
motion={0.05,0}
assert(presentation.keyboard_mouse_swing_roll(1,nil,1)==0)
controller_observation.head_aim_qw=nil
assert(presentation.keyboard_mouse_swing_roll(1,0,1)==0)
print('keyboard_mouse_melee=pass headset_frame leaned_sweep toward_centre stock_fallback')
