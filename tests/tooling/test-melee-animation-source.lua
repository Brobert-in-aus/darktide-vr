local file=assert(io.open(arg[1],'r'));local text=file:read('*all');file:close()
local first=assert(text:find('function BodyProxy.follow_gameplay_hands',1,true))
local last=assert(text:find('\nfunction BodyProxy.hides_source_slot',first,true))
local mt={}
local function v(x,y,z) return setmetatable({x=x,y=y,z=z},mt) end
mt.__add=function(a,b)return v(a.x+b.x,a.y+b.y,a.z+b.z)end
mt.__sub=function(a,b)return v(a.x-b.x,a.y-b.y,a.z-b.z)end
local fp,body={},{}
state={source_unit=body}
rigid_hands={left={unit={}},right={unit={}}}
BodyProxy={rigid_hands_active=function()return true end}
ScriptUnit={has_extension=function(unit,name)assert(unit==body);return {_first_person_unit=fp}end}
Unit={alive=function()return true end,has_node=function()return true end,node=function(_,name)return name end,
 world_position=function(unit,node)
  if unit==body then return v(999,999,999) end
  if node==1 then return v(2,3,4) end
  return v(2,4,4)
 end,world_rotation=function()return 0 end}
Quaternion={multiply=function(a,b)return a+b end,rotate=function(angle,p)
 return v(math.cos(angle)*p.x-math.sin(angle)*p.y,math.sin(angle)*p.x+math.cos(angle)*p.y,p.z)
end}
inverse_quaternion=function(q)return -q end
local count=0
place_rigid_hand=function(_,hand,position,rotation,authored)
 assert(math.abs(position.x-1)<1e-7 and math.abs(position.y-3)<1e-7 and position.z==4,'read modified 3p hands or used wrong pivot')
 assert(rotation==math.pi/2 and authored)
 count=count+1
end
assert(loadstring(text:sub(first,last-1)))()
assert(BodyProxy.follow_gameplay_hands({},math.pi/2))
assert(count==2)
print('melee hands use untouched first-person animation and rotate around its root passed')
