local Gesture=dofile(assert(arg[1]))
local owner,other={},{}
local function armed()
    local gate=Gesture.new(0.2)
    assert(not gate.sample(1,owner,true,false,0,0).claim_stick)
    assert(not gate.sample(2,owner,true,false,0,0).claim_stick)
    return gate
end
local gate=armed()
local start=gate.sample(3,owner,true,true,0.9,0.4)
assert(start.pressed and start.held and start.claim_stick and start.x==0.9)
start.x=99
assert(gate.sample(3,owner,true,true,0.9,0.4).x==0.9, 'caller must not mutate cached decision')
local held=gate.sample(4,owner,true,true,-1,0)
assert(held.held and not held.pressed and held.token==start.token)
local release=gate.sample(5,owner,true,false,-1,0)
assert(release.released and not release.held and release.claim_stick and release.x==0)
assert(gate.sample(5,owner,true,false,0,0).released, 'same frame shares first decision')
assert(not gate.closed(release.token), 'cannot close before deferred selection is handled')
assert(gate.take_release(release.token))
assert(not gate.take_release(release.token), 'second eye/deferred duplicate must not select again')
assert(gate.closed(release.token))
assert(not gate.closed(release.token))
assert(gate.sample(6,owner,true,false,-1,0).claim_stick, 'held direction remains consumed during rearm')
assert(gate.sample(7,owner,true,true,0,0).claim_stick, 'hold must release before rearm')
assert(not gate.sample(8,owner,true,false,0,0).claim_stick)
local next_start=gate.sample(9,owner,true,true,0,1)
assert(next_start.pressed and next_start.token~=release.token)
assert(not gate.take_release(release.token), 'old release cannot select new gesture')

for _,reason in ipairs({'blocked','owner','backwards','invalid','cancel'}) do
    gate=armed(); local token=gate.sample(3,owner,true,true,0,0).token
    gate.sample(4,owner,true,false,0,0)
    local out
    if reason=='blocked' then out=gate.sample(4,owner,false,false,0,0)
    elseif reason=='owner' then out=gate.sample(4,other,true,false,0,0)
    elseif reason=='backwards' then out=gate.sample(2,owner,true,false,0,0)
    elseif reason=='invalid' then out=gate.sample(4,owner,true,false,0/0,0)
    else gate.cancel() end
    if out then assert(out.cancelled and not out.released and not out.claim_stick, reason) end
    assert(not gate.take_release(token), reason..' did not revoke deferred selection')
    assert(not gate.closed(token))
end

gate=Gesture.new(0.2)
for frame=1,3 do
    local out=gate.sample(frame,owner,true,true,0,0)
    assert(not out.pressed and not out.held, 'held on activation must not start a gesture')
end
assert(not gate.sample(4,owner,true,false,1,0).claim_stick)
assert(not gate.sample(5,owner,true,true,0,0).pressed)
gate.sample(6,owner,true,false,0.1,0.1)
assert(gate.sample(7,owner,true,true,0,0).pressed)
assert(not pcall(Gesture.new,0))
assert(not pcall(gate.sample,math.huge,owner,true,false,0,0))
print('communication_gesture=pass ownership, rearm, repeated frames, deferred release and cancellation')
