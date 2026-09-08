local State=dofile(arg[1])
local source_renderer,capture_renderer={},{}
local materials,created,released={},0,0
local types={}
local fail_cleanup=false
for _,kind in ipairs({'texture','texture_uv','rotated_texture','text','rect'}) do
    types[kind]={init=function(pass) return {dirty=true,value_id=pass.value_id} end,
        destroy=function(pass,renderer)
            if pass.data.material then
                local material=pass.data.material
                assert(materials[material]==renderer,'wrong GUI owns material')
                materials[material]=nil;released=released+1
                pass.data.material=nil
                if fail_cleanup then error('material cleanup failed') end
            end
        end}
end
local function material(renderer)
    local h={};materials[h]=renderer;created=created+1;return h
end
local source_material=material(source_renderer)
local original={material=source_material,material_value='texture',dirty=false}
local pass={pass_type='texture',value_id='image',data=original}
local widget={passes={pass},style={},content={image='texture'}}
local state=State.new(capture_renderer,types)
local draw_count=0
local function draw()
    draw_count=draw_count+1
    assert(pass.data~=original and pass.data.material~=source_material)
    if not pass.data.material then
        pass.data.material=material(capture_renderer);pass.data.material_value='texture'
    end
    assert(materials[pass.data.material]==capture_renderer)
    return 1,nil,3
end
local handled,a,b,c=state:draw({widget},{},draw)
assert(handled and a==1 and b==nil and c==3 and draw_count==1)
assert(pass.data==original and original.material==source_material and not original.dirty)
local first_created=created
assert(state:draw({widget},{},draw) and created==first_created,'capture cache was recreated')
assert(materials[source_material]==source_renderer and released==0)
-- Reject an entire mixed widget set before binding any capture data or drawing.
local unsupported={passes={{pass_type='logic',data={}}},style={},content={}}
assert(not state:draw({widget,unsupported},{},draw) and draw_count==2)
assert(pass.data==original)
pass.retained_mode=true
assert(not state:draw({widget},{},draw));pass.retained_mode=nil
original.retained_id=14
assert(not state:draw({widget},{},draw));original.retained_id=nil
original.retained_ids={}
assert(not state:draw({widget},{},draw));original.retained_ids=nil
assert(not state:draw({widget},{force_retained_mode=true},draw))
capture_renderer.render_settings={force_retained_mode=true}
assert(not state:draw({widget},{},draw));capture_renderer.render_settings=nil
widget.style.material={foreign=true}
assert(not state:draw({widget},{},draw));widget.style.material=nil
widget.content.image={foreign=true}
assert(not state:draw({widget},{},draw));widget.content.image='texture'
assert(not state:draw({widget,widget},{},draw))
-- A draw failure restores source bindings and retires further capture draws.
local ok,err=pcall(state.draw,state,{widget},{},function() draw();error('draw failed') end)
assert(not ok and tostring(err):find('draw failed',1,true))
assert(pass.data==original and original.material==source_material)
assert(not state:draw({widget},{},draw))
state:destroy();state:destroy()
assert(released==1 and materials[source_material]==source_renderer)

-- Removing a widget releases its cache through the capture renderer only.
state=State.new(capture_renderer,types)
assert(state:draw({widget},{},draw))
local second={pass_type='text',value_id='text',data={value_id='text'}}
local second_widget={passes={second},style={},content={text='text'}}
assert(state:draw({second_widget},{},function()
    assert(second.data.value_id=='text')
    second.data.material=material(capture_renderer)
end))
assert(released==2 and pass.data==original)
state:destroy();assert(released==3 and materials[source_material]==source_renderer)

-- Every cache still receives cleanup when one destructor fails.
state=State.new(capture_renderer,types)
assert(state:draw({widget,second_widget},{},function()
    draw();second.data.material=material(capture_renderer)
end))
fail_cleanup=true
assert(not pcall(state.destroy,state))
assert(released==5 and pass.data==original and second.data.material==nil)
assert(materials[source_material]==source_renderer)
local count=released;state:destroy();assert(released==count)
local live=0;for _ in pairs(materials) do live=live+1 end;assert(live==1)
print('widget_capture_state: GUI ownership, cached reuse, preflight rejection and failure restoration pass')

if arg[2] then
    local actual_live={}
    local stock_renderer={
        create_material=function(r,value)
            local h={value=value};actual_live[h]=r;return h
        end,
        destroy_material=function(r,h)
            assert(actual_live[h]==r,'stock destroyed foreign GUI material')
            actual_live[h]=nil
        end}
    local function submit(r,h)
        assert(actual_live[h]==r,'stock submitted foreign GUI material')
    end
    stock_renderer.script_draw_bitmap=submit
    stock_renderer.script_draw_bitmap_uv=submit
    stock_renderer.draw_texture_rotated=submit
    local env=setmetatable({GameParameters={testify=false},
        Script={new_map=function() return {} end},
        Gui={scale_vector3=function(v) return v end},
        Material={set_scalar=function(h) assert(actual_live[h]) end},
        require=function(name)
            if name=='scripts/managers/ui/ui_renderer' then return stock_renderer end
            return {}
        end},{__index=_G})
    local chunk=assert(loadfile(arg[2]));setfenv(chunk,env)
    local stock=chunk()
    for _,kind in ipairs({'texture','texture_uv','rotated_texture'}) do
        local source={scale=1,render_settings={}}
        local target={scale=1,render_settings={}}
        local p={pass_type=kind,value_id='image'}
        p.data=stock[kind].init(p)
        local w={passes={p},content={image='first'},style={scale_to_material=true,
            color={255,255,255,255},uvs={{0,0},{1,1}},angle=0.5,pivot={5,5}}}
        local function stock_draw(r)
            stock[kind].draw(p,r,w.style,w.content,{0,0,0},{10,10,0})
        end
        stock_draw(source)
        local old_data,old_material=p.data,p.data.material
        local capture=State.new(target,stock)
        assert(capture:draw({w},{},stock_draw,target))
        assert(p.data==old_data and p.data.material==old_material)
        w.content.image='second'
        assert(capture:draw({w},{},stock_draw,target))
        assert(actual_live[old_material]==source)
        capture:destroy()
        assert(actual_live[old_material]==source and p.data==old_data)
        stock[kind].destroy(p,source)
        assert(next(actual_live)==nil)
    end
    print('widget_capture_state: actual stock texture/UV/rotated material creation, replacement and cleanup pass')
end
