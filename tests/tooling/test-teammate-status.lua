-- Teammate status: state labels, constant angular size, bar order and clamps.
local Status=dofile(assert(arg[1]))
local function near(a,b,m) assert(math.abs(a-b)<1e-9,(m or 'mismatch')..': '..tostring(a)) end
assert(Status.state_label('knocked_down')=='DOWNED' and Status.state_label('netted')=='NETTED')
assert(Status.state_label('walking')==nil and Status.state_label(nil)==nil,'not disabled')
near(Status.metres_per_pixel(10),10*Status.METRES_PER_PIXEL_PER_METRE,'scales with distance')
near(Status.metres_per_pixel(20)/Status.metres_per_pixel(10),2,'constant angular size')
near(Status.metres_per_pixel(100),Status.MAX_DISTANCE*Status.METRES_PER_PIXEL_PER_METRE,'capped far away')
near(Status.metres_per_pixel(0.9),Status.MIN_DISTANCE*Status.METRES_PER_PIXEL_PER_METRE,'floored close by')
assert(Status.metres_per_pixel(0.5)==nil,'hidden when too near')
assert(Status.metres_per_pixel(0/0)==nil)
local bars=Status.bars({toughness=.4,health=50,max_health=200})
assert(#bars==2 and bars[1].id=='toughness' and bars[2].id=='health','toughness above health')
near(bars[1].fraction,.4); near(bars[2].fraction,.25)
bars=Status.bars({toughness=2,health=300,max_health=200})
assert(bars[1].fraction==1 and bars[2].fraction==1,'clamped')
assert(#Status.bars({health=10,max_health=0})==0 and #Status.bars(nil)==0)
-- The overlay anchor key belongs to the player, not to their place in an
-- unordered iteration: the cell shows a frame late, so a key that moves when
-- `pairs` re-orders draws one teammate's bars over another's head.
local function player_with(fields) local p = {}; for k, v in pairs(fields) do p[k] = v end; return p end
local by_account = player_with({account_id = function() return "acct-7" end, peer_id = function() return "peer-1" end})
assert(Status.anchor_key(by_account, "unitA") == "teammate_acct-7", "the account identifies the player")
local by_peer = player_with({peer_id = function() return "peer-9" end})
assert(Status.anchor_key(by_peer, "unitB") == "teammate_peer-9", "the peer is the fallback")
local plain = player_with({unique_id = "uid-3"})
assert(Status.anchor_key(plain, "unitC") == "teammate_uid-3", "a plain field is used when there is no accessor")
assert(Status.anchor_key(nil, "unitD") == "teammate_unitD", "no player object: the unit is stable enough")
local throws = player_with({account_id = function() error("no account yet") end, peer_id = function() return "peer-2" end})
assert(Status.anchor_key(throws, "unitE") == "teammate_peer-2", "an accessor that throws falls through")
-- The same player keeps its key whatever order it is seen in.
assert(Status.anchor_key(by_account, "unitA") == Status.anchor_key(by_account, "unitZ"),
    "the key must not depend on the unit when the player identifies itself")
-- Solo play is three bots, and a bot is added with no account id and the
-- *host's* peer id: asking for those before `unique_id` gave all three one
-- key, so two panels fought over one bot's head and the others had none.
local function bot(unique)
    return player_with({
        account_id = function() return nil end,
        peer_id = function() return "host-peer" end,
        unique_id = function() return unique end,
    })
end
local one, two, three = bot("host-peer:2:1"), bot("host-peer:3:1"), bot("host-peer:4:1")
local keys = {}
for _, b in ipairs({one, two, three}) do
    local key = Status.anchor_key(b, "bot_unit")
    assert(not keys[key], "two bots share the anchor key " .. key)
    keys[key] = true
end
assert(Status.anchor_key(one, "unitA") == "teammate_host-peer:2:1", "a bot is keyed by its unique id")
-- An id that arrives as the class method -- which is what `player.unique_id`
-- resolves to through the metatable -- is called, not stringified: every
-- player shares that one function address, so using it as the id would put
-- them all on one key. When nothing answers, the unit is what is left.
local shared_method = function() return nil end
local answers_nothing = setmetatable({}, {__index = {unique_id = shared_method, peer_id = shared_method,
    account_id = shared_method}})
assert(Status.anchor_key(answers_nothing, "unitF") == "teammate_unitF" and
    Status.anchor_key(answers_nothing, "unitG") == "teammate_unitG",
    "a player whose accessors answer nothing falls through to the unit, not to a shared function address")
-- And a method reached only through the metatable still identifies the player.
local inherited = setmetatable({}, {__index = {unique_id = function() return "uid-inherited" end}})
assert(Status.anchor_key(inherited, "unitH") == "teammate_uid-inherited", "an inherited accessor is called")

-- A display that used to switch itself off for the session. Both of these
-- latched on the FIRST error, and the teammate nameplates had no `destroy` at all, so one transient nil -- a unit
-- gone mid-draw, a level change caught at the wrong moment -- took the
-- display out until the game was restarted. Three in a row is a broken
-- display; one is a level change.
local warnings = 0
local stub_mod = {
    get = function(self, key) return true end,
    warning = function() warnings = warnings + 1 end,
    info = function() end,
    echo = function() end,
}
-- `attempts` is the probe: the real draw asks for the eye pose before it
-- reaches for anything the test has no double for, so a bump means the
-- display genuinely tried this frame and no bump means it has stopped.
local attempts = 0
local presentation = {mode = 1, hand_overlay = {},
    eye_pose = function() attempts = attempts + 1; return {} end}
local api = Status.install(stub_mod, presentation)
-- Drives the real failure path rather than an early return: the body runs and
-- reaches for something the test has no double for, which is exactly the
-- shape of the transient faults this counts.
local function fail_once() api.draw({}, {}) end
fail_once()
assert(warnings == 1, "the first failure is reported, not swallowed: " .. warnings)
fail_once()
assert(warnings == 2, "and the display is still trying after one failure")
fail_once()
assert(warnings == 3, "the third failure in a row is the one that stops it")
fail_once()
assert(warnings == 3, "after three in a row it stops calling, so nothing more is reported")
-- The re-arm. This is the whole point: without it the display is gone for the
-- session.
assert(type(api.destroy) == "function", "a level load needs a destroy to re-arm the display")
api.destroy()
fail_once()
assert(warnings == 4, "a level load forgives the count and the display tries again")

-- A good frame clears the RUN but not the total. Without the run resetting, a
-- display that fails every other frame -- which is what an intermittent nil
-- looks like -- stops after three bad frames spread over a whole level, and a
-- display that has already recovered is judged on failures it came back from.
-- Warnings cannot see this: the gate gives the same count either way. What
-- can is whether the display is still TRYING, which is what `attempts` says.
api.destroy()
warnings, attempts = 0, 0
fail_once()
fail_once()
presentation.mode = 2       -- the draw returns early: a frame that did not fail
api.draw({}, {})
presentation.mode = 1
assert(attempts == 2, "a good frame is not an attempt at the failing path")
fail_once()
fail_once()
local before = attempts
fail_once()
assert(attempts == before + 1,
    "two failures, a good frame, then two more: the run reset, so it is still trying")
-- And the total still stops it, or an every-other-frame fault would warn for
-- ever and never be judged broken.
api.destroy()
attempts = 0
for _ = 1, 40 do
    presentation.mode = 2; api.draw({}, {}); presentation.mode = 1
    fail_once()
end
before = attempts
fail_once()
assert(before >= 20 and attempts == before,
    "a fault that fails every other frame is stopped by the total, not the run: " ..
    before .. " attempts")
-- Keep both (user, 17 October): the team panel is not hidden, and the game's
-- own mission nameplate above a teammate is made transparent while the option
-- is on, after its update (which sets it opaque), and left alone when off.
do
    local on, hooks, required = true, {}, {}
    local hook_mod = {get = function() return on end, warning = function() end, info = function() end,
        hook = function(_, target, name, fn) hooks[#hooks + 1] = {target = target, name = name, fn = fn} end,
        hook_require = function(_, path, fn) required[path] = fn end}
    local view = {mode = 1}
    Status.install(hook_mod, view)
    for _, h in ipairs(hooks) do
        assert(h.target ~= "HudElementTeamPlayerPanel", "the team panel is hidden again")
    end
    local template = {update_function = function(_, _, widget) widget.alpha_multiplier = 1; return "stock" end}
    local install = assert(required["scripts/ui/hud/elements/world_markers/templates/world_marker_template_nameplate_combat"],
        "the mission nameplate template is not hooked")
    install(template)
    local hook = hooks[#hooks]
    assert(hook.target == template and hook.name == "update_function")
    local widget = {}
    assert(hook.fn(template.update_function, nil, nil, widget) == "stock", "the stock result is kept")
    assert(widget.alpha_multiplier == 0, "the stock nameplate still shows with the option on")
    on = false
    hook.fn(template.update_function, nil, nil, widget)
    assert(widget.alpha_multiplier == 1, "the stock nameplate is hidden with the option off")
    on, view.mode = true, 2
    hook.fn(template.update_function, nil, nil, widget)
    assert(widget.alpha_multiplier == 1, "the stock nameplate is hidden outside gameplay")
end
print('teammate_status=pass state_label angular_size bars clamps team_panel_kept stock_nameplate_hidden')
