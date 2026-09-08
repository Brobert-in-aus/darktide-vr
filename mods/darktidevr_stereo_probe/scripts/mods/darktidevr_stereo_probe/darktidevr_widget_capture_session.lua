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
            local ok,err=pcall(self.state.destroy,self.state)
            local released,release_error=pcall(backend.destroy,backend)
            if not ok then
                if not released then err=tostring(err)..'; backend: '..tostring(release_error) end
                error(err,0)
            end
            if not released then error(release_error,0) end
        end})
    return self
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
    local b=request.bounds
    if not finite(b.x) or not finite(b.y) or not finite(b.width) or not finite(b.height) or
        b.width<=0 or b.height<=0 or b.width*request.scale>self.backend.width or
        b.height*request.scale>self.backend.height then return reject('invalid_bounds') end
    if request.settings.scale~=request.scale or request.settings.inverse_scale~=1/request.scale then
        return reject('inconsistent_scale')
    end
    local admitted,reason=self.state:admit(request.widgets,request.settings)
    if not admitted then return reject(reason) end
    local graph,detail=self.Snapshot.create(request.scenegraph,request.scale,-b.x,-b.y,self.get_size)
    if not graph then return reject(detail) end
    local metadata={bounds={x=b.x,y=b.y,width=b.width,height=b.height},scale=request.scale,
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
