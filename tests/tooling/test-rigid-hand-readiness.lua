local f=assert(io.open(arg[1],'r')); local source=f:read('*all'); f:close()
local first=assert(source:find('local function update_rigid_hand(',1,true))
local last=assert(source:find('\nlocal function place_rigid_hand(',first,true))
local updates,surfaces=0,0
Unit={alive=function(u) return not u.dead end}
show_rigid_hand_surface=function(hand) assert(hand.unit); surfaces=surfaces+1 end
local update=assert(loadstring(source:sub(first,last-1)..'\nreturn update_rigid_hand'))()
local function hand()
    local spawner={unit={},complete=false,fail=false}
    function spawner:update(dt,t)
        assert(dt==.02 and t==10); updates=updates+1
        if self.fail then error('stream failed') end
    end
    function spawner:spawned() return self.complete end
    function spawner:spawned_character_unit() return self.unit end
    return {side='left',profile_spawner=spawner},spawner
end
local h,s=hand()
assert(update(h,.02,10)==nil and not h.ready and h.unit==nil and surfaces==0,
    'An existing unit was accepted before the spawner completed initialization')
assert(update(h,.02,10)==nil and updates==2,'Pending spawner stopped receiving updates')
s.complete=true
assert(update(h,.02,10)==s.unit and h.ready and h.unit==s.unit)
assert(updates==3 and surfaces==1)
for _=1,100 do assert(update(h,.02,10)==s.unit) end
assert(updates==3 and surfaces==1,'Ready-hand update repeated the placement visibility pass')
s.unit.dead=true
assert(update(h,.02,10)==nil,'Dead unit was returned as ready')
h,s=hand(); s.complete=true; s.unit=nil
assert(update(h,.02,10)==nil and not h.ready)
s.unit={}; assert(update(h,.02,10)==s.unit and h.ready)
h,s=hand(); s.fail=true
local before=updates
assert(update(h,.02,10)==nil and h.failure and not h.ready)
assert(update(h,.02,10)==nil and updates==before+1,'Failed streaming retried every frame')
-- Replacement ownership gets a fresh hand record and can initialize normally.
h,s=hand(); s.complete=true
assert(update(h,.02,10)==s.unit and h.ready and not h.failure)
print('rigid hand waits for stock spawn readiness, initializes visibility once and retains failed-owner quarantine')
