-- Coordinates a registered weapon socket, live tracking and the physical grip
-- mapper. No guessed socket profiles or changes to the user's ADS preference.
local Support={}
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function valid_profile(profile)
    if type(profile)~='table' or type(profile.socket)~='table' then return false end
    local length=0
    for i=1,3 do
        local v=profile.socket[i]
        if not finite(v) then return false end
        length=length+v*v
    end
    return length>=.0064 and length<=1 and finite(profile.acquire) and
        finite(profile.release) and profile.acquire>0 and profile.acquire<=.3 and
        profile.release>=profile.acquire and profile.release<=.6 and
        finite(profile.smoothing) and profile.smoothing>=0 and profile.smoothing<=.3
end
function Support.new(Pose)
    local api={profiles={},enabled=false,ads_unavailable=false,held=false}
    local filter=Pose.new()
    local context,identity
    function api.clear()
        context,identity=nil,nil
        api.ads_unavailable=false
        api.held=false
        filter.reset()
    end
    function api.prepare(frame)
        local profile=frame and api.profiles[frame.template]
        if not api.enabled or not frame or frame.active~=true or frame.live~=true or
            frame.weapon==nil or frame.unit==nil or frame.generation==nil or frame.recenter==nil or
            (frame.side~='left' and frame.side~='right') or not valid_profile(profile) or
            not finite(frame.dt) or frame.dt<0 or frame.dt>.25 or
            not Pose.correction(frame.rotation,frame.primary,frame.support,profile.socket) then
            api.clear(); return nil
        end
        -- Copy tunable values into identity. In-place tuning, role changes,
        -- recentering and weapon replacement all retire the old gesture.
        local action=profile.ads==true and frame.toggle_ads==false and 'alternate' or 'unbound'
        local hand=type(profile.hand_rotation)=='table' and profile.hand_rotation or {}
        if not identity or identity.weapon~=frame.weapon or identity.unit~=frame.unit or
            identity.generation~=frame.generation or identity.recenter~=frame.recenter or
            identity.side~=frame.side or identity.profile~=profile or identity.action~=action or
            identity.acquire~=profile.acquire or identity.release~=profile.release or
            identity.smoothing~=profile.smoothing or identity.x~=profile.socket[1] or
            identity.y~=profile.socket[2] or identity.z~=profile.socket[3] or
            identity.hx~=hand[1] or identity.hy~=hand[2] or identity.hz~=hand[3] or identity.hw~=hand[4] then
            identity={weapon=frame.weapon,unit=frame.unit,generation=frame.generation,
                recenter=frame.recenter,side=frame.side,profile=profile,action=action,
                acquire=profile.acquire,release=profile.release,smoothing=profile.smoothing,
                x=profile.socket[1],y=profile.socket[2],z=profile.socket[3],
                hx=hand[1],hy=hand[2],hz=hand[3],hw=hand[4]}
            filter.reset()
        end
        context=frame
        api.ads_unavailable=profile.ads==true and frame.toggle_ads~=false
        return {control=frame.side..'_grip',owner=identity,action=action,
            acquire=Pose.near(frame.rotation,frame.primary,frame.support,profile.socket,profile.acquire),
            retain=Pose.near(filter.apply(frame.rotation),frame.primary,frame.support,profile.socket,profile.release)}
    end
    function api.finish(grip)
        api.held=false
        if not context or not identity then filter.reset(); return end
        filter.update(context.rotation,context.primary,context.support,identity.profile.socket,
            grip.held,identity,context.dt,identity.smoothing,grip.cancelled)
        api.held=grip.held and filter.owner~=nil
    end
    function api.rotation(unit,rotation)
        if not identity or identity.unit~=unit or not filter.owner then return rotation end
        return filter.apply(rotation) or rotation
    end
    function api.current(unit,weapon,generation,recenter,side)
        return identity and identity.unit==unit and identity.weapon==weapon and
            identity.generation==generation and identity.recenter==recenter and
            (side==nil or identity.side==side) or false
    end
    function api.hand_pose(unit,primary,rotation)
        if not api.held or not identity or identity.unit~=unit then return nil end
        return Pose.hand(rotation,primary,identity.profile.socket,identity.profile.hand_rotation)
    end
    return api
end
function Support.install(mod,presentation,observation)
    local Pose=mod:io_dofile('darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_two_hand_pose')
    local api=Support.new(Pose)
    local previous_t
    local allowed_states={walking=true,sprinting=true,sliding=true,jumping=true,falling=true,dodging=true}
    local allowed_actions={aim=true,unaim=true,shoot_hit_scan=true,shoot_pellets=true,shoot_projectile=true}
    local function vector(v) return v and {Vector3.x(v),Vector3.y(v),Vector3.z(v)} end
    local function quaternion(q) return q and {Quaternion.to_elements(q)} end
    local function live()
        local dominant=presentation.weapon_hand_roles.physical('dominant')
        local support=presentation.weapon_hand_roles.physical('support')
        return (dominant=='left' or dominant=='right') and (support=='left' or support=='right') and
            observation[dominant..'_grip_tracking_live']==true and
            observation[support..'_grip_tracking_live']==true and observation[dominant..'_aim_usable']==true
    end
    local function snapshot(unit,dt,handler)
        if not unit or not live() or
            not presentation.online_rules.simulation_aim_active(unit) then return nil end
        local machine=ScriptUnit.has_extension(unit,'character_state_machine_system')
        if not machine or not allowed_states[machine:current_state_name()] then return nil end
        local weapon=ScriptUnit.has_extension(unit,'weapon_system')
        local template=weapon and weapon:weapon_template()
        if not presentation.gun_aim.is_gun(template) then return nil end
        local action=weapon:running_action_settings()
        if action and not allowed_actions[action.kind] then return nil end
        local equipped=weapon:_wielded_weapon(weapon._inventory_component,weapon._weapons)
        local dominant=presentation.weapon_hand_roles.physical('dominant')
        local _,rotation
        if dominant=='right' then _,rotation=presentation.controller_aim_target()
        else _,rotation=presentation.left_controller_aim_target() end
        rotation=presentation.gun_aim.base_aim(unit,rotation)
        local settings=handler and handler._input_settings_table
        local support_position,support_rotation=presentation.weapon_grip_target('support')
        return {active=true,live=true,unit=unit,weapon=equipped,template=template.name,
            side=presentation.weapon_hand_roles.physical('support'),
            generation=observation.last_transport_generation,recenter=observation.head_recenter_generation,
            dt=dt,rotation=quaternion(rotation),primary=vector(presentation.weapon_grip_target('dominant')),
            support=vector(support_position),support_rotation=quaternion(support_rotation),
            toggle_ads=settings and settings.toggle_ads,
            action=action and action.kind}
    end
    function api.arm_capture(unit)
        api.capture_pending=nil
        local ok,frame=pcall(snapshot,unit,0,nil)
        if not ok or not frame or not frame.weapon or type(frame.template)~='string' then return false end
        api.enabled=false; api.clear()
        api.capture_pending={unit=unit,weapon=frame.weapon,template=frame.template,side=frame.side,
            generation=frame.generation,recenter=frame.recenter,deadline=previous_t and previous_t+30}
        return true
    end
    local function capture(frame,t)
        local pending=api.capture_pending
        if not pending then return end
        if not frame or t>pending.deadline or pending.weapon~=frame.weapon or pending.unit~=frame.unit or
            pending.template~=frame.template or pending.side~=frame.side or
            pending.generation~=frame.generation or pending.recenter~=frame.recenter or
            (frame.action and frame.action~='aim' and frame.action~='unaim') then
            api.capture_pending=nil
            mod:info('DARKTIDEVR_TWO_HAND calibration=cancelled')
            return
        end
        if not pending.at then
            pending.at=t+3
            mod:info('DARKTIDEVR_TWO_HAND calibration=countdown seconds=3')
            return
        end
        if t<pending.at then return end
        api.capture_pending=nil
        local socket=Pose.socket(frame.rotation,frame.primary,frame.support)
        local hand_rotation=Pose.relative_rotation(frame.rotation,frame.support_rotation)
        if not socket or not hand_rotation then mod:info('DARKTIDEVR_TWO_HAND calibration=invalid_geometry'); return end
        api.profiles[frame.template]={socket=socket,hand_rotation=hand_rotation,acquire=.1,release=.2,smoothing=.07,ads=true}
        api.clear()
        mod:info('DARKTIDEVR_TWO_HAND calibration=captured weapon=%s socket=%.4f,%.4f,%.4f session_only=true',
            frame.template,socket[1],socket[2],socket[3])
        if mod.echo then mod:echo('Support grip recorded for this session. Use /dtvr_two_hand_on to test it.') end
    end
    local function sample(unit,active,t,handler)
        local dt=previous_t and t-previous_t or 0
        previous_t=t
        if api.capture_pending and finite(t) and not api.capture_pending.deadline then
            api.capture_pending.deadline=t+30
        end
        if api.capture_pending and (not finite(t) or t>api.capture_pending.deadline or not live()) then
            api.capture_pending=nil
        end
        if api.capture_pending and api.capture_pending.at and (not finite(dt) or dt<0 or dt>.25) then
            api.capture_pending=nil
        end
        if not active then
            -- Allow the command's chat box to close before starting its countdown.
            -- Reopening a menu after that point cancels the measurement.
            if api.capture_pending and api.capture_pending.at then api.capture_pending=nil end
            return api.prepare(nil)
        end
        if not api.enabled and not api.capture_pending then return api.prepare(nil) end
        local frame=snapshot(unit,dt,handler)
        capture(frame,t)
        return api.prepare(frame)
    end
    function api.sample(unit,active,t,handler)
        local ok,request=pcall(sample,unit,active,t,handler)
        if ok then return request end
        api.clear(); previous_t=nil; api.capture_pending=nil
        if not api.failure_logged then
            api.failure_logged=true
            mod:info('DARKTIDEVR_TWO_HAND cancelled=%s',tostring(request):sub(1,160))
        end
    end
    local function resolve(unit,rotation)
        if not api.enabled or not rotation then return rotation end
        if not live() or not presentation.online_rules.simulation_aim_active(unit) then
            api.clear(); return rotation
        end
        local weapon=unit and ScriptUnit.has_extension(unit,'weapon_system')
        local equipped=weapon and weapon:_wielded_weapon(weapon._inventory_component,weapon._weapons)
        local action=weapon and weapon:running_action_settings()
        local machine=unit and ScriptUnit.has_extension(unit,'character_state_machine_system')
        if not api.current(unit,equipped,observation.last_transport_generation,observation.head_recenter_generation,
                presentation.weapon_hand_roles.physical('support')) or
            not machine or not allowed_states[machine:current_state_name()] or
            not weapon or not presentation.gun_aim.is_gun(weapon:weapon_template()) or
            (action and not allowed_actions[action.kind]) then api.clear(); return rotation end
        local result=api.rotation(unit,quaternion(rotation))
        return result and Quaternion.from_elements(unpack(result)) or rotation
    end
    function api.resolve(unit,rotation)
        local ok,result=pcall(resolve,unit,rotation)
        if ok then return result end
        api.clear()
        return rotation
    end
    function api.place_hand(world,unit,primary,rotation)
        if not api.enabled or not api.held or not live() or not presentation.body_proxy or
            not presentation.body_proxy.place_support_hand then return false end
        local position,orientation=api.hand_pose(unit,vector(primary),quaternion(rotation))
        if not position then return false end
        local ok,written=pcall(presentation.body_proxy.place_support_hand,world,unit,
            presentation.weapon_hand_roles.physical('support'),Vector3(unpack(position)),
            Quaternion.from_elements(unpack(orientation)))
        return ok and written==true
    end
    if mod.command then
        mod:command('dtvr_two_hand_calibrate','Record the current gun support grip after a three-second delay',function()
            local manager=Managers and Managers.player
            local player=manager and manager:local_player(1)
            local armed=api.arm_capture(player and player.player_unit)
            mod:echo(armed and 'Close chat and hold the support hand at the gun grip for three seconds. Capture does not enable two-handing.' or
                'Support capture needs a live tracked gun in Psykhanium.')
        end)
        mod:command('dtvr_two_hand_on','Enable calibrated two-hand support for this session',function()
            api.enabled=true
            mod:echo('Two-hand support enabled for calibrated guns. Press grip near the recorded support point.')
        end)
        mod:command('dtvr_two_hand_off','Disable two-hand support and cancel pending capture',function()
            api.enabled=false; api.capture_pending=nil; api.clear()
            mod:echo('Two-hand support disabled.')
        end)
    end
    return api
end
return Support
