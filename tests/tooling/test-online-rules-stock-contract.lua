-- Optional source integration: execute stock first-person and walking methods
-- after the real VR cache adapter. Engine math is isolated; no live XR/network.
local vector_meta={}
Vector3=setmetatable({}, {__call=function(_,x,y,z) return setmetatable({x,y,z},vector_meta) end})
vector_meta.__add=function(a,b) return Vector3(a[1]+b[1],a[2]+b[2],a[3]+b[3]) end
vector_meta.__unm=function(a) return Vector3(-a[1],-a[2],-a[3]) end
vector_meta.__mul=function(a,b)
    if type(a)=='number' then a,b=b,a end
    return Vector3(a[1]*b,a[2]*b,a[3]*b)
end
Vector3.x=function(v) return v[1] end; Vector3.y=function(v) return v[2] end
Vector3.to_elements=function(v) return unpack(v) end
Vector3.dot=function(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
Vector3.length_squared=function(v) return Vector3.dot(v,v) end
Vector3.length=function(v) return math.sqrt(Vector3.length_squared(v)) end
Vector3.normalize=function(v) local n=Vector3.length(v); return n>0 and v*(1/n) or Vector3(0,0,0) end
Vector3.flat=function(v) return Vector3(v[1],v[2],0) end
Vector3.up=function() return Vector3(0,0,1) end
Quaternion={from_yaw_pitch_roll=function(y,p,r) return {yaw=y,pitch=p,roll=r} end,
    yaw=function(q) return q.yaw end,pitch=function(q) return q.pitch end,
    inverse=function(q) return {yaw=-q.yaw,pitch=0,roll=0} end,
    forward=function(q) return Vector3(-math.sin(q.yaw),math.cos(q.yaw),0) end,
    look=function(v) return {yaw=math.atan2(-v[1],v[2]),pitch=0,roll=0} end,
    rotate=function(q,v) return Vector3(math.cos(q.yaw)*v[1]-math.sin(q.yaw)*v[2],
        math.sin(q.yaw)*v[1]+math.cos(q.yaw)*v[2],v[3]) end}
math.lerp=function(a,b,t) return a+(b-a)*t end
local root=arg[3]..'/scripts/'
local function source(path)
    local f=assert(io.open(root..path..'.lua','r')); local s=f:read('*all'); f:close(); return s
end
local fp_source=source('extension_systems/first_person/player_unit_first_person_extension')
local function extract(first,last)
    local a=assert(fp_source:find(first,1,true)); local b=assert(fp_source:find(last,a,true))
    return fp_source:sub(a,b-1)
end
-- Stock height interpolation is included; this fixture uses settled height.
local height_source=extract('local function _calculate_base_player_height(',
    '\nlocal half_pi ='):gsub('local function','function',1)
assert(loadstring(height_source))()
PlayerUnitFirstPersonExtension={}
assert(loadstring(extract('PlayerUnitFirstPersonExtension.fixed_update =',
    '\nPlayerUnitFirstPersonExtension.server_correction_occurred =')))()
Recoil={first_person_offset=function() return .02,.01 end}
GameSession={set_game_object_field=function() end}
local walking=assert(loadstring(source('extension_systems/character_state_machine/character_states/utilities/accelerated_local_space_movement')))()
local player={player_unit='local'}
Managers={state={game_session={is_server=function() return true end}},
    player={local_player=function() return player end},ui={using_input=function() return false end,
        communication_wheel_wants_camera_control=function() return false end,
        emote_wheel_wants_camera_control=function() return false end}}
Unit={alive=function() return true end}
ScriptUnit={has_extension=function() return {current_state_name=function() return 'walking' end} end}
Network={pack_unpack=function(_,value) return value end} -- Engine quantization not covered here.
package.preload['scripts/settings/player_character/player_orientation_settings']=function()
    return {default={min_pitch=-math.pi*.45,max_pitch=math.pi*.45}}
end
local aim=Quaternion.from_yaw_pitch_roll(math.pi/2,.3,0)
local view=Quaternion.from_yaw_pitch_roll(0,.1,0)
local presentation={mode=1,gameplay_context=dofile(arg[2]),
    flat_movement_rotation=function(y) return Quaternion.from_yaw_pitch_roll(y,0,0) end,
    controller_aim_target=function() return Vector3(99,88,77),aim end}
HumanGameplay={}
local gameplay_source=source('managers/player/player_game_states/human_gameplay')
local selection_start=assert(gameplay_source:find('HumanGameplay._player_orientation_class =',1,true))
local selection_end=assert(gameplay_source:find('\nHumanGameplay._cb_player_activate_emote =',selection_start,true))
assert(loadstring(gameplay_source:sub(selection_start,selection_end-1)))()
local orientation_class=HumanGameplay
ALIVE={['local']=true}
PlayerUnitStatus={is_ledge_hanging=function(component) return component.hanging end}
SweepStickyness={is_sticking_to_unit=function(component) return component.sticking end}
local rules=dofile(arg[1]).install({get=function() return true end,info=function() end,warning=function() end,
    hook_require=function(_,path,callback) callback(orientation_class) end,
    hook=function(_,class,name,callback)
        local original=class[name]; class[name]=function(...) return callback(original,...) end
    end},
    presentation,{authoring_enabled=true,gameplay_input_active=true},function() return 'shooting_range' end)
local h={_player=player,_input_cache={{0},{0},{1},{0},{0},{0},{0}},
    _action_lookup={move_right=1,move_left=2,move_forward=3,move_backward=4},
    _pack_unpack_action_to_network_type_index={move_right=1,move_left=1,move_forward=1,move_backward=1},
    _yaw_index=5,_pitch_index=6,_roll_index=7,_buffer_index=function() return 1 end}
player.input_handler=h
local gameplay={_player=player,_player_unit='local',_default_player_orientation={},
    _weapon_lock_view_component={state='none'},_force_look_rotation_component={},
    _character_state_component={},_action_sweep_component={},
    _forced_player_orientation={},_ledge_hanging_player_orientation={},
    _weapon_lock_view_player_orientation={},_weapon_force_view_player_orientation={},
    _smooth_force_view_player_orientation={},_communication_wheel_orientation={},_dead_player_orientation={}}
assert(orientation_class._player_orientation_class(gameplay)==gameplay._default_player_orientation)
rules.capture(h,1); assert(rules.frames==1)
local input={get_orientation=function() return h._input_cache[5][1],h._input_cache[6][1],h._input_cache[7][1] end,
    get=function(_,name) assert(name=='move'); return Vector3(h._input_cache[1][1]-h._input_cache[2][1],
        h._input_cache[3][1]-h._input_cache[4][1],0) end}
local component={wanted_height=1.7,height_change_start_time=0,height_change_duration=0,rotation=view}
local fp={_first_person_component=component,_locomotion_component={position=Vector3(10,20,0)},
    _inair_state_component={on_ground=true},_input_extension=input,_is_server=true,
    _weapon_extension={recoil_template=function() end,running_action_settings=function() return {} end},
    _peeking_component={is_peeking=false},_update_first_person_forced_rotation=function() end}
PlayerUnitFirstPersonExtension.fixed_update(fp,'local',.02,10,1)
assert(component.position[1]==10 and component.position[2]==20 and component.position[3]==1.7,
    'Stock body/height firing origin was replaced by hand origin')
assert(math.abs(component.rotation.yaw-(aim.yaw+.01))<1e-12)
assert(math.abs(component.rotation.pitch-(aim.pitch+.02))<1e-12)
assert(component.previous_rotation==view and view.yaw==0 and view.pitch==.1)
-- Stock local rendering and camera root use the original orientation owner,
-- independently of the hand-directed fixed simulation component.
assert(loadstring(extract('PlayerUnitFirstPersonExtension._update_rotation =',
    '\nPlayerUnitFirstPersonExtension.spectated_aim_rotation =')))()
local rendered_rotation
Unit.set_local_rotation=function(unit,node,rotation)
    assert(unit=='first_person' and node==1); rendered_rotation=rotation
end
fp._is_local_unit=true
fp._first_person_unit='first_person'
fp._player={get_orientation=function() return view end}
PlayerUnitFirstPersonExtension._update_rotation(fp,'local',.02,10)
assert(math.abs(rendered_rotation.yaw-.01)<1e-12 and math.abs(rendered_rotation.pitch-.12)<1e-12)
assert(math.abs(component.rotation.yaw-(math.pi/2+.01))<1e-12)
CameraHandler={}; CameraModes={observer='observer'}
local camera_source=source('managers/player/player_game_states/camera_handler')
local camera_first=assert(camera_source:find('CameraHandler._camera_root_orientation =',1,true))
local camera_last=assert(camera_source:find('\nCameraHandler._switch_follow_target =',camera_first,true))
assert(loadstring(camera_source:sub(camera_first,camera_last-1)))()
local camera_yaw,camera_pitch=CameraHandler._camera_root_orientation({_mode='first_person'},
    {orientation=function() return view.yaw,view.pitch,view.roll end,
     orientation_offset=function() return .01,.02,0 end})
assert(camera_yaw==rendered_rotation.yaw and camera_pitch==rendered_rotation.pitch)
-- With zero recoil, the actual walking method reconstructs the intended head-
-- relative direction from the transformed input. Its own backward penalty stays.
local constants={acceleration=1000,deceleration=1000,backward_move_scale=.5,
    move_speed=5,crouch_move_speed=2,slide_move_speed_threshold=2}
local function move(yaw)
    return walking.wanted_movement(constants,input,{local_move_x=0,local_move_y=0},
        {player_speed_scale=1},{rotation=Quaternion.from_yaw_pitch_roll(yaw,0,0)},
        false,Vector3(0,0,0),1)
end
local direction,speed=move(aim.yaw)
assert(math.abs(direction[1])<1e-12 and math.abs(direction[2]-1)<1e-12 and speed==5)
aim=Quaternion.from_yaw_pitch_roll(math.pi,0,0)
h._input_cache={{0},{0},{1},{0},{0},{0},{0}}
rules.capture(h,2)
direction,speed=move(aim.yaw)
assert(math.abs(direction[1])<1e-12 and math.abs(direction[2]-1)<1e-12)
assert(math.abs(speed-2.5)<1e-12,'Stock backward penalty must remain')
-- Verify through actual walking, including rotated diagonals that exceed the
-- stock square. All headings keep the desired direction at settled input.
for step=0,11 do
    for _,wanted in ipairs({{1,1},{1,.5},{-1,1},{-.3,-.8}}) do
        aim=Quaternion.from_yaw_pitch_roll(step*math.pi/6,0,0)
        local x,y=wanted[1],wanted[2]
        h._input_cache={{math.max(x,0)},{math.max(-x,0)},
            {math.max(y,0)},{math.max(-y,0)},{0},{0},{0}}
        rules.capture(h,step+3)
        direction=move(aim.yaw)
        local length=math.sqrt(x*x+y*y)
        assert(math.abs(direction[1]-x/length)<1e-12 and
            math.abs(direction[2]-y/length)<1e-12,'Stock walking direction changed after aim conversion')
        for index=1,4 do assert(h._input_cache[index][1]>=0 and h._input_cache[index][1]<=1) end
    end
end
-- Execute the actual stock selector for forced look, weapon lock, melee
-- stickiness, ledge hanging, communication/emote wheels and dead ownership.
local selected_cases={
    function() gameplay._force_look_rotation_component.use_force_look_rotation=true end,
    function() gameplay._force_look_rotation_component.use_force_look_rotation=false; gameplay._character_state_component.hanging=true end,
    function() gameplay._character_state_component.hanging=false; gameplay._weapon_lock_view_component.state='weapon_lock' end,
    function() gameplay._weapon_lock_view_component.state='weapon_lock_no_lerp' end,
    function() gameplay._weapon_lock_view_component.state='force_look' end,
    function() gameplay._weapon_lock_view_component.state='none'; gameplay._action_sweep_component.sticking=true end,
    function() gameplay._action_sweep_component.sticking=false; Managers.ui.communication_wheel_wants_camera_control=function() return true end end,
    function() Managers.ui.communication_wheel_wants_camera_control=function() return false end; Managers.ui.emote_wheel_wants_camera_control=function() return true end end,
    function() Managers.ui.emote_wheel_wants_camera_control=function() return false end; ALIVE['local']=false end,
}
for i,select_case in ipairs(selected_cases) do
    select_case()
    assert(orientation_class._player_orientation_class(gameplay)~=gameplay._default_player_orientation)
    h._input_cache={{0},{0},{1},{0},{0},{0},{0}}
    rules.capture(h,i+10)
    assert(h._input_cache[5][1]==0 and h._input_cache[3][1]==1,'Overrode forced stock orientation')
end
print('PASS: actual stock pose keeps body origin/recoil; actual walking preserves direction and backward penalty')
print('PASS: actual stock orientation selector retains forced look, weapon locks, sticky melee, ledges, wheels and death')
print('PASS: actual stock local rendering and camera root retain independent view orientation')
print('LIMIT: isolated engine math, no real quantization, live network or worn acceptance')
