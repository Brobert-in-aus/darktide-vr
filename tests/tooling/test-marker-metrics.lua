local metrics = dofile(arg[1])
local messages,commands,calls = {},{},0
local measure_calls=0
local renderer_class = {text_size=function(self,text,font,font_size,size,options,use_max)
    measure_calls=measure_calls+1
    assert(text=='private text' and font=='font' and use_max==true)
    if options and options.fail then error('measurement failed') end
    if options and options.invalid then return -1,20,{0,0,0} end
    return size[1],font_size,{options and options.overhang or 0,-2,0}
end}
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
assert(a==41 and b==nil and c==43 and #messages==0 and measure_calls==0,'default-off path altered drawing')
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
-- Stop/restart during a draw must not publish the old scope into the new run.
-- A real draw error still propagates, without consuming the new run's pair.
for _,fail in ipairs({false,true}) do
    metrics.start(4)
    local before_messages=#messages
    local success,problem=pcall(metrics.draw,renderer,'markers',owner,14.5,1,nil,function()
        metrics.stop();metrics.start(4)
        renderer:script_draw_bitmap('old',{0,0,0},{10,20,0})
        if fail then error('retired draw failure')end
    end)
    assert(success~=fail and (not fail or problem:find('retired draw failure',1,true)))
    metrics.draw(renderer,'markers',owner,14.5,2,nil,function()
        renderer:script_draw_bitmap('old',{0,0,0},{10,20,0})
    end)
    assert(#messages==before_messages+1 and messages[#messages]:find('unmatched=true',1,true),
        'retired scope was published into the restarted measurement')
end
-- Reordered/different resources must not be silently paired by ordinal.
for _,fail in ipairs({false,true})do
    metrics.start(4)
    local before_messages=#messages
    local success=pcall(metrics.draw,renderer,'markers',owner,14.75,1,nil,function()
        metrics.start(4)
        metrics.draw(renderer,'markers',owner,14.75,1,nil,function()
            renderer:script_draw_bitmap('new',{0,0,0},{10,20,0})
        end)
        local before_measure=measure_calls
        renderer:script_draw_text('private text',24,'font',{0,0,0},{100,20,0})
        assert(measure_calls==before_measure,'retired outer draw still measured text')
        if fail then error('old failure')end
    end)
    assert(success~=fail)
    metrics.draw(renderer,'markers',owner,14.75,2,nil,function()
        renderer:script_draw_bitmap('new',{0,0,0},{10,20,0})
    end)
    assert(#messages==before_messages+1 and messages[#messages]:find('left=1 right=1 matched=1',1,true),
        'retired outer draw overwrote or cleared the new primary scope')
end
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
metrics.start(2)
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,21,eye,nil,function()
        local options={overhang=eye==1 and -3 or -8}
        renderer:script_draw_text('private text',24,'font',{0,0,0},{100,20,0},nil,options)
        assert(options.overhang==(eye==1 and -3 or -8), 'observer changed text options')
    end)
end
assert(messages[#messages-1]:find('shape=0 font=0',1,true))
assert(messages[#messages-1]:find('text_layout=1 text_measured=1',1,true), 'glyph origin change was missed')
metrics.start(2)
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,21.5,eye,nil,function()
        renderer:script_draw_text_3d('private text',24,'font',{
            x={x=1,y=0,z=0},z={x=0,y=0,z=1},translation={x=0,y=0,z=0}},
            {0,0,0},1,{100,20,0},nil,{overhang=-eye})
    end)
end
assert(messages[#messages-1]:find('text_layout=1 text_measured=1',1,true), '3D text options were not measured')
for _,option in ipairs({'fail','invalid'}) do
    metrics.start(2)
    local before=calls
    for eye=1,2 do
        metrics.draw(renderer,'markers',owner,22,eye,nil,function()
            renderer:script_draw_text('private text',24,'font',{0,0,0},{100,20,0},nil,{[option]=true})
        end)
    end
    assert(calls==before+2, 'text measurement failure swallowed actual drawing')
    assert(messages[#messages-1]:find('incomplete=true',1,true))
end
assert(not table.concat(messages):find('private text',1,true))
-- Layer is an ordering input, not a scaled XY coordinate or a 3D translation.
metrics.start(2)
for eye=1,2 do
    renderer.scale=eye
    renderer.render_settings.start_layer=eye==1 and 10 or 20
    metrics.draw(renderer,'markers',owner,23,eye,nil,function()
        renderer:script_draw_bitmap('material',{0,0,eye},{10,20,0})
        renderer:script_draw_bitmap_3d('material',{
            x={x=1,y=0,z=0},z={x=0,y=0,z=1},translation={x=0,y=0,z=0}},
            {0,0,99},eye*3,{10,20,0})
        renderer:script_draw_text_3d('private text',24,'font',{
            x={x=1,y=0,z=0},z={x=0,y=0,z=1},translation={x=0,y=0,z=0}},
            {0,0,99},eye*4,{100,20,0})
        renderer:draw_rect({0,0,7},{10/eye,20/eye,0})
    end)
end
assert(messages[#messages-1]:find('layer=3 start_layer=4 max_layer_delta=4.000',1,true),
    '2D/3D layer inputs or renderer start layer were missed')
assert(messages[#messages-1]:find('max_anchor_delta=0.000',1,true),
    'draw ordering must not be reported as a spatial displacement')
renderer.scale=1;renderer.render_settings.start_layer=nil
metrics.start(2)
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,23.5,eye,nil,function()
        local tm={x={x=1,y=0,z=0},z={x=0,y=0,z=1},translation={x=0,y=0,z=0}}
        renderer:script_draw_bitmap_3d('material',tm,{0,0,eye*7},5,{10,20,0})
        renderer:script_draw_text_3d('private text',24,'font',tm,{0,0,eye*3},6,{100,20,0})
    end)
end
assert(messages[#messages-1]:find('offset_depth=2 max_offset_depth_delta=7.000',1,true),
    '3D position-offset third component was omitted')
assert(messages[#messages-1]:find('layer=0 start_layer=0 max_layer_delta=0.000',1,true),
    '3D offset must remain distinct from ordering')
metrics.start(2)
local before_offset_calls=calls
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,23.75,eye,nil,function()
        renderer:script_draw_bitmap_3d('material',{
            x={x=1,y=0,z=0},z={x=0,y=0,z=1},translation={x=0,y=0,z=0}},
            {0,0,0/0},5,{10,20,0})
    end)
end
assert(calls==before_offset_calls+2 and messages[#messages-1]:find('incomplete=true',1,true),
    'invalid offset must mark evidence incomplete without suppressing stock drawing')
metrics.start(2)
local before_layer_calls=calls
for eye=1,2 do
    metrics.draw(renderer,'markers',owner,24,eye,nil,function()
        renderer:script_draw_bitmap('material',{0,0,0/0},{10,20,0})
    end)
end
assert(calls==before_layer_calls+2 and messages[#messages-1]:find('incomplete=true',1,true),
    'invalid layer must mark evidence incomplete without suppressing the draw')
print('marker_metrics=pass bounded_input_geometry_only=true text_layout_not_raster=true')

-- Optional source contract: verify final pixel font/box/options reach the stock
-- max-extents API unchanged and that its origin is returned, not discarded.
if arg[2] then
    local path=arg[2]..'/scripts/managers/ui/ui_renderer.lua'
    local file=assert(io.open(path,'r'));local source=file:read('*a');file:close()
    local first=assert(source:find('UIRenderer.text_size =',1,true))
    local last=assert(source:find('\nUIRenderer.styled_text_size =',first,true))
    local stock,observed={},0
    local options={shadow=true,line_spacing=1.25,vertical_alignment='center'}
    local function extents(gui,text,font,font_size,settings)
        observed=observed+1
        assert(gui=='owned_gui' and text=='private text' and font=='font_path' and font_size==36)
        assert(settings.flags==7 and settings.shadow and settings.line_spacing==1.25)
        assert(settings.optional_size[1]==300 and settings.optional_size[2]==60)
        return {-4,-9,0},{104,31,0},{10,0,0}
    end
    local env=setmetatable({UIRenderer=stock,optional_gui_args={},
        UIFonts={data_by_type=function(font)assert(font=='font');return {path='font_path',render_flags=7} end},
        Gui={VerticalAlignCenter='center'},Vector2=function(x,y)return {x,y} end,
        Vector3={to_elements=function(value)return unpack(value) end},
        Gui2_slug_text_max_extents=extents,Gui2_slug_text_extents=function()error('must use max extents')end,
        table={clear=function(value)for key in pairs(value)do value[key]=nil end end}}, {__index=_G})
    setfenv(assert(loadstring(source:sub(first,last-1),'@'..path)),env)()
    local width,height,minimum=stock.text_size({gui='owned_gui',scale=1.5},'private text','font',36,{300,60},options,true)
    assert(width==108 and height==40 and minimum[1]==-4 and minimum[2]==-9 and observed==1)
    assert(options.flags==nil and options.optional_size==nil, 'stock layout must not mutate supplied options')
    print('marker_text_layout_stock=pass final pixel scale, options and glyph origin forwarded')

    -- Execute real stock 2D/3D bitmap methods behind the observer. In 2D stock
    -- mutates position[3]; in 3D it adjusts a separate scalar, not position.z.
    local layer_class,native_layers,native_offsets={},{},{}
    local layer_env=setmetatable({UIRenderer=layer_class,optional_gui_args={},
        STRING_IDENTIFIER='string',SNAP_PIXEL_POSITIONS=false,
        _get_material_flag=function() return 0 end,
        Gui2_bitmap=function(gui,material,flags,position)
            native_layers[#native_layers+1]=position[3]
            return 71
        end,
        Gui2_bitmap_3d=function(gui,material,flags,tm,layer,options)
            native_offsets[#native_offsets+1]=options.position_offset[3]
            native_layers[#native_layers+1]=layer
            return 73
        end,
        table={clear=function(value)for key in pairs(value)do value[key]=nil end end}}, {__index=_G})
    for _,name in ipairs({'script_draw_bitmap','script_draw_bitmap_3d'}) do
        local begin=assert(source:find('UIRenderer.'..name..' =',1,true))
        local finish=assert(source:find('\nUIRenderer.',begin+1,true))
        setfenv(assert(loadstring(source:sub(begin,finish-1),'@'..path)),layer_env)()
    end
    local layer_metrics=dofile(arg[1])
    layer_metrics.install(mod,layer_class)
    local stock_instance=setmetatable({scale=2,gui='owned_gui',render_settings={}}, {__index=layer_class})
    layer_metrics.start(2)
    for eye=1,2 do
        stock_instance.render_settings.start_layer=eye*10
        layer_metrics.draw(stock_instance,'markers',owner,25,eye,nil,function()
            local position={0,0,eye}
            assert(stock_instance:script_draw_bitmap('material',position,{10,20,0})==71)
            assert(position[3]==eye*11,'stock mutation contract changed')
            assert(stock_instance:script_draw_bitmap_3d('material',{
                x={x=1,y=0,z=0},z={x=0,y=0,z=1},translation={x=0,y=0,z=0}},
                {0,0,99+eye},eye*3,{10,20,0})==73)
        end)
    end
    assert(table.concat(native_layers,',')=='11,13,22,26')
    assert(table.concat(native_offsets,',')=='100,101')
    assert(messages[#messages-1]:find('layer=2 start_layer=2 max_layer_delta=3.000',1,true))
    assert(messages[#messages-1]:find('max_anchor_delta=0.000 incomplete=false',1,true))
    assert(messages[#messages-1]:find('offset_depth=1 max_offset_depth_delta=1.000',1,true))
    print('marker_layer_stock=pass 2D mutation and separate 3D layer preserved')
end
