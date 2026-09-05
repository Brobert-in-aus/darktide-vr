require = function() return {} end
local aim = assert(loadfile(arg[1]))()
local player_unit = {}
Managers = {
    player = {local_player = function() return {player_unit = player_unit} end},
    state = {game_mode = {game_mode_name = function() return "shooting_range" end}},
}
local hand_position, hand_rotation = {}, {}
local presentation = {controller_aim_target = function() return hand_position, hand_rotation end}
local hooks = {}
local mod = {
    hook = function(_, _, method, callback) hooks[method] = callback end,
    hook_safe = function() end, command = function() end, info = function() end,
}
aim.install(mod, presentation, {authoring_enabled = true})
local component = {position = {}, rotation = {}, other = 7}
local action = {_player_unit = player_unit, _first_person_component = component}
local function verify(self, argument)
    assert(argument == 42)
    assert(self._first_person_component.rotation == hand_rotation)
    assert(self._first_person_component.position == component.position, "changed melee reach origin")
    assert(self._first_person_component.other == 7)
    assert(component.rotation ~= hand_rotation, "changed shared movement heading")
    return "position", nil, "direction"
end
local a, b, c = aim.with_melee_aim(action, verify, 42)
assert(a == "position" and b == nil and c == "direction", "lost action return values")
assert(action._first_person_component == component)
local ok = pcall(aim.with_melee_aim, action, function() error("fixture") end)
assert(not ok and action._first_person_component == component, "failed action leaked pose override")
for _, method in ipairs({"start", "_update_sweep", "_push", "_find_explosion_position_and_direction"}) do
    assert(hooks[method], "missing melee hook: " .. method)
    hooks[method](verify, action, 42)
end
action._player_unit = {}
aim.with_melee_aim(action, function(self) assert(self._first_person_component == component) end)
action._player_unit = player_unit
hand_rotation = nil
aim.with_melee_aim(action, function(self) assert(self._first_person_component == component) end)
print("melee_aim=pass")
