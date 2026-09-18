-- Bounded observation after stock dispatch. No input, action, pose or hit writes.
--
-- The detail is capped per weapon route because four shots show the geometry
-- and four hundred show it four hundred times. The COUNT is not capped, and
-- that distinction was bought the hard way: on 18 September the gun stopped
-- producing bullets mid-session while the trigger, the sound and the animation
-- all still worked, and the log could not answer whether a shot had been
-- dispatched at all, because the last line it wrote was the fourth, four
-- minutes before the fault. "No line" meant "capped", not "no shot", so the
-- one question that mattered had no answer in a 13,000 line log.
--
-- So past the cap a compact line still goes out, throttled by time rather than
-- by count: enough that a burst of fire always leaves a mark, few enough that
-- holding down an autogun does not fill the file.
local Evidence={}
local DETAIL_SHOTS=4
local SUMMARY_SECONDS=5
-- The count throttle used when there is no usable clock. Chosen so a fast
-- weapon still writes a line every couple of seconds rather than per shot.
local SUMMARY_SHOTS=20
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function vector_text(v)
    if not v then return 'unavailable' end
    local x,y,z=Vector3.x(v),Vector3.y(v),Vector3.z(v)
    if not finite(x) or not finite(y) or not finite(z) then return 'invalid' end
    return string.format('%.4f,%.4f,%.4f',x,y,z)
end
function Evidence.install(mod,presentation)
    local instance={rows={},failures=0,total=0}
    instance.hits=mod:io_dofile('darktidevr/scripts/mods/darktidevr/darktidevr_hit_evidence').install(mod,presentation)
    local owner,session
    local function observe(action,position,rotation,power,charge,t)
        if not presentation.online_rules.simulation_aim_active(action._player_unit) or
                (action._unit_data_extension and action._unit_data_extension.is_resimulating) then return end
        -- The same dispatch drives the immersive shot vibration (one hook per method).
        if presentation.haptics and presentation.haptics.shot then pcall(presentation.haptics.shot,action) end
        local current_session=Managers.state.game_session
        if owner~=action._player_unit or session~=current_session then
            owner,session,instance.rows=action._player_unit,current_session,{}
        end
        local template=action._weapon_template
        local weapon=tostring(template and template.name or 'unknown')
        local kind=tostring(action._action_settings and action._action_settings.kind or action.__class_name or 'unknown')
        local key=weapon..'/'..kind
        local row=instance.rows[key]
        if not row then row={calls=0} instance.rows[key]=row end
        row.calls=row.calls+1
        instance.total=instance.total+1
        if row.calls>DETAIL_SHOTS then
            -- Past the detail cap. A count and a time, so a later reader can
            -- ask "did anything fire here" and get an answer.
            -- An unusable time falls back to counting rather than logging.
            -- Written the other way round -- "unknown time, log anyway" -- it
            -- also stored nil, so a single bad `t` disarmed the throttle
            -- permanently and a fast weapon then wrote a line per shot for the
            -- rest of the session (review, 18 September).
            local now=type(t)=='number' and t==t and t or nil
            local due
            if now then due=row.summary_t==nil or now>=row.summary_t+SUMMARY_SECONDS
            else due=row.calls-(row.summary_calls or DETAIL_SHOTS)>=SUMMARY_SHOTS end
            if due then
                row.summary_t=now or row.summary_t
                local since=row.calls-(row.summary_calls or DETAIL_SHOTS)
                row.summary_calls=row.calls
                mod:info('DARKTIDEVR_RANGED_EVIDENCE weapon=%s kind=%s dispatches=%d since_last=%d time=%s',
                    weapon,kind,row.calls,since,tostring(t))
            end
            return
        end
        local direction=rotation and Quaternion.forward(rotation)
        local aim=presentation.controller_aim
        local point=aim and aim.cached_reticle_target()
        local angle='unavailable'
        if point and position and direction then
            local toward=point:unbox()-position
            if Vector3.length_squared(toward)>1e-8 then
                local dot=Vector3.dot(Vector3.normalize(toward),Vector3.normalize(direction))
                if finite(dot) then angle=string.format('%.3f',math.deg(math.acos(math.max(-1,math.min(1,dot))))) end
            end
        end
        local result=action._shot_result
        local hit=result and result.data_valid and tostring(result.hit_minion==true) or 'unknown'
        local action_name=action._weapon_action_component and action._weapon_action_component.current_action_name
        local muzzle,muzzle_rotation
        if aim and aim.third_person_muzzle then
            local fired=action._action_component and action._action_component.num_shots_fired
            -- Stock preparation has already advanced this count; observe the
            -- barrel used by this shot, not the next alternating muzzle.
            muzzle,muzzle_rotation=aim.third_person_muzzle(action,finite(fired) and math.max(0,fired-1) or nil)
        end
        local muzzle_direction=muzzle_rotation and Quaternion.forward(muzzle_rotation)
        mod:info('DARKTIDEVR_RANGED_EVIDENCE weapon=%s kind=%s action=%s dispatch=%d authority=%s time=%s charge=%s origin=%s direction=%s shot_vs_reticle_deg=%s hit_minion=%s muzzle=%s muzzle_node_forward=%s',
            weapon,kind,tostring(action_name or 'unknown'),row.calls,
            action._is_server and 'server' or 'client',tostring(t),tostring(charge),
            vector_text(position),vector_text(direction),angle,hit,
            vector_text(muzzle),vector_text(muzzle_direction))
    end
    function instance.observe(...)
        local ok,message=pcall(observe,...)
        if not ok then
            instance.failures=instance.failures+1
            if instance.failures==1 then
                -- Diagnostic failure must not create repeating audible mod errors.
                pcall(mod.info,mod,'DARKTIDEVR_RANGED_EVIDENCE unavailable=%s',tostring(message):sub(1,160))
            end
        end
    end
    for _,name in ipairs({'action_shoot_hit_scan','action_shoot_pellets','action_shoot_projectile',
            'action_flamer_gas','action_flamer_gas_burst'}) do
        mod:hook_safe(require('scripts/extension_systems/weapon/actions/'..name),'_shoot',instance.observe)
    end
    mod:command('dtvr_ranged_evidence','Report observed stock ranged dispatches',function()
        local keys={}
        for key in pairs(instance.rows) do keys[#keys+1]=key end
        table.sort(keys)
        -- instance.total counts the session; instance.rows is wiped on an
        -- owner or game-session change, so say which is which rather than
        -- print a total that does not add up to the lines under it.
        mod:echo('Ranged evidence: %d weapon routes, %d dispatches since the last respawn, %d this session, %d diagnostic failures',
            #keys,(function() local n=0 for _,row in pairs(instance.rows) do n=n+row.calls end return n end)(),
            instance.total,instance.failures)
        for _,key in ipairs(keys) do mod:echo('%s: %d stock dispatches',key,instance.rows[key].calls) end
    end)
    return instance
end
return Evidence
