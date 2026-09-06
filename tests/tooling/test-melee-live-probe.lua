local Live = dofile(arg[1])
local flag, mode, calls, crash = false, "shooting_range", {}, false
local player = {player_unit={}}
local player_position={9,8,7}
POSITION_LOOKUP={[player.player_unit]=player_position}
Managers = {player={local_player=function() return player end}}
Mods = {lua={io={open=function()
    return {read=function() return flag and "enabled" or "disabled" end,close=function() end}
end}}}
package.preload["scripts/settings/equipment/action_sweep_settings"] = function() return {} end
Vector3 = {x=function(p) return p[1] end,y=function(p) return p[2] end,z=function(p) return p[3] end}
Quaternion = {to_elements=function(q) return unpack(q) end}
local volume = {shape="oobb",corner_radius=1}
local modules = {simulation={},sweep_plan={},probe={},timing={},hit_zone={},contacts={},volume={resolve=function() return volume end},
    diagnostics={new=function() return {} end,sample=function(_,request)
        calls[#calls+1] = request
        if crash then error("fixture failure") end
        return {plan={reason="fixture"},overlap={actor_count=0},contacts={},query_count=1}
    end}}
local warnings = 0
local selections = 0
modules.diagnostics.select_contacts=function(report,resolver,collector,context)
    selections=selections+1
    assert(report.contacts and resolver==modules.hit_zone and collector==modules.contacts)
    assert(context.attacker==player.player_unit and context.attacker_position==player_position)
    assert(context.action.kind=='sweep' and context.target_key(player)==player)
    return {selected={{hit_zone='shield'}},unresolved={{reason='unresolved_hit_zone'}}}
end
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
assert(selections==1,'live result did not reach contact selection')
local key = calls[1].history_key
extension._weapon_action_component.current_action_name = "none"
live.fixed_update(extension,3,3)
assert(#calls == 2 and calls[2].history_key == key) -- Remains active while idle.
assert(selections==1,'selection ignored five-second diagnostic cadence')
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
local timing_calls, graph_calls, effective_scale = 0,0,1
modules.timing.from_windup=function(_,name,scale_for,_,validate)
    timing_calls=timing_calls+1
    assert(name=='windup' and validate({}) and scale_for({})==effective_scale)
    return {light_action='light',heavy_action='heavy',light_interval=.5/effective_scale,heavy_charge=.5}
end
modules.timing.light_combo=function()
    graph_calls=graph_calls+1
    return {steps={{light_action='light',interval=.5/effective_scale}},
        cycle_start=1,entry_duration=0,cycle_duration=.5/effective_scale}
end
weapon.weapon_template.actions.windup={kind='windup'}
extension._action_handler={_calculate_time_scale=function() return effective_scale end,
    _validate_action=function() return true end}
extension.condition_func_params=function() return {} end
extension._weapon_action_component.current_action_name='windup'
extension._weapon_action_component.start_t=10
live.fixed_update(extension,10,10)
live.fixed_update(extension,10.1,11)
assert(timing_calls==1 and graph_calls==1,'same windup tick repeated timing resolution')
effective_scale=2
extension._weapon_action_component.start_t=11
live.fixed_update(extension,11,12)
assert(timing_calls==2 and graph_calls==2,'same-named new windup missed speed refresh')
print("live melee diagnostic opt-in, private mode, idle continuity, timing reentry and failure recovery passed")
