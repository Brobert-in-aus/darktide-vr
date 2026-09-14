-- Geometry only. Inputs are numeric {x,y,z} / {x,y,z,w} arrays in one space.
-- The caller owns weapon sockets, tracking identity and the grip gesture.
local Pose={}
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function valid(v,n)
    if type(v)~='table' then return false end
    for i=1,n do if not finite(v[i]) then return false end end
    return true
end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
local function normalize(v,n)
    if not valid(v,n) then return nil end
    local norm=0
    for i=1,n do norm=norm+v[i]*v[i] end
    if not finite(norm) or norm<1e-12 then return nil end
    norm=math.sqrt(norm)
    local out={}
    for i=1,n do out[i]=v[i]/norm end
    return out
end
local function multiply(a,b)
    return {a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],
        a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],
        a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],
        a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}
end
local function inverse(q) return {-q[1],-q[2],-q[3],q[4]} end
local function rotate(q,v)
    local out=multiply(multiply(q,{v[1],v[2],v[3],0}),inverse(q))
    return {out[1],out[2],out[3]}
end
local function difference(a,b) return {a[1]-b[1],a[2]-b[2],a[3]-b[3]} end
local function slerp(a,b,t)
    local d=dot(a,b)+a[4]*b[4]
    if d<0 then b={-b[1],-b[2],-b[3],-b[4]}; d=-d end
    d=math.min(1,d)
    local x,y=1-t,t
    if d<0.999999 then
        local theta=math.acos(d)
        x,y=math.sin((1-t)*theta)/math.sin(theta),math.sin(t*theta)/math.sin(theta)
    end
    return normalize({x*a[1]+y*b[1],x*a[2]+y*b[2],x*a[3]+y*b[3],x*a[4]+y*b[4]},4)
end
function Pose.near(rotation,primary,support,socket,radius)
    local q=normalize(rotation,4)
    if not q or not valid(primary,3) or not valid(support,3) or
        not valid(socket,3) or not finite(radius) or radius<0 then return false end
    local local_hand=rotate(inverse(q),difference(support,primary))
    local offset=difference(local_hand,socket)
    local distance_squared,limit=dot(offset,offset),radius*radius
    return finite(distance_squared) and finite(limit) and distance_squared<=limit
end
function Pose.socket(rotation,primary,support)
    local q=normalize(rotation,4)
    if not q or not valid(primary,3) or not valid(support,3) then return nil end
    local offset=rotate(inverse(q),difference(support,primary))
    local length=dot(offset,offset)
    if not finite(length) or length<.0064 or length>1 then return nil end
    return offset
end
-- The weapon's authored support grip: where the stock animation holds the left
-- hand, expressed like a calibrated socket (support offset from the primary
-- grip in the gun's aim frame) with the hand's rotation in that frame.
-- attach_* is the rig's weapon attach node (at the primary grip), left_* its
-- left hand, muzzle_in_attach the weapon's fixed attach-to-muzzle rotation
-- (the aim frame is the muzzle's). nil for implausible hands: too close or far,
-- behind the grip, or well off the barrel line (a one-handed weapon's idle hand).
Pose.AUTHORED_LIMITS={min_forward=.08,max_length=.9,max_lateral=.25,max_vertical=.3}
function Pose.authored_socket(attach_position,attach_rotation,left_position,left_rotation,muzzle_in_attach)
    local attach,muzzle=normalize(attach_rotation,4),normalize(muzzle_in_attach,4)
    local left=normalize(left_rotation,4)
    if not attach or not muzzle or not left or not valid(attach_position,3) or
        not valid(left_position,3) then return nil end
    local in_attach=rotate(inverse(attach),difference(left_position,attach_position))
    local socket=rotate(inverse(muzzle),in_attach)
    local limits=Pose.AUTHORED_LIMITS
    local length=math.sqrt(dot(socket,socket))
    if not finite(length) or length<.08 or length>limits.max_length or socket[2]<limits.min_forward or
        math.abs(socket[1])>limits.max_lateral or math.abs(socket[3])>limits.max_vertical then return nil end
    local hand=normalize(multiply(inverse(muzzle),multiply(inverse(attach),left)),4)
    return socket,hand
end
-- Running mean of authored sockets for one weapon; the hand rotation is the
-- latest sample's (the animation keeps it steady on the grip).
function Pose.new_authored_average(samples)
    local state={count=0,sum={0,0,0},done=nil}
    function state.add(socket,hand)
        if state.done then return state.done end
        state.count=state.count+1
        for i=1,3 do state.sum[i]=state.sum[i]+socket[i] end
        state.hand=hand
        if state.count>=samples then
            state.done={socket={state.sum[1]/state.count,state.sum[2]/state.count,state.sum[3]/state.count},
                hand_rotation=state.hand}
        end
        return state.done
    end
    return state
end
-- Settle detector: the first moment the authored hand has stayed on the
-- weapon for `frames` consecutive samples within `tolerance` metres of their
-- mean. Usually reached while the draw animation is ending, so a grip is
-- ready when the weapon is. reset() on a rejected sample.
function Pose.new_authored_settle(frames,tolerance)
    local state={}
    local recent,next_slot,filled={},1,0
    function state.reset() next_slot,filled=1,0 end
    function state.add(socket,hand)
        recent[next_slot]=socket
        next_slot=next_slot%frames+1
        filled=math.min(filled+1,frames)
        if filled<frames then return nil end
        local mean={0,0,0}
        for i=1,frames do for axis=1,3 do mean[axis]=mean[axis]+recent[i][axis]/frames end end
        for i=1,frames do
            local d=difference(recent[i],mean)
            if dot(d,d)>tolerance*tolerance then return nil end
        end
        return {socket=mean,hand_rotation=hand}
    end
    return state
end
function Pose.relative_rotation(base,rotation)
    local a,b=normalize(base,4),normalize(rotation,4)
    return a and b and normalize(multiply(inverse(a),b),4) or nil
end
function Pose.hand(rotation,primary,socket,relative_rotation)
    local q,hand=normalize(rotation,4),normalize(relative_rotation,4)
    if not q or not hand or not valid(primary,3) or not valid(socket,3) then return nil end
    local offset=rotate(q,socket)
    return {primary[1]+offset[1],primary[2]+offset[2],primary[3]+offset[3]},
        normalize(multiply(q,hand),4)
end
function Pose.correction(rotation,primary,support,socket)
    local q=normalize(rotation,4)
    if not q or not valid(primary,3) or not valid(support,3) or not valid(socket,3) then return nil end
    local line=difference(support,primary)
    -- Near-coincident hands do not define a stable pointing direction. Refuse
    -- the ambiguous reverse direction instead of inventing a 180-degree roll.
    if dot(line,line)<0.0064 or dot(socket,socket)<0.0064 then return nil end
    local from,to=normalize(socket,3),normalize(rotate(inverse(q),line),3)
    if not from or not to then return nil end
    local d=dot(from,to)
    if d< -0.95 then return nil end
    return normalize({from[2]*to[3]-from[3]*to[2],from[3]*to[1]-from[1]*to[3],
        from[1]*to[2]-from[2]*to[1],1+d},4)
end
-- Also returns the stock's blend weight (0 when not in contact) and the
-- butt-to-anchor distance (nil without a usable stock).
function Pose.stock_correction(rotation,primary,support,socket,stock)
    local correction=Pose.correction(rotation,primary,support,socket)
    if not correction or type(stock)~='table' or not valid(stock.anchor,3) or
        not valid(stock.offset,3) or not finite(stock.radius) or stock.radius<=0 or stock.radius>.5 or
        not finite(stock.strength) or stock.strength<=0 or stock.strength>1 or
        dot(stock.offset,stock.offset)>1 then return correction,0 end
    local q=normalize(rotation,4)
    local placed=rotate(multiply(q,correction),stock.offset)
    local delta={primary[1]+placed[1]-stock.anchor[1],primary[2]+placed[2]-stock.anchor[2],
        primary[3]+placed[3]-stock.anchor[3]}
    local distance=math.sqrt(dot(delta,delta))
    if not finite(distance) then return correction,0 end
    if distance>=stock.radius then return correction,0,distance end
    local stock_ray=difference(socket,stock.offset)
    local shouldered=Pose.correction(q,stock.anchor,support,stock_ray)
    if not shouldered then return correction,0,distance end
    -- The caller supplies a stable body/shoulder anchor. No headset yaw is
    -- used here, and the primary grip position is never moved to the shoulder.
    local proximity=1-distance/stock.radius
    local weight=stock.strength*proximity*proximity
    return slerp(correction,shouldered,weight),weight,distance
end
function Pose.stock_profile(profile)
    if type(profile)~='table' or not valid(profile.shoulder,3) or not valid(profile.offset,3) or
        dot(profile.shoulder,profile.shoulder)>9 or dot(profile.offset,profile.offset)>1 or
        not finite(profile.radius) or profile.radius<=0 or profile.radius>.5 or
        not finite(profile.strength) or profile.strength<=0 or profile.strength>1 then return nil end
    return {shoulder={unpack(profile.shoulder,1,3)},offset={unpack(profile.offset,1,3)},
        radius=profile.radius,strength=profile.strength}
end
function Pose.new_stock_anchor()
    local state={owner=nil,relative_yaw=nil}
    function state.reset() state.owner=nil; state.relative_yaw=nil end
    function state.update(frame,socket,profile,held,owner)
        if not held or not owner or not profile or not valid(frame.body_position,3) or
            not finite(frame.scene_yaw) or not finite(frame.body_yaw) then state.reset(); return nil end
        if state.owner~=owner then state.reset() end
        -- Avatar yaw is sampled only when contact starts. During contact the
        -- anchor turns with the scene (stick turning), never head-only yaw.
        local relative=state.relative_yaw or frame.body_yaw-frame.scene_yaw
        local yaw=frame.scene_yaw+relative
        local q={0,0,math.sin(yaw*.5),math.cos(yaw*.5)}
        local offset=rotate(q,profile.shoulder)
        local anchor={frame.body_position[1]+offset[1],frame.body_position[2]+offset[2],
            frame.body_position[3]+offset[3]}
        local correction=Pose.correction(frame.rotation,frame.primary,frame.support,socket)
        local base=normalize(frame.rotation,4)
        if not correction or not base then state.reset(); return nil end
        local stock_point=rotate(multiply(base,correction),profile.offset)
        local delta={frame.primary[1]+stock_point[1]-anchor[1],frame.primary[2]+stock_point[2]-anchor[2],
            frame.primary[3]+stock_point[3]-anchor[3]}
        local distance=dot(delta,delta)
        if not finite(distance) or distance>=profile.radius*profile.radius then state.reset(); return nil end
        state.owner=owner; state.relative_yaw=relative
        return {anchor=anchor,offset=profile.offset,radius=profile.radius,strength=profile.strength}
    end
    return state
end
-- One Euro filter (Casiez et al.) on a 3-vector: little smoothing while the
-- value moves fast, more while it is nearly still. Cutoffs in hertz, beta per
-- unit of speed (metres per second for a hands line).
function Pose.new_one_euro(min_cutoff,beta,derivative_cutoff)
    local state={min_cutoff=min_cutoff}
    local function alpha(cutoff,dt) return 1/(1+1/(2*math.pi*cutoff*dt)) end
    function state.reset() state.value=nil; state.speed=nil end
    function state.filter(value,dt)
        if not valid(value,3) then return nil end
        if not state.value then
            state.value={value[1],value[2],value[3]}; state.speed={0,0,0}
            return state.value
        end
        if not finite(dt) or dt<=0 then return state.value end
        local d=alpha(derivative_cutoff,dt)
        local speed=0
        for i=1,3 do
            state.speed[i]=state.speed[i]+d*((value[i]-state.value[i])/dt-state.speed[i])
            speed=speed+state.speed[i]*state.speed[i]
        end
        local a=alpha(state.min_cutoff+beta*math.sqrt(speed),dt)
        for i=1,3 do state.value[i]=state.value[i]+a*(value[i]-state.value[i]) end
        return state.value
    end
    return state
end
-- Hands-line steadying (two-hand aim design, 15 September): the line from the
-- dominant grip to the support hand is filtered in tracking space (the scene
-- basis removed, so stick turns and walking are never delayed) and the swing
-- is recomputed from the current dominant rotation every frame, so turning
-- the wrist cannot carry the barrel off the support hand.
Pose.HANDS_LINE_BETA=20
Pose.HANDS_LINE_DERIVATIVE_CUTOFF=1
function Pose.new()
    local state={correction={0,0,0,1},owner=nil,engaged=0}
    local line=Pose.new_one_euro(1,Pose.HANDS_LINE_BETA,Pose.HANDS_LINE_DERIVATIVE_CUTOFF)
    function state.reset()
        state.correction={0,0,0,1}; state.owner=nil; state.engaged=0; line.reset()
    end
    function state.apply(rotation)
        local q=normalize(rotation,4)
        return q and normalize(multiply(q,state.correction),4) or nil
    end
    -- steady: nil for the classic filter, or {mode='hands_line', scene=quaternion or nil}.
    function state.update(rotation,primary,support,socket,held,owner,dt,smoothing,cancelled,stock,steady)
        local q=normalize(rotation,4)
        if not q then state.reset(); return nil end
        if cancelled or owner==nil or not finite(dt) or dt<0 or dt>0.25 or
            not finite(smoothing) or smoothing<0 then state.reset(); return q end
        if state.owner~=owner then state.reset(); state.owner=owner end
        local weight=smoothing==0 and 1 or 1-math.exp(-dt/smoothing)
        if type(steady)=='table' and steady.mode=='hands_line' and held and
            valid(primary,3) and valid(support,3) then
            local scene=steady.scene and normalize(steady.scene,4)
            local world_line=difference(support,primary)
            local tracked=scene and rotate(inverse(scene),world_line) or world_line
            -- The classic smoothing time constant sets the resting cutoff.
            line.min_cutoff=smoothing>0 and 1/(2*math.pi*smoothing) or 1000
            local filtered=line.filter(tracked,dt)
            local back=filtered and (scene and rotate(scene,filtered) or filtered)
            local target
            if back then
                target,state.stock_weight,state.stock_distance=Pose.stock_correction(q,primary,
                    {primary[1]+back[1],primary[2]+back[2],primary[3]+back[3]},socket,stock)
            end
            if not target then state.reset(); return q end
            -- Taking hold eases in from the previous correction over the
            -- classic time constant; after that the swing is exact for this
            -- frame's wrist.
            if state.engaged==0 then state.from=state.correction end
            state.engaged=state.engaged+(1-state.engaged)*weight
            if state.engaged>.999 then state.engaged=1 end
            state.correction=state.engaged==1 and target or slerp(state.from,target,state.engaged)
            return normalize(multiply(q,state.correction),4)
        end
        line.reset(); state.engaged=0
        local target={0,0,0,1}
        state.stock_weight,state.stock_distance=0,nil
        if held then target,state.stock_weight,state.stock_distance=Pose.stock_correction(q,primary,support,socket,stock) end
        if not target then state.reset(); return q end
        -- Classic: smooth only the support correction in controller-local
        -- space. The primary controller's deliberate motion remains immediate;
        -- release blends back to its accepted one-hand orientation.
        state.correction=slerp(state.correction,target,weight)
        return normalize(multiply(q,state.correction),4)
    end
    return state
end
return Pose
