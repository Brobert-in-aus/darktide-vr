-- Diagnostic: the Skitarii flamethrower skull order shows no ground preview in
-- VR. The preview is a particle the stock effect template
-- companion_servo_skull_aim_on_ground_effect creates at the aim's ground
-- position while the order aim runs. Log when that template starts and stops,
-- and on every change of the inputs that decide whether it spawns the
-- particle, so a worn test separates "never spawned" from "spawned but not
-- seen".
local Trace = {}
local PATH = "scripts/settings/fx/effect_templates/companion_servo_skull_aim_on_ground_effect"

local function fmt_position(position)
    if not position then return "nil" end
    return string.format("%.2f,%.2f,%.2f", position.x, position.y, position.z)
end

function Trace.snapshot(data)
    local position_finder = data._position_finder_component
    local target_finder = data._action_module_target_finder_component
    local grenade = data._grenade_ability_action_component
    local position = position_finder and position_finder.position
    local player = data._player_unit and POSITION_LOOKUP and POSITION_LOOKUP[data._player_unit]
    return {
        local_unit = tostring(data.is_local_unit),
        action = tostring(grenade and grenade.current_action_name),
        valid = tostring(position_finder and position_finder.position_valid),
        target = tostring(target_finder and target_finder.target_unit_1 ~= nil),
        particle = tostring(data._targeting_effect_id ~= nil),
        fx = tostring(data._targeting_fx_name):match("[^/]*$"),
        position = fmt_position(position),
        distance = position and player and string.format("%.2f", Vector3.distance(position, player)) or "nil",
    }
end

function Trace.key(s)
    -- Position and distance are left out so aiming around does not log every frame.
    return table.concat({s.local_unit, s.action, s.valid, s.target, s.particle, s.fx}, "|")
end

function Trace.line(s)
    return string.format(
        "DARKTIDEVR_SKULL_PREVIEW local=%s action=%s position_valid=%s target=%s particle=%s fx=%s position=%s distance_m=%s",
        s.local_unit, s.action, s.valid, s.target, s.particle, s.fx, s.position, s.distance)
end

function Trace.install(mod)
    local api = {lines = 0}
    local last_key
    local function log(text)
        if api.lines >= 200 then return end
        api.lines = api.lines + 1
        mod:info("%s", text)
    end
    mod:hook_require(PATH, function(template)
        mod:hook(template, "start", function(func, data, context, ...)
            local result = func(data, context, ...)
            last_key = nil
            log("DARKTIDEVR_SKULL_PREVIEW template=start local=" .. tostring(data.is_local_unit))
            return result
        end)
        mod:hook(template, "update", function(func, data, context, dt, t, ...)
            local result = func(data, context, dt, t, ...)
            local ok, s = pcall(Trace.snapshot, data)
            if ok then
                local key = Trace.key(s)
                if key ~= last_key then
                    last_key = key
                    log(Trace.line(s))
                end
            end
            return result
        end)
        mod:hook(template, "stop", function(func, data, context, ...)
            log("DARKTIDEVR_SKULL_PREVIEW template=stop particle=" .. tostring(data._targeting_effect_id ~= nil))
            last_key = nil
            return func(data, context, ...)
        end)
    end)
    return api
end

return Trace
