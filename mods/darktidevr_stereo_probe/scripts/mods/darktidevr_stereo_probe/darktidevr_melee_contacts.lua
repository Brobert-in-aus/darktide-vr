-- Offline contact collection for one simulation update, before cooldowns or
-- damage. The physics adapter supplies validated, unobstructed contacts and
-- stock action/shield priorities. This module performs no physics or damage.
local Contacts = {}
local function finite(value)
    return type(value) == "number" and value == value and
        value > -math.huge and value < math.huge
end
local function vector(value)
    return type(value) == "table" and finite(value.x) and
        finite(value.y) and finite(value.z)
end

function Contacts.new()
    return { by_target = {}, ordered = {} }
end

function Contacts.add(batch, contact)
    if type(contact) ~= "table" or contact.target == nil or
            (type(contact.target) == "number" and not finite(contact.target)) or
            contact.actor == nil or type(contact.priority) ~= "number" or
            contact.priority ~= contact.priority or
            contact.priority == -math.huge or not vector(contact.position) or
            not vector(contact.normal) then
        return false, "invalid_contact"
    end
    local index = batch.by_target[contact.target]
    if index and contact.priority >= batch.ordered[index].priority then
        return false, "existing_priority"
    end
    -- Query result tables/vectors may be reused by the next physics substep.
    -- Copy scalars now. Actor liveness must still be checked before consumption.
    local snapshot = {
        target = contact.target, actor = contact.actor,
        hit_zone = contact.hit_zone, priority = contact.priority,
        position = {x=contact.position.x, y=contact.position.y, z=contact.position.z},
        normal = {x=contact.normal.x, y=contact.normal.y, z=contact.normal.z},
    }
    if not index then
        index = #batch.ordered + 1
        batch.by_target[contact.target] = index
    end
    batch.ordered[index] = snapshot
    return true
end

function Contacts.clear(batch)
    -- Clearing query results must not clear the separate per-target ledger.
    for key in pairs(batch.by_target) do batch.by_target[key] = nil end
    for index = #batch.ordered, 1, -1 do batch.ordered[index] = nil end
end

return Contacts
