-- Offline comparison of actual HUD follow modules; no rendering or game access.
local ffi=require('ffi')
ffi.cdef[[int __stdcall QueryPerformanceCounter(int64_t* value);
int __stdcall QueryPerformanceFrequency(int64_t* value);]]
local counter,frequency=ffi.new('int64_t[1]'),ffi.new('int64_t[1]')
assert(ffi.C.QueryPerformanceFrequency(frequency)~=0)
local function now()
    assert(ffi.C.QueryPerformanceCounter(counter)~=0)
    return tonumber(counter[0])/tonumber(frequency[0])
end
package.loaded['scripts/managers/ui/ui_renderer']={}
package.loaded['scripts/managers/ui/ui_widget']={}
package.loaded['scripts/foundation/utilities/script_world']={}
local variants={baseline=dofile(assert(arg[1])).follow_pose,
    candidate=dofile(assert(arg[2])).follow_pose}
local targets={}
for i=1,10000 do
    local angle=math.sin(i*0.013)*0.8
    local sign=i%173==0 and -1 or 1
    targets[i]={x=math.sin(i*0.01)*0.1,y=0,z=0,
        qx=0,qy=math.sin(angle/2)*sign,qz=0,qw=math.cos(angle/2)*sign}
end
local function equal(a,b)
    assert(type(a)==type(b))
    if type(a)~='table' then assert(a==b);return end
    for k,v in pairs(a)do equal(v,b[k])end
    for k in pairs(b)do assert(a[k]~=nil)end
end
local a,b
for i,target in ipairs(targets)do
    local t=i/90
    a=variants.baseline(a,target,t);b=variants.candidate(b,target,t)
    equal(a,b)
    assert(variants.baseline(a,target,t)==a)
    assert(variants.candidate(b,target,t)==b)
end
for _,t in ipairs({-1,1000})do
    for _,fn in pairs(variants)do assert(fn(a,targets[1],t)==targets[1])end
end
local jump={x=100,y=0,z=0,qx=0,qy=0,qz=0,qw=1}
for _,fn in pairs(variants)do assert(fn(a,jump,a.t+0.01)==jump)end
for trial=1,5 do
    local order=trial%2==1 and {'baseline','candidate'} or {'candidate','baseline'}
    for _,name in ipairs(order)do
        local fn=variants[name]
        local previous
        for i=1,3000 do previous=fn(previous,targets[i],i/90)end
        previous=nil
        collectgarbage('collect');collectgarbage('stop')
        local memory=collectgarbage('count');local start=now()
        for i,target in ipairs(targets)do previous=fn(previous,target,i/90)end
        local elapsed=(now()-start)*1000
        local growth=collectgarbage('count')-memory
        collectgarbage('restart');collectgarbage('collect')
        assert(previous.t==10000/90)
        print(string.format('version=%s trial=%d calls=10000 wall_ms=%.4f heap_growth_kib=%.4f',name,trial,elapsed,growth))
    end
end
print('PASS exact_follow_fields=10000 same_time_identity=preserved reset_identity=preserved')
