local root=arg[1]
local function module(name) return dofile(root..'/darktidevr_'..name..'.lua') end
local Session,Surface,State,Snapshot=module('widget_capture_session'),module('widget_surface'),
    module('widget_capture_state'),module('widget_scenegraph')
local cleanup={}
local types={texture={init=function() return {} end,
    destroy=function(pass,r) cleanup[#cleanup+1]='material';assert(pass.data.material==r) end}}
local function backend()
    return {width=512,height=256,renderer={},world={},queues=0,copies=0,
        queue=function(self,draw,metadata,revision)
            self.queues=self.queues+1;self.submitted=nil;draw();self.revision=revision
        end,
        pass=function(self,graph,input,dt,settings,draw)
            self.graph=graph;draw(self.renderer,settings)
        end,
        observe_render=function(self,world)
            if world==self.world and self.revision~=self.submitted then
                self.submitted=self.revision;return self.revision
            end
        end,
        copy=function(self)
            assert(self.submitted==self.revision)
            self.copies=self.copies+1
            if self.fail_copy then error('copy failed') end
        end,
        destroy=function(self) cleanup[#cleanup+1]='backend';self.destroyed=true end}
end
local function setup()
    local b=backend()
    local session=Session.new(b,types,Surface,State,Snapshot,function(graph,name) return unpack(graph[name].size) end)
    local original={material='source'}
    local pass={pass_type='texture',value_id='image',data=original}
    local widgets={{passes={pass},style={},content={image='material'}}}
    local draws=0
    local request={bounds={x=1700,y=400,width=400,height=150},scale=1,dt=0.01,
        settings={scale=1,inverse_scale=1},widgets=widgets,
        scenegraph={pivot={parent='root',size={400,150},world_position={1700,400,100}}},
        draw=function(renderer)
            draws=draws+1;assert(pass.data~=original);pass.data.material=renderer
            assert(b.graph.pivot.world_position[1]==0 and b.graph.pivot.world_position[2]==0)
        end}
    return session,b,request,function() return draws end,original,pass
end
local s,b,r,draws,original,pass=setup()
local identity={}
assert(select(2,s:capture(1,identity,r))=='warming' and draws()==1)
assert(pass.data==original and original.material=='source')
assert(s:capture(1,identity,r) and draws()==1)
assert(not s:capture(1,{},r))
s:observe_render({});assert(not s:visible(1,identity))
s:observe_render(b.world)
r.bounds.width=420
assert(select(2,s:capture(2,identity,r))=='ready')
assert(s:visible(2,identity).metadata.bounds.width==400 and draws()==2 and b.copies==1)
-- One rejected first-eye decision cannot become a second-eye capture.
r.bounds.width=700
assert(select(2,s:capture(3,identity,r))=='invalid_bounds')
assert(not s:visible(3,identity))
r.bounds.width=400
assert(select(2,s:capture(3,identity,r))=='invalid_bounds' and draws()==2)
assert(select(2,s:capture(4,identity,r))=='warming')
s:observe_render(b.world)
local other={}
assert(select(2,s:capture(5,other,r))=='warming' and not s:visible(5,other))
-- Hide and reappear cannot copy the hidden target's last submission.
s:observe_render(b.world);s:invalidate()
assert(select(2,s:capture(6,other,r))=='warming')
s:observe_render(b.world)
assert(select(2,s:capture(0,other,r))=='warming')
s:destroy();s:destroy()
assert(cleanup[#cleanup-1]=='material' and cleanup[#cleanup]=='backend')
assert(not s:capture(7,identity,r) and not s:visible(7,identity))

s,b,r,draws=setup()
r.settings.scale=2
assert(select(2,s:capture(1,identity,r))=='inconsistent_scale' and b.queues==0)
r.settings.scale=1;r.widgets[1].passes[1].retained_mode=true
assert(select(2,s:capture(2,identity,r))=='retained_mode' and b.queues==0)
s:destroy()

s,b,r,draws,original,pass=setup()
local good_draw=r.draw
r.draw=function(renderer) good_draw(renderer);error('widget broke') end
local ok,err=pcall(s.capture,s,1,identity,r)
assert(not ok and tostring(err):find('widget broke',1,true))
assert(draws()==1 and pass.data==original and not s:visible(1,identity))
assert(not s:capture(2,identity,r) and draws()==1)
s:destroy()

s,b,r,draws=setup()
assert(s:capture(1,identity,r));s:observe_render(b.world);b.fail_copy=true
assert(select(2,s:capture(2,identity,r))=='copy_failed' and draws()==1)
assert(not s:visible(2,identity));s:destroy()
-- Fractional logical bounds need outward pixel alignment at every UI scale.
for _,case in ipairs({
    {scale=1,x=1700.25,y=400.75,w=399.5,h=149.5,bx=1700,by=400,bw=400,bh=151},
    {scale=2,x=-0.1,y=-2.3,w=100,h=40,bx=-0.5,by=-2.5,bw=100.5,bh=40.5},
    {scale=0.5,x=1,y=1,w=399,h=149,bx=0,by=0,bw=400,bh=150},
}) do
    s,b,r,draws,original,pass=setup()
    r.scale=case.scale;r.settings.scale=case.scale;r.settings.inverse_scale=1/case.scale
    r.bounds={x=case.x,y=case.y,width=case.w,height=case.h}
    r.draw=function()
        pass.data.material=b.renderer
        assert(b.graph.pivot.world_position[1]==1700-case.bx)
        assert(b.graph.pivot.world_position[2]==400-case.by)
    end
    assert(s:capture(1,identity,r));s:observe_render(b.world)
    assert(s:capture(2,identity,r))
    local bounds=s:visible(2,identity).metadata.bounds
    assert(bounds.x==case.bx and bounds.y==case.by and bounds.width==case.bw and bounds.height==case.bh)
    assert(r.bounds.x==case.x and r.bounds.width==case.w, 'caller bounds must remain unchanged')
    s:destroy()
end
for _,bounds in ipairs({
    {x=0.25,y=0,width=512,height=100}, -- 513 pixels after outward alignment.
    {x=0,y=-0.25,width=100,height=256}, -- 257 pixels with a negative origin.
    {x=1e308,y=0,width=1e308,height=100}, -- Finite operands, overflowing sum.
    {x=1e308,y=0,width=1,height=100}, -- Extent lost to floating-point precision.
}) do
    s,b,r=setup();r.bounds=bounds
    assert(select(2,s:capture(1,identity,r))=='invalid_bounds' and b.queues==0)
    s:destroy()
end
print('widget_capture_session: first-eye admission, pixel-aligned bounds, failure cleanup and lifecycle pass')
