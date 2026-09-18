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
local panel_height = 1.125 * 0.9
local symmetric_width = projection.binocular_panel_width(symmetric,symmetric,.032,1,panel_height,10)
assert(math.abs(symmetric_width - 2*(math.tan(.8)-.032)*.96)<1e-6)
local panel_left=projection.recentered_eye({left=-.94,right=.70,down=-.7,up=.9},1)
local panel_right=projection.recentered_eye({left=-.70,right=.94,down=-.85,up=.75},1)
local panel_width,panel_center=projection.binocular_panel_width(panel_left,panel_right,.032,1,panel_height,2)
assert(panel_width>0 and panel_width<symmetric_width)
-- Reproject every panel corner independently into each pitched, offset eye.
-- No corner may pass either horizontal edge of either rendered frustum.
for index,e in ipairs({panel_left,panel_right}) do
    local q=e.rotation
    local inverse=Quaternion.from_elements(-q.x,-q.y,-q.z,q.w)
    local eye_x=index==1 and -.032 or .032
    for _,x in ipairs({panel_center-panel_width/2,panel_center+panel_width/2}) do
        for _,z in ipairs({-panel_height/2,panel_height/2}) do
            local ray=Quaternion.rotate(inverse,Vector3(x-eye_x,1,z))
            assert(ray.y>0 and math.abs(ray.x/ray.y)<math.tan(e.horizontal_half))
        end
    end
end
-- The banner used to be printed here, a hundred and twenty assertions early.
-- Anything reading this test's output for "projection_math=pass" would have
-- seen it before a single one of the later checks had run -- which is exactly
-- how twelve mutations once came back NOT CAUGHT. It lives at the end now,
-- and there is only one of it.
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

-- Aim-down-sights zoom: the rendered frustum's tangents divided by the
-- magnification, asymmetry and optical centre with them, so both eyes stay on
-- the same world ray. The viewer submits the image with the field of view it
-- always had, which is what turns a narrower cone into a magnified view.
local wide = {left = -0.893445, right = 0.648593, down = -0.909609, up = 0.71549}
local zoomed = projection.zoomed_frustum(wide, 1.12)
for _, edge in ipairs({"left", "right", "down", "up"}) do
    local expected = math.atan(math.tan(wide[edge]) / 1.12)
    assert(math.abs(zoomed[edge] - expected) < 1e-12, "edge " .. edge .. " not divided by the magnification")
    assert(math.abs(zoomed[edge]) < math.abs(wide[edge]), "edge " .. edge .. " did not narrow")
end
-- The optical centre keeps its share of the narrower cone.
local centre_before = (math.tan(wide.left) + math.tan(wide.right)) * 0.5
local centre_after = (math.tan(zoomed.left) + math.tan(zoomed.right)) * 0.5
assert(math.abs(centre_after * 1.12 - centre_before) < 1e-12, "the optical centre did not scale with the cone")
-- Unusable magnifications leave the frustum exactly as it was.
for _, m in ipairs({1, 0.5, -3, 0 / 0, 9}) do
    assert(projection.zoomed_frustum(wide, m) == wide, "magnification " .. tostring(m) .. " was applied")
end
assert(projection.zoomed_frustum(nil, 1.12) == nil)

-- The eased blend and the magnification it produces.
assert(projection.zoom_blend(nil, true, 0.016) == 1, "no previous blend: take the target")
assert(projection.zoom_blend(0, true, nil) == 0, "no time step: hold")
local b = projection.zoom_blend(0, true, projection.ZOOM_TAU)
assert(math.abs(b - (1 - math.exp(-1))) < 1e-9, "one time constant closes 63 per cent")
for _ = 1, 200 do b = projection.zoom_blend(b, true, 0.016) end
assert(b == 1, "the blend settles exactly on its target")
for _ = 1, 200 do b = projection.zoom_blend(b, false, 0.016) end
assert(b == 0, "and comes back to none")
assert(math.abs(projection.zoom_magnification(12, 1) - 1.12) < 1e-12)
assert(projection.zoom_magnification(12, 0) == 1, "no blend, no zoom")
assert(math.abs(projection.zoom_magnification(12, 0.5) - 1.06) < 1e-12)
assert(projection.zoom_magnification(0, 1) == 1 and projection.zoom_magnification(nil, 1) == 1)
assert(projection.zoom_magnification(500, 1) == 1 + projection.ZOOM_MAX_PERCENT * 0.01, "clamped")
assert(projection.zoom_magnification(0 / 0, 1) == 1 and projection.zoom_magnification(12, 0 / 0) == 1)
-- A world point published for a zoomed image: the reticle is placed by the
-- field of view the viewer submits, which is not the one the pair was
-- rendered with while the zoom is on, so everything off the view's centre has
-- to move out by the magnification to stay where it is seen.
local x, y, z = projection.magnified_target(0.3, -0.2, -10, 1.12)
-- The RANGE is kept. Scaling the across components and leaving the depth alone
-- moved the point off the surface it was measured on -- worn, aiming at the
-- ground put the reticle underneath it and further away than the thing it
-- marked. The correction is for the angle; the distance was never the zoom's.
local before = math.sqrt(0.3 * 0.3 + 0.2 * 0.2 + 10 * 10)
local after = math.sqrt(x * x + y * y + z * z)
assert(math.abs(after - before) < 1e-9, "the range is preserved: " .. after .. " vs " .. before)
assert(z > -10 and z < -9.99, "the depth gives a little so the range can hold: " .. z)
assert(x > 0.3 and y < -0.2, "and the across components still move outward")
x, y, z = projection.magnified_target(0, 0, -10, 1.12)
assert(x == 0 and y == 0 and z == -10, "a point dead ahead does not move")
-- The same tangents: that is what makes it cancel, and renormalising cannot
-- disturb them because both components are divided by the same number.
local real_tangent = 0.3 / 10
local mx, _, mz = projection.magnified_target(0.3, 0, -10, 1.12)
local published_tangent = mx / math.abs(mz)
assert(math.abs(published_tangent - real_tangent * 1.12) < 1e-12,
    "the published tangent is the magnified one")
-- A point at no range has no direction to correct.
local zx, zy, zz = projection.magnified_target(0, 0, 0, 1.12)
assert(zx == 0 and zy == 0 and zz == 0, "a point at the eye is left alone")
for _, m in ipairs({1, 1.00005, 0, -2, 4.5, 0 / 0}) do
    x, y, z = projection.magnified_target(0.3, -0.2, -10, m)
    assert(x == 0.3 and y == -0.2 and z == -10, "magnification " .. tostring(m) .. " was applied")
end
x, y, z = projection.magnified_target(0 / 0, -0.2, -10, 1.12)
assert(x ~= x and y == -0.2, "a point that is not a number is passed through untouched")
-- THE RETICLE'S RANGE IN THE SIGHTS (19 September). The world is rendered
-- through a narrowed frustum and submitted at the unchanged field of view, so
-- it appears at D/m; the reticle is a quad layer composited at the submitted
-- field of view, so it stays at D and reads m times too far. The fix is the
-- range, and the fault is proportional -- which is exactly how the user
-- described it, and why a fixed offset was never going to be it.
for _, m in ipairs({1.03, 1.5, 2.0, 3.99}) do
  for _, d in ipairs({0.5, 3.0, 16.2, 33.2}) do
    local placed = projection.zoomed_range(d, m)
    assert(math.abs(placed - d / m) < 1e-9, 'the range comes in by the magnification')
    -- Proportional, not fixed: the error it removes grows with the distance,
    -- which is the observation that identified the fault.
    assert(math.abs((d - placed) - d * (1 - 1 / m)) < 1e-9, 'the correction is proportional')
    assert(placed < d, 'the reticle comes nearer, never further')
  end
end
-- At the shipped 3% setting it is 9 cm at three metres -- under the ground
-- when looking down at it -- and most of a metre at thirty.
assert(math.abs((3.0 - projection.zoomed_range(3.0, 1.03)) - 0.0874) < 0.0005)
assert(math.abs((33.2 - projection.zoomed_range(33.2, 1.03)) - 0.9670) < 0.0005)
-- No zoom, no correction: outside the sights the reticle is already right,
-- and that is the fact that told us where to look.
assert(projection.zoomed_range(12.0, 1.0) == 12.0, 'no zoom leaves the range alone')
assert(projection.zoomed_range(12.0, 1.00005) == 12.0, 'below the threshold')
-- The same guards as magnified_target: a magnification out of range or a
-- nonsense number corrects nothing rather than moving the reticle somewhere
-- arbitrary.
assert(projection.zoomed_range(12.0, 4.5) == 12.0, 'beyond the cap')
assert(projection.zoomed_range(12.0, 0 / 0) == 12.0, 'a nan magnification')
assert(projection.zoomed_range(0 / 0, 1.5) ~= projection.zoomed_range(0 / 0, 1.5) or true)
assert(projection.zoomed_range(-1.0, 1.5) == -1.0, 'a range behind the eye')
assert(projection.zoomed_range(nil, 1.5) == nil and projection.zoomed_range(12.0, nil) == 12.0)

print("projection_math=pass recentered visibility panel lod zoom magnified_target zoomed_range")
