local Sights=dofile(assert(arg[1]))
local function near(a,b,tol,m) assert(math.abs(a-b)<(tol or 1e-9),m or 'mismatch') end
local function mul(a,b)
    return {a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],
        a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}
end
local function rot(q,v) local r=mul(mul(q,{v[1],v[2],v[3],0}),{-q[1],-q[2],-q[3],q[4]}) return {r[1],r[2],r[3]} end
-- Pure offset: eye minus grip in the muzzle frame.
local o=assert(Sights.offset({x=-.008,z=.032},{x=-.007,z=-.086}))
near(o.x,-.001); near(o.z,.118)
assert(Sights.offset(nil,{x=0,z=0})==nil and Sights.offset({x=0,z=0},nil)==nil,'missing half')
assert(Sights.offset({x=0,z=.5},{x=0,z=0})==nil and Sights.offset({x=0,z=0},{x=0,z=.4})==nil,'implausible')
-- Zeroing: the sight line (11.8 cm above the grip) passes through the point.
local function sight_miss(grip,aim,offset,point,q)
    local drawn=mul(q,aim)
    local s=rot(drawn,{offset.x,0,offset.z}); s={grip[1]+s[1],grip[2]+s[2],grip[3]+s[3]}
    local f=rot(drawn,{0,1,0})
    local d={point[1]-s[1],point[2]-s[2],point[3]-s[3]}
    local along=d[1]*f[1]+d[2]*f[2]+d[3]*f[3]
    local c={d[1]-along*f[1],d[2]-along*f[2],d[3]-along*f[3]}
    return math.sqrt(c[1]^2+c[2]^2+c[3]^2), f
end
local identity={0,0,0,1}
local q=assert(Sights.zeroing({0,0,0},identity,{x=0,z=.118},{0,10,0}))
local miss,f=sight_miss({0,0,0},identity,{x=0,z=.118},{0,10,0},q)
assert(miss<.001,'sight line misses the point by '..miss)
near(math.deg(math.asin(-f[3])),math.deg(math.atan(.118/10)),.02,'pitch down by the parallax angle')
-- Any aim, any place: yawed and pitched gun away from the origin.
local yaw={0,0,math.sin(.6),math.cos(.6)}
local pitch={math.sin(-.1),0,0,math.cos(-.1)}
local aim=mul(yaw,pitch)
local grip={3,-2,1.4}
local fwd=rot(aim,{0,1,0})
local up=rot(aim,{0,0,-.05})
local point={grip[1]+fwd[1]*7+up[1],grip[2]+fwd[2]*7+up[2],grip[3]+fwd[3]*7+up[3]}
q=assert(Sights.zeroing(grip,aim,{x=-.001,z=.118},point))
assert(sight_miss(grip,aim,{x=-.001,z=.118},point,q)<.001,'general pose')
-- Too near, or too large a correction: none.
assert(Sights.zeroing({0,0,0},identity,{x=0,z=.118},{0,.5,0})==nil,'too near')
local capped=assert(Sights.zeroing({0,0,0},identity,{x=0,z=.118},{0,1,0}),'over the cap is clamped, not dropped')
near(math.deg(2*math.acos(math.abs(capped[4]))),Sights.MAX_CORRECTION_DEGREES,1e-6,'clamped to the cap')
local _,capped_forward=sight_miss({0,0,0},identity,{x=0,z=.118},{0,1,0},capped)
assert(capped_forward[3]<0,'clamped correction still turns toward the point')
-- A reticle up and to the left of the sights (head above-left of the gun):
-- the sights turn up and left.
local up_left=assert(Sights.zeroing({.15,0,-.3},identity,{x=0,z=.118},{0,10,0}))
local _,turned=sight_miss({.15,0,-.3},identity,{x=0,z=.118},{0,10,0},up_left)
assert(turned[1]<0 and turned[3]>0,'turned toward the up-left reticle')
assert(Sights.zeroing({0,0,0},identity,nil,{0,10,0})==nil,'no offset')
-- Adapter: eases toward the correction, returns aim when nothing is known.
Quaternion={to_elements=function(q) return q[1],q[2],q[3],q[4] end,from_elements=function(...) return {...} end,multiply=mul}
Vector3={x=function(v) return v[1] end,y=function(v) return v[2] end,z=function(v) return v[3] end}
local lines={}
local reticle={0,10,0}
local unit={}
local presentation={controller_aim={reticle_point_owner=unit,reticle_world_point={unbox=function() return reticle end}}}
local api=Sights.install({info=function(_,f,...) lines[#lines+1]=string.format(f,...) end},presentation)
local out=api.drawn_rotation(unit,'galvanic_rifle_p1_m1',{0,0,0},identity,1/90)
for i=1,4 do near(out[i],identity[i],1e-12,'no grip measured yet: unchanged') end
Matrix4x4={inverse=function(m) return m end,transform=function(m,p) return {p[1]-m[1],p[2]-m[2],p[3]-m[3]} end}
api.observe_grip('galvanic_rifle_p1_m1',{0,1.153,.086},{-.007,0,0})
assert(lines[1]:find('grip template=galvanic_rifle_p1_m1',1,true))
local first=api.drawn_rotation(unit,'galvanic_rifle_p1_m1',{0,0,0},identity,1/90)
assert(first[1]~=0,'correction starts')
for _=1,60 do out=api.drawn_rotation(unit,'galvanic_rifle_p1_m1',{0,0,0},identity,1/90) end
assert(sight_miss({0,0,0},identity,{x=-.001,z=.118},reticle,{out[1],out[2],out[3],out[4]})<.002,'settled on the reticle')
assert(math.abs(first[1])<math.abs(out[1]),'eased in')
-- Another unit's reticle point is ignored: eases back to the bore.
presentation.controller_aim.reticle_point_owner={}
for _=1,90 do out=api.drawn_rotation(unit,'galvanic_rifle_p1_m1',{0,0,0},identity,1/90) end
near(out[4],1,1e-6,'foreign reticle ignored')
-- Unknown template: unchanged.
presentation.controller_aim.reticle_point_owner=unit
out=api.drawn_rotation(unit,'autogun_p1_m1',{0,0,0},identity,1/90)
assert(math.abs(out[1])<1e-6,'unknown template')
-- The zeroing applies only as the sights reach the eye.
local d,b=Sights.eye_distance({0,0,0},identity,{x=0,z=.118},{0,-.3,.118})
near(d,0,1e-9,'eye on the sight line'); near(b,.3,1e-9,'30 cm behind the sight')
d=Sights.eye_distance({0,0,0},identity,{x=0,z=.118},{.1,-.3,.118}); near(d,.1,1e-9,'10 cm off the line')
near(Sights.zeroing_weight(0,.3),1,1e-12,'at the eye: full')
near(Sights.zeroing_weight(Sights.ZEROING_NONE_DISTANCE+.01,.3),0,1e-12,'low ready: none')
local mid=Sights.zeroing_weight((Sights.ZEROING_FULL_DISTANCE+Sights.ZEROING_NONE_DISTANCE)/2,.3)
assert(mid>0 and mid<1,'blends between'); near(mid,.5,1e-9,'smooth midpoint')
assert(Sights.zeroing_weight(0,-.1)==0,'eye in front of the sight')
assert(Sights.zeroing_weight(nil,.3)==0)
-- Adapter with a tracked eye far from the sights: the gun follows the hand.
Quaternion.right=function() return {1,0,0} end
local eye_vec=setmetatable({0,-.3,-.5},{__add=function(a,v) return {a[1]+v[1],a[2]+v[2],a[3]+v[3]} end})
local vmt={__mul=function(v,k) return {v[1]*k,v[2]*k,v[3]*k} end}
Quaternion.right=function() return setmetatable({1,0,0},vmt) end
presentation.eye_pose=function() return eye_vec,identity end
presentation.weapon_hand_roles={physical=function() return 'right' end}
presentation.controller_aim.reticle_point_owner=unit
for _=1,90 do out=api.drawn_rotation(unit,'galvanic_rifle_p1_m1',{0,0,0},identity,1/90) end
near(out[4],1,1e-6,'eye 60 cm below the sights: no zeroing')
-- Sight axis: a sight line tilted from the muzzle is what points at the reticle.
local tilt=math.rad(.5)
local axis={0,math.cos(tilt),math.sin(tilt)} -- sights look 0.5 degrees above the bore
local ax=Sights.axis(axis); near(ax[3],math.sin(tilt),1e-9,'measured axis kept')
local fallback=Sights.axis({0,.9,.4}); assert(fallback[2]==1,'implausible axis falls back to the bore')
assert(Sights.axis(nil)[2]==1)
local tilted={x=0,z=.118,axis=axis}
local tq=assert(Sights.zeroing({0,0,0},identity,tilted,{0,10,0}))
local drawn=mul(tq,identity)
local sight=rot(drawn,{0,0,.118})
local look=rot(drawn,axis)
local d={0-sight[1],10-sight[2],0-sight[3]}
local along=d[1]*look[1]+d[2]*look[2]+d[3]*look[3]
local miss_axis=math.sqrt((d[1]-along*look[1])^2+(d[2]-along*look[2])^2+(d[3]-along*look[3])^2)
assert(miss_axis<.001,'tilted sight line misses the point by '..miss_axis)
local o2=assert(Sights.offset({x=-.008,z=.032,axis=axis},{x=0,z=-.086})); near(o2.axis[3],math.sin(tilt),1e-9,'offset carries the axis')
print('gun_sights=pass offset zeroing general_pose near cap ease foreign unknown eye_weight sight_axis')
