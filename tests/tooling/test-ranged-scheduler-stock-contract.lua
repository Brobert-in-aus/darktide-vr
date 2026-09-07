-- Optional stock-source scheduler contract. No engine, damage, action hierarchy
-- or live weapon acceptance. Preparation/dispatch are observations, not physics.
local root=assert(arg[1])..'/scripts/'
local function read(path)
    local f=assert(io.open(root..path..'.lua','rb'))
    local text=f:read('*a'); f:close(); return text
end
local function section(text,first,last)
    local a=assert(text:find(first,1,true),first)
    local b=assert(text:find(last,a+1,true),last)
    return text:sub(a,b-1)
end
math.round=function(n) return math.floor(n+.5) end
math.lerp=function(a,b,t) return a+(b-a)*t end
math.index_wrapper=function(i,n) return (i-1)%n+1 end
table.clear=function(t) for k in pairs(t) do t[k]=nil end end
Managers={state={game_session={fixed_time_step=1/60}},stats={record_private=function() end}}
FixedFrame=assert(loadstring(read('utilities/fixed_frame')))()
ActionShoot={}
ActionUtility={}
-- Inventory storage is a fixture. The actual stock admission and spending
-- logic below decide availability and cost; this is a single ammo pool.
Ammo={current_ammo_in_clips=function(slot) return slot.clip end,
    set_current_ammo_in_clips=function(slot,n) slot.clip=n end}
assert(loadstring(section(read('extension_systems/weapon/actions/utilities/action_utility'),
    'ActionUtility.has_ammunition =','\nlocal EPSILON')))()
MultiFireModes={single=1,alternating=2,simultaneous=3}
buff_keywords={no_ammo_consumption='free',no_ammo_consumption_on_crits='free_crit',
    double_ammo_consumption='double',reduced_ammo_consumption='reduced'}
proc_events={on_ammo_consumed='ammo'}
DEFAULT_POWER_LEVEL=500
EMPTY_TABLE={}
local text=read('extension_systems/weapon/actions/action_shoot')
assert(loadstring(section(text,'ActionShoot.fixed_update =','\nActionShoot._prepare_fire_config =')))()
assert(loadstring(section(text,'ActionShoot._spend_ammunition =','\nActionShoot._add_heat =')))()
assert(loadstring(section(text,'ActionShoot._has_ammo =','\nfunction _set_charge_level')))()
local function noop() end
local function make(options)
    local s=setmetatable({}, {__index=ActionShoot})
    s._action_settings={ammunition_usage=options.cost or 1,
        allow_shots_with_less_than_required_ammo=options.allow_partial,
        use_charge=options.charge~=nil,ammunition_usage_min=1,ammunition_usage_max=5}
    s._action_component={fire_state='waiting_to_shoot',fire_at_time=.1,
        current_fire_config=1,num_shots_fired=0}
    s._is_auto_fire_weapon=options.auto~=false
    s._base_fire_configurations={{}}
    s._multi_fire_mode=MultiFireModes.single
    s._inventory_slot_component={clip=options.ammo or 20,
        current_ammunition_reserve=options.reserve or 0,
        free_ammunition_transfer=options.free_transfer or false}
    s._inventory_component={wielded_slot='slot_secondary'}
    s._critical_strike_component={is_active=options.critical or false}
    s._unit_data_extension={is_resimulating=options.replay or false}
    s._shot_result={old=true}
    s._buff_extension={has_keyword=function(_,k) return (options.keywords or {})[k] end,
        stat_buffs=function() return {ranged_attack_speed=options.speed or 1,attack_speed=1} end,
        request_proc_event_param_table=function() end}
    s._weapon_extension={weapon_handling_template=function()
        return {fire_rate={auto_fire_time=options.auto~=false and .1 or nil,max_shots=3}}
    end}
    s._set_fire_state=function(self,_,name) self._action_component.fire_state=name end
    s._update_delta_charge=noop
    s._add_heat=noop; s._pay_warp_charge_cost_immediate=noop
    s._trigger_new_charge=noop; s._handle_shot_concluded_stats=noop
    s.prepared={}; s.dispatched={}
    s._prepare_shooting=function(self,_,t)
        local a=self._action_component
        a.num_shots_fired=a.num_shots_fired+1
        a.shooting_position='stock_body_origin'
        a.shooting_rotation=t -- distinct pose on each preparation frame
        a.shooting_charge_level=options.charge or 0
        self.prepared[#self.prepared+1]=t
    end
    s._shoot=function(self,position,rotation,power,charge,t)
        assert(position=='stock_body_origin' and rotation==t)
        assert(charge==(options.charge or 0) and power==DEFAULT_POWER_LEVEL)
        assert(next(self._shot_result)==nil,'stock must clear prior shot results')
        self._shot_result.observed=true
        self.dispatched[#self.dispatched+1]=t
    end
    return s
end
local cases=0
local scenarios={
    {name='single',auto=false,shots=1,remaining=19},
    {name='automatic',shots=3,remaining=17},
    {name='ammo_exhausted',ammo=2,shots=2,remaining=0},
    {name='empty',ammo=0,shots=0,remaining=0},
    {name='reload_needed',ammo=0,reserve=5,shots=0,remaining=0,reload=true},
    {name='free_transfer',ammo=0,free_transfer=true,shots=0,remaining=0,reload=true},
    {name='insufficient',ammo=2,cost=3,shots=0,remaining=2},
    {name='partial_allowed',ammo=2,cost=3,allow_partial=true,shots=1,remaining=0},
    {name='free_buff',ammo=0,keywords={free=true},shots=3,remaining=0},
    {name='free_critical',ammo=0,critical=true,keywords={free_crit=true},shots=3,remaining=0},
    {name='no_free_noncritical',ammo=0,keywords={free_crit=true},shots=0,remaining=0},
    {name='double_cost',keywords={double=true},shots=3,remaining=14},
    {name='half_charge',charge=.5,shots=3,remaining=11},
    {name='full_charge',charge=1,shots=3,remaining=5},
    {name='resimulation',replay=true,shots=0,remaining=17,preparations=3},
}
for _,hz in ipairs({30,60,90}) do
    for _,speed in ipairs({.75,1,1.5}) do
        Managers.state.game_session.fixed_time_step=1/hz
        for _,options in ipairs(scenarios) do
            options.speed=speed
            local s=make(options)
            local reload=false
            for frame=1,2*hz do
                local result=s:fixed_update(1/hz,frame/hz,frame/hz,frame)
                if result then reload=true; break end
            end
            local label=options.name..'/'..hz..'/'..speed
            assert(#s.dispatched==options.shots,label..' shot count '..#s.dispatched)
            assert(#s.prepared==(options.preparations or options.shots),label..' preparations')
            assert(s._inventory_slot_component.clip==options.remaining,label..' remaining ammo')
            assert(reload==(options.reload or false),label..' reload gate')
            local interval=FixedFrame.clamp_to_fixed_time(.1/speed)
            for i,t in ipairs(s.prepared) do
                assert(t>=.1,label..' early shot')
                if i>1 then
                    local elapsed=t-s.prepared[i-1]
                    assert(elapsed>=interval-1e-8 and elapsed<=interval+1/hz+1e-8,label..' cadence')
                end
            end
            cases=cases+1
        end
    end
end
print('PASS stock ranged scheduler: '..cases..' fixed-rate/buff/scenario combinations; cadence, fresh pose, ammo, charge and replay')
print('LIMIT: supplied settings; single ammo pool; preparation/dispatch and secondary effects substituted; no action hierarchy, damage, pellet batching or live acceptance')
