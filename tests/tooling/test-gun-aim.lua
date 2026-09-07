local GunAim=dofile(assert(arg[1]))
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
    assert(a and b,'missing aim')
    local dot=0; for i=1,4 do dot=dot+a[i]*b[i] end
    assert(math.abs(dot)>1-1e-8,'held muzzle aim mismatch')
end
Quaternion={multiply=mul,inverse=function(a) return {-a[1],-a[2],-a[3],a[4]} end}
QuaternionBox=function(a) local copy={unpack(a)}; return {unbox=function() return copy end} end
local source,muzzle,world={},{},{}
local grip,basis=q(.2,-.4,.6),q(-.7,.5,.4)
local template={name='fixture_gun',actions={shoot={kind='shoot_hit_scan'}}}
local held={fx_sources={_muzzle='muzzle'}}
local settings,active,dominant=nil,true,'right'
local pose_reads,messages=0,0
local weapon={_inventory_component={},_weapons={},
    weapon_template=function() return template end,running_action_settings=function() return settings end,
    _wielded_weapon=function() return held end,
    _fx_extension={vfx_spawner_unit_and_node=function() return nil,nil,muzzle,1 end}}
ScriptUnit={has_extension=function(unit,name) assert(unit==source and name=='weapon_system'); return weapon end}
Unit={alive=function(unit) return unit and not unit.dead end,
    world_rotation=function(unit,node) assert(unit==muzzle and node==1); pose_reads=pose_reads+1; return mul(grip,basis) end,
    set_local_rotation=function() error('Aim calibration moved the weapon') end,
    set_local_position=function() error('Aim calibration moved the grip') end}
local presentation={online_rules={simulation_aim_active=function(unit) return active and unit==source end},
    weapon_hand_roles={physical=function(role) return role=='support' and 'left' or dominant end},
    weapon_grip_target=function() return nil,grip end}
local instance=GunAim.install({info=function() messages=messages+1 end},presentation)
instance.update(world,source)
for i=1,120 do
    grip=q(.01*i,.3,.02*i)
    -- Resolve newer live tracking without recapturing the animated weapon.
    near(instance.aim(source,grip),mul(grip,basis))
    instance.update(world,source)
end
assert(pose_reads==1 and messages==1 and instance.failures==0)
assert(instance.aim({},grip)==nil and instance.aim(source,nil)==nil)
settings={kind='shoot_hit_scan'}; instance.update(world,source)
near(instance.aim(source,grip),mul(grip,basis)); assert(pose_reads==1)
template={keywords={'force_staff'},actions={shoot={kind='shoot_hit_scan'}}}
assert(instance.aim(source,grip)==nil)
instance.update(world,source)
template={actions={shoot={kind='shoot_pellets'}}}; held={fx_sources={_muzzle='muzzle'}}
settings={kind='reload_state'}; instance.update(world,source); assert(instance.aim(source,grip)==nil)
settings=nil; instance.update(world,source); near(instance.aim(source,grip),mul(grip,basis))
muzzle.dead=true; assert(instance.aim(source,grip)==nil)
muzzle={}; instance.update(world,source); near(instance.aim(source,grip),mul(grip,basis))
active=false; assert(instance.aim(source,grip)==nil); instance.update(world,source)
active=true; dominant='left'; instance.update(world,source); assert(instance.aim(source,grip)==nil)
dominant='right'; instance.update(world,source)
-- Exercise the actual aim reader used by the online fixed-input author.
local file=assert(io.open(assert(arg[2]),'rb')); local main=file:read('*a'); file:close()
local first=assert(main:find('function presentation.weapon_aim_target(',1,true))
local last=assert(main:find('\nfunction presentation.weapon_grip_target(',first,true))
local raw=q(.6,.2,-.7)
presentation.gun_aim=instance
presentation.controller_aim_target=function() return 42,raw end
presentation.left_controller_aim_target=function() return 24,raw end
Managers={player={local_player=function() return {player_unit=source} end}}
local chunk=assert(loadstring(main:sub(first,last-1)))
setfenv(chunk,setmetatable({presentation=presentation},{__index=_G})); chunk()
local p,r=presentation.weapon_aim_target('dominant'); assert(p==42); near(r,mul(grip,basis))
p,r=presentation.weapon_aim_target('support'); assert(p==24); near(r,raw)
template={keywords={'force_staff'}}
p,r=presentation.weapon_aim_target('dominant'); assert(p==42); near(r,raw)
print('PASS gun aim: 120 multi-axis live grip poses, no attachment writes, resting basis cache, stock recoil isolation, owner/weapon/tracking guards and actual input reader')
