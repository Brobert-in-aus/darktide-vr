-- Virtual holsters: body frame, zone geometry with hysteresis and dwell, and
-- the grip request (empty or wielded slots pass through; a claim survives the
-- hand leaving the zone until the grip is released).
local Holsters = dofile(assert(arg[1]))
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- Frame: forward along +y, eyes at 1.64 m: local = world offset.
local frame = assert(Holsters.frame({10, 20, 1.64}, {0, 1, 0}, 1.64))
local p = Holsters.local_point(frame, {10.2, 20, 0.92})
assert(near(p[1], 0.2) and near(p[2], 0) and near(p[3], -0.72), "identity frame")
-- Facing +x: the body's right is -y. Forward's vertical part is ignored.
frame = assert(Holsters.frame({0, 0, 1.64}, {2, 0, 5}, 1.64))
p = Holsters.local_point(frame, {0.16, -0.2, 1.64})
assert(near(p[1], 0.2) and near(p[2], 0.16) and near(p[3], 0), "rotated frame")
-- A shorter player: offsets scale with the eye height.
frame = assert(Holsters.frame({0, 0, 1.23}, {0, 1, 0}, 1.23))
p = Holsters.local_point(frame, {0.15, 0, 0.69})
assert(near(p[1], 0.2) and near(p[3], -0.72), "scaled frame")
-- Unusable inputs give no frame.
assert(not Holsters.frame({0, 0, 0 / 0}, {0, 1, 0}, 1.6))
assert(not Holsters.frame({0, 0, 1.6}, {0, 0, 1}, 1.6), "vertical forward")
assert(not Holsters.frame({0, 0, 1.6}, {0, 1, 0}, 0.3), "implausible eye height")
assert(Holsters.frame({0, 0, 3.0}, {0, 1, 0}, 3.0), "an Ogryn-scale eye height is plausible")
assert(not Holsters.local_point(nil, {0, 0, 0}))
-- Implausible measurements are clamped (a headset resting on a desk).
assert(math.abs(Holsters.plausible_eye_height(0.89) - 1.23) < 1e-9)
assert(math.abs(Holsters.plausible_eye_height(1.70) - 1.70) < 1e-9)
assert(math.abs(Holsters.plausible_eye_height(2.6) - 2.132) < 1e-9)
assert(Holsters.plausible_eye_height(nil) == Holsters.REFERENCE_EYE_HEIGHT)

-- Zone scale: the standing calibration's eye height, not the live (seated) one.
assert(Holsters.standing_eye_height({floor_eye_height = 1.62}, 1.25) == 1.62, "standing calibration")
assert(Holsters.standing_eye_height({floor_eye_height = 1.2, seated = true}, 1.25) == 1.25, "seated calibration: live")
assert(Holsters.standing_eye_height(nil, 1.25) == 1.25 and Holsters.standing_eye_height({floor_eye_height = 9}, nil) == nil)

-- Zones: entry radius, exit hysteresis, nearest by relative distance.
local hip_left = Holsters.zone_at({-0.20, 0.05, -0.72})
assert(hip_left and hip_left.id == "hip_left" and hip_left.selector == "melee" and hip_left.slot == "slot_primary")
assert(Holsters.zone_at({-0.20, 0.16, -0.72}) == nil, "outside the entry radius")
assert(Holsters.zone_at({-0.20, 0.16, -0.72}, nil, "hip_left").id == "hip_left", "inside the exit radius keeps the zone")
assert(Holsters.zone_at({-0.20, 0.19, -0.72}, nil, "hip_left") == nil, "beyond the exit radius")
assert(Holsters.zone_at({0.16, -0.14, -0.10}).id == "shoulder_right")
assert(Holsters.zone_at({0, 0, 0}) == nil, "the head is no holster")
for _, zone in ipairs(Holsters.ZONES) do
    assert(Holsters.zone_at(zone.centre).id == zone.id, "zone centre resolves to another zone: " .. zone.id)
end

-- Dwell: a hand passing through does not arm the zone.
local api = Holsters.new()
local chest = {-0.13, 0.16, -0.38}
assert(api.update("left", chest, 1.00) == nil, "armed on the first frame")
assert(api.update("left", chest, 1.03) == nil, "armed before the dwell")
local ready = api.update("left", chest, 1.06)
assert(ready and ready.id == "chest_left")
-- Grace: just after leaving, the zone is still offered (a press on the haptic).
local graced = api.update("left", {0, 0, 0}, 1.07)
assert(graced and graced.id == "chest_left" and api.hands.left.zone == nil, "left the zone, within the grace")
assert(api.update("left", {0, 0, 0}, 1.07 + Holsters.GRACE_SECONDS + 0.01) == nil, "grace expires")
assert(api.update("left", chest, 1.50) == nil, "dwell restarts on re-entry")
assert(api.update("left", chest, 1.50 + Holsters.DWELL_SECONDS) ~= nil, "armed again after the dwell")
-- Passing through without the dwell leaves no grace.
local quick = Holsters.new()
quick.update("left", chest, 2.00)
assert(quick.update("left", {0, 0, 0}, 2.02) == nil, "no grace for a zone never armed")
assert(api.update("left", nil, 1.2) == nil and api.hands.left.zone == nil, "lost tracking leaves the zone")
assert(api.update("both", chest, 1.2) == nil, "unknown hand")

-- Approach: within 1.5 times a zone's radius, a request that only marks the hand.
do
    local zones = {{id = "z", centre = {0, 0, 0}, radius = 0.1, slot = "slot_pocketable_small", selector = "stim"}}
    assert(Holsters.zone_near({0.14, 0, 0}, zones, Holsters.APPROACH_SCALE).id == "z", "approaching")
    assert(Holsters.zone_near({0.16, 0, 0}, zones, Holsters.APPROACH_SCALE) == nil, "too far")
    local near_api = Holsters.new()
    local inv = {slot_pocketable_small = "content/items/pocketable/syringe", wielded_slot = "slot_secondary"}
    local request = near_api.approach("left", zones[1], inv)
    assert(request and request.approach and request.acquire == false and request.action == "stim", "approach request")
    assert(near_api.approach("left", zones[1], {slot_pocketable_small = "not_equipped"}) == nil, "empty slot")
    -- An approach never displaces a support request; an arrival still yields to a held support grip.
    local support = {control = "left_grip", acquire = false}
    local chosen, ours = Holsters.choose(request, support, false, {held = false})
    assert(chosen == support and not ours, "approach yields to the support request")
    chosen, ours = Holsters.choose(request, nil, false, nil)
    assert(chosen == request and ours, "approach alone is the holster's")
end

-- Reach: the hand segment's point nearest a zone, so fingers inside it count.
do
    local zones = {{id = "z", centre = {0, 0.2, 0}, radius = 0.05}}
    local p = Holsters.reach_point({0, 0, 0}, {0, 0.1, 0}, zones)
    assert(math.abs(p[2] - 0.1) < 1e-9 and Holsters.zone_at(p, zones) == nil, "tip nearest, still outside")
    p = Holsters.reach_point({0, 0.08, 0}, {0, 0.18, 0}, zones)
    assert(Holsters.zone_at(p, zones) == zones[1], "fingertips in the zone count")
    assert(Holsters.zone_at({0, 0.08, 0}, zones) == nil, "the palm alone was outside")
    p = Holsters.reach_point({0, 0.3, 0}, {0, 0.4, 0}, zones)
    assert(math.abs(p[2] - 0.3) < 1e-9, "palm nearest when the tip points away")
    assert(Holsters.reach_point({1, 2, 3}, nil, zones)[1] == 1, "no tip: the palm")
end

-- Requests.
local inventory = {wielded_slot = "slot_secondary", slot_primary = "sword", slot_secondary = "lasgun",
    slot_pocketable_small = "syringe", slot_pocketable = "not_equipped", slot_device = "auspex"}
local stim = Holsters.zone_at(chest)
local request = assert(api.request("left", stim, inventory))
assert(request.control == "left_grip" and request.action == "stim" and request.acquire == true and request.retain == true)
assert(api.request("left", stim, inventory).owner == request.owner, "offer identity changes every frame")
-- Empty slot: no request, the grip keeps its binding.
assert(api.request("right", Holsters.zone_at({0.13, 0.16, -0.38}), inventory) == nil, "empty pocketable slot claimed")
-- The slot already in the hand: the press is taken and holds no input.
do
    local refuse_api = Holsters.new()
    local refused = assert(refuse_api.request("right", Holsters.zone_at({0.16, -0.14, -0.10}), inventory))
    assert(refused.action == "unbound" and refused.owner.refused == true and refused.acquire == true, "wielded slot not refused")
    local near = assert(refuse_api.approach("right", Holsters.zone_at({0.16, -0.14, -0.10}), inventory))
    assert(near.action == "unbound" and near.approach == true, "wielded approach not refused")
    local switched = {wielded_slot = "slot_primary", slot_primary = "sword", slot_secondary = "lasgun"}
    local offered = refuse_api.request("right", Holsters.zone_at({0.16, -0.14, -0.10}), switched)
    assert(offered.action == "ranged" and not offered.owner.refused, "refusal outlived the switch")
end
assert(api.request("right", nil, inventory) == nil)
-- Pressed: the claim holds while the hand draws the item out of the zone.
api.finish("left", {pressed = true, held = true})
local held = assert(api.request("left", nil, inventory), "claim lost outside the zone")
assert(held.owner == request.owner and held.action == "stim" and held.acquire == false and held.retain == true)
api.finish("left", {held = true})
assert(api.request("left", nil, inventory), "claim lost while held")
api.finish("left", {released = true})
assert(api.request("left", nil, inventory) == nil, "claim outlived the release")
-- Cancelled (e.g. menu opened) also ends the claim.
api.request("left", stim, inventory)
api.finish("left", {pressed = true, held = true})
api.finish("left", {cancelled = true})
assert(api.request("left", nil, inventory) == nil)
-- A grip that was not pressed in the zone never becomes a claim.
api.request("left", stim, inventory)
api.finish("left", {held = false})
assert(api.request("left", nil, inventory) == nil)
-- Belt: blitz has no inventory slot; it is requested whatever is wielded,
-- including while the blitz is already out (the press throws or re-aims as
-- the blitz button does).
local belt = Holsters.zone_at({0, 0.14, -0.60})
assert(belt and belt.id == "belt" and belt.selector == "blitz" and belt.slot == nil)
local blitz = assert(api.request("right", belt, inventory), "belt not requested")
assert(blitz.action == "blitz" and blitz.acquire == true)
local grenade_out = {wielded_slot = "slot_grenade_ability", slot_primary = "sword"}
api.reset("right")
assert(api.request("right", belt, grenade_out), "belt passed through while the blitz is out")
api.reset("right")
assert(api.request("right", belt, nil) == nil, "requested without an inventory")
api.reset()
assert(api.hands.left.claim == nil and api.hands.right.zone == nil)

-- Choosing between a holster request and two-hand support.
local h, s = {action = "stim"}, {action = "alternate", acquire = false}
local chosen, ours = Holsters.choose(nil, s, false, {held = false})
assert(chosen == s and not ours, "no holster request")
chosen, ours = Holsters.choose(h, nil, false, nil)
assert(chosen == h and ours, "holster alone")
chosen, ours = Holsters.choose(h, s, false, {held = true})
assert(chosen == s and not ours, "a held support grip was pre-empted by a resting hand")
chosen, ours = Holsters.choose(h, {action = "alternate", acquire = true}, false, {held = false})
assert(not ours, "a support grip being acquired was pre-empted")
chosen, ours = Holsters.choose(h, s, false, {held = false})
assert(chosen == h and ours, "idle support blocked the holster")
chosen, ours = Holsters.choose(h, s, true, {held = true})
assert(chosen == h and ours, "a holster claim lost its grip")

print("holsters=pass frame zones hysteresis dwell requests claim_retention pass_through")
