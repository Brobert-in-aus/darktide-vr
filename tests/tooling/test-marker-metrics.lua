local metrics = dofile(arg[1])
local messages,commands,calls = {},{},0
local renderer_class = {}
for _,name in ipairs({'script_draw_bitmap','script_draw_bitmap_uv','script_draw_bitmap_3d',
        'script_draw_text','script_draw_text_3d','draw_rect','draw_rect_rotated',
        'draw_slug_icon','draw_slug_icon_rotated','draw_slug_picture','draw_triangle'}) do
    renderer_class[name]=function(self,...)
        calls=calls+1
        return 'drawn',nil,17
    end
end
local mod = {
    hook=function(_,class,name,hook)
        local original=class[name]
        class[name]=function(...) return hook(original,...) end
    end,
    command=function(_,name,_,callback) commands[name]=callback end,
    info=function(_,format,...) messages[#messages+1]=string.format(format,...) end,
}
metrics.install(mod,renderer_class)
local renderer=setmetatable({scale=1,render_settings={alpha_multiplier=1}}, {__index=renderer_class})
local other=setmetatable({scale=7}, {__index=renderer_class})
local owner={}
local function draw(width,font,x)
    local a,b,c=renderer:script_draw_bitmap('material',{x,30,0},{width,20,0},{255,1,1,1})
    assert(a=='drawn' and b==nil and c==17)
    renderer:script_draw_text('private text',font,'font',{x,30,0},{width,20,0})
    other:draw_rect({1,2,0},{999,888,0})
    return 41,nil,43
end
local function pair(t,width,font,scale)
    renderer.scale=1
    metrics.draw(renderer,'interaction',owner,t,1,nil,draw,100,24,10)
    renderer.scale=scale or 1
    metrics.draw(renderer,'interaction',owner,t,2,nil,draw,width or 100,font or 24,40)
end
local a,b,c=metrics.draw(renderer,'interaction',owner,0,1,nil,draw,100,24,10)
assert(a==41 and b==nil and c==43 and #messages==0,'default-off path altered drawing')
commands.dtvr_marker_metrics()
pair(1)
assert(messages[#messages]:find('left=2 right=2 matched=2 shape=0 font=0 scale=0',1,true))
assert(messages[#messages]:find('max_anchor_delta=30.000 incomplete=false',1,true))
assert(not table.concat(messages):find('private text',1,true))
pair(2,80,20,1.5)
assert(messages[#messages]:find('shape=2 font=1 scale=2',1,true),'real geometry differences not detected')
-- Renderer-scale multiplication belongs only to the logical-coordinate APIs.
metrics.start(4)
renderer.scale=2
metrics.draw(renderer,'markers',owner,3,1,nil,function()
    renderer:draw_rect({1,2,0},{10,20,0})
    renderer:draw_slug_icon('resource',1,{1,2,0},{10,20,0})
    renderer:script_draw_bitmap_uv('material',{1,2,0},{10,20,0},{})
end)
renderer.scale=1
metrics.draw(renderer,'markers',owner,3,2,nil,function()
    renderer:draw_rect({1,2,0},{20,40,0})
    renderer:draw_slug_icon('resource',1,{1,2,0},{20,40,0})
    renderer:script_draw_bitmap_uv('material',{1,2,0},{10,20,0},{})
end)
assert(messages[#messages]:find('matched=3 shape=0 font=0 scale=3',1,true))
-- The immediate-GUI wrapper still runs once and preserves sparse returns.
local wrappers=0
local function wrapper(actual,func,...)
    assert(actual==renderer); wrappers=wrappers+1
    return func(...)
end
a,b,c=metrics.draw(renderer,'markers',owner,4,1,wrapper,draw,100,24,10)
metrics.draw(renderer,'markers',owner,4,2,nil,draw,100,24,40)
assert(wrappers==1 and a==41 and b==nil and c==43)
assert(messages[#messages]:find('complete=true',1,true))
local completed=#messages
pair(5)
assert(#messages==completed,'budget did not expire')
-- No stale-frame/owner matching, and unsupported primitives fail visibly.
metrics.start(10)
metrics.draw(renderer,'markers',owner,6,1,nil,draw,100,24,10)
metrics.draw(renderer,'markers',owner,7,2,nil,draw,100,24,40)
assert(messages[#messages]:find('unmatched=true',1,true))
metrics.draw(renderer,'markers',{},8,1,nil,draw,100,24,10)
metrics.draw(renderer,'markers',owner,8,2,nil,draw,100,24,40)
assert(messages[#messages]:find('unmatched=true',1,true))
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,9,eye,nil,function()
        renderer:draw_triangle({}, {}, {})
    end)
end
assert(messages[#messages]:find('incomplete=true',1,true))
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,10,eye,nil,function()
        for i=1,129 do renderer:draw_rect({1,2,0},{10,20,0}) end
    end)
end
assert(messages[#messages]:find('left=129 right=129 matched=128',1,true))
assert(messages[#messages]:find('incomplete=true',1,true))
-- Observer extraction errors cannot swallow or prevent the actual draw.
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,11,eye,nil,function()
        renderer:script_draw_bitmap('material',{0,0,0},{0/0,20,0})
    end)
end
assert(messages[#messages-1]:find('incomplete=true',1,true))
metrics.start(4)
local ok,err=pcall(metrics.draw,renderer,'markers',owner,12,1,nil,function() error('draw failure') end)
assert(not ok and err:find('draw failure',1,true))
renderer:draw_rect({1,2,0},{10,20,0}) -- Failed scope must not stay active.
pair(13)
assert(messages[#messages]:find('left=2 right=2 matched=2',1,true))
commands.dtvr_marker_metrics_off()
completed=#messages
pair(14)
assert(#messages==completed)
assert(calls>260)
-- Reordered/different resources must not be silently paired by ordinal.
metrics.start(4)
metrics.draw(renderer,'markers',owner,15,1,nil,function()
    renderer:script_draw_bitmap('first',{0,0,0},{10,20,0})
end)
metrics.draw(renderer,'markers',owner,15,2,nil,function()
    renderer:script_draw_bitmap('second',{0,0,0},{10,20,0})
end)
assert(messages[#messages]:find('kind_mismatch=1',1,true))
assert(messages[#messages]:find('incomplete=true',1,true))
Matrix4x4={x=function(tm)return tm.x end,z=function(tm)return tm.z end,
    translation=function(tm)return tm.translation end}
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,16,eye,nil,function()
        renderer:script_draw_bitmap_3d('material',{
            x={x=eye,y=0,z=0},z={x=0,y=0,z=1},translation={x=eye*10,y=0,z=0}},nil,1,{10,20,0})
    end)
end
assert(messages[#messages-1]:find('shape=1',1,true))
assert(messages[#messages-1]:find('max_anchor_delta=10.000 incomplete=false',1,true))
metrics.start(2)
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,17,eye,nil,function()
        renderer:draw_rect({0,0,0},{10,20,0},{eye*100,1,1,1})
    end)
end
assert(messages[#messages-1]:find('color_alpha=1',1,true),'style alpha difference was missed')
local original_info=mod.info
mod.info=function() error('observer logger failure') end
metrics.start(2)
pair(18) -- Logging failure must not change successful drawing.
mod.info=original_info
metrics.start(4)
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,19,eye,nil,function()
        renderer:script_draw_bitmap_3d('material',{
            x={x=1,y=eye-1,z=0},z={x=0,y=0,z=1},
            translation={x=0,y=(eye-1)*12,z=0}},nil,1,{10,20,0})
    end)
end
assert(messages[#messages]:find('shape=1',1,true),'depth basis change was missed')
assert(messages[#messages]:find('max_anchor_delta=12.000',1,true),'depth translation was missed')
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,20,eye,nil,function()
        renderer:draw_rect_rotated({20,30,0},{0,0,0},0.5,{eye*3,2,0})
        renderer:draw_slug_icon_rotated('resource',1,{20,30,0},{0,0,0},0.5,{1,eye*2,0})
    end)
end
assert(messages[#messages-1]:find('shape=2',1,true),'rotation pivot change was missed')
print('marker_metrics=pass bounded_input_geometry_only=true')
