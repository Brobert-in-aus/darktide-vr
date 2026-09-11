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
    Vector3=setmetatable({x=function(v) return v[1] end,y=function(v) return v[2] end,z=function(v) return v[3] end,
        dot=function(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end},
        {__call=function(_,x,y,z) return {x,y,z} end})
    -- The adapter derives yaw/pitch/roll from the forward and up vectors of a
    -- yaw/pitch/roll rotation; stub the same three axes as the policy test.
    Quaternion={yaw=function(q) return q.yaw end,pitch=function(q) return q.pitch end,
        from_yaw_pitch_roll=function(y,p,r) return {yaw=y,pitch=p,roll=r} end,
        forward=function(q) return {-math.sin(q.yaw)*math.cos(q.pitch),math.cos(q.yaw)*math.cos(q.pitch),math.sin(q.pitch)} end,
        right=function(q) assert(q.roll==0); return {math.cos(q.yaw),math.sin(q.yaw),0} end,
        up=function(q)
            local s,c=math.sin(q.roll or 0),math.cos(q.roll or 0)
            return {math.cos(q.yaw)*s+math.sin(q.yaw)*math.sin(q.pitch)*c,
                math.sin(q.yaw)*s-math.cos(q.yaw)*math.sin(q.pitch)*c,math.cos(q.pitch)*c}
        end,
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

    do
        -- Execute the real extension-manager/holder/base replay dispatch. The
        -- component correction itself is supplied; replay reads recorded input.
        ExtensionManager,ExtensionSystemHolder,ExtensionSystemBase={},{},{}
        method('foundation/managers/extension/extension_manager','local TEMP_SYSTEM_MAP =',
            '\nExtensionManager.registered_level_units =')
        method('foundation/managers/extension/extension_system_holder','local TEMP_SYSTEM_LIST =',
            '\nExtensionSystemHolder.hot_join_sync =')
        method('foundation/managers/extension/extension_system_base',
            'ExtensionSystemBase.unit_server_correction_occurred =','\nExtensionSystemBase.hot_join_sync =')
        local correction={supplied=true}
        local corrected,replayed,resets=0,{},0
        Script={temp_byte_count=function() return 42 end,set_temp_byte_count=function(count)
            assert(count==42); resets=resets+1
        end}
        hand=setmetatable({}, {__index=function() error('Replay read current hand tracking') end})
        local consumer={fixed_update=function(_,unit,dt,t,frame,context)
            assert(unit=='local' and dt==.02 and t==frame*.02 and corrected==1)
            assert(context.resimulate_from_frame==7 and context.resimulate_to_frame==9)
            assert(client_unit_input._frame==frame,'Input system did not run before simulation consumer')
            local yaw,pitch,roll=client_unit_input:get_orientation()
            local recorded=expected[frame]
            local movement=client_unit_input:get('move')
            assert(yaw==recorded[6] and pitch==recorded[7] and roll==recorded[8])
            assert(movement[1]==recorded[2]-recorded[3] and movement[2]==recorded[4]-recorded[5])
            assert(client_unit_input:get('action_one_hold')==recorded[1])
            replayed[#replayed+1]=frame
        end,server_correction_occurred=function(_,unit,first,last,components)
            assert(unit=='local' and first==7 and last==9 and components==correction)
            corrected=corrected+1
        end}
        local function system(name,extension)
            return setmetatable({NAME=name,_fixed_update_extensions={['local']=extension},
                _unit_to_extension_map={['local']=extension}}, {__index=ExtensionSystemBase})
        end
        local inputs=system('input_system',client_unit_input)
        local simulation=system('simulation_system',consumer)
        local unrelated=system('unrelated_system',{fixed_update=function() error('Replayed unrelated extension') end,
            server_correction_occurred=function() error('Corrected unrelated extension') end})
        local holder=setmetatable({_system_update_context={fixed_frame=9},_fixed_time_step=.02,
            _systems={unrelated,simulation,inputs},_num_systems=3,
            _update_lists={fixed_update={inputs,unrelated,simulation}}}, {__index=ExtensionSystemHolder})
        local manager=setmetatable({_extension_system_holder=holder,
            _units={['local']={input_extension=client_unit_input,simulation_extension=consumer},empty={}},
            _extension_to_system_map={input_extension='input_system',simulation_extension='simulation_system'}},
            {__index=ExtensionManager})
        local packet_count=#packets
        manager:fixed_update_resimulate_unit('local',7,correction)
        assert(table.concat(replayed,',')=='7,8,9' and corrected==1 and resets==6)
        assert(holder._system_update_context.fixed_frame==9)
        assert(rules.frames==7 and rules.failures==0 and #packets==packet_count,
            'Replay recaptured input or sent another packet')
        agrees(7); agrees(8); agrees(9)
        -- Both manager maps and holder lists must be cleared between owners.
        manager:fixed_update_resimulate_unit('empty',8,{})
        assert(#replayed==3 and corrected==1 and resets==6,'Replay retained the prior unit systems')
        print('PASS: actual stock replay dispatch follows recorded input order/frames without tracking recapture or cross-unit system leakage')

        -- Stock correction boundary with a deliberately small supplied schema.
        -- Scalar/boolean/array component restore is real Lua; engine game-object
        -- decoding, vector/quaternion userdata and simulation remain substitutes.
        local data_class={}
        local snapshot={frame=6,remainder=.004,frame_time=.02,
            fields={'value',2,'flag',false,'entries',{9}}}
        local field_reads,correction_events,correction_frames,action_corrections=0,0,0,0
        local acknowledgements,panics={},{}
        local boundary_environment={PlayerUnitDataExtension=data_class,
            FRAME_INDEX_FIELD='frame',REMAINDER_TIME_FIELD='remainder',FRAME_TIME_FIELD='frame_time',
            _game_object_field=function(session,id,field) assert(session=='session' and id==44); return snapshot[field] end,
            NETWORK_NAME_ID_TO_FIELD_ID={value=1,flag=2,entries=3},
            FIELD_NETWORK_LOOKUP={{'test','value','number',nil,'float'},
                {'test','flag','boolean'},{'test','entries','array'}},
            NUMBER_NETWORK_TYPE_TOLERANCES={default=.001},FIXED_FRAME_OFFSET_NETWORK_TYPES={},
            info=function() end,
            GameSession={game_object_fields_array=function(session,id,target)
                assert(session=='session' and id==44); field_reads=field_reads+1
                for i,value in ipairs(snapshot.fields) do target[i]=value end
                return #snapshot.fields
            end},
            Managers={state={extension=manager},telemetry_reporters={reporter=function(_,name)
                assert(name=='mispredict')
                return {register_event=function() correction_events=correction_events+1 end,
                    register_frame=function() correction_frames=correction_frames+1 end}
            end}}}
        local function boundary_method(first_marker,last_marker)
            local file=assert(io.open(arg[1]..'/scripts/extension_systems/unit_data/player_unit_data_extension.lua','r'))
            local source=file:read('*all'); file:close()
            local first=assert(source:find(first_marker,1,true)); local last=assert(source:find(last_marker,first,true))
            local chunk=assert(loadstring(source:sub(first,last-1)))
            setfenv(chunk,setmetatable(boundary_environment,{__index=_G})); chunk()
        end
        boundary_method('PlayerUnitDataExtension._read_server_unit_data_state =','\nreturn PlayerUnitDataExtension')
        boundary_method('PlayerUnitDataExtension._copy_components =','\nPlayerUnitDataExtension.update =')
        method(human,'HumanInputHandler.frame_parsed =','\nHumanInputHandler.frame_acknowledged =')
        method(human,'HumanInputHandler.set_in_panic =','\nreturn HumanInputHandler')
        client._last_frame_parsed=0
        client._client_clock_handler={frame_parsed=function(_,frame,remainder,frame_time)
            assert(remainder==.004 and frame_time==.02); acknowledgements[#acknowledgements+1]=frame
        end,set_in_panic=function(_,value) panics[#panics+1]=value end}
        local data=setmetatable({_server_data_state_game_object_id=44,_game_session='session',
            _state_cache_size=4,_player={input_handler=client},_last_received_frame=5,_last_fixed_frame=9,
            _components={test={}},_rollback_components={test={}},_component_blackboard={},
            _component_config={test={value={type='number'},flag={type='boolean'},entries={type='array'}}},
            _game_object_return_table={},_time_since_last_mispredict=3,_unit='local',is_resimulating=false,
            _action_input_extension={mispredict_happened=function(_,frame,session,id)
                assert(frame==6 and session=='session' and id==44); action_corrections=action_corrections+1
            end}}, {__index=data_class})
        for i=1,4 do data._components.test[i]={value=1,flag=true,entries={__data={3,4,5}}} end
        correction=data._rollback_components
        corrected,replayed,resets=0,{},0
        local consume=consumer.fixed_update
        consumer.fixed_update=function(...)
            assert(data.is_resimulating and data._component_index==3 and data._component_blackboard.index==3)
            return consume(...)
        end
        data:_read_server_unit_data_state(20)
        assert(table.concat(replayed,',')=='7,8,9' and corrected==1 and action_corrections==1)
        assert(correction_events==3 and correction_frames==1 and not data.is_resimulating)
        assert(data._last_received_frame==6 and data._time_since_last_mispredict==0)
        for _,index in ipairs({2,3}) do
            local component=data._components.test[index]
            assert(component.value==2 and component.flag==false and #component.entries.__data==1 and component.entries.__data[1]==9)
        end
        assert(data._components.test[1].value==1 and data._components.test[4].flag==true)
        assert(correction.test.value==1 and correction.test.flag==true and correction.test.entries[1]==9)
        assert(acknowledgements[1]==6 and client._last_frame_acknowledged==6)
        local before_reads=field_reads
        data:_read_server_unit_data_state(21) -- Duplicate correction does not replay or acknowledge again.
        snapshot.frame=5; data:_read_server_unit_data_state(22)
        assert(field_reads==before_reads and #acknowledgements==1 and correction_frames==1)
        snapshot.frame=7; data:_read_server_unit_data_state(23) -- Matching corrected next state.
        assert(correction_frames==1 and #replayed==3 and acknowledgements[2]==7)
        assert(data._last_received_frame==7 and client._last_frame_acknowledged==7)
        -- Out-of-window snapshots update the stock clock/panic state without
        -- decoding components or overwriting a newer ring slot.
        for _,case in ipairs({{frame=11,fixed=9,behind=true},{frame=5,fixed=9,behind=false}}) do
            data._last_received_frame=0; data._last_fixed_frame=case.fixed; data._in_panic=false
            client._last_frame_parsed=0; snapshot.frame=case.frame
            local reads=field_reads
            data:_read_server_unit_data_state(30)
            assert(field_reads==reads and data._in_panic and data._panic_is_behind==case.behind)
            assert(client._in_panic and panics[#panics]==true and acknowledgements[#acknowledgements]==case.frame)
            assert(correction_frames==1 and #replayed==3)
        end
        snapshot.frame=7; data:_read_server_unit_data_state(31)
        assert(not data._in_panic and not client._in_panic and panics[#panics]==false)
        assert(correction_frames==1 and rules.frames==7 and rules.failures==0 and #packets==packet_count)
        print('PASS: stock correction boundary restores supplied scalar/array state, rejects duplicates and protects the ring from future/expired snapshots')
    end

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
if arg[2] then
    -- Zero synthetic release edges do not mean a stock action is cancelled:
    -- several real templates finish their release sequence on held=false.
    local parser={}
    local function text(path)
        local f=assert(io.open(arg[1]..'/scripts/'..path..'.lua','r'))
        local s=f:read('*all'); f:close(); return s
    end
    local parser_source=text('extension_systems/action_input/action_input_parser')
    local a=assert(parser_source:find('ActionInputParser._evaluate_element =',1,true))
    local b=assert(parser_source:find('\nActionInputParser._progress_input_sequence =',a,true))
    setfenv(assert(loadstring(parser_source:sub(a,b-1))),setmetatable({ActionInputParser=parser,ELEMENT_START_T=3},{__index=_G}))()
    local function inputs(path,name)
        local s=text(path)
        local first=assert(s:find('local '..name..' = {}',1,true))
        local last=assert(s:find('\ntable.add_missing(',first,true))
        return setfenv(assert(loadstring(s:sub(first,last-1)..'\nreturn '..name..'.action_inputs')),
            setmetatable({wield_inputs={}},{__index=_G}))()
    end
    local melee=inputs('settings/equipment/weapon_templates/default_melee_action_input_setup','default_melee_action_input_setup')
    local pocket=inputs('settings/equipment/weapon_templates/pocketables/settings_templates/pocketables_template_settings','pocketables_template_settings')
    local bindings_path=arg[2]:gsub('darktidevr_online_rules.lua$','darktidevr_controller_bindings.lua')
    local mapper_module=dofile(bindings_path)
    local settings={}
    local mod={get=function(_,key) return settings[key] end}
    local mapper=mapper_module.install(mod)
    bit=require('bit')
    mapper.sample(true,0,0,0,true,1,'combat')
    local _,held=mapper.sample(true,5,0,0,true,1,'combat')
    assert(held==5)
    settings.vr_bind_right_trigger='unbound'; settings.vr_bind_right_grip='unbound'
    mod.on_setting_changed('vr_bind_right_trigger')
    local pressed,cancelled_held,released=mapper.sample(true,5,0,0,true,1,'combat')
    assert(pressed==0 and cancelled_held==0 and released==0)
    local raw={action_one_pressed=false,action_one_hold=false,action_one_release=false,
        weapon_extra_pressed=false,weapon_extra_hold=false,weapon_extra_release=false}
    local cases={melee.light_attack.input_sequence[1],melee.heavy_attack.input_sequence[2],
        melee.attack_release.input_sequence[1],pocket.aim_give_release.input_sequence[1]}
    for _,config in ipairs(cases) do
        local failed,completed=parser:_evaluate_element(config,raw,{true,1,0},.1)
        assert(not failed and completed,'Stock false-held release was incorrectly treated as cancelled')
        raw[config.input]=true
        local _,still_complete=parser:_evaluate_element(config,raw,{true,1,0},.1)
        assert(not still_complete,'Held action completed a release sequence')
        raw[config.input]=false
    end
    print('PASS: real remap suppresses explicit release edges; actual stock melee/giving sequences still accept false-held input')
    print('LIMIT: this executes sequence elements, not action hierarchy dispatch or a live release/damage outcome')
end
print('LIMIT: no engine serialization, live server, damage, movement or headset acceptance')
