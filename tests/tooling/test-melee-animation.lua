require = function() return {} end
local body = assert(loadfile(arg[1]))()
local stock = body.uses_stock_melee_animation
assert(stock("slot_primary", "windup"))
assert(stock("slot_primary", "sweep"))
assert(stock("slot_primary", "push"))
assert(stock("slot_secondary", "sweep"), "gun bash retained tracked wrists")
assert(stock("slot_secondary", "melee_explosive"), "gauntlet melee retained IK")
assert(not stock("slot_secondary", "windup"), "ranged charge lost tracking")
local staff_start = { allowed_chain_actions = {
    special_action_release = { action_name = "stab" } } }
assert(stock("slot_secondary", "windup", staff_start,
    { stab = { kind = "sweep" } }), "staff stab windup retained tracking")
assert(not stock("slot_secondary", "windup", staff_start,
    { stab = { kind = "spawn_projectile" } }), "projectile charge lost tracking")
assert(not stock("slot_secondary", "shoot_hit_scan"))
assert(not stock("slot_primary", "block"))
assert(not stock(nil, nil))
print("melee_animation_owner=pass")
