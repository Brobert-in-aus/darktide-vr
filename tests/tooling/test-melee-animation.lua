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
-- A held block plays the authored guard pose on every melee weapon.
assert(stock("slot_primary", "block") and stock("slot_primary", "block_windup"))
assert(not stock(nil, nil))
-- THE PLAYER'S SWITCH (Nexus request, 19 September): "keep the hands/weapon
-- tracking the controllers rather than swinging".
local allowed = body.stock_melee_animation_allowed
local swings = {"sweep", "melee_explosive", "windup"}
-- Push is kept alongside block (user, 19 September). Both are read by other
-- people as well as the player: a shove that staggers, and a guard that says
-- you are blocking.
local kept = {"push", "block", "block_windup", "block_aiming", "block_unaim"}
for _, kind in ipairs(swings) do
  assert(allowed(kind, true), kind .. ' plays while the option is on')
  assert(not allowed(kind, false), kind .. ' is the animation being turned off')
  -- nil is ON. An option not yet registered, or a profile written before it
  -- existed, must not silently take everyone's melee animations away.
  assert(allowed(kind, nil), kind .. ' plays when the option has never been set')
end
for _, kind in ipairs(kept) do
  -- These stay whatever the switch says: information lost, not a swing the
  -- player asked to make themselves.
  assert(allowed(kind, true) and allowed(kind, false) and allowed(kind, nil),
    kind .. ' is exempt')
end
-- The exemption list and the swing list between them account for every kind
-- uses_stock_melee_animation claims, so a kind cannot be added to one without
-- a decision about the other.
for kind in pairs(body.KEPT_MELEE_ANIMATIONS) do
  local listed = false
  for _, k in ipairs(kept) do listed = listed or k == kind end
  assert(listed, 'KEPT_MELEE_ANIMATIONS has ' .. kind .. ' but the test does not')
end
-- The two questions are separate and both have to say yes. This one does not
-- decide whether the kind is a melee animation at all, so it says yes to
-- things that are not -- `uses_stock_melee_animation` is what refuses those,
-- and the caller asks both.
assert(allowed("shoot", true) and allowed(nil, true))
assert(not allowed("shoot", false), 'the option gates every non-block kind it is asked about')
assert(not stock("slot_secondary", "shoot"), 'and the kind gate still refuses a shot')

print("melee_animation_owner=pass allowed")
