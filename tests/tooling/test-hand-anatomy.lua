local file = assert(io.open(arg[1], 'r'))
local source = file:read('*all'); file:close()
local first = assert(source:find('local function inverse_quaternion(', 1, true))
local last = assert(source:find('\nlocal function copy_gameplay_fingers(', first, true))
local mt = {}
local function v(x,y,z) return setmetatable({x,y,z},mt) end
mt.__sub=function(a,b) return v(a[1]-b[1],a[2]-b[2],a[3]-b[3]) end
mt.__add=function(a,b) return v(a[1]+b[1],a[2]+b[2],a[3]+b[3]) end
mt.__mul=function(a,b) return v(a[1]*b,a[2]*b,a[3]*b) end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
local function cross(a,b) return v(a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]) end
local function norm(a) return a*(1/math.sqrt(dot(a,a))) end
Vector3={normalize=norm,cross=cross,length_squared=function(a) return dot(a,a) end}
local function q(x,y,z,w) return {x,y,z,w} end
local function multiply(a,b)
    local av,bv=v(a[1],a[2],a[3]),v(b[1],b[2],b[3])
    local xyz=av*b[4]+bv*a[4]+cross(av,bv)
    return q(xyz[1],xyz[2],xyz[3],a[4]*b[4]-dot(av,bv))
end
local function rotate(a,b)
    local r=multiply(multiply(a,q(b[1],b[2],b[3],0)),q(-a[1],-a[2],-a[3],a[4]))
    return v(r[1],r[2],r[3])
end
local function look(forward,up)
    local y=norm(forward); local x=norm(cross(y,up)); local z=cross(x,y)
    local m={{x[1],y[1],z[1]},{x[2],y[2],z[2]},{x[3],y[3],z[3]}}
    local trace=m[1][1]+m[2][2]+m[3][3]
    if trace>0 then
        local s=2*math.sqrt(trace+1)
        return q((m[3][2]-m[2][3])/s,(m[1][3]-m[3][1])/s,(m[2][1]-m[1][2])/s,s/4)
    end
    local i=1
    for j=2,3 do if m[j][j]>m[i][i] then i=j end end
    local j=i%3+1; local k=j%3+1
    local s=2*math.sqrt(1+m[i][i]-m[j][j]-m[k][k])
    local result={}
    result[i]=s/4; result[j]=(m[j][i]+m[i][j])/s
    result[k]=(m[k][i]+m[i][k])/s; result[4]=(m[k][j]-m[j][k])/s
    return result
end
Quaternion={to_elements=unpack,from_elements=q,multiply=multiply,rotate=rotate,look=look,
    right=function(a) return rotate(a,v(1,0,0)) end,
    forward=function(a) return rotate(a,v(0,1,0)) end}
QuaternionBox=function(a) return {unbox=function() return a end} end
Unit={has_node=function(u,n) return u[n]~=nil end,node=function(_,n) return n end,
    world_position=function(u,n) return u[n] end,world_rotation=function(u) return u.rotation end}
rigid_hands={left={},right={}}
local calibrate=assert(loadstring(source:sub(first,last-1)..'\nreturn anatomical_hand_rotation'))()
local function near(a,b)
    local d=a-b; assert(dot(d,d)<1e-16,'anatomical axis changed')
end
local function axis_rotation(axis,angle)
    local n=norm(axis)*math.sin(angle/2); return q(n[1],n[2],n[3],math.cos(angle/2))
end
local function rig(side,rotation,scale)
    local prefix='j_'..side..'hand'; local wrist=v(3,-2,5)
    -- Distinct authored wrist bases, independent of the root's world rotation.
    local longitudinal=side=='left' and v(0,0,-1) or v(0,-1,0)
    local across=side=='left' and v(-1,0,0) or v(0,0,1)
    return {rotation=rotation,[prefix]=wrist,
        [prefix..'middle1']=wrist+rotate(rotation,longitudinal)*(.06*scale),
        [prefix..'index1']=wrist+rotate(rotation,across)*(.02*scale),
        [prefix..'pinky1']=wrist-rotate(rotation,across)*(.02*scale)},longitudinal,across
end
for _,side in ipairs({'left','right'}) do
    for _,scale in ipairs({.94,1,1.08}) do
        rigid_hands[side]={}
        local unit,longitudinal,across=rig(side,axis_rotation(v(1,2,-3),1.8),scale)
        local grip=axis_rotation(v(-2,1,3),2.3)
        local result=assert(calibrate(unit,side,grip))
        -- Fingertips along -grip up; little-to-index along grip forward.
        -- The signed cross normal is -grip right for BOTH physical hands.
        near(rotate(result,longitudinal),rotate(grip,v(0,0,-1)))
        near(rotate(result,across),rotate(grip,v(0,1,0)))
        near(rotate(result,cross(across,longitudinal)),rotate(grip,v(-1,0,0)))
        local saved=rigid_hands[side].anatomy_inverse
        unit['j_'..side..'handmiddle1']=unit['j_'..side..'hand'] -- Later curled/animated pose.
        local next_grip=axis_rotation(v(3,1,-2),-1.1)
        result=assert(calibrate(unit,side,next_grip))
        near(rotate(result,longitudinal),rotate(next_grip,v(0,0,-1)))
        assert(rigid_hands[side].anatomy_inverse==saved,'finger animation recalibrated the wrist')
    end
    for _,invalid in ipairs({'missing','zero_length','zero_width','parallel','nonfinite'}) do
        rigid_hands[side]={}
        local unit=rig(side,q(0,0,0,1),1); local prefix='j_'..side..'hand'
        if invalid=='missing' then unit[prefix..'middle1']=nil
        elseif invalid=='zero_length' then unit[prefix..'middle1']=unit[prefix]
        elseif invalid=='zero_width' then unit[prefix..'index1']=unit[prefix..'pinky1']
        elseif invalid=='parallel' then
            unit[prefix..'index1']=unit[prefix..'middle1']; unit[prefix..'pinky1']=unit[prefix]
        else unit[prefix..'middle1']=v(0/0,math.huge,0) end
        assert(calibrate(unit,side,q(0,0,0,1))==nil,'invalid '..invalid..' anatomy must wait for a usable pose')
        assert(rigid_hands[side].anatomy_inverse==nil,'invalid anatomy poisoned the calibration cache')
        assert(calibrate(rig(side,q(0,0,0,1),1),side,q(0,0,0,1)),'calibration did not recover')
    end
end
-- Stock-animation placement must also wait for initial calibration before
-- copying animated fingers over the source anatomy needed for the retry.
anatomical_hand_rotation=calibrate
Unit.alive=function() return true end
copy_gameplay_fingers=function() error('uncalibrated pose imported animated fingers') end
local place_first=assert(source:find('local function place_rigid_hand(',1,true))
local place_last=assert(source:find('\nlocal function spawn(',place_first,true))
local place=assert(loadstring(source:sub(place_first,place_last-1)..'\nreturn place_rigid_hand'))()
for _,side in ipairs({'left','right'}) do
    rigid_hands[side]={}
    local unit=rig(side,q(0,0,0,1),1)
    unit['j_'..side..'handmiddle1']=unit['j_'..side..'hand']
    for _,authored in ipairs({false,true}) do
        assert(place({}, {side=side,unit=unit,ready=true},v(0,0,0),q(0,0,0,1),authored)==false)
        assert(rigid_hands[side].anatomy_inverse==nil)
    end
end
print('both anatomical bases preserve physical grip axes, cache valid anatomy and retry invalid poses')
