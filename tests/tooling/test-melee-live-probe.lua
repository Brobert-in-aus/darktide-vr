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
local tracking = {right_grip_usable=true,right_grip_tracking_live=true,body_anchor_qw=1}
local presentation={controller_grip_target=function() return {1,2,3},{0,0,0,1} end}
local live = Live.install(mod,presentation,
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
tracking.right_grip_usable=true
tracking.last_transport_generation=1
tracking.head_recenter_generation=0
live.fixed_update(extension,12,13)
local reference_key=calls[#calls].history_key
tracking.last_sequence=100
live.fixed_update(extension,12.02,14)
assert(calls[#calls].history_key==reference_key,'Ordinary samples must retain sweep history')
tracking.last_transport_generation=2
live.fixed_update(extension,12.04,15)
assert(calls[#calls].history_key~=reference_key,'Publisher replacement retained a cross-reference sweep')
reference_key=calls[#calls].history_key
live.fixed_update(extension,12.06,16)
assert(calls[#calls].history_key==reference_key,'Stable publisher discarded sweep history')
tracking.head_recenter_generation=1
live.fixed_update(extension,12.08,17)
assert(calls[#calls].history_key~=reference_key,'Recenter retained a cross-reference sweep')
reference_key=calls[#calls].history_key
live.fixed_update(extension,12.10,18)
assert(calls[#calls].history_key==reference_key,'Stable recenter discarded sweep history')
local hand='right'
presentation.weapon_hand_roles={physical=function(role) assert(role=='dominant'); return hand end}
presentation.weapon_grip_target=function(role)
    assert(role=='dominant'); return {1,2,3},{0,0,0,1}
end
tracking.left_grip_usable=true
tracking.left_grip_tracking_live=true
live.fixed_update(extension,12.12,19)
assert(calls[#calls].history_key==reference_key)
hand='left'
live.fixed_update(extension,12.14,20)
assert(calls[#calls].history_key~=reference_key and calls[#calls].step.tracking_valid,
    'Changing the physical hand retained the previous hand trajectory')
reference_key=calls[#calls].history_key
live.fixed_update(extension,12.16,21)
assert(calls[#calls].history_key==reference_key)
extension._weapon_action_component.current_action_name='light'
local last_count=#calls
modules.volume.resolve=function() return nil,'invalid_modifiers' end
live.fixed_update(extension,13,22)
assert(#calls==last_count,'Invalid geometry continued querying the cached volume')
modules.volume.resolve=function() return volume end
live.fixed_update(extension,13.02,23)
assert(#calls==last_count+1 and calls[#calls].volume==volume,
    'A restored same-named sweep never recovered its valid volume')
assert(calls[#calls].history_key~=reference_key,'Geometry recovery bridged an invalid-volume interval')
reference_key=calls[#calls].history_key
live.fixed_update(extension,13.04,24)
assert(calls[#calls].history_key==reference_key,'Stable recovered geometry repeatedly discarded history')
-- IK deliberately retains a usable grip pose during tracking loss. Contact
-- queries must use current tracking, not that held presentation fallback.
local grip_reads=0
extension._unit_data_extension.is_resimulating=false
presentation.weapon_grip_target=function()
    grip_reads=grip_reads+1; return {1,2,3},{0,0,0,1}
end
tracking.left_grip_tracking_live=false
live.fixed_update(extension,13.06,25)
assert(tracking.left_grip_usable,'Probe changed the held IK pose policy')
assert(not calls[#calls].step.tracking_valid and not calls[#calls].pose and grip_reads==0,
    'Held IK pose authorized a stale physical-contact sample')
tracking.left_grip_tracking_live=nil
live.fixed_update(extension,13.08,26)
assert(not calls[#calls].step.tracking_valid and grip_reads==0,'Missing live tracking was admitted')
tracking.left_grip_tracking_live=true
live.fixed_update(extension,13.10,27)
assert(calls[#calls].step.tracking_valid and calls[#calls].pose and grip_reads==1)
hand='right'; tracking.right_grip_tracking_live=false
live.fixed_update(extension,13.12,28)
assert(not calls[#calls].step.tracking_valid and grip_reads==1,'Tracking gate ignored the physical hand')
-- Stock ActionWeaponBase retains its owning weapon extension. LuaJIT weak-key
-- tables alone do not collect a key reachable through a strong cached value.
local discarded=setmetatable({weapon},{__mode='v'})
extension._weapons.slot_primary=nil; weapon=nil
collectgarbage(); collectgarbage()
assert(discarded[1]==nil,'Probe retained an unequipped weapon')
local count_before_empty=#calls
live.fixed_update(extension,13.14,29)
assert(#calls==count_before_empty,'Collected weapon identity concealed an empty slot and retained its volume')
weapon={weapon_template={name='replacement',actions={light={kind='sweep'}}},actions={light={_uses_matrix_data=true}}}
extension._weapons.slot_primary=weapon
live.fixed_update(extension,13.16,30)
weapon.actions.light._weapon_extension=extension
local retired=setmetatable({extension,weapon},{__mode='v'})
extension=nil; weapon=nil
collectgarbage(); collectgarbage()
assert(retired[1]==nil and retired[2]==nil,'Diagnostic cache retained a retired weapon extension cycle')
print("live melee diagnostic opt-in, private mode, idle continuity, timing reentry and failure recovery passed")
