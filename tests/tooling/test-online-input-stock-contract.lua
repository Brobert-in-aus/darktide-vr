-- Optional stock-source audit: executes actual Lua input buffering, send and
-- receive methods with an in-memory RPC sink. This is not a network/engine test.
-- Usage: luajit test-online-input-stock-contract.lua <stock-source-root>
-- Optional trailing args: <online-rules.lua> <gameplay-context.lua> exercise
-- the real VR adapter through these same stock send/receive/history methods.
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
local rules, hand, owns, expected = nil, nil, false, {}
local client_unit_input, server_unit_input
if arg[2] then
    assert(arg[3], 'The VR adapter check also requires gameplay-context.lua')
    local names={'move_right','move_left','move_forward','move_backward'}
    client._input_cache,client._send_array,server._input_cache={},{},{}
    for i=1,8 do client._input_cache[i]={}; client._send_array[i]={}; server._input_cache[i]={} end
    client._yaw_index,client._pitch_index,client._roll_index=6,7,8
    server._yaw_index,server._pitch_index,server._roll_index=6,7,8
    server._input_cache_size=8
    client._action_lookup={}
    client._pack_unpack_action_to_network_type_index={}
    for i,name in ipairs(names) do
        client._action_lookup[name]=i+1
        client._pack_unpack_action_to_network_type_index[name]=7
    end
    client._action_lookup.action_one_hold=1
    server._action_lookup=client._action_lookup
    method(human,'HumanInputHandler.get =','\nHumanInputHandler._parse_input =')
    method(authority,'AuthoritativePlayerInputHandler.get =',
        '\nAuthoritativePlayerInputHandler.rpc_player_input_array =')
    HumanUnitInput={}
    method('extension_systems/input/human_unit_input','HumanUnitInput.fixed_update =',
        '\nHumanUnitInput.had_received_input =')
    client_unit_input=setmetatable({_input_handler=client},{__index=HumanUnitInput})
    server_unit_input=setmetatable({_input_handler=server},{__index=HumanUnitInput})
    client._parse_input=function(_,cache,input,index)
        cache[1][index]=input
        cache[2][index],cache[3][index],cache[4][index],cache[5][index]=.4,0,1,0
    end
    local player=client._player
    player.player_unit='local'; player.input_handler=client
    Managers.player={local_player=function() return player end}
    Managers.ui={using_input=function() return owns end}
    -- This proves transport of the range-authored sample in an in-memory
    -- remote pipeline. Production still gates actual remote mission admission.
    Managers.state.game_session.is_server=function() return true end
    Unit={alive=function(unit) return unit=='local' end}
    ScriptUnit={has_extension=function() return {current_state_name=function() return 'walking' end} end}
    Vector3=setmetatable({x=function(v) return v[1] end,y=function(v) return v[2] end},
        {__call=function(_,x,y,z) return {x,y,z} end})
    Quaternion={yaw=function(q) return q.yaw end,pitch=function(q) return q.pitch end,
        inverse=function(q) return -q end,
        rotate=function(q,v) return {math.cos(q)*v[1]-math.sin(q)*v[2],
            math.sin(q)*v[1]+math.cos(q)*v[2],v[3]} end}
    Network={pack_unpack=function(kind,value)
        assert(kind==7 and value>=0 and value<=1)
        return math.floor(value*10000+.5)/10000 -- Deliberately substitute engine packing.
    end}
    package.preload['scripts/settings/player_character/player_orientation_settings']=function()
        return {default={min_pitch=-math.pi*.45,max_pitch=math.pi*.45}}
    end
    local selector={_player_orientation_class=function(self) return self._default_player_orientation end}
    local mod={get=function() return true end,info=function() end,warning=function() end,
        hook_require=function(_,_,callback) callback(selector) end,
        hook=function(_,class,name,callback)
            local original=class[name]; class[name]=function(...) return callback(original,...) end
        end}
    rules=dofile(arg[2]).install(mod,{mode=1,gameplay_context=dofile(arg[3]),
        flat_movement_rotation=function(yaw) return yaw end,
        controller_aim_target=function() return 'unused_position',hand end},
        {authoring_enabled=true,gameplay_input_active=true},function() return 'shooting_range' end)
    selector._player_orientation_class({_player=player,_default_player_orientation={}})
end
local function sample(frame)
    client:fixed_update(.02, frame * .02, frame, frame % 2 == 0,
                        frame * .1, frame * -.03, 0)
    if rules then
        hand=frame~=5 and {yaw=frame*.4,pitch=frame*.07} or nil
        owns=frame==3 -- Mix UI-owned and tracking-unavailable fallback frames into history.
        rules.capture(client,frame)
        local index=client:_buffer_index(frame)
        expected[frame]={}
        for i=1,8 do expected[frame][i]=client._input_cache[i][index] end
        local yaw=expected[frame][6]
        assert(math.abs(yaw-frame*((owns or not hand) and .1 or .4))<1e-12)
        -- Resend/receive/replay happen with a different live pose and UI state.
        hand={yaw=-99,pitch=-99}; owns=false
    end
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
    if rules then
        for _,unit_input in ipairs({client_unit_input,server_unit_input}) do
            unit_input:fixed_update('local',.02,frame*.02,frame)
            local uy,up,ur=unit_input:get_orientation()
            assert(uy==expected[frame][6] and up==expected[frame][7] and ur==expected[frame][8])
            local move=unit_input:get('move')
            assert(move[1]==expected[frame][2]-expected[frame][3] and
                move[2]==expected[frame][4]-expected[frame][5])
            assert(unit_input:get('action_one_hold')==expected[frame][1])
        end
        for i=1,8 do
            assert(client._input_cache[i][client:_buffer_index(frame)]==expected[frame][i])
            assert(server._input_cache[i][frame-server._parsed_frame]==expected[frame][i],
                'VR action/movement/aim history disagrees: '..frame..' column '..i)
        end
    end
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
if rules then
    assert(rules.frames==7 and rules.failures==0,'Transport must not resample current hand pose')
    print('PASS: real VR adapter keeps action/movement/aim columns paired across stock replay, including UI/tracking fallback frames')
end
print('LIMIT: no engine serialization, live server, damage, movement or headset acceptance')
