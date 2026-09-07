-- Optional integration against actual stock ProjectileFxExtension methods.
-- Engine particles/math are isolated; no XR, live game or network is used.
local module_path=assert(arg[1]); local stock=assert(arg[2])..'/scripts/'
local vm={}
Vector3=setmetatable({}, {__call=function(_,x,y,z) return setmetatable({x=x,y=y,z=z},vm) end})
vm.__add=function(a,b) return Vector3(a.x+b.x,a.y+b.y,a.z+b.z) end
vm.__sub=function(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__mul=function(a,b) return Vector3(a.x*b,a.y*b,a.z*b) end
Vector3.x=function(v) return v.x end; Vector3.y=function(v) return v.y end; Vector3.z=function(v) return v.z end
Vector3.length_squared=function(v) return v.x*v.x+v.y*v.y+v.z*v.z end
Vector3.length=function(v) return math.sqrt(Vector3.length_squared(v)) end
local function box(value)
    return {unbox=function(self) return self.value end,store=function(self,v) self.value=v end,value=value}
end
Vector3Box=box; QuaternionBox=box; Matrix4x4Box=box
Quaternion={identity=function() return 'identity' end,inverse=function(q) return q end}
Matrix4x4={from_quaternion=function(q) return {rotation=q} end}
local positions={}; local live={}
Unit={alive=function(u) return live[u]==true end,world_position=function(u) return assert(positions[u]) end,
    world_rotation=function() return 'identity' end,node=function() return 1 end,
    flow_event=function() end}
local particles,created,linked,moved,destroyed,variables={},{},{},{},{},{}
local next_id=0
World={create_particles=function(world,name,position,rotation,scale,group)
    next_id=next_id+1
    particles[next_id]={position=position,world=world,name=name,group=group}
    created[#created+1]=next_id
    return next_id
end,link_particles=function(world,id,unit,node,pose,policy)
    assert(particles[id]); particles[id].linked=unit
    linked[#linked+1]=id
end,move_particles=function(world,id,position)
    assert(particles[id] and not particles[id].linked)
    particles[id].position=position; moved[#moved+1]=id
end,destroy_particles=function(world,id)
    assert(particles[id],'double destroy'); particles[id]=nil; destroyed[#destroyed+1]=id
end,find_particles_variable=function() return 7 end,set_particles_variable=function(world,id,index,value)
    variables[id]=value
end}
WwiseWorld={is_playing=function() return false end}
local templates={force_staff_ball={name='force_staff_ball'},force_staff_ball_heavy={name='force_staff_ball_heavy'}}
local deps={
    ['scripts/utilities/attack/attacking_unit_resolver']={},
    ['scripts/utilities/attack/impact_effect']={},
    ['scripts/network_lookup/network_lookup']={projectile_template_effects={impact=1}},
    ['scripts/settings/projectile_locomotion/projectile_locomotion_settings']={states={sleep='sleep'}},
    ['scripts/settings/projectile/projectile_templates']=templates,
    ['scripts/settings/surface_material_settings']={hit_types={stop='stop'}},
}
for name,value in pairs(deps) do local v=value; package.preload[name]=function() return v end end
class=function() return {} end
local Fx=dofile(stock..'extension_systems/fx/projectile_fx_extension.lua')
package.preload['scripts/extension_systems/fx/projectile_fx_extension']=function() return Fx end
local calls=0
local Action={_fire_projectile=function(self,t,unit,paid,locomotion)
    calls=calls+1
    assert(self._first_person_component.position==self.stock_position,'simulation pose changed')
    assert(locomotion._position:unbox()==positions[unit],'projectile position changed')
    return 'stock',nil,42
end}
package.preload['scripts/extension_systems/weapon/actions/action_spawn_projectile']=function() return Action end
local enabled=true; local hand=Vector3(1,0,1.7); local tip=Vector3(1.5,0,1.7)
local presentation={online_rules={simulation_aim_active=function(u) return enabled and u=='owner' end},
    weapon_aim_target=function(role) return hand end,
    controller_aim={staff_tip=function() return tip end}}
local warnings=0
local mod={hook=function(_,c,n,h) local f=assert(c[n],n); c[n]=function(...) return h(f,...) end end,
    info=function() end,warning=function() warnings=warnings+1 end}
local visual=dofile(module_path)
local instance=visual.install(mod,presentation)
local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a)..' != '..tostring(b)) end
near(visual.weight(0),1); near(visual.weight(.5),.5); near(visual.weight(1),0)
local serial=0
local function shot(heavy,owner)
    serial=serial+1; local unit='projectile'..serial
    live[unit]=true; positions[unit]=Vector3(0,0,1.7)
    local action={_player_unit=owner or 'owner',_action_settings={use_charge=heavy},
        _projectile_template=function() return templates[heavy and 'force_staff_ball_heavy' or 'force_staff_ball'] end,
        stock_position=positions[unit]}
    action._first_person_component={position=action.stock_position}
    local a,b,c=Action._fire_projectile(action,0,unit,0,{_position=box(positions[unit])})
    assert(a=='stock' and b==nil and c==42)
    local fx=setmetatable({_unit=unit,_owner_unit=owner or 'owner',_world='world',
        _projectile_template=action:_projectile_template(),_effect_ids={},_life_times={},
        _looping_playing_ids={},_charge_level=.8,_optional_particle_group_id=19,
        _effects={spawn={vfx={particle_name='staff',link=true,orphaned_policy='destroy',
            use_charge_level=true,min_charge_level=.35}}}}, {__index=Fx})
    return fx,unit
end
local fx,unit=shot(false)
-- The launch origin is frozen even when the next effect update sees a new hand.
hand=Vector3(2,0,1.7)
fx:start_fx('spawn'); local id=fx._effect_ids.spawn
near(particles[id].position.x,1); assert(not particles[id].linked)
near(variables[id].x,.87); assert(particles[id].group==19)
positions[unit]=Vector3(0,.5,1.7); fx:update(unit,.01,.01)
near(particles[id].position.x,.5); near(particles[id].position.y,.5)
positions[unit]=Vector3(0,1,1.7); fx:update(unit,.01,.02)
assert(particles[id].linked==unit and #linked==1)
assert(positions[unit].x==0 and instance.completed==1)
local charged,u2=shot(true); charged:start_fx('spawn')
near(particles[charged._effect_ids.spawn].position.x,1.5)
-- Near impact hands the particle back before stock impact processing.
charged:on_impact(Vector3(0,.2,1.7),'wall',nil,nil,60)
assert(particles[charged._effect_ids.spawn].linked==u2 and charged._has_impacted)
local dead,u3=shot(false); dead:start_fx('spawn'); local dead_id=dead._effect_ids.spawn
dead:destroy(); assert(not particles[dead_id] and dead._effect_ids.spawn==nil)
local stopped=shot(false); stopped:start_fx('spawn'); local stop_id=stopped._effect_ids.spawn
stopped:_stop_fx('spawn'); stopped:destroy(); assert(not particles[stop_id])
local foreign=shot(false,'other'); foreign:start_fx('spawn')
assert(particles[foreign._effect_ids.spawn].linked)
local retired=shot(false); retired:start_fx('spawn'); enabled=false
retired:update(retired._unit,.01,1); assert(particles[retired._effect_ids.spawn].linked)
local disabled=shot(false); disabled:start_fx('spawn')
assert(particles[disabled._effect_ids.spawn].linked); enabled=true
-- A projectile first rendered past one metre must not jump back toward the hand.
local late,ul=shot(false); positions[ul]=Vector3(0,2,1.7); late:start_fx('spawn')
near(particles[late._effect_ids.spawn].position.y,2)
assert(particles[late._effect_ids.spawn].linked)
-- A stock exception restores the engine-hook scope and cleans the free particle.
local broken=shot(false); local original_variable=World.set_particles_variable
World.set_particles_variable=function() error('stock fixture failure') end
local ok,err=pcall(broken.start_fx,broken,'spawn')
assert(not ok and tostring(err):find('stock fixture failure'))
World.set_particles_variable=original_variable
local independent=World.create_particles('world','staff',Vector3(7,8,9),'identity')
near(particles[independent].position.x,7)
assert(broken._effect_ids.spawn==nil)
assert(warnings==0 and calls==9)
-- Tracking loss or an implausible offset leaves the ordinary effect linked.
hand=nil
local untracked=shot(false); untracked:start_fx('spawn')
assert(particles[untracked._effect_ids.spawn].linked)
hand=Vector3(20,0,1.7)
local distant=shot(false); distant:start_fx('spawn')
assert(particles[distant._effect_ids.spawn].linked)
hand=Vector3(1,0,1.7)
local failed_move=shot(false); failed_move:start_fx('spawn')
local original_move=World.move_particles
World.move_particles=function() error('engine move failure') end
failed_move:update(failed_move._unit,.01,2)
World.move_particles=original_move
assert(particles[failed_move._effect_ids.spawn].linked and warnings==1)
print('PASS actual stock FX: hand/staff launch, one-metre convergence, frozen origin, unchanged simulation,')
print('     charge/group preservation, impact alignment, cleanup, owner/mode guards, late spawn and exception scope.')
print('LIMIT: engine particles and tracking are fixtures; live trail appearance and worn alignment remain pending.')
