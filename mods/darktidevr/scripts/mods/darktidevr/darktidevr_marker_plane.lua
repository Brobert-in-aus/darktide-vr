-- Geometry candidate only. No runtime hook enables this module yet.
-- Coordinates are Stingray world axes (+X right, +Y forward, +Z up), with
-- bottom-left screen pixels. A marker and all of its primitives share one
-- finite-depth plane; neither eye gets to resize that plane independently.
local Plane = {}
local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end
local function valid(v)
    return v and finite(v.x) and finite(v.y) and finite(v.z)
end
local function v(x,y,z) return {x=x,y=y,z=z} end
local function add(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
local function sub(a,b) return v(a.x-b.x,a.y-b.y,a.z-b.z) end
local function mul(a,s) return v(a.x*s,a.y*s,a.z*s) end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function cross(a,b)
    return v(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)
end
local function unit(a)
    local length=math.sqrt(dot(a,a))
    if not finite(length) or length < 1e-8 then return nil end
    return mul(a,1/length),length
end

-- tangent_per_pixel is a shared reference projection's central pixel slope,
-- e.g. 2*tan(vertical_fov/2)/height. It is not recomputed for each optical eye
-- or each marker's screen eccentricity. Preserve stock hover/distance sizing
-- in the primitive coordinates supplied to point()/homography().
function Plane.create(anchor, center, head_right, head_up, tangent_per_pixel, pivot)
    if not valid(anchor) or not valid(center) or not valid(head_right) or
            not valid(head_up) or not finite(tangent_per_pixel) or
            tangent_per_pixel <= 0 or not pivot or not finite(pivot.x) or
            not finite(pivot.y) then return nil,"invalid_input" end
    local normal,distance=unit(sub(anchor,center))
    if not normal then return nil,"zero_distance" end
    local reference_up=unit(head_up)
    local reference_right=unit(head_right)
    if not reference_up or not reference_right or
            math.abs(dot(reference_up,reference_right)) > 1e-5 then
        return nil,"invalid_head_basis"
    end
    local right=unit(cross(normal,reference_up))
    -- A marker along head-up has no unique head-up tangent. Use the head's
    -- right axis there; visibility policy must still decide whether to show it.
    if not right then
        right=unit(sub(reference_right,mul(normal,dot(reference_right,normal))))
    end
    if not right then return nil,"degenerate_basis" end
    local up=cross(right,normal)
    local scale=distance*tangent_per_pixel
    if not finite(scale) then return nil,"invalid_scale" end
    return {anchor=v(anchor.x,anchor.y,anchor.z), normal=normal,
        x_axis=mul(right,scale), y_axis=mul(up,scale), distance=distance,
        pivot={x=pivot.x,y=pivot.y}}
end

function Plane.point(plane,x,y)
    return add(plane.anchor,add(mul(plane.x_axis,x-plane.pivot.x),
        mul(plane.y_axis,y-plane.pivot.y)))
end

-- Rows map [pixel_x,pixel_y,1] to [screen_x*w,screen_y*w,w]. Keep w until
-- rasterization: transforming only a bitmap's corners or text origin and
-- keeping its old pixel dimensions is not a perspective-correct draw path.
function Plane.homography(plane,eye)
    if not eye or not valid(eye.position) or not valid(eye.right) or
            not valid(eye.up) or not valid(eye.forward) or
            not finite(eye.width) or not finite(eye.height) or
            eye.width <= 0 or eye.height <= 0 or
            not finite(eye.tan_horizontal) or not finite(eye.tan_vertical) or
            eye.tan_horizontal <= 0 or eye.tan_vertical <= 0 then
        return nil,"invalid_eye"
    end
    for _,axis in ipairs({eye.right,eye.up,eye.forward}) do
        if math.abs(dot(axis,axis)-1) > 1e-5 then return nil,"invalid_eye_basis" end
    end
    if math.abs(dot(eye.right,eye.up)) > 1e-5 or
            math.abs(dot(eye.right,eye.forward)) > 1e-5 or
            math.abs(dot(eye.up,eye.forward)) > 1e-5 or
            dot(cross(eye.right,eye.forward),eye.up) < 1-1e-5 then
        return nil,"invalid_eye_basis"
    end
    local origin=sub(Plane.point(plane,0,0),eye.position)
    local fx,fy=eye.width/(2*eye.tan_horizontal),eye.height/(2*eye.tan_vertical)
    local cx,cy=eye.width/2,eye.height/2
    local h={}
    for column,axis in ipairs({plane.x_axis,plane.y_axis,origin}) do
        local depth=dot(axis,eye.forward)
        h[column]=cx*depth+fx*dot(axis,eye.right)
        h[column+3]=cy*depth+fy*dot(axis,eye.up)
        h[column+6]=depth
    end
    for _,n in ipairs(h) do if not finite(n) then return nil,"invalid_matrix" end end
    return h
end

function Plane.project(h,x,y,near_distance)
    if not finite(x) or not finite(y) or not finite(near_distance) or
            near_distance < 0 then return nil,"invalid_input" end
    local w=h[7]*x+h[8]*y+h[9]
    if not finite(w) or w <= near_distance then return nil,"behind_near_plane" end
    local sx,sy=(h[1]*x+h[2]*y+h[3])/w,(h[4]*x+h[5]*y+h[6])/w
    if not finite(sx) or not finite(sy) then return nil,"invalid_projection" end
    return sx,sy,w
end

return Plane
