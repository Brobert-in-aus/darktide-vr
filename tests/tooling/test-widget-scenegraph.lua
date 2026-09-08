local Snapshot=dofile(arg[1])
-- These are the stock draw consumers' relevant semantics: root/fit nodes use
-- viewport dimensions; ordinary descendants use their resolved logical size.
local viewport={1920,1080}
local function size(graph,name,scale)
    local node=graph[name]
    if node.scale=='fit' or not node.parent then return viewport[1]/scale,viewport[2]/scale end
    return node.size[1],node.size[2]
end
local source={screen={size={1,1},world_position={0,0,0},scale='fit'},
    pivot={parent='screen',size={0,0},world_position={1800,500,100}},
    text={parent='pivot',size={420,70},world_position={1812,480,102}}}
source.hierarchical_scenegraph={source.screen}
source.screen.children={source.pivot}
source.screen.scene_graph_ref={native_cache=true}
local view,meta=Snapshot.create(source,1.5,-1700,-400,size)
assert(view and meta.nodes==3 and meta.scale==1.5)
assert(view.screen~=source.screen and view.text.size~=source.text.size)
assert(view.text.world_position[1]==112 and view.text.world_position[2]==80)
assert(view.text.world_position[3]==102)
assert(view.pivot.world_position[1]==100 and view.pivot.world_position[2]==100)
assert(not view.screen.children and not view.screen.scene_graph_ref)
assert(view.screen.scale==nil and view.screen.parent)
local w,h=size(view,'screen',1.5);assert(w==1280 and h==720)
-- A capture viewport resize cannot re-resolve a source root's fit dimensions.
viewport={512,256}
w,h=size(view,'screen',1.5);assert(w==1280 and h==720)
w,h=size(view,'text',1.5);assert(w==420 and h==70)
view.text.world_position[1]=0;view.text.size[1]=1
assert(source.text.world_position[1]==1812 and source.text.size[1]==420)
source.pivot.world_position[1]=900
assert(view.pivot.world_position[1]==100)
assert(source.screen.scene_graph_ref.native_cache)
assert(not Snapshot.create({},1,0,0,size))
assert(not Snapshot.create(source,0,0,0,size))
assert(not Snapshot.create(source,1,0/0,0,size))
assert(not Snapshot.create(source,1,0,0,function() error('size failed') end))
assert(not Snapshot.create(source,1,0,0,function() return math.huge,1 end))
assert(not Snapshot.create(source,1,0,0,function() return -1,1 end))
source.text.world_position[2]=0/0
assert(not Snapshot.create(source,1,0,0,size))
source.text.world_position[2]=480
local too_many={}
for i=1,257 do too_many[i]={parent=true,size={1,1},world_position={i,0,0}} end
assert(select(2,Snapshot.create(too_many,1,0,0,size))=='too_many_nodes')
print('widget_scenegraph: detached positions, frozen fit sizes, translation and bounds validation pass')

-- Optional real stock consumer check; cached game sources are not distributed.
if arg[2] then
    Vector3={};EngineOptimized={}
    local stock=dofile(arg[2])
    local checked=0
    for _,mode in ipairs({'root','fit','hud_fit','fit_width','fit_height','aspect_ratio','child'}) do
        for _,scale in ipairs({0.75,1,1.5,2}) do
            RESOLUTION_LOOKUP={width=1920,height=1080,scale=scale}
            local node={size={600,200},world_position={1500,600,101}}
            if mode~='root' then node.parent='screen' end
            if mode~='root' and mode~='child' then node.scale=mode end
            local graph={node=node}
            local expected_w,expected_h=stock.get_size(graph,'node',scale)
            local capture=assert(Snapshot.create(graph,scale,-1400,-500,stock.get_size))
            RESOLUTION_LOOKUP={width=512,height=256,scale=scale}
            local actual_w,actual_h=stock.get_size(capture,'node',scale)
            assert(actual_w==expected_w and actual_h==expected_h,mode)
            local position=stock.world_position(capture,'node')
            assert(position[1]==100 and position[2]==100 and position[3]==101)
            checked=checked+1
        end
    end
    print('widget_scenegraph: actual cached stock get_size/world_position pass '..checked..' configurations')
end
