-- Weapon parts the stock animation parks inside the character's own hand.
--
-- Some third-person weapons keep their reload props (loose rounds, clips) on
-- the gun at the grip outside a reload, where the stock wrist and sleeve
-- cover them. With tracked hands the avatar's arms are hidden and only a
-- glove is drawn, so the props show: the galvanic rifle's round column beside
-- the right glove (worn, 14 September), gone during reloads, when the
-- animation moves the rounds into the magazine.
--
-- While the avatar's arms are hidden, the listed meshes of the wielded
-- third-person attachment are hidden except during the listed reload actions.
-- Identified by elimination in eye renders
-- (artifacts/unattended/stray-bullet-20260915).
local Parked = {}

-- Attachment unit name -> inclusive mesh index ranges.
Parked.MESHES = {
    -- 27-58 and 63-66: the round column (14 September). 23-26: the U-shaped
    -- clip by the drum; 59-62: a cartridge case above the grip (worn, 15
    -- September evening; isolated in stray-bullet-20260915/parts1).
    ["content/weapons/player/ranged/galvanic_rifle/attachments/receiver_01/receiver_01"] = {{23, 26}, {27, 58}, {59, 62}, {63, 66}},
}
Parked.SHOWN_DURING = {reload_state = true, reload_shotgun = true}

-- The mesh indices to hide on an attachment, or nil. Pure.
function Parked.hidden_meshes(unit_name, action_kind, arms_hidden, mesh_count)
    local ranges = arms_hidden and Parked.MESHES[unit_name]
    if not ranges or Parked.SHOWN_DURING[action_kind] then return nil end
    local meshes = {}
    for _, range in ipairs(ranges) do
        for index = range[1], math.min(range[2], mesh_count or range[2]) do meshes[#meshes + 1] = index end
    end
    return #meshes > 0 and meshes or nil
end

function Parked.install(mod, presentation)
    local api = {}
    local hidden = {} -- unit -> list of mesh indices this module hid
    local logged = {}
    local failures = 0
    local function show(unit, indices)
        if Unit.alive(unit) then
            for _, index in ipairs(indices) do Unit.set_mesh_visibility(unit, index, true) end
        end
    end
    local function update(player_unit)
        local proxy = presentation.body_proxy
        local arms_hidden = proxy and proxy.hides_source_slot and proxy.hides_source_slot("slot_body_arms") or false
        local unit_data = player_unit and ScriptUnit.has_extension(player_unit, "unit_data_system")
        local inventory = unit_data and unit_data:read_component("inventory")
        local loadout = player_unit and ScriptUnit.has_extension(player_unit, "visual_loadout_system")
        local slot = inventory and loadout and loadout._equipment and loadout._equipment[inventory.wielded_slot]
        local weapon = player_unit and ScriptUnit.has_extension(player_unit, "weapon_system")
        local action = weapon and weapon:running_action_settings()
        local wanted = {}
        local attachments = slot and slot.unit_3p and slot.attachments_by_unit_3p and slot.attachments_by_unit_3p[slot.unit_3p]
        for _, attachment in ipairs(attachments or {}) do
            if Unit.alive(attachment) then
                local meshes = Parked.hidden_meshes(Unit.get_data(attachment, "unit_name"), action and action.kind,
                    arms_hidden, Unit.num_meshes(attachment))
                if meshes then wanted[attachment] = meshes end
            end
        end
        for unit, indices in pairs(hidden) do
            if not wanted[unit] then show(unit, indices); hidden[unit] = nil end
        end
        for unit, indices in pairs(wanted) do
            -- Every frame: the game's own visibility updates can show them again.
            for _, index in ipairs(indices) do Unit.set_mesh_visibility(unit, index, false) end
            if not hidden[unit] and not logged[unit] then
                logged[unit] = true
                mod:info("DARKTIDEVR_WEAPON_PARTS parked_hidden unit=%s meshes=%d", tostring(Unit.get_data(unit, "unit_name")), #indices)
            end
            hidden[unit] = indices
        end
    end
    function api.update(player_unit)
        local ok, message = pcall(update, player_unit)
        if not ok then
            failures = failures + 1
            for unit, indices in pairs(hidden) do pcall(show, unit, indices) end
            hidden = {}
            if failures == 1 then mod:info("DARKTIDEVR_WEAPON_PARTS failed=%s", tostring(message):sub(1, 160)) end
        end
    end
    return api
end

return Parked
