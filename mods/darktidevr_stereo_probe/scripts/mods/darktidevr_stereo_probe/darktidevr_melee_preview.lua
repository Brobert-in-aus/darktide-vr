-- Read-only stock swing geometry. No contacts, damage, action starts or input.
local Preview={}
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function copy(v)
    local x,y,z=Vector3.x(v),Vector3.y(v),Vector3.z(v)
    if not finite(x) or not finite(y) or not finite(z) then return nil end
    return {x=x,y=y,z=z}
end

-- Use a stock-selected idle start action. Do not guess from an action's name
-- or reuse the last observed combo attack. Validation belongs to the caller.
function Preview.first_light(actions,start_name)
    local start=actions and actions[start_name]
    if not start or start.kind~='windup' then return nil,'unsupported_start' end
    local chain=start.allowed_chain_actions and start.allowed_chain_actions.light_attack
    if type(chain)~='table' or #chain>0 or chain.chain_until or
            chain.running_action_state_requirement then return nil,'conditional_chain' end
    local name=chain.action_name
    local action=name and actions[name]
    if not action or action.kind~='sweep' then return nil,'unsupported_swing' end
    return name,action
end

function Preview.sample(instance,origin,rotation)
    local settings=instance and instance._action_settings
    local splines=instance and instance._sweep_splines
    if not settings or settings.kind~='sweep' or settings.sphere_radius or
            not splines or #splines==0 or #splines>8 or not origin or not rotation then
        return nil,'unsupported_geometry'
    end
    local extents=instance:_weapon_half_extents(instance._weapon_template,settings)
    local dimensions=copy(extents)
    if not dimensions or dimensions.x<=0 or dimensions.y<=0 or dimensions.z<=0 then
        return nil,'invalid_extents'
    end
    local paths={}
    for _,spline in ipairs(splines) do
        local frames=spline._num_frames
        if not finite(frames) or frames<2 or frames>256 or frames~=math.floor(frames) then
            return nil,'unsupported_frames'
        end
        local path={}
        for frame=1,frames do
            -- Exact authored damage-window frames, using the same reference
            -- origin/rotation as stock. Copy before engine temporary reuse.
            local position,orientation=spline:position_and_rotation((frame-1)/(frames-1),origin,rotation)
            local base=copy(position)
            local center=instance:_modify_sweep_position(position,orientation,extents,settings)
            local middle=copy(center)
            local tip=copy(instance:_modify_sweep_position(center,orientation,extents,settings))
            if not base or not middle or not tip then return nil,'invalid_sample' end
            path[#path+1]={base=base,center=middle,tip=tip}
        end
        paths[#paths+1]=path
    end
    return {paths=paths,half_extents=dimensions,damage=false,obstruction_tested=false}
end

function Preview.context(extension,presentation,t)
    local handler=extension._action_handler
    if handler:running_action_name('weapon_action') then return nil,'action_running' end
    local slot=extension._inventory_component.wielded_slot
    local weapon=extension._weapons[slot]
    local template=weapon and weapon.weapon_template
    if not template or not template.actions then return nil,'missing_weapon' end
    local params=extension:condition_func_params(slot)
    local start=handler:_valid_action_from_action_input(template.actions,'start_attack',t,0,params,nil)
    local name,settings=Preview.first_light(template.actions,start)
    if not name then return nil,settings end
    if not handler:_validate_action(settings,params,t,0,nil) then return nil,'unavailable_swing' end
    local instance=weapon.actions and weapon.actions[name]
    local component=instance and instance._first_person_component
    if not component then return nil,'missing_instance' end
    local rotation
    if presentation.online_rules.simulation_aim_active(extension._unit) then
        rotation=component.rotation
    else
        local ignored
        ignored,rotation=presentation.controller_aim.target('dominant')
    end
    if not rotation then return nil,'missing_aim' end
    local result,reason=Preview.sample(instance,component.position,rotation)
    if result then result.action_name=name end
    return result,reason
end

return Preview
