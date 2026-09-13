-- The scan hologram is placed again after the tracked hand pose, from the
-- scanner in the hand: only the stock auspex scanning script, at dt 0 and the
-- frame's t. The Psykhanium check stands in for a scanning zone only while on.
local ScannerHolo = dofile(assert(arg[1]))
local function vec(x, y, z) return {x = x, y = y, z = z} end
Vector3 = {distance = function(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
end}
local positions = {}
Unit = {alive = function(u) return u ~= nil and not u.dead end,
    local_position = function(u, node) assert(node == 1); return positions[u] end,
    world_position = function(u, node) assert(node == 2); return positions[u] end}
local loadout = {_inventory_component = {wielded_slot = "slot_device"}, _wieldable_slot_scripts = {}}
ScriptUnit = {has_extension = function(unit, name)
    assert(name == "visual_loadout_system"); return unit == "player" and loadout or nil
end}
local infos, hooks = {}, {}
local mod = {info = function(_, format, ...) infos[#infos + 1] = string.format(format, ...) end,
    hook_require = function(_, path, fn) hooks.path = path; fn(hooks) end,
    hook = function(_, class, name, fn) assert(class == hooks); hooks[name] = fn end}
local api = ScannerHolo.install(mod)

-- Scripts: the auspex scanner effects, another script, a deleted one.
local holo, item = {}, {}
local calls = {}
local auspex = {__class_name = "AuspexScanningEffects", _player_holo_unit = holo, _item_unit_3p = item,
    _is_screen_enabled = false}
function auspex.update_unit_position(self, unit, dt, t)
    calls[#calls + 1] = {unit = unit, dt = dt, t = t}
    positions[holo] = vec(0, 0, 1.084)
end
local other = {__class_name = "FlamerGasEffects", update_unit_position = function() error("other script re-run") end}
local deleted = setmetatable({__class_name = "AuspexScanningEffects", __deleted = true},
    {__index = function() error("deleted script touched") end})
loadout._wieldable_slot_scripts.slot_device = {other, deleted, auspex}
loadout._wieldable_slot_scripts.slot_primary = {auspex}

-- Not scanning: placed again, no log.
positions[holo] = vec(0.4, 0.3, 1.2); positions[item] = vec(0, 0, 1)
assert(api.place("player", 12.5) == 1)
assert(#calls == 1 and calls[1].unit == "player" and calls[1].dt == 0 and calls[1].t == 12.5)
assert(#infos == 0)
-- Scan starts: one log with the stock placement's miss and the new distance to the scanner.
auspex._is_screen_enabled = true
positions[holo] = vec(0.4, 0.3, 1.2)
api.place("player", 12.6)
assert(#infos == 1, infos[1])
assert(infos[1]:find("scan=start moved_m=0.513 holo_to_scanner_m=0.084 test_zone=false", 1, true), infos[1])
api.place("player", 12.7)
assert(#infos == 1, "logged every scanning frame")
auspex._is_screen_enabled = false; api.place("player", 12.8)
auspex._is_screen_enabled = true; api.place("player", 12.9)
assert(#infos == 2, "a new scan did not log")
-- Nothing wielded, other slot, missing unit or t: nothing runs.
local before = #calls
loadout._inventory_component.wielded_slot = "slot_secondary"
assert(api.place("player", 13) == 0)
loadout._inventory_component.wielded_slot = "slot_device"
assert(api.place("husk", 13) == 0 and api.place(nil, 13) == 0 and api.place("player", nil) == 0)
assert(#calls == before)
-- A failing placement is contained and logged once.
auspex.update_unit_position = function() error("retired holo") end
assert(api.place("player", 14) == 0 and api.place("player", 14) == 0)
assert(api.failures == 2 and #infos == 3 and infos[3]:find("DARKTIDEVR_SCANNER_HOLO fallback=", 1, true))

-- Scanning zone stand-in.
assert(hooks.path == "scripts/extension_systems/mission_objective_zone/mission_objective_zone_system")
local stock = function(self) return self.real end
assert(hooks.any_active_scanning_zone(stock, {real = false}) == false)
assert(hooks.any_active_scanning_zone(stock, {real = true}) == true)
api.test_zone = true
assert(hooks.any_active_scanning_zone(stock, {real = false}) == true)
api.test_zone = false
assert(hooks.any_active_scanning_zone(stock, {real = false}) == false)

-- The main chunk places the hologram after the hand pose, and a map change ends the check.
local file = assert(io.open(assert(arg[2]), "rb")); local main = file:read("*a"); file:close()
local ik = assert(main:find("presentation.gun_aim.update(self._world, player_unit)", 1, true))
local place = assert(main:find("presentation.scanner_holo.place(player_unit, t)", 1, true))
assert(place > ik, "hologram placed before the hand pose")
local state = assert(main:find("mod.on_game_state_changed = function", 1, true))
assert(main:find("presentation.scanner_holo.test_zone = false", state, true), "test zone survives a map change")
-- The test hands out the auspex but never writes the wield itself.
local toggle = assert(main:find("mod.toggle_scan_test = function", 1, true))
local toggle_end = assert(main:find('mod:command("dtvr_scan_test"', toggle, true))
assert(not main:sub(toggle, toggle_end):find("wield_slot", 1, true), "scan test writes a wield")
print("scanner_holo=pass replaced_after_hand_pose dt0 auspex_only log_per_scan failure_contained test_zone")
