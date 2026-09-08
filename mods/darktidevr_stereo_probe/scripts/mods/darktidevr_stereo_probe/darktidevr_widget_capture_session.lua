-- Offline integration boundary for one bounded popup capture. Caller supplies
-- complete measured bounds; this module does not infer them from node sizes.
local Session={}
Session.__index=Session
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end

function Session.new(backend, pass_types, Surface, State, Snapshot, get_size)
    local self=setmetatable({backend=backend,Snapshot=Snapshot,get_size=get_size},Session)
    self.state=State.new(backend.renderer,pass_types)
    self.surface=Surface.new({
        copy=function() backend:copy() end,
        queue=function(_,draw,metadata,revision) backend:queue(draw,metadata,revision) end,
        destroy=function()
            local errors={}
            local function release(label,fn,owner)
                local ok,err=pcall(fn,owner)
                if not ok then errors[#errors+1]=label..': '..tostring(err) end
            end
            local display=self.display
            self.display=nil
            -- The display material borrows the completed target. Retire its
            -- GUI binding before capture caches, renderer and target teardown.
            if display then release('display',display.destroy,display) end
            release('state',self.state.destroy,self.state)
            release('backend',backend.destroy,backend)
            if #errors>0 then error(table.concat(errors,'; '),0) end
        end})
    return self
end

function Session:create_display(Display,api,world,Quad,Plane,layer)
    assert(not self.destroyed and not self.surface.failed and not self.display,
        'widget session display unavailable')
    -- A failed constructor owns its partial cleanup; do not retain it.
    local display=Display.new(api,world,self,Quad,Plane,layer)
    self.display=display
    return display
end

function Session:capture(t,identity,request)
    if self.destroyed or self.surface.failed then return false,'unavailable' end
    if not finite(t) or identity==nil then self:invalidate();return false,'invalid_input' end
    -- Preserve the first eye's complete acceptance/rejection decision. A second
    -- eye must not switch to capture after the first already drew stock.
    if self.t==t then
        if self.identity~=identity then return false,'identity_changed_within_frame' end
        return self.handled,self.reason
    end
    self.t=t;self.identity=identity
    self.handled=false;self.reason='invalid_input'
    local function reject(reason)
        self.surface:invalidate()
        self.reason=reason
        return false,reason
    end
    if type(request)~='table' or type(request.bounds)~='table' or
        type(request.settings)~='table' or type(request.draw)~='function' or
        not finite(request.dt) or request.dt<0 or not finite(request.scale) or request.scale<=0 then
        return reject('invalid_input')
    end
    local measured=request.bounds
    local pivot=request.pivot
    if type(pivot)~='table' or not finite(pivot.x) or not finite(pivot.y) then
        return reject('invalid_pivot')
    end
    if not finite(measured.x) or not finite(measured.y) or not finite(measured.width) or
        not finite(measured.height) or measured.width<=0 or measured.height<=0 then
        return reject('invalid_bounds')
    end
    -- Translate by whole capture pixels so stock pixel snapping remains in the
    -- same phase as the source. Round outward before testing target capacity;
    -- fractional origins can require one more pixel than width*scale suggests.
    local scale=request.scale
    local left,top=measured.x*scale,measured.y*scale
    local right,bottom=(measured.x+measured.width)*scale,(measured.y+measured.height)*scale
    if not finite(left) or not finite(top) or not finite(right) or not finite(bottom) or
        right<=left or bottom<=top then return reject('invalid_bounds') end
    left,top=math.floor(left),math.floor(top)
    right,bottom=math.ceil(right),math.ceil(bottom)
    local pixel_width,pixel_height=right-left,bottom-top
    if pixel_width>self.backend.width or pixel_height>self.backend.height then
        return reject('invalid_bounds')
    end
    local b={x=left/scale,y=top/scale,width=pixel_width/scale,height=pixel_height/scale}
    if not finite(b.x) or not finite(b.y) or not finite(b.width) or not finite(b.height) then
        return reject('invalid_bounds')
    end
    if request.settings.scale~=request.scale or request.settings.inverse_scale~=1/request.scale then
        return reject('inconsistent_scale')
    end
    local admitted,reason=self.state:admit(request.widgets,request.settings)
    if not admitted then return reject(reason) end
    local graph,detail=self.Snapshot.create(request.scenegraph,request.scale,-b.x,-b.y,self.get_size)
    if not graph then return reject(detail) end
    local metadata={bounds={x=b.x,y=b.y,width=b.width,height=b.height},scale=request.scale,
        pivot={x=pivot.x,y=pivot.y},pixel_width=pixel_width,pixel_height=pixel_height,
        capture_width=self.backend.width,capture_height=self.backend.height}
    local ok,handled,status=pcall(self.surface.capture,self.surface,t,identity,metadata,function()
        self.backend:pass(graph,request.input_service,request.dt,request.settings,function(renderer,settings)
            local routed,rejection=self.state:draw(request.widgets,settings,request.draw,renderer,settings)
            -- Preflight already admitted the entire widget. Never silently fall
            -- back after a callback may have advanced animation state.
            assert(routed,'capture admission changed: '..tostring(rejection))
        end)
    end)
    if not ok then
        self.reason='draw_failed'
        error(handled,0)
    end
    self.handled=handled;self.reason=status
    return handled,status
end

function Session:observe_render(world)
    if self.destroyed then return end
    local revision=self.backend:observe_render(world)
    if revision then self.surface:submitted(revision) end
end

function Session:visible(t,identity)
    if not self.handled then return nil end
    return self.surface:visible(t,identity)
end

function Session:invalidate()
    self.surface:invalidate()
    self.t=nil;self.identity=nil;self.handled=false;self.reason=nil
end

function Session:destroy()
    if self.destroyed then return end
    self.destroyed=true
    self:invalidate()
    self.surface:destroy()
end

return Session
