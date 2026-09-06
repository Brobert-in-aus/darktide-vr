-- Isolated production policy/cache adapter; no game, network or headset.
local Rules = dofile(arg[1])
local context = dofile(arg[2])
local mode, option, owns, character = 'shooting_range', true, false, 'walking'
local hand = {yaw=math.pi/2,pitch=.2}
local player = {player_unit='local'}
local logs, packed = {}, 0
local mod = {get=function() return option end,
    info=function(_,message) logs[#logs+1]=message end,
    warning=function(_,message) logs[#logs+1]=message end}
Managers={state={game_session={is_server=function() return true end}},
    player={local_player=function() return player end},
    ui={using_input=function() return owns end}}
Unit={alive=function(unit) return unit=='local' end}
ScriptUnit={has_extension=function() return {current_state_name=function() return character end} end}
Vector3=setmetatable({x=function(v) return v[1] end,y=function(v) return v[2] end},
    {__call=function(_,x,y,z) return {x,y,z} end})
Quaternion={yaw=function(q) return q.yaw end,pitch=function(q) return q.pitch end,
    inverse=function(q) return -q end,
    rotate=function(q,v) return {math.cos(q)*v[1]-math.sin(q)*v[2],
        math.sin(q)*v[1]+math.cos(q)*v[2],v[3]} end}
Network={pack_unpack=function(kind,value)
    assert(kind==7 and value>=0 and value<=1); packed=packed+1
    return math.floor(value*10000+.5)/10000
end}
package.preload['scripts/settings/player_character/player_orientation_settings']=function()
    return {default={min_pitch=-math.pi*.45,max_pitch=math.pi*.45}}
end
local state={authoring_enabled=true,gameplay_input_active=true}
local presentation={mode=1,gameplay_context=context,flat_movement_rotation=function(yaw) return yaw end,
    controller_aim_target=function() return 'unused_hand_origin',hand end}
local rules=Rules.install(mod,presentation,state,function() return mode end)
local names={'move_right','move_left','move_forward','move_backward'}
local function handler()
    local h={_player=player,_input_cache={{},{},{},{},{},{},{}},_action_lookup={},
        _yaw_index=5,_pitch_index=6,_roll_index=7,_pack_unpack_action_to_network_type_index={},
        _buffer_index=function(_,frame) return frame end}
    for i,name in ipairs(names) do h._action_lookup[name]=i; h._pack_unpack_action_to_network_type_index[name]=7 end
    return h
end
local h=handler()
local function fresh(frame,x,y)
    local c=h._input_cache
    c[1][frame],c[2][frame]=math.max(x or 0,0),math.max(-(x or 0),0)
    c[3][frame],c[4][frame]=math.max(y or 0,0),math.max(-(y or 0),0)
    c[5][frame],c[6][frame],c[7][frame]=0,0,0
end
local function stock(frame)
    assert(h._input_cache[5][frame]==0 and h._input_cache[6][frame]==0)
end
fresh(1,0,1); rules.capture(h,1)
assert(rules.frames==1 and packed==4)
assert(h._input_cache[5][1]==math.pi/2)
assert(math.abs(h._input_cache[6][1]-.2)<1e-12)
assert(h._input_cache[1][1]==1 and h._input_cache[3][1]==0)
-- Stock-origin angle routing never writes the visual camera or live hand pose.
assert(presentation.camera==nil and hand.yaw==math.pi/2)
hand={yaw=math.pi,pitch=math.pi/2}
fresh(2,0,1); rules.capture(h,2)
assert(h._input_cache[4][2]==1 and h._input_cache[5][2]==math.pi)
assert(h._input_cache[6][2]==math.pi*.45 and h._input_cache[7][2]==0)
assert(h._input_cache[5][1]==math.pi/2,'Later tracking rewrote earlier frame')
-- Menus, unavailable tracking, disabled states, foreign handlers and failure
-- in movement packing must preserve the whole stock input sample.
local gates={
    function() owns=true end,
    function() owns=false; hand=nil end,
    function() hand={yaw=1,pitch=0}; character='knocked_down' end,
    function() character='minigame' end,
    function() character='walking'; h._player={} end,
    function() h._player=player; state.gameplay_input_active=false end,
    function() state.gameplay_input_active=true; state.authoring_enabled=false end,
    function() state.authoring_enabled=true; presentation.mode=5 end,
    function() presentation.mode=1; hand.yaw=0/0 end,
    function() hand.yaw=1; h._pack_unpack_action_to_network_type_index.move_left=nil end,
}
for i,gate in ipairs(gates) do gate(); fresh(i+2,0,1); rules.capture(h,i+2); stock(i+2) end
h._pack_unpack_action_to_network_type_index.move_left=7
local original_pack=Network.pack_unpack
local count=0
Network.pack_unpack=function(...)
    count=count+1; if count==3 then error('packing unavailable') end
    return original_pack(...)
end
fresh(20,0,1); rules.capture(h,20); stock(20)
assert(h._input_cache[3][20]==1 and rules.failures==1,'Partial input mutation on failure')
Network.pack_unpack=original_pack
-- Settings are latched until leaving the range. Remote missions stay gated.
option=false; assert(rules.enabled())
mode='hub'; assert(not rules.enabled())
mode='shooting_range'; assert(not rules.enabled())
option=true; mode='coop_complete_objective'; assert(not rules.enabled())
mode='training_grounds'; assert(not rules.enabled())
mode='shooting_range'; assert(rules.enabled())
Managers.state.game_session={is_server=function() return false end}
assert(not rules.enabled())
print('PASS: range rules, frame aim, movement basis/packing, pitch limits, stock fallbacks and session setting')
