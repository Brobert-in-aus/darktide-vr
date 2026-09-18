-- Which units are drawing arms, named.
--
-- "I have two pairs of hands, both merging at the wrists into my hands", and
-- then "I have two arms even when the mirror character is disabled". Four
-- theories were offered for that and all four were wrong: the mirror's copy,
-- the body proxy's gloves, the source avatar's arm slot left unhidden, and the
-- hand rig handing over without anyone taking the hiding with it. Each was
-- reasoned from the code and none of them was checked against the world.
--
-- So this does not reason. It walks every unit that could be drawing an arm,
-- asks whether it has a wrist, asks where that wrist is, and prints the list.
-- Two entries with a right wrist in the same place are the two arms, and the
-- entry names which one is the stranger.
--
-- Off unless `darktidevr_arm_census.flag` says enabled, and it reports once
-- per wielded-slot change rather than per frame: the question is what exists,
-- not what it is doing.
local Census = {}
Census.FLAG = "./../mods/darktidevr/darktidevr_arm_census.flag"
-- The nodes that say "this is an arm". A unit with a right wrist is drawing a
-- hand somewhere, whatever it calls itself.
-- The right wrist is what positions are compared on: one wrist per unit is
-- enough to pair them, and using both would report every unit twice.
Census.WRIST_NODE = "j_righthand"
-- Re-report the same wielded slot after this long. The first report for the
-- slot the player spawns holding is taken the moment the input path first runs
-- with the flag on, which can be before the proxy or the mirror have spawned
-- anything -- and the slot key was only ever set, so that one empty report was
-- the only one that slot ever got (review, 18 September).
Census.REARM_SECONDS = 30
Census.ARM_NODES = {"j_rightarm", "j_leftarm", "j_rightforearm", "j_leftforearm"}

-- Two wrists close enough to be the pair the player sees as one. Pure.
Census.SAME_WRIST_M = 0.08
function Census.same_wrist(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
    local squared = dx * dx + dy * dy + dz * dz
    if squared ~= squared then return false end
    return squared <= Census.SAME_WRIST_M * Census.SAME_WRIST_M
end

-- The duplicates in a list of {label, wrist} entries: every pair whose wrists
-- coincide, as {a_label, b_label, separation}. Pure, so the rule that decides
-- "these two are the same hand" is testable without a world.
function Census.duplicates(entries)
    local found = {}
    for i = 1, #entries do
        for j = i + 1, #entries do
            local a, b = entries[i], entries[j]
            if a.wrist and b.wrist and Census.same_wrist(a.wrist, b.wrist) then
                local dx = a.wrist[1] - b.wrist[1]
                local dy = a.wrist[2] - b.wrist[2]
                local dz = a.wrist[3] - b.wrist[3]
                found[#found + 1] = {a = a.label, b = b.label,
                    separation = math.sqrt(dx * dx + dy * dy + dz * dz)}
            end
        end
    end
    return found
end

function Census.install(mod, presentation)
    local api = {}
    local poll, enabled, last_key, last_t = 0, false, nil, nil
    local function flag()
        poll = poll - 1
        if poll > 0 then return enabled end
        poll = 300
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Census.FLAG, "r")
        if not file then enabled = false; return false end
        local value = file:read(32) or ""
        file:close()
        enabled = value:match("^%s*enabled%s*$") ~= nil
        return enabled
    end

    local function array(v) return v and {Vector3.x(v), Vector3.y(v), Vector3.z(v)} or nil end

    local function node_names(unit)
        local wrist, arms = nil, 0
        if Unit.has_node(unit, Census.WRIST_NODE) then
            wrist = array(Unit.world_position(unit, Unit.node(unit, Census.WRIST_NODE)))
        end
        for _, name in ipairs(Census.ARM_NODES) do
            if Unit.has_node(unit, name) then arms = arms + 1 end
        end
        return wrist, arms
    end

    -- Everything that could be drawing an arm, whatever spawned it. Labelled by
    -- where it came from, because "there are two" is half an answer and the
    -- other half is which two.
    local function candidates(player_unit)
        local list = {}
        local function add(label, unit)
            if not unit or not Unit.alive(unit) then return end
            for _, entry in ipairs(list) do if entry.unit == unit then return end end
            local ok, wrist, arms = pcall(node_names, unit)
            if not ok then return end
            local meshes = 0
            pcall(function() meshes = Unit.num_meshes(unit) end)
            -- No visibility column. `Unit.is_visible` appears nowhere in the
            -- stock source -- only the setters do -- so it would have been
            -- "unknown" on every row: a constant that looks like data, which
            -- is the trap this whole module exists to avoid. Mesh count and a
            -- wrist position are things that can actually be read.
            list[#list + 1] = {label = label, unit = unit, wrist = wrist,
                arms = arms or 0, meshes = meshes}
        end

        add("player_3p", player_unit)
        local first_person = ScriptUnit.has_extension(player_unit, "first_person_system")
        add("first_person", first_person and first_person:first_person_unit())
        -- The equipment slots hanging off the player, which is where the arm
        -- and glove meshes actually live.
        local loadout = ScriptUnit.has_extension(player_unit, "visual_loadout_system")
        for slot_name, slot in pairs(loadout and loadout._equipment or {}) do
            add("slot_3p/" .. tostring(slot_name), slot.unit_3p)
            add("slot_1p/" .. tostring(slot_name), slot.unit_1p)
        end
        -- The mod's own drawn bodies, which each module now names for itself.
        -- Reached through `drawn_units` rather than guessed at: the first cut
        -- asked `hand_pose(side).unit` (that returns a position and a
        -- rotation, so it read nil or raised and took the whole report with
        -- it) and `body_mirror.drawn_unit` (which did not exist, so the prime
        -- suspect was silently absent). Both are review findings.
        for _, module in ipairs({presentation.body_proxy, presentation.body_mirror}) do
            if module and module.drawn_units then
                local ok, drawn = pcall(module.drawn_units)
                if ok then
                    for _, entry in ipairs(drawn or {}) do add(entry.label, entry.unit) end
                end
            end
        end
        return list
    end

    -- Reported on a change of what is wielded, which is when the set of drawn
    -- units changes, rather than every frame.
    function api.report(player_unit)
        if not flag() or not player_unit or not Unit.alive(player_unit) then return end
        local unit_data = ScriptUnit.has_extension(player_unit, "unit_data_system")
        local inventory = unit_data and unit_data:read_component("inventory")
        local key = tostring(inventory and inventory.wielded_slot or "none")
        local now = Managers and Managers.time and Managers.time.has_timer and
            Managers.time:has_timer("main") and Managers.time:time("main") or nil
        local stale = last_t == nil or now == nil or now >= last_t + Census.REARM_SECONDS
        if key == last_key and not stale then return end
        last_key, last_t = key, now
        local ok, list = pcall(candidates, player_unit)
        if not ok then
            mod:info("DARKTIDEVR_ARM_CENSUS unavailable=%s", tostring(list):sub(1, 120))
            return
        end
        local with_arms = {}
        for _, entry in ipairs(list) do
            if entry.arms > 0 or entry.wrist then
                with_arms[#with_arms + 1] = entry
                mod:info("DARKTIDEVR_ARM_CENSUS wielded=%s source=%s arms=%d meshes=%d wrist=%s",
                    key, entry.label, entry.arms, entry.meshes,
                    entry.wrist and string.format("%.3f,%.3f,%.3f",
                        entry.wrist[1], entry.wrist[2], entry.wrist[3]) or "none")
            end
        end
        for _, pair in ipairs(Census.duplicates(with_arms)) do
            mod:info("DARKTIDEVR_ARM_CENSUS duplicate wielded=%s a=%s b=%s separation_m=%.4f",
                key, pair.a, pair.b, pair.separation)
        end
        mod:info("DARKTIDEVR_ARM_CENSUS total wielded=%s arm_units=%d of=%d",
            key, #with_arms, #list)
    end
    return api
end

return Census
