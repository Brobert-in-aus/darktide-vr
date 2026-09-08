local Capture=dofile(arg[1])
local Surface=dofile(arg[2])
local function engine(fail_at, nil_failure)
    local e={live={},calls=0,copies=0,clears=0,destroys=0}
    local function allocate(kind)
        e.calls=e.calls+1
        if e.calls==fail_at then
            if nil_failure then return nil end
            error('allocation '..kind)
        end
        local h={kind=kind};e.live[h]=true;return h
    end
    local function free(h)
        assert(e.live[h],'double release');e.live[h]=nil;e.destroys=e.destroys+1
    end
    e.ui={create_world=function() return allocate('world') end,
        destroy_world=function(_,h) free(h) end,
        create_viewport=function(_,world,name,kind,order,a,b,settings)
            assert(e.live[world] and e.live[settings.back_buffer])
            e.viewport=allocate('viewport');return e.viewport
        end}
    e.Renderer={create_resource=function() return allocate('target') end,
        destroy_resource=free,
        copy_render_target_rect=function(source,x,y,w,h,dest)
            assert(source~=dest and e.live[source] and e.live[dest])
            e.copies=e.copies+1
            if e.fail_copy then error('copy failure') end
        end}
    e.World={create_screen_gui=function() return allocate('gui') end,destroy_gui=function(_,h) free(h) end}
    e.UIRenderer={create_ui_renderer=function(world,gui,retained)
            local r=allocate('renderer')
            if r then r.gui=gui;r.gui_retained=retained end
            return r
        end,
        destroy=function(r) free(r.gui);free(r.gui_retained);free(r) end}
    e.ScriptWorld={destroy_viewport=function()
        free(e.viewport)
        if e.fail_cleanup then error('viewport cleanup failure') end
    end}
    e.Gui={render_pass=function(_,_,name,clear)
        assert(name=='to_screen' and clear);e.clears=e.clears+1
    end}
    return e
end

-- Each successfully returned handle is released for every partial constructor.
for failure=1,7 do
    for _,nil_failure in ipairs({false,true}) do
        local e=engine(failure,nil_failure)
        assert(not pcall(Capture.new,e,512,256))
        assert(next(e.live)==nil,'leaked partial allocation '..failure)
    end
end
for _,size in ipairs({0,-1,0/0,math.huge,1.5,4097}) do
    local e=engine()
    assert(not pcall(Capture.new,e,size,128) and e.calls==0)
end
assert(not pcall(Capture.new,engine(),4096,4096))

local e=engine()
local c=Capture.new(e,512,256)
local s=Surface.new(c)
local key,meta={},{}
local draws=0
local function draw(renderer,metadata)
    assert(renderer==c.renderer and metadata==meta)
    draws=draws+1
end
assert(not pcall(c.copy,c))
assert(s:capture(1,key,meta,draw))
assert(c:observe_render({})==nil)
assert(not pcall(c.copy,c))
assert(s:capture(1,key,meta,draw) and draws==1)
s:submitted(assert(c:observe_render(c.world)))
assert(c:observe_render(c.world)==nil)
assert(select(2,s:capture(2,key,meta,draw))=='ready')
assert(e.copies==1 and e.clears==2 and draws==2)
-- A newly authored image cannot inherit submission from the preceding image.
assert(not pcall(c.copy,c))
assert(select(2,s:capture(3,key,meta,draw))=='warming')
assert(e.copies==1 and not s:visible(3,key))
local world=c.world
s:destroy();s:destroy()
assert(next(e.live)==nil and c:observe_render(world)==nil)
assert(not pcall(c.queue,c,draw,meta,4))

e=engine();c=Capture.new(e,64,64)
local attempts=0
assert(not pcall(c.queue,c,function() attempts=attempts+1;error('draw failure') end,{},1))
assert(attempts==1 and c:observe_render(c.world)==nil and not pcall(c.copy,c))
c:destroy();assert(next(e.live)==nil)

e=engine();c=Capture.new(e,64,64)
c:queue(function() end,{},1);assert(c:observe_render(c.world)==1)
e.fail_copy=true
assert(not pcall(c.copy,c) and c:observe_render(c.world)==nil)
c:destroy();assert(next(e.live)==nil)

e=engine();c=Capture.new(e,64,64);e.fail_cleanup=true
assert(not pcall(c.destroy,c))
assert(next(e.live)==nil,'cleanup stopped after first error')
local destroyed=e.destroys;c:destroy();assert(e.destroys==destroyed)
print('widget_capture: partial allocation cleanup, paired submission, distinct copy, failure retirement pass')
