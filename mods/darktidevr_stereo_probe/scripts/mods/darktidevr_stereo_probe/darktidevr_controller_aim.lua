local controller_aim = {}
local MultiFireModes = require(
    "scripts/settings/equipment/weapon_templates/multi_fire_modes")

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

    function controller_aim.target()
        if not state.authoring_enabled or not is_private_range() then
            return nil, nil
        end
        return presentation.controller_aim_target()
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
            action.shooting_rotation = Quaternion.multiply(
                aim_rotation, authored_offset)
            local stock_position = action.shooting_position
            local muzzle_position = controller_aim.third_person_muzzle(self)
            if muzzle_position then
                action.shooting_position = muzzle_position
                controller_aim.muzzle_origin_writes =
                    controller_aim.muzzle_origin_writes + 1
            else
                controller_aim.muzzle_origin_fallbacks =
                    controller_aim.muzzle_origin_fallbacks + 1
            end
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

    mod:command(
        "dtvr_controller_aim_status",
        "Report controller-authored ranged aim state",
        function()
            local position, rotation = controller_aim.target()
            local direction = rotation and Quaternion.forward(rotation)
            mod:echo(
                "DARKTIDEVR_WEAPON_AIM enabled=%s mode=%s target=%s shots=%d reused=%d network_writes=%d muzzle_writes=%d muzzle_fallbacks=%d stock_origin_offset_m=%.4f direction=%s",
                tostring(state.authoring_enabled),
                tostring(active_mode()),
                tostring(position ~= nil),
                controller_aim.authored_shots,
                controller_aim.reused_simultaneous_shots,
                controller_aim.network_writes,
                controller_aim.muzzle_origin_writes,
                controller_aim.muzzle_origin_fallbacks,
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
