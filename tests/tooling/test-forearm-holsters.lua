local Forearm=dofile(assert(arg[1]))
local Holsters=dofile(assert(arg[2]))
local function near(a,b,m) assert(math.abs(a-b)<1e-9,(m or 'mismatch')..': '..tostring(a)) end
-- The weapon zone holds the weapon not in the hand.
local slot,selector=Forearm.assignment(1,'slot_secondary'); assert(slot=='slot_primary' and selector=='melee')
slot,selector=Forearm.assignment(1,'slot_primary'); assert(slot=='slot_secondary' and selector=='ranged')
slot,selector=Forearm.assignment(1,'slot_device'); assert(slot=='slot_secondary' and selector=='ranged','any other wield offers the gun')
slot,selector=Forearm.assignment(2,'slot_secondary'); assert(slot=='slot_pocketable_small' and selector=='stim')
slot,selector=Forearm.assignment(3); assert(slot=='slot_pocketable' and selector=='pocketable')
slot,selector=Forearm.assignment(4); assert(slot=='slot_device' and selector=='device')
assert(Forearm.assignment(5)==nil)
-- Centres run back along the forearm from the grip, above its line.
local grip,forward,up={1,2,1.2},{0,1,0},{0,0,1}
local c1=Forearm.centre(1,grip,forward,up)
near(c1[1],1); near(c1[2],2-Forearm.ZONE_START,'first zone behind the grip'); near(c1[3],1.2+Forearm.ZONE_HEIGHT,'above')
local c4=Forearm.centre(4,grip,forward,up)
near(c1[2]-c4[2],Forearm.ZONE_SPACING*3,'spacing')
-- Turned arm: forward along +x.
local c2=Forearm.centre(2,grip,{1,0,0},up)
near(c2[1],1-(Forearm.ZONE_START+Forearm.ZONE_SPACING),'follows the arm')
-- User layout: 8 cm zones, 4 cm apart, the weapon above the wrist.
near(Forearm.ZONE_RADIUS*2,.08,'8 cm zones'); near(Forearm.ZONE_SPACING-2*Forearm.ZONE_RADIUS,.04,'4 cm between zones')
near(Forearm.ZONE_START,.08,'weapon zone above the wrist')
assert(Forearm.PREVIEW_SIZE>=.096,'miniatures at least 50% larger than the first fit')
-- Miniatures are fitted to one size; unusable extents are refused.
near(Forearm.fit_scale(1.0),Forearm.PREVIEW_SIZE,'a 1 m weapon'); near(Forearm.fit_scale(0.25),Forearm.PREVIEW_SIZE*4,'a 25 cm stim')
assert(Forearm.fit_scale(0)==nil and Forearm.fit_scale(nil)==nil and Forearm.fit_scale(0/0)==nil)
near(Forearm.shown_scale(.1,true),.1*Forearm.HOVER_SCALE,'hovered grows'); near(Forearm.shown_scale(.1,false),.1)
-- Flat boxes (the maul's effect plane) stay out of the bounds; thin parts stay in.
assert(not Forearm.solid_box(0,.4,.146),'flat plane'); assert(Forearm.solid_box(.041,.006,.002),'thin part')
-- Holster state with a per-hand zone list: the off hand arms a forearm zone.
local frame=Holsters.frame({0,0,1.64},{0,1,0},1.64)
local zone={id='forearm_stim',slot='slot_pocketable_small',selector='stim',radius=.04,
    centre=Holsters.local_point(frame,{.35,.3,1.5})}
local holsters=Holsters.new()
local zones={zone}
assert(holsters.update('left',Holsters.local_point(frame,{.35,.31,1.5}),1,zones)==nil,'dwell first')
local ready=holsters.update('left',Holsters.local_point(frame,{.35,.31,1.5}),1.1,zones)
assert(ready==zone,'forearm zone ready after the dwell')
local request=holsters.request('left',ready,{slot_pocketable_small='content/items/pocketable/syringe',wielded_slot='slot_secondary'})
assert(request and request.action=='stim' and request.control=='left_grip' and request.acquire,'grip request for the stim')
assert(holsters.request('left',ready,{slot_pocketable_small='not_equipped',wielded_slot='slot_secondary'})==nil,'empty holster offers nothing')
-- Without the list the body zones apply: the same point is in none of them.
local other=Holsters.new()
other.update('left',Holsters.local_point(frame,{.35,.31,1.5}),1)
assert(other.update('left',Holsters.local_point(frame,{.35,.31,1.5}),1.1)==nil,'body zones unchanged')
-- Roll-stable above: world up across the forearm, whatever the wrist roll.
local u=Forearm.stable_up({0,1,0},{1,0,0})
near(u[1],0); near(u[2],0); near(u[3],1,'level forearm: straight up')
u=Forearm.stable_up({0,math.sqrt(.5),math.sqrt(.5)},{1,0,0})
near(u[1]*0+u[2]*math.sqrt(.5)+u[3]*math.sqrt(.5),0,'perpendicular to the forearm'); assert(u[3]>0,'still above')
u=Forearm.stable_up({0,0,1},{1,0,0})
assert(u[1]==1,'vertical forearm uses the fallback')
-- Cylindrical billboard: the long axis lies across the view, horizontally.
local side=Forearm.billboard_side({0,1,1},{0,0,1.6})
near(side[3],0,'horizontal'); near(side[1]*0+side[2]*-1,0,'perpendicular to the eye direction'); near(math.abs(side[1]),1)
assert(Forearm.billboard_side({0,0,0},{0,0,2})==nil,'eye straight above')
-- Hidden in the aim line: nearer than the reticle and close to the line to it.
assert(Forearm.in_aim_line({0,.5,0},{0,0,0},{0,10,0},12),'on the line')
assert(Forearm.in_aim_line({.05,.5,0},{0,0,0},{0,10,0},12),'within 12 degrees')
assert(not Forearm.in_aim_line({.3,.5,0},{0,0,0},{0,10,0},12),'well off the line')
assert(not Forearm.in_aim_line({0,12,0},{0,0,0},{0,10,0},12),'beyond the reticle')
print('forearm_holsters=pass assignment centres layout fit hover stable_up billboard aim_line zone_override request empty')
