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
-- Unattended runs turn the option on through this rather than the saved
-- settings, which belong to the player.
Reach.TEST_FLAG = "./../mods/darktidevr/darktidevr_reach_test.flag"
Reach.PROBE_SECONDS = 2
Reach.PROBE_LINES = 40
-- The stock search is a physics sphere overlap per extended hand. Running it
-- on every input frame adds two of those to a frame that stock does one in, for
-- a feature that is idle most of the time. Run it every SEARCH_EVERY frames and
-- re-measure the cached targets against live hand positions in between, so
-- arming stays as responsive as the hand.
Reach.SEARCH_EVERY = 2

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
    local claim, logged, failures = nil, {}, 0
    local tick, cached = 0, {}
    local reach_target = nil

    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        -- Every 300 calls (about five seconds at the input rate): a failed open
        -- on the main thread each poll is where these modules' spikes came
        -- from (docs/LUA-FRAME-PROFILE-2026-09-16.md).
        test_poll = 300
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Reach.TEST_FLAG, "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end

    function api.enabled()
        return mod:get("vr_reach_interact") == true or test_flag()
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
        -- The node the stock search hit, not the unit's root. A downed team
        -- mate's root is at their feet and a door's is its origin, both often
        -- a metre from the part the hand is actually on, which would leave
        -- them out of reach for ever.
        local position
        if node and node > 0 then
            local ok, hit = pcall(Unit.world_position, target, node)
            if ok then position = vector(hit) end
        end
        return target, node or 0, position or vector(Unit.world_position(target, 1))
    end

    local function sample(unit, active, t)
        if not active or not unit or not api.enabled() then
            claim, reach_target, cached = nil, nil, {}
            return nil
        end
        if not Unit.alive(unit) then claim, reach_target = nil, nil; return nil end
        local extension = ScriptUnit.has_extension(unit, "interactor_system")
        if not extension then claim, reach_target = nil, nil; return nil end
        local eye = presentation.eye_pose and vector(presentation.eye_pose(unit))
        if not eye then claim, reach_target = nil, nil; return nil end
        tick = (tick + 1) % Reach.SEARCH_EVERY
        local searching = tick == 0
        local hands = {}
        for _, hand in ipairs({"right", "left"}) do
            local grip = hand == "right" and presentation.controller_grip_target() or
                presentation.left_controller_grip_target()
            local position = vector(grip)
            if position then
                local found = searching and nil or cached[hand]
                if not found then
                    local target, node, target_position = search(extension, unit, eye, position)
                    if target_position then
                        found = {target = target_position, unit = target, node = node}
                    end
                    cached[hand] = found
                elseif not found.unit or not Unit.alive(found.unit) then
                    found, cached[hand] = nil, nil
                end
                if found then
                    -- The target is from this frame or the last; the hand
                    -- position always from this one.
                    hands[#hands + 1] = {hand = hand, position = position, target = found.target,
                        unit = found.unit, node = found.node}
                end
            else
                cached[hand] = nil
            end
        end
        local choice = Reach.choose(eye, hands)
        -- Probe: every PROBE_SECONDS, up to PROBE_LINES a session, what the
        -- stock search found along each hand. Reading it is how a worn check
        -- tells "nothing was in reach" from "the search never ran".
        if type(t) == "number" and (api.probe_lines or 0) < Reach.PROBE_LINES and t >= (api.probe_t or 0) then
            api.probe_t, api.probe_lines = t + Reach.PROBE_SECONDS, (api.probe_lines or 0) + 1
            local parts = {}
            for i = 1, #hands do
                parts[#parts + 1] = string.format("%s=%.2f", hands[i].hand,
                    Reach.distance(hands[i].position, hands[i].target) or -1)
            end
            mod:info("DARKTIDEVR_REACH probe found=%d %s chosen=%s", #hands,
                table.concat(parts, " "), choice and choice.hand or "none")
        end
        if not choice then claim, reach_target = nil, nil; return nil end
        for i = 1, #hands do
            if hands[i].hand == choice.hand then
                reach_target = {unit = hands[i].unit, node = hands[i].node, interactor = unit,
                    approach = choice.approach}
            end
        end
        -- One claim identity while the same hand keeps reaching the same unit,
        -- so the bindings hold the grip rather than re-taking it each frame.
        if not claim or claim.hand ~= choice.hand or claim.unit ~= reach_target.unit then
            claim = {hand = choice.hand, unit = reach_target.unit}
        end
        claim.approach = choice.approach
        local armed_key = choice.hand .. tostring(reach_target.unit)
        if not choice.approach and not logged[armed_key] then
            logged[armed_key] = true
            mod:info("DARKTIDEVR_REACH armed hand=%s distance_m=%.2f", choice.hand, choice.distance)
            -- The same pulse a foregrip or an armed holster gives: this hand's
            -- grip now does something other than its binding.
            if presentation.haptics and type(t) == "number" then
                pcall(presentation.haptics.pulse, choice.hand, "zone", t)
            end
        end
        return Reach.request({hand = choice.hand, approach = choice.approach}, claim)
    end

    -- The stock interactor's own choice, replaced by what the hand reaches.
    -- Returning it here keeps every later stock check (duration, interactee
    -- state, the ongoing-interaction tests) exactly as it is.
    function api.find(extension, unit, chosen)
        if not api.enabled() then return chosen end
        if not reach_target or reach_target.interactor ~= unit then return chosen end
        -- Only once the hand has arrived. While it is merely approaching, the
        -- claim exists so a grip pressed on the way in is held back, but the
        -- interaction target is still the game's own: otherwise standing with
        -- a hand loosely within 75 cm of a console would change what the
        -- ordinary interact button does, and what a tag picks, without the
        -- player having reached for anything.
        if reach_target.approach then return chosen end
        if not reach_target.unit or not Unit.alive(reach_target.unit) then return chosen end
        return reach_target.unit, reach_target.node
    end

    function api.sample(unit, active, t, support_request)
        -- A holster or two-hand claim owns the grip first: reaching for a door
        -- must not take the grip away from drawing a weapon.
        if support_request then claim, reach_target = nil, nil; return support_request end
        local ok, request = pcall(sample, unit, active, t)
        if not ok then
            -- Keep going. One bad frame during a load or a respawn used to
            -- switch the feature off for the rest of the session, which reads
            -- as "it stopped working" with one warning far up the log.
            failures = failures + 1
            claim, reach_target = nil, nil
            if failures <= 3 then
                mod:warning("DARKTIDEVR_REACH error=%s failures=%d",
                    tostring(request):sub(1, 160), failures)
            end
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
