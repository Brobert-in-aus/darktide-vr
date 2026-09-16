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
-- Rest offsets: the side mirrored, the forward replaced only when given.
local rest = Skull.rest_offsets({a = {0.3, -0.15, -0.2}, b = {-0.1, 0.05, 0}}, 0.3, true)
assert(rest.a[1] == -0.3 and rest.a[2] == 0.3 and rest.a[3] == -0.2, 'mirrored and brought forward')
assert(rest.b[1] == 0.1 and rest.b[2] == 0.3, 'every entry mirrored')
local kept = Skull.rest_offsets({a = {0.3, -0.15, -0.2}}, nil, true)
assert(kept.a[1] == -0.3 and kept.a[2] == -0.15, 'no forward given: the stock forward kept')
assert(Skull.rest_offsets({a = {0.3, -0.15, -0.2}}, nil, false).a[1] == 0.3, 'not mirrored when not asked')
assert(Skull.MIRROR_SIDE == true)

-- The follower: snaps without a drawn position or beyond the snap distance,
-- otherwise closes the gap exponentially and never overshoots.
local s0 = Skull.smoothed(nil, {1, 2, 3}, 0.016)
assert(s0[1] == 1 and s0[2] == 2 and s0[3] == 3, 'first frame snaps')
local s1 = Skull.smoothed({0, 0, 0}, {1, 0, 0}, 0.2, 0.2, 2)
assert(math.abs(s1[1] - (1 - math.exp(-1))) < 1e-9 and s1[2] == 0, 'one time constant closes 63 per cent')
local s2 = Skull.smoothed({0, 0, 0}, {5, 0, 0}, 0.016, 0.2, 2)
assert(s2[1] == 5, 'beyond the snap distance it snaps')
local s3 = Skull.smoothed({0.5, 0, 0}, {1, 0, 0}, 0, 0.2, 2)
assert(s3[1] == 0.5, 'no time passed: no movement')
assert(Skull.smoothed({0, 0, 0}, {1, 0, 0}, 10, 0.2, 2)[1] <= 1, 'never overshoots')
assert(Skull.FOLLOW_TAU == 0.2 and Skull.FOLLOW_SNAP == 2.0)
print('skull_throw=pass flight_time blend drawn forward_offsets rest_offsets smoothed')
