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
local extension = {_first_person_component=component}
extension.is_within_default_view = function(self)
    return self._first_person_component.rotation == hand_rotation
end
extension.unrelated_method = function(self) assert(self == extension); return 9 end
local action = {_player_unit = player_unit, _first_person_component = component,
    _first_person_extension=extension}
local function verify(self, argument)
    assert(argument == 42)
    assert(self._first_person_component.rotation == hand_rotation)
    assert(self._first_person_component.position == component.position, "changed melee reach origin")
    assert(self._first_person_component.other == 7)
    assert(component.rotation ~= hand_rotation, "changed shared movement heading")
    assert(self._first_person_extension:is_within_default_view({}), "head-facing view rejected hand-directed contact")
    assert(self._first_person_extension:unrelated_method() == 9)
    assert(extension._first_person_component == component, "modified camera extension")
    return "position", nil, "direction"
end
local a, b, c = aim.with_melee_aim(action, verify, 42)
assert(a == "position" and b == nil and c == "direction", "lost action return values")
assert(action._first_person_component == component)
assert(action._first_person_extension == extension)
local ok = pcall(aim.with_melee_aim, action, function() error("fixture") end)
assert(not ok and action._first_person_component == component, "failed action leaked pose override")
assert(action._first_person_extension == extension, "failed action leaked view override")
for _, method in ipairs({"start", "_update_sweep", "_push", "_find_explosion_position_and_direction"}) do
    assert(hooks[method], "missing melee hook: " .. method)
    hooks[method](verify, action, 42)
end
action._player_unit = {}
aim.with_melee_aim(action, function(self) assert(self._first_person_component == component) end)
action._player_unit = player_unit
local interactor = {_unit=player_unit,_first_person_component=component}
for _, method in ipairs({"_find_interaction_object", "_find_interaction_object_3p",
        "_check_valid_ongoing_interaction", "force_update_smart_tag_targets"}) do
    local function verify_interaction(self)
        assert(self._first_person_component.position == hand_position)
        assert(self._first_person_component.rotation == hand_rotation)
        assert(self._first_person_component.other == 7)
        return "target", nil, 4
    end
    local target, missing, node = hooks[method](verify_interaction, interactor)
    assert(target == "target" and missing == nil and node == 4)
    assert(interactor._first_person_component == component)
    assert(not pcall(hooks[method], function() error("interaction failure") end, interactor))
    assert(interactor._first_person_component == component)
    interactor._unit = {}
    hooks[method](function(self) assert(self._first_person_component == component) end, interactor)
    interactor._unit = player_unit
end
hand_rotation = nil
aim.with_melee_aim(action, function(self) assert(self._first_person_component == component) end)
print("melee_aim=pass")
