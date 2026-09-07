-- Surface classification only; no game systems or raycasts execute.
require = function() return {} end
local aim = assert(loadfile(arg[1]))()
assert(not aim.is_reticle_surface(false, false, true, "afro"),
    "suppression volume stopped the reticle")
assert(not aim.is_reticle_surface(false, true, true, "afro"),
    "static classification bypassed suppression exclusion")
assert(not aim.is_reticle_surface(true, false, true, "torso"),
    "local body stopped the reticle")
assert(not aim.is_reticle_surface(false, false, true, nil),
    "movement capsule stopped the reticle")
assert(aim.is_reticle_surface(false, false, true, "torso"))
assert(aim.is_reticle_surface(false, false, true, "shield"))
assert(aim.is_reticle_surface(false, true, false, nil))
print("reticle_surfaces=pass")

-- Execute the real publication/convergence cache against changing owners.
local f=assert(io.open(arg[1],'r')); local source=f:read('*all'); f:close()
local first=assert(source:find('    function controller_aim.clear_reticle(',1,true))
local last=assert(source:find('\n    function controller_aim.staff_tip(',first,true))
local mt={}
local function v(x,y,z) return setmetatable({x,y,z},mt) end
mt.__add=function(a,b) return v(a[1]+b[1],a[2]+b[2],a[3]+b[3]) end
mt.__sub=function(a,b) return v(a[1]-b[1],a[2]-b[2],a[3]-b[3]) end
mt.__mul=function(a,b) return v(a[1]*b,a[2]*b,a[3]*b) end
local function length_squared(a) return a[1]^2+a[2]^2+a[3]^2 end
local function normalize(a) return a*(1/math.sqrt(length_squared(a))) end
Vector3={length_squared=length_squared,normalize=normalize}
Vector3Box=function(a) return {unbox=function() return a end} end
Quaternion={forward=function(q) return q.forward end,up=function() return v(0,0,1) end,
    look=function(direction) return direction end}
local owner,session={},{}
local player={player_unit=owner}
Managers={player={local_player=function() return player end},state={game_session=session}}
Unit={alive=function(unit) return not unit.dead end}
local native_active,fail_query
local state={last_sequence=100,last_transport_generation=1}
local presentation={publish_gameplay_aim_state=function(active) native_active=active; return true end}
local env=setmetatable({controller_aim=aim,state=state,presentation=presentation,
    mod={info=function() end,error=function() end}}, {__index=_G})
local owner_first=assert(source:find('local function is_local_unit(',1,true))
local owner_last=assert(source:find('\nlocal function is_local_visual_unit(',owner_first,true))
local code=source:sub(owner_first,owner_last-1)..'\n'..source:sub(first,last-1)
setfenv(assert(loadstring(code)),env)()
PhysicsWorld={raycast=function()
    if fail_query then error('ray unavailable') end
    return {},0
end}
for _,name in ipairs({'reticle_publishes','reticle_misses','reticle_failures',
        'last_reticle_log_sequence','convergence_fallbacks','converged_writes'}) do aim[name]=0 end
aim.target=function() end
local origin=v(0,0,0); local ray={forward=v(1,0,0)}; local current={forward=v(0,1,0)}
local extension={_unit=owner,_physics_world='physics'}
local function publish()
    state.last_sequence=100; state.last_transport_generation=1
    player.player_unit=owner; Managers.state.game_session=session
    aim.publish_reticle(extension,origin,ray)
    assert(native_active)
end
local function expect(direction)
    local result,written=aim.converged_rotation(origin,origin,current)
    assert(written and length_squared(result-direction)<1e-12,'stale reticle cache redirected weapon convergence')
end
publish(); expect(v(1,0,0))
state.last_sequence=160; expect(v(1,0,0))
state.last_sequence=161; expect(v(0,1,0))
publish(); state.last_sequence=99; expect(v(0,1,0))
publish(); state.last_sequence=110; state.last_transport_generation=2; expect(v(0,1,0))
publish(); player.player_unit={}; expect(v(0,1,0))
publish(); owner.dead=true; expect(v(0,1,0)); owner.dead=false
publish(); Managers.state.game_session={}; expect(v(0,1,0))
publish(); aim.publish_reticle(extension); assert(not native_active); expect(v(0,1,0))
publish(); fail_query=true; aim.publish_reticle(extension,origin,ray)
assert(not native_active); expect(v(0,1,0))
print('reticle cache rejects backwards age, publisher/player/session changes and failed observations')
