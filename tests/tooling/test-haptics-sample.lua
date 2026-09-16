-- A behaviour lock for haptics' per-frame sample: scripted component values
-- across frames, every pulse recorded. The trace below was taken from the
-- code as it stood before the allocation rewrite of 16 September; the
-- rewrite must reproduce it exactly. Run with TRACE=1 to print a fresh trace.
local Haptics = dofile(assert(arg[1]))

-- install requires the stock melee classes to hook them and reads the attack
-- strength table at load; the same stubs the haptics test uses.
local real_require = require
require = function(name)
    if name:find("attack_settings$") then return {melee_attack_strength = {heavy = "heavy", light = "light"}} end
    if name:find("action_sweep$") or name:find("action_melee_explosive$") or name:find("action_push$") then
        return {_play_hit_effects = function() end, _play_push_rumble = function() end}
    end
    return real_require(name)
end
Mods = {lua = {io = {open = function() return nil end}}}
local clock = 100
Managers = {time = {has_timer = function() return true end,
    time = function() return clock end}}

-- The scripted world: components by name, and the extensions the sample asks for.
local components, health, toughness, ability, template
local function reset_world()
    components = {
        character_state = {state_name = "walking"},
        disabled_character_state = {is_disabled = false},
        stamina = {current_fraction = 1},
        block = {has_blocked = false, is_perfect_blocking = false},
        inventory = {wielded_slot = "slot_primary", slot_secondary = "gun_a"},
        slot_primary = {special_active = false, overheat_current_percentage = 0},
        slot_secondary = {special_active = false, overheat_current_percentage = 0},
        warp_charge = {current_percentage = 0},
        action_module_charge = {charge_level = 0, max_charge = 1},
        weapon_action = {current_action_name = "none", start_t = 0, time_scale = 1},
        interaction = {state = "waiting_to_interact", start_time = 0, duration = 0},
    }
    health = {current_health = function() return 100 end, max_health = function() return 100 end}
    toughness = {current_toughness_percent = function() return 1 end}
    ability = {remaining_ability_charges = function(_, name) return name == "combat_ability" and 1 or 2 end}
    template = {keywords = {"melee"}, actions = {
        action_melee_start_left = {kind = "windup", allowed_chain_actions = {heavy_attack = {chain_time = 0.5}}}}}
end
local unit = {}
ScriptUnit = {has_extension = function(u, name)
    if u ~= unit then return nil end
    if name == "unit_data_system" then return {read_component = function(_, key) return components[key] end} end
    if name == "health_system" then return health end
    if name == "toughness_system" then return toughness end
    if name == "ability_system" then return ability end
    if name == "weapon_system" then return {weapon_template = function() return template end} end
    return nil
end}

local ammo = nil
local function run(mode)
    reset_world()
    local pulses = {}
    local api = Haptics.install({
        get = function(_, key) return key == "vr_haptics_mode" and mode or nil end,
        info = function() end,
        hook_safe = function() end,
    }, {
        online_rules = {simulation_aim_active = function(u) return u == unit end},
        weapon_hand_roles = {physical = function(role) return role == "dominant" and "right" or "left" end},
        hand_side = function(role) return role == "support" and "left" or "right" end,
        using_native_menu_input = function() return true end,
        two_hand = {held = false},
        ammo_readout = {slot_values = function() return ammo end},
    }, function(hands, amplitude) pulses[#pulses + 1] = string.format("%d:%.3f", hands, amplitude); return true end)
    local function frame() clock = clock + 1; api.sample(unit) end
    frame()                                                       -- 1 baseline, nothing to compare
    health.current_health = function() return 70 end; frame()    -- 2 damage
    toughness.current_toughness_percent = function() return 0 end; frame() -- 3 toughness broken
    components.block.has_blocked = true; frame()                 -- 4 block
    components.block.has_blocked = false
    components.stamina.current_fraction = 0; frame()             -- 5 stamina out
    components.character_state.state_name = "knocked_down"; frame() -- 6 disabled
    components.character_state.state_name = "walking"; frame()   -- 7 recovered
    components.warp_charge.current_percentage = 0.97; frame()    -- 8 peril
    components.action_module_charge.charge_level = 1; frame()    -- 9 charge full
    components.weapon_action.current_action_name = "action_melee_start_left"
    components.weapon_action.start_t = clock; frame()            -- 10 windup starts
    frame(); frame()                                             -- 11-12 heavy ready
    components.weapon_action.current_action_name = "none"; frame() -- 13
    components.slot_primary.special_active = true; frame()       -- 14 special on
    components.slot_primary.special_active = false; frame()      -- 15
    components.interaction.state = "is_interacting"; components.interaction.start_time = clock
    components.interaction.duration = 2; frame()                 -- 16 interacting
    frame()                                                      -- 17 hum
    components.interaction.state = "waiting_to_interact"; frame() -- 18 done
    components.inventory.wielded_slot = "slot_secondary"
    ammo = {clip = 5, clip_max = 5, reserve = 20, reserve_max = 20}; frame() -- 19 gun out
    ammo = {clip = 0, clip_max = 5, reserve = 20, reserve_max = 20}; frame() -- 20 clip empty
    ammo = {clip = 5, clip_max = 5, reserve = 15, reserve_max = 20}; frame() -- 21 reloaded
    ammo = {clip = 1, clip_max = 5, reserve = 2, reserve_max = 20}; frame()  -- 22 low ammo
    ammo = nil; components.inventory.wielded_slot = "slot_primary"; frame() -- 23 melee again
    -- A slot whose config does not declare the two weapon-specific fields:
    -- the stock read proxy throws on an undeclared field (its __index does
    -- config[field].type), so those two reads must stay guarded. Every other
    -- field the sample reads is in the static config and cannot throw.
    components.slot_primary = setmetatable({}, {__index = function(_, key)
        if key == "overheat_current_percentage" or key == "special_active" then
            error("undeclared field " .. key)
        end
        return nil
    end})
    frame()                                                      -- 24 strict slot
    -- Off: nothing, and the history is dropped so nothing fires on return.
    mode = "off"; frame()
    return pulses
end

local informative = run("informative")
local immersive = run("immersive")
require = real_require

if os.getenv("TRACE") then
    print("informative=" .. table.concat(informative, " "))
    print("immersive=" .. table.concat(immersive, " "))
    return
end

-- The lock. Hands: 1 left, 2 right, 3 both (Haptics.HANDS). Amplitude is the
-- kind's, times any scale the event carried.
local EXPECT_INFORMATIVE = "3:0.700 3:0.600 3:0.500 3:0.400 3:1.000 3:0.900 2:0.350 2:0.300 2:0.500 2:0.500 2:0.800 2:0.500 2:0.400"
local EXPECT_IMMERSIVE = "3:0.700 3:0.600 3:0.500 3:1.000 3:0.900 2:0.350 2:0.300 2:0.500 2:0.200 2:0.500 2:0.800 2:0.500"
assert(table.concat(informative, " ") == EXPECT_INFORMATIVE,
    "informative trace changed:\n  got  " .. table.concat(informative, " ") .. "\n  want " .. EXPECT_INFORMATIVE)
assert(table.concat(immersive, " ") == EXPECT_IMMERSIVE,
    "immersive trace changed:\n  got  " .. table.concat(immersive, " ") .. "\n  want " .. EXPECT_IMMERSIVE)
print("haptics_sample=pass locked " .. #informative .. " informative and " .. #immersive .. " immersive pulses")
