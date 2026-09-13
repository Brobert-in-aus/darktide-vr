-- Keyboard and mouse aim never comes from a controller while in use, even a tracked one:
-- a controller on the desk drifting in and out of tracking made the stock
-- input aim, and the reticle with it, jump between the mouse and the controller.
local file=assert(io.open(arg[1],'r'))
local source=file:read('*all'); file:close()
local first=assert(source:find('function presentation.controller_aim_target()',1,true))
local last=assert(source:find('\nfunction presentation.weapon_grip_target(',first,true))
local mt={}
local function v(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
mt.__add=function(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
Vector3=v
Quaternion={from_elements=function() return 'q' end,multiply=function() return 'aim' end}
local keyboard_mouse=false
local presentation={
    keyboard_mouse_enabled=function() return keyboard_mouse end,
    controllers_suppressed=function() return keyboard_mouse end,
    rotate_vector=function(_,p) return p end,
    weapon_hand_roles={physical=function(role) return role=='dominant' and 'right' or 'left' end},
}
local observation={right_aim_usable=true,left_aim_usable=true,body_anchor_x=0,body_anchor_y=0,body_anchor_z=0,
    body_anchor_qx=0,body_anchor_qy=0,body_anchor_qz=0,body_anchor_qw=1,
    right_aim_x=1,right_aim_y=0,right_aim_z=0,right_aim_qx=0,right_aim_qy=0,right_aim_qz=0,right_aim_qw=1,
    left_aim_x=-1,left_aim_y=0,left_aim_z=0,left_aim_qx=0,left_aim_qy=0,left_aim_qz=0,left_aim_qw=1}
setfenv(assert(loadstring(source:sub(first,last-1))),
    setmetatable({presentation=presentation,controller_observation=observation},{__index=_G}))()
-- Controller play: tracked controllers aim.
assert(select(2,presentation.controller_aim_target())=='aim')
assert(select(2,presentation.left_controller_aim_target())=='aim')
assert(select(2,presentation.weapon_aim_target('dominant'))=='aim')
-- Keyboard or mouse in use with controllers enabled and tracked: no controller
-- aim reaches the weapon, the stock input or the reticle.
keyboard_mouse=true
assert(presentation.controller_aim_target()==nil and select(2,presentation.controller_aim_target())==nil,
    'a tracked controller took over keyboard and mouse aim')
assert(select(2,presentation.left_controller_aim_target())==nil,'the left controller aimed in keyboard and mouse play')
assert(select(2,presentation.weapon_aim_target('dominant'))==nil and select(2,presentation.weapon_aim_target('support'))==nil,
    'the online-rules input aim used a controller in keyboard and mouse play')
-- Animated keyboard and mouse hands move 10 cm forward along the aim heading
-- (never its pitch) and 10 cm down, in player scale.
do
    local offset_first=assert(source:find('function presentation.keyboard_mouse_hand_offset()',1,true))
    local offset_last=assert(source:find('\nfunction presentation.',offset_first+1,true))
    local vm={}
    local function vec(x,y,z) return setmetatable({x=x,y=y,z=z},vm) end
    vm.__add=function(a,b) return vec(a.x+b.x,a.y+b.y,a.z+b.z) end
    vm.__sub=function(a,b) return vec(a.x-b.x,a.y-b.y,a.z-b.z) end
    vm.__mul=function(a,b) if type(a)=='number' then a,b=b,a end; return vec(a.x*b,a.y*b,a.z*b) end
    local KeyboardMouse=dofile(arg[2])
    local kbm=KeyboardMouse.install({get=function() return nil end,info=function() end},function() end)
    local g={keyboard_mouse=kbm,keyboard_mouse_enabled=function() return true end,
        calibrated_character_scale=function(player) assert(player=='player'); return 1.25 end}
    local env=setmetatable({presentation=g,
        Managers={player={local_player=function() return 'player' end}},
        Vector3={up=function() return vec(0,0,1) end},
        Quaternion={from_yaw_pitch_roll=function(yaw,pitch,roll)
            assert(pitch==0 and roll==0,'the hand offset followed aim pitch'); return yaw end,
            forward=function(yaw) return vec(-math.sin(yaw),math.cos(yaw),0) end}},{__index=_G})
    setfenv(assert(loadstring(source:sub(offset_first,offset_last-1))),env)()
    assert(g.keyboard_mouse_hand_offset()==nil,'an offset without a mouse aim')
    kbm.state.aim_yaw,kbm.state.aim_pitch=math.pi/2,0.6
    local o=g.keyboard_mouse_hand_offset()
    assert(math.abs(o.x+0.125)<1e-9 and math.abs(o.y)<1e-9 and math.abs(o.z+0.125)<1e-9,
        string.format('hand offset %.3f,%.3f,%.3f',o.x,o.y,o.z))
    g.keyboard_mouse_enabled=function() return false end
    assert(g.keyboard_mouse_hand_offset()==nil)
end
-- The hands hang from the camera anchor refreshed at the IK seam.
do
    local pivot_first=assert(source:find('function presentation.keyboard_mouse_hand_pivot(',1,true))
    local pivot_last=assert(source:find('\nfunction presentation.',pivot_first+1,true))
    local refreshed,obs={}, {}
    local g={refresh_body_anchor_from_avatar=function(owner)
        refreshed[#refreshed+1]=owner; obs.body_anchor_x,obs.body_anchor_y,obs.body_anchor_z=1,2,3; return true end}
    setfenv(assert(loadstring(source:sub(pivot_first,pivot_last-1))),setmetatable({presentation=g,
        controller_observation=obs,Vector3=function(x,y,z) return {x,y,z} end},{__index=_G}))()
    local p=g.keyboard_mouse_hand_pivot('avatar')
    assert(refreshed[1]=='avatar' and p[1]==1 and p[2]==2 and p[3]==3,'hands did not use the refreshed camera anchor')
    g.refresh_body_anchor_from_avatar=function() return false end
    assert(g.keyboard_mouse_hand_pivot('avatar')==nil,'a failed anchor refresh still moved the hands')
end
print('keyboard_mouse_aim_source=pass controller_play tracked_controller_ignored_for_aim hand_offset hand_pivot')
