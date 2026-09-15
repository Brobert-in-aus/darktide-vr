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
-- A grip press this soon after the hand passed through a zone still takes
-- that zone (worn, 15 September evening: the hand is thrown out and grips on
-- the haptic, by which time it has already left).
Holsters.GRACE_SECONDS = 0.35
-- Within this multiple of a zone's radius a hand is approaching it: a grip
-- press there waits for the hand (reverse grace, darktidevr_controller_bindings).
Holsters.APPROACH_SCALE = 1.5
-- A grip press on the holster of the item already in the hand does nothing
-- and plays a double tap (user, 15 September evening: it fired the grip's
-- own binding, the special ability). The second tap follows this long after.
Holsters.REFUSED_TAP_GAP = 0.12
-- The hand reaches from the controller grip (the palm) this far along the
-- controller's aim toward the fingertips: fingers inside an item did not
-- count while the palm was outside its zone (worn, 15 September evening).
Holsters.HAND_REACH = 0.10
-- Body holsters are withheld from 0.2.0-alpha.1 (user, 15 September
-- evening): the option is out of the menu and a saved setting is ignored
-- until the tracked-eye frame (checklist item 32) is checked worn. The
-- unattended test flag still turns them on.
Holsters.BODY_AVAILABLE = false
Holsters.PROBE_SECONDS = 2
Holsters.PROBE_LINES = 60
Holsters.TEST_FLAG = "./../mods/darktidevr/darktidevr_holsters_test.flag"

-- Zone centres in the body frame at the reference eye height, metres from the
-- eyes: x to the right, y forward, z up. Radii scale with the eye height too.
-- selector names the stock wield input the press delivers.
Holsters.ZONES = {
    -- Very large: behind the head, out of sight (user, 15 September evening).
    -- Centred further back and out so the head (the frame origin) stays 5 cm
    -- outside it.
    {id = "shoulder_right", selector = "ranged", slot = "slot_secondary", centre = {0.20, -0.20, -0.10}, radius = 0.25},
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

-- The eye height the zones scale with: the standing calibration's floor eye
-- height when one was taken standing, else the live measurement. The live
-- value follows the head: seated (worn, 15 September evening) it read about
-- 1.25 m and shrank every zone to the minimum. calibration: the saved
-- calibration result table or nil. Pure.
function Holsters.standing_eye_height(calibration, live)
    local standing = type(calibration) == "table" and calibration.seated ~= true and
        tonumber(calibration.floor_eye_height) or nil
    if finite(standing) and standing >= 0.8 and standing <= 2.4 then return standing end
    return live
end

-- The measured standing eye height, clamped to 0.75-1.3 times the reference
-- (1.23-2.13 m): a headset measured while resting on a desk (0.9 m) or a
-- seated measurement must not shrink the zones out of reach.
function Holsters.plausible_eye_height(measured)
    local reference = Holsters.REFERENCE_EYE_HEIGHT
    if not finite(measured) then return reference end
    return math.max(reference * 0.75, math.min(reference * 1.3, measured))
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

-- The nearest zone within scale times its radius of a local point, or nil.
function Holsters.zone_near(point, zones, scale)
    if not point then return nil end
    local best, best_ratio
    for _, zone in ipairs(zones or Holsters.ZONES) do
        local ratio = distance(point, zone.centre) / (zone.radius * scale)
        if ratio <= 1 and (not best_ratio or ratio < best_ratio) then best, best_ratio = zone, ratio end
    end
    return best
end

-- The point of the hand segment from palm to tip (local 3-arrays) that comes
-- nearest to any zone relative to its radius, for zone tests; the palm when
-- there is no zone. Pure.
function Holsters.reach_point(palm, tip, zones)
    if not palm or not tip then return palm end
    local d = {tip[1] - palm[1], tip[2] - palm[2], tip[3] - palm[3]}
    local length2 = d[1] * d[1] + d[2] * d[2] + d[3] * d[3]
    if length2 < 1e-10 then return palm end
    local best, best_ratio = palm, nil
    for _, zone in ipairs(zones or Holsters.ZONES) do
        local c = zone.centre
        local s = ((c[1] - palm[1]) * d[1] + (c[2] - palm[2]) * d[2] + (c[3] - palm[3]) * d[3]) / length2
        s = math.max(0, math.min(1, s))
        local p = {palm[1] + d[1] * s, palm[2] + d[2] * s, palm[3] + d[3] * s}
        local ratio = distance(p, c) / zone.radius
        if not best_ratio or ratio < best_ratio then best, best_ratio = p, ratio end
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
    -- time, or for GRACE_SECONDS after it left that zone while in no other,
    -- or nil. A hand without a usable point leaves its zone.
    -- zones: this hand's zones this frame (default api.zones).
    function api.update(hand, point, t, zones)
        local state = api.hands[hand]
        if not state then return nil end
        if not point or not finite(t) then
            state.zone, state.since, state.recent, state.recent_t = nil, nil, nil, nil
            return nil
        end
        local zone = Holsters.zone_at(point, zones or api.zones, state.zone and state.zone.id)
        if zone ~= state.zone then
            if state.zone and state.since and t - state.since >= Holsters.DWELL_SECONDS then
                state.recent, state.recent_t = state.zone, t
            end
            state.zone, state.since = zone, zone and t or nil
        end
        if zone then
            if t - state.since >= Holsters.DWELL_SECONDS then return zone end
            return nil
        end
        if state.recent and t - state.recent_t <= Holsters.GRACE_SECONDS then return state.recent end
        state.recent, state.recent_t = nil, nil
        return nil
    end

    -- The offer for a zone: its selector, or for the slot already in the hand
    -- a refusal whose press holds no input ("unbound").
    local function offer_for(state, zone, inventory)
        local refused = zone.slot ~= nil and inventory.wielded_slot == zone.slot
        if not (state.offer and state.offer.zone == zone and state.offer.refused == refused) then
            state.offer = {zone = zone, selector = refused and "unbound" or zone.selector, slot = zone.slot,
                refused = refused}
        end
        return state.offer
    end

    -- The grip request for one hand. A claim keeps its owner until the grip
    -- is released (drawing the item moves the hand out of the zone). Nothing
    -- is requested for an empty slot, so the grip keeps its own binding there;
    -- the slot already in the hand takes the press and does nothing.
    function api.request(hand, ready_zone, inventory)
        local state = api.hands[hand]
        if not state then return nil end
        if state.claim then
            return {control = hand .. "_grip", owner = state.claim, action = state.claim.selector,
                acquire = false, retain = true}
        end
        if not ready_zone or not equipped(inventory, ready_zone.slot) then return nil end
        local offer = offer_for(state, ready_zone, inventory)
        return {control = hand .. "_grip", owner = offer, action = offer.selector, acquire = true, retain = true}
    end

    -- A request that only marks the hand as approaching a zone: a grip press
    -- waits for it to arrive. Nothing for an empty slot, or while the hand
    -- already holds a claim.
    function api.approach(hand, zone, inventory)
        local state = api.hands[hand]
        if not state or state.claim or not zone or not equipped(inventory, zone.slot) then return nil end
        local offer = offer_for(state, zone, inventory)
        return {control = hand .. "_grip", owner = offer, action = offer.selector,
            acquire = false, approach = true, retain = true}
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

-- Which grip request the bindings get: a holster claim already held keeps
-- its grip; a two-hand support grip that is held, or is being acquired this
-- frame, is never pre-empted by a hand merely resting in a zone (review, 14
-- September: a hand drifting through a zone dropped the rifle's support grip).
-- Returns the request and whether it is the holster's.
function Holsters.choose(holster_request, support_request, holster_claimed, support_grip)
    if not holster_request then return support_request, false end
    if holster_claimed then return holster_request, true end
    -- A hand only approaching a holster never displaces a support request.
    if support_request and holster_request.approach == true then return support_request, false end
    if support_request and ((type(support_grip) == "table" and support_grip.held) or
            support_request.acquire == true) then
        return support_request, false
    end
    return holster_request, true
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
    local haptic_zone = {}
    local function vector(v) return v and {Vector3.x(v), Vector3.y(v), Vector3.z(v)} end
    local function inventory_of(unit)
        local loadout = ScriptUnit.has_extension(unit, "visual_loadout_system")
        return loadout and loadout._inventory_component
    end
    local function body_frame(unit)
        local first_person = ScriptUnit.has_extension(unit, "first_person_system")
        local eye_unit = first_person and first_person:first_person_unit()
        if not eye_unit or not Unit.alive(eye_unit) then return nil end
        -- The tracked eye (where the player's head really is), not the
        -- first-person unit: seated, or away from the play-space centre, the
        -- real eye sat 30-55 cm ahead of and below it, so every body zone was
        -- behind the player and out of reach (worn probe, 15 September
        -- evening, on the Psyker).
        local eye = presentation.eye_pose and presentation.eye_pose(unit) or Unit.world_position(eye_unit, 1)
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
        local calibration = mod.darktidevr_calibration and mod.darktidevr_calibration.result or
            (mod.get and mod:get("vr_calibration_v1"))
        local physical = Holsters.standing_eye_height(calibration,
            presentation.physical_eye_height and presentation.physical_eye_height())
        local player = Managers.player and Managers.player:local_player(1)
        local character_scale = presentation.calibrated_character_scale and
            presentation.calibrated_character_scale(player) or 1
        local eye_height = Holsters.plausible_eye_height(physical) * (tonumber(character_scale) or 1)
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
    local hand_zones, no_zones = {}, {}
    local pending_tap, last_t, last_unit
    local function sample(unit, active, t)
        last_t, last_unit = t, unit
        -- The second tap of a refused press.
        if pending_tap and type(t) == "number" and t >= pending_tap.at then
            if presentation.haptics then presentation.haptics.pulse(pending_tap.hand, "refused", t) end
            pending_tap = nil
        end
        local body = (Holsters.BODY_AVAILABLE and mod:get("vr_holsters")) or test_flag()
        api.body_active = body == true
        local forearm = presentation.forearm_holsters
        local forearm_on = forearm and forearm.enabled()
        local skull = presentation.skull_throw
        local skull_on = skull and skull.enabled()
        if not active or not (body or forearm_on or skull_on) or not unit then
            api.reset(); owner_hand = nil; haptic_zone = {}; api.frame = nil; api.body_active = false
            return nil
        end
        local frame = body_frame(unit)
        -- For holster counts: the zones' frame this frame.
        api.frame = frame
        -- Probe (worn, 15 September evening: on the Psyker the body holsters
        -- gave no zone and their models did not show, on the Skitarius they
        -- worked): every PROBE_SECONDS, up to PROBE_LINES per session, the
        -- frame against the tracked eye and each hand's local point and nearest
        -- body zone.
        if body and frame and type(t) == "number" and (api.probe_lines or 0) < Holsters.PROBE_LINES and
                t >= (api.probe_t or 0) then
            api.probe_t, api.probe_lines = t + Holsters.PROBE_SECONDS, (api.probe_lines or 0) + 1
            local eye, eye_rotation
            if presentation.eye_pose then eye, eye_rotation = presentation.eye_pose(unit) end
            local parts = {}
            for _, hand in ipairs({"right", "left"}) do
                local position
                if hand == "right" then position = presentation.controller_grip_target()
                else position = presentation.left_controller_grip_target() end
                local p = position and Holsters.local_point(frame, vector(position))
                local nearest, ratio
                for _, zone in ipairs(api.zones) do
                    local r = p and distance(p, zone.centre) / zone.radius
                    if r and (not ratio or r < ratio) then nearest, ratio = zone.id, r end
                end
                parts[#parts + 1] = string.format("%s=%s nearest=%s ratio=%s", hand,
                    p and string.format("%.2f,%.2f,%.2f", p[1], p[2], p[3]) or "nil", tostring(nearest),
                    ratio and string.format("%.2f", ratio) or "nil")
            end
            local eye_local = eye and Holsters.local_point(frame, vector(eye))
            local eye_yaw = eye_rotation and math.deg(Quaternion.yaw(eye_rotation))
            local frame_yaw = math.deg(math.atan2(-frame.forward[1], frame.forward[2]))
            mod:info("DARKTIDEVR_HOLSTER probe scale=%.2f origin=%.2f,%.2f,%.2f eye_local=%s eye_yaw=%s frame_yaw=%.1f %s %s",
                frame.scale, frame.origin[1], frame.origin[2], frame.origin[3],
                eye_local and string.format("%.2f,%.2f,%.2f", eye_local[1], eye_local[2], eye_local[3]) or "nil",
                eye_yaw and string.format("%.1f", eye_yaw) or "nil", frame_yaw, parts[1], parts[2])
        end
        local inventory = inventory_of(unit)
        -- Weapon hand holsters: zones on the gun hand's forearm, for the off
        -- hand only.
        local forearm_zones = forearm_on and frame and forearm.local_zones(unit, frame, Holsters, inventory) or nil
        -- The servo skull's grab zone (darktidevr_skull_throw), for the off hand.
        local skull_zones = skull_on and frame and skull.local_zones(unit, frame, Holsters) or nil
        local support_hand = presentation.weapon_hand_roles and presentation.weapon_hand_roles.physical("support")
        local chosen
        for _, hand in ipairs({"right", "left"}) do
            local zones = body and api.zones or no_zones
            if (forearm_zones or skull_zones) and hand == support_hand then
                for i = #hand_zones, 1, -1 do hand_zones[i] = nil end
                for _, zone in ipairs(zones) do hand_zones[#hand_zones + 1] = zone end
                for _, zone in ipairs(forearm_zones or no_zones) do hand_zones[#hand_zones + 1] = zone end
                for _, zone in ipairs(skull_zones or no_zones) do hand_zones[#hand_zones + 1] = zone end
                zones = hand_zones
            end
            local role_position
            if hand == "right" then role_position = presentation.controller_grip_target()
            else role_position = presentation.left_controller_grip_target() end
            local live = observation[hand .. "_grip_tracking_live"] == true
            local point = live and frame and Holsters.local_point(frame, vector(role_position))
            if point then
                local _, aim_rotation
                if hand == "right" then _, aim_rotation = presentation.controller_aim_target()
                elseif presentation.left_controller_aim_target then _, aim_rotation = presentation.left_controller_aim_target() end
                if aim_rotation then
                    local tip = Holsters.local_point(frame,
                        vector(role_position + Quaternion.forward(aim_rotation) * Holsters.HAND_REACH))
                    point = Holsters.reach_point(point, tip, zones)
                end
            end
            local ready = api.update(hand, point, t, zones)
            local request = api.request(hand, ready, inventory) or
                (point and api.approach(hand, Holsters.zone_near(point, zones, Holsters.APPROACH_SCALE), inventory))
            -- One vibration as a hand's grip becomes a holster press.
            local armed = request and request.acquire and request.owner.zone or nil
            if armed and armed ~= haptic_zone[hand] and presentation.haptics then
                presentation.haptics.pulse(hand, "zone", t)
            end
            haptic_zone[hand] = armed
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
            -- A hand arriving at a zone wins over the other hand merely approaching one.
            if request and (owner_hand == hand or (not owner_hand and (not chosen or
                    (chosen.request.acquire ~= true and request.acquire == true)))) then
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
        return Holsters.choose(request, support_request, owner_hand and api.hands[owner_hand].claim ~= nil,
            presentation.controller_bindings and presentation.controller_bindings.support_grip)
    end
    function api.finish_grip(grip, ours)
        if ours and owner_hand then
            local offer = api.hands[owner_hand].offer
            if grip.pressed and offer and offer.refused then
                mod:info("DARKTIDEVR_HOLSTER refused hand=%s zone=%s (already wielded)", owner_hand,
                    tostring(offer.zone and offer.zone.id))
                if presentation.haptics and type(last_t) == "number" then
                    presentation.haptics.pulse(owner_hand, "refused", last_t)
                    pending_tap = {hand = owner_hand, at = last_t + Holsters.REFUSED_TAP_GAP}
                end
            elseif grip.pressed then
                mod:info("DARKTIDEVR_HOLSTER wield hand=%s selector=%s", owner_hand,
                    tostring(offer and offer.selector))
            end
            local claim = api.hands[owner_hand].claim
            api.finish(owner_hand, grip)
            -- Letting go of the servo skull is the throw.
            if claim and grip.released and not api.hands[owner_hand].claim and claim.zone and
                    claim.zone.id == "skull" and presentation.skull_throw then
                presentation.skull_throw.released(last_unit)
            end
            if not api.hands[owner_hand].claim then owner_hand = nil end
        end
    end
    return api
end

return Holsters
