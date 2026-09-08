-- Isolated production policy/cache adapter; no game, network or headset.
local Rules = dofile(arg[1])
local context = dofile(arg[2])
local mode, option, owns, character = 'shooting_range', true, false, 'walking'
local hand = {yaw=math.pi/2,pitch=.2}
local player = {player_unit='local'}
local logs, packed = {}, 0
local orientation_class={_player_orientation_class=function(self) return self.chosen end}
local mod = {get=function() return option end,
    info=function(_,message,...) logs[#logs+1]=string.format(message,...) end,
    warning=function(_,message) logs[#logs+1]=message end,
    hook_require=function(_,path,callback) callback(orientation_class) end,
    hook=function(_,class,name,callback)
        local original=class[name]; class[name]=function(...) return callback(original,...) end
    end}
Managers={state={game_session={is_server=function() return true end}},
    player={local_player=function() return player end},
    ui={using_input=function() return owns end}}
Unit={alive=function(unit) return unit=='local' end}
ScriptUnit={has_extension=function() return {current_state_name=function() return character end} end}
Vector3=setmetatable({x=function(v) return v[1] end,y=function(v) return v[2] end,z=function(v) return v[3] end,
    dot=function(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end},
    {__call=function(_,x,y,z) return {x,y,z} end})
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
    assert(kind==7 and value>=0 and value<=1); packed=packed+1
    return math.floor(value*10000+.5)/10000
end}
package.preload['scripts/settings/player_character/player_orientation_settings']=function()
    return {default={min_pitch=-math.pi*.45,max_pitch=math.pi*.45}}
end
local state={authoring_enabled=true,gameplay_input_active=true}
local presentation={mode=1,gameplay_context=context,flat_movement_rotation=function(yaw) return yaw end,
    controller_aim_target=function() error('Online input bypassed dominant role') end,
    weapon_aim_target=function(role) assert(role=='dominant'); return 'unused_hand_origin',hand end}
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
player.input_handler=h
local default_orientation={}
local gameplay=setmetatable({_player=player,_default_player_orientation=default_orientation,
    chosen=default_orientation},{__index=orientation_class})
assert(gameplay:_player_orientation_class()==default_orientation)
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
hand={yaw=math.pi,pitch=math.pi/2-.0001}
fresh(2,0,1); rules.capture(h,2)
assert(h._input_cache[4][2]==1 and h._input_cache[5][2]==math.pi)
assert(h._input_cache[6][2]==math.pi*.45 and h._input_cache[7][2]==0)
assert(h._input_cache[5][1]==math.pi/2,'Later tracking rewrote earlier frame')
-- Diagonal keyboard/combined input can leave the square after rotation.
-- Saturation must keep its direction instead of clipping axes independently.
hand={yaw=math.pi/6,pitch=0}
fresh(23,1,1); rules.capture(h,23)
local c=h._input_cache
local world=Quaternion.rotate(hand.yaw,Vector3(c[1][23]-c[2][23],c[3][23]-c[4][23],0))
assert(math.abs(world[1]-world[2])<.0002,'Rotated diagonal changed intended movement direction')
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
-- A forced look can occur while the character remains walking. Respect the
-- actual stock orientation selection, including nil/unknown ownership.
for _,choice in ipairs({{},false}) do
    gameplay.chosen=choice or nil
    assert(gameplay:_player_orientation_class()==gameplay.chosen)
    fresh(21,0,1); rules.capture(h,21); stock(21)
end
gameplay.chosen=default_orientation
gameplay:_player_orientation_class()
fresh(22,0,1); rules.capture(h,22); assert(h._input_cache[5][22]==1)
-- Settings are latched until leaving the range. Remote missions stay gated.
option=false; assert(rules.enabled())
mode='hub'; assert(not rules.enabled())
mode='shooting_range'; assert(not rules.enabled())
-- Every admitted local mission uses stock rules even with the range option off.
-- Reuse the manager to exercise a transition without an intervening hub call.
for _,mission in ipairs({'coop_complete_objective','survival','expedition','prologue'}) do
    mode=mission; assert(rules.enabled())
    fresh(28,0,1); rules.capture(h,28)
    assert(h._input_cache[5][28]==1 and rules.frames==1)
    Managers.state.game_session={is_server=function() return false end}
    assert(not rules.enabled())
    fresh(29,0,1); rules.capture(h,29); stock(29)
    Managers.state.game_session={is_server=function() return true end}
end
mode='unknown_mission'; assert(not rules.enabled())
option=true
mode='training_grounds'; assert(not rules.enabled())
mode='shooting_range'; assert(rules.enabled())
assert(rules.frames==0 and rules.failures==0,'Range re-entry retained previous session diagnostics')
local function log_count(pattern)
    local count=0
    for _,message in ipairs(logs) do if message:find(pattern,1,true) then count=count+1 end end
    return count
end
local first_frames=log_count('input_frame=')
fresh(24,0,1); rules.capture(h,24)
fresh(25,0,1); rules.capture(h,25)
assert(rules.frames==2 and log_count('input_frame=')==first_frames+1,
    'Re-entry must emit exactly one fresh authored-frame diagnostic')
-- A replacement range session can arrive without an observed hub call.
Managers.state.game_session={is_server=function() return true end}
assert(rules.enabled() and rules.frames==0 and rules.failures==0)
Network.pack_unpack=function() error('new session packing unavailable') end
fresh(26,0,1); rules.capture(h,26); stock(26)
fresh(27,0,1); rules.capture(h,27); stock(27)
assert(rules.failures==2 and log_count('input_fallback=')==2,
    'Each visit must report its first failure without repeating every frame')
Network.pack_unpack=original_pack
Managers.state.game_session={is_server=function() return false end}
assert(not rules.enabled())
-- Preview is visual-only: read the local simulated component even when live
-- hand tracking is unavailable, and reject foreign/stale/retiring roots.
local simulated={position=300,rotation=400}
local extension={_first_person_component=simulated,first_person_unit=function() return 'fp' end}
local effects={_is_local_unit=true,_first_person_unit='fp'}
ScriptUnit.has_extension=function(_,system) assert(system=='first_person_system'); return extension end
assert(rules.preview_pose(effects)==nil,'Remote authority admitted a simulation preview')
Managers.state.game_session={is_server=function() return true end}
hand=nil
local p,r=rules.preview_pose(effects); assert(p==300 and r==400)
effects._first_person_unit='old'; assert(rules.preview_pose(effects)==nil)
effects._first_person_unit='fp'; effects._is_local_unit=false; assert(rules.preview_pose(effects)==nil)
effects._is_local_unit=true; presentation.mode=5; assert(rules.preview_pose(effects)==nil)
presentation.mode=1
extension=setmetatable({}, {__index=function() error('retiring preview owner') end})
assert(rules.preview_pose(effects)==nil)
-- Difficulty describes the successful proving sample; it must not authorize,
-- alter or break input when an optional manager is missing/retiring/invalid.
ScriptUnit.has_extension=function() return {current_state_name=function() return 'walking' end} end
hand={yaw=1,pitch=0}
for _,case in ipairs({
    {manager={get_challenge=function() return 5 end,get_resistance=function() return 4 end},want='challenge=5 resistance=4'},
    {manager={},want='challenge=unknown resistance=unknown'},
    {manager=setmetatable({}, {__index=function() error('retiring difficulty') end}),want='challenge=unknown resistance=unknown'},
    {manager={get_challenge=function() return 0/0 end,get_resistance=function() return math.huge end},want='challenge=unknown resistance=unknown'},
    {manager={get_challenge=function() return 3 end,get_resistance=function() error('missing') end},want='challenge=3 resistance=unknown'},
}) do
    Managers.state.game_session={is_server=function() return true end}
    Managers.state.difficulty=case.manager
    fresh(30,0,1); rules.capture(h,30)
    assert(rules.frames==1 and rules.failures==0 and h._input_cache[5][30]==1)
    assert(logs[#logs]:find(case.want,1,true), 'Difficulty evidence was incorrect or broke input')
    local count=#logs
    fresh(31,0,1); rules.capture(h,31)
    assert(#logs==count,'Difficulty diagnostics repeated on stable frames')
end
Managers.state.difficulty=nil
-- Full wrist turns leave pointing unchanged, including upside-down poses.
for _,yaw in ipairs({0,.7,math.pi,5.8}) do
    for _,pitch in ipairs({-1.4,-.3,0,.8,1.4}) do
        for degrees=-360,360 do
            local roll=math.rad(degrees)
            local y,p,r=Rules.orientation({yaw=yaw,pitch=pitch,roll=roll},0)
            assert(math.abs(math.sin(y-yaw))<1e-10 and math.cos(y-yaw)>.999999)
            assert(math.abs(p-pitch)<1e-10)
            assert(math.abs(math.sin(r-roll))<1e-10 and math.cos(r-roll)>.999999)
        end
    end
end
local y,p=Rules.orientation({yaw=2,pitch=math.pi/2,roll=.7},.4)
assert(y==.4 and math.abs(p-math.pi/2)<1e-12,'Pole lost prior yaw')
assert(Rules.orientation({yaw=0/0,pitch=0},0)==nil)
assert(Rules.snap_roll(math.rad(22),nil)==0)
assert(Rules.snap_roll(math.rad(24),0)==0,'Boundary noise changed sector')
assert(Rules.snap_roll(math.rad(26),0)==math.pi/4)
assert(Rules.snap_roll(math.rad(21),math.pi/4)==math.pi/4)
assert(Rules.snap_roll(math.rad(18),math.pi/4)==0)
assert(Rules.snap_roll(math.rad(-1),0)==0,'Wraparound changed sector')
local template={keywords={'melee'}}
local running
local melee_weapon={weapon_template=function() return template end,
    running_action_settings=function() return running end}
ScriptUnit.has_extension=function(_,system)
    if system=='weapon_system' then return melee_weapon end
    return {current_state_name=function() return 'walking' end}
end
hand={yaw=.7,pitch=.2,roll=math.pi/2}
fresh(40,0,1); rules.capture(h,40)
assert(h._input_cache[7][40]==math.pi/2,'Melee wrist angle absent from stock input')
running={kind='windup'}; hand.roll=math.pi
fresh(41,0,1); rules.capture(h,41)
assert(h._input_cache[7][41]==math.pi/2,'First swing angle changed during windup')
running={kind='sweep'}
fresh(42,0,1); rules.capture(h,42)
assert(h._input_cache[7][42]==math.pi/2)
running=nil
fresh(43,0,1); rules.capture(h,43)
assert(h._input_cache[7][43]==math.pi,'Idle selection did not resume')
template={keywords={'ranged','force_staff'}}
fresh(44,0,1); rules.capture(h,44)
assert(h._input_cache[7][44]==0,'Melee roll leaked into staff aim')
assert(math.abs(h._input_cache[5][44]-.7)<1e-12 and math.abs(h._input_cache[6][44]-.2)<1e-12)
print('PASS: range rules, frame aim, movement basis/packing, pitch limits, stock fallbacks and session setting')
