-- Opt-in, private-range diagnostics only. Grip origin is provisional: this
-- checks engine queries, not visual calibration or physical damage acceptance.
local Live = {}

function Live.install(mod, presentation, tracking, game_mode)
    local prefix = "darktidevr/scripts/mods/darktidevr/"
    local function load(name) return mod:io_dofile(prefix .. "darktidevr_melee_" .. name) end
    local Simulation, Planner, Probe = load("simulation"), load("sweep_plan"), load("probe")
    local Diagnostics, Volume = load("diagnostics"), load("volume")
    local Timing = load("timing")
    local HitZone, Contacts = load("hit_zone"), load("contacts")
    local defaults = require("scripts/settings/equipment/action_sweep_settings")
    local states = setmetatable({}, {__mode="k"})
    local enabled, last_check, failed = false, nil, false

    local function update(extension, t, frame)
        local player = Managers and Managers.player and Managers.player:local_player(1)
        if not player or player.player_unit ~= extension._unit then return end
        if not last_check or t < last_check or t-last_check >= 1 then
            last_check = t
            local flag = Mods and Mods.lua and Mods.lua.io and Mods.lua.io.open(
                "./../mods/darktidevr/darktidevr_melee_probe.flag", "r")
            local next_enabled = false
            if flag then
                next_enabled = flag:read("*all"):match("^%s*enabled%s*$") ~= nil
                flag:close()
            end
            if not next_enabled then failed = false end
            if enabled ~= next_enabled then
                enabled = next_enabled
                states = setmetatable({}, {__mode="k"})
                mod:info("DARKTIDEVR_MELEE probe=%s damage=false origin=provisional_grip", tostring(enabled))
            end
        end
        if not enabled or failed then return end
        local mode = game_mode()
        if mode ~= "shooting_range" and mode ~= "training_grounds" then
            states[extension] = nil
            return
        end
        local state = states[extension]
        if not state then
            state = {diagnostics=Diagnostics.new(Simulation, Planner, Probe), last_log=-math.huge,
                references=setmetatable({}, {__mode="v"})}
            states[extension] = state
        end
        local slot = extension._inventory_component.wielded_slot
        local weapon = extension._weapons[slot]
        -- Action instances point back to their owning extension. A strong
        -- weapon here defeats the outer weak key under LuaJIT's collector.
        if (weapon ~= nil) ~= state.weapon_present or weapon ~= state.references.weapon then
            state.weapon_present = weapon ~= nil
            state.references.weapon, state.volume, state.action_name = weapon, nil, nil
            state.references.action = nil
            state.reason = nil
            state.windup_name = nil
            state.windup_start_t, state.combo_fingerprint = nil, nil
            state.history_key = {}
        end
        local template = weapon and weapon.weapon_template
        local name = extension._weapon_action_component.current_action_name
        local action = template and template.actions and template.actions[name]
        local instance = weapon and weapon.actions and weapon.actions[name]
        local action_start = extension._weapon_action_component.start_t
        if action and action.kind == "windup" and
                (state.windup_name ~= name or state.windup_start_t ~= action_start) then
            state.windup_name, state.windup_start_t = name, action_start
            local handler = extension._action_handler
            local params = extension:condition_func_params(slot)
            local function scale_for(settings) return handler:_calculate_time_scale(settings) end
            local function validate(settings) return handler:_validate_action(settings,params,t,0,nil) end
            local inverted = handler._action_kinds_with_inverted_timescale
            local timing, timing_reason = Timing.from_windup(template,name,scale_for,inverted,validate)
            mod:info("DARKTIDEVR_MELEE timing windup=%s result=%s light=%s heavy=%s light_interval=%.4f heavy_charge=%.4f heavy_auto_complete_after=%s heavy_damage_charge=%s damage=false",
                name,timing and "resolved" or tostring(timing_reason),
                timing and timing.light_action or "none",timing and timing.heavy_action or "none",
                timing and timing.light_interval or 0,timing and timing.heavy_charge or 0,
                timing and tostring(timing.heavy_auto_complete_after) or "unknown",
                timing and timing.heavy_damage_charge or "unknown")
            local combo, combo_reason, at = Timing.light_combo(template,name,scale_for,inverted,validate)
            local steps = {}
            for _,step in ipairs(combo and combo.steps or {}) do
                steps[#steps+1] = string.format("%s:%.4f",step.light_action,step.interval)
            end
            local fingerprint = table.concat(steps,",") .. ":" .. tostring(combo_reason) .. ":" .. tostring(at)
            if state.combo_fingerprint ~= fingerprint then
                state.combo_fingerprint = fingerprint
                mod:info("DARKTIDEVR_MELEE combo windup=%s result=%s at=%s cycle_start=%d entry_seconds=%.4f cycle_seconds=%.4f steps=%s snapshot=true damage=false",
                    name,combo and "resolved" or tostring(combo_reason),tostring(at),
                    combo and combo.cycle_start or 0,combo and combo.entry_duration or 0,
                    combo and combo.cycle_duration or 0,table.concat(steps,","))
            end
        end
        -- Observe an action the engine actually selected. Do not guess an idle
        -- route from unordered action names or use block/push timing as light.
        if action and action.kind == "sweep" and instance then
            local volume, reason = Volume.resolve(template, action, defaults, instance._uses_matrix_data)
            if volume and (not state.volume or state.action_name ~= name) then
                state.volume, state.action_name, state.history_key = volume, name, {}
                state.references.action = action
                state.reason = nil
                mod:info("DARKTIDEVR_MELEE context template=%s action=%s shape=%s radius=%.4f origin=provisional_grip damage=false",
                    tostring(template.name), name, volume.shape, volume.corner_radius)
            elseif not volume then
                state.volume = nil
                state.reason = reason
            end
        end
        if not state.volume then
            if t-state.last_log >= 5 then
                state.last_log = t
                mod:info("DARKTIDEVR_MELEE waiting=%s slot=%s", state.reason or "observed_sweep_action", tostring(slot))
            end
            return
        end
        local hand = presentation.hand_side("dominant")
        if state.transport_generation ~= tracking.last_transport_generation or
                state.recenter_generation ~= tracking.head_recenter_generation or
                state.hand ~= hand then
            state.transport_generation = tracking.last_transport_generation
            state.recenter_generation = tracking.head_recenter_generation
            state.hand = hand
            -- A new coordinate reference is not weapon motion, even when its
            -- displacement fits the ordinary per-tick sweep limits. Preserve
            -- simulation tick ownership; only retire the trajectory history.
            state.history_key = {}
        end
        -- IK may keep a last-known grip for visual continuity. That held pose
        -- cannot authorize physical queries after its live tracking is lost.
        local valid = tracking[hand.."_grip_usable"] == true and
            tracking[hand.."_grip_tracking_live"] == true and tracking.body_anchor_qw ~= nil
        local position, rotation
        if valid then
            position, rotation = presentation.weapon_grip_target("dominant")
        end
        valid = valid and position ~= nil and rotation ~= nil
        local pose
        if valid then
            local x,y,z,w = Quaternion.to_elements(rotation)
            pose = {position={Vector3.x(position),Vector3.y(position),Vector3.z(position)}, rotation={x,y,z,w}}
        end
        local report, reason, detail = Diagnostics.sample(state.diagnostics, {
            history_key=state.history_key, pose=pose,
            step={frame=frame,time=t,tracking_valid=valid,
                resimulating=extension._unit_data_extension.is_resimulating == true},
            world=extension._physics_world,volume=state.volume,
            filter="filter_player_character_melee_sweep",rewind_ms=0,max_hits=128,
            limits={max_gap=.1,max_translation=1,arc_step=.05,max_segments=32}})
        if t-state.last_log >= 5 then
            state.last_log = t
            local resolution, selection_reason
            local attacker_position = POSITION_LOOKUP and POSITION_LOOKUP[extension._unit]
            if report and state.references.action and attacker_position then
                resolution, selection_reason = Diagnostics.select_contacts(report,HitZone,Contacts,{
                    attacker=extension._unit,attacker_position=attacker_position,
                    action=state.references.action,
                    -- Diagnostic identity lives only for this one result batch.
                    -- A future cooldown ledger needs a true spawn-generation key.
                    target_key=function(unit) return unit end})
            end
            mod:info("DARKTIDEVR_MELEE sample frame=%s result=%s actors=%d contacts=%d queries=%d saturated=%s capacity_verified=false damage=false detail=%s",
                tostring(frame), report and report.plan.reason or tostring(reason),
                report and report.overlap.actor_count or 0, report and #report.contacts or 0,
                report and report.query_count or 0, tostring(report and report.saturated or false), tostring(detail))
            if report then
                local zones = {}
                for _,contact in ipairs(resolution and resolution.selected or {}) do
                    local zone = tostring(contact.hit_zone)
                    zones[zone] = (zones[zone] or 0)+1
                end
                local summary = {}
                for zone,count in pairs(zones) do summary[#summary+1]=zone..":"..tostring(count) end
                table.sort(summary)
                mod:info("DARKTIDEVR_MELEE selection targets=%d unresolved=%d zones=%s result=%s obstruction_verified=false damage=false",
                    resolution and #resolution.selected or 0,resolution and #resolution.unresolved or 0,
                    table.concat(summary,","),resolution and "resolved" or tostring(selection_reason or "missing_context"))
            end
        end
    end
    function Live.fixed_update(extension, t, frame)
        local ok, failure = pcall(update, extension, t, frame)
        if not ok then
            -- Stop querying this extension after an adapter failure; no repeated
            -- per-frame exception storm. Toggle the flag to retry after a fix.
            failed = true
            states = setmetatable({}, {__mode="k"})
            mod:warning("DARKTIDEVR_MELEE probe_error=%s damage=false", tostring(failure))
        end
    end
    return Live
end

return Live
