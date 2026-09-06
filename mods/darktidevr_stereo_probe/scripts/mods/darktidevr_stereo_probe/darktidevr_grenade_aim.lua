local Grenade = {}
local Action = require("scripts/utilities/action/action")
local function pack(...) return {n=select("#",...),...} end

function Grenade.supported(template,settings)
    if not template or not settings or settings.spawn_node or
            (settings.kind~="aim_projectile" and settings.kind~="throw_grenade") or
            (settings.throw_type~="throw" and settings.throw_type~="underhand_throw") then
        return false
    end
    for _,keyword in ipairs(template.keywords or {}) do
        if keyword=="grenade" then return true end
    end
    return false
end

function Grenade.install(mod,aim)
    local function action_pose(func,self,...)
        local player=Managers and Managers.player and Managers.player:local_player(1)
        if not player or player.player_unit~=self._player_unit or
                not Grenade.supported(self._weapon_template,self._action_settings) then
            return func(self,...)
        end
        local position,rotation=aim.target("right")
        local previous=self._first_person_component
        if not previous or not position or not rotation then return func(self,...) end
        self._first_person_component=setmetatable({position=position,rotation=rotation},
            {__index=function(_,key) return previous[key] end})
        local result=pack(pcall(func,self,...))
        self._first_person_component=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
    mod:hook(require("scripts/extension_systems/weapon/actions/action_aim_projectile"),
        "fixed_update",action_pose)
    mod:hook(require("scripts/extension_systems/weapon/actions/action_throw_grenade"),
        "_spawn_projectile",action_pose)

    mod:hook(require("scripts/extension_systems/visual_loadout/wieldable_slot_scripts/aim_projectile_effects"),
        "_update_trajectory",function(func,self,settings,...)
            local component,actions=self._weapon_action_component,self._weapon_actions
            local action_settings=component and actions and
                Action.current_action_settings_from_component(component,actions)
            if not self._is_local_unit or not self._first_person_unit or not settings or
                    not Grenade.supported(self._weapon_template,action_settings) then
                return func(self,settings,...)
            end
            local position,rotation=aim.target("right")
            if not position or not rotation then return func(self,settings,...) end
            local trajectory={}
            for key,value in pairs(settings) do trajectory[key]=value end
            -- Stock cosmetic offsets move the start of the arc away from the
            -- simulated path. In VR start it at the actual hand-based spawn.
            trajectory.start_offset=nil
            trajectory.arc_vfx_spawner_name=nil
            local unit=self._first_person_unit
            local world_position,world_rotation=Unit.world_position,Unit.world_rotation
            -- The stock arc reads native Unit accessors, not action components.
            -- Redirect only this root node during the synchronous arc call;
            -- all other nodes/units delegate and there is no permanent hot hook.
            Unit.world_position=function(target,node,...)
                if target==unit and node==1 then return position end
                return world_position(target,node,...)
            end
            Unit.world_rotation=function(target,node,...)
                if target==unit and node==1 then return rotation end
                return world_rotation(target,node,...)
            end
            local result=pack(pcall(func,self,trajectory,...))
            Unit.world_position,Unit.world_rotation=world_position,world_rotation
            if not result[1] then error(result[2],0) end
            return unpack(result,2,result.n)
        end)
end

return Grenade
