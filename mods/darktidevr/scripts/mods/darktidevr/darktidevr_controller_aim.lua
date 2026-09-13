local controller_aim = {}
local MultiFireModes = require(
    "scripts/settings/equipment/weapon_templates/multi_fire_modes")
local Health = require("scripts/utilities/health")
local HitZone = require("scripts/utilities/attack/hit_zone")

function controller_aim.is_reticle_surface(is_self, is_static, damageable, hit_zone)
    -- Darktide's "afro" actor is the oversized suppression/near-miss volume.
    -- HitScan processes suppression there and continues past it without impact.
    return not is_self and hit_zone ~= "afro" and
        (is_static or (damageable and hit_zone ~= nil))
end

local function query_active_mode()
    local presentation = controller_aim.presentation
    if presentation and presentation.current_game_mode_name then
        return presentation.current_game_mode_name()
    end
    local manager = Managers and Managers.state and Managers.state.game_mode
    return manager and manager:game_mode_name() or nil
end

local function active_mode()
    local ok, mode = pcall(query_active_mode)
    return ok and type(mode) == "string" and mode or nil
end

local function is_private_range()
    local mode = active_mode()
    return mode == "shooting_range" or mode == "training_grounds"
end

local function is_local_unit(unit)
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager:local_player(1)
    return player and player.player_unit == unit
end

local function attachment_set_contains(attachment_set, unit)
    if attachment_set == nil then return false end
    for _, attachments in pairs(attachment_set) do
        for index = 1, #attachments do
            if unit == attachments[index] then return true end
        end
    end
    return false
end

local function is_local_visual_unit(extension, unit)
    local owner = extension and extension._unit
    if not owner or not unit then
        return false
    end
    if unit == owner then
        return true
    end
    local visual = ScriptUnit.has_extension(owner, "visual_loadout_system")
    if not visual then
        return false
    end
    if unit == visual._first_person_unit then
        return true
    end
    local equipment = visual._equipment
    if not equipment then return false end
    for _, slot in pairs(equipment) do
        if type(slot) == "table" then
            if unit == slot.unit_1p or unit == slot.unit_3p then
                return true
            end
            if attachment_set_contains(slot.attachments_by_unit_1p, unit) or
                    attachment_set_contains(slot.attachments_by_unit_3p, unit) then
                return true
            end
        end
    end
    return false
end

local function has_keyword(keywords, wanted)
    if type(keywords) ~= "table" then
        return false
    end
    for i = 1, #keywords do
        if keywords[i] == wanted then
            return true
        end
    end
    return false
end

local function is_force_staff(action)
    local template = action and action._weapon_template
    return template and has_keyword(template.keywords, "force_staff")
end

local function packed(...)
    return {n = select("#", ...), ...}
end

local function simulated_melee_visual_rotation(unit)
    local extension = ScriptUnit.has_extension(unit, "first_person_system")
    if not extension or extension._unit ~= unit or not extension._is_local_unit then return end
    local component = extension._first_person_component
    return component and component.rotation
end

local function finish_first_person_pose(action, component, ok, ...)
    action._first_person_component = component
    if not ok then
        error((...), 0)
    end
    return ...
end

local function with_first_person_pose(action, position, rotation, func, ...)
    local component = action and action._first_person_component
    if not component or not position or not rotation then
        return func(action, ...)
    end
    -- Weapon actions receive a read-only unit-data component. Never write it:
    -- substitute a scoped Lua read proxy on this action/module only, so all
    -- fields except the tracked pose continue to resolve from Darktide's live
    -- component and no other consumer observes the temporary ownership.
    local proxy = setmetatable({
        position = position,
        rotation = rotation,
    }, {
        __index = function(_, key)
            return component[key]
        end,
    })
    action._first_person_component = proxy
    return finish_first_person_pose(action, component, pcall(func, action, ...))
end

function controller_aim.install(mod, presentation, state)
    if controller_aim.installed then
        return controller_aim
    end
    controller_aim.installed = true
    controller_aim.presentation = presentation
    controller_aim.state = state
    controller_aim.last_log_sequence = 0
    controller_aim.authored_shots = 0
    controller_aim.reused_simultaneous_shots = 0
    controller_aim.network_writes = 0
    controller_aim.last_origin_offset = 0
    controller_aim.muzzle_origin_writes = 0
    controller_aim.muzzle_origin_fallbacks = 0
    controller_aim.staff_primary_writes = 0
    controller_aim.staff_secondary_writes = 0
    controller_aim.staff_tip_fallbacks = 0
    controller_aim.lightning_pose_writes = 0
    controller_aim.melee_pose_writes = 0
    controller_aim.reticle_publishes = 0
    controller_aim.reticle_hits = 0
    controller_aim.reticle_static_hits = 0
    controller_aim.reticle_damage_hits = 0
    controller_aim.reticle_misses = 0
    controller_aim.reticle_failures = 0
    controller_aim.reticle_self_skips = 0
    controller_aim.reticle_non_surface_skips = 0
    controller_aim.reticle_suppression_skips = 0
    controller_aim.last_reticle_log_sequence = 0
    controller_aim.reticle_world_point = nil
    controller_aim.reticle_point_sequence = 0
    controller_aim.reticle_point_owner = nil
    controller_aim.reticle_point_session = nil
    controller_aim.reticle_point_generation = nil
    controller_aim.converged_writes = 0
    controller_aim.convergence_fallbacks = 0

    function controller_aim.target(side)
        side = side or "dominant"
        if presentation.weapon_hand_roles then
            side = presentation.weapon_hand_roles.physical(side)
        elseif side == "dominant" then side = "right"
        elseif side == "support" then side = "left" end
        if side ~= "left" and side ~= "right" then return nil, nil end
        if not state.authoring_enabled then return nil, nil end
        local mode_allowed = presentation.is_controller_aim_mode and
            presentation.is_controller_aim_mode() or
            (not presentation.is_controller_aim_mode and is_private_range())
        if not mode_allowed then
            return nil, nil
        end
        if side == "left" then
            return presentation.left_controller_aim_target()
        end
        return presentation.controller_aim_target()
    end

    function controller_aim.melee_visual_rotation(unit)
        if not unit or not is_local_unit(unit) or not Unit.alive(unit) or
                not state.authoring_enabled then return end
        if presentation.online_rules and presentation.online_rules.simulation_aim_active(unit) then
            -- Presentation only: stock-input mode declines the action pose
            -- overrides, so use the same simulated aim as its sweep/preview.
            local ok, rotation = pcall(simulated_melee_visual_rotation, unit)
            return ok and rotation or nil
        end
        local _, rotation = controller_aim.target("dominant")
        return rotation
    end

    function controller_aim.clear_reticle()
        controller_aim.reticle_hit_unit = nil
        controller_aim.reticle_world_point = nil
        controller_aim.reticle_point_owner = nil
        controller_aim.reticle_point_session = nil
        controller_aim.reticle_point_generation = nil
    end

    function controller_aim.publish_reticle(extension, stock_position, stock_rotation)
        controller_aim.clear_reticle()
        local position, rotation = stock_position, stock_rotation
        if not position or not rotation then position, rotation = controller_aim.target("dominant") end
        local physics_world = extension and extension._physics_world
        if not position or not rotation or not physics_world then
            presentation.publish_gameplay_aim_state(false, false, 0)
            return
        end
        local direction = Quaternion.forward(rotation)
        local ok, hits, hit_count = pcall(
            PhysicsWorld.raycast,
            physics_world,
            position,
            direction,
            200,
            "all",
            "types",
            "both",
            "max_hits",
            64,
            "collision_filter",
            "filter_player_character_shooting_raycast")
        if not ok then
            controller_aim.reticle_failures =
                controller_aim.reticle_failures + 1
            presentation.publish_gameplay_aim_state(false, false, 0)
            if controller_aim.reticle_failures == 1 then
                mod:error(
                    "DARKTIDEVR_WEAPON_AIM reticle_raycast_failed error=%s",
                    tostring(hits))
            end
            return
        end
        local hit = false
        local hit_kind = "miss"
        local distance = nil
        local count = hit_count or (hits and #hits) or 0
        for i = 1, count do
            local candidate = hits[i]
            local candidate_position = candidate.position or candidate[1]
            local candidate_distance = candidate.distance or candidate[2]
            local candidate_actor = candidate.actor or candidate[4]
            local candidate_unit = candidate_actor and
                Actor.unit(candidate_actor) or nil
            -- A hand-origin ray begins inside parts of the local third-person
            -- avatar. Darktide's shot processing rejects its attacker unit
            -- after the all-hit query; do the same before selecting the
            -- reticle surface rather than clamping that zero-distance overlap.
            local is_self = is_local_visual_unit(extension, candidate_unit)
            local is_static = candidate_actor and
                Actor.is_static(candidate_actor)
            local is_damage_surface = false
            local hit_zone = candidate_unit and
                HitZone.get_name(candidate_unit, candidate_actor)
            if not is_static and candidate_unit then
                local damageable = Health.is_damagable(candidate_unit)
                is_damage_surface = controller_aim.is_reticle_surface(
                    is_self, false, damageable, hit_zone)
            end
            -- HitScan processes past local equipment and broad dynamic
            -- movement/capsule actors. Match that behavior for the visual
            -- convergence point: stop at static world geometry or at an
            -- actual damage hit-zone actor, not a character's outer capsule.
            if controller_aim.is_reticle_surface(
                    is_self, is_static, is_damage_surface, hit_zone) then
                distance = candidate_distance or candidate_position and
                    Vector3.distance(position, candidate_position)
                if distance then
                    hit = true
                    hit_kind = is_damage_surface and "damage" or "static"
                    controller_aim.reticle_hit_unit = candidate_unit
                    break
                end
            elseif is_self then
                controller_aim.reticle_self_skips =
                    controller_aim.reticle_self_skips + 1
            else
                controller_aim.reticle_non_surface_skips =
                    controller_aim.reticle_non_surface_skips + 1
                if hit_zone == "afro" then
                    controller_aim.reticle_suppression_skips =
                        controller_aim.reticle_suppression_skips + 1
                end
            end
        end
        distance = hit and distance or 50
        distance = math.max(0.05, math.min(200, distance or 50))
        controller_aim.reticle_distance = distance
        controller_aim.reticle_world_point = Vector3Box(position + direction * distance)
        controller_aim.reticle_point_sequence = state.last_sequence
        controller_aim.reticle_point_generation = state.last_transport_generation
        controller_aim.reticle_point_owner = extension._unit
        controller_aim.reticle_point_session = Managers and Managers.state and
            Managers.state.game_session
        if not presentation.publish_gameplay_aim_state(
                true, hit == true, distance, controller_aim.reticle_world_point:unbox()) then
            controller_aim.reticle_failures =
                controller_aim.reticle_failures + 1
            return
        end
        controller_aim.reticle_publishes =
            controller_aim.reticle_publishes + 1
        if hit then
            controller_aim.reticle_hits = controller_aim.reticle_hits + 1
            if hit_kind == "damage" then
                controller_aim.reticle_damage_hits =
                    controller_aim.reticle_damage_hits + 1
            else
                controller_aim.reticle_static_hits =
                    controller_aim.reticle_static_hits + 1
            end
        else
            controller_aim.reticle_misses = controller_aim.reticle_misses + 1
        end
        if state.last_sequence >=
                controller_aim.last_reticle_log_sequence + 600 then
            controller_aim.last_reticle_log_sequence = state.last_sequence
            mod:info(
                "DARKTIDEVR_WEAPON_AIM reticle sequence=%d distance_m=%.3f hit=%s kind=%s publishes=%d hits=%d static_hits=%d damage_hits=%d misses=%d self_skips=%d non_surface_skips=%d failures=%d suppression_skips=%d",
                state.last_sequence,
                distance,
                tostring(hit == true),
                hit_kind,
                controller_aim.reticle_publishes,
                controller_aim.reticle_hits,
                controller_aim.reticle_static_hits,
                controller_aim.reticle_damage_hits,
                controller_aim.reticle_misses,
                controller_aim.reticle_self_skips,
                controller_aim.reticle_non_surface_skips,
                controller_aim.reticle_failures,
                controller_aim.reticle_suppression_skips)
        end
    end

    function controller_aim.cached_reticle_target()
        local point = controller_aim.reticle_world_point
        local age = point and state.last_sequence - controller_aim.reticle_point_sequence
        local session = Managers and Managers.state and Managers.state.game_session
        -- Sequence restarts must not turn a previous world's point into a
        -- "fresh" negative-age sample, including a restart that advances past
        -- the old sequence before this consumer next runs.
        local fresh = point and age >= 0 and age <= 60 and
            controller_aim.reticle_point_generation == state.last_transport_generation and
            controller_aim.reticle_point_owner ~= nil and
            Unit.alive(controller_aim.reticle_point_owner) and
            controller_aim.reticle_point_session == session
        if fresh then
            local ok, is_owner = pcall(is_local_unit, controller_aim.reticle_point_owner)
            fresh = ok and is_owner == true
        end
        if not fresh then
            controller_aim.clear_reticle()
            return nil, nil
        end
        return point, controller_aim.reticle_hit_unit
    end

    function controller_aim.converged_rotation(origin, right_position,
            right_rotation)
        if not origin or not right_position or not right_rotation then
            return right_rotation, false
        end
        local cached = controller_aim.cached_reticle_target()
        local point = cached and cached:unbox()
        if not point then
            point = right_position + Quaternion.forward(right_rotation) * 50
            controller_aim.convergence_fallbacks =
                controller_aim.convergence_fallbacks + 1
        end
        local delta = point - origin
        if Vector3.length_squared(delta) <= 0.000001 then
            return right_rotation, false
        end
        controller_aim.converged_writes =
            controller_aim.converged_writes + 1
        return Quaternion.look(
            Vector3.normalize(delta), Quaternion.up(right_rotation)), true
    end

    function controller_aim.staff_tip(action)
        local fx_extension = action and action._fx_extension
        local source_name = action and action._muzzle_fx_source_name
        if not fx_extension or not source_name or
                type(fx_extension.vfx_spawner_unit_and_node) ~= "function" then
            return nil, nil
        end
        local ok, unit, node, unit_3p, node_3p = pcall(
            fx_extension.vfx_spawner_unit_and_node,
            fx_extension,
            source_name)
        if not ok then
            return nil, nil
        end
        local use_third_person = unit_3p and node_3p ~= nil and
            Unit.alive(unit_3p)
        local target_unit = use_third_person and unit_3p or unit
        local target_node = use_third_person and node_3p or node
        if not target_unit or not Unit.alive(target_unit) or
                target_node == nil then
            return nil, nil
        end
        local position_ok, position = pcall(
            Unit.world_position, target_unit, target_node)
        local rotation_ok, rotation = pcall(
            Unit.world_rotation, target_unit, target_node)
        if not position_ok or not rotation_ok then
            return nil, nil
        end
        return position, rotation
    end

    function controller_aim.projectile_target(action)
        local template = action and action._weapon_template
        local knife_settings = action and action._action_settings
        local name = template and template.name
        -- Psyker targeting consumes the existing hand-authored smart-target
        -- result; preserve sticky-target and homing rules at launch.
        local knife = knife_settings and knife_settings.kind == "spawn_projectile" and
            not knife_settings.spawn_node and not knife_settings.track_towards_position and
            ((name == "zealot_throwing_knives" and not knife_settings.track_towards_target) or
             (name == "psyker_throwing_knives" and knife_settings.track_towards_target and
              knife_settings.target_finder_module_class_name == "smart_target_targeting"))
        if knife then
            local position, rotation = controller_aim.target("dominant")
            return position, rotation, "knife_dominant_aim"
        end
        if not is_force_staff(action) then
            return nil, nil, nil
        end
        local right_position, right_rotation =
            controller_aim.target("dominant")
        if not right_rotation then
            return nil, nil, nil
        end
        local settings = action._action_settings
        if settings and settings.use_charge then
            local position = controller_aim.staff_tip(action)
            if position then
                local rotation = controller_aim.converged_rotation(
                    position, right_position, right_rotation)
                return position, rotation, "staff_tip_converged_aim"
            end
            controller_aim.staff_tip_fallbacks =
                controller_aim.staff_tip_fallbacks + 1
            return right_position, right_rotation,
                "staff_tip_fallback_dominant"
        end
        local left_position = controller_aim.target("support")
        local rotation = controller_aim.converged_rotation(
            left_position, right_position, right_rotation)
        return left_position, rotation, "support_origin_converged_aim"
    end

    function controller_aim.third_person_muzzle(action, prepared_shots)
        local fx_extension = action._fx_extension
        local action_component = action._action_component
        if not fx_extension or
                type(fx_extension.vfx_spawner_unit_and_node) ~= "function" or
                not action_component then
            return nil
        end
        local fire_configurations = action:_fire_configurations()
        local fire_config = fire_configurations and
            fire_configurations[action_component.current_fire_config]
        if not fire_config then
            return nil
        end
        local source_name
        local fx = action._action_settings and action._action_settings.fx
        if fx and fx.alternate_muzzle_flashes then
            -- Called before stock preparation advances the shot counter.
            local prepared_index = math.max(0, prepared_shots or action_component.num_shots_fired)
            source_name = prepared_index % 2 == 0 and
                action._muzzle_fx_source_name or
                action._muzzle_fx_source_secondary_name
        else
            local source_ok, source = pcall(
                action._muzzle_fx_source, action)
            source_name = source_ok and source or nil
        end
        if not source_name then
            return nil
        end
        local attachment_ok, attachment = pcall(
            action._reference_attachment_id, action, fire_config)
        if not attachment_ok then
            attachment = nil
        end
        local pose_ok, unit, node, unit_3p, node_3p = pcall(
            fx_extension.vfx_spawner_unit_and_node,
            fx_extension,
            source_name,
            attachment)
        if not pose_ok then
            return nil
        end
        local use_third_person = unit_3p and node_3p ~= nil and
            Unit.alive(unit_3p)
        local target_unit = use_third_person and unit_3p or unit
        local target_node = use_third_person and node_3p or node
        if not target_unit or not Unit.alive(target_unit) or
                target_node == nil then
            return nil
        end
        local position_ok, position = pcall(
            Unit.world_position, target_unit, target_node)
        local rotation_ok, rotation = pcall(
            Unit.world_rotation, target_unit, target_node)
        return position_ok and position or nil, rotation_ok and rotation or nil
    end

    local PlayerUnitAimExtension = require(
        "scripts/extension_systems/aim/player_unit_aim_extension")
    mod:hook_safe(
        PlayerUnitAimExtension,
        "fixed_update",
        function(self, unit)
            if not self._is_server or not is_local_unit(unit) then
                return
            end
            local _, aim_rotation = controller_aim.target()
            if not aim_rotation or not self._game_session_id or
                    not self._game_object_id then
                return
            end
            local direction = Quaternion.forward(aim_rotation)
            GameSession.set_game_object_field(
                self._game_session_id,
                self._game_object_id,
                "aim_direction",
                direction)
            controller_aim.network_writes =
                controller_aim.network_writes + 1
        end)

    function controller_aim.with_ranged_pose(action, func, ...)
        if not is_local_unit(action._player_unit) then
            return func(action, ...)
        end
        local position, rotation = controller_aim.target("dominant")
        if not position or not rotation or not action._first_person_component then
            return func(action, ...)
        end
        local muzzle = controller_aim.third_person_muzzle(action)
        if muzzle then
            rotation = controller_aim.converged_rotation(muzzle, position, rotation)
            position = muzzle
            controller_aim.muzzle_origin_writes = controller_aim.muzzle_origin_writes + 1
        else
            controller_aim.muzzle_origin_fallbacks = controller_aim.muzzle_origin_fallbacks + 1
        end
        return with_first_person_pose(action, position, rotation, func, ...)
    end

    function controller_aim.prepare_ranged_shot(func, action, ...)
        local component = action._action_component
        local before = component and component.num_shots_fired
        -- Supply the hand pose before stock recoil/sway/assist/spread and muzzle
        -- FX run. Stock code owns simultaneous grouping and writes the prepared
        -- pair once; never rebase that pair after its shot counter advances.
        local results = packed(controller_aim.with_ranged_pose(action, func, ...))
        if is_local_unit(action._player_unit) and controller_aim.target("dominant") and
                component and type(before) == "number" then
            local configurations = action._base_fire_configurations
            local first = action._multi_fire_mode ~= MultiFireModes.simultaneous or
                configurations and #configurations > 0 and
                (before + 1) % #configurations == 1
            if first then
                controller_aim.authored_shots = controller_aim.authored_shots + 1
            else
                controller_aim.reused_simultaneous_shots = controller_aim.reused_simultaneous_shots + 1
            end
            if controller_aim.authored_shots <= 4 or
                    state.last_sequence >= controller_aim.last_log_sequence + 120 then
                controller_aim.last_log_sequence = state.last_sequence
                mod:info("DARKTIDEVR_WEAPON_AIM ranged class=%s sequence=%d shots=%d reused=%d",
                    tostring(action.__class_name), state.last_sequence,
                    controller_aim.authored_shots, controller_aim.reused_simultaneous_shots)
            end
        end
        return unpack(results, 1, results.n)
    end

    -- Stingray class() copies base members. Hook each concrete shooting class:
    -- replacing ActionShoot after derived classes exist cannot update their
    -- copied _prepare_shooting members. Load all classes before installing hooks.
    local ranged_classes = {}
    for _, name in ipairs({"action_shoot_hit_scan", "action_shoot_pellets",
            "action_shoot_projectile", "action_flamer_gas", "action_flamer_gas_burst"}) do
        ranged_classes[#ranged_classes + 1] = require(
            "scripts/extension_systems/weapon/actions/" .. name)
    end
    for _, class in ipairs(ranged_classes) do
        mod:hook(class, "_prepare_shooting", controller_aim.prepare_ranged_shot)
    end
    for index = 4, 5 do
        -- Flame damage and suppression query the camera directly, independently
        -- of the prepared shot. Both must consume the same hand-authored pose.
        for _, method in ipairs({"_acquire_targets", "_acquire_suppressed_units"}) do
            mod:hook(ranged_classes[index], method, function(func, self, ...)
                return controller_aim.with_ranged_pose(self, func, ...)
            end)
        end
    end

    local ActionSpawnProjectile = require(
        "scripts/extension_systems/weapon/actions/action_spawn_projectile")
    mod:hook(
        ActionSpawnProjectile,
        "_spawn_projectile_unit",
        function(func, self, ...)
            if not is_local_unit(self._player_unit) then
                return func(self, ...)
            end
            local position, rotation, owner =
                controller_aim.projectile_target(self)
            if not position or not rotation then
                return func(self, ...)
            end
            if owner == "knife_dominant_aim" then
                return with_first_person_pose(self, position, rotation, func, ...)
            end
            if owner == "support_origin_converged_aim" then
                controller_aim.staff_primary_writes =
                    controller_aim.staff_primary_writes + 1
            else
                controller_aim.staff_secondary_writes =
                    controller_aim.staff_secondary_writes + 1
            end
            local source_count = owner == "support_origin_converged_aim" and
                controller_aim.staff_primary_writes or
                controller_aim.staff_secondary_writes
            if source_count <= 4 then
                local direction = Quaternion.forward(rotation)
                mod:info(
                    "DARKTIDEVR_WEAPON_AIM psyker_projectile owner=%s count=%d origin=%.4f,%.4f,%.4f converged_direction=%.4f,%.4f,%.4f",
                    owner,
                    source_count,
                    Vector3.x(position),
                    Vector3.y(position),
                    Vector3.z(position),
                    Vector3.x(direction),
                    Vector3.y(direction),
                    Vector3.z(direction))
            end
            return with_first_person_pose(self, position, rotation, func, ...)
        end)
    mod:hook(
        ActionSpawnProjectile,
        "_fire_projectile",
        function(func, self, ...)
            if not is_local_unit(self._player_unit) then
                return func(self, ...)
            end
            if presentation.projectile_visual and presentation.online_rules and
                    presentation.online_rules.simulation_aim_active(self._player_unit) then
                return presentation.projectile_visual.fire_projectile(func, self, ...)
            end
            local position, rotation = controller_aim.projectile_target(self)
            if not position or not rotation then
                return func(self, ...)
            end
            return with_first_person_pose(self, position, rotation, func, ...)
        end)

    function controller_aim.with_weapon_throw_pose(action, func, ...)
        local settings = action._action_settings
        local template = action._weapon_template
        -- Audited dual-shiv specials use straight launch parameters. Node-based
        -- origins and homing/position modules need their own ownership policy.
        if not is_local_unit(action._player_unit) or not settings or
                settings.kind ~= "weapon_throw" or settings.spawn_node or
                settings.track_towards_target or settings.track_towards_position or
                not template or not has_keyword(template.keywords,"dual_shivs") then
            return func(action,...)
        end
        local position,rotation = controller_aim.target("dominant")
        return with_first_person_pose(action,position,rotation,func,...)
    end
    local ActionWeaponThrow = require(
        "scripts/extension_systems/weapon/actions/action_weapon_throw")
    for _,method in ipairs({"_spawn_projectile_unit","_fire_projectile"}) do
        -- Stingray copies inherited methods into concrete classes; hooking only
        -- ActionSpawnProjectile can miss an already-created ActionWeaponThrow.
        mod:hook(ActionWeaponThrow,method,function(func,self,...)
            return controller_aim.with_weapon_throw_pose(self,func,...)
        end)
    end

    function controller_aim.with_melee_aim(action, func, ...)
        if not is_local_unit(action._player_unit) then
            return func(action, ...)
        end
        local _, rotation = controller_aim.target("dominant")
        local component = action._first_person_component
        if not rotation or not component then
            return func(action, ...)
        end
        -- Keep the authored sweep's origin/reach and animation timing. Only
        -- its orientation follows the hand; movement's shared component is
        -- never changed by this action-local read proxy.
        controller_aim.melee_pose_writes = controller_aim.melee_pose_writes + 1
        if controller_aim.melee_pose_writes <= 4 then
            mod:info("DARKTIDEVR_MELEE aim=right_hand stock_origin=true count=%d",
                controller_aim.melee_pose_writes)
        end
        if controller_aim.melee_pose_writes % 120 == 1 and Quaternion then
            local hand_forward = Quaternion.forward(rotation)
            local head_forward = Quaternion.forward(component.rotation)
            mod:info("DARKTIDEVR_MELEE direction hand=%.3f,%.3f,%.3f head=%.3f,%.3f,%.3f",
                Vector3.x(hand_forward), Vector3.y(hand_forward), Vector3.z(hand_forward),
                Vector3.x(head_forward), Vector3.y(head_forward), Vector3.z(head_forward))
        end
        local extension = action._first_person_extension
        if extension and extension.is_within_default_view then
            local view = setmetatable({
                _first_person_component = setmetatable({
                    position = component.position, rotation = rotation,
                }, {__index = component}),
            }, {__index = extension})
            action._first_person_extension = setmetatable({
                is_within_default_view = function(_, position)
                    return extension.is_within_default_view(view, position)
                end,
            }, {__index = function(_, key)
                local value = extension[key]
                if type(value) == "function" then
                    return function(_, ...) return value(extension, ...) end
                end
                return value
            end})
        end
        local results = packed(pcall(with_first_person_pose,
            action, component.position, rotation, func, ...))
        action._first_person_extension = extension
        if not results[1] then error(results[2], 0) end
        return unpack(results, 2, results.n)
    end

    for _, entry in ipairs({
        {"action_sweep", "start"},
        {"action_sweep", "_update_sweep"},
        {"action_push", "_push"},
        {"action_melee_explosive", "_find_explosion_position_and_direction"},
    }) do
        local observe_start = entry[1] == "action_sweep" and entry[2] == "start"
        mod:hook(require("scripts/extension_systems/weapon/actions/" .. entry[1]),
            entry[2], function(func, self, ...)
                if not observe_start then
                    return controller_aim.with_melee_aim(self, func, ...)
                end
                local result = packed(controller_aim.with_melee_aim(self, func, ...))
                local preview = presentation.melee_preview
                if preview and preview.on_action_start then
                    local ok, err = pcall(preview.on_action_start, self, ...)
                    if not ok then
                        mod:warning("DARKTIDEVR_MELEE comparison_error=%s", tostring(err))
                    end
                end
                return unpack(result, 1, result.n)
            end)
    end

    function controller_aim.with_dominant_aim(action, func, ...)
        if not is_local_unit(action._player_unit) then
            return func(action, ...)
        end
        local position, rotation = controller_aim.target("dominant")
        if not position or not rotation then
            return func(action, ...)
        end
        controller_aim.lightning_pose_writes =
            controller_aim.lightning_pose_writes + 1
        if controller_aim.lightning_pose_writes <= 4 then
            local direction = Quaternion.forward(rotation)
            mod:info(
                "DARKTIDEVR_WEAPON_AIM lightning dominant_aim count=%d origin=%.4f,%.4f,%.4f direction=%.4f,%.4f,%.4f",
                controller_aim.lightning_pose_writes,
                Vector3.x(position),
                Vector3.y(position),
                Vector3.z(position),
                Vector3.x(direction),
                Vector3.y(direction),
                Vector3.z(direction))
        end
        return with_first_person_pose(action, position, rotation, func, ...)
    end

    local ChainLightningTargetingActionModule = require(
        "scripts/extension_systems/weapon/actions/modules/chain_lightning_targeting_action_module")
    mod:hook(
        ChainLightningTargetingActionModule,
        "fixed_update",
        function(func, self, ...)
            return controller_aim.with_dominant_aim(self, func, ...)
        end)
    local PsykerChainLightningSingleTargetingActionModule = require(
        "scripts/extension_systems/weapon/actions/modules/psyker_chain_lightning_single_targeting_action_module")
    mod:hook(
        PsykerChainLightningSingleTargetingActionModule,
        "fixed_update",
        function(func, self, ...)
            return controller_aim.with_dominant_aim(self, func, ...)
        end)
    local ActionChainLightning = require(
        "scripts/extension_systems/weapon/actions/action_chain_lightning")
    mod:hook(
        ActionChainLightning,
        "_deal_damage",
        function(func, self, ...)
            return controller_aim.with_dominant_aim(self, func, ...)
        end)

    local PlayerUnitSmartTargetingExtension = require(
        "scripts/extension_systems/smart_targeting/player_unit_smart_targeting_extension")
    mod:hook(PlayerUnitSmartTargetingExtension, "force_update_smart_tag_targets",
        function(func, self, ...)
            local position, rotation = controller_aim.target("dominant")
            if not is_local_unit(self._unit) or not position or not rotation then
                return func(self, ...)
            end
            return with_first_person_pose(self, position, rotation, func, ...)
        end)
    local InteractorExtension = require("scripts/extension_systems/interaction/interactor_extension")
    for _, method in ipairs({"_find_interaction_object", "_find_interaction_object_3p",
            "_check_valid_ongoing_interaction"}) do
        mod:hook(InteractorExtension, method, function(func, self, ...)
            local position, rotation = controller_aim.target("dominant")
            if not is_local_unit(self._unit) or not position or not rotation then
                return func(self, ...)
            end
            return with_first_person_pose(self, position, rotation, func, ...)
        end)
    end
    mod:hook(
        PlayerUnitSmartTargetingExtension,
        "fixed_update",
        function(func, self, unit, dt, t, ...)
            -- SoloPlay bots are local simulation units too. Their stock
            -- targeting must run, but only the current human player may
            -- publish or clear the one shared VR crosshair.
            if not self._is_local_unit or not is_local_unit(self._unit) then
                return func(self, unit, dt, t, ...)
            end
            if presentation.online_rules and presentation.online_rules.enabled() then
                local result = func(self, unit, dt, t, ...)
                if presentation.weapon_assist then presentation.weapon_assist.observe(self,t) end
                local component = self._first_person_component
                local position, rotation
                if presentation.online_reticle then
                    position, rotation = presentation.online_reticle.pose(self, t)
                elseif component then position, rotation = component.position, component.rotation end
                if position and rotation then
                    controller_aim.publish_reticle(self, position, rotation)
                else
                    controller_aim.clear_reticle()
                    presentation.publish_gameplay_aim_state(false, false, 0)
                end
                return result
            end
            local position, rotation = controller_aim.target("dominant")
            -- Keyboard and mouse in a private range with no hand ray to use:
            -- stock targeting already follows the mouse-authored first-person
            -- pose, so the reticle reads it. A tracked hand keeps its own aim.
            if (not position or not rotation) and
                    presentation.keyboard_mouse_enabled and presentation.keyboard_mouse_enabled() and
                    presentation.is_controller_aim_mode and presentation.is_controller_aim_mode() then
                local result = func(self, unit, dt, t, ...)
                local component = self._first_person_component
                if component and component.position and component.rotation then
                    controller_aim.publish_reticle(self, component.position, component.rotation)
                else
                    controller_aim.clear_reticle()
                    presentation.publish_gameplay_aim_state(false, false, 0)
                end
                return result
            end
            if not position or not rotation then
                controller_aim.clear_reticle()
                presentation.publish_gameplay_aim_state(false, false, 0)
                return func(self, unit, dt, t, ...)
            end
            local result = with_first_person_pose(
                self, position, rotation, func, unit, dt, t, ...)
            controller_aim.publish_reticle(self)
            return result
        end)

    mod:command(
        "dtvr_controller_aim_status",
        "Report controller-authored ranged aim state",
        function()
            local position, rotation = controller_aim.target()
            local direction = rotation and Quaternion.forward(rotation)
            mod:echo(
                "DARKTIDEVR_WEAPON_AIM enabled=%s mode=%s target=%s shots=%d reused=%d network_writes=%d muzzle_writes=%d muzzle_fallbacks=%d staff_primary=%d staff_secondary=%d staff_tip_fallbacks=%d lightning_pose_writes=%d reticle_publishes=%d reticle_hits=%d reticle_static_hits=%d reticle_damage_hits=%d reticle_misses=%d reticle_self_skips=%d reticle_non_surface_skips=%d reticle_failures=%d converged_writes=%d convergence_fallbacks=%d stock_origin_offset_m=%.4f direction=%s",
                tostring(state.authoring_enabled),
                tostring(active_mode()),
                tostring(position ~= nil),
                controller_aim.authored_shots,
                controller_aim.reused_simultaneous_shots,
                controller_aim.network_writes,
                controller_aim.muzzle_origin_writes,
                controller_aim.muzzle_origin_fallbacks,
                controller_aim.staff_primary_writes,
                controller_aim.staff_secondary_writes,
                controller_aim.staff_tip_fallbacks,
                controller_aim.lightning_pose_writes,
                controller_aim.reticle_publishes,
                controller_aim.reticle_hits,
                controller_aim.reticle_static_hits,
                controller_aim.reticle_damage_hits,
                controller_aim.reticle_misses,
                controller_aim.reticle_self_skips,
                controller_aim.reticle_non_surface_skips,
                controller_aim.reticle_failures,
                controller_aim.converged_writes,
                controller_aim.convergence_fallbacks,
                controller_aim.last_origin_offset,
                direction and string.format(
                    "%.4f,%.4f,%.4f",
                    Vector3.x(direction),
                    Vector3.y(direction),
                    Vector3.z(direction)) or "unavailable")
        end)

    mod:info(
        "DARKTIDEVR_WEAPON_AIM installed policy=private_range_controller_rotation_preserve_stock_offsets")
    return controller_aim
end

return controller_aim
