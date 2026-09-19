-- Servo skull throw: flight time, blend timing, drawn position, rest offsets.
local Skull=dofile(assert(arg[1]))
local function near(a,b,m) assert(math.abs(a-b)<1e-9,(m or 'mismatch')..': '..tostring(a)) end
near(Skull.flight_time({0,0,0},{0,8,0}),0.8,'8 m at 10 m/s')
near(Skull.flight_time({1,2,3},{4,6,3}),0.5,'5 m')
assert(Skull.flight_time(nil,{0,0,0})==nil and Skull.flight_time({0,0,0},{0/0,0,0})==nil)
-- Free for the first 2/5 of the flight OR a quarter of a second, whichever is
-- shorter, then blended in by its end. The cap is what stops a long throw
-- flying the drawn skull metres off the real one -- and through the floor --
-- before the blend takes over.
near(Skull.FREE_MAX_SECONDS,0.25,'the cap')
near(Skull.blend_weight(0,1),0)
near(Skull.blend_weight(Skull.FREE_MAX_SECONDS,1),0,'a one second flight is capped, not 2/5 of it')
near(Skull.blend_weight(0.625,1),0.5,'halfway through the blend that follows')
near(Skull.blend_weight(1,1),1); near(Skull.blend_weight(3,1),1)
-- A short throw is below the cap, so it is unchanged: 2/5 of 0.5 s is 0.2 s.
near(Skull.blend_weight(0.2,0.5),0,'short throws still use the fraction')
near(Skull.blend_weight(0.35,0.5),0.5)
assert(Skull.blend_weight(0.3,1)>0,'and the cap really shortens the free flight')
near(Skull.blend_weight(0.1,0),1,'no flight: on the real skull')
-- The free flight arcs now (user, worn: "can we have the skull tumble and
-- follow a ballistic arc rather than moving in a straight line?"). Only the
-- DRAWN skull does; the real one still flies straight to its target, and the
-- blend still lands on it.
local d=Skull.drawn_position({0,0,1},{0,2,0},0.5,{0,4,1},0)
near(d[1],0); near(d[2],1,'free flight at the release velocity')
near(d[3],1-0.5*Skull.GRAVITY*0.25,'and falls under gravity')
-- Straight up and along: the horizontal is untouched by the drop.
local arc=Skull.ballistic({0,0,0},{3,0,4},1)
near(arc[1],3,'horizontal is ballistic-free'); near(arc[2],0)
near(arc[3],4-0.5*Skull.GRAVITY,'and the vertical carries the gravity')
near(Skull.ballistic({1,2,3},{0,0,0},0)[3],3,'no time, no drop')
near(Skull.ballistic({1,2,3},{0,0,0},-5)[3],3,'nor negative time')
-- Over the free flight's own cap the drop stays in the range a throw reads as.
local drop=0.5*Skull.GRAVITY*Skull.FREE_MAX_SECONDS*Skull.FREE_MAX_SECONDS
assert(drop>0.15 and drop<0.6,'the arc is visible but not a fall: '..drop)

-- The tumble axis is RANDOM per throw (user, 18 September: "give the thrown
-- skull a random tumble rather than a horizontal spin"). Uniform on the
-- sphere, not uniform in the angles, which would crowd the poles.
local axis = Skull.random_axis(0.3, 0.7)
near(math.sqrt(axis[1]^2 + axis[2]^2 + axis[3]^2), 1, 'the axis is a unit vector')
for _, pair in ipairs({{0, 0}, {0.999, 0.999}, {0.5, 0}, {1, 1}, {0/0, 0.2}}) do
  local a = Skull.random_axis(pair[1], pair[2])
  near(math.sqrt(a[1]^2 + a[2]^2 + a[3]^2), 1,
    'unit at ' .. tostring(pair[1]) .. ',' .. tostring(pair[2]))
end
-- Different draws give different axes, or it is not random.
local a1, a2 = Skull.random_axis(0.1, 0.2), Skull.random_axis(0.8, 0.6)
assert(math.abs(a1[1]-a2[1]) + math.abs(a1[2]-a2[2]) + math.abs(a1[3]-a2[3]) > 0.1,
  'two draws differ')
-- Not crowded onto the horizontal, which is what it replaced: the z of a
-- uniform axis is uniform in [-1,1], so a spread of draws must reach high |z|.
local reached = 0
for i = 0, 20 do
  if math.abs(Skull.random_axis(i / 21, 0.3)[3]) > 0.8 then reached = reached + 1 end
end
assert(reached >= 2, 'the axis reaches the poles, got ' .. reached)

-- The rate: harder throws spin faster, up to a cap.
local slow = Skull.tumble_rate({0, 2, 0})
local fast = Skull.tumble_rate({0, 9, 0})
assert(fast > slow, 'a harder throw spins faster: ' .. fast .. ' vs ' .. slow)
near(Skull.tumble_rate({0, 1000, 0}), Skull.TUMBLE_MAX_RATE, 'and the spin is capped')
assert(Skull.tumble_rate({0, 0, 0}) == nil, 'a dead stop does not tumble')
assert(Skull.tumble_rate(nil) == nil and Skull.tumble_rate({0/0, 1, 0}) == nil)
-- A purely vertical throw DOES tumble now: the axis is no longer derived from
-- the velocity, so there is nothing about it to be degenerate.
assert(Skull.tumble_rate({0, 0, 5}) ~= nil, 'a vertical throw still tumbles')

-- The angle only ever grows. The first cut scaled the finished angle by
-- (1 - weight), which is a parabola: the skull spun forward and then spun
-- BACKWARD through the same arc to its rest orientation.
local angle, rate = 0, 10
local highest = 0
for step = 1, 40 do
  local weight = math.min(1, step / 40)
  local next_angle = Skull.tumbled_angle(angle, rate, weight, 1 / 40)
  assert(next_angle >= angle - 1e-12,
    'the tumble never rewinds: ' .. next_angle .. ' after ' .. angle)
  angle = next_angle
  highest = math.max(highest, angle)
end
near(angle, highest, 'and it ends at its furthest point, not back at the start')
assert(angle > 1, 'it actually turned: ' .. angle)
-- Fully blended in, it stops accumulating.
near(Skull.tumbled_angle(3, 10, 1, 0.1), 3, 'at full blend the spin has stopped')
near(Skull.tumbled_angle(3, 10, 0.5, 0), 3, 'no time, no turn')
near(Skull.tumbled_angle(0/0, 10, 0, 0.1), 1, 'a nan angle restarts from zero')

-- The step, which the sweep collides. A closed form cannot be collided, so the
-- free flight is integrated now (user: "it should bounce off the ground and
-- not path through solid objects").
local p, v = Skull.step({0, 0, 10}, {0, 5, 0}, 0.1)
near(p[2], 0.5, 'the horizontal advances')
near(v[3], -Skull.GRAVITY * 0.1, 'and gravity is applied to the velocity')
near(p[3], 10 + v[3] * 0.1, 'which is what moves the height')
local sp, sv = Skull.step({1, 2, 3}, {4, 5, 6}, 0)
assert(sp[1] == 1 and sv[1] == 4, 'no time, no step')
assert(Skull.step(nil, {0,0,0}, 0.1) == nil, 'nothing to step')

-- The bounce. Reflected about the normal, damped, and the sliding part kept.
local up = {0, 0, 1}
local b = Skull.bounce({0, 4, -10}, up, 0.35)
assert(b[3] > 0, 'it comes back up off the floor: ' .. b[3])
near(b[3], 10 * 0.35, 'damped by the restitution')
assert(b[2] > 0 and b[2] < 4, 'and slides on, slowed: ' .. b[2])
-- An unnormalised normal is normalised rather than scaling the result.
local scaled = Skull.bounce({0, 4, -10}, {0, 0, 5}, 0.35)
near(scaled[3], b[3], 'the normal length does not change the bounce')
-- Already leaving the surface: not flipped back into it, which is what makes
-- a resting object jitter.
local leaving = Skull.bounce({0, 1, 3}, up, 0.35)
assert(leaving[3] == 3, 'a velocity already off the surface is untouched')
-- Degenerate normals and inputs pass through rather than producing nonsense.
local zero_n = Skull.bounce({0, 0, -5}, {0, 0, 0}, 0.35)
assert(zero_n[3] == -5, 'a zero normal is not a surface')
assert(Skull.bounce(nil, up, 0.35) == nil)
assert(Skull.RESTITUTION > 0 and Skull.RESTITUTION < 1, 'bone, not rubber')
assert(Skull.FRICTION > 0 and Skull.FRICTION <= 1, 'sliding is damped, not reversed')
-- A wall, not a floor: the horizontal component reverses instead.
local wall = Skull.bounce({-8, 0, 0}, {1, 0, 0}, 0.35)
assert(wall[1] > 0, 'it comes back off the wall: ' .. wall[1])

-- The drawn position takes a stepped free flight when one is given, so a
-- bounced path is what gets blended rather than the closed form.
local blended = Skull.drawn_position({0,0,0}, {0,0,0}, 0.1, {0, 10, 0}, 0, {0, 3, 0})
near(blended[2], 3, 'the stepped position is used')
local without = Skull.drawn_position({0,0,5}, {0,0,0}, 0, {0, 10, 0}, 0)
near(without[3], 5, 'and the closed form still works without one')

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
-- One error used to switch the whole module off for the session, so a bug in
-- the purely cosmetic bounce cost the side mirroring and the hold pose too
-- (worn, 18 September). Three strikes, and a level load re-arms.
assert(Skull.MAX_CONSECUTIVE_FAILURES and Skull.MAX_CONSECUTIVE_FAILURES > 1,
  'one error does not stand the module down, got ' .. tostring(Skull.MAX_CONSECUTIVE_FAILURES))
assert(Skull.MAX_CONSECUTIVE_FAILURES <= 10, 'but a run of them still does')

-- The grab's axis and angle from quaternion elements: the identity gives no
-- axis and no angle; a quarter turn about z gives z and pi/2; a turn past a
-- half is taken the short way; a negated quaternion is the same rotation.
do
  local axis, angle = Skull.axis_angle(0, 0, 0, 1)
  assert(axis == nil and angle == 0, 'the identity has no axis')
  local s, c = math.sin(math.pi / 4), math.cos(math.pi / 4)
  axis, angle = Skull.axis_angle(0, 0, s, c)
  assert(math.abs(axis[3] - 1) < 1e-9 and math.abs(angle - math.pi / 2) < 1e-9, 'a quarter turn about z')
  axis, angle = Skull.axis_angle(0, 0, -s, -c)
  assert(math.abs(angle) - math.pi / 2 < 1e-9 and math.abs(axis[3] * angle - math.pi / 2) < 1e-9, 'the negated quaternion is the same turn')
  local h = math.rad(100)
  axis, angle = Skull.axis_angle(0, math.sin(h), 0, math.cos(h))
  assert(math.abs(math.abs(angle) - math.rad(160)) < 1e-9, 'a 200 degree turn is taken as 160 the other way')
  assert(Skull.GRAB_HOLD_MIN < Skull.GRAB_RADIUS + 0.05 and Skull.GRAB_HOLD_MAX > Skull.GRAB_HOLD_MIN, 'the held distance brackets the skull')
end

-- The held layout (19:10 worn run, "no change": the unit's world box held
-- its distance to neither the placed centre nor the root, so the mesh is on
-- the children and the layout was wrong). A rigid part is the drawn point
-- plus the part's rest offset spun by the wanted delta, and nothing else:
-- two parts that differ in rest offset keep their separation under any
-- spin, and a part with no rest offset sits on the drawn point whatever
-- the spin. The placement's grab call has to ask for that pivot, and the
-- placement has to honour it, or the parts spin about their mean and the
-- root's turning swings them (the source scan below).
do
  local quarter = function(v) return {-v[2], v[1], v[3]} end
  local a = Skull.rigid_part({1, 2, 3}, {0.1, 0, 0}, quarter)
  local b = Skull.rigid_part({1, 2, 3}, {0, 0.1, 0}, quarter)
  near(a[1], 1, 'x spun to y') near(a[2], 2.1, 'the offset is spun') near(a[3], 3, 'z untouched')
  local sep = math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
  near(sep, math.sqrt(0.02), 'the parts keep their separation under the spin')
  local o = Skull.rigid_part({1, 2, 3}, {0, 0, 0}, quarter)
  near(o[1], 1) near(o[2], 2) near(o[3], 3, 'a part with no offset is the drawn point')
  local u = Skull.rigid_part({1, 2, 3}, {0.1, 0, 0}, nil)
  near(u[1], 1.1, 'no spin, the rest offset as is')
  assert(Skull.GRAB_PIVOT ~= nil, 'the held pivot is named')
  local source = assert(io.open(arg[1], 'rb')):read('*a')
  local grab_call = source:find('or nil, angle, Skull%.GRAB_PIVOT%)', 1)
  assert(grab_call, 'the grab places its parts with the drawn-point pivot')
  assert(source:find('pivot_mode == Skull%.GRAB_PIVOT then%s+pivot = local_offset', 1),
    'the placement spins about the drawn point when asked')
end

print('skull_throw=pass flight_time blend drawn forward_offsets rest_offsets smoothed stock_offset lead fed_offset axis_angle rigid_part')
