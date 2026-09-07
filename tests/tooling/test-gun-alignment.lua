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
local source,muzzle,world={},{},{}
local parent,original,relative=q(.2,-.4,.6),q(.5,.3,-.2),q(-.7,.5,.4)
local local_rotation=original
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
    world_rotation=function(unit,node)
        if unit==muzzle then return mul(mul(parent,local_rotation),relative) end
        assert(unit==source); return node==1 and parent or mul(parent,local_rotation)
    end,
    set_local_rotation=function(unit,node,value) assert(unit==source and node==2); local_rotation=value end}
World={update_unit_and_children=function(w,u) assert(w==world and u==source) end}
local messages=0
local instance=Alignment.install({info=function(_,format) if format:find('fallback',1,true) then messages=messages+1 end end},
    {online_rules={simulation_aim_active=function(unit) return active and unit==source end},
        weapon_hand_roles={physical=function() return dominant end},weapon_aim_target=function() return nil,aim end})
for i=1,120 do
    parent=q(.01*i,.3,-.6)
    aim=q(.2,.02*i,-.4)
    instance.update(world,source)
    near(Unit.world_rotation(muzzle,1),aim)
end
assert(instance.writes==120 and instance.failures==0)
template={keywords={'force_staff'},actions={shoot={kind='shoot_hit_scan'}}}
instance.update(world,source); near(local_rotation,original)
template={actions={shoot={kind='shoot_pellets'}}}
instance.update(world,source); near(Unit.world_rotation(muzzle,1),aim)
settings={kind='reload'}; instance.update(world,source); near(local_rotation,original)
settings=nil; instance.update(world,source)
local engine_authored=q(.4,-.2,.8)
local_rotation=engine_authored; active=false
instance.update(world,source); near(local_rotation,engine_authored)
active=true; dominant='left'; instance.update(world,source); near(local_rotation,engine_authored)
dominant='right'; instance.update(world,source)
aim=nil; instance.update(world,source); near(local_rotation,engine_authored)
aim=q(.3,.2,.1)
weapon._fx_extension.vfx_spawner_unit_and_node=function() error('retired muzzle') end
instance.update(world,source); instance.update(world,source)
assert(messages==1 and instance.failures==2); near(local_rotation,engine_authored)
assert(not Alignment.is_gun({actions={fire={kind='flamer_gas'}}}))
print('PASS gun alignment: 120 multi-axis parent/aim poses, stable attachment, stock/staff/reload restoration, ownership, lost tracking and failure isolation')
