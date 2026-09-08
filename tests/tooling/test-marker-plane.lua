local Plane=dofile(arg[1])
local function v(x,y,z) return {x=x,y=y,z=z} end
local function add(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
local function sub(a,b) return v(a.x-b.x,a.y-b.y,a.z-b.z) end
local function mul(a,s) return v(a.x*s,a.y*s,a.z*s) end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function length(a) return math.sqrt(dot(a,a)) end
local function check(a,b,epsilon)
    assert(math.abs(a-b) < (epsilon or 1e-8),string.format("%.12g != %.12g",a,b))
end
local function same(a,b) check(length(sub(a,b)),0,1e-7) end
local function angle(a,b)
    return math.acos(math.max(-1,math.min(1,dot(a,b)/(length(a)*length(b)))))
end
local origin,right,up=v(0,0,0),v(1,0,0),v(0,0,1)
local pivot={x=1800,y=1500}
local slope=0.000856
local function direction(yaw,pitch)
    return v(math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch))
end
local function eye(yaw,pitch,side,ipd)
    local forward=direction(yaw,pitch)
    return {position=v(side*ipd/2,0,0),forward=forward,
        right=v(math.cos(yaw),-math.sin(yaw),0),
        up=v(-math.sin(yaw)*math.sin(pitch),-math.cos(yaw)*math.sin(pitch),math.cos(pitch)),
        width=2496,height=2688,tan_horizontal=1.05,tan_vertical=1.15}
end
-- Independent inverse-ray/plane intersection checks the projection's whole
-- surface, not just its center. Samples represent corners and interior glyph,
-- bar, rotated icon and custom-logic vertices; the geometry has no pass type.
local samples={{0,0},{50,0},{-50,0},{0,50},{0,-50},{-170,83},{39,-27},{125,92}}
local cases,vertices=0,0
for _,distance in ipairs({0.5,1,3,30}) do
    for _,yaw in ipairs({-0.62,0,0.35,0.62}) do
        for _,pitch in ipairs({-0.4,0,0.4}) do
            local anchor=mul(direction(yaw,pitch),distance)
            local plane=assert(Plane.create(anchor,origin,right,up,slope,pivot))
            same(Plane.point(plane,pivot.x,pivot.y),anchor)
            check(dot(plane.x_axis,plane.normal),0)
            check(dot(plane.y_axis,plane.normal),0)
            check(dot(plane.x_axis,plane.y_axis),0)
            -- The cyclopean angular size is invariant under eccentricity and
            -- distance. Finite-IPD eyes correctly see different distances.
            check(angle(Plane.point(plane,pivot.x-50,pivot.y),
                Plane.point(plane,pivot.x+50,pivot.y)),2*math.atan(50*slope))
            check(angle(Plane.point(plane,pivot.x,pivot.y-50),
                Plane.point(plane,pivot.x,pivot.y+50)),2*math.atan(50*slope))
            for _,ipd in ipairs({0,0.064,0.075}) do
                for _,side in ipairs({-1,1}) do
                    local camera=eye(side*-0.12,0.08,side,ipd)
                    local h=assert(Plane.homography(plane,camera))
                    for _,offset in ipairs(samples) do
                        local x,y=pivot.x+offset[1],pivot.y+offset[2]
                        local px,py=Plane.project(h,x,y,0.01)
                        assert(px and py)
                        local ray=add(camera.forward,add(
                            mul(camera.right,(2*px/camera.width-1)*camera.tan_horizontal),
                            mul(camera.up,(2*py/camera.height-1)*camera.tan_vertical)))
                        local hit=add(camera.position,mul(ray,
                            dot(sub(anchor,camera.position),plane.normal)/dot(ray,plane.normal)))
                        same(hit,Plane.point(plane,x,y))
                        vertices=vertices+1
                    end
                    cases=cases+1
                end
            end
        end
    end
end
-- Genuine stereo disparity at a finite-depth anchor; no screen-space center
-- forcing. With parallel eyes the disparity has a simple independent answer.
local plane=assert(Plane.create(v(0,2,0),origin,right,up,slope,pivot))
local left,right_eye=eye(0,0,-1,0.064),eye(0,0,1,0.064)
local lx=assert(Plane.project(assert(Plane.homography(plane,left)),pivot.x,pivot.y,0.01))
local rx=assert(Plane.project(assert(Plane.homography(plane,right_eye)),pivot.x,pivot.y,0.01))
check(lx-rx,left.width/(2*left.tan_horizontal)*0.064/2)

-- An eye optical-axis rotation changes screen coordinates, but must not
-- change the physical width reconstructed from their inverse-projected rays.
-- At finite distance exact equal angular sizes would itself distort geometry.
local edge=assert(Plane.create(mul(direction(0.62,0.2),0.5),origin,right,up,slope,pivot))
local width_angles={}
for index,camera in ipairs({left,right_eye}) do
    local a=sub(Plane.point(edge,pivot.x-50,pivot.y),camera.position)
    local b=sub(Plane.point(edge,pivot.x+50,pivot.y),camera.position)
    width_angles[index]=angle(a,b)
end
assert(math.abs(width_angles[1]-width_angles[2]) > 0.0001)

-- A translated and rolled head keeps the same construction in world space.
local function transform(a) return v(a.z+12,a.y-7,-a.x+2) end
local moved=assert(Plane.create(transform(v(0,2,0)),transform(origin),
    v(0,0,-1),v(1,0,0),slope,pivot))
same(Plane.point(moved,1730,1542),transform(Plane.point(plane,1730,1542)))
for _,pole in ipairs({v(0,2,0),v(0,0,2),v(0,0,-2)}) do
    local p=assert(Plane.create(pole,origin,right,up,slope,pivot))
    check(length(p.x_axis),2*slope)
    check(dot(p.x_axis,p.y_axis),0)
end
-- Reject invalid coordinates/bases and behind/near-plane points instead of
-- letting an eye independently clamp, resize or mirror the UI.
assert(not Plane.create(origin,origin,right,up,slope,pivot))
assert(not Plane.create(v(0,1,0),origin,right,right,slope,pivot))
assert(not Plane.create(v(0,1,0),origin,right,up,0,pivot))
assert(not Plane.create(v(0,1,0),origin,right,up,0/0,pivot))
assert(not Plane.create(v(math.huge,1,0),origin,right,up,slope,pivot))
local camera=eye(0,0,0,0)
camera.forward=v(0,-1,0)
assert(not Plane.homography(plane,camera),"reject left-handed eye basis")
camera=eye(math.pi,0,0,0)
local h=assert(Plane.homography(plane,camera))
assert(not Plane.project(h,pivot.x,pivot.y,0.01))
h=assert(Plane.homography(plane,eye(0,0,0,0)))
assert(not Plane.project(h,pivot.x,pivot.y,2))
assert(not Plane.project(h,0/0,pivot.y,0.01))
print(string.format("marker_plane=pass cases=%d projected_vertices=%d",cases,vertices))
