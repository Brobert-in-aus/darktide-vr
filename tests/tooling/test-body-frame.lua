local BodyFrame=dofile(assert(arg[1]))
local function near(a,b,tol,m) assert(math.abs(a-b)<(tol or 1e-6),(m or 'mismatch')..': '..tostring(a)..' vs '..tostring(b)) end
local function dir(yaw,pitch)
    pitch=pitch or 0
    return {-math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch)}
end
local function up_for(yaw,pitch) return dir(yaw,(pitch or 0)+math.pi/2) end
local eye={2,3,1.62}
-- Head yaw, including straight down and up without a flip.
near(BodyFrame.head_yaw(dir(.4),up_for(.4)),.4,1e-9,'level')
near(BodyFrame.head_yaw(dir(.4,-1.55),up_for(.4,-1.55)),.4,1e-6,'looking down')
near(BodyFrame.head_yaw(dir(.4,1.55),up_for(.4,1.55)),.4,1e-6,'looking up')
-- Hands in front pull the yaw 0.7 of the way, capped at 60 degrees.
local function hand(yaw,dist) local d=dir(yaw) return {eye[1]+d[1]*dist,eye[2]+d[2]*dist,1.2} end
near(BodyFrame.target_yaw(0,eye,{hand(.3,.5),hand(.3,.5)}),.21,1e-6,'hand bias')
near(BodyFrame.target_yaw(0,eye,{hand(1.2,.5)}),.84,1e-6,'wide hand')
near(BodyFrame.target_yaw(0,eye,{hand(1.4,.5)}),0,1e-9,'hand at the side is not in front')
near(BodyFrame.target_yaw(0,eye,{hand(math.pi,.5)}),0,1e-9,'hands behind ignored')
near(BodyFrame.target_yaw(0,eye,{{eye[1]+.05,eye[2],1.2}}),0,1e-9,'hand at the body ignored')
-- A head glance within the dead zone leaves the body where it was.
local frame=BodyFrame.new()
local function step(head_yaw,hands,dt) return assert(frame.update({eye=eye,head_forward=dir(head_yaw),head_up=up_for(head_yaw),hands=hands,eye_height=1.62},dt)) end
local f=step(0,nil,1/90)
near(f.yaw,0,1e-9,'starts at head yaw')
for _=1,90 do f=step(math.rad(18),nil,1/90) end
near(f.yaw,0,1e-9,'18 degree glance held')
-- A 40 degree turn: the body follows within about half a second.
for _=1,45 do f=step(math.rad(40),nil,1/90) end
assert(math.abs(f.yaw-math.rad(40))<math.rad(2),'body followed the turn: '..math.deg(f.yaw))
-- Glancing 40 degrees while both hands hold a gun forward keeps the body within 20 degrees.
frame.reset()
local gun={hand(0,.45),hand(0,.6)}
f=step(0,gun,1/90)
for _=1,90 do f=step(math.rad(40),gun,1/90) end
assert(math.abs(f.yaw)<math.rad(20),'hands anchor the body during a glance: '..math.deg(f.yaw))
-- Neck and shoulders: 7 cm back, 8 cm down, 17 cm either side, scaled.
frame.reset()
f=step(0,nil,1/90)
near(f.neck[1],2,1e-9); near(f.neck[2],3-.07,1e-9,'neck back'); near(f.neck[3],1.62-.08,1e-9,'neck down')
near(f.shoulder_right[1],2.17,1e-9,'right shoulder side'); near(f.shoulder_left[1],1.83,1e-9,'left shoulder side')
near(f.shoulder_right[3],1.62-.16,1e-9,'shoulder height')
frame.reset()
f=assert(frame.update({eye=eye,head_forward=dir(math.pi/2),head_up=up_for(math.pi/2),eye_height=1.215},1/90))
near(f.scale,.75,1e-9,'scale')
near(f.shoulder_right[2],3+.17*.75,1e-9,'right shoulder turns with the body (yaw 90: right is +y)')
-- Invalid input resets.
assert(frame.update({eye={0/0,0,0},head_forward=dir(0),head_up=up_for(0)},1/90)==nil and frame.yaw==nil)
print('body_frame=pass head_yaw pitch_safe hand_bias dead_zone turn glance shoulders scale invalid')
