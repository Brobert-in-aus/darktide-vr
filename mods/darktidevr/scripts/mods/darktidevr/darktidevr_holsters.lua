-- Virtual holsters: reach to a body zone and press grip to wield what is kept
-- there (design: docs/phase1/virtual-holsters-2026-09-14.md). Pure logic, no
-- engine calls: the caller supplies tracked hand positions, the head position,
-- the body's flat forward direction and the calibrated eye height, and gets
-- back a grip request in the shape the controller bindings already accept for
-- two-hand support ({control, owner, action, acquire, retain}).
local Holsters = {}

Holsters.REFERENCE_EYE_HEIGHT = 1.64
Holsters.EXIT_SCALE = 1.25
Holsters.DWELL_SECONDS = 0.05
Holsters.TEST_FLAG = "./../mods/darktidevr/darktidevr_holsters_test.flag"

-- Zone centres in the body frame at the reference eye height, metres from the
-- eyes: x to the right, y forward, z up. Radii scale with the eye height too.
-- selector names the stock wield input the press delivers.
Holsters.ZONES = {
    {id = "shoulder_right", selector = "ranged", slot = "slot_secondary", centre = {0.16, -0.14, -0.10}, radius = 0.15},
    {id = "hip_left", selector = "melee", slot = "slot_primary", centre = {-0.20, 0.00, -0.72}, radius = 0.14},
    {id = "hip_right", selector = "device", slot = "slot_device", centre = {0.20, 0.00, -0.72}, radius = 0.14},
    {id = "chest_left", selector = "stim", slot = "slot_pocketable_small", centre = {-0.13, 0.16, -0.38}, radius = 0.10},
    {id = "chest_right", selector = "pocketable", slot = "slot_pocketable", centre = {0.13, 0.16, -0.38}, radius = 0.10},
    -- Blitz from the belt: the grip holds the stock blitz input, so pressing
    -- draws and aims it and releasing throws, as the blitz button does. No
    -- inventory slot to check; the ability itself decides (charges, class).
    {id = "belt", selector = "blitz", centre = {0.00, 0.14, -0.60}, radius = 0.11},
}

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function vector(v) return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3]) end

-- Body frame from the head position, the body's forward direction (only its
-- horizontal part is used) and the eye height. nil when any input is unusable.
function Holsters.frame(head, forward, eye_height)
    if not vector(head) or not vector(forward) or not finite(eye_height) or
            eye_height < 0.8 or eye_height > 4.5 then return nil end
    local length = math.sqrt(forward[1] * forward[1] + forward[2] * forward[2])
    if length < 1e-4 then return nil end
    local fx, fy = forward[1] / length, forward[2] / length
    return {origin = head, forward = {fx, fy}, right = {fy, -fx},
        scale = eye_height / Holsters.REFERENCE_EYE_HEIGHT}
end

-- A world point in reference-body coordinates (x right, y forward, z up).
function Holsters.local_point(frame, point)
    if not frame or not vector(point) then return nil end
    local dx, dy, dz = point[1] - frame.origin[1], point[2] - frame.origin[2], point[3] - frame.origin[3]
    local s = frame.scale
    return {(dx * frame.right[1] + dy * frame.right[2]) / s,
        (dx * frame.forward[1] + dy * frame.forward[2]) / s, dz / s}
end

local function distance(a, b)
    local x, y, z = a[1] - b[1], a[2] - b[2], a[3] - b[3]
    return math.sqrt(x * x + y * y + z * z)
end

-- The zone holding a local point: the current zone keeps the hand until it
-- leaves the larger exit radius; otherwise the nearest zone whose entry
-- radius contains the point, relative to its radius.
function Holsters.zone_at(point, zones, current)
    if not point then return nil end
    zones = zones or Holsters.ZONES
    if current then
        for _, zone in ipairs(zones) do
            if zone.id == current and distance(point, zone.centre) <= zone.radius * Holsters.EXIT_SCALE then
                return zone
            end
        end
    end
    local best, best_ratio
    for _, zone in ipairs(zones) do
        local ratio = distance(point, zone.centre) / zone.radius
        if ratio <= 1 and (not best_ratio or ratio < best_ratio) then
            best, best_ratio = zone, ratio
        end
    end
    return best
end

local function equipped(inventory, slot)
    if slot == nil then return inventory ~= nil end
    local item = inventory and inventory[slot]
    return item ~= nil and item ~= "not_equipped"
end

function Holsters.new(zones)
    local api = {zones = zones or Holsters.ZONES, hands = {left = {}, right = {}}}

    function api.reset(hand)
        if hand then api.hands[hand] = {} else api.hands = {left = {}, right = {}} end
    end

    -- Track one hand. Returns the zone the hand has rested in for the dwell
    -- time, or nil. A hand without a usable point leaves its zone.
    function api.update(hand, point, t)
        local state = api.hands[hand]
        if not state then return nil end
        if not point or not finite(t) then
            state.zone, state.since = nil, nil
            return nil
        end
        local zone = Holsters.zone_at(point, api.zones, state.zone and state.zone.id)
        if zone ~= state.zone then
            state.zone, state.since = zone, zone and t or nil
        end
        return zone and t - state.since >= Holsters.DWELL_SECONDS and zone or nil
    end

    -- The grip request for one hand. A claim keeps its owner until the grip
    -- is released (drawing the item moves the hand out of the zone). Nothing
    -- is requested for an empty slot or for the slot already in the hand, so
    -- the grip keeps its own binding there.
    function api.request(hand, ready_zone, inventory)
        local state = api.hands[hand]
        if not state then return nil end
        if state.claim then
            return {control = hand .. "_grip", owner = state.claim, action = state.claim.selector,
                acquire = false, retain = true}
        end
        if not ready_zone or not equipped(inventory, ready_zone.slot) or
                (ready_zone.slot and inventory.wielded_slot == ready_zone.slot) then
            return nil
        end
        state.offer = state.offer and state.offer.zone == ready_zone and state.offer or
            {zone = ready_zone, selector = ready_zone.selector, slot = ready_zone.slot}
        return {control = hand .. "_grip", owner = state.offer, action = ready_zone.selector,
            acquire = true, retain = true}
    end

    -- Feed back the bindings' grip result for the hand that made the request.
    function api.finish(hand, grip)
        local state = api.hands[hand]
        if not state or type(grip) ~= "table" then return end
        if grip.pressed and state.offer then
            state.claim, state.offer = state.offer, nil
        end
        if grip.released or grip.cancelled or (state.claim and not grip.held and not grip.pressed) then
            state.claim = nil
        end
    end

    return api
end

-- Live adapter, behind the "vr_holsters" option (default off). World space
-- throughout: tracked grip targets, the first-person eye position, the body's
-- visual yaw (head yaw when unknown) and the player's physical eye height. One hand at a time owns a request; a claim keeps its hand until the
-- grip is released. The two-hand support request is used when no holster is
-- armed or claimed.
function Holsters.install(mod, presentation, observation)
    local api = Holsters.new()
    api.idle_grip = {held = false, pressed = false, released = false, cancelled = false}
    local owner_hand, logged = nil, {}
    local function vector(v) return v and {Vector3.x(v), Vector3.y(v), Vector3.z(v)} end
    local function inventory_of(unit)
        local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
        return loadout and loadout._inventory_component
    end
    local function body_frame(unit)
        local first_person = ScriptUnit.has_extension(unit, "first_person_system")
        local eye_unit = first_person and first_person:first_person_unit()
        if not eye_unit or not Unit.alive(eye_unit) then return nil end
        local eye = Unit.world_position(eye_unit, 1)
        local yaw = observation.body_visual_yaw
        local forward
        if type(yaw) == "number" and yaw == yaw then
            forward = Quaternion.forward(Quaternion(Vector3.up(), yaw))
        else
            forward = Quaternion.forward(Unit.world_rotation(eye_unit, 1))
        end
        -- Tracked hands move in physical metres (times the character scale,
        -- 1 for humans), so the zones scale with the player's own eye height,
        -- not the character's eye height in the world.
        local physical = presentation.physical_eye_height and presentation.physical_eye_height()
        local player = Managers.player and Managers.player:local_player(1)
        local character_scale = presentation.calibrated_character_scale and
            presentation.calibrated_character_scale(player) or 1
        local eye_height = (physical or Holsters.REFERENCE_EYE_HEIGHT) * (tonumber(character_scale) or 1)
        return Holsters.frame(vector(eye), vector(forward), eye_height)
    end
    -- Unattended runs turn holsters on with a request file instead of the
    -- saved option ("enabled"); players never have it.
    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Holsters.TEST_FLAG, "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end
    local function sample(unit, active, t)
        if not active or not (mod:get("vr_holsters") or test_flag()) or not unit then
            api.reset(); owner_hand = nil
            return nil
        end
        local frame = body_frame(unit)
        local inventory = inventory_of(unit)
        local chosen
        for _, hand in ipairs({"right", "left"}) do
            local role_position
            if hand == "right" then role_position = presentation.controller_grip_target()
            else role_position = presentation.left_controller_grip_target() end
            local live = observation[hand .. "_grip_tracking_live"] == true
            local point = live and frame and Holsters.local_point(frame, vector(role_position))
            local ready = api.update(hand, point, t)
            local request = api.request(hand, ready, inventory)
            if test_enabled and hand == "right" then
                api.trace_count = (api.trace_count or 0) + 1
                if api.trace_count % 60 == 1 then
                    local state = api.hands[hand]
                    mod:info("DARKTIDEVR_HOLSTER trace live=%s point=%s zone=%s ready=%s claim=%s request=%s eye_height=%s",
                        tostring(live), point and string.format("%.2f,%.2f,%.2f", point[1], point[2], point[3]) or "nil",
                        tostring(state.zone and state.zone.id), tostring(ready and ready.id),
                        tostring(state.claim and state.claim.selector), tostring(request and request.action),
                        frame and string.format("%.2f", frame.scale * Holsters.REFERENCE_EYE_HEIGHT) or "nil")
                end
            end
            if request and (owner_hand == hand or (not owner_hand and not chosen)) then
                chosen = {hand = hand, request = request}
            end
        end
        if chosen and chosen.request.acquire and not logged[chosen.request.owner.zone.id] then
            logged[chosen.request.owner.zone.id] = true
            mod:info("DARKTIDEVR_HOLSTER armed zone=%s hand=%s selector=%s wielded=%s",
                chosen.request.owner.zone.id, chosen.hand, chosen.request.action,
                tostring(inventory and inventory.wielded_slot))
        end
        owner_hand = chosen and chosen.hand or nil
        -- Evidence of the result: the wielded slot whenever it changes.
        local wielded = inventory and inventory.wielded_slot
        if wielded ~= api.last_wielded then
            if api.last_wielded then
                mod:info("DARKTIDEVR_HOLSTER wielded_slot=%s previous=%s", tostring(wielded), tostring(api.last_wielded))
            end
            api.last_wielded = wielded
        end
        return chosen and chosen.request or nil
    end
    -- Returns the request to hand to the bindings, and whether it is ours.
    function api.sample(unit, active, t, support_request)
        local ok, request = pcall(sample, unit, active, t)
        if not ok then
            api.reset(); owner_hand = nil
            if not logged.failure then
                logged.failure = true
                mod:info("DARKTIDEVR_HOLSTER cancelled=%s", tostring(request):sub(1, 160))
            end
            return support_request, false
        end
        if request then return request, true end
        return support_request, false
    end
    function api.finish_grip(grip, ours)
        if ours and owner_hand then
            if grip.pressed then
                mod:info("DARKTIDEVR_HOLSTER wield hand=%s selector=%s", owner_hand,
                    tostring(api.hands[owner_hand].offer and api.hands[owner_hand].offer.selector))
            end
            api.finish(owner_hand, grip)
            if not api.hands[owner_hand].claim then owner_hand = nil end
        end
    end
    return api
end

return Holsters
