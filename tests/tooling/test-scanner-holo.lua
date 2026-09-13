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
local other = {__class_name = "WeaponShoutEffects", update_unit_position = function() error("other script re-run") end}
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

-- Other held-item effects: each placer only moves what exists.
do
    local moves, fx_updates, stock_calls, windups = {}, {}, {}, 0
    World = {move_particles = function(world, id, position, rotation)
        moves[#moves + 1] = {world = world, id = id, position = position, rotation = rotation}
    end}
    Matrix4x4 = {translation = function(pose) return pose.translation end}
    Quaternion = {forward = function(q) return q.forward end, look = function(direction) return {look = direction} end}
    local flamer = {__class_name = "FlamerGasEffects", _world = "world", _fx_source_name = "_muzzle",
        _fx_extension = {vfx_spawner_pose = function(_, name) assert(name == "_muzzle"); return {translation = "muzzle_after_ik"} end},
        _first_person_component = {rotation = {forward = "aim_forward"}},
        update_unit_position = function() error("flamer full update re-run") end,
        _update_effects = function() error("flamer effects update re-run") end}
    local links = {__class_name = "ChainLightningLinkEffects",
        update_unit_position = function() error("link targets re-picked") end,
        _update_fx = function(_, t) fx_updates[#fx_updates + 1] = t end}
    local hand = {__class_name = "ChainLightningAbilityHandEffects",
        update_unit_position = function(_, unit, dt, t) stock_calls[#stock_calls + 1] = {unit, dt, t} end}
    local slash = {__class_name = "ForceWeaponWindSlashActivationEffects",
        update_unit_position = function(_, unit, dt, t) stock_calls[#stock_calls + 1] = {unit, dt, t} end}
    local shield = {__class_name = "RiotShieldEffects",
        update = function() error("shield update re-run") end,
        _update_windup_vfx_loop = function() windups = windups + 1 end}
    loadout._wieldable_slot_scripts.slot_primary = {flamer, links, hand, slash, shield}
    loadout._inventory_component.wielded_slot = "slot_primary"
    local logs = #infos
    -- Not firing, no windup: the flamer and shield move nothing.
    assert(api.place("player", 20) == 5)
    assert(#moves == 0 and windups == 0)
    assert(#fx_updates == 1 and fx_updates[1] == 20)
    assert(#stock_calls == 2 and stock_calls[1][1] == "player" and stock_calls[1][2] == 0 and stock_calls[1][3] == 20)
    -- One log per class, not per frame.
    assert(#infos == logs + 5 and infos[logs + 1]:find("DARKTIDEVR_HELD_EFFECTS placed class=FlamerGasEffects", 1, true), infos[logs + 1])
    -- Firing and winding up: the stream moves to the posed muzzle along the aim.
    flamer._stream_effect_id = 7
    shield._looping_windup_effect_id = 3
    api.place("player", 20.1)
    assert(#moves == 1 and moves[1].world == "world" and moves[1].id == 7)
    assert(moves[1].position == "muzzle_after_ik" and moves[1].rotation.look == "aim_forward")
    assert(windups == 1 and #infos == logs + 5)
    loadout._inventory_component.wielded_slot = "slot_device"
end

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
-- It hands out the scanning auspex, not the not-wieldable decoding device.
assert(main:sub(toggle, toggle_end):find('weapon_template == "scanner_equip"', 1, true), "scan test item is not scanner_equip")
assert(not main:sub(toggle, toggle_end):find("scanner_test_item()", 1, true), "scan test uses the decoding auspex")
print("scanner_holo=pass replaced_after_hand_pose dt0 auspex_only log_per_scan failure_contained test_zone")
