-- Scoped ownership tests: stock throw physics and timing remain behind these hooks.
local root="scripts/extension_systems/weapon/actions/"
local effects_path="scripts/extension_systems/visual_loadout/wieldable_slot_scripts/aim_projectile_effects"
local luggable_effects_path="scripts/extension_systems/visual_loadout/wieldable_slot_scripts/aim_luggable_effects"
local classes={[root.."action_aim_projectile"]={},[root.."action_throw_grenade"]={},
    [effects_path]={},[luggable_effects_path]={}}
local action_utility={current_action_settings_from_component=function(component,actions)
    return actions[component.current_action_name]
end}
package.preload["scripts/utilities/action/action"]=function() return action_utility end
for path,class in pairs(classes) do
    local value=class
    package.preload[path]=function() return value end
end
local hooks={}
local mod={hook=function(_,class,name,hook)
    hooks[class]=hooks[class] or {}; assert(not hooks[class][name],'Duplicate concrete hook')
    hooks[class][name]=hook
end}
local available=true
local target={target=function(side)
    assert(side=="right")
    if available then return 100,200 end
end}
Managers={player={local_player=function() return {player_unit="local"} end}}
Unit={world_position=function(unit,node) return "p:"..unit..":"..tostring(node) end,
    world_rotation=function(unit,node) return "r:"..unit..":"..tostring(node) end}
local old_position,old_rotation=Unit.world_position,Unit.world_rotation
local grenade=dofile(assert(arg[1])); grenade.install(mod,target)
local aim_hook=hooks[classes[root.."action_aim_projectile"]].fixed_update
local throw_hook=hooks[classes[root.."action_throw_grenade"]]._spawn_projectile
local preview_hook=hooks[classes[effects_path]]._update_trajectory
local luggable_preview_hook=hooks[classes[luggable_effects_path]]._update_trajectory
local template={keywords={"other","grenade"}}
local settings={kind="aim_projectile",throw_type="throw"}
local original=setmetatable({}, {__index={position=1,rotation=2,unchanged=33},
    __newindex=function() error("read-only component") end})
local action={_player_unit="local",_weapon_template=template,_action_settings=settings,
    _first_person_component=original}
local count=0
local function stock(self,dt,t)
    count=count+1
    assert(dt==0.01 and t==42 and self._first_person_component.unchanged==33)
    return self._first_person_component.position,nil,self._first_person_component.rotation
end
local function expect(hook,p,r)
    local a,b,c=hook(stock,action,0.01,42)
    assert(a==p and b==nil and c==r)
    assert(action._first_person_component==original)
end
expect(aim_hook,100,200)
settings.kind="throw_grenade"; expect(throw_hook,100,200)
settings.throw_type="underhand_throw"; expect(throw_hook,100,200)
assert(count==3)
-- Never redirect other players, arbitrary projectile actions, nodes or mines.
action._player_unit="remote"; expect(throw_hook,1,2); action._player_unit="local"
available=false; expect(throw_hook,1,2); available=true
settings.spawn_node=1; expect(throw_hook,1,2); settings.spawn_node=nil
settings.throw_type="place"; expect(throw_hook,1,2); settings.throw_type="throw"
settings.kind="spawn_projectile"; expect(throw_hook,1,2); settings.kind="throw_grenade"
template.keywords={"zealot"}; expect(throw_hook,1,2); template.keywords={"grenade"}
local ok,err=pcall(throw_hook,function(self)
    assert(self._first_person_component.position==100); error("stock throw error")
end,action)
assert(not ok and tostring(err):find("stock throw error",1,true))
assert(action._first_person_component==original)
-- Independent stock arc reads must share the hand pose without changing other nodes.
local effect={_is_local_unit=true,_first_person_unit="fp",_weapon_template=template,
    _weapon_action_component={current_action_name="aim"},_weapon_actions={aim=settings}}
local trajectory={start_offset="cosmetic",arc_vfx_spawner_name="weapon",speed=12,momentum=13}
local function arc(self,passed,dt,t)
    assert(dt==0.01 and t==42 and passed~=trajectory)
    assert(passed.start_offset==nil and passed.arc_vfx_spawner_name==nil)
    assert(passed.speed==12 and passed.momentum==13)
    assert(Unit.world_position("fp",1)==100 and Unit.world_rotation("fp",1)==200)
    assert(Unit.world_position("fp",2)=="p:fp:2")
    assert(Unit.world_rotation("other",1)=="r:other:1")
    assert(Unit.world_position("fp")=="p:fp:nil")
    return "arc",nil,42
end
local a,b,c=preview_hook(arc,effect,trajectory,0.01,42)
assert(a=="arc" and b==nil and c==42)
assert(Unit.world_position==old_position and Unit.world_rotation==old_rotation)
assert(trajectory.start_offset=="cosmetic" and trajectory.arc_vfx_spawner_name=="weapon")
-- Nested calls unwind to the enclosing accessors before restoring native accessors.
preview_hook(function(self,passed,dt,t)
    local outer=Unit.world_position
    preview_hook(arc,self,trajectory,dt,t)
    assert(Unit.world_position==outer)
end,effect,trajectory,0.01,42)
assert(Unit.world_position==old_position)
ok,err=pcall(preview_hook,function() error("stock arc error") end,effect,trajectory)
assert(not ok and tostring(err):find("stock arc error",1,true))
assert(Unit.world_position==old_position and Unit.world_rotation==old_rotation)
local function fallback(self,passed)
    assert(passed==trajectory and Unit.world_position==old_position)
end
effect._is_local_unit=false; preview_hook(fallback,effect,trajectory); effect._is_local_unit=true
available=false; preview_hook(fallback,effect,trajectory); available=true
effect._weapon_action_component.current_action_name="missing"; preview_hook(fallback,effect,trajectory)
-- All three audited luggables author aim and the concrete inherited preview.
-- Their cached throw and near-feet drop consumers require no release hook.
effect._weapon_action_component.current_action_name='aim'
template.keywords={'luggable'}
settings.kind,settings.throw_type='aim_projectile','throw'
for _,name in ipairs({'luggable','luggable_light','luggable_mission'}) do
    template.name=name
    expect(aim_hook,100,200)
    luggable_preview_hook(arc,effect,trajectory,.01,42)
    assert(Unit.world_position==old_position and action._first_person_component==original)
end
settings.kind='throw_luggable'
assert(not grenade.supported(template,settings),'Cached release must remain stock')
settings.throw_type='drop'
assert(not grenade.supported(template,settings),'Near-feet drop was redirected')
settings.kind,settings.throw_type='aim_projectile','underhand_throw'
assert(not grenade.supported(template,settings),'Unaudited luggable route enabled')
settings.throw_type='throw'; template.name='unknown_luggable'
expect(aim_hook,1,2)
luggable_preview_hook(fallback,effect,trajectory)
template.name='luggable'; action._player_unit='remote'
expect(aim_hook,1,2); action._player_unit='local'
available=false
expect(aim_hook,1,2); luggable_preview_hook(fallback,effect,trajectory)
available=true
print("grenade aim/throw/preview ownership, fallback and restoration passed")
