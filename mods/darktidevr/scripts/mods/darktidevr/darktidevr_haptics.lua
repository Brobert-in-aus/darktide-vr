-- Controller vibration requested by gameplay features. The capture library
-- forwards each pulse to the viewer on the presentation packet
-- (dtvr_request_haptic_v1); the viewer plays it with xrApplyHapticFeedback.
-- Option "vr_haptics_mode" (Experimental): off (default), informative or
-- immersive. Each kind lists the modes that play it: some in both (a grip in
-- reach, the clip running dry), some only informative (notices such as low
-- ammo), some only immersive (the feel of actions such as every shot). The
-- catalogue and plan: docs/phase1/haptics-2026-09-14.md.
local Haptics = {}

Haptics.HANDS = {left = 1, right = 2, both = 3}
Haptics.MODES = {off = true, informative = true, immersive = true}
local BOTH = {informative = true, immersive = true}
-- Pulse shapes by feedback kind: the modes that play it, whether it is a
-- notice (never dropped for a feel pulse), amplitude 0 to 1 and duration in
-- milliseconds.
Haptics.KINDS = {
    -- A hand reaches a place where a grip press does something (a gun's
    -- foregrip, an armed holster).
    zone = {modes = BOTH, notice = true, amplitude = 0.3, duration_ms = 15},
    -- A grip takes hold (two-hand support).
    grip = {modes = BOTH, notice = true, amplitude = 0.55, duration_ms = 30},
    -- The last round in the clip was fired.
    clip_empty = {modes = BOTH, notice = true, amplitude = 0.8, duration_ms = 90},
    -- A reload put the clip back to full (or used the last of the reserve).
    reload = {modes = BOTH, notice = true, amplitude = 0.5, duration_ms = 45},
    -- Clip and reserve together fell to the stock low-ammo share (20 %).
    low_ammo = {modes = {informative = true}, notice = true, amplitude = 0.4, duration_ms = 25},
    -- A shot left the gun, at the weapon family's strength (SHOT_FAMILIES);
    -- continuous weapons pulse at the rate limit.
    shot = {modes = {immersive = true}, amplitude = 1.0, duration_ms = 20},
    -- Body (both hands). Health lost, scaled by the share of a quarter of
    -- maximum health; toughness broken; toughness lost without health loss.
    damage = {modes = BOTH, notice = true, amplitude = 0.7, duration_ms = 45},
    toughness_broken = {modes = BOTH, notice = true, amplitude = 0.6, duration_ms = 60},
    toughness_hit = {modes = {immersive = true}, amplitude = 0.35, duration_ms = 20},
    -- Knocked down, netted, pounced, grabbed, hanging from a ledge.
    disabled = {modes = BOTH, notice = true, amplitude = 1.0, duration_ms = 200},
    -- Health falls to LOW_HEALTH_SHARE; stamina runs out.
    low_health = {modes = {informative = true}, notice = true, amplitude = 0.5, duration_ms = 40},
    stamina_empty = {modes = {informative = true}, notice = true, amplitude = 0.4, duration_ms = 25},
    -- A block takes a hit (the first of a block hold); a perfect block.
    block = {modes = BOTH, amplitude = 0.5, duration_ms = 25},
    perfect_block = {modes = BOTH, notice = true, amplitude = 0.75, duration_ms = 35},
    -- Combat ability charge used or regained; blitz charge regained.
    ability_used = {modes = {immersive = true}, amplitude = 0.6, duration_ms = 40},
    ability_ready = {modes = {informative = true}, notice = true, amplitude = 0.45, duration_ms = 30},
    blitz_ready = {modes = {informative = true}, notice = true, amplitude = 0.3, duration_ms = 15},
    -- A melee swing connects (heavy attacks full strength); a shove.
    melee_hit = {modes = {immersive = true}, amplitude = 0.8, duration_ms = 30},
    push = {modes = {immersive = true}, amplitude = 0.6, duration_ms = 35},
}
Haptics.LIGHT_MELEE_SCALE = 0.7
Haptics.MISSED_PUSH_SCALE = 0.5
Haptics.LOW_HEALTH_SHARE = 0.25
Haptics.LOW_AMMO_SHARE = 0.2
-- Shot strength by weapon template family: the first matching prefix wins,
-- so more specific prefixes come first. Unlisted guns use SHOT_DEFAULT; a
-- flamer's (or flame staff's) gas action uses SHOT_STREAM.
Haptics.SHOT_FAMILIES = {
    {"lasgun_p2", 0.75},            -- helbore
    {"lasgun", 0.45}, {"laspistol", 0.4},
    {"autogun", 0.5}, {"autopistol", 0.4}, {"dual_autopistols", 0.4},
    {"dual_stubpistols", 0.55}, {"stubrevolver", 0.85},
    {"boltpistol", 0.9}, {"bolter", 1.0}, {"plasmagun", 1.0},
    {"shotpistol", 0.75}, {"shotgun", 0.9},
    {"ogryn_heavystubber", 0.55}, {"ogryn_rippergun", 0.8}, {"ogryn_thumper", 0.95}, {"ogryn_gauntlet", 0.95},
    {"galvanic_rifle", 0.7}, {"arc_rifle", 0.6}, {"needlepistol", 0.45}, {"phosphor_pistol", 0.6},
    {"forcestaff", 0.5}, {"flamer", 0.35}, {"missile_launcher", 1.0},
}
Haptics.SHOT_DEFAULT = 0.65
Haptics.SHOT_STREAM = 0.35
function Haptics.shot_scale(template_name, action_kind)
    if type(action_kind) == "string" and action_kind:find("flamer_gas", 1, true) then return Haptics.SHOT_STREAM end
    if type(template_name) == "string" then
        for _, family in ipairs(Haptics.SHOT_FAMILIES) do
            if template_name:sub(1, #family[1]) == family[1] then return family[2] end
        end
    end
    return Haptics.SHOT_DEFAULT
end
-- Pulses on one hand closer together than this are dropped: requests between
-- two viewer frames coalesce anyway, and a buzzing hand is no feedback.
-- A notice is never dropped for a feel pulse.
Haptics.MIN_INTERVAL = 0.06
Haptics.TEST_FLAG = "./../mods/darktidevr/darktidevr_haptics_test.flag"
Haptics.LOGGED_PULSES = 20

-- Whether a kind plays in a mode (an unset or foreign mode plays nothing).
function Haptics.plays(kind, mode)
    local shape = Haptics.KINDS[kind]
    return shape ~= nil and type(mode) == "string" and shape.modes[mode] == true
end

-- send(hands, amplitude, duration_ms, frequency_hz) returns true once the
-- request is on its way. mode() returns the current mode name.
function Haptics.new(send, mode)
    local api = {last = {}, sent = 0, dropped = 0}
    -- scale (default 1) multiplies the kind's amplitude, within 0.05 to 1.
    function api.pulse(hand, kind, t, scale)
        local bits, shape = Haptics.HANDS[hand], Haptics.KINDS[kind]
        if not bits or not shape or type(t) ~= "number" or t ~= t then return false end
        if not Haptics.plays(kind, mode and mode()) then return false end
        local notice = shape.notice == true
        for name, bit in pairs(Haptics.HANDS) do
            local last = api.last[name]
            if name ~= "both" and bits % (bit * 2) >= bit and last and t >= last.t and
                    t - last.t < Haptics.MIN_INTERVAL and not (notice and not last.notice) then
                api.dropped = api.dropped + 1
                return false
            end
        end
        local amplitude = shape.amplitude
        if type(scale) == "number" and scale == scale then
            amplitude = math.max(0.05, math.min(1, amplitude * scale))
        end
        if not send(bits, amplitude, shape.duration_ms, 0) then return false end
        for name, bit in pairs(Haptics.HANDS) do
            if name ~= "both" and bits % (bit * 2) >= bit then api.last[name] = {t = t, notice = notice} end
        end
        api.sent = api.sent + 1
        return true
    end
    return api
end

-- Ammo feedback from two readings of the wielded gun ({weapon, clip,
-- clip_max, reserve, reserve_max}): the clip reaching 0; a reload (clip up
-- while the reserve went down, so a pickup is not a reload) that fills the
-- clip or empties the reserve, so a shell-by-shell reload pulses once when
-- full; and clip plus reserve falling to LOW_AMMO_SHARE of their capacity.
function Haptics.ammo_events(previous, current)
    if type(previous) ~= "table" or type(current) ~= "table" or previous.weapon ~= current.weapon or
            type(previous.clip) ~= "number" or type(current.clip) ~= "number" then
        return nil
    end
    if previous.clip > 0 and current.clip == 0 then return "clip_empty" end
    if current.clip > previous.clip and type(previous.reserve) == "number" and
            type(current.reserve) == "number" and current.reserve < previous.reserve and
            (current.clip >= (current.clip_max or math.huge) or current.reserve == 0) then
        return "reload"
    end
    local capacity = (current.clip_max or 0) + (current.reserve_max or 0)
    if capacity > 0 and type(previous.reserve) == "number" and type(current.reserve) == "number" then
        local before = (previous.clip + previous.reserve) / capacity
        local after = (current.clip + current.reserve) / capacity
        if before > Haptics.LOW_AMMO_SHARE and after <= Haptics.LOW_AMMO_SHARE then return "low_ammo" end
    end
    return nil
end

-- Body feedback from two readings of the local player ({health, max_health,
-- toughness (fraction), disabled, stamina (fraction), blocked, perfect_block,
-- combat_charges, grenade_charges}). Returns the events of this frame, most
-- important first, each {kind, scale}. A reading taken as the player becomes
-- disabled (a knocked-down health pool) reports only the disable.
function Haptics.body_events(previous, current)
    local events = {}
    if type(previous) ~= "table" or type(current) ~= "table" then return events end
    local function number(v) return type(v) == "number" and v == v end
    if current.disabled and not previous.disabled then
        events[#events + 1] = {"disabled", 1}
        return events
    end
    local health_lost = number(previous.health) and number(current.health) and
        previous.disabled == current.disabled and previous.health - current.health or 0
    if health_lost > 0.5 then
        local quarter = number(current.max_health) and current.max_health > 0 and current.max_health * 0.25 or 50
        events[#events + 1] = {"damage", math.max(0.4, math.min(1, health_lost / quarter))}
    end
    if number(previous.toughness) and number(current.toughness) then
        if previous.toughness > 0 and current.toughness <= 0 then
            events[#events + 1] = {"toughness_broken", 1}
        elseif health_lost <= 0.5 and previous.toughness - current.toughness > 0.01 then
            events[#events + 1] = {"toughness_hit", math.max(0.4, math.min(1, (previous.toughness - current.toughness) / 0.25))}
        end
    end
    if current.blocked and not previous.blocked then
        events[#events + 1] = {current.perfect_block and "perfect_block" or "block", 1}
    end
    if number(previous.health) and number(current.health) and number(current.max_health) and current.max_health > 0 and
            previous.health / current.max_health > Haptics.LOW_HEALTH_SHARE and
            current.health / current.max_health <= Haptics.LOW_HEALTH_SHARE and not current.disabled then
        events[#events + 1] = {"low_health", 1}
    end
    if number(previous.stamina) and number(current.stamina) and previous.stamina > 0.05 and current.stamina <= 0 then
        events[#events + 1] = {"stamina_empty", 1}
    end
    if number(previous.combat_charges) and number(current.combat_charges) then
        if current.combat_charges < previous.combat_charges then events[#events + 1] = {"ability_used", 1}
        elseif current.combat_charges > previous.combat_charges then events[#events + 1] = {"ability_ready", 1} end
    end
    if number(previous.grenade_charges) and number(current.grenade_charges) and
            current.grenade_charges > previous.grenade_charges then
        events[#events + 1] = {"blitz_ready", 1}
    end
    return events
end

-- States the stock character state machine uses for a player who cannot act.
Haptics.DISABLED_STATES = {knocked_down = true, hogtied = true, ledge_hanging = true, catapulted = true,
    netted = true, pounced = true, grabbed = true, consumed = true, warp_grabbed = true,
    mutant_charged = true, vortex_grabbed = true, dead = true}

function Haptics.install(mod, presentation, send)
    local test_poll, test_mode = 0, nil
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_mode end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Haptics.TEST_FLAG, "r")
        if not file then test_mode = nil; return nil end
        local value = file:read("*all"); file:close()
        value = type(value) == "string" and value:match("^%s*(%a+)%s*$")
        test_mode = value == "enabled" and "immersive" or (Haptics.MODES[value] and value) or nil
        return test_mode
    end
    local logged = 0
    local function logged_send(hands, amplitude, duration_ms, frequency_hz)
        local ok, delivered = pcall(send, hands, amplitude, duration_ms, frequency_hz)
        delivered = ok and delivered == true
        if logged < Haptics.LOGGED_PULSES then
            logged = logged + 1
            mod:info("DARKTIDEVR_HAPTICS pulse hands=%d amplitude=%.2f duration_ms=%d delivered=%s",
                hands, amplitude, duration_ms, tostring(delivered))
        end
        return delivered
    end
    local api = Haptics.new(logged_send, function()
        return test_flag() or mod:get("vr_haptics_mode")
    end)
    local pulse = api.pulse
    local function now()
        local time = Managers and Managers.time
        return time and time:has_timer("main") and time:time("main") or nil
    end
    -- Callers without a frame time use the main clock.
    function api.pulse(hand, kind, t, scale)
        return pulse(hand, kind, t == nil and now() or t, scale)
    end
    local counts = {}
    local function count(kind)
        counts[kind] = (counts[kind] or 0) + 1
        if counts[kind] == 1 or counts[kind] % 50 == 0 then
            mod:info("DARKTIDEVR_HAPTICS event=%s count=%d", kind, counts[kind])
        end
    end
    -- The gun hand, and both hands while the support hand holds the foregrip.
    local function gun_hands()
        local roles = presentation.weapon_hand_roles
        local dominant = roles and roles.physical("dominant")
        if dominant ~= "left" and dominant ~= "right" then return nil end
        return presentation.two_hand and presentation.two_hand.held and "both" or dominant
    end
    -- From the stock shot dispatch (local player, not resimulating).
    function api.shot(action)
        local hands = gun_hands()
        local template = action and action._weapon_template
        local settings = action and action._action_settings
        local scale = Haptics.shot_scale(template and template.name, settings and settings.kind)
        if hands and api.pulse(hands, "shot", nil, scale) then count("shot") end
    end
    -- Melee: the stock hit effects of a connecting sweep and the stock push
    -- rumble, local player only and never while resimulating. Observe-only
    -- hooks; a subclass with its own copy of the method is hooked as well.
    local function local_action(action)
        return action and presentation.online_rules and
            presentation.online_rules.simulation_aim_active(action._player_unit) and
            not (action._unit_data_extension and action._unit_data_extension.is_resimulating)
    end
    local function melee_hands()
        local roles = presentation.weapon_hand_roles
        local dominant = roles and roles.physical("dominant")
        return (dominant == "left" or dominant == "right") and dominant or nil
    end
    function api.melee_hit(action, damage_profile)
        if not local_action(action) then return end
        local heavy_strength = api.heavy_melee_strength
        local heavy = heavy_strength ~= nil and type(damage_profile) == "table" and
            damage_profile.melee_attack_strength == heavy_strength
        local hands = melee_hands()
        if hands and api.pulse(hands, "melee_hit", nil, heavy and 1 or Haptics.LIGHT_MELEE_SCALE) then
            count("melee_hit")
        end
    end
    function api.push(action, number_of_units_hit)
        if not local_action(action) then return end
        local hit = type(number_of_units_hit) == "number" and number_of_units_hit > 0
        if api.pulse("both", "push", nil, hit and 1 or Haptics.MISSED_PUSH_SCALE) then count("push") end
    end
    if mod.hook_safe then
        local function observe(handler)
            return function(...)
                local ok, message = pcall(handler, ...)
                if not ok and not api.hook_failure_logged then
                    api.hook_failure_logged = true
                    mod:info("DARKTIDEVR_HAPTICS hook_failure=%s", tostring(message):sub(1, 160))
                end
            end
        end
        api.heavy_melee_strength = require("scripts/settings/damage/attack_settings").melee_attack_strength.heavy
        local sweep = require("scripts/extension_systems/weapon/actions/action_sweep")
        mod:hook_safe(sweep, "_play_hit_effects", observe(function(self, _, damage_profile)
            api.melee_hit(self, damage_profile)
        end))
        local explosive = require("scripts/extension_systems/weapon/actions/action_melee_explosive")
        if rawget(explosive, "_play_hit_effects") and rawget(explosive, "_play_hit_effects") ~= rawget(sweep, "_play_hit_effects") then
            mod:hook_safe(explosive, "_play_hit_effects", observe(function(self, _, damage_profile)
                api.melee_hit(self, damage_profile)
            end))
        end
        mod:hook_safe(require("scripts/extension_systems/weapon/actions/action_push"), "_play_push_rumble",
            observe(function(self, number_of_units_hit) api.push(self, number_of_units_hit) end))
    end
    local previous, previous_body
    local function field(read)
        local ok, value = pcall(read)
        return ok and value or nil
    end
    local function read_body(unit, unit_data)
        local health = ScriptUnit.has_extension(unit, "health_system")
        local toughness = ScriptUnit.has_extension(unit, "toughness_system")
        local ability = ScriptUnit.has_extension(unit, "ability_system")
        local state = field(function() return unit_data:read_component("character_state").state_name end)
        return {
            health = health and field(function() return health:current_health() end),
            max_health = health and field(function() return health:max_health() end),
            toughness = toughness and field(function() return toughness:current_toughness_percent() end),
            disabled = Haptics.DISABLED_STATES[state] == true or
                field(function() return unit_data:read_component("disabled_character_state").is_disabled end) == true,
            stamina = field(function() return unit_data:read_component("stamina").current_fraction end),
            blocked = field(function() return unit_data:read_component("block").has_blocked end) == true,
            perfect_block = field(function() return unit_data:read_component("block").is_perfect_blocking end) == true,
            combat_charges = ability and field(function() return ability:remaining_ability_charges("combat_ability") end),
            grenade_charges = ability and field(function() return ability:remaining_ability_charges("grenade_ability") end),
        }
    end
    -- Once per gameplay frame, after input.
    function api.sample(unit)
        local mode = test_flag() or mod:get("vr_haptics_mode")
        if not unit or (mode ~= "informative" and mode ~= "immersive") then
            previous, previous_body = nil, nil; return
        end
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        if unit_data then
            local body = read_body(unit, unit_data)
            -- The first event this mode plays; the rest of the frame is one pulse.
            for _, event in ipairs(Haptics.body_events(previous_body, body)) do
                if Haptics.plays(event[1], mode) then
                    if api.pulse("both", event[1], nil, event[2]) then count(event[1]) end
                    break
                end
            end
            previous_body = body
        end
        local inventory = unit_data and unit_data:read_component("inventory")
        if not inventory or inventory.wielded_slot ~= "slot_secondary" then previous = nil; return end
        local values = presentation.ammo_readout and presentation.ammo_readout.slot_values and
            presentation.ammo_readout.slot_values(unit)
        local current = values and values.clip and {weapon = inventory.slot_secondary, clip = values.clip,
            clip_max = values.clip_max, reserve = values.reserve, reserve_max = values.reserve_max} or nil
        local event = Haptics.ammo_events(previous, current)
        previous = current
        local hands = event and gun_hands()
        if hands and api.pulse(hands, event) then count(event) end
    end
    return api
end

return Haptics
