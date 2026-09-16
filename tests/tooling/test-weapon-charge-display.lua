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

-- The charge itself lives in the style's material_values, not in the pass
-- geometry, so those have to be replayed onto a material instance or the bar
-- draws at the material's authored default for ever (review, 16 September).
Vector2 = function(x, y) return {'v2', x, y} end
Vector3 = function(x, y, z) return {'v3', x, y, z} end
Quaternion = {from_elements = function(x, y, z, w) return {'v4', x, y, z, w} end}
local set = {}
local Material = {
    set_scalar = function(m, k, v) set[#set + 1] = {'scalar', m, k, v} end,
    set_vector2 = function(m, k, v) set[#set + 1] = {'vector2', m, k, v} end,
    set_vector3 = function(m, k, v) set[#set + 1] = {'vector3', m, k, v} end,
    set_vector4 = function(m, k, v) set[#set + 1] = {'vector4', m, k, v} end,
    set_texture = function(m, k, v) set[#set + 1] = {'texture', m, k, v} end,
}
-- The shapes the stock templates use: a bare number, and tables of 1 to 4.
local applied = Charge.apply_material_values(Material, 'handle', {
    progress = 0.25, amount = {0.75}, arc_top_bottom = {0.1, 0.9},
    fillcolor = {1, 0.5, 0}, glow = {1, 2, 3, 4}, texture = 'some/texture',
    cleared = ''})
assert(applied == 7, 'every value applied: ' .. tostring(applied))
local kinds = {}
for _, entry in ipairs(set) do kinds[entry[1]] = (kinds[entry[1]] or 0) + 1 end
assert(kinds.scalar == 2, 'a bare number and a one-entry table are both scalars')
assert(kinds.vector2 == 1 and kinds.vector3 == 1 and kinds.vector4 == 1)
assert(kinds.texture == 2, 'a name and an empty string, which clears it')
for _, entry in ipairs(set) do
    if entry[3] == 'cleared' then assert(entry[4] == nil, 'an empty string clears the texture') end
    if entry[3] == 'progress' then assert(entry[4] == 0.25) end
end
-- Nothing usable is not an error; it just applies nothing.
assert(Charge.apply_material_values(Material, 'handle', nil) == 0)
assert(Charge.apply_material_values(nil, 'handle', {a = 1}) == 0)
assert(Charge.apply_material_values(Material, nil, {a = 1}) == 0)
assert(Charge.apply_material_values(Material, 'handle', {ignored = true}) == 0,
    'a value of a kind the engine has no setter for')

print('weapon_charge_display=pass accept rebuild scale freshness material_values')
