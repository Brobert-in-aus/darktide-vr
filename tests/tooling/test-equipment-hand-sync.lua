local file = assert(io.open(arg[1], 'r'))
local source = file:read('*all')
file:close()
local first = assert(source:find('function presentation.sync_equipment_hand_to_proxy', 1, true))
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
print('equipment sync preserves scaled world poses, item animation and partial-rig fallback')
