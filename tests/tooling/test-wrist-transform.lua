local file = assert(io.open(arg[1], 'r'))
local source = file:read('*all')
file:close()
local first = assert(source:find('function presentation.body_ik_calibrated_wrist_target', 1, true))
local last = assert(source:find('\nfunction presentation.update_body_ik_trace_gate', first, true))
local mt = {}
local function v(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
mt.__add=function(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
mt.__sub=function(a,b) return v(a.x-b.x,a.y-b.y,a.z-b.z) end
mt.__mul=function(a,b) return v(a.x*b,a.y*b,a.z*b) end
Vector3 = {up=function() return v(0,0,1) end}
local identity = {right=v(1,0,0),forward=v(0,1,0),up=v(0,0,1)}
Quaternion = {
 right=function(q) return q.right end,
 forward=function(q) return q.forward end,
 up=function(q) return q.up end,
 axis_angle=function() return identity end,
}
presentation = {}
controller_observation = {body_visual_yaw=0}
assert(loadstring(source:sub(first,last-1)))()
local function near(a,b)
 assert(math.abs(a.x-b.x)<1e-8 and math.abs(a.y-b.y)<1e-8 and math.abs(a.z-b.z)<1e-8,
   'controller-relative wrist offset changed under rotation')
end
local origin=v(2,3,4)
local offset=v(-.03,-.04,.04)
near(presentation.body_ik_calibrated_wrist_target('left',origin,identity),origin+offset)
-- Quarter-turn about forward: local wrist offset must rotate as a rigid vector.
local roll={right=v(0,0,-1),forward=v(0,1,0),up=v(1,0,0)}
near(presentation.body_ik_calibrated_wrist_target('left',origin,roll),origin+v(.04,-.04,.03))
-- Upside down, where body-frame residuals previously moved across the palm.
local inverted={right=v(-1,0,0),forward=v(0,1,0),up=v(0,0,-1)}
near(presentation.body_ik_calibrated_wrist_target('left',origin,inverted),origin+v(.03,-.04,-.04))
-- Keep the previously accepted right-hand mapping in this candidate.
near(presentation.body_ik_calibrated_wrist_target('right',origin,roll),origin+v(.08,-.04,-.01))
print('wrist transform covariance and right-hand preservation passed')
