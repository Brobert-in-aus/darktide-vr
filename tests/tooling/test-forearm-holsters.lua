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
assert(Forearm.ZONE_SPACING>=Forearm.ZONE_RADIUS*1.5,'neighbouring zones overlap too much')
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
-- Previews move toward the eye, never past halfway.
local p=Forearm.preview_point({0,1,0},{0,0,0})
near(p[2],1-Forearm.PREVIEW_TOWARD_EYE,'toward the eye')
p=Forearm.preview_point({0,.1,0},{0,0,0})
near(p[2],.05,'at most halfway')
p=Forearm.preview_point({1,1,1},{1,1,1})
near(p[1],1,'coincident eye')
print('forearm_holsters=pass assignment centres spacing zone_override request empty preview_point')
