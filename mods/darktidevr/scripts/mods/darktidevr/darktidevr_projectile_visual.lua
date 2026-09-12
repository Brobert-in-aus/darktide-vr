-- Offset only the local staff spawn particle. Projectile units, physics,
-- simulation components, impact positions and network messages remain stock.
local module = {}
local supported = {force_staff_ball=true, force_staff_ball_heavy=true}
local function pack(...) return {n=select('#',...), ...} end
local function finite_vector(v)
    if not v then return false end
    local x,y,z = Vector3.x(v),Vector3.y(v),Vector3.z(v)
    return x==x and y==y and z==z and math.abs(x)<100000 and
        math.abs(y)<100000 and math.abs(z)<100000
end

function module.weight(distance)
    local t = math.max(0, math.min(1, distance)) -- one metre
    return 1 - t*t*(3-2*t)
end

function module.install(mod, presentation)
    local instance = {starts=0, completed=0, failures=0}
    local pending = setmetatable({}, {__mode='k'})
    local active = setmetatable({}, {__mode='k'})
    local scope
    local function admitted(owner)
        return presentation.online_rules.simulation_aim_active(owner)
    end
    local function origin(action)
        if not admitted(action._player_unit) then return end
        local template = action:_projectile_template()
        if not template or not supported[template.name] then return end
        local settings = action._action_settings
        local role = settings and settings.use_charge and 'dominant' or 'support'
        local hand = presentation.weapon_aim_target(role)
        if not finite_vector(hand) then return end
        if role=='dominant' then
            local tip = presentation.controller_aim.staff_tip(action)
            if finite_vector(tip) and Vector3.length_squared(tip-hand)<9 then hand=tip end
        end
        return Vector3Box(hand)
    end
    local function report_failure()
        instance.failures=instance.failures+1
        if instance.failures==1 then
            mod:warning('DARKTIDEVR_PROJECTILE_VISUAL fallback=stock reason=visual_operation_failed')
        end
    end
    local function retire(fx, destroy)
        local entry=active[fx]
        if not entry then return end
        active[fx]=nil
        local owns_slot=fx._effect_ids and fx._effect_ids.spawn==entry.id
        if owns_slot and not destroy and Unit.alive(entry.unit) and entry.pose then
            local ok=pcall(World.link_particles,entry.world,entry.id,entry.unit,
                entry.node,entry.pose:unbox(),entry.orphaned_policy)
            if ok then instance.completed=instance.completed+1; return end
            report_failure()
        end
        -- An unlinked effect has no unit-orphan cleanup until handed back.
        pcall(World.destroy_particles,entry.world,entry.id)
        if owns_slot then fx._effect_ids.spawn=nil end
    end
    -- Called by the existing controller-aim hook: DMF replaces duplicate hooks
    -- from one mod instead of composing them like an ordinary Lua wrapper.
    function instance.fire_projectile(func,self,t,unit,paid,locomotion,...)
        local ok,hand=pcall(origin,self)
        if not ok then report_failure(); hand=nil end
        local result=pack(func(self,t,unit,paid,locomotion,...))
        if hand and unit and Unit.alive(unit) then
            -- Capture at release, not when the next rendered frame samples hands.
            local saved,entry=pcall(function()
                local position=locomotion._position:unbox()
                if not finite_vector(position) then return end
                return {owner=self._player_unit,hand=hand,start=Vector3Box(position)}
            end)
            if saved then pending[unit]=entry else report_failure() end
        end
        return unpack(result,1,result.n)
    end
    -- Scope the engine hooks to exactly the particle created by stock start_fx.
    -- Stock retains charge variables, particle groups, sounds and effect IDs.
    mod:hook(World,'create_particles',function(func,world,name,position,rotation,...)
        local entry=scope
        if not entry or entry.world~=world or entry.name~=name or entry.id then
            return func(world,name,position,rotation,...)
        end
        local delta=position-entry.start:unbox()
        entry.distance=Vector3.length(delta)
        local offset=entry.hand:unbox()-entry.start:unbox()
        if not finite_vector(offset) or Vector3.length_squared(offset)>9 or entry.distance>=1 then
            return func(world,name,position,rotation,...)
        end
        entry.offset=Vector3Box(offset)
        entry.last=Vector3Box(position)
        entry.rotation=QuaternionBox(rotation)
        local visual=position+offset*module.weight(entry.distance)
        local id=func(world,name,visual,rotation,...)
        entry.id=id
        return id
    end)
    mod:hook(World,'link_particles',function(func,world,id,unit,node,pose,orphaned_policy,...)
        local entry=scope
        if entry and entry.world==world and entry.id==id and entry.unit==unit then
            entry.node=node
            entry.pose=Matrix4x4Box(pose)
            entry.orphaned_policy=orphaned_policy
            return -- move the free particle until convergence, then link once
        end
        return func(world,id,unit,node,pose,orphaned_policy,...)
    end)
    local Fx = require('scripts/extension_systems/fx/projectile_fx_extension')
    mod:hook(Fx,'start_fx',function(func,self,kind,...)
        if kind~='spawn' then return func(self,kind,...) end
        local entry=pending[self._unit]
        pending[self._unit]=nil
        local vfx=self._effects and self._effects.spawn and self._effects.spawn.vfx
        if not entry or entry.owner~=self._owner_unit or not admitted(entry.owner) or
                not supported[self._projectile_template.name] or not vfx or not vfx.link then
            return func(self,kind,...)
        end
        retire(self,true)
        entry.unit,entry.world=self._unit,self._world
        entry.name=self._is_critical_strike and vfx.particle_name_critical_strike or vfx.particle_name
        local previous=scope
        scope=entry
        local result=pack(pcall(func,self,kind,...))
        scope=previous
        if entry.id then
            active[self]=entry
            if not result[1] or not entry.pose then
                retire(self,true)
            else
                instance.starts=instance.starts+1
                if instance.starts<=4 then
                    mod:info('DARKTIDEVR_PROJECTILE_VISUAL start=%d template=%s converge_m=1 offset_m=%.4f',
                        instance.starts,self._projectile_template.name,Vector3.length(entry.offset:unbox()))
                end
            end
        end
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end)
    local function update(fx)
        local entry=active[fx]
        if not entry then return end
        if not Unit.alive(entry.unit) or not admitted(entry.owner) or fx._has_impacted or
                fx._effect_ids.spawn~=entry.id then retire(fx,false); return end
        local position=Unit.world_position(entry.unit,entry.node)
        if not finite_vector(position) then retire(fx,false); return end
        entry.distance=entry.distance+Vector3.length(position-entry.last:unbox())
        entry.last:store(position)
        if entry.distance>=1 then retire(fx,false); return end
        World.move_particles(entry.world,entry.id,
            position+entry.offset:unbox()*module.weight(entry.distance),entry.rotation:unbox())
    end
    mod:hook(Fx,'update',function(func,self,...)
        local result=pack(func(self,...))
        local ok=pcall(update,self)
        if not ok then report_failure(); retire(self,false) end
        return unpack(result,1,result.n)
    end)
    for _,name in ipairs({'on_impact','on_stick'}) do
        mod:hook(Fx,name,function(func,self,...)
            retire(self,false)
            return func(self,...)
        end)
    end
    mod:hook(Fx,'_stop_fx',function(func,self,kind,...)
        if kind=='spawn' then active[self]=nil end -- stock destroys this ID
        return func(self,kind,...)
    end)
    mod:hook(Fx,'destroy',function(func,self,...)
        pending[self._unit]=nil
        retire(self,true)
        return func(self,...)
    end)
    mod:info('DARKTIDEVR_PROJECTILE_VISUAL installed converge_m=1 physics=stock')
    return instance
end

return module
