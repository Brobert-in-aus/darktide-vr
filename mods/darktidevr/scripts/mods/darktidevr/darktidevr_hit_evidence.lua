-- Observe the actual stock hit result and collision list without changing either.
local Evidence={}
local function pack(...) return {n=select('#',...),...} end
local function vector(v)
    if not v then return 'none' end
    return string.format('%.4f,%.4f,%.4f',Vector3.x(v),Vector3.y(v),Vector3.z(v))
end
function Evidence.install(mod,presentation)
    local instance={rows={},failures=0}
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
        instance.rows[name]=(instance.rows[name] or 0)+1
        local count=instance.rows[name]
        if count>4 then return end
        local endpoint=result[1]
        local distance=endpoint and math.sqrt(Vector3.length_squared(endpoint-position)) or -1
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
