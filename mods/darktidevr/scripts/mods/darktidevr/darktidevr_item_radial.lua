-- Item radial (todo-2026-09-14: "Holding the carried-items button shows a
-- radial at the hand; flick the stick to pick scanner, stim or carried item").
-- Pure: no engine calls.
--
-- Stock, the carried-items control cycles through what you have, so reaching a
-- particular item means pressing it until the right one comes up. Held, this
-- shows the three as sectors at the off hand and the stick picks one directly;
-- released, it wields what was picked.
--
-- The control's own action fires on *press*, so the radial cannot simply watch
-- the control: it would cycle an item before the player had chosen one, and
-- its Device sector could never fire, because that action's mask is inside the
-- control's own. Instead the radial takes the control through the bindings'
-- contextual claim, the same one the virtual holsters use for the grips, with
-- the "unbound" action: for that press the control does nothing of its own,
-- and the pick is delivered on release as a one-frame press through the
-- forced-action channel. Released with nothing picked, it delivers the
-- control's own stock cycle instead, so a plain tap still does what it did.
-- (docs/phase1/item-radial-2026-09-16.md records the first attempt.)
--
-- It overlaps the virtual holsters, which put the same three items on the
-- body. It is not redundant while those are withheld from release, and the two
-- run together: the holsters are reached for, this is chosen, and a holster or
-- two-hand claim always takes the slot first.
local Radial = {}

-- The stock wield inputs behind each sector, in the bindings' catalogue.
Radial.OPTIONS = {
    {id = "pocketable", mask = 65536, label = "Item"},
    {id = "stim", mask = 131072, label = "Stim"},
    {id = "device", mask = 262144, label = "Device"},
}
-- The stick has to leave the centre by this much to pick anything.
Radial.DEADZONE = 0.5
-- The carried-items control's own action, delivered on a release with nothing
-- picked: the claim swallows the press, so a plain tap must be given back its
-- stock cycle, or turning the option on would take that away.
Radial.CYCLE_MASK = 786432
-- The actions the carried-items control may be carrying, most specific first:
-- a player who binds the two item actions apart still gets the radial on
-- whichever control carries either.
Radial.CONTROL_ACTIONS = {"pocketable_device", "cycle_pocketables", "device"}
-- Sectors are placed from straight up, clockwise.

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end

-- Which sector a stick position picks, or nil inside the deadzone. Pure.
function Radial.select(x, y, count)
    count = count or #Radial.OPTIONS
    if not finite(x) or not finite(y) or count < 1 then return nil end
    if math.sqrt(x * x + y * y) < Radial.DEADZONE then return nil end
    local angle = math.atan2(x, y)
    if angle < 0 then angle = angle + math.pi * 2 end
    local step = math.pi * 2 / count
    return math.floor(angle / step + 0.5) % count + 1
end

-- Where a sector's label sits, in metres from the radial's centre. Pure.
function Radial.label_offset(index, count, radius)
    count = count or #Radial.OPTIONS
    if type(index) ~= "number" or index < 1 or index > count then return nil end
    local angle = (index - 1) * math.pi * 2 / count
    return math.sin(angle) * radius, math.cos(angle) * radius
end

-- A closed radial. Pure.
function Radial.closed() return {open = false} end

-- The state after a frame, driven by the bindings' report of the claim
-- (`grip`: pressed, held, released, cancelled, as `support_grip`) and the
-- stick. Returns the new state and the mask to deliver, if any.
--
-- Opening needs the claim to have been *taken* (a fresh press the bindings
-- accepted). A pick is delivered on the flick itself: the frame the stick
-- enters a sector (worn, 16 September: waiting for the release turned a
-- natural flick-and-press into the tap's stock cycle, a weapon switch). If
-- the stick was already hard over at the press (a tap mid snap-turn), it
-- must pass through neutral once first, so no sector the player never saw
-- is picked. A further flick to another sector delivers that one too. The
-- release then delivers nothing; a release with no pick at all is a tap and
-- gives back the stock cycle. A cancelled claim delivers nothing. Pure.
function Radial.step(state, grip, x, y)
    state = type(state) == "table" and state or Radial.closed()
    if type(grip) ~= "table" or grip.cancelled then return Radial.closed(), nil end
    if grip.pressed then
        return {open = true, index = nil, neutral_seen = Radial.select(x, y) == nil, delivered = false}, nil
    end
    if grip.released then
        if not state.open then return Radial.closed(), nil end
        if state.delivered then return Radial.closed(), nil end
        -- A tap: the stock cycle, one frame later than stock would have.
        return Radial.closed(), Radial.CYCLE_MASK
    end
    if not grip.held or not state.open then return Radial.closed(), nil end
    local picked = Radial.select(x, y)
    local neutral_seen = state.neutral_seen or picked == nil
    local index, delivered, deliver = state.index, state.delivered, nil
    if neutral_seen and picked and picked ~= index then
        index, delivered, deliver = picked, true, Radial.OPTIONS[picked].mask
    end
    return {open = true, index = index, neutral_seen = neutral_seen, delivered = delivered}, deliver
end

-- Whether the radial gives the claim slot to another feature's request this
-- frame. The slot carries one request; two-hand support offers one every
-- frame a gun is out, wherever the off hand is, so yielding to any request
-- closed the radial a moment after it opened with a ranged weapon wielded
-- and left the stick to its stock flick, the weapon switch (worn, 17
-- September). It yields only to a request that wants the hand now (acquire),
-- whose hand is on its way (approach), or whose claim is already held
-- (other_holds: replacing a held grip's request would cancel the grip). Pure.
function Radial.yields(request, other_holds)
    if type(request) ~= "table" then return request ~= nil and request ~= false end
    return request.acquire == true or request.approach == true or other_holds == true
end

-- Engine side. The pure part above is what the tests exercise.
Radial.TEST_FLAG = "./../mods/darktidevr/darktidevr_item_radial_test.flag"
Radial.RADIUS = 0.055
-- Sharper and brighter (user, 17 September worn: "low resolution and too
-- hard to see before you switch to it"): the panel's scale is as fine as one
-- overlay cell allows (the labels reach 5.5 cm from the centre and the cell
-- is 477 px wide at a 1908-wide eye target), the letters a little larger
-- (1.5 cm, were 1.4), the unpicked labels near white instead of grey.
Radial.LABEL_PX = 44
Radial.PIXEL_METRES = 0.00034
Radial.LABEL_COLOR = {235, 240, 240, 230}
Radial.PICKED_COLOR = {255, 255, 205, 90}
Radial.FORWARD = 0.06

function Radial.install(mod, presentation, observation)
    local api = {}
    local state, claim, failures, opened = Radial.closed(), nil, 0, 0
    -- Whether last frame's request in the slot was the radial's.
    local ours_last = false

    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        -- Every 300 calls (about five seconds at the input rate): a failed open
        -- on the main thread each poll is where these modules' spikes came
        -- from (docs/LUA-FRAME-PROFILE-2026-09-16.md).
        test_poll = 300
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Radial.TEST_FLAG, "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end

    function api.enabled()
        return mod:get("vr_item_radial") == true or test_flag()
    end

    -- The button carrying the carried-items action, or nil.
    local function control_id()
        local bindings = presentation.controller_bindings
        if not bindings or not bindings.controls_for_action then return nil end
        for _, action in ipairs(Radial.CONTROL_ACTIONS) do
            for _, id in ipairs(bindings.controls_for_action(action)) do
                if presentation.controller_bindings_module.control_bit(id) then return id end
            end
        end
        return nil
    end

    -- Before the bindings sample. Returns the request for the slot, and
    -- whether it is the radial's. A holster, two-hand or reach claim takes the
    -- slot first; ineligibility closes the radial without delivering, so a pick
    -- made before a menu or a downing never fires later out of nowhere.
    function api.sample(active, support_request)
        local bindings = presentation.controller_bindings
        local grip = bindings and bindings.support_grip
        local other_holds = type(grip) == "table" and (grip.held == true or grip.pressed == true) and not ours_last
        if not active or not api.enabled() or Radial.yields(support_request, other_holds) then
            state, claim = Radial.closed(), nil
            return support_request, false
        end
        local ok, id = pcall(control_id)
        if not ok or not id then
            state, claim = Radial.closed(), nil
            return support_request, false
        end
        -- One owner table for the whole hold: a changed owner cancels a claim.
        if not claim or claim.control ~= id then claim = {control = id} end
        return {control = id, owner = claim, action = "unbound", acquire = true, retain = true}, true
    end

    -- Whether the stick belongs to the radial this frame.
    function api.open() return state.open == true end

    -- After the bindings sample: the claim's edges drive the radial, and a
    -- pick is delivered as a one-frame press into the next sample.
    function api.finish(grip, ours, stick_x, stick_y, stick_usable)
        local bindings = presentation.controller_bindings
        ours_last = ours == true
        if not ours or not grip then
            state = Radial.closed()
            return
        end
        local x, y = stick_x, stick_y
        if not stick_usable then x, y = 0, 0 end
        local deliver
        state, deliver = Radial.step(state, grip, x, y)
        if grip.pressed and opened < 10 then
            opened = opened + 1
            mod:info("DARKTIDEVR_ITEM_RADIAL open control=%s entries=%d", tostring(claim and claim.control), opened)
        end
        if deliver and bindings then
            bindings.forced = bit.bor(tonumber(bindings.forced) or 0, deliver)
            mod:info("DARKTIDEVR_ITEM_RADIAL wield mask=%d", deliver)
        end
    end

    -- Drawn at the off hand, in the draw pass, only while that hand tracks.
    local function draw(world)
        if not state.open or not api.enabled() then return end
        local side = presentation.hand_side and presentation.hand_side("support")
        if not side or not observation[side .. "_grip_tracking_live"] then return end
        local grip, grip_rotation = presentation.weapon_grip_target("support")
        if not grip or not grip_rotation then return end
        local centre = grip + Quaternion.forward(grip_rotation) * Radial.FORWARD
        local overlay = presentation.hand_overlay
        local canvas = overlay and overlay.canvas(world, "item_radial", centre, Radial.PIXEL_METRES)
        if not canvas then return end
        for index, option in ipairs(Radial.OPTIONS) do
            local x, y = Radial.label_offset(index, #Radial.OPTIONS, Radial.RADIUS)
            local chosen = state.index == index
            canvas.text(option.label, Radial.LABEL_PX, x, y, chosen and Radial.PICKED_COLOR or Radial.LABEL_COLOR)
        end
    end

    function api.draw(world)
        local ok, err = pcall(draw, world)
        if not ok then
            failures = failures + 1
            if failures <= 3 then
                mod:warning("DARKTIDEVR_ITEM_RADIAL draw_error=%s", tostring(err):sub(1, 160))
            end
        end
    end

    function api.destroy() state, claim = Radial.closed(), nil end
    return api
end

return Radial
