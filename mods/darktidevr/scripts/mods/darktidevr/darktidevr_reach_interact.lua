-- Reach interactions (todo-2026-09-14: "Grip on an interactable within arm's
-- reach triggers interact without aiming at it, still through the stock
-- interactor and its range from the player"). Pure: no engine calls.
--
-- The stock interactor picks its target from the first-person position and the
-- look direction, first by a ray and then by a sphere near that line
-- (`InteractorExtension._find_interaction_object`). Rather than choose targets
-- ourselves, which would lose the stock range, collision filters, priorities
-- and interactee checks, this aims that same near-line search along the
-- direction from the head to the hand. Reaching for a door control then finds
-- it while the player looks elsewhere, and everything the stock search refuses
-- is still refused.
--
-- The grip delivers the stock interact input through the contextual grip
-- request the virtual holsters use, so the reverse-grip grace, the haptics and
-- the "suppress the bound action for that press" rules are shared.
local Reach = {}

-- The head-to-hand direction is only meaningful once the hand is away from the
-- head; nearer than this the direction swings wildly with tracking noise.
Reach.MIN_EXTENSION = 0.30
-- A hand this far from the chosen target counts as reaching it. Arm's reach is
-- the point, and the stock interactor's own distance from the player still
-- bounds what can be found at all.
Reach.HAND_RADIUS = 0.45
-- Announced earlier than that, so a grip pressed on the way in is held by the
-- bindings' reverse grace instead of firing the grip's bound action.
Reach.APPROACH_RADIUS = 0.75

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function point(v) return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3]) end
local function subtract(a, b) return {a[1] - b[1], a[2] - b[2], a[3] - b[3]} end
local function length(v) return math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2) end

function Reach.distance(a, b)
    if not point(a) or not point(b) then return nil end
    return length(subtract(a, b))
end

-- The unit direction from the head to the hand, for the stock near-line
-- search, or nil while the hand is too close to the head to aim with. Pure.
function Reach.direction(eye, hand)
    if not point(eye) or not point(hand) then return nil end
    local offset = subtract(hand, eye)
    local extension = length(offset)
    if extension < Reach.MIN_EXTENSION then return nil end
    return {offset[1] / extension, offset[2] / extension, offset[3] / extension}, extension
end

-- Which hand is reaching, given each hand's position, the head and the target
-- the stock search returned for that hand. Hands are
-- {{hand = "left", position = {...}, target = {...}}, ...}; a hand with no
-- target is skipped. Returns the nearest hand-to-target pair with how far it
-- is and whether it is only approaching, or nil. Pure.
function Reach.choose(eye, hands)
    if type(hands) ~= "table" then return nil end
    local best
    for i = 1, #hands do
        local entry = hands[i]
        if type(entry) == "table" and point(entry.position) and point(entry.target) and
                Reach.direction(eye, entry.position) then
            local distance = Reach.distance(entry.position, entry.target)
            if distance and distance <= Reach.APPROACH_RADIUS and
                    (not best or distance < best.distance) then
                best = {hand = entry.hand, target = entry.target, distance = distance,
                    approach = distance > Reach.HAND_RADIUS}
            end
        end
    end
    return best
end

-- The contextual grip request for a choice, in the shape the bindings expect
-- (see darktidevr_holsters.lua). `owner` identifies the claim so a moving hand
-- or a changed target releases it. Pure.
function Reach.request(choice, owner)
    if type(choice) ~= "table" or not choice.hand then return nil end
    return {control = choice.hand .. "_grip", owner = owner or choice, action = "interact",
        acquire = not choice.approach, approach = choice.approach or nil, retain = true}
end

-- Engine side. The pure part above is what the tests exercise.
function Reach.install(mod, presentation)
    local api = {}
    local claim, logged, failed = nil, {}, false
    local reach_target = nil

    function api.enabled()
        return mod:get("vr_reach_interact") == true
    end

    local function vector(value)
        if not value then return nil end
        local ok, x, y, z = pcall(Vector3.to_elements, value)
        if not ok or x ~= x then return nil end
        return {x, y, z}
    end

    -- The stock near-line search, aimed along the head-to-hand direction
    -- instead of the look direction. Everything it refuses stays refused.
    local function search(extension, unit, eye, hand)
        local direction = Reach.direction(eye, hand)
        if not direction then return nil end
        local component = extension._first_person_component
        if not component or not component.position then return nil end
        local target, node = extension:_find_object_near_line_of_sight(unit, component.position,
            Vector3(direction[1], direction[2], direction[3]), true)
        if not target or not Unit.alive(target) then return nil end
        return target, node or 0, vector(Unit.world_position(target, 1))
    end

    local function sample(unit, active, t)
        if not active or not unit or not api.enabled() then
            claim, reach_target = nil, nil
            return nil
        end
        local extension = ScriptUnit.has_extension(unit, "interactor_system")
        if not extension then claim, reach_target = nil, nil; return nil end
        local eye = presentation.eye_pose and vector(presentation.eye_pose(unit))
        if not eye then claim, reach_target = nil, nil; return nil end
        local hands = {}
        for _, hand in ipairs({"right", "left"}) do
            local grip = hand == "right" and presentation.controller_grip_target() or
                presentation.left_controller_grip_target()
            local position = vector(grip)
            if position then
                local target, node, target_position = search(extension, unit, eye, position)
                if target_position then
                    hands[#hands + 1] = {hand = hand, position = position, target = target_position,
                        unit = target, node = node}
                end
            end
        end
        local choice = Reach.choose(eye, hands)
        if not choice then claim, reach_target = nil, nil; return nil end
        for i = 1, #hands do
            if hands[i].hand == choice.hand then
                reach_target = {unit = hands[i].unit, node = hands[i].node, interactor = unit}
            end
        end
        -- One claim identity while the same hand keeps reaching the same unit,
        -- so the bindings hold the grip rather than re-taking it each frame.
        if not claim or claim.hand ~= choice.hand or claim.unit ~= reach_target.unit then
            claim = {hand = choice.hand, unit = reach_target.unit}
        end
        claim.approach = choice.approach
        if not choice.approach and not logged[claim] then
            logged[claim] = true
            mod:info("DARKTIDEVR_REACH armed hand=%s distance_m=%.2f", choice.hand, choice.distance)
        end
        return Reach.request({hand = choice.hand, approach = choice.approach}, claim)
    end

    -- The stock interactor's own choice, replaced by what the hand reaches.
    -- Returning it here keeps every later stock check (duration, interactee
    -- state, the ongoing-interaction tests) exactly as it is.
    function api.find(extension, unit, chosen)
        if not api.enabled() then return chosen end
        if not reach_target or reach_target.interactor ~= unit then return chosen end
        if not reach_target.unit or not Unit.alive(reach_target.unit) then return chosen end
        return reach_target.unit, reach_target.node
    end

    function api.sample(unit, active, t, support_request)
        -- A holster or two-hand claim owns the grip first: reaching for a door
        -- must not take the grip away from drawing a weapon.
        if support_request then claim, reach_target = nil, nil; return support_request end
        if failed then return support_request end
        local ok, request = pcall(sample, unit, active, t)
        if not ok then
            failed = true
            claim, reach_target = nil, nil
            mod:warning("DARKTIDEVR_REACH error=%s", tostring(request):sub(1, 160))
            return support_request
        end
        return request or support_request
    end

    -- No hook of its own: darktidevr_controller_aim.lua already hooks
    -- InteractorExtension._find_interaction_object (DMF keeps one hook per
    -- function per mod) and calls api.find from there.

    function api.destroy() claim, reach_target = nil, nil end
    return api
end

return Reach
