-- Coordinates a registered weapon socket, live tracking and the physical grip
-- mapper. No guessed socket profiles or changes to the user's ADS preference.
local Support={}
-- Authored grips known before play, by weapon template (see Support.install).
-- Values are the DARKTIDEVR_TWO_HAND authored_grip source=measured log line.
Support.SHIPPED_GRIPS={
    -- 14 September 2026, Psykhanium (Skitarius).
    galvanic_rifle_p1_m1={socket={-.0338,.3289,-.0017},hand_rotation={-.4336,-.1215,.5998,.6614}},
}
function Support.ads_supported(template)
    if type(template)~='table' or type(template.actions)~='table' or
        type(template.action_inputs)~='table' or type(template.alternate_fire_settings)~='table' then return false end
    local found={}
    for _,action in pairs(template.actions) do
        if type(action)=='table' and (action.kind=='aim' or action.kind=='unaim') then
            local definition=template.action_inputs[action.start_input]
            local sequence=type(definition)=='table' and definition.input_sequence
            local step=type(sequence)=='table' and #sequence==1 and sequence[1]
            if type(step)=='table' and step.input=='action_two_hold' and step.value==(action.kind=='aim') then
                local setting=step.input_setting
                if setting==nil or (type(setting)=='table' and setting.setting=='toggle_ads' and
                    setting.setting_value==true and setting.input=='action_two_pressed' and setting.value==true) then
                    found[action.kind]=true
                end
            end
        end
    end
    return found.aim==true and found.unaim==true
end
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
-- Grip zone feedback: while the support hand is close enough for a grip press
-- to take hold (the profile's acquire radius, left again ZONE_EXIT_MARGIN
-- further out), the support glove eases onto the grip over SNAP_SECONDS and
-- eases back when the hand leaves; it stays on while held.
Support.SNAP_SECONDS=.1
Support.ZONE_EXIT_MARGIN=.015
function Support.snap_step(weight,target,dt)
    if not finite(weight) then weight=0 end
    if not finite(dt) or dt<=0 then return weight end
    local step=dt/Support.SNAP_SECONDS
    if target>weight then return math.min(target,weight+step) end
    return math.max(target,weight-step)
end
-- Eased blend weight (smoothstep): quick in the middle, no jolt at either end.
function Support.snap_ease(weight)
    local w=math.max(0,math.min(1,weight or 0))
    return w*w*(3-2*w)
end
local function same_stock(a,b)
    if not a or not b then return a==b end
    if a.radius~=b.radius or a.strength~=b.strength then return false end
    for i=1,3 do
        if a.shoulder[i]~=b.shoulder[i] or a.offset[i]~=b.offset[i] then return false end
    end
    return true
end
local function valid_profile(profile)
    if type(profile)~='table' or type(profile.socket)~='table' then return false end
    if profile.side~=nil and profile.side~='left' and profile.side~='right' then return false end
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
    local api={profiles={},enabled=false,ads_unavailable=false,held=false,stock_active=false,in_zone=false,snap=0}
    function api.is_enabled() return api.enabled end
    -- Grip mode: false holds while grip is held, true toggles on each press.
    function api.grip_toggle() return false end
    -- Steadying: 'classic' smooths the swing in controller space; 'hands_line'
    -- filters the hands line in tracking space (two-hand aim design, 15 September).
    function api.steadying() return 'classic' end
    local hands_line={mode='hands_line',scene=nil}
    local filter=Pose.new()
    local stock_anchor=Pose.new_stock_anchor()
    local context,identity
    function api.clear(interrupted)
        -- Fixed input can lose gameplay ownership between render samples.
        -- Preserve only the initial wait for the calibration command's chat.
        if interrupted and api.capture_pending and api.capture_pending.at then
            api.capture_pending=nil
        end
        context,identity=nil,nil
        api.in_zone=false
        api.snap=0
        api.ads_unavailable=false
        api.held=false
        api.stock_active=false
        filter.reset()
        stock_anchor.reset()
    end
    function api.prepare(frame)
        local profile=frame and api.profiles[frame.template]
        -- A grip measured on another item of the template is not borrowed; the
        -- weapon's own authored grip (the stock animation's left hand) is the
        -- default instead.
        if profile and profile.weapon~=nil and frame and profile.weapon~=frame.weapon then profile=nil end
        if not profile and frame and api.authored_profile then profile=api.authored_profile(frame) end
        if not api.is_enabled() or not frame or frame.active~=true or frame.live~=true or
            frame.weapon==nil or frame.unit==nil or frame.generation==nil or frame.recenter==nil or
            (frame.side~='left' and frame.side~='right') or not valid_profile(profile) or
            (profile.side~=nil and profile.side~=frame.side) or
            (profile.weapon~=nil and profile.weapon~=frame.weapon) or
            not finite(frame.dt) or frame.dt<0 or frame.dt>.25 or
            not Pose.correction(frame.rotation,frame.primary,frame.support,profile.socket) then
            api.clear(); return nil
        end
        -- Copy tunable values into identity. In-place tuning, role changes,
        -- recentering and weapon replacement all retire the old gesture.
        local action=profile.ads==true and frame.ads_supported==true and frame.toggle_ads==false and 'alternate' or 'unbound'
        local hand=type(profile.hand_rotation)=='table' and profile.hand_rotation or {}
        local stock=Pose.stock_profile(profile.stock)
        if not identity or identity.weapon~=frame.weapon or identity.unit~=frame.unit or
            identity.generation~=frame.generation or identity.recenter~=frame.recenter or
            identity.side~=frame.side or identity.profile~=profile or identity.action~=action or
            identity.acquire~=profile.acquire or identity.release~=profile.release or
            identity.smoothing~=profile.smoothing or identity.x~=profile.socket[1] or
            identity.y~=profile.socket[2] or identity.z~=profile.socket[3] or
            identity.hx~=hand[1] or identity.hy~=hand[2] or identity.hz~=hand[3] or identity.hw~=hand[4] or
            not same_stock(identity.stock,stock) then
            identity={weapon=frame.weapon,unit=frame.unit,generation=frame.generation,
                recenter=frame.recenter,side=frame.side,profile=profile,action=action,
                acquire=profile.acquire,release=profile.release,smoothing=profile.smoothing,
                x=profile.socket[1],y=profile.socket[2],z=profile.socket[3],
                hx=hand[1],hy=hand[2],hz=hand[3],hw=hand[4],stock=stock}
            filter.reset()
            stock_anchor.reset()
        end
        -- A new gesture identity re-enters the zone from outside; the glove
        -- blend itself carries over (a weapon change clears it through clear()).
        if identity.zone_owner~=identity then api.in_zone=false; identity.zone_owner=identity end
        api.in_zone=Pose.near(frame.rotation,frame.primary,frame.support,profile.socket,
            profile.acquire+(api.in_zone and Support.ZONE_EXIT_MARGIN or 0))
        context=frame
        api.ads_unavailable=profile.ads==true and (frame.toggle_ads~=false or frame.ads_supported~=true)
        return {control=frame.side..'_grip',owner=identity,action=action,toggle=api.grip_toggle()==true,layer='gripping',
            acquire=Pose.near(frame.rotation,frame.primary,frame.support,profile.socket,profile.acquire),
            -- Once held, the grip keeps any hand spacing: only the guards above end
            -- it (hands too close or crossed to give the gun a direction, lost
            -- tracking, weapon or action changes, a menu).
            retain=true}
    end
    function api.finish(grip)
        api.held=false
        api.stock_active=false
        if not context or not identity then filter.reset(); stock_anchor.reset(); api.in_zone=false; api.snap=0; return end
        local stock=stock_anchor.update(context,identity.profile.socket,identity.stock,
            grip.held and not grip.cancelled,identity)
        local steady=nil
        if api.steadying()=='hands_line' then hands_line.scene=context.scene_rotation; steady=hands_line end
        filter.update(context.rotation,context.primary,context.support,identity.profile.socket,
            grip.held,identity,context.dt,identity.smoothing,grip.cancelled,stock,steady)
        api.held=grip.held and filter.owner~=nil
        api.stock_active=api.held and stock~=nil
        api.snap=Support.snap_step(api.snap,(api.held or api.in_zone) and 1 or 0,context.dt)
    end
    function api.current_profile() return identity and identity.profile end
    function api.rotation(unit,rotation)
        if not identity or identity.unit~=unit or not filter.owner then return rotation end
        return filter.apply(rotation) or rotation
    end
    function api.current(unit,weapon,generation,recenter,side)
        return identity and identity.unit==unit and identity.weapon==weapon and
            identity.generation==generation and identity.recenter==recenter and
            (side==nil or identity.side==side) or false
    end
    -- The support glove's grip pose and its eased blend weight, or nil
    -- while the hand is away from the grip.
    function api.hand_pose(unit,primary,rotation)
        if not identity or identity.unit~=unit or api.snap<=0 then return nil end
        local position,orientation=Pose.hand(rotation,primary,identity.profile.socket,identity.profile.hand_rotation)
        return position,orientation,identity.profile.authored==true,Support.snap_ease(api.snap)
    end
    return api
end
function Support.install(mod,presentation,observation)
    local Pose=mod:io_dofile('darktidevr/scripts/mods/darktidevr/darktidevr_two_hand_pose')
    local api=Support.new(Pose)
    -- The option turns support on for every session; the chat commands still
    -- work for the current one.
    -- test_enabled: darktidevr_two_hand_test.flag "enabled", "enabled_toggle",
    -- and either with "_line" for hands-line steadying
    local test_enabled_flag,test_toggle_flag,test_line_flag
    function api.is_enabled()
        return api.enabled or (mod.get and mod:get('vr_two_hand_support')==true) or test_enabled_flag==true or false
    end
    function api.grip_toggle()
        return (mod.get and mod:get('vr_two_hand_grip_mode')=='toggle') or test_toggle_flag==true
    end
    function api.steadying()
        if test_line_flag==true then return 'hands_line' end
        return (mod.get and mod:get('vr_two_hand_steadying')=='hands_line') and 'hands_line' or 'classic'
    end
    -- Authored grips, per weapon template: where the stock first-person
    -- animation holds the left hand on the weapon. Right-dominant only (the
    -- animation's support hand is the left). A grip is ready without waiting:
    -- - shipped (Support.SHIPPED_GRIPS) or stored grips (vr_two_hand_grips_v1,
    --   measured in an earlier session) are used from the first frame;
    -- - otherwise the hand settling on the weapon during the draw
    --   (SETTLE_FRAMES within SETTLE_TOLERANCE) gives a grip at once;
    -- - the first AUTHORED_SAMPLES steady frames each session average the
    --   final grip, which replaces the earlier one when the hand is not
    --   holding and is stored if it moved more than STORE_TOLERANCE.
    -- After that the template costs nothing for the rest of the session.
    Support.AUTHORED_SAMPLES=30
    Support.SETTLE_FRAMES=6
    Support.SETTLE_TOLERANCE=.005
    Support.STORE_TOLERANCE=.003
    Support.STORE_KEY='vr_two_hand_grips_v1'
    local function vec3(v) return v and {Vector3.x(v),Vector3.y(v),Vector3.z(v)} end
    local function quat(q) return q and {Quaternion.to_elements(q)} end
    local function authored_entry(socket,hand,source)
        if type(socket)~='table' or type(hand)~='table' then return nil end
        for i=1,3 do if not finite(socket[i]) then return nil end end
        for i=1,4 do if not finite(hand[i]) then return nil end end
        return {socket={socket[1],socket[2],socket[3]},hand_rotation={hand[1],hand[2],hand[3],hand[4]},
            side='left',acquire=.1,release=.2,smoothing=.07,ads=false,authored=true,source=source}
    end
    local grips={}
    for name,grip in pairs(Support.SHIPPED_GRIPS) do grips[name]=authored_entry(grip.socket,grip.hand_rotation,'shipped') end
    local stored=mod.get and mod:get(Support.STORE_KEY)
    if type(stored)=='table' then
        for name,grip in pairs(stored) do
            if type(name)=='string' and type(grip)=='table' then
                grips[name]=authored_entry(grip.socket,grip.hand_rotation,'stored') or grips[name]
            end
        end
    end
    local function store(name,entry)
        if not mod.set then return end
        local copy={}
        local current=mod.get and mod:get(Support.STORE_KEY)
        if type(current)=='table' then for k,v in pairs(current) do copy[k]=v end end
        copy[name]={socket=entry.socket,hand_rotation=entry.hand_rotation}
        mod:set(Support.STORE_KEY,copy)
    end
    local sessions={}
    local rig_logged=false
    local steady_actions={aim=true,unaim=true,shoot_hit_scan=true,shoot_pellets=true,shoot_projectile=true}
    local function log_grip(name,entry,session)
        mod:info('DARKTIDEVR_TWO_HAND authored_grip template=%s source=%s socket=%.3f,%.3f,%.3f hand=%.4f,%.4f,%.4f,%.4f frames_after_wield=%d',
            name,entry.source,entry.socket[1],entry.socket[2],entry.socket[3],entry.hand_rotation[1],
            entry.hand_rotation[2],entry.hand_rotation[3],entry.hand_rotation[4],session.frames)
    end
    function api.observe_authored(unit,equipped,template,muzzle_in_attach)
        if not unit or not equipped or type(template)~='table' or type(template.name)~='string' then return end
        local name=template.name
        local session=sessions[name]
        if session and session.final then return end
        local first_person=ScriptUnit.has_extension(unit,'first_person_system')
        local rig=first_person and first_person._first_person_unit
        if not rig or not Unit.alive(rig) or not Unit.has_node(rig,'j_lefthand') or
            not Unit.has_node(rig,'j_rightweaponattach') then
            if not rig_logged then
                rig_logged=true
                mod:info('DARKTIDEVR_TWO_HAND authored_grip=unavailable reason=first_person_rig_nodes')
            end
            return
        end
        if not session then
            session={settle=Pose.new_authored_settle(Support.SETTLE_FRAMES,Support.SETTLE_TOLERANCE),
                average=Pose.new_authored_average(Support.AUTHORED_SAMPLES),rejected=0,frames=0}
            sessions[name]=session
        end
        if session.item~=equipped then session.item,session.frames=equipped,0 end
        session.frames=session.frames+1
        local weapon=ScriptUnit.has_extension(unit,'weapon_system')
        local action=weapon and weapon:running_action_settings()
        local steady=not action or steady_actions[action.kind]==true
        local attach,left=Unit.node(rig,'j_rightweaponattach'),Unit.node(rig,'j_lefthand')
        local socket,hand=Pose.authored_socket(vec3(Unit.world_position(rig,attach)),
            quat(Unit.world_rotation(rig,attach)),vec3(Unit.world_position(rig,left)),
            quat(Unit.world_rotation(rig,left)),quat(muzzle_in_attach))
        if not socket then
            session.settle.reset()
            if steady then
                session.rejected=session.rejected+1
                if session.rejected==120 then
                    session.final=true
                    -- A one-handed weapon's draw can rest the hand briefly.
                    if grips[name] and grips[name].source=='settled' then grips[name]=nil end
                    if not grips[name] then
                        mod:info('DARKTIDEVR_TWO_HAND authored_grip=none template=%s reason=hand_off_weapon',name)
                    end
                end
            end
            return
        end
        if not grips[name] then
            local settled=session.settle.add(socket,hand)
            if settled then
                grips[name]=authored_entry(settled.socket,settled.hand_rotation,'settled')
                log_grip(name,grips[name],session)
            end
        end
        if not steady then return end
        local done=session.pending or session.average.add(socket,hand)
        if not done then return end
        -- Swapping the socket retires a gesture, so wait for the hand to let go.
        if api.held then session.pending=done; return end
        session.final=true
        local current=grips[name]
        local moved=not current or math.sqrt((current.socket[1]-done.socket[1])^2+
            (current.socket[2]-done.socket[2])^2+(current.socket[3]-done.socket[3])^2)
        if current and moved<=Support.STORE_TOLERANCE and current.source~='settled' then return end
        grips[name]=authored_entry(done.socket,done.hand_rotation,'measured')
        log_grip(name,grips[name],session)
        store(name,grips[name])
    end
    -- One log line per item when support first takes hold, naming the grip's
    -- source, and one per release (up to RELEASE_LOGS a session) with the
    -- largest correction the support hand applied to the aim while held.
    Support.RELEASE_LOGS=20
    local finish=api.finish
    local held_logged=setmetatable({},{__mode='k'})
    local releases_logged,was_held,hold_source=0,false,nil
    local zone_logs,was_in_zone,snap_frames=0,false,nil
    api.steer={max_degrees=0,frames=0}
    function api.finish(grip)
        finish(grip)
        local profile=api.held and api.current_profile and api.current_profile()
        if profile and not held_logged[profile] then
            held_logged[profile]=true
            mod:info('DARKTIDEVR_TWO_HAND held=true source=%s grip=%s socket=%.3f,%.3f,%.3f',
                profile.authored and 'authored' or 'calibrated',tostring(profile.source or 'command'),
                profile.socket[1],profile.socket[2],profile.socket[3])
        end
        local haptics=presentation.haptics
        local support_side=presentation.weapon_hand_roles and presentation.weapon_hand_roles.physical('support')
        if api.held and not was_held then
            if haptics then haptics.pulse(support_side,'grip') end
            api.steer.max_degrees,api.steer.frames=0,0
            hold_source=profile and (profile.authored and 'authored' or 'calibrated') or 'unknown'
        elseif was_held and not api.held and releases_logged<Support.RELEASE_LOGS then
            releases_logged=releases_logged+1
            mod:info('DARKTIDEVR_TWO_HAND released source=%s mode=%s ended=%s max_steer_degrees=%.1f steered_frames=%d',
                hold_source,api.grip_toggle() and 'toggle' or 'hold',grip.cancelled and 'cancelled' or 'released',
                api.steer.max_degrees,api.steer.frames)
        end
        was_held=api.held
        -- Zone feedback evidence: entry, and frames until the glove sits on the grip.
        if api.in_zone and not was_in_zone and not api.held and haptics then haptics.pulse(support_side,'zone') end
        if api.in_zone and not was_in_zone and zone_logs<Support.RELEASE_LOGS then
            zone_logs=zone_logs+1; snap_frames=0
            mod:info('DARKTIDEVR_TWO_HAND zone=enter held=%s',tostring(api.held))
        end
        if snap_frames then
            snap_frames=snap_frames+1
            if api.snap>=1 then
                mod:info('DARKTIDEVR_TWO_HAND zone=snapped frames=%d',snap_frames); snap_frames=nil
            elseif not api.in_zone then snap_frames=nil end
        end
        was_in_zone=api.in_zone
    end
    local function steer_degrees(a,b)
        local dot=math.abs(a[1]*b[1]+a[2]*b[2]+a[3]*b[3]+a[4]*b[4])
        return math.deg(2*math.acos(math.min(1,dot)))
    end
    function api.authored_profile(frame)
        return frame and type(frame.template)=='string' and grips[frame.template] or nil
    end
    -- Development preview: darktidevr_two_hand_test.flag "preview" places the
    -- support glove on the authored grip without a grip press, so the eye
    -- render shows where it lands. Players never have the file.
    local preview_poll,preview=0,false
    local function preview_requested()
        preview_poll=preview_poll-1
        if preview_poll>0 then return preview end
        preview_poll=60
        local io_api=Mods and Mods.lua and Mods.lua.io
        local file=io_api and io_api.open('./../mods/darktidevr/darktidevr_two_hand_test.flag','r')
        local value=file and file:read('*all')
        if file then file:close() end
        preview=type(value)=='string' and value:match('^%s*preview%s*$')~=nil
        local mode=type(value)=='string' and value:match('^%s*(enabled[_%a]*)%s*$')
        mode=(mode=='enabled' or mode=='enabled_toggle' or mode=='enabled_line' or mode=='enabled_toggle_line') and mode or nil
        test_enabled_flag=mode~=nil
        test_toggle_flag=mode~=nil and mode:find('toggle',1,true)~=nil
        test_line_flag=mode~=nil and mode:find('_line',1,true)~=nil
        return preview
    end
    local previous_t
    local allowed_states={walking=true,sprinting=true,sliding=true,jumping=true,falling=true,dodging=true}
    -- Gun actions the support grip holds through. Reloads keep it (worn, 14 September:
    -- reloading must not break two-handing; nor bashing, the gun's sweep, push and
    -- windup actions); inspect, draw and holster end it.
    local allowed_actions={aim=true,unaim=true,shoot_hit_scan=true,shoot_pellets=true,shoot_projectile=true,
        reload_state=true,reload_shotgun=true,charge_ammo=true,ranged_load_special=true,toggle_special=true,
        vent_overheat=true,overload_charge=true,charge=true,flamer_gas=true,flamer_gas_burst=true,
        sweep=true,push=true,windup=true}
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
        local frame={active=true,live=true,unit=unit,weapon=equipped,template=template.name,
            side=presentation.weapon_hand_roles.physical('support'),
            generation=observation.last_transport_generation,recenter=observation.head_recenter_generation,
            dt=dt,rotation=quaternion(rotation),primary=vector(presentation.weapon_grip_target('dominant')),
            support=vector(support_position),support_rotation=quaternion(support_rotation),
            toggle_ads=settings and settings.toggle_ads,ads_supported=Support.ads_supported(template),
            action=action and action.kind}
        -- The scene basis (stick turning, pre head tracking) lets the hands
        -- line be filtered in tracking space.
        if finite(observation.body_anchor_qx) and finite(observation.body_anchor_qy) and
            finite(observation.body_anchor_qz) and finite(observation.body_anchor_qw) then
            frame.scene_rotation={observation.body_anchor_qx,observation.body_anchor_qy,
                observation.body_anchor_qz,observation.body_anchor_qw}
        end
        local profile=api.profiles[template.name]
        if profile and profile.stock and presentation.body_alignment_unit==unit and
            finite(observation.body_visual_yaw) and finite(observation.body_anchor_qx) and
            finite(observation.body_anchor_qy) and finite(observation.body_anchor_qz) and
            finite(observation.body_anchor_qw) then
            frame.body_position=vector(Unit.world_position(unit,1))
            frame.body_yaw=observation.body_visual_yaw
            -- This is the scene basis captured before physical head tracking.
            frame.scene_yaw=Quaternion.yaw(Quaternion.from_elements(observation.body_anchor_qx,
                observation.body_anchor_qy,observation.body_anchor_qz,observation.body_anchor_qw))
        end
        return frame
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
        api.profiles[frame.template]={weapon=frame.weapon,side=frame.side,socket=socket,hand_rotation=hand_rotation,
            acquire=.1,release=.2,smoothing=.07,ads=true}
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
        if not api.is_enabled() and not api.capture_pending then return api.prepare(nil) end
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
        if not api.is_enabled() or not rotation then return rotation end
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
        local input=quaternion(rotation)
        local result=api.rotation(unit,input)
        if result and api.held then
            local degrees=steer_degrees(input,result)
            if degrees==degrees then
                api.steer.frames=api.steer.frames+(degrees>=.5 and 1 or 0)
                if degrees>api.steer.max_degrees then api.steer.max_degrees=degrees end
            end
        end
        return result and Quaternion.from_elements(unpack(result)) or rotation
    end
    function api.resolve(unit,rotation)
        local ok,result=pcall(resolve,unit,rotation)
        if ok then return result end
        api.clear()
        return rotation
    end
    function api.place_hand(world,unit,primary,rotation)
        if not presentation.body_proxy or not presentation.body_proxy.place_support_hand then return false end
        local position,orientation,authored_rotation,weight
        if preview_requested() then
            local weapon=unit and ScriptUnit.has_extension(unit,'weapon_system')
            local template=weapon and weapon:weapon_template()
            local grip=template and grips[template.name]
            if grip then
                position,orientation=Pose.hand(quaternion(rotation),vector(primary),grip.socket,grip.hand_rotation)
                authored_rotation=true
            end
        end
        if not position then
            if not api.is_enabled() or not live() then return false end
            position,orientation,authored_rotation,weight=api.hand_pose(unit,vector(primary),quaternion(rotation))
        end
        if not position or not orientation then return false end
        local ok,written=pcall(presentation.body_proxy.place_support_hand,world,unit,
            presentation.weapon_hand_roles.physical('support'),Vector3(unpack(position)),
            Quaternion.from_elements(unpack(orientation)),authored_rotation,weight)
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
