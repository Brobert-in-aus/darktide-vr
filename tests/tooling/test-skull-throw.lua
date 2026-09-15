-- Servo skull throw: flight time, blend timing, drawn position, rest offsets.
local Skull=dofile(assert(arg[1]))
local function near(a,b,m) assert(math.abs(a-b)<1e-9,(m or 'mismatch')..': '..tostring(a)) end
near(Skull.flight_time({0,0,0},{0,8,0}),0.8,'8 m at 10 m/s')
near(Skull.flight_time({1,2,3},{4,6,3}),0.5,'5 m')
assert(Skull.flight_time(nil,{0,0,0})==nil and Skull.flight_time({0,0,0},{0/0,0,0})==nil)
-- Free for the first 2/5 of the flight, then blended in by its end.
near(Skull.blend_weight(0,1),0); near(Skull.blend_weight(0.4,1),0,'free until 2/5')
near(Skull.blend_weight(0.7,1),0.5,'halfway through the blend')
near(Skull.blend_weight(1,1),1); near(Skull.blend_weight(3,1),1)
near(Skull.blend_weight(0.1,0),1,'no flight: on the real skull')
local d=Skull.drawn_position({0,0,1},{0,2,0},0.5,{0,4,1},0)
near(d[1],0); near(d[2],1,'free flight at the release velocity'); near(d[3],1)
d=Skull.drawn_position({0,0,1},{0,2,0},0.5,{0,4,1},1); near(d[2],4,'blended fully onto the real skull')
d=Skull.drawn_position({0,0,1},{0,2,0},0.5,{0,4,1},0.5); near(d[2],2.5)
-- Brought forward, side and height kept.
local offsets=Skull.forward_offsets({rest={-0.25,-0.15,0.15},in_combat={-0.25,-0.15,0.15}},Skull.FORWARD)
near(offsets.rest[1],-0.25); near(offsets.rest[2],Skull.FORWARD); near(offsets.rest[3],0.15)
near(offsets.in_combat[2],Skull.FORWARD)
assert(Skull.FREE_FRACTION==0.4 and Skull.SPEED==10 and Skull.RULE=='cryptic_servo_skull_flamethrower')
print('skull_throw=pass flight_time blend drawn forward_offsets')
