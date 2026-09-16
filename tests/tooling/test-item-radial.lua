-- Item radial: which sector the stick picks, where the labels sit, and that a
-- tap with a resting thumb still falls through to the stock cycle.
local Radial = dofile(assert(arg[1]))

assert(#Radial.OPTIONS == 3, 'carried item, stim, device')
local by_id = {}
for i, option in ipairs(Radial.OPTIONS) do by_id[option.id] = i end
assert(by_id.pocketable and by_id.stim and by_id.device)

-- Straight up is the middle of the first sector, then clockwise.
assert(Radial.select(0, 1) == 1, 'up')
assert(Radial.select(0.95, -0.3) == 2, 'down and right')
assert(Radial.select(-0.95, -0.3) == 3, 'down and left')
-- The sector boundaries: a third of a turn each, so 60 degrees either side of
-- up still picks up.
assert(Radial.select(math.sin(math.rad(55)), math.cos(math.rad(55))) == 1)
assert(Radial.select(math.sin(math.rad(65)), math.cos(math.rad(65))) == 2)

-- A resting thumb picks nothing, so the control keeps its stock behaviour.
assert(Radial.select(0, 0) == nil)
assert(Radial.select(0.3, 0.3) == nil, 'inside the deadzone')
assert(Radial.select(0 / 0, 1) == nil and Radial.select(0, nil) == nil)

-- Label placement: the first straight up, and all of them on the circle.
local x, y = Radial.label_offset(1, 3, 0.1)
assert(math.abs(x) < 1e-9 and math.abs(y - 0.1) < 1e-9, 'first is up')
for i = 1, 3 do
    local lx, ly = Radial.label_offset(i, 3, 0.1)
    assert(math.abs(math.sqrt(lx * lx + ly * ly) - 0.1) < 1e-9, 'on the circle')
end
assert(Radial.label_offset(0, 3, 0.1) == nil and Radial.label_offset(4, 3, 0.1) == nil)

-- Holding opens it and keeps the last pick while the thumb returns to centre,
-- so letting go of the stick before the button does not lose the choice.
local state, deliver = Radial.step(nil, true, nil)
assert(state.open and state.index == nil and deliver == nil)
state, deliver = Radial.step(state, true, 2)
assert(state.open and state.index == 2 and deliver == nil)
state, deliver = Radial.step(state, true, nil)
assert(state.index == 2, 'a centred stick keeps the pick')

-- Releasing delivers that option once.
state, deliver = Radial.step(state, false, nil)
assert(deliver == Radial.OPTIONS[2].mask and state.open == false)
-- And only once.
state, deliver = Radial.step(state, false, nil)
assert(deliver == nil)

-- Released without ever picking: nothing delivered, so the stock cycle runs.
local tapped = Radial.step(nil, true, nil)
local after, tap_deliver = Radial.step(tapped, false, nil)
assert(tap_deliver == nil and after.open == false, 'a tap falls through to stock')

print('item_radial=pass select labels hold_release tap_falls_through')
