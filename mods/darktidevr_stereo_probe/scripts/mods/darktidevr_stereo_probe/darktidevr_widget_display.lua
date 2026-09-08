-- Unloaded immediate world-GUI display for one capture session. Destroy this
-- owner BEFORE its capture backend or source world. Caller chooses draw layer;
-- this is not acceptance of marker occlusion, complete bounds or engine hooks.
local Display={}
Display.__index=Display
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end

function Display.new(api,world,session,Quad,Plane,layer)
    assert(api and world and session and session.backend and finite(layer),'invalid widget display owner')
    local backend=session.backend
    assert(not backend.destroyed and not backend.failed and backend.display_target and
        backend.capture_target~=backend.display_target,'invalid widget display target')
    local self=setmetatable({api=api,world=world,session=session,backend=backend,
        target=backend.display_target,Quad=Quad,Plane=Plane,layer=layer},Display)
    local ok,err=pcall(function()
        self.gui=assert(api.World.create_world_gui(world,api.Matrix4x4.identity(),1,1,'immediate'),
            'widget display GUI creation failed')
        self.material=assert(api.Gui.create_material(self.gui,
            'content/ui/materials/icons/items/containers/item_container_square'),
            'widget display material creation failed')
        for name,value in pairs({use_placeholder_texture=0,use_render_target=1,rows=1,columns=1,grid_index=0}) do
            api.Material.set_scalar(self.material,name,value)
        end
        api.Material.set_resource(self.material,'render_target',self.target)
    end)
    if not ok then
        local cleaned,cleanup=pcall(self.destroy,self)
        if not cleaned then err=tostring(err)..'; cleanup: '..tostring(cleanup) end
        error(err,0)
    end
    return self
end

function Display:draw(t,identity,anchor,center,right,up,tangent_per_pixel)
    if self.destroyed or self.failed then return false,'unavailable' end
    local backend=self.backend
    if backend.destroyed or backend.failed or self.session.backend~=backend or
        backend.display_target~=self.target then return false,'backend_changed' end
    if not finite(t) or identity==nil then return false,'invalid_input' end
    local image=self.session:visible(t,identity)
    if self.t==t then
        if self.identity~=identity then return false,'image_changed_within_frame' end
        if not self.revision then return false,self.reason end
        if not image then return false,'hidden' end
        if self.revision~=image.revision then return false,'image_changed_within_frame' end
    else
        self.t=t;self.identity=identity;self.revision=nil;self.quad=nil;self.reason='hidden'
        if not image then return false,self.reason end
        if not finite(image.revision) or image.revision<=0 or image.revision%1~=0 or
            type(image.metadata)~='table' or image.metadata.capture_width~=backend.width or
            image.metadata.capture_height~=backend.height then
            self.reason='invalid_image';return false,self.reason
        end
        self.revision=image.revision
        self.quad,self.reason=self.Quad.create(self.Plane,image,anchor,center,right,up,tangent_per_pixel)
    end
    if not self.quad then return false,self.reason end
    local q,api=self.quad,self.api
    local function v(value)return api.Vector3(value.x,value.y,value.z)end
    local ok,err=pcall(function()
        local tm=api.Matrix4x4.identity()
        api.Matrix4x4.set_right(tm,v(q.x_axis))
        api.Matrix4x4.set_forward(tm,v(q.y_axis))
        api.Matrix4x4.set_up(tm,v(q.z_axis))
        api.Matrix4x4.set_translation(tm,v(q.position))
        api.Gui2.bitmap_3d(self.gui,self.material,nil,tm,self.layer,{
            position_offset=api.Vector3(0,0,0),size=api.Vector3(q.width,q.height,0),
            color=api.Color(255,255,255,255),uv00=api.Vector2(q.uv00.x,q.uv00.y),
            uv11=api.Vector2(q.uv11.x,q.uv11.y),snap_pixel_positions=false})
    end)
    if not ok then self.failed=true;error(err,0) end
    return true
end

function Display:destroy()
    if self.destroyed then return end
    self.destroyed=true;self.quad=nil
    local errors={}
    local function release(fn,...)
        local ok,err=pcall(fn,...)
        if not ok then errors[#errors+1]=tostring(err) end
    end
    if self.material then release(self.api.Gui.destroy_material,self.gui,self.material) end
    if self.gui then release(self.api.World.destroy_gui,self.world,self.gui) end
    self.material=nil;self.gui=nil
    if #errors>0 then error(table.concat(errors,'; '),0) end
end
return Display
