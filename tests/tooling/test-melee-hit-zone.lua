local enemy, player, wall = {}, {}, {}
local shield, head, body = {unit=enemy,zone="shield"}, {unit=enemy,zone="head"},
    {unit=enemy,zone="torso"}
local blocking, attacker_position, shield_checks = true, {}, 0
package.loaded["scripts/utilities/attack/hit_zone"] = {
    get=function(_, actor) return actor.zone and {name=actor.zone} end}
package.loaded["scripts/settings/equipment/action_sweep_settings"] = {
    default_hit_zone_priority={shield=1,head=2,torso=3},
    hit_zone_priority_functions={shield=function(unit, position, priority)
        assert(unit == enemy and position == attacker_position)
        shield_checks = shield_checks + 1
        return blocking and priority or math.huge
    end}}
Actor = {unit=function(actor) return actor.unit end}
ALIVE = {[enemy]=true,[player]=true,[wall]=true}
local Resolver, Contacts = dofile(arg[1]), dofile(arg[2])
local generation = {}
local context = {attacker=player,attacker_position=attacker_position,action={},
    target_key=function(unit) return unit == enemy and generation end}
local batch = Contacts.new()
local function add(actor)
    local contact, reason = Resolver.resolve({actor=actor,
        position={x=10,y=0,z=1},normal={x=-1,y=0,z=0}}, context)
    if contact then Contacts.add(batch,contact) end
    return contact, reason
end
add(body); add(head); add(shield)
assert(#batch.ordered == 1 and batch.ordered[1].actor == shield)
blocking = false
Contacts.clear(batch)
add(shield); add(body); add(head)
assert(batch.ordered[1].actor == head and shield_checks == 2)
context.action.hit_zone_priority = {shield=1,head=3,torso=2}
Contacts.clear(batch)
add(head); add(body)
assert(batch.ordered[1].actor == body, "weapon-specific priority was ignored")
local contact, reason = add({unit=wall})
assert(not contact and reason == "unresolved_hit_zone")
contact, reason = add({unit=wall,zone="head"})
assert(not contact and reason == "unregistered_target")
assert(not add({unit=player,zone="head"}))
ALIVE[enemy] = false
assert(not add(head))
assert(shield_checks == 2)
print("stock dynamic shield/hit-zone priority, source position and unresolved scenery passed")
