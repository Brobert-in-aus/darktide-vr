-- Observe the actual stock hit result and collision list without changing either.
--
-- The detail is capped per weapon, and past the cap a compact line still goes
-- out. The reason is the ranged evidence's reason (see that file): on 18
-- September a gun stopped producing bullets and the log could not say whether
-- a sweep had even run, because the last line it wrote was four minutes old.
-- Knowing the shot dispatched is half the answer; whether the sweep ran, what
-- it hit and at what distance is the half that tells the two failures apart.
local Evidence={}
local DETAIL_SHOTS=4
local SUMMARY_SECONDS=5
local SUMMARY_SHOTS=20
local function pack(...) return {n=select('#',...),...} end
local function vector(v)
    if not v then return 'none' end
    return string.format('%.4f,%.4f,%.4f',Vector3.x(v),Vector3.y(v),Vector3.z(v))
end
function Evidence.install(mod,presentation)
    local instance={rows={},failures=0,total=0}
    local owner,session
    local Health=require('scripts/utilities/health')
    local HitZone=require('scripts/utilities/attack/hit_zone')
    local function observe(result,is_server,world,physics,attacker,configuration,hits,position,direction)
        if not presentation.online_rules.simulation_aim_active(attacker) then return end
        local data=ScriptUnit.has_extension(attacker,'unit_data_system')
        if data and data.is_resimulating then return end
        if owner~=attacker or session~=Managers.state.game_session then
            owner,session,instance.rows=attacker,Managers.state.game_session,{}
        end
        local weapon=ScriptUnit.has_extension(attacker,'weapon_system')
        local template=weapon and weapon:weapon_template()
        local name=tostring(template and template.name or 'unknown')
        local row=instance.rows[name]
        if type(row)~='table' then row={calls=0} instance.rows[name]=row end
        row.calls=row.calls+1
        instance.total=instance.total+1
        local count=row.calls
        local endpoint=result[1]
        local distance=endpoint and math.sqrt(Vector3.length_squared(endpoint-position)) or -1
        if count>DETAIL_SHOTS then
            -- Whether the sweep ran, and what it came back with. The first
            -- collision is named because every shot so far has begun inside
            -- the player's own hitbox, and a sweep that stops there is exactly
            -- the failure this line has to be able to show.
            local now=Managers and Managers.time and Managers.time.has_timer and
                Managers.time:has_timer('main') and Managers.time:time('main') or nil
            local due
            if now then due=row.summary_t==nil or now>=row.summary_t+SUMMARY_SECONDS
            else due=count-(row.summary_calls or DETAIL_SHOTS)>=SUMMARY_SHOTS end
            if due then
                row.summary_t=now or row.summary_t
                local since=count-(row.summary_calls or DETAIL_SHOTS)
                row.summary_calls=count
                local first=hits and hits[1]
                local first_actor=first and (first.actor or first[4])
                local first_unit=first_actor and Actor.unit(first_actor)
                mod:info('DARKTIDEVR_HIT_EVIDENCE weapon=%s sweeps=%d since_last=%d distance=%.4f minion=%s hit_count=%d first_self=%s',
                    name,count,since,distance,tostring(result[5]),hits and #hits or 0,
                    tostring(first_unit==attacker))
            end
            return
        end
        mod:info('DARKTIDEVR_HIT_EVIDENCE weapon=%s shot=%d endpoint=%s distance=%.4f minion=%s hit_count=%d origin=%s direction=%s',
            name,count,vector(endpoint),distance,tostring(result[5]),hits and #hits or 0,vector(position),vector(direction))
        for i=1,math.min(hits and #hits or 0,8) do
            local hit=hits[i]
            local actor=hit.actor or hit[4]
            local unit=actor and Actor.unit(actor)
            local zone=unit and HitZone.get_name(unit,actor)
            local proxy=presentation.body_proxy and presentation.body_proxy.visual_owner(unit)
            mod:info('DARKTIDEVR_HIT_EVIDENCE collision=%d distance=%s unit=%s actor=%s self=%s proxy=%s static=%s damageable=%s zone=%s position=%s',
                i,tostring(hit.distance or hit[2]),tostring(unit),tostring(actor),tostring(unit==attacker),
                tostring(proxy or 'none'),tostring(actor and Actor.is_static(actor)),
                tostring(unit and Health.is_damagable(unit)),tostring(zone),vector(hit.position or hit[1]))
        end
    end
    mod:hook(require('scripts/utilities/attack/hit_scan'),'process_hits',function(func,...)
        local result=pack(func(...))
        local ok,message=pcall(observe,result,...)
        if not ok then
            instance.failures=instance.failures+1
            if instance.failures==1 then
                pcall(mod.info,mod,'DARKTIDEVR_HIT_EVIDENCE unavailable=%s',tostring(message):sub(1,160))
            end
        end
        return unpack(result,1,result.n)
    end)
    return instance
end
return Evidence
