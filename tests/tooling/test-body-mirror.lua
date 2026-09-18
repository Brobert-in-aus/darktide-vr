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
assert(Mirror.MODES.overlay.follow_neck and not Mirror.MODES.overlayarms.follow_neck)
local off,len=Mirror.neck_offset({0,0.16,1.45},{0,-0.07,1.69},true)
assert(near(off[2],-0.23) and near(off[3],0.24) and near(len,math.sqrt(0.23^2+0.24^2)),'moves neck onto target')
off=Mirror.neck_offset({0,0.16,1.45},{0,-0.07,1.69})
assert(near(off[2],-0.23) and off[3]==0,'never lifts by default')
off=Mirror.neck_offset({0,0,1.45},{0,0,1.20})
assert(near(off[3],-0.25),'lowers for a crouch')
off,len=Mirror.neck_offset({0,0,0},{0,0,2},true)
assert(near(off[3],Mirror.NECK_FOLLOW_MAX) and near(len,2),'capped')
assert(Mirror.MODES.overlay.scale_to_neck and not Mirror.MODES.overlayfollow.scale_to_neck and Mirror.MODES.overlayfollow.follow_neck)
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
    assert(Mirror.MODES.overlayarmlength.arm_length and not Mirror.MODES.overlay.arm_length,'arm length A/B mode')
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
assert(reflection.reflect and reflection.solve_arms and reflection.follow_neck and reflection.scale_to_neck and
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

print('body_mirror=pass keeps_slot same_layout modes hides_slot elbow near_eye hand_rig neck_offset scale_ratio clavicles yaw_trace colliders')
