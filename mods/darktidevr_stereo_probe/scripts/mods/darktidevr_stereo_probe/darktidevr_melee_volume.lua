-- Offline geometry resolver for the future tracked-contact probe. No game
-- dependencies are loaded here, and no collision/damage/render calls are made.
local Volume = {}

local function positive(value)
    return type(value) == "number" and value == value and
        value > 0 and value < math.huge
end

local function multiplier(action, defaults, name)
    local local_value = action[name .. "_mod"]
    if local_value == nil then local_value = 1 end
    local global_value = defaults["sweep_" .. name .. "_mod"]
    if not positive(local_value) or not positive(global_value) then return nil end
    local value = local_value * global_value
    if positive(value) then return value end
end

function Volume.resolve(weapon, action, defaults, uses_matrix_data)
    if type(action) ~= "table" then return nil, "missing_action" end
    if action.use_sphere_sweep then
        if not positive(action.sphere_radius) then return nil, "invalid_radius" end
        return {shape="sphere", radius=action.sphere_radius,
            offset={0, 0, 0}, corner_radius=action.sphere_radius}
    end
    if type(weapon) ~= "table" or type(defaults) ~= "table" or
        type(uses_matrix_data) ~= "boolean" then
        return nil, "missing_box_context"
    end
    local box = action.weapon_box or weapon.weapon_box
    if type(box) ~= "table" or not positive(box[1]) or
        not positive(box[2]) or not positive(box[3]) then
        return nil, "invalid_box"
    end
    local width = multiplier(action, defaults, "width")
    local height = multiplier(action, defaults, "height")
    local range = multiplier(action, defaults, "range")
    if not width or not height or not range then return nil, "invalid_modifiers" end

    -- Matrix-authored sweeps extend along local up (Z); older spline sweeps
    -- extend along local forward (Y). Width stays on local right (X).
    local x = box[1] * width
    local y = box[2] * (uses_matrix_data and height or range)
    local z = box[3] * (uses_matrix_data and range or height)
    if not positive(x) or not positive(y) or not positive(z) then
        return nil, "invalid_extents"
    end
    local offset = uses_matrix_data and {0, 0, z} or {0, y, 0}
    -- The input pose is the stock sweep origin, not an already shifted centre.
    -- Measure the furthest corner about that origin for rotational sampling.
    local far_y, far_z = y + offset[2], z + offset[3]
    local corner_radius = math.sqrt(x*x + far_y*far_y + far_z*far_z)
    if not positive(corner_radius) then return nil, "invalid_extents" end
    return {shape="oobb", half_extents={x, y, z}, offset=offset,
        corner_radius=corner_radius}
end

return Volume
