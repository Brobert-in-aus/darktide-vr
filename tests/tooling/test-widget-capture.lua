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
            if r then r.gui=gui;r.gui_retained=retained;r.ui_scenegraph_queue={} end
            return r
        end,
        destroy=function(r) free(r.gui);free(r.gui_retained);free(r) end,
        begin_pass=function(r,graph,input,dt,settings)
            r.ui_scenegraph=graph;r.render_settings=settings;r.scale=settings.scale
            r.inverse_scale=settings.inverse_scale;r.dt=dt;r.input_service=input
            r.current_clipping_rect=nil
            for k in pairs(r.ui_scenegraph_queue) do r.ui_scenegraph_queue[k]=nil end
            if e.fail_begin then error('begin failure') end
        end,
        end_pass=function(r)
            e.ends=(e.ends or 0)+1
            r.ui_scenegraph=nil;r.render_settings=nil;r.scale=nil;r.inverse_scale=nil
            if e.fail_end then error('end failure') end
        end}
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

for _,failure in ipairs({'none','begin','draw','end','draw_end','nested'}) do
    e=engine();c=Capture.new(e,64,64)
    local renderer=c.renderer
    local old_graph,old_settings,old_input,old_clip={},{},{},{}
    renderer.ui_scenegraph=old_graph;renderer.render_settings=old_settings
    renderer.input_service=old_input;renderer.current_clipping_rect=old_clip
    renderer.scale=2;renderer.inverse_scale=0.5;renderer.dt=0.1
    renderer.ui_scenegraph_queue[1]=old_graph
    local queue=renderer.ui_scenegraph_queue
    local settings={scale=1,inverse_scale=1,alpha_multiplier=0.8}
    local graph={}
    e.fail_begin=failure=='begin'
    e.fail_end=failure=='end' or failure=='draw_end'
    local called=0
    local ok,err=pcall(c.pass,c,graph,{},0.2,settings,function(r,owned)
        called=called+1
        assert(r==renderer and r.ui_scenegraph==graph and owned~=settings)
        owned.alpha_multiplier=0
        r.ui_scenegraph_queue[1]={}
        r.current_clipping_rect={}
        if failure=='draw' or failure=='draw_end' then error('draw failure') end
        if failure=='nested' then c:pass(graph,{},0.2,settings,function() end) end
    end)
    assert(ok==(failure=='none'))
    assert(called==(failure=='begin' and 0 or 1) and e.ends==1)
    assert(settings.alpha_multiplier==0.8 and not c.in_pass)
    assert(renderer.ui_scenegraph==old_graph and renderer.render_settings==old_settings)
    assert(renderer.input_service==old_input and renderer.current_clipping_rect==old_clip)
    assert(renderer.scale==2 and renderer.inverse_scale==0.5 and renderer.dt==0.1)
    assert(renderer.ui_scenegraph_queue==queue and queue[1]==old_graph and #queue==1)
    if failure=='draw_end' then
        assert(tostring(err):find('draw failure',1,true) and tostring(err):find('end failure',1,true))
    end
    c:destroy();assert(next(e.live)==nil)
end
print('widget_capture: isolated pass restores renderer state through begin/draw/end failures')
