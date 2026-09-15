local SightAds=dofile(assert(arg[1]))
local function near(a,b,tol,m) assert(math.abs(a-b)<(tol or 1e-9),(m or 'mismatch')..': '..tostring(a)) end
-- Gun level, pointing +y, grip at origin; sight 11.8 cm above the grip.
local forward,up,right={0,1,0},{0,0,1},{1,0,0}
local offset={x=0,z=.118}
-- Eye on the sight line, 25 cm behind the grip, looking forward.
local d,behind,facing=SightAds.measure({0,0,0},forward,up,right,offset,{0,-.25,.118},{0,1,0})
near(d,0); near(behind,.25); near(facing,1)
-- 4 cm to the side.
d=SightAds.measure({0,0,0},forward,up,right,offset,{.04,-.25,.118},{0,1,0})
near(d,.04)
-- The sight's lateral offset counts.
d=SightAds.measure({0,0,0},forward,up,right,{x=.01,z=.118},{.01,-.25,.118},{0,1,0})
near(d,0,1e-9,'lateral offset')
-- Engagement with hysteresis.
assert(SightAds.engaged(false,.055,.25,1),'enter at 5.5 cm')
assert(not SightAds.engaged(false,.07,.25,1),'no entry at 7 cm')
assert(SightAds.engaged(true,.08,.25,1),'stays at 8 cm')
assert(not SightAds.engaged(true,.095,.25,1),'leaves past 9 cm')
-- Release grace: stays engaged for 0.3 s after the sights leave the eye.
local e,away=SightAds.hold(true,false,0,.1); assert(e and math.abs(away-.1)<1e-9,'still engaged at 0.1 s')
e,away=SightAds.hold(e,false,away,.15); assert(e,'still engaged at 0.25 s')
e,away=SightAds.hold(e,false,away,.1); assert(not e,'released after 0.3 s')
e,away=SightAds.hold(false,false,0,.1); assert(not e and away==0,'never engaged stays off')
e,away=SightAds.hold(true,true,.2,.1); assert(e and away==0,'back at the eye resets the grace')
assert(not SightAds.engaged(false,.01,.25,math.cos(math.rad(30))),'looking away does not enter')
assert(SightAds.engaged(true,.01,.25,math.cos(math.rad(30))),'a small glance keeps it')
assert(not SightAds.engaged(false,.01,-.05,1),'eye in front of the grip (gun behind the head)')
assert(not SightAds.engaged(false,.01,.8,1),'too far behind')
assert(not SightAds.engaged(false,0/0,.25,1))
-- Input edges: hold and toggle.
local p,h,r=SightAds.edges(false,true,false); assert(p and h and not r,'hold: enter')
p,h,r=SightAds.edges(true,true,false); assert(not p and h and not r,'hold: stay')
p,h,r=SightAds.edges(true,false,false); assert(not p and not h and r,'hold: exit')
p,h,r=SightAds.edges(false,false,false); assert(not p and not h and not r,'hold: idle')
p,h,r=SightAds.edges(false,true,true); assert(p and not h and not r,'toggle: enter presses')
p,h,r=SightAds.edges(true,true,true); assert(not p and not h and not r,'toggle: stay quiet')
p,h,r=SightAds.edges(true,false,true); assert(p and not h and not r,'toggle: exit presses again')
print('sight_ads=pass measure lateral hysteresis facing behind edges_hold edges_toggle')
