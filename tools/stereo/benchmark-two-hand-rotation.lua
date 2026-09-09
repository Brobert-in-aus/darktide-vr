-- Pure geometry comparison; no game, tracking, rendering or input hooks.
local ffi=require('ffi')
ffi.cdef[[int __stdcall QueryPerformanceCounter(int64_t* value);
int __stdcall QueryPerformanceFrequency(int64_t* value);]]
local counter,frequency=ffi.new('int64_t[1]'),ffi.new('int64_t[1]')
assert(ffi.C.QueryPerformanceFrequency(frequency)~=0)
local function now()
    assert(ffi.C.QueryPerformanceCounter(counter)~=0)
    return tonumber(counter[0])/tonumber(frequency[0])
end
local variants={baseline=dofile(assert(arg[1])),candidate=dofile(assert(arg[2]))}
local cases={}
for i=1,10000 do
    local scale=10^((i%25)-12)
    cases[i]={{math.sin(i*.011)*scale,math.cos(i*.017)*scale,
        math.sin(i*.021)*scale,math.cos(i*.027)*scale},
        {math.sin(i*.01),math.cos(i*.01),1},
        {math.sin(i*.01)+.1,math.cos(i*.01)+.3,1.1},
        {.02,.3,.01},{0,0,0,1}}
end
local function equal(a,b)
    assert(type(a)==type(b))
    if type(a)=='table' then
        assert(#a==#b)
        for i=1,#a do equal(a[i],b[i])end
    else assert(a==b or (type(a)=='number' and a~=a and b~=b))end
end
local function compare(case)
    local q,p,s,k,r=unpack(case)
    equal(variants.baseline.near(q,p,s,k,.15),variants.candidate.near(q,p,s,k,.15))
    equal(variants.baseline.socket(q,p,s),variants.candidate.socket(q,p,s))
    equal(variants.baseline.correction(q,p,s,k),variants.candidate.correction(q,p,s,k))
    local a,b=variants.baseline.hand(q,p,k,r)
    local x,y=variants.candidate.hand(q,p,k,r)
    equal(a,x);equal(b,y)
end
for _,case in ipairs(cases)do compare(case)end
for _,invalid in ipairs({0/0,math.huge,-math.huge,1e300})do
    compare({{0,0,0,1},{0,0,0},{invalid,.3,0},{0,.3,0},{0,0,0,1}})
    compare({{invalid,0,0,1},{0,0,0},{0,.3,0},{0,.3,0},{0,0,0,1}})
end
local function workload(module,case)
    local q,p,s,k,r=unpack(case)
    module.near(q,p,s,k,.15)
    module.socket(q,p,s)
    module.correction(q,p,s,k)
    return module.hand(q,p,k,r)
end
for trial=1,5 do
    local order=trial%2==1 and {'baseline','candidate'} or {'candidate','baseline'}
    for _,name in ipairs(order)do
        local module=variants[name]
        for i=1,3000 do workload(module,cases[i])end
        collectgarbage('collect');collectgarbage('stop')
        local memory=collectgarbage('count');local start=now()
        for _,case in ipairs(cases)do workload(module,case)end
        local elapsed=(now()-start)*1000
        local growth=collectgarbage('count')-memory
        collectgarbage('restart');collectgarbage('collect')
        print(string.format('version=%s trial=%d groups=10000 wall_ms=%.4f heap_growth_kib=%.4f',name,trial,elapsed,growth))
    end
end
print('PASS exact_geometry_results=10000 invalid_results=matched')
