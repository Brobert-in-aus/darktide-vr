local root=arg[1]
local Plane=dofile(root..'/darktidevr_marker_plane.lua')
local Quad=dofile(root..'/darktidevr_widget_quad.lua')
local function v(x,y,z)return {x=x,y=y,z=z}end
local function close(a,b)assert(math.abs(a-b)<1e-9,tostring(a)..' ~= '..tostring(b))end
local function same(a,b)close(a.x,b.x);close(a.y,b.y);close(a.z,b.z)end
local center,right,up=v(0,0,0),v(1,0,0),v(0,0,1)
local function image(scale)
    return {metadata={bounds={x=1700,y=400,width=400/scale,height=150/scale},
        pivot={x=1800,y=500},scale=scale,pixel_width=400,pixel_height=150,
        capture_width=512,capture_height=256}}
end
local cases=0
for _,scale in ipairs({0.5,1,1.5,2})do
    for _,anchor in ipairs({v(0,2,0),v(-1,2,0.5),v(1,0.5,-0.2),v(0,0,2)})do
        local source=image(scale)
        local q=assert(Quad.create(Plane,source,anchor,center,right,up,0.001))
        local plane=assert(Plane.create(anchor,center,right,up,0.001,{x=1800*scale,y=500*scale}))
        close(q.uv00.x,400/512);close(q.uv00.y,1)
        close(q.uv11.x,0);close(q.uv11.y,1-150/256)
        -- Map all four texture corners through the actual reversed-X draw
        -- convention, then compare with the original shared-plane coordinates.
        for _,xy in ipairs({{0,0},{1,0},{0,1},{1,1}})do
            local x,y=xy[1],xy[2]
            local actual=v(q.position.x+x*q.width*q.x_axis.x+y*q.height*q.z_axis.x,
                q.position.y+x*q.width*q.x_axis.y+y*q.height*q.z_axis.y,
                q.position.z+x*q.width*q.x_axis.z+y*q.height*q.z_axis.z)
            same(actual,Plane.point(plane,1700*scale+(1-x)*400,400*scale+y*150))
        end
        close(q.x_axis.x*q.y_axis.x+q.x_axis.y*q.y_axis.y+q.x_axis.z*q.y_axis.z,0)
        same(q.y_axis,v(-plane.normal.x,-plane.normal.y,-plane.normal.z))
        local saved=q.position.x
        source.metadata.pivot.x=0;source.metadata.bounds.x=0
        assert(q.position.x==saved,'quad borrowed mutable source layout')
        cases=cases+1
    end
end
for _,change in ipairs({
    function(m)m.pivot=nil end,
    function(m)m.pivot.x=0/0 end,
    function(m)m.pixel_width=513 end,
    function(m)m.pixel_height=0 end,
    function(m)m.pixel_width=400.1 end,
    function(m)m.capture_width=math.huge end,
    function(m)m.bounds.width=399 end,
    function(m)m.scale=0 end,
    function(m)m.bounds.x=1e308 end,
})do
    local source=image(1);change(source.metadata)
    assert(not Quad.create(Plane,source,v(0,2,0),center,right,up,0.001))
end
assert(not Quad.create(Plane,image(1),center,center,right,up,0.001))
assert(not Quad.create(Plane,image(1),v(0,2,0),center,right,right,0.001))
print('widget_quad: '..cases..' crop/scale/anchor cases, image-owned pivot and readable texture mapping pass')
