-- Real exported force-sword frames and full stock spline evaluator, with
-- mathematical value-type fixtures. Does not render, track, collide or attack.
local root,preview_path=assert(arg[1]),assert(arg[2])
local V={}
local function vec(x,y,z) return setmetatable({x=x,y=y,z=z},V) end
V.__add=function(a,b) return vec(a.x+b.x,a.y+b.y,a.z+b.z) end
V.__mul=function(a,b) return vec(a.x*b,a.y*b,a.z*b) end
Vector3=setmetatable({x=function(v) return v.x end,y=function(v) return v.y end,z=function(v) return v.z end},
    {__call=function(_,...) return vec(...) end})
-- Rotation fixtures use orthonormal basis columns instead of quaternion storage.
Quaternion={}
Quaternion.rotate=function(r,v) return r[1]*v.x+r[2]*v.y+r[3]*v.z end
Quaternion.multiply=function(a,b) return {Quaternion.rotate(a,b[1]),Quaternion.rotate(a,b[2]),Quaternion.rotate(a,b[3])} end
Quaternion.up=function(r) return r[3] end
Quaternion.forward=function(r) return r[2] end
Matrix4x4={from_elements=function(...) local m={...}; return {
    rotation={vec(m[1],m[2],m[3]),vec(m[4],m[5],m[6]),vec(m[7],m[8],m[9])},
    position=vec(m[10],m[11],m[12])} end,
    translation=function(m) return m.position end,rotation=function(m) return m.rotation end}
Matrix4x4Box=setmetatable({unbox=function(m) return m end},{__call=function(_,m) return m end})
local env=setmetatable({math=setmetatable({round=function(n) return math.floor(n+.5) end},{__index=math}),
    dofile=function(path) return dofile(root..'/'..path..'.lua') end,
    class=function() local c={}; c.__index=c
        function c:new(...) local self=setmetatable({},c); self:init(...); return self end
        return c
    end},{__index=_G})
local Spline=setfenv(assert(loadfile(root..'/scripts/extension_systems/weapon/actions/utilities/sweep_spline_exported.lua')),env)()
local Sweep={}
env.ActionSweep=Sweep
env.ActionSweepSettings={sweep_width_mod=1,sweep_height_mod=1,sweep_range_mod=1}
local file=assert(io.open(root..'/scripts/extension_systems/weapon/actions/action_sweep.lua','r'))
local source=file:read('*a'); file:close()
for _,markers in ipairs({{'ActionSweep._modify_sweep_position =','\nActionSweep._run_sphere_sweeps ='},
        {'ActionSweep._weapon_half_extents =','\nlocal DEFAULT_HIT_ANIMS'}}) do
    local first=assert(source:find(markers[1],1,true))
    local last=assert(source:find(markers[2],first,true))
    setfenv(assert(loadstring(source:sub(first,last-1))),env)()
end
-- Parameters transcribed from forcesword_p1_m1.action_left_diagonal_light.
local settings={kind='sweep',damage_window_start=.15,damage_window_end=.25,range_mod=1.25,weapon_box={.15,.15,1.2}}
local asset='content/characters/player/human/first_person/animations/force_sword/attack_left_diagonal_down'
local spline=Spline:new(settings,asset,{0,0,-.125})
local instance=setmetatable({_action_settings=settings,_weapon_template={},_uses_matrix_data=true,_sweep_splines={spline}}, {__index=Sweep})
local Preview=dofile(preview_path)
local origin=vec(4,5,6)
local rotations={{vec(1,0,0),vec(0,1,0),vec(0,0,1)},
    {vec(0,1,0),vec(-1,0,0),vec(0,0,1)},
    {vec(1,0,0),vec(0,0,1),vec(0,-1,0)}}
local exported=dofile(root..'/'..asset..'.lua')
local function close(a,b)
    assert(math.abs(a.x-b.x)<1e-6 and math.abs(a.y-b.y)<1e-6 and math.abs(a.z-b.z)<1e-6,'Exported frame geometry disagrees')
end
for _,rotation in ipairs(rotations) do
    local result=assert(Preview.sample(instance,origin,rotation))
    assert(#result.paths[1]==spline._num_frames and spline._num_frames>2)
    assert(result.half_extents.z==1.5)
    for i,point in ipairs(result.paths[1]) do
        local data=assert(exported[spline._frame_to_time_map[i]])
        -- Independent reference from raw matrix translation and its up column.
        local base=origin+Quaternion.rotate(rotation,vec(data[13],data[14],data[15]-.125))
        local up=Quaternion.rotate(rotation,vec(data[9],data[10],data[11]))
        close(point.base,base); close(point.center,base+up*1.5); close(point.tip,base+up*3)
    end
end
print('melee_preview_spline_stock=pass exported_frames='..spline._num_frames..' reference_rotations=3 anchor extent center tip')
print('LIMIT: value-type math and action parameters are fixtures; no live GUI, tracking, collisions or authoritative damage')
