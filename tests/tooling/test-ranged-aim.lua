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
local function stock_throw(self, marker)
    assert(marker==42)
    self.launches=(self.launches or 0)+1
    return self._first_person_component.position,nil,self._first_person_component.rotation,65
end
modules[action_root.."action_spawn_projectile"]={
    _spawn_projectile_unit=stock_throw,_fire_projectile=stock_throw}
modules[action_root.."action_weapon_throw"]={
    _spawn_projectile_unit=stock_throw,_fire_projectile=stock_throw}
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
local safe_hooks={}
local mod = {
    hook = function(_, class, method, callback)
        local original = class[method] or function() end
        class[method] = function(...) return callback(original, ...) end
    end,
    hook_safe = function(_,class,method,callback)
        safe_hooks[class]=safe_hooks[class] or {}; safe_hooks[class][method]=callback
    end, command = function() end, info = function() end,
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
local throw=action(modules[action_root.."action_weapon_throw"])
throw._action_settings={kind='weapon_throw'}
throw._weapon_template={keywords={'melee','dual_shivs','p1'}}
for _,method in ipairs({'_spawn_projectile_unit','_fire_projectile'}) do
    assert(modules[action_root.."action_weapon_throw"][method]~=stock_throw)
    local p,n,r,s=throw[method](throw,42)
    assert(p==20 and n==nil and r==100 and s==65)
    assert(throw._first_person_component==shared)
end
assert(throw.launches==2,'duplicated stock launch')
local p,_,r=modules[action_root.."action_spawn_projectile"]._fire_projectile(throw,42)
assert(p==1 and r==10,'changed the staff-only base policy')
for _,case in ipairs({'remote','untracked','not_private','node','homing','position','other_weapon','other_action'}) do
    throw._player_unit=case=='remote' and remote or player
    enabled,private=case~='untracked',case~='not_private'
    throw._weapon_template.keywords=case=='other_weapon' and {'melee'} or {'dual_shivs'}
    throw._action_settings={kind=case=='other_action' and 'spawn_projectile' or 'weapon_throw',
        spawn_node=case=='node' and 'hand' or nil,
        track_towards_target=case=='homing',track_towards_position=case=='position'}
    local p,_,r=throw:_fire_projectile(42)
    assert(p==1 and r==10,'changed unsupported throw: '..case)
    assert(throw._first_person_component==shared)
end
enabled,private=true,true
throw._action_settings={kind='weapon_throw'}
assert(not pcall(aim.with_weapon_throw_pose,throw,function(self)
    assert(self._first_person_component.rotation==100)
    error('throw failure')
end))
assert(throw._first_person_component==shared and shared.rotation==10)
-- Ability knives share ActionSpawnProjectile, with an explicit template policy.
local knife=action(modules[action_root.."action_spawn_projectile"])
for _,name in ipairs({'zealot_throwing_knives','psyker_throwing_knives'}) do
    knife._weapon_template={name=name,keywords={name=='psyker_throwing_knives' and 'psyker' or 'zealot'}}
    knife._action_settings={kind='spawn_projectile',track_towards_target=name=='psyker_throwing_knives',
        target_finder_module_class_name='smart_target_targeting'}
    for _,method in ipairs({'_spawn_projectile_unit','_fire_projectile'}) do
        local p,n,r,s=knife[method](knife,42)
        assert(p==20 and n==nil and r==100 and s==65)
        assert(knife._first_person_component==shared)
    end
end
assert(knife.launches==4)
for _,case in ipairs({'remote','untracked','not_private','node','position','other_template','other_module','other_action'}) do
    knife._player_unit=case=='remote' and remote or player
    enabled,private=case~='untracked',case~='not_private'
    knife._weapon_template={name=case=='other_template' and 'psyker_other' or 'psyker_throwing_knives',keywords={'psyker'}}
    knife._action_settings={kind=case=='other_action' and 'weapon_throw' or 'spawn_projectile',
        spawn_node=case=='node' and 'hand' or nil,track_towards_position=case=='position',
        track_towards_target=true,target_finder_module_class_name=case=='other_module' and 'other' or 'smart_target_targeting'}
    local p,_,r=knife:_fire_projectile(42)
    assert(p==1 and r==10,'changed unsupported knife: '..case)
    assert(knife._first_person_component==shared)
end
print("ranged_aim=pass copied_classes=6 simultaneous_groups=pass throwing_guards=pass knife_routes=pass scope_recovery=pass")
-- Exercise the shared mission authority decision through real preparation
-- hooks. Remote units and remote-server sessions must retain stock poses.
local context=dofile(arg[1]:gsub("darktidevr_controller_aim.lua$", "darktidevr_gameplay_context.lua"))
local mode,owns="coop_complete_objective",true
local session={is_server=function() return owns end}
aim.presentation.is_controller_aim_mode=function() return context.aim_mode(mode,session) end
aim.third_person_muzzle=function() return nil end
enabled=true
for _,owner in ipairs({player,remote}) do
    for _,authority in ipairs({true,false}) do
        owns=authority
        local mission_action=action(modules[action_root..paths[1]])
        mission_action._player_unit=owner
        mission_action:_prepare_shooting(42)
        local permitted=owner==player and authority
        assert(mission_action._action_component.shooting_rotation==(permitted and 107 or 17))
        assert(mission_action._action_component.shooting_position==(permitted and 20 or 1))
        assert(mission_action._first_person_component==shared)
    end
end
owns=true
local mission_action=action(modules[action_root..paths[1]])
mission_action:_prepare_shooting(42)
owns=false
mission_action:_prepare_shooting(42)
assert(mission_action._action_component.shooting_rotation==17,"host loss retained hand authoring")
print("mission_ranged=pass local_authority local_player stock_remote host_loss scope_restore")
local network_hook=safe_hooks[modules["scripts/extension_systems/aim/player_unit_aim_extension"]].fixed_update
Quaternion={forward=function(rotation) return rotation end}
local writes=0
GameSession={set_game_object_field=function(session_id,object_id,field,value)
    assert(session_id==3 and object_id==4 and field=="aim_direction" and value==100)
    writes=writes+1
end}
local extension={_is_server=true,_game_session_id=3,_game_object_id=4}
owns=true
network_hook(extension,player)
assert(writes==1)
network_hook(extension,remote)
extension._is_server=false
network_hook(extension,player)
extension._is_server=true
owns=false
network_hook(extension,player)
assert(writes==1,"remote unit/client/host-loss authored server aim")
print("mission_aim_replication=pass local_server_only")
-- The proving range deliberately declines every local hand-pose override.
-- Prepared attacks use the simulation component already authored from input.
aim.presentation.is_controller_aim_mode=function() return false end
aim.presentation.online_rules={enabled=function() return true end}
for _,name in ipairs(paths) do
    local stock_action=action(modules[action_root..name])
    stock_action:_prepare_shooting(42)
    assert(stock_action._action_component.shooting_position==shared.position)
    assert(stock_action._action_component.shooting_rotation==shared.rotation+7)
    assert(stock_action._first_person_component==shared)
end
local reticles=0
aim.publish_reticle=function(ext,position,rotation)
    assert(position==shared.position and rotation==shared.rotation)
    assert(ext._first_person_component==shared); reticles=reticles+1
end
local smart=modules['scripts/extension_systems/smart_targeting/player_unit_smart_targeting_extension']
smart.fixed_update({_is_local_unit=true,_first_person_component=shared})
assert(reticles==1,'Online reticle did not use the stock simulated origin')
smart.fixed_update({_is_local_unit=false,_first_person_component=shared})
assert(reticles==1,'Changed remote reticle')
print('online_range_ranged=pass stock_origins stock_preparation simulated_reticle remote_unchanged')
-- Exercise role routing through concrete attack hooks without swapping raw
-- physical readers or the local player's anatomical skeleton.
local Roles=dofile(arg[1]:gsub('darktidevr_controller_aim.lua$', 'darktidevr_weapon_hand_roles.lua'))
aim.presentation.is_controller_aim_mode=function() return true end
aim.presentation.weapon_hand_roles=Roles.new('left')
local left_available=true
aim.presentation.left_controller_aim_target=function()
    if left_available then return 30,200 end
end
assert(aim.target('dominant')==30 and aim.target('support')==20)
assert(aim.target('right')==20 and aim.target('left')==30 and aim.target('unknown')==nil)
for _,name in ipairs(paths) do
    local left_action=action(modules[action_root..name])
    left_action:_prepare_shooting(42)
    assert(left_action._action_component.shooting_position==30 and
        left_action._action_component.shooting_rotation==207)
    assert(left_action._first_person_component==shared)
end
left_available=false
assert(aim.target('dominant')==nil and aim.target('support')==20)
local lost=action(modules[action_root..paths[1]])
lost:_prepare_shooting(42)
assert(lost._action_component.shooting_position==shared.position and
    lost._action_component.shooting_rotation==shared.rotation+7,'Tracking loss fell back to the other hand')
print('weapon_roles_ranged=pass dominant_input physical_identity tracking_loss stock_fallback')
