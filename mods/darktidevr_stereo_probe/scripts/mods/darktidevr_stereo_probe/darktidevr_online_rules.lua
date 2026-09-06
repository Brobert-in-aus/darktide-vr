-- Range proving mode: author only stock input columns. No action pose proxy,
-- origin override, extra movement velocity, damage rule or custom RPC.
local Rules = {}
local ranges = {shooting_range=true}
local controllable = {walking=true, sprinting=true, sliding=true,
    jumping=true, falling=true, dodging=true, interacting=true}
local movement_names = {"move_right", "move_left", "move_forward", "move_backward"}
local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end

function Rules.install(mod, presentation, state, mode_name)
    local instance = {frames=0, failures=0}
    local session_owner, selected
    local orientation_owners = setmetatable({}, {__mode="k"})
    -- Walking alone does not imply free aim: chainsaw locks, forced look and
    -- sweep stickiness select another orientation object in the same state.
    -- Observe the stock selection that HumanGameplay makes immediately before
    -- caching inputs. Do not replace it or eagerly load gameplay dependencies.
    mod:hook_require("scripts/managers/player/player_game_states/human_gameplay", function(class)
        mod:hook(class, "_player_orientation_class", function(func, self, ...)
            local orientation = func(self, ...)
            local handler = self._player and self._player.input_handler
            if handler then
                orientation_owners[handler] = orientation ~= nil and
                    orientation == self._default_player_orientation
            end
            return orientation
        end)
    end)
    local function enabled()
        local session = Managers and Managers.state and Managers.state.game_session
        if not ranges[mode_name()] then
            session_owner, selected = nil, nil
            return false
        end
        if not presentation.gameplay_context.local_authority(session) then
            return false
        end
        if session ~= session_owner then
            session_owner = session
            -- Readiness evidence belongs to this visit. A prior visit's first
            -- success/failure must not suppress diagnostics for a new session.
            instance.frames, instance.failures = 0, 0
            -- Latch on entering a session: switching rules during a charged
            -- attack would mix histories. The setting takes effect next visit.
            selected = mod:get("psykhanium_online_rules") ~= false
            mod:info("DARKTIDEVR_ONLINE_RULES range=%s enabled=%s origins=stock damage=stock",
                tostring(mode_name()), tostring(selected))
        end
        return selected
    end
    instance.enabled = enabled

    local function capture(handler, frame)
        if not enabled() or presentation.mode ~= 1 or
                not state.authoring_enabled or not state.gameplay_input_active or
                presentation.gameplay_context.ui_blocks_gameplay(Managers.ui) then return end
        local player = Managers.player and Managers.player:local_player(1)
        if not player or handler._player ~= player or not finite(frame) or
                orientation_owners[handler] ~= true then return end
        local unit = player.player_unit
        if not unit or not Unit.alive(unit) then return end
        local machine = ScriptUnit.has_extension(unit, "character_state_machine_system")
        if not machine or not controllable[machine:current_state_name()] then return end
        local _, rotation = presentation.controller_aim_target()
        if not rotation then return end
        local yaw, pitch = Quaternion.yaw(rotation), Quaternion.pitch(rotation)
        local index = handler:_buffer_index(frame)
        local cache, lookup = handler._input_cache, handler._action_lookup
        local old_yaw = cache[handler._yaw_index][index]
        if not finite(yaw) or not finite(pitch) or not finite(old_yaw) then return end
        local limits = require("scripts/settings/player_character/player_orientation_settings").default
        yaw = yaw % (2*math.pi)
        pitch = (pitch+math.pi) % (2*math.pi)-math.pi
        pitch = math.max(limits.min_pitch, math.min(limits.max_pitch, pitch)) % (2*math.pi)
        -- The existing adapter has already combined keyboard and VR movement
        -- in the head basis. Express that same desired vector in the sent aim
        -- basis, then pack it exactly as stock movement input requires.
        local values = {}
        for i, name in ipairs(movement_names) do
            local value = cache[lookup[name]][index]
            if not finite(value) then return end
            values[i] = value
        end
        local desired = Quaternion.rotate(presentation.flat_movement_rotation(old_yaw),
            Vector3(values[1]-values[2], values[3]-values[4], 0))
        local relative = Quaternion.rotate(Quaternion.inverse(
            presentation.flat_movement_rotation(yaw)), desired)
        local x, y = Vector3.x(relative), Vector3.y(relative)
        if not finite(x) or not finite(y) then return end
        -- Keyboard diagonals and combined inputs can rotate outside the unit
        -- square. Scale both axes together: independent clipping changes the
        -- intended world direction. Stock speed/acceleration still apply.
        local scale = math.max(1, math.abs(x), math.abs(y))
        x, y = x/scale, y/scale
        values = {math.max(x,0), math.max(-x,0), math.max(y,0), math.max(-y,0)}
        for i, name in ipairs(movement_names) do
            local network_type = handler._pack_unpack_action_to_network_type_index[name]
            if not network_type then return end
            values[i] = Network.pack_unpack(network_type, values[i])
            if not finite(values[i]) then return end
        end
        -- Validate destinations before making any writes. Failure keeps all
        -- original stock columns together, rather than changing only aim.
        assert(cache[handler._pitch_index] and cache[handler._roll_index])
        for i, name in ipairs(movement_names) do cache[lookup[name]][index] = values[i] end
        cache[handler._yaw_index][index] = yaw
        cache[handler._pitch_index][index] = pitch
        cache[handler._roll_index][index] = 0
        instance.frames = instance.frames + 1
        if instance.frames == 1 then
            mod:info("DARKTIDEVR_ONLINE_RULES input_frame=%s aim=right_hand movement=stock_packed replay=stock_history",
                tostring(frame))
        end
    end
    function instance.capture(handler, frame)
        local ok, message = pcall(capture, handler, frame)
        if not ok then
            instance.failures = instance.failures + 1
            if instance.failures == 1 then
                mod:warning("DARKTIDEVR_ONLINE_RULES input_fallback=%s", tostring(message))
            end
        end
    end
    return instance
end

return Rules
