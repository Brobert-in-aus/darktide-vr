local mod = get_mod("darktidevr_camera_probe")

local last_sample_time = {}
local sample_interval = 1

local function finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

mod:hook_safe("CameraManager", "_update_camera", function(self, dt, t, viewport_name)
    if type(t) ~= "number" or type(viewport_name) ~= "string" then
        return
    end

    local previous = last_sample_time[viewport_name] or -math.huge

    if t - previous < sample_interval then
        return
    end

    last_sample_time[viewport_name] = t

    local position = self:camera_position(viewport_name)
    local rotation = self:camera_rotation(viewport_name)
    local vertical_fov = self:fov(viewport_name)
    local px, py, pz = Vector3.to_elements(position)
    local qx, qy, qz, qw = Quaternion.to_elements(rotation)

    if not finite(px) or not finite(py) or not finite(pz) or
        not finite(qx) or not finite(qy) or not finite(qz) or
        not finite(qw) or not finite(vertical_fov) then
        mod:error("DARKTIDEVR_CAMERA invalid_sample viewport=%s", viewport_name)
        return
    end

    mod:info(
        "DARKTIDEVR_CAMERA schema=1 viewport=%s " ..
        "position=%.6f,%.6f,%.6f rotation=%.8f,%.8f,%.8f,%.8f vfov_rad=%.6f",
        viewport_name,
        px, py, pz,
        qx, qy, qz, qw,
        vertical_fov
    )
end)
