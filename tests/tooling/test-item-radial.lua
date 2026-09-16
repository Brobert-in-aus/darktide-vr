-- Item radial: which sector the stick picks, where the labels sit, and the
-- state machine driven by the bindings' claim edges.
local Radial = dofile(assert(arg[1]))

assert(#Radial.OPTIONS == 3, 'carried item, stim, device')
local by_id = {}
for i, option in ipairs(Radial.OPTIONS) do by_id[option.id] = i end
assert(by_id.pocketable and by_id.stim and by_id.device)
assert(Radial.CONTROL_ACTIONS[1] == 'pocketable_device', 'the combined action first')

-- Straight up is the middle of the first sector, then clockwise.
assert(Radial.select(0, 1) == 1, 'up')
assert(Radial.select(0.95, -0.3) == 2, 'down and right')
assert(Radial.select(-0.95, -0.3) == 3, 'down and left')
assert(Radial.select(math.sin(math.rad(55)), math.cos(math.rad(55))) == 1)
assert(Radial.select(math.sin(math.rad(65)), math.cos(math.rad(65))) == 2)
assert(Radial.select(0, 0) == nil and Radial.select(0.3, 0.3) == nil, 'inside the deadzone')
assert(Radial.select(0 / 0, 1) == nil and Radial.select(0, nil) == nil)

-- Labels: the first straight up, all on the circle.
local x, y = Radial.label_offset(1, 3, 0.1)
assert(math.abs(x) < 1e-9 and math.abs(y - 0.1) < 1e-9, 'first is up')
for i = 1, 3 do
    local lx, ly = Radial.label_offset(i, 3, 0.1)
    assert(math.abs(math.sqrt(lx * lx + ly * ly) - 0.1) < 1e-9, 'on the circle')
end
assert(Radial.label_offset(0, 3, 0.1) == nil and Radial.label_offset(4, 3, 0.1) == nil)

-- The claim's edges, in the shape the bindings report them.
local PRESSED, HELD, RELEASED, CANCELLED = {pressed = true, held = true}, {held = true},
    {released = true}, {cancelled = true}

-- A fresh press the bindings accepted opens it; a held stick at that moment
-- picks nothing until the stick has been neutral once (mid snap-turn tap).
local state, deliver = Radial.step(nil, PRESSED, 1, 0)
assert(state.open and state.index == nil and deliver == nil)
state = Radial.step(state, HELD, 1, 0)
assert(state.index == nil, 'a stick already hard over does not pick')
state = Radial.step(state, HELD, 0, 0)
assert(state.neutral_seen and state.index == nil, 'neutral seen, nothing picked yet')
state = Radial.step(state, HELD, 0.95, -0.3)
assert(state.index == 2, 'now a flick picks')
state = Radial.step(state, HELD, 0, 0)
assert(state.index == 2, 'and returning the stick to centre keeps the pick')
-- Release delivers that option, once.
state, deliver = Radial.step(state, RELEASED, 0, 0)
assert(deliver == Radial.OPTIONS[2].mask and state.open == false)
state, deliver = Radial.step(state, {}, 0, 0)
assert(deliver == nil and state.open == false)

-- Released with nothing picked: the stock cycle, since the claim swallowed the
-- press that would have cycled. Turning the option on must not take a plain
-- tap's behaviour away.
local tap = Radial.step(nil, PRESSED, 0, 0)
local after, tap_deliver = Radial.step(tap, RELEASED, 0, 0)
assert(tap_deliver == Radial.CYCLE_MASK and after.open == false, 'a tap cycles as stock does')
assert(Radial.CYCLE_MASK == 786432, 'the carried-items control own action')

-- A cancelled claim (another claim took the slot, input went away, the level
-- changed) closes without delivering: no wield out of nowhere later.
local picked = Radial.step(Radial.step(Radial.step(nil, PRESSED, 0, 0), HELD, 0, 0), HELD, 0, 1)
assert(picked.index == 1)
local cancelled, cancel_deliver = Radial.step(picked, CANCELLED, 0, 0)
assert(cancel_deliver == nil and cancelled.open == false)
local later, later_deliver = Radial.step(cancelled, RELEASED, 0, 0)
assert(later_deliver == nil, 'a release after a cancel delivers nothing')
-- And an unopened radial reports nothing on a stray release or held frame.
assert(select(2, Radial.step(nil, RELEASED, 0, 1)) == nil)
assert(Radial.step(nil, HELD, 0, 1).open == false, 'held without a press stays closed')
assert(Radial.step(nil, nil, 0, 0).open == false)

-- The Device sector delivers its own mask, which the first attempt could not.
local dev = Radial.step(Radial.step(Radial.step(nil, PRESSED, 0, 0), HELD, 0, 0), HELD, -0.95, -0.3)
assert(dev.index == by_id.device)
assert(select(2, Radial.step(dev, RELEASED, 0, 0)) == 262144, 'device delivers wield_5')

print('item_radial=pass select labels claim_edges neutral_rearm cancel device tap_cycles')
