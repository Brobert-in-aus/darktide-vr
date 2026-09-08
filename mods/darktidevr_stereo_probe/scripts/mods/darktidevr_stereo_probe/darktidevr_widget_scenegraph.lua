-- Draw-only snapshot for UIWidget's get_size/world_position reads. Resolve
-- stock screen-fit sizing once before translating into capture coordinates.
-- Never pass this snapshot to UIScenegraph.update_scenegraph or cache builders.
local Snapshot={}
local function finite(n)
    return type(n)=='number' and n==n and math.abs(n)<math.huge
end

function Snapshot.create(source, scale, offset_x, offset_y, get_size)
    if type(source)~='table' or not finite(scale) or scale<=0 or
        not finite(offset_x) or not finite(offset_y) or type(get_size)~='function' then
        return nil,'invalid_input'
    end
    local result={}
    -- A private, truthy parent prevents stock get_size from treating formerly
    -- root nodes as screen-fit nodes. It is not an engine hierarchy.
    local parent={}
    local count=0
    for name,node in pairs(source) do
        if type(node)=='table' and rawget(node,'world_position')~=nil then
            count=count+1
            if count>256 then return nil,'too_many_nodes' end
            local position=node.world_position
            if type(position)~='table' or not finite(position[1]) or
                not finite(position[2]) or not finite(position[3]) then
                return nil,'invalid_position'
            end
            local ok,width,height=pcall(get_size,source,name,scale)
            if not ok or not finite(width) or not finite(height) or width<0 or height<0 then
                return nil,'invalid_size'
            end
            local x,y=position[1]+offset_x,position[2]+offset_y
            if not finite(x) or not finite(y) then return nil,'invalid_translation' end
            result[name]={name=name,parent=parent,size={width,height},
                world_position={x,y,position[3]}}
        end
    end
    if count==0 then return nil,'empty_scenegraph' end
    return result,{scale=scale,offset_x=offset_x,offset_y=offset_y,nodes=count}
end

return Snapshot
