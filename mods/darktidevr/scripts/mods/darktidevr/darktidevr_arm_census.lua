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
Census.WRIST_NODES = {"j_righthand", "j_lefthand"}
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
    local poll, enabled, last_key = 0, false, nil
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
        for _, name in ipairs(Census.WRIST_NODES) do
            if Unit.has_node(unit, name) then
                if name == "j_righthand" then
                    wrist = array(Unit.world_position(unit, Unit.node(unit, name)))
                end
            end
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
            local visible = "unknown"
            pcall(function() visible = tostring(Unit.is_visible(unit)) end)
            list[#list + 1] = {label = label, unit = unit, wrist = wrist,
                arms = arms or 0, meshes = meshes, visible = visible}
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
        -- The mod's own drawn bodies.
        local proxy = presentation.body_proxy
        if proxy then
            for _, side in ipairs({"left", "right"}) do
                local pose = proxy.hand_pose and proxy.hand_pose(side)
                if pose and pose.unit then add("proxy_glove/" .. side, pose.unit) end
            end
        end
        if presentation.body_mirror and presentation.body_mirror.drawn_unit then
            add("mirror_copy", presentation.body_mirror.drawn_unit())
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
        if key == last_key then return end
        last_key = key
        local ok, list = pcall(candidates, player_unit)
        if not ok then
            mod:info("DARKTIDEVR_ARM_CENSUS unavailable=%s", tostring(list):sub(1, 120))
            return
        end
        local with_arms = {}
        for _, entry in ipairs(list) do
            if entry.arms > 0 or entry.wrist then
                with_arms[#with_arms + 1] = entry
                mod:info("DARKTIDEVR_ARM_CENSUS wielded=%s source=%s arms=%d meshes=%d visible=%s wrist=%s",
                    key, entry.label, entry.arms, entry.meshes, entry.visible,
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
