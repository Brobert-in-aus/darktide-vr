-- Execute the stock sweep update with authored-spline/physics sinks. Tests
-- reference ownership and damage-window dispatch, not collisions or damage.
local root=assert(arg[1])
local path=root..'/scripts/extension_systems/weapon/actions/action_sweep.lua'
local f=assert(io.open(path,'r')); local source=f:read('*a'); f:close()
local first=assert(source:find('ActionSweep._update_sweep =',1,true))
local last=assert(source:find('\nActionSweep._any_sweep_aborted =',first,true))
local Sweep={}
setfenv(assert(loadstring(source:sub(first,last-1),'@'..path)),
    setmetatable({ActionSweep=Sweep},{__index=_G}))()
local samples,overlaps,exits,procs={},{},0,0
local aborted=false
local component={position='stock_origin_A',rotation='recorded_aim_A'}
local reference={reference_position='old_origin',reference_rotation='old_aim'}
local settings={}
local spline={position_and_rotation=function(_,phase,position,rotation)
    local value={phase=phase,position=position,rotation=rotation}
    samples[#samples+1]=value
    return value,rotation
end}
local self=setmetatable({_first_person_component=component,
    _weapon_action_component={time_scale=1,special_active_at_start=false},
    _action_sweep_component=reference,_sweep_splines={spline},_num_hit_enemies=0,
    _is_within_damage_window=function(_,time)
        return time>=.3 and time<=.5,(time-.3)/.2,time<.3,.2
    end,
    _all_sweeps_aborted=function() return aborted end,
    _is_sweep_aborted=function() return aborted end,
    _any_sweep_aborted=function() return aborted end,
    _do_overlap=function(_,t,a,ar,b,br,final,action,index)
        overlaps[#overlaps+1]={a=a,b=b,ar=ar,br=br,final=final}
        assert(action==settings and index==1)
    end,
    _exit_damage_window=function() exits=exits+1 end,
    _is_currently_sticky=function() return false end,
    _handle_exit_procs=function() procs=procs+1 end}, {__index=Sweep})
self:_update_sweep(.02,.2,.2,settings)
assert(#samples==0 and #overlaps==0)
assert(reference.reference_position=='stock_origin_A' and reference.reference_rotation=='recorded_aim_A')
component.position='stock_origin_B'; component.rotation='recorded_aim_B'
self:_update_sweep(.02,.31,.31,settings)
assert(#samples==2 and #overlaps==1)
assert(samples[1].phase==0 and samples[1].position=='stock_origin_A' and samples[1].rotation=='recorded_aim_A')
assert(math.abs(samples[2].phase-.05)<1e-12 and samples[2].position=='stock_origin_B')
assert(samples[2].rotation=='recorded_aim_B' and not overlaps[1].final)
assert(reference.reference_rotation=='recorded_aim_B')
component.position='stock_origin_C'; component.rotation='recorded_aim_C'
self:_update_sweep(.02,.33,.33,settings)
assert(samples[3].rotation=='recorded_aim_B' and samples[4].rotation=='recorded_aim_C',
    'Stock sweep latched attack-start aim instead of consuming recorded current aim')
self:_update_sweep(.03,.52,.52,settings)
assert(samples[6].phase==1 and overlaps[3].final and exits==1 and procs==1)
assert(reference.sweep_state=='after_damage_window')
self:_update_sweep(.03,.55,.55,settings)
assert(#overlaps==3 and exits==1 and procs==1,'After-window update repeated overlap/exit')
aborted=true
self:_update_sweep(.02,.4,.4,settings)
assert(#overlaps==3,'Aborted sweep issued another overlap')
print('melee_reference_stock=pass prewindow first_frame previous_current_aim final_frame exit_once aborted')
print('LIMIT: synthetic recorded poses and spline/physics sinks; no RPC precision, live authority or hit validation')
