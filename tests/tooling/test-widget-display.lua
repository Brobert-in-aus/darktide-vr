local root=arg[1]
local Display=dofile(root..'/darktidevr_widget_display.lua')
local Plane=dofile(root..'/darktidevr_marker_plane.lua')
local Quad=dofile(root..'/darktidevr_widget_quad.lua')
local function v(x,y,z)return {x=x,y=y,z=z}end
local function fixture(failure)
    local world,gui,material,target,capture={},{},{},{},{}
    local calls={draws={},cleanup={},scalars={}}
    local api={Vector3=v,Vector2=function(x,y)return {x=x,y=y}end,Color=function(...)return {...}end,
        Matrix4x4={identity=function()return {}end},World={},Gui={},Gui2={},Material={}}
    for _,name in ipairs({'right','forward','up','translation'})do
        api.Matrix4x4['set_'..name]=function(tm,value)tm[name]=value end
    end
    function api.World.create_world_gui(w,tm,width,height,mode)
        assert(w==world and width==1 and height==1 and mode=='immediate')
        if failure=='gui' then error('gui failure')end
        return gui
    end
    function api.Gui.create_material(g,name)
        assert(g==gui and name=='content/ui/materials/icons/items/containers/item_container_square')
        if failure=='material' then error('material failure')end
        return material
    end
    function api.Material.set_scalar(m,name,value)assert(m==material);calls.scalars[name]=value end
    function api.Material.set_resource(m,name,value)
        assert(m==material and name=='render_target' and value==target and value~=capture)
        if failure=='binding' then error('binding failure')end
        calls.bound=value
    end
    function api.Gui2.bitmap_3d(g,m,flags,tm,layer,args)
        assert(g==gui and m==material and flags==nil and layer==37)
        if failure=='draw' then error('draw failure')end
        calls.draws[#calls.draws+1]={tm=tm,args=args}
    end
    function api.Gui.destroy_material(g,m)
        assert(g==gui and m==material);calls.cleanup[#calls.cleanup+1]='material'
        if failure=='cleanup' then error('material cleanup failure')end
    end
    function api.World.destroy_gui(w,g)
        assert(w==world and g==gui);calls.cleanup[#calls.cleanup+1]='gui'
        if failure=='cleanup' then error('gui cleanup failure')end
    end
    local backend={display_target=target,capture_target=capture,width=512,height=256}
    local image={revision=1,metadata={bounds={x=1700,y=400,width=400,height=150},
        pivot={x=1800,y=500},scale=1,pixel_width=400,pixel_height=150,capture_width=512,capture_height=256}}
    local session={backend=backend,image=image}
    function session:visible()return self.image end
    return api,world,session,calls,image
end
local api,world,session,calls,image=fixture()
local display=Display.new(api,world,session,Quad,Plane,37)
assert(calls.bound==session.backend.display_target and calls.scalars.use_render_target==1 and calls.scalars.rows==1)
local identity={}
local anchor,center,right,up=v(0,2,0),v(0,0,0),v(1,0,0),v(0,0,1)
local function draw(t)return display:draw(t,identity,anchor,center,right,up,0.001)end
assert(draw(1));local first=calls.draws[1]
local expected_plane=assert(Plane.create(anchor,center,right,up,0.001,{x=1800,y=500}))
for _,corner in ipairs({{0,0},{1,0},{0,1},{1,1}})do
    local x,y=corner[1],corner[2]
    local expected=Plane.point(expected_plane,2100-x*400,400+y*150)
    for _,axis in ipairs({'x','y','z'})do
        local actual=first.tm.translation[axis]+first.tm.right[axis]*first.args.size.x*x+
            first.tm.up[axis]*first.args.size.y*y
        assert(math.abs(actual-expected[axis])<1e-9,'submitted transform must retain shared-plane corner geometry')
    end
end
anchor.x=1;image.metadata.pivot.x=0
assert(draw(1));local second=calls.draws[2]
assert(first.tm.translation.x==second.tm.translation.x and first.args.size.x==second.args.size.x,
    'second eye must retain the first pose and image geometry')
assert(first.tm~=second.tm and first.args~=second.args,'engine arguments must be private per draw')
assert(first.args.uv00.x==400/512 and first.args.uv00.y==1 and first.args.uv11.x==0)
assert(first.args.snap_pixel_positions==false and first.args.position_offset.x==0)
assert(draw(2) and calls.draws[3].tm.translation.x~=first.tm.translation.x)
image.revision=2;assert(not draw(2) and #calls.draws==3,'revision change within eye pair')
session.image=nil;assert(not draw(3));session.image=image
assert(not draw(3) and #calls.draws==3,'first-eye hidden decision must persist')
assert(draw(4))
session.image=nil;assert(not draw(4),'invalidation hides a previously cached quad')
session.image=image;image.metadata.capture_width=256;assert(not draw(5))
image.metadata.capture_width=512;assert(not draw(5),'first-eye rejection must persist')
assert(draw(6))
session.backend.display_target={};assert(not draw(7),'never sample a replaced target')
display:destroy();display:destroy();assert(table.concat(calls.cleanup,',')=='material,gui')
assert(not draw(8))

for _,failure in ipairs({'gui','material','binding','draw','cleanup'})do
    api,world,session,calls=fixture(failure)
    local ok,result=pcall(Display.new,api,world,session,Quad,Plane,37)
    if failure=='gui' then assert(not ok and #calls.cleanup==0)
    elseif failure=='material' then assert(not ok and table.concat(calls.cleanup,',')=='gui')
    elseif failure=='binding' then assert(not ok and table.concat(calls.cleanup,',')=='material,gui')
    else
        assert(ok);display=result
        if failure=='draw' then
            local drawn,err=pcall(draw,1)
            assert(not drawn and tostring(err):find('draw failure',1,true) and not draw(1))
            display:destroy()
        else
            local cleaned,err=pcall(display.destroy,display)
            assert(not cleaned and tostring(err):find('material cleanup failure',1,true) and tostring(err):find('gui cleanup failure',1,true))
            display:destroy()
        end
        assert(table.concat(calls.cleanup,',')=='material,gui')
    end
end
print('widget_display=pass completed target private eye arguments frame latching invalidation and owned cleanup')
