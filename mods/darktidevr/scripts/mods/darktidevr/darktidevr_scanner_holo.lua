-- The auspex scan hologram (stock AuspexScanningEffects) is a set of free
-- world units placed from the held scanner's node 2 in the visual loadout's
-- update_unit_position. That runs inside locomotion post_update, before the
-- tracked hand pose moves the held scanner, so the hologram sat where the
-- animation holds the scanner rather than above the scanner in the hand.
-- After the hand pose, run the placement again with dt 0 and the same t: its
-- smoothing, sound, light and outline state stand still, so only the hologram
-- unit poses change.
--
-- Other held-item effects sample hand or item nodes at the same moment and
-- get the same late placement (queue 14 September; static read in the
-- unattended session handover). Each placer only moves effects that already
-- exist; none creates, destroys, spawns impacts or advances timers:
-- - flamer stream: move the stream from the muzzle along the stock aim
--   rotation (the full update would queue impacts and lerp sound);
-- - chain lightning links: move the existing links (the full update picks new
--   targets with math.random);
-- - chain lightning and wind slash hand effects: the stock placement at dt 0
--   (it creates only when missing and compares times);
-- - riot shield windup loop: move it and set its length.
-- Not fixable here: one-shot bursts (shout, shield activation) spawn before
-- the hand pose and are not tracked afterwards.
local ScannerHolo = {}
local CLASS_NAME = "AuspexScanningEffects"

local function stock_placement(script, unit, t)
    script:update_unit_position(unit, 0, t)
end

ScannerHolo.PLACERS = {
    AuspexScanningEffects = stock_placement,
    ChainLightningAbilityHandEffects = stock_placement,
    ForceWeaponWindSlashActivationEffects = stock_placement,
    ChainLightningLinkEffects = function(script, unit, t)
        script:_update_fx(t)
    end,
    FlamerGasEffects = function(script)
        local effect_id = script._stream_effect_id
        if not effect_id then return end
        local pose = script._fx_extension:vfx_spawner_pose(script._fx_source_name)
        local direction = Quaternion.forward(script._first_person_component.rotation)
        World.move_particles(script._world, effect_id, Matrix4x4.translation(pose), Quaternion.look(direction))
    end,
    RiotShieldEffects = function(script)
        if script._looping_windup_effect_id then
            script:_update_windup_vfx_loop()
        end
    end,
}

function ScannerHolo.scripts(unit)
    local loadout = unit and ScriptUnit.has_extension(unit, "visual_loadout_system")
    local inventory = loadout and loadout._inventory_component
    local per_slot = loadout and loadout._wieldable_slot_scripts
    return inventory and per_slot and per_slot[inventory.wielded_slot]
end

function ScannerHolo.install(mod)
    local api = {placements = 0, failures = 0, test_zone = false}
    local logged_scan = false
    local logged_classes = {}

    function api.place(unit, t)
        local scripts = ScannerHolo.scripts(unit)
        if not scripts or not t then return 0 end
        local placed = 0
        for i = 1, #scripts do
            local script = scripts[i]
            -- A deleted script raises on any field other than these raw ones.
            local class_name = type(script) == "table" and not rawget(script, "__deleted") and script.__class_name
            local placer = class_name and ScannerHolo.PLACERS[class_name]
            if placer then
                local holo = class_name == CLASS_NAME and script._player_holo_unit
                local before = holo and Unit.alive(holo) and Unit.local_position(holo, 1)
                local ok, err = pcall(placer, script, unit, t)
                if ok and class_name ~= CLASS_NAME then
                    placed = placed + 1
                    api.placements = api.placements + 1
                    if not logged_classes[class_name] then
                        logged_classes[class_name] = true
                        mod:info("DARKTIDEVR_HELD_EFFECTS placed class=%s", class_name)
                    end
                elseif ok then
                    placed = placed + 1
                    api.placements = api.placements + 1
                    local scanning = script._is_screen_enabled == true
                    holo = script._player_holo_unit
                    if scanning and not logged_scan and holo and Unit.alive(holo) then
                        logged_scan = true
                        local after = Unit.local_position(holo, 1)
                        local item = script._item_unit_3p
                        local grip = item and Unit.alive(item) and Unit.world_position(item, 2)
                        mod:info("DARKTIDEVR_SCANNER_HOLO scan=start moved_m=%.3f holo_to_scanner_m=%.3f test_zone=%s",
                            before and Vector3.distance(before, after) or -1,
                            grip and Vector3.distance(after, grip) or -1, tostring(api.test_zone))
                    elseif not scanning then
                        logged_scan = false
                    end
                else
                    api.failures = api.failures + 1
                    if api.failures == 1 then
                        mod:info("DARKTIDEVR_SCANNER_HOLO fallback=%s class=%s", tostring(err):sub(1, 160), class_name)
                    end
                end
            end
        end
        return placed
    end

    -- Psykhanium check: the scan action puts the scanner away at once when
    -- no scanning zone is active. The test stands in for a zone there only,
    -- so holding the scan shows the hologram (the player marker; target
    -- spheres need real scannable objects).
    mod:hook_require("scripts/extension_systems/mission_objective_zone/mission_objective_zone_system",
        function(class)
            mod:hook(class, "any_active_scanning_zone", function(func, self, ...)
                if api.test_zone then return true end
                return func(self, ...)
            end)
        end)

    return api
end

return ScannerHolo
