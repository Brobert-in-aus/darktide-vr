local Volume = dofile(arg[1])
local defaults = {sweep_width_mod=1, sweep_height_mod=1, sweep_range_mod=1}
local function close(a,b) assert(math.abs(a-b)<1e-9, tostring(a).." ~= "..tostring(b)) end
local weapon = {weapon_box={.15,.15,1.1}}
local action = {range_mod=1.25}
local box = assert(Volume.resolve(weapon, action, defaults, true))
assert(box.shape == 'oobb')
close(box.half_extents[1], .15)
close(box.half_extents[2], .15)
close(box.half_extents[3], 1.375)
close(box.offset[3], 1.375)
close(box.corner_radius, math.sqrt(.15^2+.15^2+2.75^2))
-- Every corner lies within the origin-based sampling radius; the far blade
-- corner reaches it, whereas using only box half-length would underestimate it.
for sx=-1,1,2 do for sy=-1,1,2 do for sz=-1,1,2 do
    local x,y,z = sx*.15, sy*.15, box.offset[3]+sz*1.375
    assert(math.sqrt(x*x+y*y+z*z) <= box.corner_radius+1e-9)
end end end

local overrides = {weapon_box={1,2,3}, width_mod=2, height_mod=3, range_mod=4}
local scaled = {sweep_width_mod=.5, sweep_height_mod=2, sweep_range_mod=.5}
local modern = assert(Volume.resolve(weapon, overrides, scaled, true))
local legacy = assert(Volume.resolve(weapon, overrides, scaled, false))
close(modern.half_extents[1],1); close(modern.half_extents[2],12); close(modern.half_extents[3],6)
close(legacy.half_extents[1],1); close(legacy.half_extents[2],4); close(legacy.half_extents[3],18)
close(legacy.offset[2],4); close(legacy.offset[3],0)
close(legacy.corner_radius,math.sqrt(1+8^2+18^2))
assert(overrides.weapon_box[2]==2 and weapon.weapon_box[3]==1.1 and scaled.sweep_range_mod==.5)

local sphere=assert(Volume.resolve(nil,{use_sphere_sweep=true,sphere_radius=.4},nil,nil))
assert(sphere.shape=='sphere' and sphere.radius==.4 and sphere.offset[3]==0)
assert(not Volume.resolve(nil,{use_sphere_sweep=true,sphere_radius=0},nil,nil))
assert(not Volume.resolve(weapon,{},defaults,nil), 'missing axis convention was guessed')
assert(not Volume.resolve({}, {}, defaults, true))
assert(not Volume.resolve(weapon,{range_mod=0},defaults,true))
assert(not Volume.resolve(weapon,{range_mod=0/0},defaults,true))
assert(not Volume.resolve(weapon,{range_mod=math.huge},defaults,true))
assert(not Volume.resolve(weapon,{}, {},true), 'missing stock modifiers were guessed')
print('stock box overrides, axis conventions, pivot radius, sphere and invalid geometry passed')
