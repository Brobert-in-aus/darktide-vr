-- Optional source audit fixture. No game, network, backend or XR calls.
-- Runs stock first-person calculation with isolated vector/quaternion helpers.
local root=assert(arg[1], 'Pass the stock source snapshot directory')..'/scripts/'
local function source(path)
    local f=assert(io.open(root..path..'.lua','r'))
    local s=f:read('*all'); f:close(); return s
end
local function chunk(s, first, last)
    local a=assert(s:find(first,1,true),first)
    local b=assert(s:find(last,a,true),last)
    return s:sub(a,b-1)
end
local function near(a,b) assert(math.abs(a-b)<1e-9, tostring(a)..' != '..tostring(b)) end
math.half_pi=math.pi/2
math.clamp=function(v,a,b) return math.max(a,math.min(b,v)) end
math.sign=function(v) return v>0 and 1 or v<0 and -1 or 0 end
-- Match the snapshot's clamped ilerp, not an unconstrained approximation.
math.ilerp=function(a,b,v) return (math.clamp(v,math.min(a,b),math.max(a,b))-a)/(b-a) end
math.lerp=function(a,b,t) return a*(1-t)+b*t end
math.remap=function(a,b,c,d,v) return math.lerp(c,d,math.ilerp(a,b,v)) end
local vm={}
Vector3=setmetatable({}, {__call=function(_,x,y,z) return setmetatable({x,y,z},vm) end})
vm.__add=function(a,b) return Vector3(a[1]+b[1],a[2]+b[2],a[3]+b[3]) end
vm.__unm=function(a) return Vector3(-a[1],-a[2],-a[3]) end
vm.__mul=function(a,b) return Vector3(a[1]*b,a[2]*b,a[3]*b) end
Vector3.up=function() return Vector3(0,0,1) end
Vector3.dot=function(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
Quaternion={
    from_yaw_pitch_roll=function(y,p,r) return {yaw=y,pitch=p,roll=r} end,
    forward=function(q) return Vector3(-math.sin(q.yaw)*math.cos(q.pitch),
        math.cos(q.yaw)*math.cos(q.pitch),math.sin(q.pitch)) end,
}
Recoil={first_person_offset=function() return 0,0 end}
PlayerUnitFirstPersonExtension={}
local fp_source=source('extension_systems/first_person/player_unit_first_person_extension')
assert(loadstring(chunk(fp_source,'local function _ease_out_quad(',
    '\nPlayerUnitFirstPersonExtension.server_correction_occurred =')))()
local publications={}
GameSession={set_game_object_field=function(_,_,name,value)
    assert(name=='character_height'); publications[#publications+1]=value
end}
local pose={wanted_height=1.7,old_height=1.7,height=1.7,
    height_change_start_time=0,height_change_duration=0,
    rotation=Quaternion.from_yaw_pitch_roll(0,0,0)}
local yaw,pitch,roll=0,0,0
local fp={_first_person_component=pose,
    _locomotion_component={position=Vector3(10,20,3)},
    _inair_state_component={on_ground=true},
    _input_extension={get_orientation=function() return yaw,pitch,roll end},
    _weapon_extension={recoil_template=function() end,running_action_settings=function() return {} end},
    _peeking_component={is_peeking=false,peeking_height=1.35},
    _heights={crouch=1,default=1.7},_fixed_time_step=1/60,
    _update_first_person_forced_rotation=function() end}
local frame=0
local function step()
    frame=frame+1
    PlayerUnitFirstPersonExtension.fixed_update(fp,'fixture',1/60,frame/60,frame)
    near(pose.position[1],10); near(pose.position[2],20)
    near(pose.position[3],3+pose.height)
end
-- Directly changing a local pose is overwritten by the next stock calculation.
-- Both client prediction and server calculation use the supplied locomotion state.
for _,server in ipairs({false,true}) do
    fp._is_server=server
    local before=#publications
    for _,angles in ipairs({{0,0,0},{1,.4,0},{2,-.5,1.2}}) do
        yaw,pitch,roll=unpack(angles)
        pose.position=Vector3(99,88,77)
        step(); near(pose.height,1.7)
        near(pose.rotation.yaw,yaw); near(pose.rotation.roll,roll)
    end
    assert(#publications-before==(server and 3 or 0))
end
-- Height transitions allow intermediate vertical values, but no horizontal offset.
pose.old_height=1.7; pose.wanted_height=1
pose.height_change_start_time=frame/60; pose.height_change_duration=.3
pose.height_change_function='ease_out_quad'
step(); assert(pose.height>1 and pose.height<1.7)
for i=1,20 do step() end
near(pose.height,1)
-- Peeking consumes an already admitted server peeking state. This does not
-- bypass the separate talent, weapon, crouch, cover and ledge admission checks.
fp._peeking_component.is_peeking=true
for _,case in ipairs({{0,1.35},{math.pi*.45,1},{-math.pi*.45,1.7}}) do
    pitch=case[1]
    for i=1,40 do step(); assert(pose.height>=1 and pose.height<=1.7) end
    near(pose.height,case[2])
end
-- A modified wanted_height can affect this process, illustrating why a local
-- server is not a remote trust-boundary test. It is not a client input column.
fp._peeking_component.is_peeking=false; fp._is_server=false
pose.wanted_height=7; pose.height_change_duration=0
step(); near(pose.height,7)
settings=function(_,t) return t end
local inputs=assert(loadstring(source('managers/player/player_game_states/input_handler_settings')))()
local columns=3
for _,group in ipairs({'actions','ephemeral_actions','ui_interaction_actions','input_settings'}) do
    columns=columns+#inputs[group]
    for _,name in ipairs(inputs[group]) do
        assert(not name:find('height') and not name:find('position') and not name:find('pose'))
    end
end
assert(columns==57)
-- Execute the real profile-height utility with an explicit human breed fixture.
package.preload['scripts/settings/breed/breed_settings']=function()
    return {base_player_body_size_heights={human_sized=1.65,ogryn_sized=2.2}}
end
table.size=function(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
Script={new_map=function() return {} end}
local height=assert(loadstring(source('utilities/player_height')))()
local average=(.95+1.08)/2
local breed={body_size='human_sized',average_size=average,
    heights={default=1.65/average,crouch=1/average,slide=.85/average}}
for _,scale in ipairs({.95,1,1.08}) do
    local heights=height.player_character_first_person_heights(breed,{personal={character_height=scale}})
    near(heights.default,breed.heights.default*scale)
    near(heights.crouch,breed.heights.crouch*scale)
end
print('PASS stock head reconstruction: client/server pose overwrite, server-only height publication,')
print('     intermediate stance heights, bounded admitted peeking, 57 input columns, profile scaling.')
print('LIMIT: isolated engine math/state; no RPC serialization, official server or worn acceptance.')
