local controller_aim = {}

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
    controller_aim.network_writes = 0

    function controller_aim.target()
        if not state.authoring_enabled or not is_private_range() then
            return nil, nil
        end
        return presentation.controller_aim_target()
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

    mod:hook_safe(
        PlayerUnitAimExtension,
        "update",
        function(self, unit)
            if not is_local_unit(unit) or not self._aim_constraint_variable or
                    not unit or not Unit.alive(unit) then
                return
            end
            local _, aim_rotation = controller_aim.target()
            if not aim_rotation then
                return
            end
            local height = self._first_person_extension:
                extrapolated_character_height()
            local root_position = Unit.local_position(unit, 1) +
                height * Vector3.up()
            local target = root_position + Quaternion.forward(aim_rotation) *
                self._aim_contraint_distance
            Unit.animation_set_constraint_target(
                unit, self._aim_constraint_variable, target)
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
            local _, aim_rotation = controller_aim.target()
            local component = self._first_person_component
            local action = self._action_component
            if not aim_rotation or not component or not action or
                    not component.rotation or not action.shooting_rotation then
                return
            end

            -- Darktide has already applied recoil, sway, aim assist and spread
            -- to the stock camera rotation. Preserve that complete local
            -- offset, then move its base from the HMD to the controller aim.
            local authored_offset = Quaternion.multiply(
                inverse(component.rotation), action.shooting_rotation)
            action.shooting_rotation = Quaternion.multiply(
                aim_rotation, authored_offset)
            controller_aim.authored_shots =
                controller_aim.authored_shots + 1
            if state.last_sequence >=
                    controller_aim.last_log_sequence + 120 then
                local direction = Quaternion.forward(action.shooting_rotation)
                controller_aim.last_log_sequence = state.last_sequence
                mod:info(
                    "DARKTIDEVR_WEAPON_AIM authored sequence=%d shots=%d network_writes=%d direction=%.4f,%.4f,%.4f",
                    state.last_sequence,
                    controller_aim.authored_shots,
                    controller_aim.network_writes,
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
                "DARKTIDEVR_WEAPON_AIM enabled=%s mode=%s target=%s shots=%d network_writes=%d direction=%s",
                tostring(state.authoring_enabled),
                tostring(active_mode()),
                tostring(position ~= nil),
                controller_aim.authored_shots,
                controller_aim.network_writes,
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
