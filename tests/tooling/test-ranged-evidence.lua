local Evidence=dofile(assert(arg[1]))
local meta={}
Vector3=setmetatable({x=function(v) return v[1] end,y=function(v) return v[2] end,z=function(v) return v[3] end},
    {__call=function(_,x,y,z) return setmetatable({x,y,z},meta) end})
meta.__sub=function(a,b) return Vector3(a[1]-b[1],a[2]-b[2],a[3]-b[3]) end
Vector3.dot=function(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
Vector3.length_squared=function(v) return Vector3.dot(v,v) end
Vector3.normalize=function(v) local n=math.sqrt(Vector3.length_squared(v)); return Vector3(v[1]/n,v[2]/n,v[3]/n) end
Quaternion={forward=function(rotation) return rotation end}
local classes={}
local base='scripts/extension_systems/weapon/actions/'
for _,name in ipairs({'action_shoot_hit_scan','action_shoot_pellets','action_shoot_projectile','action_flamer_gas','action_flamer_gas_burst'}) do
    local class={_shoot=function(self,position,rotation,power,charge,t)
        self.stock_calls=self.stock_calls+1
        self._shot_result={data_valid=true,hit_minion=true}
        return nil,123
    end}
    classes[name]=class; package.loaded[base..name]=class
end
Managers={state={game_session={}}}
local logs,commands={},{}
local mod={info=function(_,format,...) logs[#logs+1]=string.format(format,...) end,
    echo=function() end,command=function(_,name,_,callback) commands[name]=callback end,
    hook_safe=function(_,class,method,callback)
        local original=class[method]
        class[method]=function(self,...)
            local a,b=original(self,...); callback(self,...); return a,b
        end
    end}
local presentation={online_rules={simulation_aim_active=function(unit) return unit=='local' end},
    controller_aim={cached_reticle_target=function() return {unbox=function() return Vector3(0,10,0) end} end,
        third_person_muzzle=function(_,count) assert(count==0); return Vector3(.3,0,0),Vector3(0,1,0) end}}
local instance=Evidence.install(mod,presentation)
local action={_player_unit='local',_is_server=true,_weapon_template={name='fixture_gun'},
    _action_settings={kind='shoot_hit_scan'},_action_component={num_shots_fired=1},stock_calls=0}
for _,class in pairs(classes) do
    local a,b=class._shoot(action,Vector3(0,0,0),Vector3(0,1,0),100,.5,12)
    assert(a==nil and b==123 and action._shot_result.hit_minion,'observer altered stock return/results')
end
assert(action.stock_calls==5 and #logs==4,'diagnostic was not bounded')
assert(logs[1]:find('weapon=fixture_gun',1,true) and logs[1]:find('shot_vs_reticle_deg=0.000',1,true))
assert(logs[1]:find('hit_minion=true',1,true))
assert(logs[1]:find('muzzle=0.3000,0.0000,0.0000',1,true))
action._player_unit='remote'; instance.observe(action); assert(#logs==4)
action._player_unit='local'; action._unit_data_extension={is_resimulating=true}
instance.observe(action); assert(#logs==4)
action._unit_data_extension.is_resimulating=false
Managers.state.game_session={}; instance.observe(action,Vector3(0,0,0),Vector3(1,0,0),100,.5,12)
assert(#logs==5 and logs[5]:find('shot_vs_reticle_deg=90.000',1,true),'visit did not reset or angular evidence changed')
presentation.controller_aim.cached_reticle_target=function() error('retired target') end
instance.observe(action,Vector3(0,0,0),Vector3(0,1,0))
instance.observe(action,Vector3(0,0,0),Vector3(0,1,0))
assert(instance.failures==2 and #logs==6,'failure created repeating error messages')
commands.dtvr_ranged_evidence()
print('PASS ranged evidence: five dispatch hooks, stock nil returns/results, bounded output, angular evidence, remote/replay/visit guards and failure isolation')
