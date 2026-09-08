-- Execute the production fixed-update hook with human/bot ordering. Stock
-- locally spawned bots have _is_local_unit=true, just like the human player.
local file=assert(io.open(arg[1],'r'));local source=file:read('*all');file:close()
local first=assert(source:find('    mod:hook(\n        PlayerUnitSmartTargetingExtension,\n        "fixed_update",',1,true))
local last=assert(source:find('\n    mod:command(',first,true))
local owner,bot1,bot2,remote={},{},{},{}
local hook,active,cached,clears,publishes,stock_calls=nil,false,nil,0,0,0
local online=true
local player={player_unit=owner}
local pose={position={},rotation={}}
local env={PlayerUnitSmartTargetingExtension={},
    mod={hook=function(_,_,method,fn) assert(method=='fixed_update');hook=fn end},
    is_local_unit=function(unit) return player.player_unit==unit end,
    presentation={online_rules={enabled=function() return online end},
        online_reticle={pose=function(ext)
            if ext._unit==player.player_unit then return pose.position,pose.rotation end
        end},
        publish_gameplay_aim_state=function(value) active=value;clears=clears+1 end},
    controller_aim={clear_reticle=function() cached=nil end,
        publish_reticle=function(ext) active=true;cached=ext._unit;publishes=publishes+1 end,
        target=function() return pose.position,pose.rotation end},
    with_first_person_pose=function(ext,_,_,fn,...) return fn(ext,...) end}
setmetatable(env,{__index=_G})
setfenv(assert(loadstring(source:sub(first,last-1))),env)()
local function stock(self,unit,dt,t,token)
    stock_calls=stock_calls+1
    assert(self._unit==unit and dt==.016 and t==1 and token=='preserved')
    return token
end
local function update(unit,local_flag)
    assert(hook(stock,{_unit=unit,_is_local_unit=local_flag,
        _first_person_component=pose},unit,.016,1,'preserved')=='preserved')
end
for _,mode in ipairs({true,false}) do
    online=mode;active=false;cached=nil;clears=0;publishes=0
    update(owner,true)
    assert(active and cached==owner and publishes==1)
    for i=1,3 do update(bot1,true);update(bot2,true);update(remote,false) end
    assert(active and cached==owner and publishes==1 and clears==0,
        'A bot/remote update overwrote the human reticle')
end
player.player_unit={}
update(owner,true)
assert(publishes==1 and clears==0,'Retired human unit changed the current reticle')
update(player.player_unit,true)
assert(cached==player.player_unit and publishes==2)
online=true;pose={}
update(player.player_unit,true)
assert(not active and cached==nil and clears==1,'Current owner could not clear unavailable aim')
assert(stock_calls==23,'Ownership guard skipped stock targeting')
print('reticle_owner=pass human/bots/remote, both aim modes, owner replacement, stock forwarding')
