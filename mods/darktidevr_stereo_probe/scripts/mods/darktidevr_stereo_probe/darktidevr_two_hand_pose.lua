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
function Pose.new()
    local state={correction={0,0,0,1},owner=nil}
    function state.reset()
        state.correction={0,0,0,1}; state.owner=nil
    end
    function state.apply(rotation)
        local q=normalize(rotation,4)
        return q and normalize(multiply(q,state.correction),4) or nil
    end
    function state.update(rotation,primary,support,socket,held,owner,dt,smoothing,cancelled)
        local q=normalize(rotation,4)
        if not q then state.reset(); return nil end
        if cancelled or owner==nil or not finite(dt) or dt<0 or dt>0.25 or
            not finite(smoothing) or smoothing<0 then state.reset(); return q end
        if state.owner~=owner then state.reset(); state.owner=owner end
        local target={0,0,0,1}
        if held then target=Pose.correction(q,primary,support,socket) end
        if not target then state.reset(); return q end
        -- Smooth only the support correction in controller-local space. The
        -- primary controller's deliberate motion remains immediate; release
        -- blends back to its accepted one-hand orientation.
        local weight=smoothing==0 and 1 or 1-math.exp(-dt/smoothing)
        state.correction=slerp(state.correction,target,weight)
        return normalize(multiply(q,state.correction),4)
    end
    return state
end
return Pose
