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
    -- A grip press on a holster whose item is already in the hand: nothing
    -- happens (played twice, a double tap, darktidevr_holsters).
    refused = {modes = BOTH, notice = true, amplitude = 0.5, duration_ms = 25},
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
    -- Weapon heat and psyker peril: a warning past WARNING_SHARE, an alert
    -- past CRITICAL_SHARE. Charging a shot or attack: a buzz rising with the
    -- charge, and a tick when it is full.
    heat_warning = {modes = {informative = true}, notice = true, amplitude = 0.45, duration_ms = 30},
    heat_critical = {modes = BOTH, notice = true, amplitude = 0.9, duration_ms = 120},
    peril_warning = {modes = {informative = true}, notice = true, amplitude = 0.45, duration_ms = 30},
    peril_critical = {modes = BOTH, notice = true, amplitude = 0.9, duration_ms = 120},
    charging = {modes = {immersive = true}, amplitude = 0.4, duration_ms = 15},
    charge_full = {modes = BOTH, notice = true, amplitude = 0.35, duration_ms = 15},
    -- Melee: a held attack can now release as a heavy; the weapon special
    -- (power field, chain teeth, force) turns on, and hums while it stays on.
    heavy_ready = {modes = BOTH, notice = true, amplitude = 0.3, duration_ms = 15},
    special_on = {modes = BOTH, notice = true, amplitude = 0.5, duration_ms = 30},
    special_hum = {modes = {immersive = true}, amplitude = 0.15, duration_ms = 15},
    -- Interactions: a light hum while holding one (revive, pick up, operate),
    -- a notice when it finishes. A cancelled hold is not a finish.
    interaction_hum = {modes = {immersive = true}, amplitude = 0.2, duration_ms = 15},
    interaction_done = {modes = BOTH, notice = true, amplitude = 0.5, duration_ms = 35},
    -- Menus (VR pointer): a tick when the pointer moves onto a control, and a
    -- firmer one on click, enter or back.
    -- Both modes (worn, 15 September evening: Immersive wants them too).
    menu_hover = {modes = BOTH, amplitude = 0.2, duration_ms = 10},
    menu_confirm = {modes = BOTH, amplitude = 0.35, duration_ms = 15},
}
-- The menu kind for a stock UI sound event, or nil. The stock UI plays its
-- hover and click sounds from the hotspot pass, so the sound is the one
-- reliable signal that a control reacted.
function Haptics.menu_kind(sound_event)
    if type(sound_event) ~= "string" then return nil end
    -- Whole words between underscores, so "background" is not "back".
    local words = {}
    for word in ("_" .. (sound_event:lower():match("([^/]+)$") or "") .. "_"):gmatch("_(%w+)") do words[word] = true end
    if words.mouseover or words.hover then return "menu_hover" end
    if words.click or words.enter or words.back or words.confirm or words.select then return "menu_confirm" end
    return nil
end
-- The Controller vibration strength option (percent) scales every pulse.
Haptics.STRENGTH_RANGE = {25, 200}
function Haptics.strength_scale(percent)
    if type(percent) ~= "number" or percent ~= percent then return 1 end
    return math.max(Haptics.STRENGTH_RANGE[1], math.min(Haptics.STRENGTH_RANGE[2], percent)) / 100
end
Haptics.SPECIAL_HUM_INTERVAL = 0.25
Haptics.WARNING_SHARE = 0.75
Haptics.CRITICAL_SHARE = 0.9
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

-- Gauge feedback from two readings ({heat, peril, charge, max_charge}, heat
-- and peril as fractions). Returns the events of this frame, most important
-- first, each {kind, scale, hands} where hands is "gun" or "both".
function Haptics.gauge_events(previous, current)
    local events = {}
    if type(previous) ~= "table" or type(current) ~= "table" then return events end
    local function number(v) return type(v) == "number" and v == v end
    local function crossed(field, share)
        return number(previous[field]) and number(current[field]) and
            previous[field] < share and current[field] >= share
    end
    if crossed("heat", Haptics.CRITICAL_SHARE) then events[#events + 1] = {"heat_critical", 1, "gun"}
    elseif crossed("heat", Haptics.WARNING_SHARE) then events[#events + 1] = {"heat_warning", 1, "gun"} end
    if crossed("peril", Haptics.CRITICAL_SHARE) then events[#events + 1] = {"peril_critical", 1, "both"}
    elseif crossed("peril", Haptics.WARNING_SHARE) then events[#events + 1] = {"peril_warning", 1, "both"} end
    local maximum = number(current.max_charge) and current.max_charge > 0 and current.max_charge or 1
    if number(previous.charge) and number(current.charge) and current.charge > previous.charge + 1e-4 then
        if current.charge >= maximum - 1e-3 then
            events[#events + 1] = {"charge_full", 1, "gun"}
        else
            events[#events + 1] = {"charging", math.max(0.4, math.min(1, current.charge / maximum)), "gun"}
        end
    end
    return events
end

-- Melee feedback from two readings ({t, windup_start, heavy_time, melee,
-- special}): windup_start is the running windup action's start time (nil
-- otherwise) and heavy_time its heavy chain time after time scale; special is
-- the wielded melee weapon's special state. Returns events like gauge_events.
function Haptics.melee_events(previous, current)
    local events = {}
    if type(previous) ~= "table" or type(current) ~= "table" then return events end
    local function number(v) return type(v) == "number" and v == v end
    if number(current.t) and number(current.windup_start) and number(current.heavy_time) and
            current.t - current.windup_start >= current.heavy_time then
        local was_ready = previous.windup_start == current.windup_start and number(previous.t) and
            previous.t - previous.windup_start >= current.heavy_time
        if not was_ready then events[#events + 1] = {"heavy_ready", 1, "gun"} end
    end
    if current.melee and current.special then
        if not (previous.melee and previous.special) then
            events[#events + 1] = {"special_on", 1, "gun"}
        elseif number(previous.t) and number(current.t) and
                math.floor(current.t / Haptics.SPECIAL_HUM_INTERVAL) ~= math.floor(previous.t / Haptics.SPECIAL_HUM_INTERVAL) then
            events[#events + 1] = {"special_hum", 1, "gun"}
        end
    end
    return events
end

-- Interaction feedback from two readings ({t, state, start_time, duration}).
-- A hold that ends within FINISH_TOLERANCE of its duration finished; one that
-- ends earlier was let go or cancelled. Instant interactions finish on exit.
Haptics.FINISH_TOLERANCE = 0.15
function Haptics.interaction_events(previous, current)
    local events = {}
    if type(previous) ~= "table" or type(current) ~= "table" then return events end
    local function number(v) return type(v) == "number" and v == v end
    local was = previous.state == "is_interacting"
    local is = current.state == "is_interacting"
    if was and not is then
        local duration = number(previous.duration) and previous.duration or 0
        local elapsed = number(previous.t) and number(previous.start_time) and previous.t - previous.start_time or 0
        if duration <= 0 or elapsed >= duration - Haptics.FINISH_TOLERANCE then
            events[#events + 1] = {"interaction_done", 1, "gun"}
        end
    elseif was and is and number(current.duration) and current.duration > 0 and number(previous.t) and
            number(current.t) and math.floor(current.t / Haptics.SPECIAL_HUM_INTERVAL) ~=
            math.floor(previous.t / Haptics.SPECIAL_HUM_INTERVAL) then
        events[#events + 1] = {"interaction_hum", 1, "gun"}
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
        amplitude = math.max(0.02, math.min(1, amplitude * Haptics.strength_scale(mod:get("vr_haptics_strength"))))
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
    -- A stock UI sound while the VR menu pointer owns menu input.
    function api.menu_sound(sound_event)
        local kind = Haptics.menu_kind(sound_event)
        if not kind or not (presentation.using_native_menu_input and presentation.using_native_menu_input()) then return end
        if api.pulse(presentation.hand_side("dominant"), kind) then count(kind) end
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
        mod:hook_safe("UIManager", "play_2d_sound", observe(function(_, sound_event) api.menu_sound(sound_event) end))
    end
    local previous, previous_body, previous_gauges, previous_melee, previous_interaction
    local function field(read)
        local ok, value = pcall(read)
        return ok and value or nil
    end
    -- The same protected reads without a closure per call (16 September: the
    -- frame profiler put sample at 57 us a frame, most of it the ten or so
    -- closures and tables it built each frame). A failed read is nil, as with
    -- field; an index on a missing component is protected the same way.
    local function index(t, k) return t[k] end
    local function component_field(unit_data, name, key)
        local ok, component = pcall(unit_data.read_component, unit_data, name)
        if not ok or component == nil then return nil end
        local ok2, value = pcall(index, component, key)
        return ok2 and value or nil
    end
    local function method_value(object, method, argument)
        local ok, value = pcall(method, object, argument)
        return ok and value or nil
    end
    local EMPTY = {}
    -- Step 2 (profile doc): read each component once a frame and cache the
    -- extensions, which do not change while the unit lives. A nil extension is
    -- not cached, so one that arrives later is still found.
    local function component(unit_data, name)
        local ok, value = pcall(unit_data.read_component, unit_data, name)
        if ok then return value end
        return nil
    end
    local function field_of(component_table, key)
        if component_table == nil then return nil end
        local ok, value = pcall(index, component_table, key)
        return ok and value or nil
    end
    local extensions = {unit = nil}
    local function extension(unit, name, key)
        if extensions.unit ~= unit then
            extensions.unit, extensions.unit_data, extensions.health, extensions.toughness,
                extensions.ability, extensions.weapon = unit, nil, nil, nil, nil, nil
        end
        local cached = extensions[key]
        if cached ~= nil then return cached end
        cached = ScriptUnit.has_extension(unit, name)
        if cached ~= nil then extensions[key] = cached end
        return cached
    end
    local last_template, last_melee = nil, false
    -- Sub-sections for the frame profiler (profile doc, step 3): where the
    -- microseconds go inside one sample. A pass-through without it.
    local function section(name, fn, a, b, c, d, e, f)
        local profile = presentation.frame_profile
        if profile then return profile.section(name, fn, a, b, c, d, e, f) end
        return fn(a, b, c, d, e, f)
    end
    local function body_events_of(previous_body, body) return Haptics.body_events(previous_body, body) end
    local function gauge_events_of(previous_gauges, gauges) return Haptics.gauge_events(previous_gauges, gauges) end
    local function melee_events_of(previous_melee, reading) return Haptics.melee_events(previous_melee, reading) end
    local function interaction_events_of(previous_interaction, interaction)
        return Haptics.interaction_events(previous_interaction, interaction)
    end
    local function read_body(unit, unit_data)
        local health = extension(unit, "health_system", "health")
        local toughness = extension(unit, "toughness_system", "toughness")
        local ability = extension(unit, "ability_system", "ability")
        local state = component_field(unit_data, "character_state", "state_name")
        local block = component(unit_data, "block")
        return {
            health = health and method_value(health, health.current_health),
            max_health = health and method_value(health, health.max_health),
            toughness = toughness and method_value(toughness, toughness.current_toughness_percent),
            disabled = Haptics.DISABLED_STATES[state] == true or
                component_field(unit_data, "disabled_character_state", "is_disabled") == true,
            stamina = component_field(unit_data, "stamina", "current_fraction"),
            blocked = field_of(block, "has_blocked") == true,
            perfect_block = field_of(block, "is_perfect_blocking") == true,
            combat_charges = ability and method_value(ability, ability.remaining_ability_charges, "combat_ability"),
            grenade_charges = ability and method_value(ability, ability.remaining_ability_charges, "grenade_ability"),
        }
    end
    local function read_melee(reading, unit, unit_data, wielded)
        reading.t = Managers.time:time("gameplay")
        local weapon = extension(unit, "weapon_system", "weapon")
        local template = weapon and weapon:weapon_template()
        -- The keyword scan only when the template changes; it is the same
        -- table for as long as the same weapon is wielded.
        if template ~= last_template then
            last_template, last_melee = template, false
            local keywords = template and template.keywords
            for _, keyword in ipairs(type(keywords) == "table" and keywords or EMPTY) do
                if keyword == "melee" then last_melee = true end
            end
        end
        reading.melee = last_melee
        if reading.melee and type(wielded) == "string" and wielded:match("^slot_") then
            reading.special = unit_data:read_component(wielded).special_active == true
        end
        local action = unit_data:read_component("weapon_action")
        local settings = template and template.actions and template.actions[action.current_action_name]
        local heavy = settings and settings.kind == "windup" and settings.allowed_chain_actions and
            settings.allowed_chain_actions.heavy_attack
        local scale = tonumber(action.time_scale) or 1
        if heavy and type(heavy.chain_time) == "number" and scale > 0 then
            reading.windup_start, reading.heavy_time = action.start_t, heavy.chain_time / scale
        end
    end
    local function read_interaction(interaction, unit_data)
        local component = unit_data:read_component("interaction")
        interaction.state, interaction.start_time, interaction.duration =
            component.state, component.start_time, component.duration
    end
    -- Once per gameplay frame, after input.
    function api.sample(unit)
        local mode = test_flag() or mod:get("vr_haptics_mode")
        if not unit or (mode ~= "informative" and mode ~= "immersive") then
            previous, previous_body, previous_gauges, previous_melee, previous_interaction = nil, nil, nil, nil, nil
            return
        end
        local unit_data = extension(unit, "unit_data_system", "unit_data")
        -- Once, for the gauges and the ammo step both.
        local inventory = unit_data and component(unit_data, "inventory")
        if unit_data then
            local body = section("haptics.read_body", read_body, unit, unit_data)
            -- The first event this mode plays; the rest of the frame is one pulse.
            for _, event in ipairs(section("haptics.body_events", body_events_of, previous_body, body)) do
                if Haptics.plays(event[1], mode) then
                    if api.pulse("both", event[1], nil, event[2]) then count(event[1]) end
                    break
                end
            end
            previous_body = body
            local wielded = field_of(inventory, "wielded_slot")
            local charge_component = section("haptics.read_gauges", component, unit_data, "action_module_charge")
            local gauges = {
                heat = type(wielded) == "string" and wielded:match("^slot_") and
                    component_field(unit_data, wielded, "overheat_current_percentage") or nil,
                peril = component_field(unit_data, "warp_charge", "current_percentage"),
                charge = field_of(charge_component, "charge_level"),
                max_charge = field_of(charge_component, "max_charge"),
            }
            for _, event in ipairs(section("haptics.gauge_events", gauge_events_of, previous_gauges, gauges)) do
                if Haptics.plays(event[1], mode) then
                    local hands = event[3] == "both" and "both" or gun_hands()
                    if hands and api.pulse(hands, event[1], nil, event[2]) then count(event[1]) end
                    break
                end
            end
            previous_gauges = gauges
            local reading = {melee = false}
            section("haptics.read_melee", pcall, read_melee, reading, unit, unit_data, wielded)
            for _, event in ipairs(section("haptics.melee_events", melee_events_of, previous_melee, reading)) do
                if Haptics.plays(event[1], mode) then
                    local hands = gun_hands()
                    if hands and api.pulse(hands, event[1], nil, event[2]) then count(event[1]) end
                    break
                end
            end
            previous_melee = reading
            local interaction = {t = reading.t}
            section("haptics.read_interaction", pcall, read_interaction, interaction, unit_data)
            for _, event in ipairs(section("haptics.interaction_events", interaction_events_of,
                    previous_interaction, interaction)) do
                if Haptics.plays(event[1], mode) then
                    local hands = melee_hands()
                    if hands and api.pulse(hands, event[1], nil, event[2]) then count(event[1]) end
                    break
                end
            end
            previous_interaction = interaction
        end
        -- The inventory read above. (It was an unprotected second read here;
        -- a throwing read now ends the ammo step rather than the whole sample,
        -- which is the only behavioural difference and the safer one.)
        if not inventory or inventory.wielded_slot ~= "slot_secondary" then previous = nil; return end
        local values = presentation.ammo_readout and presentation.ammo_readout.slot_values and
            section("haptics.ammo_slot_values", presentation.ammo_readout.slot_values, unit)
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
