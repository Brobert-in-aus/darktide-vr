local Projection = {}
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

function Projection.binocular_visibility_scale(left, right)
    -- Light admission must cover the union of the rendered eye cones. A fixed
    -- 20% tangent margin is smaller than their relative optical-axis yaw.
    -- Transform all opposite-eye corner rays into each camera and find the
    -- common expansion required by both horizontal and vertical bounds.
    local scale = 1
    for _, pair in ipairs({{left, right}, {right, left}}) do
        local own, other = pair[1], pair[2]
        local inverse = inverse_quaternion(own.rotation)
        for _, x in ipairs({-1, 1}) do
            for _, z in ipairs({-1, 1}) do
                local ray = Quaternion.rotate(inverse, Quaternion.rotate(
                    other.rotation, Vector3(x * math.tan(other.horizontal_half),
                        1, z * math.tan(other.vertical_fov * 0.5))))
                if ray.y > 0 then
                    scale = math.max(scale,
                        math.abs(ray.x / ray.y) / math.tan(own.horizontal_half),
                        math.abs(ray.z / ray.y) / math.tan(own.vertical_fov * 0.5))
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
            for _, side in ipairs({-1, 1}) do
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
    -- Keep the panel centered on the head and slightly inside the shared edge.
    return math.max(0, math.min(-lower, upper) * 2 * 0.96)
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
