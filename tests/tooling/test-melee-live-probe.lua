local Live = dofile(arg[1])
local flag, mode, calls, crash = false, "shooting_range", {}, false
local player = {player_unit={}}
Managers = {player={local_player=function() return player end}}
Mods = {lua={io={open=function()
    return {read=function() return flag and "enabled" or "disabled" end,close=function() end}
end}}}
package.preload["scripts/settings/equipment/action_sweep_settings"] = function() return {} end
Vector3 = {x=function(p) return p[1] end,y=function(p) return p[2] end,z=function(p) return p[3] end}
Quaternion = {to_elements=function(q) return unpack(q) end}
local volume = {shape="oobb",corner_radius=1}
local modules = {simulation={},sweep_plan={},probe={},timing={},volume={resolve=function() return volume end},
    diagnostics={new=function() return {} end,sample=function(_,request)
        calls[#calls+1] = request
        if crash then error("fixture failure") end
        return {plan={reason="fixture"},overlap={actor_count=0},contacts={},query_count=1}
    end}}
local warnings = 0
local mod = {io_dofile=function(_,path) return assert(modules[path:match("melee_(.+)$")]) end,
    info=function() end,warning=function() warnings=warnings+1 end}
local tracking = {right_grip_usable=true,body_anchor_qw=1}
local live = Live.install(mod,{controller_grip_target=function() return {1,2,3},{0,0,0,1} end},
    tracking,function() return mode end)
local weapon = {weapon_template={name="fixture",actions={light={kind="sweep"}}},actions={light={_uses_matrix_data=true}}}
local extension = {_unit=player.player_unit,_inventory_component={wielded_slot="slot_primary"},
    _weapons={slot_primary=weapon},_weapon_action_component={current_action_name="light"},
    _unit_data_extension={is_resimulating=false},_physics_world={}}
live.fixed_update(extension,0,0)
assert(#calls == 0)
flag = true
mode = "hub"
live.fixed_update(extension,1,1)
assert(#calls == 0)
mode = "shooting_range"
live.fixed_update(extension,2,2)
assert(#calls == 1 and calls[1].volume == volume and calls[1].step.tracking_valid)
local key = calls[1].history_key
extension._weapon_action_component.current_action_name = "none"
live.fixed_update(extension,3,3)
assert(#calls == 2 and calls[2].history_key == key) -- Remains active while idle.
tracking.right_grip_usable = false
extension._unit_data_extension.is_resimulating = true
live.fixed_update(extension,4,4)
assert(not calls[3].step.tracking_valid and calls[3].step.resimulating and not calls[3].pose)
extension._weapons.slot_primary = nil
live.fixed_update(extension,5,5)
assert(#calls == 3) -- Old volume cannot follow a weapon swap.
extension._weapons.slot_primary = weapon
extension._weapon_action_component.current_action_name = "light"
crash = true
live.fixed_update(extension,6,6)
assert(warnings == 1)
live.fixed_update(extension,7,7)
assert(warnings == 1 and #calls == 4) -- Latch instead of exception storm.
flag = false
live.fixed_update(extension,8,8)
flag, crash = true, false
live.fixed_update(extension,9,9)
assert(#calls == 5)
print("live melee diagnostic opt-in, private mode, idle continuity and failure recovery passed")
