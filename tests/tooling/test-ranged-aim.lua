-- Exercise the copied-class dispatch used by Stingray, not a base-only hook.
local modules, paths = {}, {
    "action_shoot_hit_scan", "action_shoot_pellets", "action_shoot_projectile",
    "action_flamer_gas", "action_flamer_gas_burst",
}
local action_root = "scripts/extension_systems/weapon/actions/"
local function stock_prepare(self, marker)
    assert(marker == 42)
    local a = self._action_component
    local first = self._multi_fire_mode ~= 2 or
        (a.num_shots_fired + 1) % #self._base_fire_configurations == 1
    if first then
        -- Stand-ins for the stock local recoil/sway/spread applied to the
        -- supplied pose, once per simultaneous group.
        a.shooting_rotation = self._first_person_component.rotation + 7
        a.shooting_position = self._first_person_component.position
        a.authors = (a.authors or 0) + 1
    end
    self.fx_rotation = self._first_person_component.rotation
    a.num_shots_fired = a.num_shots_fired + 1
    return "prepared", nil, marker
end
local base = {_prepare_shooting = stock_prepare}
modules[action_root .. "action_shoot"] = base
for _, name in ipairs(paths) do
    modules[action_root .. name] = {
        __class_name = name, _prepare_shooting = base._prepare_shooting,
        _acquire_targets = function(self) return self._first_person_component.rotation end,
        _acquire_suppressed_units = function(self) return self._first_person_component.rotation end,
    }
end
modules[action_root .. "action_shoot_pellets"]._prepare_shooting = function(self, ...)
    base._prepare_shooting(self, ...)
    self.pellets_fired = 0
end
require = function(path)
    if path:find("multi_fire_modes", 1, true) then return {simultaneous = 2} end
    modules[path] = modules[path] or {}
    return modules[path]
end
local player, remote = {}, {}
local private, enabled = true, true
Managers = {
    player = {local_player = function() return {player_unit = player} end},
    state = {game_mode = {game_mode_name = function()
        return private and "shooting_range" or "mission"
    end}},
}
local mod = {
    hook = function(_, class, method, callback)
        local original = class[method] or function() end
        class[method] = function(...) return callback(original, ...) end
    end,
    hook_safe = function() end, command = function() end, info = function() end,
}
local aim = assert(loadfile(arg[1]))()
aim.install(mod, {controller_aim_target = function()
    if enabled then return 20, 100 end
end}, {authoring_enabled = true, last_sequence = 1})
local actual_muzzle = aim.third_person_muzzle
aim.third_person_muzzle = function() return nil end
local shared = {position = 1, rotation = 10, other = "unchanged"}
local function action(class, group)
    return setmetatable({_player_unit = player, _first_person_component = shared,
        _action_component = {num_shots_fired = 0}, _multi_fire_mode = group and 2 or 1,
        _base_fire_configurations = group and {{}, {}} or {{}},
    }, {__index = class})
end
assert(base._prepare_shooting == stock_prepare, "base mutation cannot cover copied classes")
for _, name in ipairs(paths) do
    local class = modules[action_root .. name]
    assert(class._prepare_shooting ~= stock_prepare, "concrete route missed: " .. name)
    for _, group in ipairs({false, true}) do
        local a = action(class, group)
        for shot = 1, 4 do
            local x, y, z = a:_prepare_shooting(42)
            if name == "action_shoot_pellets" then
                assert(x == nil and y == nil and z == nil and a.pellets_fired == 0)
            else
                assert(x == "prepared" and y == nil and z == 42)
            end
            assert(a._action_component.shooting_rotation == 107, "head aim or double transform")
            assert(a._action_component.shooting_position == 20, "head origin fallback")
            assert(a.fx_rotation == 100, "muzzle FX used head rotation")
            assert(a._first_person_component == shared, "scoped pose leaked")
        end
        assert(a._action_component.authors == (group and 2 or 4), "changed group authoring")
        if name:find("flamer", 1, true) then
            assert(a:_acquire_targets() == 100 and a:_acquire_suppressed_units() == 100)
            assert(a._first_person_component == shared)
        end
    end
end
local a = action(modules[action_root .. paths[1]])
for _, case in ipairs({"remote", "untracked", "not_private"}) do
    a._player_unit = case == "remote" and remote or player
    enabled, private = case ~= "untracked", case ~= "not_private"
    a:_prepare_shooting(42)
    assert(a._action_component.shooting_rotation == 17, "changed unsupported owner/state")
end
a._player_unit, enabled, private = player, true, true
assert(not pcall(aim.with_ranged_pose, a, function(self)
    assert(self._first_person_component.rotation == 100)
    error("fixture")
end))
assert(a._first_person_component == shared and shared.rotation == 10)
aim.third_person_muzzle = function() return 50 end
aim.converged_rotation = function(origin, position, rotation)
    assert(origin == 50 and position == 20 and rotation == 100)
    return 120
end
a:_prepare_shooting(42)
assert(a._action_component.shooting_position == 50)
assert(a._action_component.shooting_rotation == 127, "lost stock offset at converged muzzle")
assert(a._first_person_component == shared)
-- Barrel lookup runs before stock increments the counter.
local source_seen
Unit = {alive = function() return true end, world_position = function(_, node) return node end}
a._action_settings = {fx = {alternate_muzzle_flashes = true}}
a._muzzle_fx_source_name, a._muzzle_fx_source_secondary_name = "left", "right"
a._action_component.current_fire_config = 1
a._fire_configurations = function() return {{}} end
a._reference_attachment_id = function() return nil end
a._fx_extension = {vfx_spawner_unit_and_node = function(_, source)
    source_seen = source
    return {}, 50, {}, 60
end}
for shot = 0, 3 do
    a._action_component.num_shots_fired = shot
    assert(actual_muzzle(a) == 60)
    assert(source_seen == (shot % 2 == 0 and "left" or "right"))
end
print("ranged_aim=pass copied_classes=5 simultaneous_groups=pass scope_recovery=pass")
