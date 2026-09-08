-- Range and local mission rules: author only stock input columns. No action pose proxy,
-- origin override, extra movement velocity, damage rule or custom RPC.
local Rules = {}
local ranges = {shooting_range=true}
local controllable = {walking=true, sprinting=true, sliding=true,
    jumping=true, falling=true, dodging=true, interacting=true}
local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function read_difficulty(method)
    local manager = Managers.state.difficulty
    return manager[method](manager)
end
local function difficulty_evidence(method)
    local ok, value = pcall(read_difficulty, method)
    return ok and finite(value) and tostring(value) or "unknown"
end

function Rules.install(mod, presentation, state, mode_name)
    local instance = {frames=0, failures=0}
    local session_owner, session_mode, selected
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
        local mode = mode_name()
        local mission = presentation.gameplay_context.local_mission(mode, session)
        if not ranges[mode] and not mission then
            session_owner, session_mode, selected = nil, nil, nil
            return false
        end
        if not presentation.gameplay_context.local_authority(session) then
            return false
        end
        if session ~= session_owner or mode ~= session_mode then
            session_owner, session_mode = session, mode
            -- Readiness evidence belongs to this visit. A prior visit's first
            -- success/failure must not suppress diagnostics for a new session.
            instance.frames, instance.failures = 0, 0
            -- Latch on entering a session: switching rules during a charged
            -- attack would mix histories. The setting takes effect next visit.
            -- Local missions always use the stock-server-compatible route.
            -- The range-only opt-out must never enable hand-origin/action
            -- proxies in a mission, including a reused manager on transition.
            selected = mission or mod:get("psykhanium_online_rules") ~= false
            mod:info("DARKTIDEVR_ONLINE_RULES range=%s enabled=%s origins=stock damage=stock",
                tostring(mode_name()), tostring(selected))
        end
        return selected
    end
    instance.enabled = enabled

    local function simulation_aim_active(unit)
        if not enabled() or presentation.mode ~= 1 or not state.authoring_enabled then return false end
        local player = Managers.player and Managers.player:local_player(1)
        return player and unit ~= nil and unit == player.player_unit and Unit.alive(unit)
    end
    function instance.simulation_aim_active(unit)
        local ok, active = pcall(simulation_aim_active, unit)
        return ok and active == true
    end

    local function preview_pose(effect)
        if not enabled() or presentation.mode ~= 1 or not effect or
                not effect._is_local_unit then return end
        local player = Managers.player and Managers.player:local_player(1)
        local unit = player and player.player_unit
        if not unit or not Unit.alive(unit) then return end
        local extension = ScriptUnit.has_extension(unit, "first_person_system")
        if not extension or not effect._first_person_unit or
                effect._first_person_unit ~= extension:first_person_unit() then return end
        local component = extension._first_person_component
        if component then return component.position, component.rotation end
    end
    function instance.preview_pose(effect)
        -- Visual effects can outlive their owner during transitions. A retired
        -- extension cannot authorize a root redirect for the next player unit.
        local ok, position, rotation = pcall(preview_pose, effect)
        if ok then return position, rotation end
    end

    local function capture(handler, frame, dt, t)
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
        local _, rotation
        if presentation.weapon_aim_target then _, rotation = presentation.weapon_aim_target("dominant")
        else _, rotation = presentation.controller_aim_target() end
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
        local right = cache[lookup.move_right][index]
        local left = cache[lookup.move_left][index]
        local forward = cache[lookup.move_forward][index]
        local backward = cache[lookup.move_backward][index]
        if not finite(right) or not finite(left) or not finite(forward) or not finite(backward) then return end
        local desired = Quaternion.rotate(presentation.flat_movement_rotation(old_yaw),
            Vector3(right-left, forward-backward, 0))
        local types = handler._pack_unpack_action_to_network_type_index
        if not types.move_right or not types.move_left or not types.move_forward or not types.move_backward then return end
        local automatic = false
        if presentation.roomscale then
            desired, automatic = presentation.roomscale.plan(unit, frame, dt, t, yaw, desired,
                function(x, y)
                    return Network.pack_unpack(types.move_right, math.max(x,0)) -
                        Network.pack_unpack(types.move_left, math.max(-x,0)),
                        Network.pack_unpack(types.move_forward, math.max(y,0)) -
                        Network.pack_unpack(types.move_backward, math.max(-y,0))
                end)
        end
        local relative = Quaternion.rotate(Quaternion.inverse(
            presentation.flat_movement_rotation(yaw)), desired)
        local x, y = Vector3.x(relative), Vector3.y(relative)
        if not finite(x) or not finite(y) then return end
        -- Keyboard diagonals and combined inputs can rotate outside the unit
        -- square. Scale both axes together: independent clipping changes the
        -- intended world direction. Stock speed/acceleration still apply.
        local scale = math.max(1, math.abs(x), math.abs(y))
        x, y = x/scale, y/scale
        -- Keep the transaction in scalar locals rather than constructing two
        -- scratch arrays on every authored fixed frame.
        right = Network.pack_unpack(types.move_right, math.max(x,0))
        if not finite(right) then return end
        left = Network.pack_unpack(types.move_left, math.max(-x,0))
        if not finite(left) then return end
        forward = Network.pack_unpack(types.move_forward, math.max(y,0))
        if not finite(forward) then return end
        backward = Network.pack_unpack(types.move_backward, math.max(-y,0))
        if not finite(backward) then return end
        -- Validate destinations before making any writes. Failure keeps all
        -- original stock columns together, rather than changing only aim.
        assert(cache[handler._pitch_index] and cache[handler._roll_index])
        cache[lookup.move_right][index], cache[lookup.move_left][index] = right, left
        cache[lookup.move_forward][index], cache[lookup.move_backward][index] = forward, backward
        cache[handler._yaw_index][index] = yaw
        cache[handler._pitch_index][index] = pitch
        cache[handler._roll_index][index] = 0
        if presentation.roomscale then presentation.roomscale.record(frame, automatic) end
        instance.frames = instance.frames + 1
        if instance.frames == 1 then
            mod:info("DARKTIDEVR_ONLINE_RULES input_frame=%s aim=dominant_hand movement=stock_packed replay=stock_history challenge=%s resistance=%s",
                tostring(frame), difficulty_evidence("get_challenge"),
                difficulty_evidence("get_resistance"))
        end
    end
    function instance.capture(handler, frame, dt, t)
        local ok, message = pcall(capture, handler, frame, dt, t)
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
