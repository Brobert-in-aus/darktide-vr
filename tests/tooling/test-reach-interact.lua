-- Reach interactions: the head-to-hand aim direction, which hand is reaching,
-- and the contextual grip request it produces.
local Reach = dofile(assert(arg[1]))
local function near(a, b, e, m)
    assert(math.abs(a - b) < (e or 1e-9), (m or 'mismatch') .. ': ' .. tostring(a) .. ' vs ' .. tostring(b))
end

local EYE = {0, 0, 1.7}

-- Direction: a hand out in front aims forward, normalised.
local direction, extension = Reach.direction(EYE, {0, 0.6, 1.5})
near(direction[1], 0); near(direction[2], 0.6 / extension); near(extension, math.sqrt(0.6 ^ 2 + 0.2 ^ 2))
near(direction[1] ^ 2 + direction[2] ^ 2 + direction[3] ^ 2, 1, 1e-12, 'unit length')
-- A hand at the chest is too close to the head to aim with.
assert(Reach.direction(EYE, {0.05, 0.10, 1.55}) == nil, 'below the extension floor')
assert(Reach.direction(EYE, nil) == nil and Reach.direction(nil, {0, 1, 1}) == nil)
assert(Reach.direction(EYE, {0, 0 / 0, 1.5}) == nil, 'non-finite')

-- Choosing: the nearer hand wins, even when both reach something.
local choice = Reach.choose(EYE, {
    {hand = 'left', position = {-0.3, 0.6, 1.4}, target = {-0.3, 0.75, 1.4}},
    {hand = 'right', position = {0.3, 0.6, 1.4}, target = {0.3, 0.95, 1.4}},
})
assert(choice.hand == 'left', 'the nearer hand reaches'); near(choice.distance, 0.15)
assert(choice.approach == false, 'inside the hand radius')

-- Past the hand radius but inside the approach radius: announced early so the
-- bindings' reverse grace can hold a grip pressed on the way in.
local approaching = Reach.choose(EYE, {{hand = 'right', position = {0.3, 0.5, 1.4}, target = {0.3, 1.1, 1.4}}})
near(approaching.distance, 0.6); assert(approaching.approach == true, 'still approaching')

-- Out of reach altogether, and a hand with nothing found for it.
assert(Reach.choose(EYE, {{hand = 'right', position = {0.3, 0.5, 1.4}, target = {0.3, 1.5, 1.4}}}) == nil)
assert(Reach.choose(EYE, {{hand = 'right', position = {0.3, 0.6, 1.4}}}) == nil, 'no target for that hand')
-- A hand that has not left the chest cannot reach, whatever is beside it.
assert(Reach.choose(EYE, {{hand = 'left', position = {0.05, 0.1, 1.6}, target = {0.05, 0.15, 1.6}}}) == nil)
assert(Reach.choose(EYE, {}) == nil and Reach.choose(EYE, nil) == nil)

-- The request: the stock interact input on that hand's grip, held while the
-- claim stands, in the shape the bindings and holsters share.
local owner = {}
local request = Reach.request(choice, owner)
assert(request.control == 'left_grip' and request.action == 'interact')
assert(request.acquire == true and request.approach == nil and request.retain == true)
assert(request.owner == owner, 'the claim identifies itself so a change releases it')
local early = Reach.request(approaching, owner)
assert(early.control == 'right_grip' and early.acquire == false and early.approach == true,
    'approaching announces without taking the grip')
assert(Reach.request(nil, owner) == nil and Reach.request({}, owner) == nil)

print('reach_interact=pass direction choose request')
