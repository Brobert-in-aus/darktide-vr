local file = assert(io.open(arg[1], 'r'))
local source = file:read('*all')
file:close()
local first = assert(source:find('function presentation.sync_equipment_hand_pose', 1, true))
local last = assert(source:find('\nfunction presentation.apply_tracked_arms', first, true))

local mt = {}
local function v(x, y, z) return setmetatable({x=x, y=y, z=z}, mt) end
mt.__add = function(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
mt.__sub = function(a,b) return v(a.x-b.x,a.y-b.y,a.z-b.z) end
mt.__div = function(a,b) return v(a.x/b,a.y/b,a.z/b) end
mt.__mul = function(a,b) return v(a.x*b,a.y*b,a.z*b) end
Vector3 = {x=function(a) return a.x end, y=function(a) return a.y end, z=function(a) return a.z end}
-- Rigid yaw rotations exercise inverse-parent composition independently of
-- the production helper. Translation includes a nonzero vertical component.
local function rotate(q,a)
    return v(math.cos(q)*a.x-math.sin(q)*a.y,
        math.sin(q)*a.x+math.cos(q)*a.y,a.z)
end
local function near(a,b)
    assert(math.abs(a.x-b.x)<1e-8 and math.abs(a.y-b.y)<1e-8 and math.abs(a.z-b.z)<1e-8,
        'world hand pose did not reach the proxy')
end
Quaternion = {multiply=function(a,b) return a+b end}
presentation = {
    inverse_quaternion=function(q) return -q end,
    rotate_vector=rotate,
    vector_distance=function(a,b) local d=a-b return math.sqrt(d.x*d.x+d.y*d.y+d.z*d.z) end,
    quaternion_angle_error=function(a,b) return math.abs(a-b) end,
}
local writes, updates, messages = 0, 0, {}
Unit = {
    alive=function(u) return not u.dead end,
    has_node=function(u,n) return u.nodes[n] ~= nil end,
    node=function(u,n) assert(u.nodes[n], 'missing node '..n) return n end,
    scene_graph_parent=function(u,n) return u.nodes[n].parent end,
    world_position=function(u,n) return u.nodes[n].position end,
    world_rotation=function(u,n) return u.nodes[n].rotation end,
    local_scale=function(u,n) assert(n, 'missing scale node') return u.nodes[n].scale or v(1,1,1) end,
    set_local_position=function(u,n,p) writes=writes+1 u.nodes[n].local_position=p end,
    set_local_rotation=function(u,n,q) writes=writes+1 u.nodes[n].local_rotation=q end,
}
World = {update_unit_and_children=function(_,u)
    updates=updates+1
    for _,name in ipairs({'j_lefthand','j_righthand'}) do
        local hand=u.nodes[name]
        if hand and hand.local_position then
            local parent=u.nodes[hand.parent]
            local scale=u.nodes[1].scale.x
            -- Same degenerate-root fallback as the existing scale contract.
            if math.abs(scale)<.001 then scale=1 end
            hand.position=parent.position+rotate(parent.rotation,hand.local_position*scale)
            hand.rotation=parent.rotation+hand.local_rotation
        end
    end
end}
mod = {info=function(_,format,...) messages[#messages+1]=string.format(format,...) end}
assert(loadstring(source:sub(first,last-1)))()

local function units(scale)
    local source_unit={nodes={
        [1]={scale=v(scale,scale,scale)},
        left_parent={position=v(-2,4,1),rotation=.7},
        right_parent={position=v(3,-1,5),rotation=-1.2},
        j_lefthand={parent='left_parent',position=v(0,0,0),rotation=0},
        j_righthand={parent='right_parent',position=v(0,0,0),rotation=0},
        weapon={local_position=v(.1,.2,.3),local_rotation=.4},
    }}
    local proxy={nodes={
        [1]={scale=v(1,1,1)},
        j_lefthand={position=v(8,-5,2),rotation=1.1},
        j_righthand={position=v(-3,6,4),rotation=-.3},
    }}
    controller_observation={}
    writes,updates,messages=0,0,{}
    return source_unit,proxy
end

for _,scale in ipairs({1,1.08,.94,0}) do
    local s,p=units(scale)
    assert(presentation.sync_equipment_hands_to_proxy({},s,p))
    assert(writes==4 and updates==1)
    for _,name in ipairs({'j_lefthand','j_righthand'}) do
        near(s.nodes[name].position,p.nodes[name].position)
        assert(math.abs(s.nodes[name].rotation-p.nodes[name].rotation)<1e-8)
    end
    assert(controller_observation.body_ik_equipment_hand_error<1e-8)
    near(s.nodes.weapon.local_position,v(.1,.2,.3))
    assert(s.nodes.weapon.local_rotation==.4)
    assert(p.nodes.j_lefthand.local_position==nil and p.nodes.j_righthand.local_position==nil,
        'anatomical proxy must not be mutated')
end

-- A partial rig is an explicitly supported result of the per-hand sync.
-- Diagnostics must not resolve the unavailable source hand or parent afterward.
for _,side in ipairs({'left','right'}) do
    for _,missing in ipairs({'source','proxy','parent'}) do
        local s,p=units(1.08)
        local name='j_'..side..'hand'
        if missing=='source' then s.nodes[name]=nil
        elseif missing=='proxy' then p.nodes[name]=nil
        else s.nodes[name].parent=nil end
        assert(presentation.sync_equipment_hands_to_proxy({},s,p))
        assert(writes==2 and updates==1)
        assert(controller_observation.body_ik_equipment_hand_syncs==1)
        local other=side=='left' and 'j_righthand' or 'j_lefthand'
        near(s.nodes[other].position,p.nodes[other].position)
    end
end
local s,p=units(1)
s.nodes.j_lefthand=nil s.nodes.j_righthand=nil
assert(not presentation.sync_equipment_hands_to_proxy({},s,p))
assert(writes==0 and updates==0)
for _,case in ipairs({'same','dead_source','dead_proxy','nil_source'}) do
    s,p=units(1)
    if case=='same' then p=s elseif case=='dead_source' then s.dead=true
    elseif case=='dead_proxy' then p.dead=true else s=nil end
    assert(not presentation.sync_equipment_hands_to_proxy({},s,p))
    assert(writes==0 and updates==0)
end
-- Execute the actual rigid-hand branch with an opposite role policy. Each
-- destination supplies its own placement status; one successful hand cannot
-- authorize a stale pose from the other hand.
local apply_first=assert(source:find('function presentation.apply_tracked_arms(',1,true))
local apply_last=assert(source:find('    -- Rigid hands use authored joint-to-root transforms.',apply_first,true))
assert(loadstring(source:sub(apply_first,apply_last-1)..'\nend'))()
local left_ok,right_ok=true,true
local destination_valid=true
local left_grip,right_grip=.8,-.6
local left_wrist,right_wrist=v(-1,3,2),v(4,2,1)
local source_unit,left_proxy,right_proxy
presentation.refresh_body_anchor_from_avatar=function() end
presentation.body_ik_controller_grip_target=function(_,side)
    if side=='left' then return left_wrist,left_grip end
    return right_wrist,right_grip
end
presentation.body_ik_calibrated_wrist_target=function(_,position) return position end
presentation.weapon_hand_roles={physical=function(role)
    if not destination_valid then return nil end
    return role=='dominant' and 'left' or 'right'
end}
presentation.body_proxy={rigid_hands_active=function() return true end,
    place_rigid_hands=function() return left_proxy,right_proxy,left_ok or right_ok,left_ok,right_ok end,
    equipment_hand_rotation=function(owner,side,grip)
        assert(owner==source_unit)
        return grip+(side=='right' and .2 or -.4) -- Distinct authored bases.
    end}
for _,scale in ipairs({.94,1,1.08}) do
    source_unit,left_proxy=units(scale); right_proxy=left_proxy
    controller_observation.body_ik_presentation_writes=0
    presentation.apply_tracked_arms(left_proxy,1,{},source_unit)
    near(source_unit.nodes.j_righthand.position,left_wrist)
    near(source_unit.nodes.j_lefthand.position,right_wrist)
    assert(math.abs(source_unit.nodes.j_righthand.rotation-(left_grip+.2))<1e-8)
    assert(math.abs(source_unit.nodes.j_lefthand.rotation-(right_grip-.4))<1e-8)
    assert(writes==4)
    assert(left_proxy.nodes.j_lefthand.local_position==nil)
    near(source_unit.nodes.weapon.local_position,v(.1,.2,.3))
end
source_unit,left_proxy=units(1); right_proxy=left_proxy
controller_observation.body_ik_presentation_writes=0
left_ok=false
presentation.apply_tracked_arms(left_proxy,1,{},source_unit)
assert(writes==2 and source_unit.nodes.j_righthand.local_position==nil,'Failed destination retained a stale equipment pose')
destination_valid=false; writes=0
presentation.apply_tracked_arms(left_proxy,1,{},source_unit)
assert(writes==0,'Unknown role fell back to the opposite hand')
left_ok=true; destination_valid=true
presentation.weapon_hand_roles.physical=function(role) return role=='dominant' and 'right' or 'left' end
source_unit,left_proxy=units(1.08); right_proxy=left_proxy
controller_observation.body_ik_presentation_writes=0
presentation.body_proxy.equipment_hand_rotation=function() error('Default policy must retain accepted proxy rotation') end
presentation.apply_tracked_arms(left_proxy,1,{},source_unit)
near(source_unit.nodes.j_lefthand.position,left_proxy.nodes.j_lefthand.position)
near(source_unit.nodes.j_righthand.position,right_proxy.nodes.j_righthand.position)
assert(writes==4)
print('equipment sync preserves scale, item animation, authored bases, role destinations and per-hand placement ownership')
