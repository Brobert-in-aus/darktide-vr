-- The skull ground-preview trace wraps the stock effect template without
-- changing its results, and logs only when the spawn inputs change.
local Trace = dofile(assert(arg[1]))
local function vec(x, y, z) return {x = x, y = y, z = z} end
Vector3 = {distance = function(a, b) return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2) end}
POSITION_LOOKUP = {}
local lines, hooked = {}, {}
local mod = {info = function(_, format, ...) lines[#lines + 1] = string.format(format, ...) end,
    hook_require = function(_, path, fn)
        assert(path == "scripts/settings/fx/effect_templates/companion_servo_skull_aim_on_ground_effect")
        fn(hooked.template)
    end,
    hook = function(_, target, name, fn)
        local original = target[name]
        target[name] = function(...) return fn(original, ...) end
    end}
local calls = {}
hooked.template = {
    start = function(data) calls[#calls + 1] = "start"; data.is_local_unit = true; return "started" end,
    update = function(data, _, dt, t) calls[#calls + 1] = "update"; return data.stop_effect end,
    stop = function(data) calls[#calls + 1] = "stop"; data._targeting_effect_id = nil end,
}
local api = Trace.install(mod)
local template = hooked.template
local player = {}
POSITION_LOOKUP[player] = vec(0, 0, 0)
local data = {_player_unit = player,
    _position_finder_component = {position_valid = false, position = vec(0, 0, 0)},
    _action_module_target_finder_component = {},
    _grenade_ability_action_component = {current_action_name = "none"}}
assert(template.start(data, {}) == "started" and lines[1] == "DARKTIDEVR_SKULL_PREVIEW template=start local=true")
template.update(data, {}, 0.016, 1)
assert(#lines == 2 and lines[2]:find("action=none position_valid=false target=false particle=false fx=nil position=0.00,0.00,0.00 distance_m=0.00", 1, true), lines[2])
template.update(data, {}, 0.016, 1.1)
assert(#lines == 2, "unchanged inputs logged again")
-- Aiming moves the position every frame: logged once when valid, not per frame.
data._grenade_ability_action_component.current_action_name = "action_aim"
data._position_finder_component.position_valid = true
data._position_finder_component.position = vec(3, 4, 2)
template.update(data, {}, 0.016, 1.2)
data._position_finder_component.position = vec(3, 5, 2)
template.update(data, {}, 0.016, 1.3)
assert(#lines == 3 and lines[3]:find("action=action_aim position_valid=true", 1, true) and
    lines[3]:find("position=3.00,4.00,2.00 distance_m=5.39", 1, true), lines[3])
data._targeting_effect_id = 7
data._targeting_fx_name = "content/fx/particles/pocketables/cryptic_servoskull_flamer_cone_decal"
data.stop_effect = true
assert(template.update(data, {}, 0.016, 1.4) == true, "update result changed")
assert(#lines == 4 and lines[4]:find("particle=true fx=cryptic_servoskull_flamer_cone_decal", 1, true), lines[4])
template.stop(data, {})
assert(lines[5] == "DARKTIDEVR_SKULL_PREVIEW template=stop particle=true" and data._targeting_effect_id == nil)
assert(table.concat(calls, ",") == "start,update,update,update,update,update,stop")
-- A broken snapshot never breaks the stock effect.
data._position_finder_component = setmetatable({}, {__index = function() error("retired component") end})
assert(template.update(data, {}, 0.016, 1.5) == true)
-- Bounded.
for i = 1, 400 do data._position_finder_component = {position_valid = i % 2 == 0}; template.update(data, {}, 0, i) end
assert(api.lines == 200)
print("skull_preview_trace=pass wraps_template logs_on_change bounded")
