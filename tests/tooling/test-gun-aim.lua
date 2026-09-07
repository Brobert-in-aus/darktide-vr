local Alignment=dofile(assert(arg[1]))
local function mul(a,b)
    return {a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],
        a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],
        a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],
        a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}
end
local function q(x,y,z)
    return mul(mul({math.sin(x/2),0,0,math.cos(x/2)},
        {0,math.sin(y/2),0,math.cos(y/2)}),{0,0,math.sin(z/2),math.cos(z/2)})
end
local function near(a,b)
    local dot=0; for i=1,4 do dot=dot+a[i]*b[i] end
    assert(math.abs(dot)>1-1e-8,'muzzle orientation mismatch')
end
Quaternion={multiply=mul,inverse=function(a) return {-a[1],-a[2],-a[3],a[4]} end,
    to_elements=function(a) return unpack(a) end}
QuaternionBox=function(a) local copy={unpack(a)}; return {unbox=function() return copy end} end
Vector3Box=QuaternionBox
local function rotate(r,v)
    local out=mul(mul(r,{v[1],v[2],v[3],0}),Quaternion.inverse(r))
    return {out[1],out[2],out[3]}
end
local function add(a,b) return {a[1]+b[1],a[2]+b[2],a[3]+b[3]} end
local function scale(a,s) return {a[1]*s,a[2]*s,a[3]*s} end
Vector3={distance=function(a,b)
    return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2+(a[3]-b[3])^2)
end}
local function near_position(a,b) assert(Vector3.distance(a,b)<1e-8,'controller grip placement mismatch') end
Matrix4x4={inverse=function(m) return {rotation=m.rotation,position=m.position,scale=m.scale,inverse=true} end,
    transform=function(m,p)
        assert(m.inverse)
        return scale(rotate(Quaternion.inverse(m.rotation),add(p,scale(m.position,-1))),1/m.scale)
    end}
local source,muzzle,world={},{},{}
local parent,original,relative=q(.2,-.4,.6),q(.5,.3,-.2),q(-.7,.5,.4)
local local_rotation=original
local original_position={.3,-.1,.2}
local local_position=original_position
local parent_position,parent_scale={4,-6,1},1.3
local grip={3,2,1}
local template={actions={shoot={kind='shoot_hit_scan'}}}
local settings,aim,active,dominant=nil,q(.1,.9,-.8),true,'right'
local weapon={_inventory_component={},_weapons={},
    weapon_template=function() return template end,running_action_settings=function() return settings end,
    _wielded_weapon=function() return {fx_sources={_muzzle='muzzle'}} end,
    _fx_extension={vfx_spawner_unit_and_node=function() return nil,nil,muzzle,1 end}}
ScriptUnit={has_extension=function(unit,name) assert(unit==source and name=='weapon_system'); return weapon end}
Unit={alive=function(unit) return not unit.dead end,
    has_node=function(unit,name) return unit==source and name=='j_rightweaponattach' end,
    node=function() return 2 end,scene_graph_parent=function() return 1 end,
    local_rotation=function(unit,node) assert(unit==source and node==2); return local_rotation end,
    local_position=function(unit,node) assert(unit==source and node==2); return local_position end,
    world_pose=function(unit,node) assert(unit==source and node==1); return {rotation=parent,position=parent_position,scale=parent_scale} end,
    world_position=function(unit,node) assert(unit==source and node==2); return add(parent_position,rotate(parent,scale(local_position,parent_scale))) end,
    world_rotation=function(unit,node)
        if unit==muzzle then return mul(mul(parent,local_rotation),relative) end
        assert(unit==source); return node==1 and parent or mul(parent,local_rotation)
    end,
    set_local_rotation=function(unit,node,value) assert(unit==source and node==2); local_rotation=value end,
    set_local_position=function(unit,node,value) assert(unit==source and node==2); local_position=value end}
World={update_unit_and_children=function(w,u) assert(w==world and u==source) end}
local messages=0
local presentation={online_rules={simulation_aim_active=function(unit) return active and unit==source end},
    weapon_hand_roles={physical=function(role) return role=='support' and 'left' or dominant end},
    weapon_aim_target=function() return nil,aim end,weapon_grip_target=function() return grip end}
local instance=Alignment.install({info=function(_,format) if format:find('fallback',1,true) then messages=messages+1 end end},presentation)
for i=1,120 do
    parent=q(.01*i,.3,-.6)
    aim=q(.2,.02*i,-.4)
    grip={.03*i,.02*i,1+.001*i}; parent_scale=.7+.01*i
    instance.update(world,source)
    near(Unit.world_rotation(muzzle,1),aim)
    near_position(Unit.world_position(source,2),grip)
end
assert(instance.writes==120 and instance.failures==0)
template={keywords={'force_staff'},actions={shoot={kind='shoot_hit_scan'}}}
instance.update(world,source); near(local_rotation,original)
near_position(local_position,original_position)
template={actions={shoot={kind='shoot_pellets'}}}
instance.update(world,source); near(Unit.world_rotation(muzzle,1),aim)
settings={kind='reload'}; instance.update(world,source); near(local_rotation,original)
near_position(local_position,original_position)
settings=nil; instance.update(world,source)
local engine_authored=q(.4,-.2,.8)
local_rotation=engine_authored; local_position={.9,.8,.7}; active=false
instance.update(world,source); near(local_rotation,engine_authored)
near_position(local_position,{.9,.8,.7})
active=true; dominant='left'; instance.update(world,source); near(local_rotation,engine_authored)
dominant='right'; instance.update(world,source)
aim=nil; instance.update(world,source); near(local_rotation,engine_authored)
aim=q(.3,.2,.1)
weapon._fx_extension.vfx_spawner_unit_and_node=function() error('retired muzzle') end
instance.update(world,source); instance.update(world,source)
assert(messages==1 and instance.failures==2); near(local_rotation,engine_authored)
assert(not Alignment.is_gun({actions={fire={kind='flamer_gas'}}}))
-- Actual simulation reader must ignore all animated hand/muzzle orientations.
local file=assert(io.open(assert(arg[2]),'rb')); local main=file:read('*a'); file:close()
local first=assert(main:find('function presentation.weapon_aim_target(',1,true))
local last=assert(main:find('\nfunction presentation.weapon_grip_target(',first,true))
local raw=q(.6,.2,-.7)
presentation.controller_aim_target=function() return 42,raw end
presentation.left_controller_aim_target=function() return 24,raw end
presentation.weapon_grip_target=function() error('Simulation aim read hand/grip basis') end
presentation.gun_aim={aim=function() error('Simulation aim used animated weapon basis') end}
local chunk=assert(loadstring(main:sub(first,last-1)))
setfenv(chunk,setmetatable({presentation=presentation},{__index=_G})); chunk()
local p,r=presentation.weapon_aim_target('dominant'); assert(p==42); near(r,raw)
p,r=presentation.weapon_aim_target('support'); assert(p==24); near(r,raw)
print('PASS controller gun alignment: 120 translated/rotated/scaled parent poses, controller grip placement, native aim reader, independent animation restoration, staff/reload/ownership/tracking guards')
