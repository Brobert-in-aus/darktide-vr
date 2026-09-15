-- Arm length from the calibration: predicted span, T-pose checks, reach, split, clamp.
local ArmLength=dofile(assert(arg[1]))
local function near(a,b,e,m) assert(math.abs(a-b)<(e or 1e-9),(m or 'mismatch')..': '..tostring(a)..' vs '..tostring(b)) end
local function has(list,id) for _,v in ipairs(list) do if v==id then return true end end return false end

-- The player's saved calibration (16 September): eye 1.725 m, span 1.506 m.
local saved={floor_eye_height=1.72487,seated=false,
    t_pose={head={0,0,0.50945},left={-0.732114,0.149433,0.372933},right={0.770146,0.0499024,0.356505}}}
near(ArmLength.predicted_span(1.72487),1.008*1.72487-0.107,1e-9,'regression')
assert(ArmLength.predicted_span(0.5)==nil and ArmLength.predicted_span(nil)==nil)
local problems=ArmLength.t_pose_problems(saved.t_pose,saved.floor_eye_height)
assert(has(problems,'short'),'the saved span is 12.6 cm short: 2.9 SD')
assert(not has(problems,'uneven') and not has(problems,'low') and not has(problems,'forward'),
    'level, above the shoulder, left grip 14.9 cm forward (under 15)')

-- A clean T-pose.
local clean={head={0,0,0.5},left={-0.82,0.02,0.33},right={0.82,0.03,0.34}}
assert(#ArmLength.t_pose_problems(clean,1.725)==0,'clean T-pose')
assert(has(ArmLength.t_pose_problems({head={0,0,0.5},left={-0.82,0,0.33},right={0.82,0,0.20}},1.725),'uneven'))
assert(has(ArmLength.t_pose_problems({head={0,0,0.5},left={-0.82,0,0.05},right={0.82,0,0.05}},1.725),'low'))
assert(has(ArmLength.t_pose_problems({head={0,0,0.5},left={-0.75,0.30,0.33},right={0.82,0,0.33}},1.725),'forward'))
assert(has(ArmLength.t_pose_problems(nil,1.725),'missing'))
-- Seated (no eye height): only the checks that do not need it.
assert(#ArmLength.t_pose_problems({head={0,0,0.5},left={-0.6,0,0.33},right={0.6,0,0.33}},nil)==0,'seated skips short and low')

-- Reach and split.
local reach=ArmLength.reach(1.64,0.36)
near(reach,(1.64-0.13-0.36)*0.5*0.97,1e-9,'reach formula')
local upper,lower=ArmLength.segments(reach)
near(upper+lower,reach); near(upper/reach,0.56)
assert(ArmLength.reach(0.3,0.36)==nil,'implausible span')
assert(ArmLength.reach(1.6,0/0)==nil)

-- From the calibration: the saved (short) span falls back to the height prediction.
local arm=ArmLength.from_calibration(saved,0.36)
assert(arm.source=='height' and has(arm.problems,'short'),'short capture uses the height prediction')
near(arm.span,ArmLength.predicted_span(1.72487))
near(arm.reach,(arm.span-0.13-0.36)*0.5*0.97,1e-9)
assert(arm.reach>0.5 and arm.reach<0.6,'about 0.55 m for a 1.84 m player')
local clean_arm=ArmLength.from_calibration({floor_eye_height=1.725,t_pose=clean},0.36)
assert(clean_arm.source=='span' and #clean_arm.problems==0)
near(clean_arm.span,math.sqrt(1.64^2+0.01^2+0.01^2),1e-9)
local seated=ArmLength.from_calibration({seated=true,floor_eye_height=1.725,t_pose={head={0,0,0.5},left={-0.6,0,0.33},right={0.6,0,0.33}}},0.36)
assert(seated.source=='span','seated with a level span uses it')
assert(ArmLength.from_calibration({seated=true,t_pose=nil},0.36).reach==nil,'nothing usable')

-- Clamp.
near(ArmLength.segment_ratio(0.30,0.34),0.30/0.34)
near(ArmLength.segment_ratio(0.20,0.34),ArmLength.MIN_RATIO)
near(ArmLength.segment_ratio(0.60,0.34),ArmLength.MAX_RATIO)
near(ArmLength.segment_ratio(0.3,0),1)
print('arm_length=pass predicted_span t_pose_checks reach split from_calibration clamp')
