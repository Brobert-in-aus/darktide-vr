-- Offline actual-module comparison with mathematical engine value doubles.
local ffi=require('ffi')
ffi.cdef[[int __stdcall QueryPerformanceCounter(int64_t* value);
int __stdcall QueryPerformanceFrequency(int64_t* value);]]
local counter,frequency=ffi.new('int64_t[1]'),ffi.new('int64_t[1]')
assert(ffi.C.QueryPerformanceFrequency(frequency)~=0)
local function now()
    assert(ffi.C.QueryPerformanceCounter(counter)~=0)
    return tonumber(counter[0])/tonumber(frequency[0])
end
Vector3=function(x,y,z)return {x=x,y=y,z=z}end
Quaternion={}
function Quaternion.from_elements(x,y,z,w)return {x=x,y=y,z=z,w=w}end
function Quaternion.to_elements(q)return q.x,q.y,q.z,q.w end
function Quaternion.multiply(a,b)
    return Quaternion.from_elements(
        a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
        a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
        a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,
        a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z)
end
function Quaternion.rotate(q,v)
    local r=Quaternion.multiply(Quaternion.multiply(q,
        Quaternion.from_elements(v.x,v.y,v.z,0)),
        Quaternion.from_elements(-q.x,-q.y,-q.z,q.w))
    return Vector3(r.x,r.y,r.z)
end
local variants={baseline=dofile(assert(arg[1])),candidate=dofile(assert(arg[2]))}
local cases={}
for i=1,2000 do
    local yaw=math.sin(i*.031)*.25
    local pitch=math.cos(i*.019)*.2
    local left=variants.baseline.recentered_eye(
        {left=-.9+yaw,right=.7+yaw,down=-.8+pitch,up=.8+pitch},.7+(i%41)/40)
    local right=variants.baseline.recentered_eye(
        {left=-.7-yaw,right=.9-yaw,down=-.8-pitch,up=.8-pitch},.7+(i%37)/40)
    cases[i]={left,right,.025+(i%15)*.001,.1+(i%300)*.01,.5+(i%30)*.04,4}
end
local function workload(module,case)
    return module.binocular_visibility_scale(case[1],case[2]),
        module.binocular_panel_width(unpack(case))
end
for _,case in ipairs(cases)do
    local a,b,c=workload(variants.baseline,case)
    local x,y,z=workload(variants.candidate,case)
    assert(a==x and b==y and c==z,'projection result changed')
end
-- Count real tangent calls separately from timings; wrappers are then removed.
local tangent=math.tan
for _,name in ipairs({'baseline','candidate'})do
    local calls=0
    math.tan=function(value)calls=calls+1;return tangent(value)end
    workload(variants[name],cases[1])
    math.tan=tangent
    print(string.format('version=%s tangent_calls=%d',name,calls))
end
for trial=1,5 do
    local order=trial%2==1 and {'baseline','candidate'} or {'candidate','baseline'}
    for _,name in ipairs(order)do
        local module=variants[name]
        for _,case in ipairs(cases)do workload(module,case)end
        collectgarbage('collect');collectgarbage('stop')
        local memory=collectgarbage('count');local start=now()
        local checksum=0
        for _,case in ipairs(cases)do
            local scale,width=workload(module,case)
            checksum=checksum+scale+width
        end
        local elapsed=(now()-start)*1000
        local growth=collectgarbage('count')-memory
        collectgarbage('restart');collectgarbage('collect')
        assert(checksum>0)
        print(string.format('version=%s trial=%d pairs=2000 wall_ms=%.4f heap_growth_kib=%.4f',name,trial,elapsed,growth))
    end
end
print('PASS exact_projection_results=2000 engine_value_types=mathematical_doubles')
