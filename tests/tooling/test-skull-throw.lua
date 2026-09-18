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

-- The bridge: linear from the follower's last drawn position to the real
-- one over the duration, then the real position and done.
local b0, d0 = Skull.bridge_position({0, 0, 0}, {2, 0, 0}, 0.175, 0.35)
assert(math.abs(b0[1] - 1) < 1e-9 and not d0, 'half way at half the duration')
local b1, d1 = Skull.bridge_position({0, 0, 0}, {2, 0, 0}, 0.35, 0.35)
assert(b1[1] == 2 and d1, 'the real position and done at the duration')
local b2, d2 = Skull.bridge_position(nil, {2, 0, 0}, 0.1, 0.35)
assert(b2[1] == 2 and d2, 'nothing to bridge from: the real position, done')
local b3, d3 = Skull.bridge_position({0, 0, 0}, {2, 0, 0}, 0, 0.35)
assert(b3[1] == 0 and not d3, 'the first frame holds the last drawn position')
assert(Skull.BRIDGE_SECONDS == 0.35)

-- The lazy heading: holds inside the dead zone, catches up beyond it, then
-- settles and holds again.
local h = Skull.lazy_yaw(nil, 0.5, nil)
assert(h.yaw == 0.5 and not h.turning, 'first sample takes the head yaw')
h = Skull.lazy_yaw(h, 0.5 + math.rad(15), 0.016)
assert(h.yaw == 0.5 and not h.turning, 'a glance inside the dead zone moves nothing')
h = Skull.lazy_yaw(h, 0.5 + math.rad(40), 0.016)
assert(h.turning and h.yaw > 0.5 and h.yaw < 0.5 + math.rad(40), 'beyond it the heading starts after the head')
for _ = 1, 400 do h = Skull.lazy_yaw(h, 0.5 + math.rad(40), 0.016) end
assert(not h.turning and math.abs(h.yaw - (0.5 + math.rad(40))) < math.rad(2.1), 'and settles on it')
local across = Skull.lazy_yaw({yaw = math.pi - 0.1, turning = true}, -math.pi + 0.1, 0.1)
assert(across.yaw > math.pi - 0.1 or across.yaw < -math.pi + 0.1, 'the short way round across the seam')
assert(Skull.lazy_yaw(h, 0 / 0, 0.016) == h, 'no head yaw: unchanged')

-- The offset the drawn skull wants from the eye. Head and heading agree and
-- the player stands: the real skull's own offset.
local o = Skull.follow_offset({1.5, 2.3, 1.4}, {1, 2, 1.6}, 0.3, 0.3, {0, 0, 0})
assert(math.abs(o[1] - 0.5) < 1e-9 and math.abs(o[2] - 0.3) < 1e-9 and math.abs(o[3] + 0.2) < 1e-9)
-- The head turned a quarter turn (Stingray yaw) while the heading stayed: a
-- skull at the head's right is turned back to the heading's right.
local turned = Skull.follow_offset({0, 1, 0}, {0, 0, 0}, math.pi / 2, 0, nil)
assert(math.abs(turned[1] - 1) < 1e-9 and math.abs(turned[2]) < 1e-9, 'at the head right stays at the heading right')
-- Running: a lead along the velocity, 0.3 m at a run, less at a walk, none
-- when standing or drifting.
local run = Skull.follow_offset({0, 0, 0}, {0, 0, 0}, 0, 0, {0, 5, 0})
assert(math.abs(run[2] - 0.3) < 1e-9 and run[1] == 0, 'a full lead at a run')
local walk = Skull.follow_offset({0, 0, 0}, {0, 0, 0}, 0, 0, {2, 0, 0})
assert(math.abs(walk[1] - 0.15) < 1e-9, 'half the lead at half the speed')
local drift = Skull.follow_offset({0, 0, 0}, {0, 0, 0}, 0, 0, {0.3, 0, 0})
assert(drift[1] == 0, 'no lead below the minimum speed')
assert(Skull.LEAD_METRES == 0.3)

-- One writer: what the stock extension is fed. Its rest offset is used as
-- position - right * x + forward * y, so x is to the LEFT of the heading.
-- Heading 0 faces +y with +x to the right.
local so = Skull.stock_offset({0.5, 0.3, -0.2}, 0)
assert(math.abs(so[1] + 0.5) < 1e-9 and math.abs(so[2] - 0.3) < 1e-9 and so[3] == -0.2, 'a point to the right has a negative x')
-- Round trip through the stock formula at an arbitrary heading.
local heading = 1.1
local c, s = math.cos(heading), math.sin(heading)
local delta = {0.4, -0.7, 0.25}
so = Skull.stock_offset(delta, heading)
local back_x = -c * so[1] + -s * so[2]
local back_y = -s * so[1] + c * so[2]
assert(math.abs(back_x - delta[1]) < 1e-9 and math.abs(back_y - delta[2]) < 1e-9, 'the stock formula puts it back where it was')
-- The lead, a world vector along the run.
local l = Skull.lead({0, 5, 0})
assert(math.abs(l[2] - 0.3) < 1e-9 and l[1] == 0 and l[3] == 0)
assert(Skull.lead({0.3, 0, 0})[1] == 0 and Skull.lead(nil)[1] == 0)
assert(math.abs(Skull.lead({2, 0, 0})[1] - 0.15) < 1e-9)
-- The fed offset: the stock flamethrower rest (-0.55 is 55 cm to the right)
-- mirrored to the left and brought forward, plus the lead in the heading's
-- frame; an unmirrored one (left-handed) keeps its side.
--
-- `forward` being given is also what says this is the THROWABLE skull, so it
-- is what gates the worn side and height offsets. The other skulls keep their
-- stock rest exactly, which is the property worth holding: the 18 September
-- answer was about the flamethrower skull alone.
local fed = Skull.fed_offset({-0.55, 0.15, -0.25}, true, 0.30, {0, 0.3, 0}, 0)
assert(math.abs(fed[1] - (0.55 - Skull.SIDE_RIGHT)) < 1e-9, 'moved right, and x is to the left')
assert(math.abs(fed[2] - 0.60) < 1e-9, 'the forward offset replaces the stock one, plus the lead')
assert(math.abs(fed[3] - (-0.25 - Skull.DOWN)) < 1e-9, 'and lowered')
assert(Skull.SIDE_RIGHT > 0 and Skull.DOWN > 0, 'right and down are positive magnitudes')
near(Skull.FORWARD, 0.60, 'the worn forward rest')
-- No `forward`: not the throwable skull, so not one of the three axes moves.
fed = Skull.fed_offset({-0.55, 0.15, -0.25}, false, nil, {0, 0, 0}, 0.7)
assert(fed[1] == -0.55 and fed[2] == 0.15 and fed[3] == -0.25, 'the other skulls are untouched')
-- Running to the right of the heading leads to the right: a smaller x.
fed = Skull.fed_offset({0, 0, 0}, false, nil, {0.3, 0, 0}, 0)
assert(math.abs(fed[1] + 0.3) < 1e-9 and math.abs(fed[2]) < 1e-9)
-- The stock update multiplies a rest offset's x by the field-of-view factor:
-- the lead is divided by it first so it stays a world distance; the stock
-- rest keeps the factor's effect, as stock intends.
fed = Skull.fed_offset({-0.55, 0.15, -0.25}, true, nil, {0.3, 0, 0}, 0, 1.25)
assert(math.abs(fed[1] - (0.55 - 0.3 / 1.25)) < 1e-9, 'lead divided, rest not')
assert(Skull.fed_offset({0, 0, 0}, false, nil, {0.3, 0, 0}, 0, 0)[1] == -0.3, 'a nonsense factor is 1')
assert(Skull.HOLD_UP == 0.07)

-- The release velocity. A single frame's finite difference reported almost
-- nothing at the moment of release, which is what "throwing it has no physics,
-- it just floats where released" was (user, 18 September): the free flight ran
-- at nearly zero.
local samples = {}
for i = 0, 15 do samples[#samples + 1] = {i * 0.01, 0, i * 0.01 * 4, 0} end
local v = Skull.release_velocity(samples, 0.15)
assert(math.abs(v[2] - 4) < 1e-6, 'four metres a second across the window, got ' .. v[2])
assert(v[1] == 0 and v[3] == 0)
-- A hand that STOPS before the button comes up still throws: the window sees
-- the movement, where the last frame alone sees the stop. This is the case the
-- change exists for, so it is asserted rather than assumed.
samples[#samples + 1] = {0.16, 0, 0.6, 0}
samples[#samples + 1] = {0.17, 0, 0.6, 0}
local stopped = Skull.release_velocity(samples, 0.17)
assert(stopped[2] > 1.5, 'the window still carries the throw, got ' .. stopped[2])
-- Capped, so a tracking glitch cannot fling the drawn skull somewhere the real
-- one never goes.
local glitch = Skull.release_velocity({{0, 0, 0, 0}, {0.01, 0, 50, 0}}, 0.01)
assert(math.abs(math.sqrt(glitch[1] ^ 2 + glitch[2] ^ 2 + glitch[3] ^ 2) -
    Skull.THROW_MAX_SPEED) < 1e-6, 'capped at THROW_MAX_SPEED')
-- Nothing usable is a zero, never a nil or a nan.
for _, bad in ipairs({{}, {{0, 0, 0, 0}}, 'not a list'}) do
    local zero = Skull.release_velocity(bad, 1)
    assert(zero[1] == 0 and zero[2] == 0 and zero[3] == 0)
end
assert(Skull.release_velocity({{0, 0, 0, 0}, {0.01, 0, 1, 0}}, 0 / 0)[2] == 0, 'no release time, no throw')
-- Samples older than the window are ignored, and one stale entry before a gap
-- cannot widen the window and understate the speed.
local gapped = {{0, 0, 0, 0}, {0.9, 0, 1, 0}, {0.95, 0, 1.5, 0}, {1.0, 0, 2, 0}}
assert(math.abs(Skull.release_velocity(gapped, 1.0)[2] - 10) < 1e-6,
    'measured across the window that is there, not back to the stale sample')
print('skull_throw=pass flight_time blend drawn forward_offsets rest_offsets smoothed stock_offset lead fed_offset')
