-- Optional stock-source audit: executes actual Lua input buffering, send and
-- receive methods with an in-memory RPC sink. This is not a network/engine test.
-- Usage: luajit test-online-input-stock-contract.lua <stock-source-root>
local function method(path, first_marker, next_marker)
    local file = assert(io.open(arg[1] .. '/scripts/' .. path .. '.lua', 'r'))
    local source = file:read('*all'); file:close()
    local first = assert(source:find(first_marker, 1, true), first_marker)
    local last = assert(source:find(next_marker, first, true), next_marker)
    assert(loadstring(source:sub(first, last - 1), '@' .. path))()
end
HumanInputHandler, AuthoritativePlayerInputHandler = {}, {}
local human = 'managers/player/player_game_states/human_input_handler'
local authority = 'managers/player/player_game_states/authoritative_player_input_handler'
for _, names in ipairs({{'_buffer_index', 'pre_update'}, {'fixed_update', 'get_orientation'},
                       {'get_orientation', 'get'}, {'update', 'rpc_player_input_array_ack'}}) do
    method(human, 'HumanInputHandler.' .. names[1] .. ' =',
           '\nHumanInputHandler.' .. names[2] .. ' =')
end
method(authority, 'AuthoritativePlayerInputHandler.get_orientation =',
       '\nAuthoritativePlayerInputHandler.get =')
method(authority, 'AuthoritativePlayerInputHandler.rpc_player_input_array =',
       '\nAuthoritativePlayerInputHandler.rewind_ms =')
Log = {debug = function() end}
_debug = function() end
table.clear = function(t) for k in pairs(t) do t[k] = nil end end
local packets = {}
Managers = {state = {game_session = {
    can_send_session_bound_rpcs = function() return true end,
    send_rpc_server = function(_, name, player, first, offset, ...)
        assert(name == 'rpc_player_input_array' and player == 1)
        local columns, copy = {...}, {}
        for i, column in ipairs(columns) do
            copy[i] = {}; for j, v in ipairs(column) do copy[i][j] = v end
        end
        packets[#packets + 1] = {first = first, offset = offset, columns = copy}
    end,
}}}
-- Small ring deliberately forces wraparound; one representative action plus
-- the three stock orientation columns. Input parsing/engine packing are stubs.
local client = setmetatable({_frame = 0, _last_frame_acknowledged = 0,
    _input_buffer_size = 4, _send_buffer_size = 3, _is_server = false,
    _input_cache = {{}, {}, {}, {}}, _send_array = {{}, {}, {}, {}},
    _yaw_index = 2, _pitch_index = 3, _roll_index = 4,
    _player = {local_player_id = function() return 1 end},
    _parse_input = function(_, cache, input, index) cache[1][index] = input end,
}, {__index = HumanInputHandler})
local server = setmetatable({_received_frame = 0, _parsed_frame = 0,
    _input_cache_size = 4, _input_cache = {{}, {}, {}, {}},
    _yaw_index = 2, _pitch_index = 3, _roll_index = 4,
    _clock_handler = {frame_received = function() end},
}, {__index = AuthoritativePlayerInputHandler})
local function sample(frame)
    client:fixed_update(.02, frame * .02, frame, frame % 2 == 0,
                        frame * .1, frame * -.03, 0)
end
local function receive(packet)
    server:rpc_player_input_array('in-memory', 1, packet.first, packet.offset,
                                  unpack(packet.columns))
end
local function agrees(frame)
    local y, p, r = client:get_orientation(frame)
    local sy, sp, sr = server:get_orientation(frame)
    assert(y == sy and p == sp and r == sr, 'Frame orientation disagrees: ' .. frame)
    assert(server._input_cache[1][frame - server._parsed_frame] == (frame % 2 == 0))
end
sample(1); sample(2); client:update(); receive(packets[1])
agrees(1); agrees(2)
-- New frame resends unacknowledged history. A changed live orientation must
-- not rewrite the earlier fixed-frame aim during replay or resend.
sample(3); client:update(); receive(packets[2]); agrees(1); agrees(2); agrees(3)
receive(packets[1]); agrees(3) -- Old/duplicate packet cannot overwrite newer input.
client._last_frame_acknowledged = 3
sample(4); sample(5); client:update()
assert(packets[3].first == 4 and packets[3].offset == 1)
receive(packets[3]); agrees(4); agrees(5)
local count = #packets; client:update(); assert(#packets == count)
-- A send window gap causes the actual server method to reset its parsed base.
sample(6); sample(7); sample(8); sample(9); client:update()
assert(packets[4].first == 7)
receive(packets[4]); assert(server._parsed_frame == 6)
agrees(7); agrees(8); agrees(9)
local y, p, r = server:get_orientation(10)
local ly, lp, lr = server:get_orientation(9)
assert(y == ly and p == lp and r == lr, 'Missing frame should use latest received aim')
print('PASS: stock fixed-frame aim/action agreement, resend, duplicate, ring wrap, gap and missing-frame behavior')
print('LIMIT: no engine serialization, live server, damage, movement or headset acceptance')
