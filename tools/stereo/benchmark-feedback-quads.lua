-- Actual pure geometry helper comparison; no engine installation or rendering.
local ffi=require('ffi')
ffi.cdef[[int __stdcall QueryPerformanceCounter(int64_t* value);
int __stdcall QueryPerformanceFrequency(int64_t* value);]]
local counter,frequency=ffi.new('int64_t[1]'),ffi.new('int64_t[1]')
assert(ffi.C.QueryPerformanceFrequency(frequency)~=0)
local function now()
    assert(ffi.C.QueryPerformanceCounter(counter)~=0)
    return tonumber(counter[0])/tonumber(frequency[0])
end
local before=dofile(assert(arg[1],'baseline required'))
local after=dofile(assert(arg[2],'candidate required'))
local function equal(a,b)
    assert(type(a)==type(b),'type mismatch')
    if type(a)~='table' then assert(a==b,'value mismatch');return end
    for key,value in pairs(a) do equal(value,b[key]) end
    for key in pairs(b) do assert(a[key]~=nil,'extra field') end
end
local pass={style_id='charge_ring',value='material'}
local offset,pivot={-4,8,0},{3,7}
local uvs,color={{.1,.2},{.8,.9}},{220,10,20,30}
local widget={style={},content={}}
for index=1,2000 do
    local style={size={1+index%79,1+index%43},angle=(index%31-15)*.1,
        offset=index%3==0 and offset or nil,pivot=index%4==0 and pivot or nil,
        uvs=uvs,color=color}
    if index%13==0 then style.offset={0,false} end
    if index%17==0 then style.pivot={false,0} end
    widget.style.charge_ring=style
    local a,b=before.quad(pass,widget),after.quad(pass,widget)
    equal(a,b)
    assert(b.uvs==uvs and b.color==color,'borrowed identity changed')
end
widget.style.charge_ring={size={12,18}}
local first,second=after.quad(pass,widget),after.quad(pass,widget)
assert(first~=second and first.color~=second.color and first.uvs~=second.uvs)
first.color[1]=0;first.uvs[1][1]=9
assert(second.color[1]==255 and second.uvs[1][1]==0,'default ownership changed')
for _,style in ipairs({{size={0,1}},{size={1,1},visible=false}}) do
    widget.style.charge_ring=style; equal(before.quad(pass,widget),after.quad(pass,widget))
end
for _,workload in ipairs({'defaults','offset','explicit'}) do
    widget.style.charge_ring={size={12,18},uvs=uvs,color=color}
    if workload~='defaults' then widget.style.charge_ring.offset=offset end
    if workload=='explicit' then widget.style.charge_ring.pivot=pivot end
    for trial=1,5 do
        local order=trial%2==1 and {'baseline','candidate'} or {'candidate','baseline'}
        for _,name in ipairs(order) do
            local module=name=='baseline' and before or after
            for _=1,3000 do assert(module.quad(pass,widget).w==12) end
            collectgarbage('collect');collectgarbage('stop')
            local memory,start=collectgarbage('count'),now()
            local checksum=0
            for index=1,100000 do
                widget.style.charge_ring.angle=(index%31)*.1
                local q=module.quad(pass,widget)
                checksum=checksum+q.x+q.y+q.w+q.h+q.c+q.s+q.layer+q.color[1]+q.uvs[1][1]+#q.material
            end
            assert(checksum==checksum and checksum>0)
            local elapsed,growth=(now()-start)*1000,collectgarbage('count')-memory
            collectgarbage('restart');collectgarbage('collect')
            print(string.format('workload=%s version=%s trial=%d calls=100000 wall_ms=%.4f heap_growth_kib=%.4f',
                workload,name,trial,elapsed,growth))
        end
    end
end
print('PASS 2000 exact geometry comparisons; returned/default/borrowed identities preserved')
