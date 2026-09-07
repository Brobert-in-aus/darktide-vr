-- Controller aim owns direction; controller grip owns weapon placement.
-- The animated hand model is never an input to gameplay aim or the grip target.
local Alignment={}
local guns={shoot_hit_scan=true,shoot_pellets=true,shoot_projectile=true}
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
    local instance={failures=0,writes=0}
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
        if presentation.weapon_hand_roles.physical('dominant')~='right' then return end
        local weapon=ScriptUnit.has_extension(unit,'weapon_system')
        local template=weapon and weapon:weapon_template()
        if not Alignment.is_gun(template) then return end
        local settings=weapon:running_action_settings()
        if settings and (settings.kind=='reload_shotgun' or settings.kind=='reload_state' or
                settings.kind=='reload' or settings.kind=='sweep' or settings.kind=='push' or
                settings.kind=='unwield' or settings.kind=='ranged_wield') then return end
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
        local original_position=Unit.local_position(unit,attach)
        local desired_position=Matrix4x4.transform(Matrix4x4.inverse(Unit.world_pose(unit,parent)),grip)
        local desired=Alignment.rotation(Unit.world_rotation(unit,parent),
            Unit.world_rotation(unit,attach),Unit.world_rotation(muzzle_unit,muzzle_node),aim)
        saved={world=world,unit=unit,node=attach,original=QuaternionBox(original),written=QuaternionBox(desired),
            original_position=Vector3Box(original_position),written_position=Vector3Box(desired_position)}
        Unit.set_local_rotation(unit,attach,desired)
        Unit.set_local_position(unit,attach,desired_position)
        World.update_unit_and_children(world,unit)
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
