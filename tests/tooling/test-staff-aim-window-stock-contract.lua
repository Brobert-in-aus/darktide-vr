-- Optional stock-source timing probe. No game, graphics, network or damage.
local root=assert(arg[1],'Pass the audited Darktide source root')
local function read(path)
    local file=assert(io.open(root..'/'..path,'r'))
    local source=file:read('*all'); file:close(); return source
end
local source=read('scripts/extension_systems/weapon/actions/action_spawn_projectile.lua')
local first=assert(source:find('ActionSpawnProjectile.fixed_update = function',1,true))
local last=assert(source:find('ActionSpawnProjectile.finish = function',first,true))
local environment={ActionSpawnProjectile={},DEFAULT_FIRE_TIME=.1,
    ActionUtility={is_within_trigger_time=function() return false end}}
setmetatable(environment,{__index=_G})
local chunk=assert(loadstring(source:sub(first,last-1)))
setfenv(chunk,environment); chunk()
local fixed_update=environment.ActionSpawnProjectile.fixed_update
local template=read('scripts/settings/equipment/weapon_templates/force_staffs/forcestaff_p4_m1.lua')
local function fire_time(action)
    local start=assert(template:find('\n\t'..action..' = {',1,true))
    return assert(tonumber(template:sub(start):match('fire_time = ([%d.]+)')))
end
local ordinary,charged=fire_time('rapid_left'),fire_time('action_shoot_charged')
assert(ordinary==.1 and charged==.2,'Reaudit changed staff timings')
local runs,late_samples,total_samples=0,0,0
for _,delay in ipairs({ordinary,charged}) do
    for _,scale in ipairs({1,1.5}) do
        for _,rewind in ipairs({0,.05,.1}) do
            for _,count in ipairs({1,2}) do
                for _,policy in ipairs({'trigger_only','action_window'}) do
                    local samples={}
                    local owner={_action_settings={fire_time=delay},
                        _weapon_action_component={time_scale=scale},_is_server=true,
                        _player={remote=true,lag_compensation_rewind_s=function() return rewind end},
                        _projectiles_fire_offsets={},_projectiles_fired={},
                        _projectile_units={},_projectile_locomotion_extensions={},
                        _first_person_component={},
                    }
                    for i=1,count do
                        owner._projectiles_fire_offsets[i]=(i-1)*.1
                        owner._projectiles_fired[i]=false
                        owner._projectile_units[i]=i
                        owner._projectile_locomotion_extensions[i]={}
                    end
                    -- Stand-in only for launch dispatch: the production method
                    -- reads first_person.rotation there. This probe establishes
                    -- scheduling, not transforms, server validation or impacts.
                    owner._fire_projectile=function(self,t,unit)
                        samples[#samples+1]={t=t,aim=self._first_person_component.rotation,unit=unit}
                    end
                    local dt=1/60
                    for frame=0,60 do
                        owner._first_person_component.rotation=
                            (policy=='action_window' or frame==0) and 'hand' or 'head'
                        fixed_update(owner,dt,frame*dt,frame*dt)
                    end
                    assert(#samples==count,'Stock launch count changed')
                    for _,sample in ipairs(samples) do
                        total_samples=total_samples+1
                        if policy=='action_window' then
                            assert(sample.aim=='hand','Action window missed a scheduled launch')
                        elseif sample.t>0 then
                            assert(sample.aim=='head')
                            late_samples=late_samples+1
                        else
                            assert(sample.aim=='hand')
                        end
                    end
                    runs=runs+1
                end
            end
        end
    end
end
assert(late_samples>0,'Trigger-frame mismatch was not reproduced')
print(string.format('staff_aim_window=pass runs=%d dispatched_samples=%d trigger_only_late_samples=%d ordinary_delay=%.1f charged_delay=%.1f',
    runs,total_samples,late_samples,ordinary,charged))
print('limits=60Hz_fixture start_and_finish_not_executed firing_dispatch_substitute no_wire_or_impact_validation')
