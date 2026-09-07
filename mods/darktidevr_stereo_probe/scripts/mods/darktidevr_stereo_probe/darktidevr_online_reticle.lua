-- Preview the stock firing centre without sampling spread or changing actions.
local Reticle = {}
local guns={shoot_hit_scan=true,shoot_pellets=true,shoot_projectile=true}
local direct={spawn_projectile=true,flamer_gas=true,flamer_gas_burst=true,chain_lightning=true}
function Reticle.uses_gun_preparation(template,settings)
    local kind=settings and settings.kind
    if guns[kind] then return true end
    if direct[kind] then return false end
    -- Idle/ADS/reload still need the equipped gun's firing centre. Staff and
    -- flame families retain their own direct first-person damage direction.
    for _,keyword in ipairs(template and template.keywords or {}) do
        if keyword=='force_staff' then return false end
    end
    for _,action in pairs(template and template.actions or {}) do
        if guns[action.kind] then return true end
    end
    return false
end
function Reticle.install(mod,presentation)
    local instance={failures=0}
    local Recoil,Sway,SmartTargeting
    local function pose(ext,t)
        local fp=ext._first_person_component
        if not fp then return end
        local weapon=ext._weapon_extension
        local template=weapon and weapon:weapon_template()
        local settings=weapon and weapon:running_action_settings()
        local rotation=fp.rotation
        if Reticle.uses_gun_preparation(template,settings) then
            Recoil=Recoil or require('scripts/utilities/recoil')
            Sway=Sway or require('scripts/utilities/sway')
            rotation=Recoil.apply_weapon_recoil_rotation(weapon:recoil_template(),
                ext._recoil_component,ext._movement_state_component,
                ext._locomotion_component,ext._inair_state_component,rotation)
            rotation=Sway.apply_sway_rotation(weapon:sway_template(),ext._sway_component,rotation)
            local assist=Managers.input:is_using_gamepad() or
                (ext._buff_extension and ext._buff_extension:has_keyword('enable_auto_aim'))
            if assist and not DevParameters.disable_aim_assist then
                SmartTargeting=SmartTargeting or require('scripts/utilities/smart_targeting')
                local targeting=SmartTargeting.smart_targeting_template(t,
                    ext._weapon_action_component,ext._combat_ability_action_component,
                    ext._grenade_ability_action_component)
                rotation=ext:assisted_hitscan_trajectory(targeting,template,rotation)
            end
        end
        -- Spread and pellet distribution remain random about this centre. Do
        -- not call randomized_spread here: preview must not consume shot RNG.
        return fp.position,rotation
    end
    function instance.pose(ext,t)
        if not presentation.online_rules.simulation_aim_active(ext._unit) then return end
        local ok,position,rotation=pcall(pose,ext,t)
        if ok then return position,rotation end
        instance.failures=instance.failures+1
        if instance.failures==1 then
            mod:warning('DARKTIDEVR_ONLINE_RETICLE fallback=first_person reason=%s',tostring(position))
        end
        local fp=ext._first_person_component
        if fp then return fp.position,fp.rotation end
    end
    return instance
end
return Reticle
