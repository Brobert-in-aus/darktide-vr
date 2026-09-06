-- Run the real movement seam with planar quaternion/vector stubs.
local file=assert(io.open(arg[1],'r'))
local source=file:read('*all'); file:close()
local first=assert(source:find('function presentation.controller_movement_is_device_axis()',1,true))
local last=assert(source:find('\nmod:hook(',first,true))
local mode,state,hand='left_hand','walking',math.pi/2
mod={get=function(_,key) assert(key=='movement_reference'); return mode end}
controller_observation={gameplay_yaw=0,character_state_name='deliberately_stale'}
presentation={gameplay_context=dofile(arg[2]),left_hand_movement_rotation=function() return hand end,
    flat_movement_rotation=function(yaw) return yaw end}
local player={player_unit='local'}
Managers={player={local_player=function(_,index) assert(index==1); return player end}}
Unit={alive=function(unit) return unit=='local' end}
local extension={current_state_name=function() return state end}
ScriptUnit={has_extension=function(unit,system)
    assert(unit=='local' and system=='character_state_machine_system'); return extension
end}
Vector3=setmetatable({length_squared=function(v) return v.x*v.x+v.y*v.y end,
    x=function(v) return v.x end,y=function(v) return v.y end},
    {__call=function(_,x,y,z) return {x=x,y=y,z=z} end})
Quaternion={inverse=function(yaw) return -yaw end,rotate=function(yaw,v)
    return Vector3(math.cos(yaw)*v.x-math.sin(yaw)*v.y,
        math.sin(yaw)*v.x+math.cos(yaw)*v.y,v.z)
end}
assert(loadstring(source:sub(first,last-1)))()
local function expect(x,y,wanted_x,wanted_y)
    local actual_x,actual_y=presentation.rotate_controller_movement(x,y)
    assert(math.abs(actual_x-wanted_x)<1e-6 and math.abs(actual_y-wanted_y)<1e-6,
        'Incorrect locomotion/device movement basis')
end
expect(1,0,0,1) -- Hand-relative locomotion retains its 90-degree rotation.
state='minigame'
expect(1,0,1,0); expect(0,1,0,1); expect(.2,-.7,.2,-.7)
hand=-math.pi/2
expect(1,0,1,0) -- Turning the support hand cannot turn the scanner knob axes.
state='walking'
expect(1,0,0,-1) -- Exiting immediately restores the selected locomotion basis.
mode='head'; expect(1,0,1,0)
mode='left_hand'; hand=nil; expect(1,0,1,0)
hand=math.pi/2
extension=nil; expect(1,0,0,1)
extension={current_state_name=function() error('retiring') end}; expect(1,0,0,1)
extension=setmetatable({}, {__index=function() error('retired proxy lookup') end})
expect(1,0,0,1)
player=nil; expect(1,0,0,1)
controller_observation.gameplay_yaw=nil; expect(1,0,1,0)
print('scanner_stick_reference=pass real_seam direct_device_axes immediate_state_transitions locomotion_preserved fallbacks')
