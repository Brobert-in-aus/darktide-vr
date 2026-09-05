local Probe, Volume = dofile(arg[1]), dofile(arg[2])
local vector_mt = {__add=function(a,b)
    return setmetatable({a[1]+b[1],a[2]+b[2],a[3]+b[3]}, getmetatable(a))
end}
Vector3 = function(x,y,z) return setmetatable({x,y,z}, vector_mt) end
Quaternion = {rotate=function(_, v) return Vector3(v[3],v[2],-v[1]) end}
local query, count, calls, actors = nil, 100, 0, {}
for i=1,100 do actors[i] = {} end
PhysicsWorld = {immediate_overlap=function(world,...)
    calls = calls + 1
    query = {world=world}
    local args = {...}
    for i=1,#args,2 do query[args[i]] = args[i+1] end
    return actors,count
end}
local box = assert(Volume.resolve({weapon_box={.15,.15,1.1}}, {},
    {sweep_width_mod=1,sweep_height_mod=1,sweep_range_mod=1}, true))
local world, rotation, origin = {}, {}, Vector3(10,20,30)
local result = assert(Probe.overlap(world,box,origin,rotation,"melee_fixture",0))
assert(query.world == world and query.rotation == rotation and query.shape == "oobb")
assert(query.position[1] == 11.1 and query.position[2] == 20 and query.position[3] == 30,
    "stock half-length offset was not rotated exactly once")
assert(query.size[1] == .15 and query.size[3] == 1.1 and query.types == "both")
assert(query.collision_filter == "melee_fixture" and query.rewind_ms == 0)
assert(result.actor_count == 100 and #result.actors == 100 and not result.capacity_verified)
local saved = result.actors[1]
actors[1] = {}
assert(result.actors[1] == saved, "query reuse changed the saved actor list")
local sphere = assert(Volume.resolve(nil,{use_sphere_sweep=true,sphere_radius=.3}))
Probe.overlap(world,sphere,origin,rotation,"melee_fixture",25)
assert(query.shape == "sphere" and query.size == .3 and query.position[1] == 10)
assert(query.rewind_ms == 25)
count = 0
assert(Probe.overlap(world,box,origin,rotation,"melee_fixture",0).actor_count == 0)
count = 101
local missing, reason = Probe.overlap(world,box,origin,rotation,"melee_fixture",0)
assert(not missing and reason == "incomplete_query_result")
local before = calls
assert(not Probe.overlap(world,box,origin,rotation,"",0))
assert(not Probe.overlap(world,box,origin,rotation,"melee_fixture",-1))
box.half_extents[1] = 0/0
assert(not Probe.overlap(world,box,origin,rotation,"melee_fixture",0))
assert(calls == before, "invalid geometry reached physics")
print("raw overlap geometry, result copying and uncapped Lua candidate collection passed")
