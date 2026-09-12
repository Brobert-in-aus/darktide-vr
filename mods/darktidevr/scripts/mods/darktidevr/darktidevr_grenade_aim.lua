local Grenade = {}
local Action = require("scripts/utilities/action/action")
local function pack(...) return {n=select("#",...),...} end
local luggables = {luggable=true,luggable_light=true,luggable_mission=true}

function Grenade.supported(template,settings)
    if not template or not settings or settings.spawn_node then return false end
    for _,keyword in ipairs(template.keywords or {}) do
        if keyword=="grenade" then
            return (settings.kind=="aim_projectile" or settings.kind=="throw_grenade") and
                (settings.throw_type=="throw" or settings.throw_type=="underhand_throw")
        elseif keyword=="luggable" and luggables[template.name] then
            -- ThrowLuggable consumes the cached aim unchanged after its stock
            -- delay. Author that cache and its preview together; drops keep
            -- the stock near-feet physics path and are never pose-substituted.
            return settings.kind=="aim_projectile" and settings.throw_type=="throw"
        end
    end
    return false
end

function Grenade.install(mod,aim,simulation_preview_pose)
    -- Inherited methods are copied into concrete Stingray classes. Load both
    -- before hooking, then patch the concrete luggable preview as well.
    local effects={
        require("scripts/extension_systems/visual_loadout/wieldable_slot_scripts/aim_projectile_effects"),
        require("scripts/extension_systems/visual_loadout/wieldable_slot_scripts/aim_luggable_effects"),
    }
    local function action_pose(func,self,...)
        local player=Managers and Managers.player and Managers.player:local_player(1)
        if not player or player.player_unit~=self._player_unit or
                not Grenade.supported(self._weapon_template,self._action_settings) then
            return func(self,...)
        end
        local position,rotation=aim.target("dominant")
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

    local function trajectory_pose(func,self,settings,...)
            local component,actions=self._weapon_action_component,self._weapon_actions
            local action_settings=component and actions and
                Action.current_action_settings_from_component(component,actions)
            if not self._is_local_unit or not self._first_person_unit or not settings or
                    not Grenade.supported(self._weapon_template,action_settings) then
                return func(self,settings,...)
            end
            -- Online-rules actions keep their stock simulation components.
            -- Their rendered first-person root still follows the head, so the
            -- visual arc needs the simulated pose independently of hand proxies.
            local position,rotation
            if simulation_preview_pose then position,rotation=simulation_preview_pose(self) end
            if not position or not rotation then position,rotation=aim.target("dominant") end
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
    end
    for _,class in ipairs(effects) do mod:hook(class,"_update_trajectory",trajectory_pose) end
end

return Grenade
