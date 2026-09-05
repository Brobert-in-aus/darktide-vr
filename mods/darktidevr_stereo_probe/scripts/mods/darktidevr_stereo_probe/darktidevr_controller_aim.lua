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

local function active_mode()
    local manager = Managers and Managers.state and Managers.state.game_mode
    if not manager or type(manager.game_mode_name) ~= "function" then
        return nil
    end
    local ok, mode = pcall(manager.game_mode_name, manager)
    return ok and mode or nil
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
    for _, slot in pairs(visual._equipment or {}) do
        if type(slot) == "table" then
            if unit == slot.unit_1p or unit == slot.unit_3p then
                return true
            end
            local attachment_sets = {
                slot.attachments_by_unit_1p,
                slot.attachments_by_unit_3p,
            }
            for _, attachment_set in pairs(attachment_sets) do
                for _, attachments in pairs(attachment_set) do
                    for index = 1, #attachments do
                        if unit == attachments[index] then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local function inverse(rotation)
    local x, y, z, w = Quaternion.to_elements(rotation)
    local length_squared = x * x + y * y + z * z + w * w
    if length_squared <= 0.0000001 then
        return Quaternion.identity()
    end
    return Quaternion.from_elements(
        -x / length_squared,
        -y / length_squared,
        -z / length_squared,
        w / length_squared)
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
    local results = packed(pcall(func, action, ...))
    action._first_person_component = component
    if not results[1] then
        error(results[2], 0)
    end
    return unpack(results, 2, results.n)
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
    controller_aim.converged_writes = 0
    controller_aim.convergence_fallbacks = 0

    function controller_aim.target(side)
        if not state.authoring_enabled or not is_private_range() then
            return nil, nil
        end
        if side == "left" then
            return presentation.left_controller_aim_target()
        end
        return presentation.controller_aim_target()
    end

    function controller_aim.publish_reticle(extension)
        local position, rotation = controller_aim.target("right")
        local physics_world = extension and extension._physics_world
        if not position or not rotation or not physics_world then
            controller_aim.reticle_world_point = nil
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
            controller_aim.reticle_world_point = nil
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
        controller_aim.reticle_world_point = position + direction * distance
        controller_aim.reticle_point_sequence = state.last_sequence
        if not presentation.publish_gameplay_aim_state(
                true, hit == true, distance) then
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

    function controller_aim.converged_rotation(origin, right_position,
            right_rotation)
        if not origin or not right_position or not right_rotation then
            return right_rotation, false
        end
        local point = controller_aim.reticle_world_point
        local fresh = point and state.last_sequence -
            controller_aim.reticle_point_sequence <= 60
        if not fresh then
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
        if not is_force_staff(action) then
            return nil, nil, nil
        end
        local right_position, right_rotation =
            controller_aim.target("right")
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
                "staff_tip_fallback_right"
        end
        local left_position = controller_aim.target("left")
        local rotation = controller_aim.converged_rotation(
            left_position, right_position, right_rotation)
        return left_position, rotation, "left_origin_converged_aim"
    end

    function controller_aim.third_person_muzzle(action)
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
            -- _prepare_shooting increments num_shots_fired before this safe
            -- hook runs. Reconstruct the source selected for the shot that was
            -- just prepared instead of accidentally choosing the next barrel.
            local prepared_index = math.max(
                0, action_component.num_shots_fired - 1)
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
        return position_ok and position or nil
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

    local ActionShoot = require(
        "scripts/extension_systems/weapon/actions/action_shoot")
    mod:hook_safe(
        ActionShoot,
        "_prepare_shooting",
        function(self)
            if not is_local_unit(self._player_unit) then
                return
            end
            local aim_position, aim_rotation = controller_aim.target()
            local component = self._first_person_component
            local action = self._action_component
            if not aim_rotation or not component or not action or
                    not component.rotation or not action.shooting_rotation then
                return
            end

            -- ActionShoot only authors shooting_position/rotation for the
            -- first projectile in a simultaneous group. Later calls reuse the
            -- already prepared pair. Rebasing those calls again would treat
            -- our controller-authored rotation as a stock camera offset and
            -- compound the controller transform across the group.
            local configurations = self._base_fire_configurations
            local first_projectile = self._multi_fire_mode ~=
                    MultiFireModes.simultaneous or
                configurations and #configurations > 0 and
                (action.num_shots_fired + 1) % #configurations == 1
            if not first_projectile then
                controller_aim.reused_simultaneous_shots =
                    controller_aim.reused_simultaneous_shots + 1
                return
            end

            -- Darktide has already applied recoil, sway, aim assist and spread
            -- to the stock camera rotation. Preserve that complete local
            -- offset, then move its base from the HMD to the controller aim.
            local authored_offset = Quaternion.multiply(
                inverse(component.rotation), action.shooting_rotation)
            local stock_position = action.shooting_position
            local muzzle_position = controller_aim.third_person_muzzle(self)
            if muzzle_position then
                action.shooting_position = muzzle_position
                aim_rotation = controller_aim.converged_rotation(
                    muzzle_position, aim_position, aim_rotation)
                controller_aim.muzzle_origin_writes =
                    controller_aim.muzzle_origin_writes + 1
            else
                controller_aim.muzzle_origin_fallbacks =
                    controller_aim.muzzle_origin_fallbacks + 1
            end
            action.shooting_rotation = Quaternion.multiply(
                aim_rotation, authored_offset)
            if aim_position and stock_position then
                controller_aim.last_origin_offset = Vector3.distance(
                    aim_position, stock_position)
            end
            controller_aim.authored_shots =
                controller_aim.authored_shots + 1
            if state.last_sequence >=
                    controller_aim.last_log_sequence + 120 then
                local direction = Quaternion.forward(action.shooting_rotation)
                controller_aim.last_log_sequence = state.last_sequence
                mod:info(
                    "DARKTIDEVR_WEAPON_AIM authored sequence=%d shots=%d reused=%d network_writes=%d muzzle_writes=%d muzzle_fallbacks=%d stock_origin_offset_m=%.4f direction=%.4f,%.4f,%.4f",
                    state.last_sequence,
                    controller_aim.authored_shots,
                    controller_aim.reused_simultaneous_shots,
                    controller_aim.network_writes,
                    controller_aim.muzzle_origin_writes,
                    controller_aim.muzzle_origin_fallbacks,
                    controller_aim.last_origin_offset,
                    Vector3.x(direction),
                    Vector3.y(direction),
                    Vector3.z(direction))
            end
        end)

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
            if owner == "left_origin_converged_aim" then
                controller_aim.staff_primary_writes =
                    controller_aim.staff_primary_writes + 1
            else
                controller_aim.staff_secondary_writes =
                    controller_aim.staff_secondary_writes + 1
            end
            local source_count = owner == "left_origin_converged_aim" and
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
            local position, rotation = controller_aim.projectile_target(self)
            if not position or not rotation then
                return func(self, ...)
            end
            return with_first_person_pose(self, position, rotation, func, ...)
        end)

    function controller_aim.with_melee_aim(action, func, ...)
        if not is_local_unit(action._player_unit) then
            return func(action, ...)
        end
        local _, rotation = controller_aim.target("right")
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
        mod:hook(require("scripts/extension_systems/weapon/actions/" .. entry[1]),
            entry[2], function(func, self, ...)
                return controller_aim.with_melee_aim(self, func, ...)
            end)
    end

    function controller_aim.with_right_aim(action, func, ...)
        if not is_local_unit(action._player_unit) then
            return func(action, ...)
        end
        local position, rotation = controller_aim.target("right")
        if not position or not rotation then
            return func(action, ...)
        end
        controller_aim.lightning_pose_writes =
            controller_aim.lightning_pose_writes + 1
        if controller_aim.lightning_pose_writes <= 4 then
            local direction = Quaternion.forward(rotation)
            mod:info(
                "DARKTIDEVR_WEAPON_AIM lightning right_aim count=%d origin=%.4f,%.4f,%.4f direction=%.4f,%.4f,%.4f",
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
            return controller_aim.with_right_aim(self, func, ...)
        end)
    local PsykerChainLightningSingleTargetingActionModule = require(
        "scripts/extension_systems/weapon/actions/modules/psyker_chain_lightning_single_targeting_action_module")
    mod:hook(
        PsykerChainLightningSingleTargetingActionModule,
        "fixed_update",
        function(func, self, ...)
            return controller_aim.with_right_aim(self, func, ...)
        end)
    local ActionChainLightning = require(
        "scripts/extension_systems/weapon/actions/action_chain_lightning")
    mod:hook(
        ActionChainLightning,
        "_deal_damage",
        function(func, self, ...)
            return controller_aim.with_right_aim(self, func, ...)
        end)

    local PlayerUnitSmartTargetingExtension = require(
        "scripts/extension_systems/smart_targeting/player_unit_smart_targeting_extension")
    mod:hook(PlayerUnitSmartTargetingExtension, "force_update_smart_tag_targets",
        function(func, self, ...)
            local position, rotation = controller_aim.target("right")
            if not is_local_unit(self._unit) or not position or not rotation then
                return func(self, ...)
            end
            return with_first_person_pose(self, position, rotation, func, ...)
        end)
    local InteractorExtension = require("scripts/extension_systems/interaction/interactor_extension")
    for _, method in ipairs({"_find_interaction_object", "_find_interaction_object_3p",
            "_check_valid_ongoing_interaction"}) do
        mod:hook(InteractorExtension, method, function(func, self, ...)
            local position, rotation = controller_aim.target("right")
            if not is_local_unit(self._unit) or not position or not rotation then
                return func(self, ...)
            end
            return with_first_person_pose(self, position, rotation, func, ...)
        end)
    end
    mod:hook(
        PlayerUnitSmartTargetingExtension,
        "fixed_update",
        function(func, self, ...)
            if not self._is_local_unit then
                return func(self, ...)
            end
            local position, rotation = controller_aim.target("right")
            if not position or not rotation then
                presentation.publish_gameplay_aim_state(false, false, 0)
                return func(self, ...)
            end
            local result = with_first_person_pose(
                self, position, rotation, func, ...)
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
