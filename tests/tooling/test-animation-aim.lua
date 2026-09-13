local file=assert(io.open(arg[1],'r'))
local source=file:read('*all'); file:close()
local first=assert(source:find('mod:hook_safe(\n    require("scripts/extension_systems/aim/player_unit_aim_extension"),\n    "update",',1,true))
local last=assert(source:find('\nmod:hook_safe(',first+1,true))
local mt={}
local function v(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
mt.__add=function(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
mt.__mul=function(a,b)
 if type(a)=='number' then a,b=b,a end
 return v(a.x*b,a.y*b,a.z*b)
end
local head={direction=v(0,1,0)}
local hand={direction=v(1,0,0)}
local written
Quaternion={forward=function(q) return q.direction end,axis_angle=function() return head end}
Vector3={up=function() return v(0,0,1) end}
Unit={alive=function() return true end,local_position=function() return v(0,0,0) end,
 animation_set_constraint_target=function(_,_,target) written=target end}
controller_observation={body_ik_presentation_enabled=true,body_head_yaw=0}
presentation={controller_aim={target=function() return v(0,0,0),hand end},
 keyboard_mouse_aim_rotation=function() end}
require=function() return {} end
local hook
mod={hook_safe=function(_,_,_,callback) hook=callback end}
assert(loadstring(source:sub(first,last-1)))()
local extension={_aim_constraint_variable=1,_aim_contraint_distance=10,
 _first_person_extension={extrapolated_character_height=function() return 2 end}}
hook(extension,{})
assert(written.x==10 and written.y==0 and written.z==2,'animation fell back to head instead of right-hand aim')
hand=nil
hook(extension,{})
assert(written.x==0 and written.y==10 and written.z==2,'lost head fallback for unavailable controller')
print('animation aim independent of head and missing-controller fallback passed')
