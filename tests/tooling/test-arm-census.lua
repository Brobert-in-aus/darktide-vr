-- The rule that decides "these two are the same hand". The census itself needs
-- a world; this does not, and this is the part that can be wrong quietly.
local Census = dofile(assert(arg[1]))
local function near(a, b, m) assert(math.abs(a - b) < 1e-9, (m or 'mismatch') .. ': ' .. tostring(a)) end

-- Two wrists within SAME_WRIST_M are the pair the player sees as one.
assert(Census.same_wrist({0, 0, 0}, {0.05, 0, 0}), 'five centimetres apart is one hand')
assert(not Census.same_wrist({0, 0, 0}, {0.2, 0, 0}), 'twenty is two')
-- The threshold is a radius, not a per-axis box: a diagonal must not sneak in.
local edge = Census.SAME_WRIST_M / math.sqrt(3) + 1e-6
assert(not Census.same_wrist({0, 0, 0}, {edge * 1.2, edge * 1.2, edge * 1.2}),
  'a diagonal beyond the radius is not the same hand')
assert(not Census.same_wrist(nil, {0, 0, 0}) and not Census.same_wrist({0, 0, 0}, nil))
assert(not Census.same_wrist({0 / 0, 0, 0}, {0, 0, 0}), 'a nan wrist matches nothing')

-- The pairing. Two arm sources at the same wrist is the whole report.
local pairs_found = Census.duplicates({
  {label = 'player_3p', wrist = {1, 2, 1.2}},
  {label = 'first_person', wrist = {1.01, 2, 1.2}},
  {label = 'slot_3p/slot_secondary', wrist = {5, 5, 0}},
})
assert(#pairs_found == 1, 'exactly one duplicate, got ' .. #pairs_found)
assert(pairs_found[1].a == 'player_3p' and pairs_found[1].b == 'first_person',
  'and it names both sides: ' .. pairs_found[1].a .. '/' .. pairs_found[1].b)
near(pairs_found[1].separation, 0.01, 'the separation is reported')

-- Three at the same place are three pairs, not one: "there are two" was the
-- half-answer that made this necessary, so the report must not collapse them.
assert(#Census.duplicates({
  {label = 'a', wrist = {0, 0, 0}}, {label = 'b', wrist = {0, 0, 0}},
  {label = 'c', wrist = {0, 0, 0}}}) == 3, 'every coinciding pair is named')

-- A source with no wrist is not a duplicate of anything, including another
-- source with no wrist -- otherwise every armless unit pairs with every other.
assert(#Census.duplicates({
  {label = 'a'}, {label = 'b'}, {label = 'c', wrist = {0, 0, 0}}}) == 0,
  'no wrist, no pairing')
assert(#Census.duplicates({}) == 0 and #Census.duplicates({{label = 'only', wrist = {0, 0, 0}}}) == 0)

-- The re-arm exists because the first report for a slot can be taken before
-- the bodies have spawned, and the throttle only ever set its key -- so that
-- one empty report was all that slot ever got.
assert(Census.REARM_SECONDS and Census.REARM_SECONDS > 0 and Census.REARM_SECONDS <= 120,
  'the census re-arms within a session, got ' .. tostring(Census.REARM_SECONDS))
-- One wrist per unit. Comparing both would report every unit against itself.
assert(Census.WRIST_NODE == 'j_righthand', 'one named wrist')

print('arm_census=pass same_wrist radius duplicates unpaired rearm')
