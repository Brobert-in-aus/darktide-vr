-- The one claim slot, driven in the order darktidevr.lua's input block uses:
-- two-hand support, then the holsters, then reach, then the item radial, then
-- the bindings' sample. Two worn faults came out of that order and neither
-- module's own test could see them: a flick inside the radial also fired the
-- stick's own binding (17 September), and reaching for a door was dead for as
-- long as a gun was wielded, because both yielded the slot to two-hand
-- support's standing offer.
local Bindings = dofile(assert(arg[1]))
local Radial = dofile(assert(arg[2]))

-- The shared rule. Two-hand support offers a request on every frame a gun
-- frame is valid, whether or not the hand is anywhere near the foregrip.
local idle_two_hand = {control = 'left_grip', owner = {}, action = 'unbound',
    acquire = false, approach = false, retain = true}
local reaching_two_hand = {control = 'left_grip', owner = {}, action = 'unbound',
    acquire = false, approach = true, retain = true}
local taking_two_hand = {control = 'left_grip', owner = {}, action = 'alternate',
    acquire = true, approach = true, retain = true}
assert(not Radial.yields(idle_two_hand, false), 'an idle offer must not take the slot')
assert(Radial.yields(reaching_two_hand, false), 'a hand on its way takes it')
assert(Radial.yields(taking_two_hand, false), 'a hand at the foregrip takes it')
assert(Radial.yields(idle_two_hand, true), 'a grip already held is never replaced')
assert(not Radial.yields(nil, false) and Radial.yields(true, false))

-- The bindings, driven directly. The carried-items control is Y (bit 16); the
-- right stick's up channel is bit 2048 and carries quick_wield (mask 16) by
-- default, which is the weapon switch the user saw.
local mapper = Bindings.install({get = function() end})
local owner = {}
local function radial_request()
    return {control = 'y', owner = owner, action = 'unbound', acquire = true,
        retain = true, exclusive_stick = true, now = 0}
end
local function plain_request()
    return {control = 'y', owner = owner, action = 'unbound', acquire = true,
        retain = true, now = 0}
end
-- enabled, physical, stick_x, stick_y, stick_usable, generation, mode, support, exclusive_stick
local function frame(physical, x, y, support, exclusive)
    return mapper.sample(true, physical, x, y, true, 1, 'mission', support, exclusive)
end
local QUICK_WIELD = 16

frame(0, 0, 0, radial_request(), false)
frame(0, 0, 0, radial_request(), false)
-- The claiming frame: the control goes down while the stick is already hard
-- over. The radial's own `open()` is not written until after this sample, so
-- the stick must be silenced by the request itself.
local pressed, held = frame(16, 0, 0.9, radial_request(), false)
assert(mapper.support_grip.pressed, 'the claim was not taken')
assert(bit.band(pressed, QUICK_WIELD) == 0 and bit.band(held, QUICK_WIELD) == 0,
    'the stick fired its own binding on the frame the radial claimed')
-- And for the rest of the hold, with the caller now reporting the radial open.
pressed, held = frame(16, 0, 0.9, radial_request(), true)
assert(bit.band(bit.bor(pressed, held), QUICK_WIELD) == 0, 'the stick fired while the radial was open')
-- Released: the stick is re-armed only after it passes back through neutral,
-- so letting go with the stick still over does not fire either.
pressed, held = frame(0, 0, 0.9, radial_request(), false)
assert(bit.band(bit.bor(pressed, held), QUICK_WIELD) == 0, 'the stick fired as the radial closed')
pressed, held = frame(0, 0, 0, radial_request(), false)
frame(0, 0, 0.9, radial_request(), false)
local _, after = frame(0, 0, 0.9, radial_request(), false)
assert(bit.band(after, QUICK_WIELD) ~= 0, 'the stick never came back after the radial let go')

-- The contrast: a claimant that does not own the stick leaves it alone, which
-- is what every other claim (a holster, two-hand support) needs.
local plain = Bindings.install({get = function() end})
local function plain_frame(physical, x, y)
    return plain.sample(true, physical, x, y, true, 1, 'mission', plain_request(), false)
end
plain_frame(0, 0, 0)
plain_frame(0, 0, 0)
local plain_pressed = plain_frame(16, 0, 0.9)
assert(bit.band(plain_pressed, QUICK_WIELD) ~= 0,
    'a claim without exclusive_stick must not silence the stick')

print('claim_arbitration=pass yields exclusive_stick rearm plain_claim')
