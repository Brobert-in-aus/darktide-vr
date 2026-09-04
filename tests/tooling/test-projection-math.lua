-- Minimal mathematical equivalents of the engine value types; no game runs.
Vector3 = function(x, y, z) return {x=x, y=y, z=z} end
Quaternion = {}
function Quaternion.from_elements(x,y,z,w) return {x=x,y=y,z=z,w=w} end
function Quaternion.to_elements(q) return q.x,q.y,q.z,q.w end
function Quaternion.multiply(a,b)
    return Quaternion.from_elements(
        a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
        a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
        a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,
        a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z)
end
function Quaternion.rotate(q,v)
    local r=Quaternion.multiply(Quaternion.multiply(q,
        Quaternion.from_elements(v.x,v.y,v.z,0)),
        Quaternion.from_elements(-q.x,-q.y,-q.z,q.w))
    return Vector3(r.x,r.y,r.z)
end
local projection = dofile(arg[1])
local function eye(left,right)
    return projection.recentered_eye({left=left,right=right,down=-0.8,up=0.8},1)
end
local symmetric=eye(-0.8,0.8)
assert(math.abs(projection.binocular_visibility_scale(symmetric,symmetric)-1)<1e-6)
local left,right=eye(-0.94,0.70),eye(-0.70,0.94)
local scale=projection.binocular_visibility_scale(left,right)
assert(scale>1)
assert(math.abs(scale-projection.binocular_visibility_scale(right,left))<1e-6)
assert(math.abs(left.vertical_fov-1.6)<1e-6)
print('projection_math=pass')
Camera = {
    vertical_fov = function(camera) return camera.fov end,
    set_vertical_fov = function(camera, value) camera.fov = value end,
}
local camera = { fov = 2.2 }
local world = {}
assert(projection.update_lod_levels(function(w, c)
    assert(w == world and c == camera and c.fov == 1.6,
        "LOD used the expanded visibility FOV")
    return 42
end, world, camera, 1.6) == 42)
assert(camera.fov == 2.2, "LOD changed the following render's visibility FOV")
local ok = pcall(projection.update_lod_levels, function()
    error("fixture failure")
end, world, camera, 1.6)
assert(not ok and camera.fov == 2.2, "failed LOD update leaked the temporary FOV")
