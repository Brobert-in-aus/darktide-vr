-- Adaptive angular damping before stock recoil/spread. One result per tracked
-- sample is shared by weapon presentation and gameplay direction consumers.
local Filter={}
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]+a[4]*b[4] end
local function normalized(q)
    for i=1,4 do if not finite(q[i]) then return end end
    local length=math.sqrt(dot(q,q))
    if length<1e-8 then return end
    return {q[1]/length,q[2]/length,q[3]/length,q[4]/length}
end
local function angle(a,b) return 2*math.acos(math.min(1,math.abs(dot(a,b)))) end
local function blend(a,b,t)
    local cosine=dot(a,b)
    local sign=cosine<0 and -1 or 1
    cosine=math.min(1,math.abs(cosine))
    local wa,wb=1-t,t
    if cosine<.9995 then
        local theta=math.acos(cosine)
        wa=math.sin((1-t)*theta)/math.sin(theta)
        wb=math.sin(t*theta)/math.sin(theta)
    end
    return normalized({wa*a[1]+sign*wb*b[1],wa*a[2]+sign*wb*b[2],
        wa*a[3]+sign*wb*b[3],wa*a[4]+sign*wb*b[4]})
end
local function alpha(cutoff,dt) return 1/(1+1/(2*math.pi*cutoff*dt)) end
function Filter.reset(state)
    state.q,state.raw,state.sequence,state.time,state.epoch,state.speed=nil,nil,nil,nil,nil,0
end
function Filter.step(state,q,sequence,time,epoch,strength,tracked)
    q=q and normalized(q)
    if not tracked or not q or not finite(sequence) or sequence<=0 or not finite(time) or time<=0 then
        Filter.reset(state);return nil
    end
    strength=finite(strength) and math.max(0,math.min(100,strength)) or 75
    if state.q and state.epoch==epoch and state.sequence==sequence and state.strength==strength then return state.q end
    local dt=state.time and time-state.time
    -- A changed strength only moves the cutoff (ADS raises it without a
    -- jump); only leaving the off state restarts from the raw pose.
    if not state.q or state.epoch~=epoch or sequence<state.sequence or not dt or dt<=0 or dt>.1 or
            strength==0 or state.strength==0 or angle(state.raw,q)>math.rad(60) then
        state.q=q;state.speed=0
    else
        state.speed=state.speed+alpha(10,dt)*(angle(state.raw,q)/dt-state.speed)
        local cutoff=12/(1+4*strength/100)+4*state.speed
        local weight=alpha(cutoff,dt)
        local separation=angle(state.q,q)
        -- Cap transient angular lag while bringing a weapon onto a new target.
        if separation>math.rad(3) then weight=math.max(weight,1-math.rad(3)/separation) end
        state.q=blend(state.q,q,weight)
    end
    state.raw,state.sequence,state.time,state.epoch,state.strength=q,sequence,time,epoch,strength
    return state.q
end

function Filter.install(mod,presentation,tracking)
    local state={}
    local owner,weapon_owner,hand
    local target=presentation.weapon_aim_target
    local api={}
    function api.reset() Filter.reset(state);owner,weapon_owner,hand=nil,nil,nil end
    function api.resolve(role,rotation)
        if role~='dominant' then return rotation end
        local side=presentation.weapon_hand_roles.physical(role)
        if not rotation or (side~='left' and side~='right') or presentation.mode~=1 or
                not tracking.authoring_enabled or not tracking[side..'_aim_usable'] or
                presentation.gameplay_context.ui_blocks_gameplay(Managers.ui) then
            api.reset();return rotation
        end
        local player=Managers.player and Managers.player:local_player_safe(1)
        local unit=player and player.player_unit
        local extension=unit and Unit.alive(unit) and ScriptUnit.has_extension(unit,'weapon_system')
        local template=extension and extension:weapon_template()
        local ranged=false
        for _,keyword in ipairs(template and template.keywords or {}) do
            if keyword=='ranged' then ranged=true end
        end
        if not ranged or not tracking.body_anchor_qw then api.reset();return rotation end
        local slot=extension._inventory_component and extension._inventory_component.wielded_slot
        local weapon=extension._weapons and extension._weapons[slot] or template
        if owner~=unit or weapon_owner~=weapon or hand~=side then
            api.reset();owner,weapon_owner,hand=unit,weapon,side
        end
        local anchor=Quaternion.from_elements(tracking.body_anchor_qx,tracking.body_anchor_qy,
            tracking.body_anchor_qz,tracking.body_anchor_qw)
        local local_rotation=Quaternion.multiply(Quaternion.inverse(anchor),rotation)
        local q={Quaternion.to_elements(local_rotation)}
        local time=tracking.timestamp_ns and tonumber(tracking.timestamp_ns[0])*1e-9
        -- Aiming down sights steadies the hand further while the option is on.
        local strength=tonumber(mod:get('vr_aim_stabilization')) or 75
        if presentation.ads_active and mod:get('ads_focus')~=false then
            strength=math.min(100,strength*1.6)
        end
        local result=Filter.step(state,q,tracking.last_sequence,time,tracking.last_transport_generation,
            strength,true)
        if not result then return rotation end
        return Quaternion.multiply(anchor,Quaternion.from_elements(unpack(result)))
    end
    presentation.weapon_aim_target=function(role)
        local position,rotation=target(role)
        return position,api.resolve(role,rotation)
    end
    return api
end
return Filter
