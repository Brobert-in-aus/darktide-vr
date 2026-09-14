local Sights=dofile(assert(arg[1]))
local function near(a,b,m) assert(math.abs(a-b)<1e-9,m) end
-- Pure offset: eye minus grip in the muzzle frame.
local o=assert(Sights.offset({x=-.008,z=.032},{x=-.007,z=-.086}))
near(o.x,-.001,'x'); near(o.z,.118,'z')
assert(Sights.offset(nil,{x=0,z=0})==nil and Sights.offset({x=0,z=0},nil)==nil,'missing half')
assert(Sights.offset({x=0,z=.5},{x=0,z=0})==nil,'implausible eye')
assert(Sights.offset({x=0,z=0},{x=0,z=.4})==nil,'implausible grip')
assert(Sights.offset({x=0/0,z=0},{x=0,z=0})==nil,'nan')
-- Adapter stubs: vectors as tables, rotations as yaw-free identity or a pitch.
local function vec(x,y,z) return setmetatable({x,y,z},{__add=function(a,b) return vec(a[1]+b[1],a[2]+b[2],a[3]+b[3]) end}) end
Vector3=setmetatable({x=function(v) return v[1] end,y=function(v) return v[2] end,z=function(v) return v[3] end},
    {__call=function(_,x,y,z) return vec(x,y,z) end})
Quaternion={rotate=function(q,v) if q=='pitch90' then return vec(v[1],-v[3],v[2]) end return vec(v[1],v[2],v[3]) end}
Matrix4x4={inverse=function(m) return {inverse=m} end,transform=function(m,p) local o=m.inverse.origin return vec(p[1]-o[1],p[2]-o[2],p[3]-o[3]) end}
local gun={name='galvanic_rifle_p1_m1',actions={}}
local wielded=gun
local weapon_ext={weapon_template=function() return wielded end}
local alternate={is_active=false}
ScriptUnit={has_extension=function(_,name)
    if name=='weapon_system' then return weapon_ext end
    if name=='unit_data_system' then return {read_component=function(_,c) return c=='alternate_fire' and alternate or {wielded_slot='slot_secondary'} end} end
end}
local lines={}
local presentation={gun_aim={is_gun=function(t) return t==gun end},
    weapon_grip_target=function() return vec(1,2,3) end}
local api=Sights.install({info=function(_,f,...) lines[#lines+1]=string.format(f,...) end},presentation)
local unit={}
-- No grip measurement yet: no change.
assert(api.origin(unit,'identity')==nil,'needs the grip half')
api.observe_grip('galvanic_rifle_p1_m1',{origin=vec(0,1.153,.086)},vec(-.007,0,0))
assert(lines[1]:find('grip template=galvanic_rifle_p1_m1',1,true))
local p=assert(api.origin(unit,'identity'))
near(p[1],1-.001,'origin x'); near(p[2],2,'origin y'); near(p[3],3+.118,'origin z')
-- The offset turns with the aim: pitched 90 degrees, "up" becomes backward.
p=assert(api.origin(unit,'pitch90'))
near(p[2],2-.118,'rotated offset'); near(p[3],3,'rotated offset z')
-- Not a gun, or unknown template: no change.
wielded={name='powermaul_p3_m1'}
assert(api.origin(unit,'identity')==nil,'melee untouched')
wielded={name='autogun_p1_m1'}; gun=wielded
assert(api.origin(unit,'identity')==nil,'no eye for this template')
print('gun_sights=pass offset plausibility origin rotation melee unknown')
