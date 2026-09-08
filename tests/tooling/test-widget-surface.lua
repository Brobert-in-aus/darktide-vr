local Surface=dofile(arg[1])
local function backend()
    return {copies=0,queues=0,destroys=0,
        copy=function(self)
            self.copies=self.copies+1
            if self.fail_copy then error('copy broke') end
        end,
        queue=function(self,draw,metadata,revision)
            self.queues=self.queues+1
            self.revision=revision
            draw()
        end,
        destroy=function(self) self.destroys=self.destroys+1 end}
end
local key,other={},{}
local old_bounds,new_bounds={width=400},{width=430}
local b=backend()
local s=Surface.new(b)
local draws=0
local function draw() draws=draws+1 end
assert(select(2,s:capture(1,key,old_bounds,draw))=='warming')
assert(not s:visible(1,key) and b.copies==0 and draws==1)
-- Repeated eye draws must not advance stock animations or recapture.
assert(s:capture(1,key,old_bounds,draw))
assert(draws==1 and b.queues==1)
assert(not s:capture(1,other,old_bounds,draw))
assert(not s:visible(1,other))
s:submitted(b.revision)
assert(select(2,s:capture(2,key,new_bounds,draw))=='ready')
local image=assert(s:visible(2,key))
assert(image.metadata==old_bounds and image.captured_t==1 and image.revision==1)
assert(b.copies==1 and draws==2)
assert(not s:visible(1,key) and not s:visible(3,key))
-- A missing render hides the prior image rather than indefinitely freezing it.
assert(select(2,s:capture(3,key,new_bounds,draw))=='warming')
assert(not s:visible(3,key) and b.copies==1)
local previous=b.revision
assert(s:capture(4,other,new_bounds,draw))
s:submitted(previous)
assert(select(2,s:capture(5,other,new_bounds,draw))=='warming')
assert(b.copies==1)
s:submitted(b.revision)
assert(select(2,s:capture(6,other,new_bounds,draw))=='ready')
assert(s:visible(6,other).metadata==new_bounds)
-- Hide/show and main-time rollback must both start from an empty image.
s:invalidate()
assert(not s:visible(6,other))
assert(select(2,s:capture(7,other,new_bounds,draw))=='warming')
s:submitted(b.revision)
assert(select(2,s:capture(0,other,new_bounds,draw))=='warming')
assert(not s:capture(0/0,key,new_bounds,draw))
s:destroy();s:destroy()
assert(b.destroys==1 and not s:capture(8,key,new_bounds,draw))

b=backend();s=Surface.new(b)
assert(s:capture(1,key,old_bounds,draw));s:submitted(b.revision)
b.fail_copy=true
local before=draws
local handled,reason=s:capture(2,key,old_bounds,draw)
assert(not handled and reason=='copy_failed' and draws==before)
assert(not s:visible(2,key) and not s:capture(3,key,old_bounds,draw))
s:destroy();assert(b.destroys==1)

b=backend();s=Surface.new(b)
local attempts=0
local ok,err=pcall(s.capture,s,1,key,old_bounds,function()
    attempts=attempts+1;error('draw broke')
end)
assert(not ok and tostring(err):find('draw broke',1,true) and attempts==1)
assert(not s:visible(1,key) and not s:capture(2,key,old_bounds,draw))
s:destroy();assert(b.destroys==1)
print('widget_surface: shared-eye image lifetime, submission, identity, failures pass')
