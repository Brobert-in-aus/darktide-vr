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
print('teammate_status=pass state_label angular_size bars clamps')
