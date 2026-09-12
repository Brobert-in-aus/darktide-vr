bit=require('bit')
local root=arg[1]
local Bindings=dofile(root..'/darktidevr_controller_bindings.lua')
local Turning=dofile(root..'/darktidevr_turning.lua')
local Gesture=dofile(root..'/darktidevr_communication_gesture.lua')
local settings={vr_turn_mode='off',vr_action_bind_primary=1+2048,
    vr_action_bind_alternate=2+4096,vr_action_bind_quick_wield=8192,vr_action_bind_interact=16384,
    vr_action_bind_combat_ability=0,vr_action_bind_reload=0} -- the stick defaults (switch, interact/reload) are owned here
local mod={get=function(_,name)return settings[name]end}
local bindings=Bindings.install(mod)
local function sample(physical,x,y,claimed)
    return bindings.sample(true,physical,x,y,true,1,'combat',nil,claimed)
end
sample(0,0,0)
local p,h,r=sample(0,0,1)
assert(p==1 and h==1)
p,h,r=sample(0,0,1,true)
assert(p==0 and h==0 and r==0,'claim must cancel axis action without an attack release')
p,h,r=sample(1,0,1,true)
assert(p==1 and h==1,'independent trigger must still work while the stick is claimed')
p,h,r=sample(0,0,1,true)
assert(r==1 and h==0,'real trigger release was swallowed by the stick claim')
for _,xy in ipairs({{0,1},{0,-1},{-1,0},{1,0}})do
    p,h,r=sample(0,xy[1],xy[2],false)
    assert(p==0 and h==0 and r==0,'sector change escaped post-claim neutral rearm')
end
sample(0,0,0,false)
p,h,r=sample(0,0,-1,false)
assert(p==2 and h==2,'fresh directional input failed after neutral')
sample(0,0,0)
p,h,r=sample(1,0,1)
assert(p==1 and h==1)
p,h,r=sample(1,0,1,true)
assert(p==0 and h==1 and r==0,'claim retriggered/cancelled a healthy trigger alias')
p,h,r=sample(0,0,1,true)
assert(r==1 and h==0)

-- Feed one gesture claim to both consumers before either applies gameplay.
-- Real adapter call ordering remains a required integration step.
for _,mode in ipairs({'smooth','snap45','snap90'})do
    settings.vr_turn_mode=mode
    local gate=Turning.install(mod)
    assert(gate.sample(true,0,0,true,1,1,'owner',1)==0)
    assert(gate.sample(true,1,0,true,1,1,'owner',1.01,true)==0)
    assert(gate.sample(true,-1,0,true,1,1,'owner',1.02,false)==0)
    assert(gate.sample(true,0,0,true,1,1,'owner',1.03,false)==0)
    assert(gate.sample(true,1,0,true,1,1,'owner',1.04,false)<0,
        mode..' did not resume after neutral')
end
settings.vr_turn_mode='snap45'
local turning=Turning.install(mod)
local gesture=Gesture.new(0.25)
local owner={}
local frame=0
local function turn(held,x,y)
    frame=frame+1
    local value=gesture.sample(frame,owner,true,held,x,y)
    local delta=turning.sample(true,x,y,true,1,1,owner,1+frame*0.01,value.claim_stick)
    return delta,value
end
turn(false,0,0);turn(false,0,0)
local delta,value=turn(true,1,0)
assert(delta==0 and value.claim_stick and value.pressed,'wheel start also turned the view')
delta,value=turn(false,1,0)
assert(delta==0 and value.released and value.claim_stick)
assert(gesture.take_release(value.token) and gesture.closed(value.token))
delta,value=turn(false,-1,0)
assert(delta==0 and value.claim_stick,'closing wheel surrendered a deflected stick')
delta,value=turn(false,0,0)
assert(delta==0 and not value.claim_stick)
delta,value=turn(false,1,0)
assert(delta<0,'fresh snap did not resume after neutral')
assert(turn(false,1,0)==0,'snap repeated without neutral')
turn(false,0,0);turn(true,1,0)
gesture.cancel()
assert(turn(false,-1,0)==0,'cancelled wheel allowed a stale snap')
turn(false,0,0)
assert(turn(false,-1,0)>0)
print('exclusive_gameplay_stick: cancel axes, preserve physical aliases, gate turns and rearm across sectors pass')
