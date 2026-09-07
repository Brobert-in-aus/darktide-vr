local Roomscale=dofile(assert(arg[1]))
local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a)..' != '..tostring(b)) end
local s=Roomscale.new()
s.sample('player','bridge:1',1,0,10,20,0,1.7,1,0)
s.sample('player','bridge:1',2,.01,10.4,19.8,.2,1.9,1,0)
near(s.x,.4); near(s.y,.2); near(s.z,0)
s.record(1,true); s.moved(1,.1,.05)
near(s.x,.3); near(s.y,.15)
near(s.render_offset(),.4) -- stock camera still represents before frame 1
s.capture_base(2); near(s.render_offset(),.3)
s.capture_base(1); near(s.render_offset(),.4) -- replay anchor excludes future rows
s.moved(1,.1,.05); near(s.x,.3) -- same correction replay
s.moved(1,.08,.04); near(s.x,.32); near(s.y,.16)
s.capture_base(2); near(s.render_offset(),.32)
s.record(2,false); s.moved(2,.2,.2); near(s.x,.32)
s.sample('player','bridge:1',3,.02,10.4,19.8,1.2,3.7,1,math.pi/2)
near(s.x,.32); near(s.y,.16); near(s.z,.8) -- turn does not orbit the residual
s.sample('player','bridge:1',4,.03,10.5,19.8,1.2,0,1,math.pi/2)
near(s.x,.32); near(s.y,.26); near(s.z,.8) -- lost STAGE retains extra height
s.sample('player','bridge:2',5,.04,10.5,19.8,0,1.7,1,0)
near(s.x,0); near(s.y,0); near(s.z,0); assert(next(s.rows)==nil)
s.sample('new-player','bridge:2',6,.05,20,30,0,1.7,1,0); near(s.x,0)
assert(not s.sample('new-player','bridge:2',7,.06,0/0,30,0,1.7,1,0))
s.sample('new-player','bridge:2',1,.07,25,30,0,1.7,1,0); near(s.x,0)
s.record(600,true); s.moved(600,.1,0); near(s.x,-.1)
s.record(1200,false); s.moved(600,.5,0); near(s.x,-.1) -- expired frame
s.record(1201,true); s.moved(1201,5,0); assert(s.owner==nil)
print('PASS roomscale: tracking basis, vertical envelope, recenter, owner, replay, history expiry, teleport')
