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
local character = 'walking'
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
    ScriptUnit={has_extension=function() return {current_state_name=function() return character end} end}
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

    -- Objective devices consume the same stock columns, but `move` is a device
    -- axis here. Run the real minigame input method against both recorded sides.
    -- Minigame/animation/weapon endpoints are sinks, not real objective outcomes.
    PlayerCharacterStateMinigame={}
    method('extension_systems/character_state_machine/character_states/player_character_state_minigame',
        'PlayerCharacterStateMinigame._update_input =',
        '\nPlayerCharacterStateMinigame._is_minigame_active =')
    local axis_meta={__index=function(v,key)
        if key=='x' then return v[1] elseif key=='y' then return v[2] end
    end}
    setmetatable(Vector3,{__call=function(_,x,y,z) return setmetatable({x,y,z},axis_meta) end})
    Vector3.zero=function() return Vector3(0,0,0) end
    Vector3.equal=function(a,b) return a[1]==b[1] and a[2]==b[2] and a[3]==b[3] end
    local dodge=false
    Dodge={check=function() return dodge end}
    character='minigame'
    local columns={'action_one_hold','interact_hold','jump_held','action_two_pressed',
        'move_right','move_left','move_forward','move_backward'}
    client._frame,client._last_frame_acknowledged=0,0
    client._last_sent_frame=nil
    packets={}
    client._input_cache,client._send_array,client._action_lookup={},{},{}
    client._pack_unpack_action_to_network_type_index={}
    server._input_cache={}
    server._parsed_frame,server._received_frame,server._input_cache_size=0,0,11
    for i=1,11 do client._input_cache[i]={}; client._send_array[i]={}; server._input_cache[i]={} end
    for i,name in ipairs(columns) do
        client._action_lookup[name]=i
        if i>=5 then client._pack_unpack_action_to_network_type_index[name]=7 end
    end
    server._action_lookup=client._action_lookup
    client._yaw_index,client._pitch_index,client._roll_index=9,10,11
    server._yaw_index,server._pitch_index,server._roll_index=9,10,11
    client._parse_input=function(_,cache,input,index)
        for i=1,4 do cache[i][index]=input[columns[i]]==true end
        cache[5][index],cache[6][index]=math.max(input.x,0),math.max(-input.x,0)
        cache[7][index],cache[8][index]=math.max(input.y,0),math.max(-input.y,0)
    end
    local function device(input)
        local observed={actions={},axes={},animations={},weapons={}}
        local active={uses_action=function() return true end,
            action=function(_,primary,t) observed.actions[#observed.actions+1]={primary,t}; return primary end,
            is_completed=function() return false end,
            uses_joystick=function() return true end,
            on_axis_set=function(_,t,x,y) observed.axes[#observed.axes+1]={t,x,y} end,
            escape_action=function(_,cancel) return cancel end,
            blocks_weapon_actions=function() return observed.blocks==true end}
        return {_input_extension=input,_minigame=active,
            _previous_action_one_hold=false,_previous_interact_hold=false,
            _previous_jump_held=false,_previous_input=false,
            _is_wielding_minigame_device=function() return observed.wielded~=false end,
            _animation_extension={anim_event_1p=function(_,event) observed.animations[#observed.animations+1]=event end},
            _weapon_extension={update_weapon_actions=function(_,frame) observed.weapons[#observed.weapons+1]=frame end}},observed
    end
    local predicted,predicted_events=device(client_unit_input)
    local authoritative,server_events=device(server_unit_input)
    local cases={
        {action_one_hold=true,x=.4,y=-.7,primary=true},
        {action_one_hold=true,x=-.6,y=.2,primary=true},
        {x=0,y=0,primary=false},
        {interact_hold=true,x=-1,y=-1,primary=true},
        {x=1,y=0,primary=false},
        {jump_held=true,x=0,y=1,primary=true},
        {x=0,y=-1,primary=true,dodge=true}, -- Stock dodge leaves prior primary input alone.
        {jump_held=true,x=1,y=1,primary=true},
        {x=-1,y=0,primary=false,blocks=true},
        {action_two_pressed=true,x=.2,y=.3,primary=false,cancel=true},
        {x=0,y=0,primary=false,wielded=false,cancel=true},
    }
    for frame,case in ipairs(cases) do
        local t=frame*.02
        client:fixed_update(.02,t,frame,case,.25,.1,0)
        hand={yaw=frame*.8,pitch=-.4}
        rules.capture(client,frame)
        assert(rules.frames==7 and rules.failures==0,'Device state authored combat aim')
        client:update(); receive(packets[#packets])
        client._last_frame_acknowledged=frame
        for _,entry in ipairs({{predicted,predicted_events},{authoritative,server_events}}) do
            local state,events=entry[1],entry[2]
            state._input_extension:fixed_update('local',.02,t,frame)
            local yaw,pitch=state._input_extension:get_orientation()
            assert(yaw==.25 and pitch==.1,'Device view inherited hand combat aim')
            events.blocks,events.wielded=case.blocks,case.wielded
            dodge=case.dodge==true
            local prior_actions,prior_weapons=#events.actions,#events.weapons
            local cancelled=PlayerCharacterStateMinigame._update_input(state,t,frame,state._input_extension)
            assert(cancelled==(case.cancel==true),'Stock device cancellation changed')
            if case.wielded==false then
                assert(#events.actions==prior_actions and #events.weapons==prior_weapons,
                    'Missing device still consumed objective input')
            else
                assert(events.actions[#events.actions][1]==case.primary,'Stock device primary phase changed')
                local axes=events.axes[#events.axes]
                assert(axes[1]==t and axes[2]==case.x and axes[3]==case.y,
                    'Recorded objective axes were rotated by hand aim')
                assert(#events.weapons==prior_weapons+((case.cancel or case.blocks) and 0 or 1),
                    'Stock device weapon-action ownership changed')
            end
        end
    end
    assert(#predicted_events.animations==#server_events.animations)
    for i,event in ipairs(predicted_events.animations) do assert(event==server_events.animations[i]) end
    print('PASS: stock objective input holds, axes, cancel, dodge arbitration and weapon gates agree after recorded send/receive')
end
print('LIMIT: no engine serialization, live server, damage, movement or headset acceptance')
