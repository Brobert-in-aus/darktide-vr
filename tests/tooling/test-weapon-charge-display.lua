-- Weapon charge bars at the weapon: which of the element's passes are taken,
-- and when a captured element has gone stale.
local Charge = dofile(assert(arg[1]))
local Feedback = dofile(assert(arg[2]))

-- The stock cooldown-charges template names its bars charge_bar_N; its other
-- passes (background, text) must not be dragged into the world with them.
assert(Charge.accept('charge_bar_1') and Charge.accept('charge_bar_8'))
assert(Charge.accept('charge_mask_left'), 'any charge pass the template adds')
assert(not Charge.accept('background') and not Charge.accept('text'))
assert(not Charge.accept(nil) and not Charge.accept(7))
-- The crosshair's own filter happens to match charge_bar_N too, since both
-- start "charge_". Passing an explicit filter is still what keeps the two
-- elements apart: each says which of *its* passes it wants, rather than
-- inheriting a rule written for the other.
assert(Feedback.accept_crosshair('charge_bar_1'), 'the prefixes overlap')
assert(Feedback.accept_crosshair('hit_top_left') and not Charge.accept('hit_top_left'),
    'the weapon counter has no hit feedback to draw')

-- The same rebuild the crosshair uses, with these ids.
local widget = {content = {charge = 'forcesword_bar'}, style = {
    charge_bar_1 = {size = {400, 400}, offset = {12, -4, 2}},
    background = {size = {40, 40}, offset = {0, 0, 1}}}}
local bar = Feedback.quad({style_id = 'charge_bar_1', value_id = 'charge'}, widget, Charge.accept)
assert(bar and bar.material == 'forcesword_bar' and bar.w == 400)
assert(Feedback.quad({style_id = 'background', value_id = 'charge'}, widget, Charge.accept) == nil)

-- A bar 400 units long is about 10 cm in the world, so it reads beside a gun
-- rather than swamping it.
local metres = 400 * Charge.PIXEL_METRES
assert(metres > 0.08 and metres < 0.13, 'about 10 cm: ' .. tostring(metres))

-- Staleness: the element is captured in its own update, and the draw happens
-- later in the frame. An element that stopped updating (hidden, destroyed,
-- another HUD) must not keep its bars on the weapon.
assert(Charge.fresh(100, 100))
assert(Charge.fresh(100, 100.05))
assert(not Charge.fresh(100, 100.2), 'a tenth of a second is the limit')
assert(not Charge.fresh(100, 99), 'time running backwards is not fresh')
assert(not Charge.fresh(nil, 100) and not Charge.fresh(100, nil))
assert(Charge.fresh(100, 100.5, 1), "the limit is the caller's")

print('weapon_charge_display=pass accept rebuild scale freshness')
