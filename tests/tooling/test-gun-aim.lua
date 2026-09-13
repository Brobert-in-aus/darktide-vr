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
    from_elements=function(...) return {...} end,
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
local pitch_setting
local instance=Alignment.install({get=function() return pitch_setting end,
    info=function(_,format) if format:find('fallback',1,true) then messages=messages+1 end end},presentation)
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
for _,kind in ipairs({'reload','reload_state','reload_shotgun','ranged_wield','unwield'}) do
    settings={kind=kind}; local_rotation=q(.9,-.7,.4)
    instance.update(world,source); near(Unit.world_rotation(muzzle,1),aim)
    near_position(Unit.world_position(source,2),grip)
end
settings=nil; instance.update(world,source)
local engine_authored=q(.4,-.2,.8)
local_rotation=engine_authored; local_position={.9,.8,.7}; active=false
instance.update(world,source); near(local_rotation,engine_authored)
near_position(local_position,{.9,.8,.7})
active=true; dominant='left'; instance.update(world,source); near(local_rotation,engine_authored)
local aligned=false
presentation.body_proxy={align_gun_hand=function(_,_,_,_,_,_,side) assert(side=='left'); return aligned end}
local prior_writes=instance.writes
instance.update(world,source); near(local_rotation,engine_authored)
assert(instance.writes==prior_writes,'Unavailable destination glove left an aligned gun behind')
aligned=true; instance.update(world,source)
near(Unit.world_rotation(muzzle,1),aim); near_position(Unit.world_position(source,2),grip)
assert(instance.writes==prior_writes+1)
dominant=nil; instance.update(world,source); near(local_rotation,engine_authored)
presentation.body_proxy=nil
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
presentation.gun_aim=instance
Managers={player={local_player=function() return {player_unit=source} end}}
local chunk=assert(loadstring(main:sub(first,last-1)))
setfenv(chunk,setmetatable({presentation=presentation},{__index=_G})); chunk()
local p,r=presentation.weapon_aim_target('dominant'); assert(p==42); near(r,mul(raw,q(math.rad(-10),0,0)))
-- A level controller's barrel pitches down, with unchanged heading.
local down=rotate(Alignment.pitch(q(0,0,0),-10),{0,1,0})
assert(math.abs(down[1])<1e-8 and math.abs(down[3]+math.sin(math.rad(10)))<1e-8)
pitch_setting=15; p,r=presentation.weapon_aim_target('dominant'); near(r,mul(raw,q(math.rad(15),0,0)))
pitch_setting=0; p,r=presentation.weapon_aim_target('dominant'); near(r,raw)
-- Every weapon and item shares the pitch, so switching never moves the crosshair.
pitch_setting=-10
local pitched=mul(raw,q(math.rad(-10),0,0))
for _,item in ipairs({{keywords={'force_staff'}},{actions={swing={kind='sweep'}}},{}}) do
    template=item; p,r=presentation.weapon_aim_target('dominant'); near(r,pitched)
end
p,r=presentation.weapon_aim_target('support'); assert(p==24); near(r,raw)
-- A left-handed player gets the same pitch on the left controller.
dominant='left'; p,r=presentation.weapon_aim_target('dominant'); assert(p==24); near(r,pitched)
dominant='right'
-- The shared aim reader applies pitch once, then the support correction. The
-- calibration/base reader must not feed the corrected pose back into itself.
template={actions={shoot={kind='shoot_hit_scan'}}}
local base=mul(raw,q(math.rad(-10),0,0))
local correction=q(0,0,.2)
local support_calls=0
presentation.two_hand={resolve=function(unit,rotation)
    assert(unit==source); near(rotation,base); support_calls=support_calls+1
    return mul(rotation,correction)
end}
p,r=presentation.weapon_aim_target('dominant'); near(r,mul(base,correction))
near(instance.base_aim(source,raw),base)
assert(support_calls==1,'Base pose recursively used two-hand aim')
p,r=presentation.weapon_aim_target('support'); near(r,raw)
assert(support_calls==1,'Support controller received the gun correction')
presentation.two_hand=nil
-- Execute the actual visible-hand correction with a separate visual root.
local body_file=assert(io.open(arg[2]:gsub('darktidevr.lua$','darktidevr_body_proxy.lua'),'rb'))
local body=body_file:read('*a'); body_file:close()
local begin=assert(body:find('function BodyProxy.convert_hand_rotation(',1,true))
local finish=assert(body:find('\nfunction BodyProxy.follow_gameplay_hands(',begin,true))
local vmeta={}; local function vec(a) return setmetatable(a,vmeta) end
vmeta.__add=function(a,b) return vec(add(a,b)) end
vmeta.__sub=function(a,b) return vec(add(a,scale(b,-1))) end
Quaternion.rotate=function(r,v) return vec(rotate(r,v)) end
local wrist_offset={.03,-.04,.02}; local wrist_basis=q(.3,.5,.2)
local oldp,newp=vec({2,3,4}),vec({-1,4,2})
local oldr,newr=q(.4,-.3,.2),q(-.5,.8,.6)
local proxy={rigid_hands_active=function() return true end}
local visible_hand={}; local placed
local opposite_hand={}
local hands={right=visible_hand,left=opposite_hand}
local expected_hand=visible_hand
local expected_rotation=mul(newr,wrist_basis)
local hand_chunk=assert(loadstring(body:sub(begin,finish-1)))
setfenv(hand_chunk,setmetatable({BodyProxy=proxy,state={source_unit=source},
    rigid_hands=hands,inverse_quaternion=Quaternion.inverse,
    Unit={alive=function() return true end,has_node=function() return true end,node=function() return 8 end,
        world_position=function() return oldp+Quaternion.rotate(oldr,wrist_offset) end,
        world_rotation=function() return mul(oldr,wrist_basis) end},
    place_rigid_hand=function(w,hand,pos,rot,authored)
        assert(w==world and hand==expected_hand and authored)
        near_position(pos,newp+Quaternion.rotate(newr,wrist_offset)); near(rot,expected_rotation)
        placed=true; return true
    end},{__index=_G})); hand_chunk()
assert(proxy.align_gun_hand(world,source,oldp,oldr,newp,newr) and placed)
assert(not proxy.align_gun_hand(world,{},oldp,oldr,newp,newr))
placed=false
assert(not proxy.align_gun_hand(world,source,oldp,oldr,newp,newr,'left') and not placed)
hands.right.anatomy_inverse=QuaternionBox(q(.2,-.7,.9))
hands.left.anatomy_inverse=QuaternionBox(q(-.6,.4,-.3))
expected_hand=opposite_hand
expected_rotation=mul(mul(mul(newr,wrist_basis),Quaternion.inverse(hands.right.anatomy_inverse:unbox())),hands.left.anatomy_inverse:unbox())
assert(proxy.align_gun_hand(world,source,oldp,oldr,newp,newr,'left') and placed)
assert(not proxy.align_gun_hand(world,source,oldp,oldr,newp,newr,'unknown'))
print('PASS controller gun pitch/hand: 120 poses, pitch sign/live setting/shared pitch for every item and hand, draw/reload ownership, actual simulation reader and rigid-hand relative grip preservation')
