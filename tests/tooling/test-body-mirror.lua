local Mirror=dofile(assert(arg[1]))
assert(Mirror.keeps_slot('slot_body_torso',{slot_type='body'}))
assert(Mirror.keeps_slot('slot_gear_head',{slot_type='gear'}))
assert(Mirror.keeps_slot('slot_gear_material_override_decal',{slot_type='material'}))
assert(Mirror.keeps_slot('slot_unarmed',{slot_type='weapon'}),'spawner plumbing')
assert(not Mirror.keeps_slot('slot_primary',{slot_type='weapon'}),'no weapons')
assert(not Mirror.keeps_slot('slot_pocketable',{slot_type='gadget',ignore_character_spawning=true}))
assert(not Mirror.keeps_slot('slot_companion_gear_full',{slot_type='gear'}),'no companion')
assert(not Mirror.keeps_slot('slot_insignia',{slot_type='ui',ignore_character_spawning=true}))
local a={j_hips=2,j_head=9}
local b={j_hips=2,j_head=9}
local c={j_hips=2,j_head=10}
local function lookup(t) return function(name) return t[name] end end
assert(Mirror.same_layout(246,246,lookup(a),lookup(b),{'j_hips','j_head'}))
assert(not Mirror.same_layout(246,220,lookup(a),lookup(b),{'j_hips'}),'node counts differ')
assert(not Mirror.same_layout(246,246,lookup(a),lookup(c),{'j_hips','j_head'}),'probe index differs')
assert(Mirror.parse_mode('mirror')=='mirror' and Mirror.parse_mode(' overlay\n')=='overlay')
assert(Mirror.parse_mode('enabled')==nil and Mirror.parse_mode(nil)==nil)
assert(Mirror.MODES.overlay.distance==0 and not Mirror.MODES.overlay.facing)
assert(Mirror.MODES.mirror.distance==Mirror.MIRROR_DISTANCE and Mirror.MODES.mirror.facing)
local head={slot_gear_head=true,slot_body_hair=true}
assert(Mirror.hides_slot('overlay','slot_gear_head',head))
assert(not Mirror.hides_slot('overlay','slot_body_torso',head))
assert(not Mirror.hides_slot('mirror','slot_gear_head',head),'mirror shows the whole character')
assert(not Mirror.hides_slot(nil,'slot_gear_head',head))
assert(Mirror.parse_mode('overlaycopy')=='overlaycopy')
assert(Mirror.MODES.overlay.solve_arms and not Mirror.MODES.overlaycopy.solve_arms)
assert(Mirror.MODES.overlaycopy.distance==0 and Mirror.hides_slot('overlaycopy','slot_gear_head',head))
local function near(a,b,e) return math.abs(a-b)<(e or 1e-6) end
local function dist(a,b) return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2+(a[3]-b[3])^2) end
local o={0,0,0}
local e,h,ok=Mirror.elbow(o,{0.2,0,-1},{0.4,0,0},0.3,0.3)
assert(ok and near(dist(o,e),0.3) and near(dist(e,h),0.3) and near(dist(h,{0.4,0,0}),0),'reachable: lengths kept, hand on target')
assert(near(e[1],0.2) and e[3]<0 and near(e[2],0),'bends toward the hint')
e,h,ok=Mirror.elbow(o,{0.2,0,1},{0.4,0,0},0.3,0.3)
assert(e[3]>0,'hint above bends up')
e,h,ok=Mirror.elbow(o,{0.2,0,-1},{1,0,0},0.3,0.3)
assert(not ok and near(dist(o,h),0.5994,1e-4) and near(dist(o,e),0.3) and near(dist(e,h),0.3,1e-4),'out of reach: straight toward target, lengths kept')
e,h,ok=Mirror.elbow(o,{0.1,0,0},{0.4,0,0},0.3,0.3)
assert(ok and e[3]<0,'hint on the line bends down')
e,h,ok=Mirror.elbow(o,{0,0,0.1},{0,0,0.4},0.3,0.3)
assert(ok and near(dist(o,e),0.3) and near(dist(e,h),0.3),'vertical reach with hint on the line')
e,h,ok=Mirror.elbow(o,{0,0,-1},{0.05,0,0},0.3,0.2)
assert(not ok and near(dist(o,e),0.3) and near(dist(e,h),0.2,1e-3),'too close: lengths kept')
assert(Mirror.elbow(o,o,o,0.3,0.3)==nil and Mirror.elbow(o,o,{1,0,0},0,0.3)==nil)
assert(Mirror.MODES.overlay.near_eye and not Mirror.MODES.overlayarms.near_eye and Mirror.MODES.overlayarms.solve_arms)
local eye={0,0.08,1.57}
local hide,d,why=Mirror.near_eye({0,0,1.42},{0.15,0.12,0.06},eye,1.34)
assert(hide and why=='near_eye' and d<0.25,'collar ring below the eye is hidden')
hide,d,why=Mirror.near_eye({0.22,0,1.34},{0.1,0.1,0.1},eye,1.34)
assert(not hide and why=='far','pauldron at the shoulder is kept')
hide,d,why=Mirror.near_eye({0,0,1.36},{0.1,0.1,0.1},eye,1.40)
assert(not hide and why=='below_shoulders')
hide,d,why=Mirror.near_eye({0,0,1.45},{0.3,0.2,0.5},eye,1.34)
assert(not hide and why=='too_large','whole torso is kept')
for _,name in ipairs({'overlay','overlayarms','overlaycopy','overlayfollow'}) do
    assert(Mirror.MODES[name].hand_rig,'one pair of hands: '..name)
end
assert(not Mirror.MODES.mirror.hand_rig,'mirror stands apart from the player')
-- ...but it reflects the body the player HAS, not the one the game animates.
-- It carried none of the solve until 18 September, so looking into it showed
-- the character going through its animation rather than the person in front of
-- it. Everything that shapes the overlay shapes the reflection, except the
-- three flags that are about being inside a body rather than looking at one.
for _,flag in ipairs({'solve_arms','follow_neck','clavicles',
        'body_yaw','protract','stretch','gait','arm_length'}) do
    assert(Mirror.MODES.mirror[flag],'the mirror reflects the solved body: '..flag)
    assert(Mirror.MODES.overlay[flag],'and the overlay is where that solve is defined: '..flag)
end
-- No live mode scales the body to the neck: the scale is the game's own
-- character height for the profile, which the calibration sets, and the
-- height beyond the settable range goes into the bones (user, 19 September).
for _,name in ipairs({'overlay','mirror','reflection'}) do
    assert(not Mirror.MODES[name].scale_to_neck,'no scaling to the neck: '..name)
    assert(type(Mirror.MODES[name].arm_length)=='table' and Mirror.MODES[name].arm_length.min<1 and
        Mirror.MODES[name].arm_length.max>1,'the arm bones take the calibrated lengths: '..name)
end
assert(not Mirror.MODES.mirror.hide_head,'a mirror without a face is useless')
assert(not Mirror.MODES.mirror.near_eye,'nothing is near the eye three metres away')
assert(Mirror.MODES.mirror.distance > 0 and Mirror.MODES.mirror.facing,
    'and it still stands in front, facing back')
assert(Mirror.MODES.overlay.follow_neck and not Mirror.MODES.overlayarms.follow_neck)
local off,len=Mirror.neck_offset({0,0.16,1.45},{0,-0.07,1.69},true)
assert(near(off[2],-0.23) and near(off[3],0.24) and near(len,math.sqrt(0.23^2+0.24^2)),'moves neck onto target')
off=Mirror.neck_offset({0,0.16,1.45},{0,-0.07,1.69})
assert(near(off[2],-0.23) and off[3]==0,'never lifts by default')
off=Mirror.neck_offset({0,0,1.45},{0,0,1.20})
assert(near(off[3],-0.25),'lowers for a crouch')
off,len=Mirror.neck_offset({0,0,0},{0,0,2},true)
assert(near(off[3],Mirror.NECK_FOLLOW_MAX) and near(len,2),'capped')
assert(not Mirror.MODES.overlay.scale_to_neck and not Mirror.MODES.overlayfollow.scale_to_neck and Mirror.MODES.overlayfollow.follow_neck)
assert(Mirror.parse_mode('overlayfollow')=='overlayfollow')
assert(near(Mirror.scale_ratio(nil,1.5,1.8,0),1.2),'first frame takes the target')
assert(Mirror.scale_ratio(nil,1.5,1.2,0)==1,'never shrinks: a crouch lowers instead')
assert(near(Mirror.scale_ratio(nil,1.5,3,0),Mirror.MAX_BODY_SCALE_RATIO),'capped')
assert(near(Mirror.scale_ratio(1,1.5,1.8,0.5),1.1),'eases by rate times dt')
assert(Mirror.scale_ratio(nil,0,1.8,0)==1,'degenerate neck height')
assert(Mirror.MODES.overlay.neck_back_extra==nil,'camera at the proper place, cowl or not')
-- Clavicles: swing toward the estimated shoulder, capped.
do
    local axis,angle=Mirror.clavicle_swing({0,0,0},{0.1,0,0},{0,0.1,0},math.rad(90))
    assert(near(axis[3],1) and near(angle,math.pi/2),'quarter turn about up')
    axis,angle=Mirror.clavicle_swing({0,0,0},{0.1,0,0},{0,0.1,0},Mirror.CLAVICLE_MAX)
    assert(near(angle,Mirror.CLAVICLE_MAX),'capped at CLAVICLE_MAX')
    axis,angle=Mirror.clavicle_swing({0,0,0},{0.1,0,0},{0.1,0.01,0},Mirror.CLAVICLE_MAX)
    assert(angle<Mirror.CLAVICLE_MAX and near(angle,math.atan2(0.01,0.1)),'small turns are exact')
    assert(Mirror.clavicle_swing({0,0,0},{0.1,0,0},{0.2,0,0})==nil,'already aligned')
    assert(Mirror.clavicle_swing({0,0,0},{0,0,0},{0.2,0,0})==nil,'degenerate')
    assert(Mirror.MODES.overlay.clavicles and not Mirror.MODES.overlaystock.clavicles)
    assert(Mirror.MODES.overlay.body_yaw and not Mirror.MODES.overlayrootyaw.body_yaw and Mirror.MODES.overlayrootyaw.clavicles)
    -- Spine: shares of the remaining swing that add up to the design weights.
    local f=Mirror.chain_fractions(Mirror.SPINE)
    assert(near(f[1],0.2) and near(f[2],0.3/0.8) and near(f[3],1),'spine fractions')
    local taken,left=0,1
    for i=1,3 do local share=left*f[i]; taken=taken+share; left=left-share
        assert(near(share,Mirror.SPINE[i][2]),'joint '..i..' takes its weight') end
    assert(near(taken,1))
    assert(Mirror.MODES.overlayspine.spine_bend and not Mirror.MODES.overlay.spine_bend)
    assert(near(Mirror.MODES.overlayreach.clavicle_max,math.rad(45)) and Mirror.MODES.overlay.clavicle_max==nil,'reach A/B cap')
    -- The calibrated arm lengths are the default now (user, 19 September),
    -- with a clamp that is a sanity bound rather than the A/B mode's fit.
    assert(Mirror.MODES.overlayarmlength.arm_length and Mirror.MODES.overlay.arm_length,'arm length everywhere')
    assert(Mirror.MODES.overlay.arm_length.min<Mirror.MODES.overlayarmlength.arm_length.min and
        Mirror.MODES.overlay.arm_length.max>Mirror.MODES.overlayarmlength.arm_length.max,'the default clamp is the looser one')
    -- Protraction: none below 0.9 of arm length, 8 % of it by 1.1.
    assert(Mirror.protraction(0.5,0.6)==0,'well within reach')
    assert(near(Mirror.protraction(0.6,0.6),0.5*0.08*0.6),'halfway up the ramp at 1.0 of arm length')
    assert(near(Mirror.protraction(0.66,0.6),0.08*0.6),'full at 1.1')
    assert(near(Mirror.protraction(0.9,0.6),0.08*0.6),'full')
    assert(Mirror.protraction(0.5,0)==0 and Mirror.protraction(0/0,0.6)==0)
    assert(Mirror.MODES.overlayprotract.protract and not Mirror.MODES.overlayprotract.clavicles)
    -- Soft stretch: none within reach, proportional past it, capped.
    assert(Mirror.stretch_ratio(0.5,0.3,0.3)==1,'within reach')
    assert(near(Mirror.stretch_ratio(0.66,0.3,0.3),1.1),'10 percent past reach')
    assert(near(Mirror.stretch_ratio(1.0,0.3,0.3),1+Mirror.STRETCH_SHARE),'capped')
    assert(Mirror.stretch_ratio(0.5,0,0)==1 and Mirror.MODES.overlayprotract.stretch)
    assert(Mirror.MODES.overlay.clavicles and Mirror.MODES.overlay.protract and Mirror.MODES.overlay.stretch,
        'overlay does the swing, protraction and stretch')
    assert(Mirror.MODES.overlayswing.clavicles and not Mirror.MODES.overlayswing.protract,'swing-only A/B')
end
-- The copy's neck target: the body frame's neck moved level and back along
-- the head's heading and straight down, scaled with the frame.
local nt = Mirror.neck_target({1, 2, 1.5}, 0, 1)
assert(math.abs(nt[1] - 1) < 1e-9 and math.abs(nt[2] - 1.95) < 1e-9 and math.abs(nt[3] - 1.4) < 1e-9, 'yaw 0 faces +y: back is -y')
nt = Mirror.neck_target({0, 0, 1.5}, math.pi / 2, 1.1)
assert(math.abs(nt[1] - 0.055) < 1e-9 and math.abs(nt[2]) < 1e-9 and math.abs(nt[3] - 1.39) < 1e-9, 'yaw 90 faces -x: back is +x, scaled')
assert(Mirror.neck_target(nil, 0, 1) == nil)
assert(Mirror.NECK_EXTRA_BACK == 0.05 and Mirror.NECK_EXTRA_DOWN == 0.10)
-- The heading eases after the body frame's steps, the short way round, and
-- takes a snap turn at once.
assert(Mirror.smooth_yaw(nil, 0.4, 0.016) == 0.4, 'first sample')
local y = Mirror.smooth_yaw(0, math.rad(20), 0.3)
assert(math.abs(y - math.rad(20) * (1 - math.exp(-1))) < 1e-9, 'one time constant closes 63 per cent of a step')
y = Mirror.smooth_yaw(math.pi - 0.05, -math.pi + 0.05, 0.016)
assert(y > math.pi - 0.05 or y < -math.pi + 0.05, 'across the seam the short way')
assert(Mirror.smooth_yaw(0, math.rad(90), 0.016) == math.rad(90), 'a snap turn is taken at once')
for _ = 1, 200 do y = Mirror.smooth_yaw(y, 1.0, 0.016) end
assert(math.abs(y - 1.0) < 1e-3, 'and it arrives')

-- The mirror key's copy: posed by the overlay's pipeline, never the hand
-- rig, its head shown; then turned about the player and stood ahead.
local reflection = assert(Mirror.MODES.reflection)
assert(reflection.reflect and reflection.solve_arms and reflection.follow_neck and not reflection.scale_to_neck and
    reflection.clavicles and reflection.body_yaw and not reflection.hand_rig and not reflection.hide_head and
    not reflection.near_eye and reflection.distance == 0)
-- Heading 0 faces +y. A root 10 cm behind the pivot ends 10 cm beyond it,
-- 2.5 m further on; a root to the pivot's left ends on its right.
local rr = Mirror.reflected_root({1.2, 3.0 - 0.1, 0.5}, {1.0, 3.0, 1.4}, 0, 2.5)
assert(math.abs(rr[1] - 0.8) < 1e-9 and math.abs(rr[2] - 5.6) < 1e-9 and rr[3] == 0.5, 'turned about the pivot, stood ahead, height kept')
rr = Mirror.reflected_root({0, 0, 0}, {0, 0, 0}, math.pi / 2, 2.5)
assert(math.abs(rr[1] + 2.5) < 1e-9 and math.abs(rr[2]) < 1e-9, 'yaw 90 faces -x')
-- Which mode runs: the dev flag first, then the mirror key in the
-- Psykhanium, then the full-body option's overlay.
assert(Mirror.requested_mode(nil, false, false, false) == nil)
assert(Mirror.requested_mode("overlayspine", true, true, true) == "overlayspine", 'the dev flag wins')
assert(Mirror.requested_mode("nonsense", false, false, true) == "overlay", 'an unknown flag mode is no flag')
assert(Mirror.requested_mode(nil, true, true, true) == "mirror", 'the key shows the mirror in the Psykhanium')
assert(Mirror.requested_mode(nil, true, false, false) == nil, 'and nowhere else')
assert(Mirror.requested_mode(nil, true, false, true) == "overlay", 'outside it the option still runs')
assert(Mirror.requested_mode(nil, false, true, true) == "overlay" and Mirror.MODES[Mirror.OPTION_MODE] ~= nil)
-- The yaw chain the trace prints. Degrees, wrapped, and nil rather than a
-- number when a yaw is missing -- a trace that prints 0 for "not measured"
-- reads as "did not move", which is the one answer it must never fake.
local sample = Mirror.yaw_sample(0, math.rad(10), math.rad(20), math.rad(30), math.rad(40), math.rad(50))
near(sample.head, 0, 1e-9); near(sample.target, 10, 1e-9); near(sample.frame, 20, 1e-9)
near(sample.mirror, 30, 1e-9); near(sample.avatar, 40, 1e-9); near(sample.unit, 50, 1e-9)
local missing = Mirror.yaw_sample(nil, 0/0, 0, nil, nil, nil)
assert(missing.head == nil and missing.target == nil, 'a missing yaw is nil, not zero')
assert(missing.frame == 0, 'and a real zero survives')
-- Wrapped, so a body crossing the back of the compass does not read as a
-- 359 degree step -- which is exactly the frame a stick turn is measured on.
near(Mirror.yaw_sample(math.rad(190), 0, 0, 0, 0, 0).head, -170, 1e-9)
near(Mirror.yaw_step(179, -179), -2, 1e-9, 'a step across the wrap is small')
near(Mirror.yaw_step(-179, 179), 2, 1e-9)
near(Mirror.yaw_step(10, 4), 6, 1e-9)
assert(Mirror.yaw_step(nil, 4) == nil and Mirror.yaw_step(4, nil) == nil, 'no step without both ends')
assert(Mirror.TRACE_EVERY >= 1 and Mirror.TRACE_MAX_LINES > 0, 'the trace is bounded')
-- The due rule spends the line budget on movement. A flat every-Nth-frame
-- trace burns it all standing in the hub, and the two things being looked for
-- may not have happened yet.
local function due(steps, root, since) return (Mirror.trace_due(steps, root, since)) end
assert(due({}, nil, 0), 'the first sample is always taken -- later steps are read against it')
assert(not due({0, 0, 0}, 0, 0), 'a still body at rest writes nothing')
assert(due({0, 0, 0}, 0, Mirror.TRACE_HEARTBEAT_FRAMES), 'but the heartbeat still comes')
assert(due({0, 0, 0}, Mirror.TRACE_MOVED_M * 2, 0), 'movement of the root is taken')
assert(due({0, Mirror.TRACE_MOVED_DEG * 2, 0}, 0, 0), 'and a turn of any yaw in the chain')
assert(due({0, -Mirror.TRACE_MOVED_DEG * 2, 0}, 0, 0), 'in either direction')
assert(not due({0 / 0}, 0, 0), 'a nan step is not movement')
-- The thresholds have to sit below what a person can see, or a jitter too
-- small to describe is also too small to record.
assert(Mirror.TRACE_MOVED_M <= 0.001 and Mirror.TRACE_MOVED_DEG <= 0.25,
    'the thresholds are below the visible')
local _, why = Mirror.trace_due({0}, Mirror.TRACE_MOVED_M * 2, 0)
assert(why == 'moved', 'the line says why it was taken, got ' .. tostring(why))

-- Which units the copy owns, and -- far more important -- which it does not.
-- Disabling the REAL player's collision would drop them through the world and
-- make them unhittable, which is a worse fault than the one this fixes, so the
-- exclusion is asserted first and from several directions.
local avatar = {'the real player'}
local root = {'the copy'}
local gun, gunSight, hat = {'gun'}, {'sight'}, {'hat'}
local data = {slots = {
  slot_secondary = {unit_3p = gun, attachments_by_unit_3p = {[gun] = {gunSight}}},
  slot_gear_head = {unit_3p = hat},
  -- A slot the profile left empty, and one whose unit IS the avatar: the
  -- second is the shape that would end the player's collision.
  slot_empty = {},
  slot_bad = {unit_3p = avatar},
}}
local owned = Mirror.collider_units(root, data, avatar)
for _, unit in ipairs(owned) do
  if unit == avatar then throwIfAvatar = true end
end
if throwIfAvatar then error('the real player was listed for collider removal') end
local function has(list, unit)
  for _, entry in ipairs(list) do if entry == unit then return true end end
  return false
end
if not has(owned, root) then error('the copy itself is not listed') end
if not has(owned, gun) then error('a slot unit is not listed') end
if not has(owned, gunSight) then error('an attachment is not listed') end
if not has(owned, hat) then error('a second slot is not listed') end
if #owned ~= 4 then error('exactly the four copy units, got ' .. #owned) end
-- Reachable twice (a slot and its own attachment list) must appear once.
local twice = Mirror.collider_units(root,
  {slots = {a = {unit_3p = gun, attachments_by_unit_3p = {[gun] = {gun, gunSight}}}}}, avatar)
if #twice ~= 3 then error('a unit reachable twice was listed twice, got ' .. #twice) end
-- Nothing to do is not an error, and a nil avatar must not make the root nil.
if #Mirror.collider_units(nil, nil, avatar) ~= 0 then error('no copy, no units') end
if #Mirror.collider_units(root, nil, nil) ~= 1 then error('the copy is still listed without an avatar') end

-- The torso's facing, from its shoulder line, in the same yaw convention as
-- the head. The first two passes at "the body turns faster than my view"
-- measured ROOT yaws and concluded the body barely moved; the torso is a joint
-- posed from the avatar every frame, so the root was never the thing being
-- reported on.
local function shoulders_at(yaw, width)
  width = width or 0.34
  -- right = (cos yaw, sin yaw): the shoulder line points along it.
  local rx, ry = math.cos(yaw) * width * 0.5, math.sin(yaw) * width * 0.5
  return {-rx, -ry, 1.4}, {rx, ry, 1.4}
end
for _, yaw in ipairs({0, 0.6, -1.2, 2.9, -3.0}) do
  local l, r = shoulders_at(yaw)
  local measured = Mirror.torso_yaw(l, r)
  local diff = (measured - yaw + math.pi) % (2 * math.pi) - math.pi
  near(diff, 0, 1e-9, 'torso yaw at ' .. yaw .. ' read as ' .. tostring(measured))
end
-- It matches the head's convention, which is the whole point: the two are
-- compared against each other, so a sign or a quarter turn between them would
-- read as the body leading or lagging when it was doing neither.
-- Checked against the FORWARD convention the head yaw uses -- forward =
-- (-sin yaw, cos yaw), read back as atan2(-fx, fy) -- rather than against the
-- number that was put in, which would only restate the loop above.
for _, yaw in ipairs({0.75, -2.1}) do
  local l, r = shoulders_at(yaw)
  local fx, fy = -math.sin(yaw), math.cos(yaw)
  local head_convention = math.atan2(-fx, fy)
  local diff = (Mirror.torso_yaw(l, r) - head_convention + math.pi) % (2 * math.pi) - math.pi
  near(diff, 0, 1e-9, 'the torso and the head are in the same frame at ' .. yaw)
end
-- Degenerate and missing inputs are nil rather than a fabricated zero, because
-- zero here means "facing along the basis" and would read as a real number.
assert(Mirror.torso_yaw({0, 0, 0}, {0, 0, 0}) == nil, 'shoulders on top of each other')
assert(Mirror.torso_yaw(nil, {1, 0, 0}) == nil and Mirror.torso_yaw({0, 0, 0}, nil) == nil)
assert(Mirror.torso_yaw({0 / 0, 0, 0}, {1, 0, 0}) == nil, 'a nan shoulder')
-- Height is ignored: a shoulder line tilted by a lean still faces the same way.
local tilted_l, tilted_r = shoulders_at(0.4)
tilted_r[3] = tilted_r[3] + 0.2
near(Mirror.torso_yaw(tilted_l, tilted_r), 0.4, 1e-9, 'a lean does not change the facing')

-- ONE BODY (19 September). The stock 3P model is hidden wholesale while a
-- copy is drawing the player's body, so this predicate decides whether the
-- player has a body at all. Every mode is checked rather than a sample: a
-- mode added later that stands the copy on the player must answer true, and
-- one that stands it away must answer false, or the stock model is taken
-- away with nothing in its place.
-- The modes that stand the copy on the player, named rather than recomputed.
-- Recomputing `distance == 0 and not reflect` here would restate the
-- implementation and could not fail for any defect that preserved it (review,
-- 19 September); this list is a second opinion, and a mode added later that
-- belongs on it has to be put here by hand.
local on_the_player = {
  overlay = true, overlaycopy = true, overlayarms = true, overlayfollow = true,
  overlayspine = true, overlayreach = true, overlayarmlength = true,
  overlayprotract = true, overlayswing = true, overlaytrue = true,
  overlayrootyaw = true, overlaystock = true, overlayanimated = true,
}
-- The animated-legs mode is the overlay with its legs on the copy's own
-- state machine: it draws the body, keeps the gait as its fallback, and
-- keeps every flag the overlay has.
assert(Mirror.MODES.overlayanimated.animated_legs and Mirror.MODES.overlayanimated.gait, 'animated legs with the gait behind them')
for flag, value in pairs(Mirror.MODES.overlay) do
  assert(Mirror.MODES.overlayanimated[flag] ~= nil, 'overlayanimated carries the overlay flag ' .. flag)
end
for name in pairs(Mirror.MODES) do
  local drawn = Mirror.draws_body(name, true, true)
  assert(drawn == (on_the_player[name] == true),
    name .. ' drew ' .. tostring(drawn) .. ', expected ' .. tostring(on_the_player[name] == true))
  -- Never before the copy exists, and never while the copy is HIDDEN for a
  -- scene-graph mismatch -- that one would hide the stock model and leave the
  -- player with nothing but a floating weapon, with no copy coming back.
  assert(not Mirror.draws_body(name, false, true), name .. ' has no copy yet')
  assert(not Mirror.draws_body(name, nil, true), name .. ' has no copy yet')
  assert(not Mirror.draws_body(name, true, false), name .. ' copy is not drawable')
  assert(not Mirror.draws_body(name, true, nil), name .. ' copy is not drawable')
end
-- Every mode this module ships is accounted for above, so a new one cannot be
-- added without a decision about whether it draws the player's body.
for name in pairs(on_the_player) do
  assert(Mirror.MODES[name], 'on_the_player names a mode that no longer exists: ' .. name)
end
assert(not Mirror.draws_body(nil, true, true), 'no mode draws nothing')
assert(not Mirror.draws_body('nosuchmode', true, true), 'an unknown mode draws nothing')
assert(Mirror.draws_body('overlay', true, true), 'the overlay is the player body')
assert(not Mirror.draws_body('mirror', true, true), 'the mirror stands away from the player')
assert(not Mirror.draws_body('reflection', true, true), 'the reflection is reflected out to the mirror')

-- THE TURN LEAK (19 September). Worn samples, degrees per sample, taken while
-- the head moved about one degree: the copy's torso swung up to ten. The rows
-- are (avatar root step, avatar torso step, copy root step, measured copy
-- torso step) straight off DARKTIDEVR_BODY_TRACE.
local turns = {
  {-10.53, -0.73, -0.04, 10.11},
  {  0.00,  4.77,  1.96,  6.60},
  { -7.18,  2.32,  1.55, 10.25},
  {  1.16,  2.03,  4.55,  4.91},
}
local moved = 0
for _, row in ipairs(turns) do
  local d_avatar, d_av_torso, d_unit, measured = row[1], row[2], row[3], row[4]
  -- A step is a difference of two yaws, so the predictor runs on the steps
  -- directly: every term in it is linear and the wrap does not bite at these
  -- sizes.
  local function step(corrected)
    return math.deg(Mirror.copy_torso_yaw(math.rad(d_avatar), math.rad(d_av_torso),
      math.rad(d_unit), corrected))
  end
  -- Uncancelled, the predictor reproduces what was actually measured. That is
  -- what makes this the diagnosis rather than a story: the term is d_unit +
  -- d_av_torso - d_avatar.
  assert(math.abs(step(false) - measured) < 1.5,
    'the leak predicts the measured torso step: ' .. step(false) .. ' vs ' .. measured)
  -- Cancelled, the copy's torso moves with the avatar's torso -- which is
  -- where the game already keeps it relative to the view -- and no longer
  -- with the avatar's ROOT, which is what the stick spins.
  assert(math.abs(step(true) - d_av_torso) < 1e-9,
    'cancelled, the torso follows the avatar torso')
  -- And what the cancellation removes is exactly the avatar root's share of
  -- the step -- stated as an identity rather than as a threshold, so this
  -- says what the fix does instead of merely that it does something.
  assert(math.abs((step(false) - step(true)) - (d_unit - d_avatar)) < 1e-9,
    'the cancellation removes the avatar root step')
  moved = math.max(moved, math.abs(step(false) - step(true)))
end
-- On the worst of these samples it is ten degrees a frame, which is the size
-- of the fault the user reported, not a rounding difference.
assert(moved > 10, 'the worst sample moves by ' .. moved .. ' degrees')
-- The leak itself: the yaw put back into the chain is the difference between
-- the avatar's root and the heading the copy's root was given.
near(math.deg(Mirror.root_yaw_leak(math.rad(30), math.rad(10))), 20, 1e-9, 'leak is the difference')
near(Mirror.root_yaw_leak(1.0, 1.0), 0, 1e-12, 'no difference, no leak')
-- Wrapped the short way round, or a body facing 179 degrees away would be
-- corrected the long way through a full turn.
near(math.deg(Mirror.root_yaw_leak(math.rad(-170), math.rad(170))), 20, 1e-9, 'wrapped the short way')
assert(Mirror.root_yaw_leak(nil, 1) == nil and Mirror.root_yaw_leak(1, nil) == nil)
assert(Mirror.root_yaw_leak(0 / 0, 1) == nil, 'a nan yaw corrects nothing')

-- The motion probe's step: a distance, nil for anything it cannot compare,
-- and the moving threshold sits between a standing character's breathing
-- and a walking step at 90 Hz.
near(Mirror.step_m({1, 2, 3}, {1, 2, 3}), 0, 1e-12, 'no move')
near(Mirror.step_m({0, 0, 0}, {0.03, 0.04, 0}), 0.05, 1e-9, 'a step of five centimetres')
assert(Mirror.step_m(nil, {0, 0, 0}) == nil and Mirror.step_m({0, 0, 0}, nil) == nil, 'a missing sample is no step')
assert(Mirror.step_m({0 / 0, 0, 0}, {0, 0, 0}) == nil, 'a nan sample is no step')
assert(Mirror.step_m({0, 0}, {0, 0, 0}) == nil, 'a short array is no step')
assert(Mirror.MOTION_MOVING_M > 0.0005 and Mirror.MOTION_MOVING_M < 0.01, 'moving threshold between breathing and a walking step')

-- THE SEPARATION RULE (user, 19 September): the base model exists hidden for
-- hit detection, the custom-IK body is the whole of what is drawn, and
-- nothing on it comes from the base model's animation -- not the idle sway,
-- not the stance in the sights, not the legs. The one read allowed is the
-- avatar's root (index 1): the simulated place the player stands. This scans
-- the module's source for any other read of an avatar joint. Before the
-- rule was applied the module copied `Unit.local_pose(avatar, index)` for
-- every joint and fell back to `Unit.world_position(avatar, arm.hand)`, and
-- this check refuses both by name.
local file = assert(io.open(arg[1], 'rb')); local source = file:read('*a'); file:close()
-- THE LEGS ARE THE EXCEPTION (user, 14:44 on 19 September, with the flicker
-- gone): "try re-enabling the original 3p model legs and attaching them to
-- the torso". The reads of the avatar's leg joints live between two markers
-- and are cut out before the scan, so anything else read from the avatar
-- still fails here. Each marked block must close, and there must be some.
local scanned, blocks = source, 0
while true do
  local open_at = scanned:find('LEGS FROM THE STOCK MODEL (begin)', 1, true)
  if not open_at then break end
  local _, close_at = scanned:find('LEGS FROM THE STOCK MODEL (end).', open_at, true)
  assert(close_at, 'a stock-legs block that never closes')
  scanned = scanned:sub(1, open_at - 1) .. scanned:sub(close_at + 1)
  blocks = blocks + 1
end
assert(blocks >= 2, 'the stock-legs blocks (ready and update) are marked')
assert(source:find('Unit%.local_pose%(avatar, index%)'), 'the stock legs are copied joint by joint from the avatar')
local forbidden = {
  'Unit%.local_pose%(avatar', 'Unit%.local_position%(avatar', 'Unit%.local_rotation%(avatar',
  'Unit%.local_scale%(avatar', 'Unit%.node%(avatar', 'shoulders%(avatar%)',
  'Unit%.world_position%(avatar,%s*[^1%s]', 'Unit%.world_rotation%(avatar,%s*[^1%s]',
  'Unit%.world_position%(avatar,%s*1%d', 'Unit%.world_rotation%(avatar,%s*1%d',
}
for _, pattern in ipairs(forbidden) do
  local at = scanned:find(pattern)
  assert(not at, 'the copy reads the avatar beyond its root: ' .. pattern .. ' at ' ..
    (at and select(2, scanned:sub(1, at):gsub('\n', '')) + 1 or 0))
end
assert(source:find('Unit%.world_position%(avatar, 1%)'), 'the root position is the one allowed read, and it is used')

-- Height beyond the settable range goes into the vertical bones as a
-- stretch factor: none within a centimetre, the exact ratio that makes the
-- floor-to-neck chain reach the calibrated height otherwise, clamped, and 1
-- for anything unusable.
near(Mirror.height_stretch(1.62, 1.62, 1.40), 1, 1e-12, 'no residual, no stretch')
near(Mirror.height_stretch(1.625, 1.62, 1.40), 1, 1e-12, 'half a centimetre is noise')
near(Mirror.height_stretch(1.64, 1.62, 1.40), 1, 1e-12, 'two centimetres is noise: the eye constants are not that exact')
near(Mirror.height_stretch(1.70, 1.62, 1.40), (1.40 + 0.08) / 1.40, 1e-12, 'eight centimetres taller lengthens the chain by eight')
near(Mirror.height_stretch(1.50, 1.62, 1.40), (1.40 - 0.12) / 1.40, 1e-12, 'twelve shorter compresses it by twelve')
assert(Mirror.height_stretch(2.60, 1.62, 1.40) == Mirror.STRETCH_MAX, 'clamped above')
assert(Mirror.height_stretch(0.90, 1.62, 1.40) == Mirror.STRETCH_MIN, 'clamped below')
assert(Mirror.height_stretch(nil, 1.62, 1.40) == 1 and Mirror.height_stretch(1.7, nil, 1.4) == 1 and
  Mirror.height_stretch(1.7, 1.62, 0) == 1 and Mirror.height_stretch(0 / 0, 1.62, 1.4) == 1, 'unusable input stretches nothing')
-- The hips stand at the ankle's height plus the legs, knee slightly soft,
-- and the legs stretched by the factor; a straight leg is never the
-- answer, and a missing length is no answer.
local hips = Mirror.standing_hips_height(0.10, 0.45, 0.42, 1)
assert(hips and hips < 0.10 + 0.45 + 0.42, 'hips under the straight leg')
near(hips, 0.10 + 0.42 + 0.45 * math.cos(Mirror.KNEE_REST_BEND), 1e-12, 'the knee softened by the rest bend')
-- A visible bend, and room for the gait's arc: at least ten degrees, at
-- most thirty (past that a standing body reads as crouching).
assert(Mirror.KNEE_REST_BEND >= math.rad(10) and Mirror.KNEE_REST_BEND <= math.rad(30), 'rest bend between ten and thirty degrees')
near(Mirror.standing_hips_height(0.10, 0.45, 0.42, 1.1) - 0.10, (hips - 0.10) * 1.1, 1e-12, 'the legs take the stretch, the ankle does not')
assert(Mirror.standing_hips_height(0.10, 0, 0.42, 1) == nil and Mirror.standing_hips_height(nil, 0.45, 0.42, 1) == nil)
near(Mirror.standing_hips_height(0.10, 0.45, 0.42, nil), hips, 1e-12, 'no factor is one')

-- The leg subtree by index: everything under either upper leg, found by
-- walking parents, and nothing else. A rig: 1 root, 2 hips, 3 spine, 4 neck,
-- 5 left upleg, 6 left leg, 7 left foot, 8 right upleg, 9 right leg, 10 right
-- foot, 11 right toe (child of 10).
local parents = {[2] = 1, [3] = 2, [4] = 3, [5] = 2, [6] = 5, [7] = 6, [8] = 2, [9] = 8, [10] = 9, [11] = 10}
local legs = Mirror.leg_indices(11, function(i) return parents[i] end, {[5] = true, [8] = true})
for _, i in ipairs({5, 6, 7, 8, 9, 10, 11}) do assert(legs[i], 'leg joint ' .. i) end
for _, i in ipairs({1, 2, 3, 4}) do assert(not legs[i], 'not a leg joint ' .. i) end
assert(next(Mirror.leg_indices(11, function(i) return parents[i] end, {})) == nil, 'no roots, no legs')
assert(next(Mirror.leg_indices(nil, nil, nil)) == nil, 'bad input, no legs')
-- A cycle in the lookup cannot hang it.
assert(next(Mirror.leg_indices(3, function(i) return i end, {[9] = true})) == nil, 'a self-parent terminates')

-- HELPERS ARE DECLARED BEFORE THEY ARE USED. Inside `install` the api
-- functions and the helpers are locals of one scope, in source order; a
-- helper called from a function defined above its `local function` line
-- resolves to a nil GLOBAL and throws when that function first runs. On
-- 19 September (12:52) that took the module down at ready and the worn
-- session looked at the stock fallback instead of the copy. For each
-- helper, the first line that calls it must come after a line that
-- declares it (`local name` or `local name,` or `local function name`).
local function first_line_matching(text, pattern)
  local at = text:find(pattern)
  if not at then return nil end
  return select(2, text:sub(1, at):gsub('\n', '')) + 1
end
for _, helper in ipairs({'log_once', 'array', 'vector', 'inverse', 'set_world_rotation', 'aim_joint',
    'apply_arm_scales', 'destroy_own', 'body_proxy', 'smooth_offset', 'assign_machine',
    'collect_children', 'measure_children'}) do
  local declared = first_line_matching(source, '\n%s*local%s+' .. helper .. '[%s,=]') or
    first_line_matching(source, '\n%s*local%s+function%s+' .. helper .. '%(') or
    first_line_matching(source, '\n%s*local%s+[%w_,%s]*,%s*' .. helper .. '[%s,=]')
  -- The first CALL: the name followed by "(", not preceded by "function ".
  local used
  for pos, line in (('\n' .. source):gmatch('()([^\n]*)')) do
    if line:find('%f[%w_]' .. helper .. '%(') and not line:find('function%s+' .. helper .. '%(') then
      used = select(2, ('\n' .. source):sub(1, pos):gsub('\n', '')); break
    end
  end
  assert(declared, helper .. ' is never declared')
  assert(used, helper .. ' is never called')
  assert(declared < used, helper .. ' is called at line ' .. used .. ' before its declaration at line ' .. declared)
end

-- The copy is posed by its own named joints. It draws when it has them all,
-- whatever the avatar's rig looks like.
local full = {}
for _, name in ipairs(Mirror.SOLVE_JOINTS) do full[name] = true end
assert(Mirror.has_solve_joints(function(name) return full[name] end), 'every solve joint present')
for _, missing in ipairs({'j_hips', 'j_neck', 'j_leftforearm', 'j_righthand'}) do
  assert(not Mirror.has_solve_joints(function(name) return name ~= missing and full[name] end), missing .. ' missing')
end
assert(not Mirror.has_solve_joints(nil), 'no lookup, no rig')
assert(not Mirror.has_solve_joints(function() return nil end), 'a lookup answering nil is not true')

-- WHEN THE COPY IS POSED (19 September, 14:36 worn run). In the locomotion
-- post_update, after post.body_ik has refreshed the frame's body anchor: the
-- same frame's anchor the camera and the weapon take. Posed before the world
-- update (13:38-14:36) it stood on the previous frame's anchor, a step
-- behind the view on alternate frames. Nothing is restored at the render
-- boundary, and no WorldManager hook poses it. Source scans, on both files.
assert(not source:find('restore_all', 1, true), 'the render-boundary restore is withdrawn')
assert(not source:find('function api.run_scheduled', 1, true), 'no deferred pose')
assert(source:find('state.posed_eye = posed_eye', 1, true), 'the eye the pose is built on is kept for the render check')
assert(source:find('render_eye_lag=%d/%d', 1, true), 'the render check reports the eye lag')
local main_path = arg[1]:gsub('darktidevr_body_mirror%.lua$', 'darktidevr.lua')
local main_file = assert(io.open(main_path, 'rb')); local main = main_file:read('*a'); main_file:close()
local post_at = main:find('"post_update",', 1, true)
assert(post_at, 'the locomotion post_update hook')
local post_end = main:find('\nmod:hook', post_at, true) or #main
local post_hook = main:sub(post_at, post_end)
local ik_at = post_hook:find('"post.body_ik"', 1, true)
local pose_at = post_hook:find('presentation.body_mirror.update, self._world, player_unit, dt, t', 1, true)
assert(ik_at and pose_at and ik_at < pose_at, 'post_update poses the copy after the body IK refreshed the anchor')
assert(not main:find('mod:hook(require("scripts/foundation/managers/world/world_manager"), "update"', 1, true),
  'no WorldManager.update hook poses the copy')

print('body_mirror=pass keeps_slot same_layout modes hides_slot elbow near_eye hand_rig neck_offset scale_ratio clavicles yaw_trace colliders torso_yaw draws_body turn_leak step_m solve_joints separation height_stretch standing_hips')
