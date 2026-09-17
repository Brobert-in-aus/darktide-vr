local Projection = {}
local signs = {-1, 1}
local function inverse_quaternion(q)
    local x, y, z, w = Quaternion.to_elements(q)
    return Quaternion.from_elements(-x, -y, -z, w)
end

local function axis_angle_quaternion(x, y, z, radians)
    local half = radians * 0.5
    local scale = math.sin(half)
    return Quaternion.from_elements(
        x * scale,
        y * scale,
        z * scale,
        math.cos(half)
    )
end

function Projection.recentered_eye(frustum, target_aspect_ratio)
    local horizontal_center = (frustum.left + frustum.right) * 0.5
    local vertical_center = (frustum.down + frustum.up) * 0.5
    local vertical_half = (frustum.up - frustum.down) * 0.5
    local horizontal_half = math.atan(
        math.tan(vertical_half) * target_aspect_ratio
    )

    -- OpenXR +Y maps to Stingray +Z, and OpenXR +X maps to Stingray +X.
    -- Keep the order identical to xr_math::recentered_symmetric_projection.
    local yaw = axis_angle_quaternion(0, 0, 1, -horizontal_center)
    local pitch = axis_angle_quaternion(1, 0, 0, vertical_center)
    return {
        rotation = Quaternion.multiply(yaw, pitch),
        vertical_fov = vertical_half * 2,
        horizontal_half = horizontal_half,
        horizontal_center = horizontal_center,
        vertical_center = vertical_center
    }
end

-- The same frustum seen through a magnifying glass: every edge's tangent
-- divided by the magnification. The mod renders the eyes with the frustum it
-- publishes, while the viewer submits that image to the runtime with the
-- field of view the runtime itself reported, so a narrower rendered cone is
-- shown across the same angle and everything in it looks larger. Asymmetry
-- and the optical centre scale with it, which keeps both eyes' centres on the
-- same world ray and the stereo comfortable. A magnification of 1 (or
-- anything unusable) returns the frustum unchanged. Pure.
function Projection.zoomed_frustum(frustum, magnification)
    if type(frustum) ~= "table" then return frustum end
    local m = tonumber(magnification)
    if not m or m ~= m or m <= 1.0001 or m > 4 then return frustum end
    local function edge(angle)
        local a = tonumber(angle)
        if not a or a ~= a then return angle end
        return math.atan(math.tan(a) / m)
    end
    return {left = edge(frustum.left), right = edge(frustum.right),
        down = edge(frustum.down), up = edge(frustum.up)}
end

-- The eased magnification from an aim-down-sights state: 1 while the sights
-- are down, rising to 1 + percent/100 while they are up, with the 0.15 s time
-- constant the viewer's focus vignette uses so the two move together.
-- `previous` and the returned value are the eased 0..1 blend. Pure.
Projection.ZOOM_TAU = 0.15
Projection.ZOOM_MAX_PERCENT = 30
function Projection.zoom_blend(previous, active, dt)
    local target = active and 1 or 0
    local p = tonumber(previous)
    local step = tonumber(dt)
    if not p or p ~= p then return target end
    if not step or step ~= step or step <= 0 or step > 0.5 then return target end
    local value = p + (target - p) * (1 - math.exp(-step / Projection.ZOOM_TAU))
    if math.abs(target - value) < 0.005 then value = target end
    return value
end

function Projection.zoom_magnification(percent, blend)
    local p = tonumber(percent) or 0
    if p ~= p then p = 0 end
    if p < 0 then p = 0 elseif p > Projection.ZOOM_MAX_PERCENT then p = Projection.ZOOM_MAX_PERCENT end
    local b = tonumber(blend) or 0
    if b ~= b then b = 0 end
    if b < 0 then b = 0 elseif b > 1 then b = 1 end
    return 1 + p * 0.01 * b
end

function Projection.binocular_visibility_scale(left, right)
    -- Light admission must cover the union of the rendered eye cones. A fixed
    -- 20% tangent margin is smaller than their relative optical-axis yaw.
    -- Transform all opposite-eye corner rays into each camera and find the
    -- common expansion required by both horizontal and vertical bounds.
    local scale = 1
    for _, pair in ipairs({{left, right}, {right, left}}) do
        local own, other = pair[1], pair[2]
        local inverse = inverse_quaternion(own.rotation)
        local other_horizontal = math.tan(other.horizontal_half)
        local other_vertical = math.tan(other.vertical_fov * 0.5)
        local own_horizontal = math.tan(own.horizontal_half)
        local own_vertical = math.tan(own.vertical_fov * 0.5)
        for _, x in ipairs(signs) do
            for _, z in ipairs(signs) do
                local ray = Quaternion.rotate(inverse, Quaternion.rotate(
                    other.rotation, Vector3(x * other_horizontal,
                        1, z * other_vertical)))
                if ray.y > 0 then
                    scale = math.max(scale,
                        math.abs(ray.x / ray.y) / own_horizontal,
                        math.abs(ray.z / ray.y) / own_vertical)
                end
            end
        end
    end
    return scale
end

function Projection.binocular_panel_width(left, right, half_ipd, distance, height, maximum)
    -- Intersect both eye frusta on the head-facing panel plane. Check its top
    -- and bottom as well as eye translation: angular overlap alone misses IPD
    -- at close distances and camera pitch can change the edge at each height.
    local lower, upper = -maximum * 0.5, maximum * 0.5
    for index, eye in ipairs({left, right}) do
        local inverse = inverse_quaternion(eye.rotation)
        local x_axis = Quaternion.rotate(inverse, Vector3(1, 0, 0))
        local eye_x = index == 1 and -half_ipd or half_ipd
        local tangent = math.tan(eye.horizontal_half)
        for _, z in ipairs({-height * 0.5, height * 0.5}) do
            local origin = Quaternion.rotate(inverse, Vector3(-eye_x, distance, z))
            for _, side in ipairs(signs) do
                local coefficient = side * x_axis.x - tangent * x_axis.y
                local bound = tangent * origin.y - side * origin.x
                if math.abs(coefficient) < 1e-8 then
                    if bound < 0 then return 0 end
                elseif coefficient > 0 then
                    upper = math.min(upper, bound / coefficient)
                else
                    lower = math.max(lower, bound / coefficient)
                end
            end
        end
    end
    -- Center on the intersection, rather than assuming the shared optical
    -- view is symmetric about head-forward (pitched/asymmetric frusta aren't).
    if upper <= lower then return 0, 0 end
    return (upper - lower) * 0.96, (lower + upper) * 0.5
end

function Projection.update_lod_levels(update, world, camera, rendered_fov)
    -- Visibility overscan is canceled by post projection in the rendered
    -- image. LOD must use that visible FOV, not the wider admission cone.
    local visibility_fov = Camera.vertical_fov(camera)
    Camera.set_vertical_fov(camera, rendered_fov)
    local ok, result = pcall(update, world, camera)
    Camera.set_vertical_fov(camera, visibility_fov)
    if not ok then error(result) end
    return result
end

return Projection
