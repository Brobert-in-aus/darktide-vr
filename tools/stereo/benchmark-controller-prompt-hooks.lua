-- Explicit offline comparison: pinned LuaJIT, then baseline and candidate module paths.
local ffi=require('ffi')
ffi.cdef[[int __stdcall QueryPerformanceCounter(int64_t* value);
int __stdcall QueryPerformanceFrequency(int64_t* value);]]
local counter,frequency=ffi.new('int64_t[1]'),ffi.new('int64_t[1]')
assert(ffi.C.QueryPerformanceFrequency(frequency)~=0)
local ticks_per_second=tonumber(frequency[0])
local function now()
    assert(ffi.C.QueryPerformanceCounter(counter)~=0)
    return tonumber(counter[0])/ticks_per_second
end
local before=assert(arg[1],'baseline module required')
local after=assert(arg[2],'candidate module required')
local function install(path)
    local hooks,utils={},{}
    package.loaded['scripts/managers/input/input_utils']=utils
    package.loaded['scripts/managers/ui/ui_renderer']={}
    local mod={hook=function(_,class,name,fn)
        hooks[class]=hooks[class] or {};hooks[class][name]=fn
    end}
    dofile(path).install(mod,{revision=0},function()return true end)
    local self={_update_input=function()end}
    local renderer={scale=1}
    local scope=hooks.HudElementPlayerWeapon._update_input
    local update=hooks.HudElementPlayerWeapon.update
    local function pack(...)return {n=select('#',...),...}end
    local token={}
    local function values()return nil,17,nil,token,nil end
    for _,call in ipairs({function(fn)return scope(fn)end,
            function(fn)return update(fn,self,0,0,renderer)end})do
        local result=pack(call(values))
        assert(result.n==5 and result[1]==nil and result[2]==17 and result[3]==nil and result[4]==token and result[5]==nil)
        assert(pack(call(function()end)).n==0)
        local ok,err=pcall(call,function()error(token,0)end)
        assert(not ok and err==token,'error identity changed')
    end
    local function stock()return nil,17,nil end
    return {scope=function()
        local a,b,c=scope(stock);assert(a==nil and b==17 and c==nil)
    end,update=function()
        local a,b,c=update(stock,self,0,0,renderer);assert(a==nil and b==17 and c==nil)
    end}
end
local variants={baseline=install(before),candidate=install(after)}
for _,workload in ipairs({'scope','update'})do
    for trial=1,5 do
        local order=trial%2==1 and {'baseline','candidate'} or {'candidate','baseline'}
        for _,name in ipairs(order)do
            local fn=variants[name][workload]
            for _=1,3000 do fn()end
            collectgarbage('collect');collectgarbage('stop')
            local memory=collectgarbage('count')
            local start=now()
            for _=1,100000 do fn()end
            local elapsed=(now()-start)*1000
            local growth=collectgarbage('count')-memory
            collectgarbage('restart');collectgarbage('collect')
            print(string.format('workload=%s version=%s trial=%d calls=100000 wall_ms=%.4f heap_growth_kib=%.4f',workload,name,trial,elapsed,growth))
        end
    end
end
print('PASS nil_return_arity=preserved error_identity=preserved')
