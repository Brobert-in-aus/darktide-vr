-- Explicit offline comparison of actual modules with small renderer doubles.
local ffi=require('ffi')
ffi.cdef[[int __stdcall QueryPerformanceCounter(int64_t* value);
int __stdcall QueryPerformanceFrequency(int64_t* value);]]
local counter,frequency=ffi.new('int64_t[1]'),ffi.new('int64_t[1]')
assert(ffi.C.QueryPerformanceFrequency(frequency)~=0)
local ticks_per_second=tonumber(frequency[0])
local function now()assert(ffi.C.QueryPerformanceCounter(counter)~=0);return tonumber(counter[0])/ticks_per_second end
package.loaded['scripts/managers/ui/ui_renderer']={}
package.loaded['scripts/managers/ui/ui_widget']={}
package.loaded['scripts/foundation/utilities/script_world']={}
World={create_screen_gui=function()return {}end,destroy_gui=function()end}
Gui={set_visible=function(gui,visible)gui.visible=visible end}
local function install(directory)
    local marker=dofile(directory..'/darktidevr_marker_gui.lua')
    local panel=dofile(directory..'/darktidevr_hud_panel.lua')
    panel.set_enabled(true)
    local original,widget={},{}
    local renderer,self={world={},gui=original},{_widget=widget}
    local function pack(...)return {n=select('#',...),...}end
    local token={}
    local function values()return nil,7,nil,token,nil end
    for _,call in ipairs({function(fn)return marker.draw(renderer,fn)end,
            function(fn)return panel.draw_stock_crosshair(fn,self)end})do
        local result=pack(call(values))
        assert(result.n==5 and result[1]==nil and result[2]==7 and result[3]==nil and result[4]==token and result[5]==nil)
        assert(pack(call(function()end)).n==0)
        local ok,err=pcall(call,function()error(token,0)end)
        assert(not ok and err==token and renderer.gui==original and self._widget==widget)
    end
    local function marker_stock()assert(renderer.gui~=original);return nil,7,nil end
    local function crosshair_stock(owner)assert(owner._widget==nil);return nil,7,nil end
    return {marker=function()
        local a,b,c=marker.draw(renderer,marker_stock)
        assert(a==nil and b==7 and c==nil and renderer.gui==original)
    end,crosshair=function()
        local a,b,c=panel.draw_stock_crosshair(crosshair_stock,self)
        assert(a==nil and b==7 and c==nil and self._widget==widget)
    end,destroy=marker.destroy_all}
end
local variants={baseline=install(assert(arg[1],'baseline directory required')),
    candidate=install(assert(arg[2],'candidate directory required'))}
for _,workload in ipairs({'marker','crosshair'})do
    for trial=1,5 do
        local order=trial%2==1 and {'baseline','candidate'} or {'candidate','baseline'}
        for _,name in ipairs(order)do
            local fn=variants[name][workload]
            for _=1,3000 do fn()end
            collectgarbage('collect');collectgarbage('stop')
            local memory=collectgarbage('count');local start=now()
            for _=1,100000 do fn()end
            local elapsed=(now()-start)*1000;local growth=collectgarbage('count')-memory
            collectgarbage('restart');collectgarbage('collect')
            print(string.format('workload=%s version=%s trial=%d calls=100000 wall_ms=%.4f heap_growth_kib=%.4f',workload,name,trial,elapsed,growth))
        end
    end
end
variants.baseline.destroy();variants.candidate.destroy()
print('PASS renderer_widget_restore=preserved nil_return_arity=preserved error_identity=preserved')
