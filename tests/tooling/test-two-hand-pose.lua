local Pose=dofile(assert(arg[1]))
local identity={0,0,0,1}
local primary,socket={3,4,5},{0,.3,0}
local function near(a,b,tolerance)
    for i=1,#a do assert(math.abs(a[i]-b[i])<(tolerance or 1e-8),'pose component mismatch') end
end
local function rotated_y(q)
    return {2*(q[1]*q[2]-q[3]*q[4]),1-2*(q[1]^2+q[3]^2),2*(q[2]*q[3]+q[1]*q[4])}
end
assert(Pose.near(identity,primary,{3,4.3,5},socket,.01))
assert(not Pose.near(identity,primary,{3,4.45,5},socket,.1))
assert(Pose.near(identity,primary,{3,4.45,5},socket,.2))
local state,owner=Pose.new(),{}
local q=state.update(identity,primary,{3.3,4,5},socket,true,owner,.01,0)
near(rotated_y(q),{1,0,0})
-- Controller distance cannot scale the gun: orientation is unchanged when
-- the support hand moves farther along the same line.
near(state.update(identity,primary,{3.6,4,5},socket,true,owner,.01,0),q)
near(primary,{3,4,5}); near(socket,{0,.3,0})
-- Authored grip: the stock left hand relative to the weapon attach node, in
-- the aim (muzzle) frame, independent of where the rig stands and faces.
do
    local yaw=math.rad(70)
    local turn={0,0,math.sin(yaw/2),math.cos(yaw/2)}
    local function rot(q,v)
        local x,y,z,w=q[1],q[2],q[3],q[4]
        local ix,iy,iz,iw=w*v[1]+y*v[3]-z*v[2], w*v[2]+z*v[1]-x*v[3], w*v[3]+x*v[2]-y*v[1], -x*v[1]-y*v[2]-z*v[3]
        return {ix*w+iw*-x+iy*-z-iz*-y, iy*w+iw*-y+iz*-x-ix*-z, iz*w+iw*-z+ix*-y-iy*-x}
    end
    local attach_position={10,20,1.5}
    -- Muzzle = attach here; left hand 35 cm forward, 3 cm left, 4 cm down.
    local offset={-.03,.35,-.04}
    local world_offset=rot(turn,offset)
    local left_position={attach_position[1]+world_offset[1],attach_position[2]+world_offset[2],attach_position[3]+world_offset[3]}
    local left_rotation={0,0,0,1}
    local s,h=Pose.authored_socket(attach_position,turn,left_position,turn,identity)
    assert(s,'authored socket rejected')
    near(s,offset,1e-6)
    near(h,identity,1e-6)
    -- A muzzle rotated in the attach frame re-expresses the offset in the aim frame.
    local roll={math.sin(math.rad(15)),0,0,math.cos(math.rad(15))}
    local s2=Pose.authored_socket(attach_position,turn,left_position,turn,roll)
    assert(s2 and math.abs(math.sqrt(s2[1]^2+s2[2]^2+s2[3]^2)-math.sqrt(offset[1]^2+offset[2]^2+offset[3]^2))<1e-6)
    -- One-handed idle hands and implausible positions are rejected.
    local function at(o) local w=rot(turn,o); return {attach_position[1]+w[1],attach_position[2]+w[2],attach_position[3]+w[3]} end
    assert(not Pose.authored_socket(attach_position,turn,at({-.3,.05,-.3}),left_rotation,identity),'hanging hand accepted')
    assert(not Pose.authored_socket(attach_position,turn,at({0,-.2,0}),left_rotation,identity),'hand behind the grip accepted')
    assert(not Pose.authored_socket(attach_position,turn,at({0,.03,0}),left_rotation,identity),'hand on the grip accepted')
    assert(not Pose.authored_socket(attach_position,turn,at({0,1.2,0}),left_rotation,identity),'hand beyond reach accepted')
    assert(not Pose.authored_socket(attach_position,nil,left_position,left_rotation,identity))
    -- Averaging: frozen after N samples.
    local average=Pose.new_authored_average(3)
    assert(not average.add({0,.3,0},identity) and not average.add({0,.4,0},identity))
    local done=average.add({0,.5,0},identity)
    near(done.socket,{0,.4,0},1e-9)
    assert(average.add({0,9,0},identity)==done,'average changed after freezing')
end
-- A common translation/rotation of both hands and the aim preserves the solution.
local quarter={0,0,math.sqrt(.5),math.sqrt(.5)}
local turned=Pose.new().update(quarter,{8,9,2},{8,9.3,2},socket,true,owner,.01,0)
near(rotated_y(turned),{0,1,0})
assert(Pose.near(quarter,{8,9,2},{7.7,9,2},socket,.01))
near(Pose.socket(quarter,{8,9,2},{7.7,9,2}),socket)
local hand_position,hand_rotation=Pose.hand(quarter,{8,9,2},socket,identity)
near(hand_position,{7.7,9,2}); near(hand_rotation,quarter)
near(Pose.relative_rotation(quarter,quarter),identity)
local _,captured_hand=Pose.hand(quarter,{0,0,0},socket,Pose.relative_rotation(quarter,identity))
near(captured_hand,identity)
assert(Pose.socket(identity,primary,primary)==nil)
assert(Pose.socket(identity,primary,{30,4,5})==nil)
-- Aligned support retains primary wrist roll; no up-vector/horizon lock.
local roll={0,math.sin(.4),0,math.cos(.4)}
near(Pose.new().update(roll,primary,{3,4.3,5},socket,true,owner,.01,0),roll)
local reference
for _,fps in ipairs({30,60,90,120}) do
    local filter=Pose.new()
    local result
    for frame=1,fps do
        result=filter.update(identity,primary,{3.3,4,5},socket,true,owner,1/fps,.2)
    end
    if reference then near(result,reference,1e-6) else reference=result end
    -- A complete second of release has the same decay at each update rate.
    for frame=1,fps do result=filter.update(identity,nil,nil,nil,false,owner,1/fps,.2) end
    assert(math.abs(result[3])<.006,'release did not return to one-hand aim')
end
-- Invalid tracking/geometry cannot preserve a stale two-hand correction.
for _,invalid in ipairs({primary,{3,3.7,5},{0/0,4,5},{math.huge,4,5}}) do
    state.update(identity,primary,{3.3,4,5},socket,true,owner,.01,0)
    near(state.update(identity,primary,invalid,socket,true,owner,.01,.2),identity)
    assert(state.owner==nil)
end
state.update(identity,primary,{3.3,4,5},socket,true,owner,.01,0)
near(state.update(identity,primary,{3.3,4,5},socket,true,{},0,.2),identity)
state.update(identity,primary,{3.3,4,5},socket,true,owner,.01,0)
near(state.update(identity,primary,{3.3,4,5},socket,true,owner,.01,.2,true),identity)
for _,dt in ipairs({-.1,.5,math.huge,0/0}) do
    near(state.update(identity,primary,{3.3,4,5},socket,true,owner,dt,.2),identity)
end
assert(state.update({0,0,0,0},primary,{3.3,4,5},socket,true,owner,.01,.2)==nil)
assert(not Pose.near(identity,primary,primary,socket,0/0))
assert(not Pose.near(identity,primary,primary,socket,-1))
assert(not Pose.near(identity,primary,{1e308,1e308,1e308},socket,1e308))
-- Off-axis authored sockets must steer the actual socket ray, not silently
-- assume every support grip sits on the barrel's forward axis.
local function rotate(q,v)
    return {
        (1-2*(q[2]^2+q[3]^2))*v[1]+2*(q[1]*q[2]-q[3]*q[4])*v[2]+2*(q[1]*q[3]+q[2]*q[4])*v[3],
        2*(q[1]*q[2]+q[3]*q[4])*v[1]+(1-2*(q[1]^2+q[3]^2))*v[2]+2*(q[2]*q[3]-q[1]*q[4])*v[3],
        2*(q[1]*q[3]-q[2]*q[4])*v[1]+2*(q[2]*q[3]+q[1]*q[4])*v[2]+(1-2*(q[1]^2+q[2]^2))*v[3]}
end
for i=1,120 do
    local angle=i*.017
    local base={0,0,math.sin(angle),math.cos(angle)}
    local offset={.03*math.sin(i),.2+.001*i,-.04}
    local target_local={.08*math.cos(i),.3,.06*math.sin(i)}
    local target_world=rotate(base,target_local)
    local hand={primary[1]+target_world[1],primary[2]+target_world[2],primary[3]+target_world[3]}
    local result=Pose.new().update(base,primary,hand,offset,true,owner,.01,0)
    local socket_world=rotate(result,offset)
    local socket_length=math.sqrt(offset[1]^2+offset[2]^2+offset[3]^2)
    local target_length=math.sqrt(target_world[1]^2+target_world[2]^2+target_world[3]^2)
    for axis=1,3 do
        assert(math.abs(socket_world[axis]/socket_length-target_world[axis]/target_length)<1e-8)
    end
end
print('two_hand_pose=pass geometry roll distance covariance smoothing invalidity reset')
-- Optional virtual stock only influences aiming close to an explicit shoulder
-- anchor. It cannot translate the main grip or silently attach to the headset.
local stock={anchor={3.05,3.75,5},offset={0,-.25,0},radius=.2,strength=1}
local stock_pose=Pose.new().update(identity,primary,{3,4.3,5},socket,true,owner,.01,0,false,stock)
assert(math.abs(stock_pose[3])>0 and math.abs(stock_pose[3])<.05)
near(primary,{3,4,5})
local weaker={anchor=stock.anchor,offset=stock.offset,radius=.2,strength=.5}
local weak_pose=Pose.new().update(identity,primary,{3,4.3,5},socket,true,owner,.01,0,false,weaker)
assert(math.abs(weak_pose[3])<math.abs(stock_pose[3]))
local filter=Pose.new()
filter.update(identity,primary,{3,4.3,5},socket,true,owner,.01,0,false,stock)
near(filter.update(identity,primary,{3,4.3,5},socket,false,owner,.01,0,false,stock),identity)
for _,bad in ipairs({{anchor={30,30,30},offset={0,-.25,0},radius=.2,strength=1},
        {anchor=stock.anchor,offset=stock.offset,radius=.2,strength=0},
        {anchor={0/0,0,0},offset=stock.offset,radius=.2,strength=1},
        {anchor=stock.anchor,offset=stock.offset,radius=math.huge,strength=1}}) do
    near(Pose.new().update(identity,primary,{3,4.3,5},socket,true,owner,.01,0,false,bad),identity)
end
print('virtual_stock_pose=pass proximity strength release invalidity fixed_primary')
local anchor=Pose.new_stock_anchor()
local stock_profile=Pose.stock_profile({shoulder={.2,0,1.4},offset={0,-.25,0},radius=.2,strength=.5})
local body_frame={body_position={0,0,0},scene_yaw=0,body_yaw=0,
    rotation=identity,primary={.2,.25,1.4},support={.2,.55,1.4}}
local contact=assert(anchor.update(body_frame,socket,stock_profile,true,owner))
near(contact.anchor,{.2,0,1.4})
body_frame.body_yaw=math.pi/2
near(assert(anchor.update(body_frame,socket,stock_profile,true,owner)).anchor,{.2,0,1.4})
-- A scene turn rotates both tracking and the latched shoulder together.
body_frame.scene_yaw=math.pi/2; body_frame.rotation=quarter
body_frame.primary={-.25,.2,1.4}; body_frame.support={-.55,.2,1.4}
near(assert(anchor.update(body_frame,socket,stock_profile,true,owner)).anchor,{0,.2,1.4})
body_frame.body_position={3,4,5}
body_frame.primary={2.75,4.2,6.4}; body_frame.support={2.45,4.2,6.4}
near(assert(anchor.update(body_frame,socket,stock_profile,true,owner)).anchor,{3,4.2,6.4})
assert(not anchor.update(body_frame,socket,stock_profile,false,owner) and not anchor.owner)
-- New contact uses the current body heading, not the previous mount's latch.
body_frame.body_yaw=math.pi/2
assert(anchor.update(body_frame,socket,stock_profile,true,owner))
body_frame.primary={5,5,5}; body_frame.support={5,5.3,5}
assert(not anchor.update(body_frame,socket,stock_profile,true,owner) and not anchor.owner)
body_frame.body_position={0/0,0,0}
assert(not anchor.update(body_frame,socket,stock_profile,true,owner))
assert(not Pose.stock_profile({shoulder={0,0,0},offset={0,0,0},radius=.2,strength=0}))
assert(not Pose.stock_profile({shoulder={0,0,10},offset={0,0,0},radius=.2,strength=.5}))
print('virtual_stock_anchor=pass head_glance scene_turn translation release contact invalidity')
