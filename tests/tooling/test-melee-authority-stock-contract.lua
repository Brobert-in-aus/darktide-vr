-- Stock final attack dispatch: prediction can calculate nonzero damage without
-- calling the health mutation sink. Calculation/health math remain fixtures.
local root=assert(arg[1])
local file=assert(io.open(root..'/scripts/utilities/attack/attack.lua','r'))
local source=file:read('*a'); file:close()
local first=assert(source:find('function _handle_attack(',1,true))
local last=assert(source:find('\nfunction _already_procced(',first,true))
local calls,calculations,writes=0,0,0
local blocked,allowed,ally=false,true,false
local unit,attacker,owner,actor,profile,position,direction={},{},{},{},{},{},{}
local block_component={}
local env=setmetatable({
    Block={is_blocking=function() return blocked end,attack_is_blockable=function() return true end},
    Breed={is_player=function() return false end},
    FriendlyFire={is_enabled=function() return false end},
    Managers={state={extension={system=function() return {is_ally=function() return ally end} end}}},
    attack_results={blocked='blocked',friendly_fire='friendly_fire',dodged='dodged',died='died'},
    DamageTakenCalculation={calculation_parameters=function()
        return false,allowed,{},0,0,100,3
    end,calculate_attack_result=function()
        calculations=calculations+1; return 'hit',10,2,3,4
    end},
    Damage={deal_damage=function(target,breed,source_unit,source_owner,result,attack_type,
            damage_profile,damage,permanent,toughness,hit_actor,attack_direction,zone,
            herding,critical,damage_type,hit_position,wounds,instakill,absorbed)
        calls=calls+1
        assert(target==unit and source_unit==attacker and source_owner==owner)
        assert(result=='hit' and attack_type=='melee' and damage_profile==profile)
        assert(damage==10 and permanent==2 and toughness==3 and absorbed==4)
        assert(hit_actor==actor and attack_direction==direction and hit_position==position)
        assert(zone=='head' and critical and damage_type=='slash' and not instakill)
        return 9 -- supplied actual health result, distinct from calculated damage
    end}
},{__index=_G})
setfenv(assert(loadstring(source:sub(first,last-1))),env)()
local data={write_component=function(_,name) assert(name=='block'); writes=writes+1; return block_component end}
local function hit(server,assisted,hogtied)
    calls,calculations,writes=0,0,0; block_component.has_blocked=nil
    return {env._handle_attack(server,false,assisted,hogtied,unit,{},20,attacker,owner,
        'head',profile,direction,actor,'melee',nil,true,position,'slash',nil,nil,data,nil,nil,1)}
end
for _,server in ipairs({false,true}) do
    for _,permission in ipairs({false,true}) do
        allowed=permission; blocked=false
        local result=hit(server,false,false)
        assert(result[1]=='hit' and result[2]==12 and calculations==1)
        assert(calls==((server and allowed) and 1 or 0))
        assert(result[7]==((server and allowed) and 9 or nil),
            'Prediction/calculated damage was confused with actual health dispatch')
    end
end
allowed=true; blocked=true
for _,server in ipairs({false,true}) do
    for _,same_side in ipairs({false,true}) do
        ally=same_side
        local result=hit(server,false,false)
        assert(result[1]==(ally and 'friendly_fire' or 'blocked'))
        assert(result[2]==0 and result[3]==20 and calls==0 and calculations==0)
        assert(writes==((server and not ally) and 1 or 0))
        assert(block_component.has_blocked==((server and not ally) and true or nil))
    end
end
blocked=false; ally=false
for _,case in ipairs({{assisted=true,absorbed=20},{hogtied=true,absorbed=0}}) do
    local result=hit(true,case.assisted,case.hogtied)
    assert(result[1]=='dodged' and result[2]==0 and result[3]==case.absorbed)
    assert(calls==0 and calculations==0)
end
print('melee_authority_stock=pass prediction_vs_health server_allowed_gate block_ownership friendly_fire assisted_hogtied')
print('LIMIT: actual stock dispatch with calculation/health fixtures; no live damage, networking or hit geometry')
