-- Haptic pulses: kinds and hands map to the native request, each kind plays
-- only in its modes, a hand is rate limited (notices are not dropped for a
-- feel pulse), a failed send does not count, and ammo readings become events.
local Haptics = dofile(assert(arg[1]))

local sent, mode, deliver = {}, "immersive", true
local api = Haptics.new(function(hands, amplitude, duration_ms, frequency_hz)
    sent[#sent + 1] = {hands, amplitude, duration_ms, frequency_hz}
    return deliver
end, function() return mode end)

assert(api.pulse("left", "zone", 1.0))
assert(sent[1][1] == 1 and sent[1][2] == Haptics.KINDS.zone.amplitude and
    sent[1][3] == Haptics.KINDS.zone.duration_ms and sent[1][4] == 0)
assert(not api.pulse("left", "grip", 1.03), "notices on one hand were not rate limited")
assert(api.pulse("right", "grip", 1.03), "the other hand was rate limited")
assert(sent[2][1] == 2 and sent[2][3] == Haptics.KINDS.grip.duration_ms)
assert(api.pulse("left", "grip", 1.0 + Haptics.MIN_INTERVAL), "pulse after the interval dropped")
-- A clock that goes backwards (a new timer) is not rate limited forever.
assert(api.pulse("left", "zone", 0.2))
assert(api.sent == 4 and api.dropped == 1)

-- Both hands: one request with both bits, limited by either hand.
assert(api.pulse("both", "shot", 5.0) and sent[#sent][1] == 3)
assert(not api.pulse("right", "shot", 5.02), "a hand pulsed inside both hands' interval")
-- A notice is not dropped for a recent feel pulse, but a feel pulse is.
assert(api.pulse("both", "clip_empty", 5.03), "a notice was dropped for a shot")
assert(not api.pulse("both", "shot", 5.05), "a shot interrupted a notice")

-- Unknown hands, kinds and times send nothing.
local before = #sent
assert(not api.pulse("feet", "zone", 9) and not api.pulse("left", "rumble", 9))
assert(not api.pulse("left", "zone", nil) and not api.pulse("left", "zone", 0 / 0))
assert(#sent == before)

-- Modes: off and unknown play nothing; each kind only in its listed modes.
for _, off in ipairs({"off", nil, false, "loud"}) do
    mode = off
    assert(not api.pulse("right", "zone", 20), "mode " .. tostring(off) .. " sent a pulse")
end
assert(#sent == before)
mode = "informative"
assert(not api.pulse("right", "shot", 30), "informative played a shot")
assert(api.pulse("right", "low_ammo", 31), "informative dropped low ammo")
mode = "immersive"
assert(not api.pulse("left", "low_ammo", 40), "immersive played an informative-only notice")
assert(api.pulse("left", "shot", 41) and api.pulse("right", "reload", 41), "immersive dropped a shared kind")
-- Every kind plays in at least one mode, and never in off.
for name, shape in pairs(Haptics.KINDS) do
    assert(shape.modes.informative or shape.modes.immersive, name .. " plays in no mode")
    assert(not Haptics.plays(name, "off"), name .. " plays when off")
    assert(shape.amplitude > 0 and shape.amplitude <= 1, name)
    assert(shape.duration_ms >= 1 and shape.duration_ms <= 1000 and shape.duration_ms % 1 == 0, name)
end

-- A failed send is not counted and does not start the interval.
deliver = false
assert(not api.pulse("right", "zone", 50))
deliver = true
assert(api.pulse("right", "zone", 50.01), "a failed send started the rate limit")

-- Ammo events.
local function reading(clip, reserve, weapon)
    return {weapon = weapon or "rifle", clip = clip, clip_max = 20, reserve = reserve, reserve_max = 180}
end
local E = Haptics.ammo_events
assert(E(reading(1, 100), reading(0, 100)) == "clip_empty")
assert(E(reading(0, 100), reading(0, 100)) == nil, "an empty clip repeated")
assert(E(reading(0, 100), reading(20, 80)) == "reload", "a full reload was missed")
assert(E(reading(5, 100), reading(6, 99)) == nil, "a shell mid-reload pulsed")
assert(E(reading(19, 81), reading(20, 80)) == "reload", "the last shell of a reload was missed")
assert(E(reading(0, 3), reading(3, 0)) == "reload", "a reload that emptied the reserve was missed")
assert(E(reading(10, 50), reading(10, 90)) == nil, "an ammo pickup counted as a reload")
assert(E(reading(10, 31), reading(9, 31)) == "low_ammo", "crossing 20 % was missed")
assert(E(reading(9, 31), reading(8, 31)) == nil, "low ammo repeated below the threshold")
assert(E(reading(1, 100), reading(0, 100, "other")) == nil, "a weapon swap produced an event")
assert(E(nil, reading(0, 0)) == nil and E(reading(1, 1), nil) == nil)

-- Amplitude scale.
mode = "immersive"
assert(api.pulse("left", "damage", 60, 0.5) and math.abs(sent[#sent][2] - Haptics.KINDS.damage.amplitude * 0.5) < 1e-9)
assert(api.pulse("right", "damage", 60, 9) and sent[#sent][2] == 1, "scale was not clamped")

-- Body events.
local function body(fields)
    local b = {health = 200, max_health = 200, toughness = 1, disabled = false, stamina = 1,
        blocked = false, perfect_block = false, combat_charges = 1, grenade_charges = 2}
    for k, v in pairs(fields or {}) do b[k] = v end
    return b
end
local function kinds(previous, current)
    local out = {}
    for _, event in ipairs(Haptics.body_events(previous, current)) do out[#out + 1] = event[1] end
    return table.concat(out, ",")
end
assert(kinds(body(), body()) == "", "an unchanged body produced events")
assert(kinds(nil, body()) == "")
local hit = Haptics.body_events(body(), body({health = 175, toughness = 0.5}))
assert(hit[1][1] == "damage" and math.abs(hit[1][2] - 0.5) < 1e-9, "damage scale: " .. tostring(hit[1][2]))
assert(#hit == 1, "toughness loss with health loss also pulsed a toughness hit")
assert(Haptics.body_events(body(), body({health = 199}))[1][2] == 0.4, "small damage below the minimum scale")
assert(kinds(body(), body({toughness = 0})) == "toughness_broken")
assert(kinds(body({toughness = 0}), body({toughness = 0})) == "")
assert(kinds(body(), body({toughness = 0.9})) == "toughness_hit")
assert(kinds(body(), body({disabled = true, health = 300, max_health = 300})) == "disabled",
    "becoming disabled pulsed more than the disable")
assert(kinds(body({disabled = true}), body({disabled = true, health = 150})) == "damage", "damage while down was missed")
assert(kinds(body(), body({blocked = true})) == "block")
assert(kinds(body(), body({blocked = true, perfect_block = true})) == "perfect_block")
assert(kinds(body({blocked = true}), body({blocked = true})) == "", "a held block repeated")
assert(kinds(body({health = 60}), body({health = 50})) == "damage,low_health")
assert(kinds(body({stamina = 0.3}), body({stamina = 0})) == "stamina_empty")
assert(kinds(body(), body({combat_charges = 0})) == "ability_used")
assert(kinds(body({combat_charges = 0}), body()) == "ability_ready")
assert(kinds(body({grenade_charges = 1}), body()) == "blitz_ready")
assert(kinds(body(), body({grenade_charges = 1})) == "", "a thrown blitz pulsed")
assert(kinds(body({health = 0 / 0}), body({health = 100})) == "", "a missing reading produced damage")
-- Every body kind named by body_events exists and plays in a mode.
for _, name in ipairs({"damage", "toughness_broken", "toughness_hit", "disabled", "low_health", "stamina_empty",
        "block", "perfect_block", "ability_used", "ability_ready", "blitz_ready"}) do
    assert(Haptics.KINDS[name], name)
end
assert(Haptics.DISABLED_STATES.knocked_down and Haptics.DISABLED_STATES.netted and not Haptics.DISABLED_STATES.walking)

-- Installed melee observers: a local connecting sweep pulses the dominant hand
-- (heavy full strength), a push both hands, a resimulated or foreign action
-- nothing; a subclass sharing the parent's method is not hooked twice.
do
    local hooks, pulses = {}, {}
    local sweep = {_play_hit_effects = function() end}
    local explosive = setmetatable({}, {__index = sweep})
    local push = {_play_push_rumble = function() end}
    local real_require = require
    require = function(name)
        if name:find("action_sweep$") then return sweep end
        if name:find("action_melee_explosive$") then return explosive end
        if name:find("action_push$") then return push end
        if name:find("attack_settings$") then return {melee_attack_strength = {heavy = "heavy", light = "light"}} end
        return real_require(name)
    end
    local clock = 100
    Managers = {time = {has_timer = function() return true end, time = function() clock = clock + 1; return clock end}}
    local local_unit = {}
    local mode, native_menu = "immersive", true
    local installed = Haptics.install({
        get = function(_, key) return key == "vr_haptics_mode" and mode or nil end,
        info = function() end,
        hook_safe = function(_, object, method, handler) hooks[#hooks + 1] = {object, method, handler} end,
    }, {
        online_rules = {simulation_aim_active = function(unit) return unit == local_unit end},
        weapon_hand_roles = {physical = function(role) return role == "dominant" and "right" or "left" end},
        using_native_menu_input = function() return native_menu end,
    }, function(hands, amplitude) pulses[#pulses + 1] = {hands, amplitude}; return true end)
    require = real_require
    assert(#hooks == 3, "expected sweep, push and UI sound hooks, got " .. #hooks)
    local function hook(object, method)
        for _, h in ipairs(hooks) do if h[1] == object and h[2] == method then return h[3] end end
    end
    local hit, shove = hook(sweep, "_play_hit_effects"), hook(push, "_play_push_rumble")
    assert(hit and shove)
    hit({_player_unit = local_unit}, {}, {melee_attack_strength = "heavy"})
    assert(pulses[1][1] == 2 and pulses[1][2] == Haptics.KINDS.melee_hit.amplitude, "heavy hit")
    hit({_player_unit = local_unit}, {}, {melee_attack_strength = "light"})
    assert(math.abs(pulses[2][2] - Haptics.KINDS.melee_hit.amplitude * Haptics.LIGHT_MELEE_SCALE) < 1e-6, "light hit")
    hit({_player_unit = {}}, {}, {})
    hit({_player_unit = local_unit, _unit_data_extension = {is_resimulating = true}}, {}, {})
    assert(#pulses == 2, "a foreign or resimulated hit pulsed")
    shove({_player_unit = local_unit}, 0)
    assert(pulses[3][1] == 3 and math.abs(pulses[3][2] - Haptics.KINDS.push.amplitude * Haptics.MISSED_PUSH_SCALE) < 1e-6)
    hit({_player_unit = local_unit}, {}, nil) -- a missing profile is a light hit, not an error
    assert(#pulses == 4)
    -- Menu sounds: both modes, and only while the VR pointer owns menus.
    local sound = hook("UIManager", "play_2d_sound")
    assert(sound, "UI sound hook")
    sound({}, "wwise/events/ui/play_ui_mouseover")
    assert(#pulses == 5 and pulses[5][1] == 2 and pulses[5][2] == Haptics.KINDS.menu_hover.amplitude,
        "menu hover tick in immersive mode")
    mode = "informative"
    sound({}, "wwise/events/ui/play_ui_click")
    assert(#pulses == 6 and pulses[6][2] == Haptics.KINDS.menu_confirm.amplitude, "menu confirm tick")
    native_menu = false
    sound({}, "wwise/events/ui/play_ui_click")
    assert(#pulses == 6, "menu tick without the VR pointer")
    Managers = nil
end

-- Shot strength by family.
assert(Haptics.shot_scale("bolter_p1_m2", "shoot_projectile") == 1.0)
assert(Haptics.shot_scale("boltpistol_p1_m1") == 0.9, "boltpistol matched bolter first")
assert(Haptics.shot_scale("lasgun_p2_m3") == 0.75 and Haptics.shot_scale("lasgun_p1_m1") == 0.45, "helbore")
assert(Haptics.shot_scale("shotpistol_shield_p1_m1") == 0.75 and Haptics.shot_scale("shotgun_p4_m1") == 0.9)
assert(Haptics.shot_scale("flamer_p1_m1", "flamer_gas") == Haptics.SHOT_STREAM)
assert(Haptics.shot_scale("forcestaff_p2_m1", "flamer_gas_burst") == Haptics.SHOT_STREAM, "flame staff stream")
assert(Haptics.shot_scale("galvanic_rifle_p1_m1", "shoot_hit_scan") == 0.7)
assert(Haptics.shot_scale("unknown_gun") == Haptics.SHOT_DEFAULT and Haptics.shot_scale(nil) == Haptics.SHOT_DEFAULT)
for _, family in ipairs(Haptics.SHOT_FAMILIES) do assert(family[2] > 0 and family[2] <= 1, family[1]) end
-- Every family is reachable (no earlier prefix swallows it).
for index, family in ipairs(Haptics.SHOT_FAMILIES) do
    assert(Haptics.shot_scale(family[1] .. "_x") == family[2], family[1] .. " is shadowed by an earlier prefix")
    for earlier = 1, index - 1 do
        local prefix = Haptics.SHOT_FAMILIES[earlier][1]
        assert(family[1]:sub(1, #prefix) ~= prefix or family[2] == Haptics.SHOT_FAMILIES[earlier][2], family[1])
    end
end

-- Gauges.
local function gauge(fields)
    local g = {heat = 0.1, peril = 0.1, charge = 0, max_charge = 1}
    for k, v in pairs(fields or {}) do g[k] = v end
    return g
end
local function gauge_kinds(previous, current)
    local out = {}
    for _, event in ipairs(Haptics.gauge_events(previous, current)) do out[#out + 1] = event[1] .. ":" .. event[3] end
    return table.concat(out, ",")
end
assert(gauge_kinds(gauge(), gauge()) == "")
assert(gauge_kinds(gauge({heat = 0.7}), gauge({heat = 0.8})) == "heat_warning:gun")
assert(gauge_kinds(gauge({heat = 0.7}), gauge({heat = 0.95})) == "heat_critical:gun", "a jump past both thresholds warned twice")
assert(gauge_kinds(gauge({heat = 0.95}), gauge({heat = 0.97})) == "", "heat above critical repeated")
assert(gauge_kinds(gauge({heat = 0.95}), gauge({heat = 0.5})) == "", "cooling down pulsed")
assert(gauge_kinds(gauge({peril = 0.8}), gauge({peril = 0.92})) == "peril_critical:both")
assert(gauge_kinds(gauge({peril = 0.5}), gauge({peril = 0.76})) == "peril_warning:both")
local rising = Haptics.gauge_events(gauge({charge = 0.2}), gauge({charge = 0.3}))
assert(rising[1][1] == "charging" and rising[1][2] == 0.4, "low charge buzz below the minimum")
assert(Haptics.gauge_events(gauge({charge = 0.7}), gauge({charge = 0.8}))[1][2] == 0.8)
assert(gauge_kinds(gauge({charge = 0.9}), gauge({charge = 1})) == "charge_full:gun")
assert(gauge_kinds(gauge({charge = 1}), gauge({charge = 1})) == "", "a held full charge repeated")
assert(gauge_kinds(gauge({charge = 0.5}), gauge({charge = 0})) == "", "releasing a charge pulsed")
assert(gauge_kinds(gauge({charge = 1.5, max_charge = 2}), gauge({charge = 2, max_charge = 2})) == "charge_full:gun")
assert(gauge_kinds(gauge({heat = 0.7, peril = 0.8}), gauge({heat = 0.8, peril = 0.95})) == "heat_warning:gun,peril_critical:both")
assert(gauge_kinds(nil, gauge()) == "")
assert(gauge_kinds(gauge({heat = false}), gauge({heat = 0.99})) == "", "a missing heat reading warned")

-- Melee windup and special.
local function melee_kinds(previous, current)
    local out = {}
    for _, event in ipairs(Haptics.melee_events(previous, current)) do out[#out + 1] = event[1] end
    return table.concat(out, ",")
end
assert(melee_kinds({t = 10.3, windup_start = 10, heavy_time = 0.5}, {t = 10.4, windup_start = 10, heavy_time = 0.5}) == "")
assert(melee_kinds({t = 10.45, windup_start = 10, heavy_time = 0.5}, {t = 10.52, windup_start = 10, heavy_time = 0.5}) == "heavy_ready")
assert(melee_kinds({t = 10.52, windup_start = 10, heavy_time = 0.5}, {t = 10.6, windup_start = 10, heavy_time = 0.5}) == "",
    "a held heavy repeated")
assert(melee_kinds({t = 10.6, windup_start = 10, heavy_time = 0.5}, {t = 11.05, windup_start = 11, heavy_time = 0.5}) == "",
    "a new windup was ready at once")
assert(melee_kinds({t = 10.6}, {t = 10.7, windup_start = 10, heavy_time = 0.5}) == "heavy_ready",
    "a windup first seen past its heavy time was missed")
assert(melee_kinds({t = 1, melee = true}, {t = 1.02, melee = true, special = true}) == "special_on")
assert(melee_kinds({t = 1.02, melee = true, special = true}, {t = 1.04, melee = true, special = true}) == "")
assert(melee_kinds({t = 1.24, melee = true, special = true}, {t = 1.26, melee = true, special = true}) == "special_hum")
assert(melee_kinds({t = 1, melee = false}, {t = 1.02, melee = false, special = true}) == "", "a flashlight hummed")
assert(melee_kinds(nil, {t = 1}) == "")

-- Interactions.
local function interaction_kinds(previous, current)
    local out = {}
    for _, event in ipairs(Haptics.interaction_events(previous, current)) do out[#out + 1] = event[1] end
    return table.concat(out, ",")
end
local holding = {t = 5.0, state = "is_interacting", start_time = 4.0, duration = 1.0}
assert(interaction_kinds(holding, {t = 5.02, state = "none"}) == "interaction_done", "a finished hold was missed")
assert(interaction_kinds({t = 4.5, state = "is_interacting", start_time = 4.0, duration = 1.0}, {t = 4.52, state = "none"}) == "",
    "a released hold counted as finished")
assert(interaction_kinds({t = 1, state = "is_interacting", start_time = 1, duration = 0}, {t = 1.01, state = "none"}) ==
    "interaction_done", "an instant interaction was missed")
assert(interaction_kinds({t = 4.24, state = "is_interacting", start_time = 4, duration = 1},
    {t = 4.26, state = "is_interacting", start_time = 4, duration = 1}) == "interaction_hum")
assert(interaction_kinds({t = 4.21, state = "is_interacting", start_time = 4, duration = 1},
    {t = 4.23, state = "is_interacting", start_time = 4, duration = 1}) == "")
assert(interaction_kinds({t = 1, state = "none"}, {t = 1.02, state = "is_interacting", start_time = 1, duration = 2}) == "")
assert(interaction_kinds(nil, {t = 1}) == "")
-- Strength option.
assert(Haptics.strength_scale(100) == 1 and Haptics.strength_scale(50) == 0.5)
assert(Haptics.strength_scale(1000) == 2 and Haptics.strength_scale(1) == 0.25, "strength not clamped to its range")
assert(Haptics.strength_scale(nil) == 1 and Haptics.strength_scale(0 / 0) == 1)

-- Menu kinds from stock UI sound events.
assert(Haptics.menu_kind("wwise/events/ui/play_ui_mouseover") == "menu_hover")
assert(Haptics.menu_kind("wwise/events/ui/play_ui_mission_buffs_buff_hover_enter") == "menu_hover", "hover wins over enter")
assert(Haptics.menu_kind("wwise/events/ui/play_ui_click") == "menu_confirm")
assert(Haptics.menu_kind("wwise/events/ui/play_ui_back_short") == "menu_confirm")
assert(Haptics.menu_kind("wwise/events/ui/play_ui_enter_short") == "menu_confirm")
assert(Haptics.menu_kind("wwise/events/ui/play_ui_talents_default_select") == "menu_confirm")
assert(Haptics.menu_kind("wwise/events/ui/play_ui_background_music") == nil and Haptics.menu_kind(nil) == nil)
assert(Haptics.plays("menu_hover", "informative") and Haptics.plays("menu_hover", "immersive"))
assert(Haptics.plays("menu_confirm", "informative") and Haptics.plays("menu_confirm", "immersive"))
print("haptics=pass mapping rate_limit notices modes failed_send ammo_events scale body_events melee_hooks shot_families gauges melee_windup_special interaction strength menu")
