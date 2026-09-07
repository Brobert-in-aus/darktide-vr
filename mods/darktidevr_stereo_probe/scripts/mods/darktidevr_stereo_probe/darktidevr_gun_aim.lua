-- Keep the authored weapon grip. Aim from its held muzzle basis instead of
-- rotating the equipment out of the hand to match OpenXR's generic aim ray.
local GunAim={}
local guns={shoot_hit_scan=true,shoot_pellets=true,shoot_projectile=true}
function GunAim.is_gun(template)
    for _,keyword in ipairs(template and template.keywords or {}) do
        if keyword=='force_staff' then return false end
    end
    for _,action in pairs(template and template.actions or {}) do
        if guns[action.kind] then return true end
    end
    return false
end
function GunAim.relative(grip,muzzle)
    return Quaternion.multiply(Quaternion.inverse(grip),muzzle)
end
function GunAim.resolve(grip,relative)
    return Quaternion.multiply(grip,relative)
end
function GunAim.install(mod,presentation)
    local instance={failures=0}
    local cache
    local function equipped(unit)
        if not presentation.online_rules.simulation_aim_active(unit) or
                presentation.weapon_hand_roles.physical('dominant')~='right' then return end
        local weapon=ScriptUnit.has_extension(unit,'weapon_system')
        local template=weapon and weapon:weapon_template()
        if not GunAim.is_gun(template) then return end
        local held=weapon:_wielded_weapon(weapon._inventory_component,weapon._weapons)
        return weapon,template,held
    end
    local function update(world,unit)
        local weapon,template,held=equipped(unit)
        if not held then cache=nil; return end
        if cache and cache.unit==unit and cache.world==world and cache.held==held and
                cache.template==template and Unit.alive(cache.muzzle) then return end
        cache=nil
        local settings=weapon:running_action_settings()
        -- Capture a resting attachment basis, not a temporary reload, recoil,
        -- melee or wield pose. Later shots retain this basis and apply stock
        -- recoil/sway/spread once through the ordinary preparation route.
        if settings and settings.kind~='aim' then return end
        local _,grip=presentation.weapon_grip_target('dominant')
        local source=held.fx_sources and held.fx_sources._muzzle
        local fx=weapon._fx_extension
        if not grip or not source or not fx then return end
        local _,_,muzzle_unit,muzzle_node=fx:vfx_spawner_unit_and_node(source)
        if not muzzle_unit or muzzle_node==nil or not Unit.alive(muzzle_unit) then return end
        local relative=GunAim.relative(grip,Unit.world_rotation(muzzle_unit,muzzle_node))
        cache={unit=unit,world=world,held=held,template=template,muzzle=muzzle_unit,relative=QuaternionBox(relative)}
        mod:info('DARKTIDEVR_GUN_AIM weapon=%s source=held_grip stock_attachment=preserved',tostring(template.name))
    end
    function instance.update(world,unit)
        local ok,message=pcall(update,world,unit)
        if not ok then
            cache=nil
            instance.failures=instance.failures+1
            if instance.failures==1 then mod:info('DARKTIDEVR_GUN_AIM fallback=%s',tostring(message):sub(1,160)) end
        end
    end
    function instance.aim(unit,grip)
        if not cache or not grip or cache.unit~=unit or not Unit.alive(cache.muzzle) then return end
        local ok,weapon,template,held=pcall(equipped,unit)
        if not ok or held~=cache.held or template~=cache.template then return end
        return GunAim.resolve(grip,cache.relative:unbox())
    end
    return instance
end
return GunAim
