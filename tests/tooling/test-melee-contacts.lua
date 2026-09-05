local Contacts, Policy = dofile(arg[1]), dofile(arg[2])
local batch = Contacts.new()
local source = {target={}, actor={}, priority=3, hit_zone="arm",
    position={x=1,y=2,z=3}, normal={x=0,y=1,z=0}}
assert(Contacts.add(batch, source))
source.position.x = 99
source.normal.y = -1
assert(batch.ordered[1].position.x == 1 and batch.ordered[1].normal.y == 1)
local shield_actor = {}
source.actor, source.priority, source.hit_zone = shield_actor, 1, "shield"
assert(Contacts.add(batch, source))
assert(#batch.ordered == 1 and batch.ordered[1].actor == shield_actor)
source.actor, source.priority = {}, 3
assert(not Contacts.add(batch, source))
source.priority = 1
assert(not Contacts.add(batch, source)) -- Equal priority preserves first result.
assert(batch.ordered[1].actor == shield_actor)
source.position.x = 0/0
source.priority = 0
assert(not Contacts.add(batch, source))
source.position.x = 1
source.target = 0/0
assert(not Contacts.add(batch, source))
Contacts.clear(batch)

local ledger, targets = Policy.new(0, 1), {}
for i=1,100 do targets[i] = {} end
local function collect_and_accept(now)
    Contacts.clear(batch)
    for substep=1,4 do
        for i=1,100 do
            source.target = targets[i]
            source.priority = 3
            Contacts.add(batch, source)
            source.priority = 1
            Contacts.add(batch, source)
        end
    end
    assert(#batch.ordered == 100) -- No inherited 20-result/finite cleave cap.
    local accepted = 0
    for _, contact in ipairs(batch.ordered) do
        if Policy.accept_contact(ledger, contact.target, now, "light", .5) then
            accepted = accepted + 1
        end
    end
    return accepted
end
assert(collect_and_accept(0) == 100)
assert(collect_and_accept(.1) == 0) -- Fresh batch never clears target cooldowns.
assert(collect_and_accept(.5) == 100) -- Stationary continuous contact repeats.
print("melee_contacts=pass")
