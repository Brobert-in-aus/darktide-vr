-- Dedicated complete-widget capture resources. Not installed as an engine hook.
-- api contains the stock Renderer, World, Gui, UIRenderer, ScriptWorld and ui
-- manager. Allocate handles individually so partial construction can unwind.
local Capture = {}
Capture.__index = Capture
local generation = 0

local function extent(value)
    return type(value)=='number' and value==math.floor(value) and value>0 and value<=4096
end

local function required(value, label)
    assert(value, 'widget capture could not create '..label)
    return value
end

function Capture.new(api, width, height)
    assert(extent(width) and extent(height) and width*height<=4194304,
        'invalid widget capture extent')
    generation=generation+1
    local self=setmetatable({api=api,width=width,height=height},Capture)
    local name='darktidevr_widget_'..tostring(generation)
    local ok,err=pcall(function()
        self.world=required(api.ui:create_world(name..'_world',198,'ui'),'world')
        self.capture_target=required(api.Renderer.create_resource('render_target',
            'R8G8B8A8',nil,width,height,name..'_capture'),'capture target')
        self.display_target=required(api.Renderer.create_resource('render_target',
            'R8G8B8A8',nil,width,height,name..'_display'),'display target')
        assert(self.capture_target~=self.display_target,'capture/display alias')
        self.gui=required(api.World.create_screen_gui(self.world,'immediate',
            'custom_size',width,height),'immediate GUI')
        self.gui_retained=required(api.World.create_screen_gui(self.world,
            'custom_size',width,height),'retained GUI')
        self.renderer=required(api.UIRenderer.create_ui_renderer(self.world,
            self.gui,self.gui_retained,name),'renderer')
        local viewport_name=name..'_viewport'
        self.viewport=required(api.ui:create_viewport(self.world,viewport_name,
            'overlay',1,nil,nil,{back_buffer=self.capture_target}),'viewport')
        self.viewport_name=viewport_name
    end)
    if not ok then
        local _,cleanup=pcall(self.destroy,self)
        if cleanup then err=tostring(err)..'; cleanup: '..tostring(cleanup) end
        error(err,0)
    end
    return self
end

function Capture:queue(draw, metadata, revision)
    assert(not self.destroyed and not self.failed,'widget capture unavailable')
    assert(type(draw)=='function' and type(revision)=='number' and
        revision>0 and revision<math.huge and revision==math.floor(revision),
        'invalid widget capture queue')
    self.queued_revision=nil
    self.submitted_revision=nil
    local ok,err=pcall(function()
        -- Overlay backbuffers retain content unless explicitly cleared.
        self.api.Gui.render_pass(self.gui,0,'to_screen',true)
        -- Caller owns a separate begin/end pass and exception-safe restoration
        -- of its widget scenegraph. Never borrow the open stock renderer pass.
        draw(self.renderer,metadata)
    end)
    if not ok then self.failed=true;error(err,0) end
    self.queued_revision=revision
end

-- Call only AFTER a successful render of this exact owned world. The returned
-- revision may be passed to Surface:submitted; unrelated worlds return nil.
function Capture:observe_render(world)
    if self.destroyed or self.failed or world~=self.world then return nil end
    local revision=self.queued_revision
    if not revision or self.submitted_revision==revision then return nil end
    self.submitted_revision=revision
    return revision
end

function Capture:copy()
    assert(not self.destroyed and not self.failed,'widget capture unavailable')
    assert(self.queued_revision and self.submitted_revision==self.queued_revision,
        'widget capture has no submitted image')
    local ok,err=pcall(self.api.Renderer.copy_render_target_rect,
        self.capture_target,0,0,1,1,self.display_target,0,0,1,1)
    if not ok then self.failed=true;error(err,0) end
end

function Capture:destroy()
    if self.destroyed then return end
    self.destroyed=true
    self.queued_revision=nil
    self.submitted_revision=nil
    local api=self.api
    local errors={}
    local function release(fn,...)
        local ok,err=pcall(fn,...)
        if not ok then errors[#errors+1]=tostring(err) end
    end
    -- Remove the output binding before releasing either target. Continue after
    -- failures so one failed cleanup does not strand every later handle.
    if self.viewport_name then
        release(api.ScriptWorld.destroy_viewport,self.world,self.viewport_name)
    end
    if self.renderer then
        -- Stock destroy owns both GUIs for a normal viewport renderer.
        release(api.UIRenderer.destroy,self.renderer,self.world)
    else
        if self.gui_retained then release(api.World.destroy_gui,self.world,self.gui_retained) end
        if self.gui then release(api.World.destroy_gui,self.world,self.gui) end
    end
    if self.world then release(api.ui.destroy_world,api.ui,self.world) end
    if self.display_target and self.display_target~=self.capture_target then
        release(api.Renderer.destroy_resource,self.display_target)
    end
    if self.capture_target then release(api.Renderer.destroy_resource,self.capture_target) end
    self.renderer=nil
    self.gui=nil
    self.gui_retained=nil
    self.viewport=nil
    self.viewport_name=nil
    self.world=nil
    self.capture_target=nil
    self.display_target=nil
    if #errors>0 then error(table.concat(errors,'; '),0) end
end

return Capture
