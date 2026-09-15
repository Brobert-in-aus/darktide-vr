-- Controller aim owns direction; controller grip owns weapon placement.
-- The animated hand model is never an input to gameplay aim or the grip target.
local Alignment={}
local guns={shoot_hit_scan=true,shoot_pellets=true,shoot_projectile=true}
function Alignment.pitch(rotation,degrees)
    local half=math.rad(degrees)*0.5
    return Quaternion.multiply(rotation,Quaternion.from_elements(math.sin(half),0,0,math.cos(half)))
end
function Alignment.is_gun(template)
    for _,keyword in ipairs(template and template.keywords or {}) do
        if keyword=='force_staff' then return false end
    end
    for _,action in pairs(template and template.actions or {}) do
        if guns[action.kind] then return true end
    end
    return false
end
function Alignment.rotation(parent,attachment,muzzle,aim)
    local relative=Quaternion.multiply(Quaternion.inverse(attachment),muzzle)
    return Quaternion.multiply(Quaternion.inverse(parent),
        Quaternion.multiply(aim,Quaternion.inverse(relative)))
end
local function same(a,b)
    local ax,ay,az,aw=Quaternion.to_elements(a)
    local bx,by,bz,bw=Quaternion.to_elements(b)
    return math.abs(ax*bx+ay*by+az*bz+aw*bw)>1-1e-7
end
function Alignment.install(mod,presentation)
    local instance={failures=0,writes=0,is_gun=Alignment.is_gun}
    -- One pitch for every weapon and item, so switching between a gun, a melee
    -- weapon, a staff or a blitz never moves the crosshair.
    function instance.base_aim(unit,rotation)
        if not unit or not rotation then return rotation end
        local degrees=tonumber(mod:get('vr_gun_pitch')) or -10
        if degrees~=degrees then degrees=-10 end
        return Alignment.pitch(rotation,math.max(-45,math.min(45,degrees)))
    end
    function instance.aim(unit,rotation)
        rotation=instance.base_aim(unit,rotation)
        if presentation.two_hand then return presentation.two_hand.resolve(unit,rotation) end
        return rotation
    end
    -- The gun as placed this frame: its attach node (at the controller grip)
    -- and the drawn aim, for displays placed relative to the gun (the ammo
    -- counter). Nil unless a gun was aligned at the current main time.
    function instance.gun_pose()
        local now=Managers and Managers.time and Managers.time:time('main')
        if not now or instance.pose_t~=now or not instance.pose_position then return nil end
        return instance.pose_position:unbox(),instance.pose_rotation:unbox()
    end
    local saved
    local function restore(world)
        if saved and saved.world==world and Unit.alive(saved.unit) then
            if same(Unit.local_rotation(saved.unit,saved.node),saved.written:unbox()) then
                Unit.set_local_rotation(saved.unit,saved.node,saved.original:unbox())
            end
            if Vector3.distance(Unit.local_position(saved.unit,saved.node),saved.written_position:unbox())<1e-6 then
                Unit.set_local_position(saved.unit,saved.node,saved.original_position:unbox())
            end
            World.update_unit_and_children(world,saved.unit)
        end
        saved=nil
    end
    local function update(world,unit)
        restore(world)
        if not presentation.online_rules.simulation_aim_active(unit) then return end
        local dominant=presentation.weapon_hand_roles.physical('dominant')
        if dominant~='right' and dominant~='left' then return end
        if dominant=='left' and (not presentation.body_proxy or not presentation.body_proxy.align_gun_hand) then return end
        local weapon=ScriptUnit.has_extension(unit,'weapon_system')
        local template=weapon and weapon:weapon_template()
        if not Alignment.is_gun(template) then return end
        local settings=weapon:running_action_settings()
        -- Keep controller ownership through draw/reload/unwield. Stock still
        -- advances ammo, timings and moving weapon parts; it cannot tilt the gun.
        if settings and (settings.kind=='sweep' or settings.kind=='push') then return end
        local _,aim=presentation.weapon_aim_target('dominant')
        local grip=presentation.weapon_grip_target('dominant')
        if not aim or not grip then return end
        local equipped=weapon:_wielded_weapon(weapon._inventory_component,weapon._weapons)
        local source=equipped and equipped.fx_sources and equipped.fx_sources._muzzle
        local fx=weapon._fx_extension
        if not source or not fx then return end
        local _,_,muzzle_unit,muzzle_node=fx:vfx_spawner_unit_and_node(source)
        if not muzzle_unit or muzzle_node==nil or not Unit.alive(muzzle_unit) then return end
        local attach_name='j_rightweaponattach'
        if not Unit.has_node(unit,attach_name) then return end
        local attach=Unit.node(unit,attach_name)
        local parent=Unit.scene_graph_parent(unit,attach)
        if parent==nil then return end
        local original=Unit.local_rotation(unit,attach)
        local old_attach_position=Unit.world_position(unit,attach)
        local old_attach_rotation=Unit.world_rotation(unit,attach)
        -- The weapon's fixed attach-to-muzzle rotation, before the write below:
        -- two-hand support uses it to express the stock left hand in the aim
        -- frame (the authored grip).
        if dominant=='right' and presentation.two_hand and presentation.two_hand.observe_authored then
            presentation.two_hand.observe_authored(unit,equipped,template,
                Quaternion.multiply(Quaternion.inverse(old_attach_rotation),Unit.world_rotation(muzzle_unit,muzzle_node)))
        end
        -- The drawn gun is zeroed on the reticle (darktidevr_gun_sights): its
        -- sights, not its bore, line up with the aim point. Presentation only.
        if presentation.gun_sights then
            local now=Managers.time and Managers.time:time('main')
            local dt=now and instance.last_time and now-instance.last_time
            instance.last_time=now
            aim=presentation.gun_sights.drawn_rotation(unit,template.name,grip,aim,dt)
        end
        local original_position=Unit.local_position(unit,attach)
        local desired_position=Matrix4x4.transform(Matrix4x4.inverse(Unit.world_pose(unit,parent)),grip)
        local desired=Alignment.rotation(Unit.world_rotation(unit,parent),
            Unit.world_rotation(unit,attach),Unit.world_rotation(muzzle_unit,muzzle_node),aim)
        saved={world=world,unit=unit,node=attach,original=QuaternionBox(original),written=QuaternionBox(desired),
            original_position=Vector3Box(original_position),written_position=Vector3Box(desired_position)}
        Unit.set_local_rotation(unit,attach,desired)
        Unit.set_local_position(unit,attach,desired_position)
        World.update_unit_and_children(world,unit)
        if instance.pose_position then
            instance.pose_position:store(Unit.world_position(unit,attach)); instance.pose_rotation:store(aim)
        else
            instance.pose_position=Vector3Box(Unit.world_position(unit,attach)); instance.pose_rotation=QuaternionBox(aim)
        end
        instance.pose_t=Managers and Managers.time and Managers.time:time('main')
        if presentation.body_proxy and presentation.body_proxy.align_gun_hand then
            local aligned=presentation.body_proxy.align_gun_hand(world,unit,old_attach_position,old_attach_rotation,
                Unit.world_position(unit,attach),Unit.world_rotation(unit,attach),dominant)
            if dominant=='left' and not aligned then restore(world); return end
        end
        if presentation.two_hand then presentation.two_hand.place_hand(world,unit,grip,aim) end
        if presentation.gun_sights then
            presentation.gun_sights.observe_grip(template.name,Unit.world_pose(muzzle_unit,muzzle_node),Unit.world_position(unit,attach))
        end
        instance.writes=instance.writes+1
        if instance.last_weapon~=template then
            instance.last_weapon=template
            local ax,ay,az,aw=Quaternion.to_elements(aim)
            local bx,by,bz,bw=Quaternion.to_elements(Unit.world_rotation(muzzle_unit,muzzle_node))
            local dot=math.min(1,math.abs(ax*bx+ay*by+az*bz+aw*bw))
            mod:info('DARKTIDEVR_GUN_AIM weapon=%s source=controller aim_angle_deg=%.4f grip_error_m=%.6f',
                tostring(template.name),math.deg(2*math.acos(dot)),Vector3.distance(Unit.world_position(unit,attach),grip))
        end
    end
    function instance.update(world,unit)
        local ok,message=pcall(update,world,unit)
        if not ok then
            pcall(restore,world)
            instance.failures=instance.failures+1
            if instance.failures==1 then
                mod:info('DARKTIDEVR_GUN_AIM fallback=%s',tostring(message):sub(1,160))
            end
        end
    end
    return instance
end
return Alignment
