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
assert(not Holsters.local_point(nil, {0, 0, 0}))

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
assert(api.update("left", {0, 0, 0}, 1.07) == nil and api.hands.left.zone == nil, "left the zone")
assert(api.update("left", chest, 1.08) == nil, "dwell restarts on re-entry")
assert(api.update("left", nil, 1.2) == nil and api.hands.left.zone == nil, "lost tracking leaves the zone")
assert(api.update("both", chest, 1.2) == nil, "unknown hand")

-- Requests.
local inventory = {wielded_slot = "slot_secondary", slot_primary = "sword", slot_secondary = "lasgun",
    slot_pocketable_small = "syringe", slot_pocketable = "not_equipped", slot_device = "auspex"}
local stim = Holsters.zone_at(chest)
local request = assert(api.request("left", stim, inventory))
assert(request.control == "left_grip" and request.action == "stim" and request.acquire == true and request.retain == true)
assert(api.request("left", stim, inventory).owner == request.owner, "offer identity changes every frame")
-- Empty slot and the slot already in the hand: no request, the grip keeps its binding.
assert(api.request("right", Holsters.zone_at({0.13, 0.16, -0.38}), inventory) == nil, "empty pocketable slot claimed")
assert(api.request("right", Holsters.zone_at({0.16, -0.14, -0.10}), inventory) == nil, "wielded ranged slot claimed")
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
api.reset()
assert(api.hands.left.claim == nil and api.hands.right.zone == nil)

print("holsters=pass frame zones hysteresis dwell requests claim_retention pass_through")
