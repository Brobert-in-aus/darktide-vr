local function yaw(d) local r=math.rad(d)/2;return {0,0,math.sin(r),math.cos(r)} end
local function degrees(q) return math.deg(2*math.atan2(q[3],q[4])) end
local function near(a,b) assert(math.abs(degrees(a)-b)<.002,string.format('%g != %g',degrees(a),b)) end
Quaternion={angle=function(a,b)
    local dot=0;for i=1,4 do dot=dot+a[i]*b[i] end
    return 2*math.acos(math.min(1,math.abs(dot)))
end,lerp=function(a,b,t)
    local q,n={},0;for i=1,4 do q[i]=a[i]*(1-t)+b[i]*t;n=n+q[i]^2 end
    for i=1,4 do q[i]=q[i]/math.sqrt(n) end;return q
end}
QuaternionBox=function(q) return {unbox=function() return q end} end
local Assist=dofile(assert(arg[1]))
near(Assist.limit(yaw(0),yaw(1)),.5)
near(Assist.limit(yaw(0),yaw(4)),1)
near(Assist.limit(yaw(0),yaw(6)),0)
local requested=true
Mods={lua={io={open=function() return {read=function() return 'enabled' end,close=function() end} end}}}
local time,blocked,gamepad,buff,calls,saves=1,false,false,false,0,0
local unit,target_unit,position={},{},{}
local template={keywords={'ranged','force_staff'}}
local weapon={weapon_template=function() return template end}
local targeting={unit=target_unit}
local helper={_unit=unit,_weapon_extension=weapon,_buff_extension={has_keyword=function() return buff end},
    targeting_data=function() return targeting end,
    assisted_hitscan_trajectory=function(_,settings,weapon_template,rotation)
        calls=calls+1;assert(settings=='stock' and weapon_template==template);return yaw(degrees(rotation)+2)
    end}
package.loaded['scripts/utilities/smart_targeting']={smart_targeting_template=function() return 'stock' end}
local settings={input_settings={controller_aim_assist='off'}}
Managers={save={account_data=function() return settings end,queue_save=function() saves=saves+1 end},
    event={trigger=function(_,event) assert(event=='event_on_input_settings_changed') end},
    time={time=function() return time end},ui={},input={is_using_gamepad=function() return gamepad end},
    player={local_player_safe=function() return {player_unit=unit} end}}
Unit={alive=function(u) return not u.dead end};DevParameters={}
local raw=yaw(0)
local tracking={authoring_enabled=true,right_aim_usable=true,last_sequence=1,last_transport_generation=1}
local presentation={mode=1,weapon_hand_roles={physical=function() return 'right' end},
    gameplay_context={ui_blocks_gameplay=function() return blocked end},
    weapon_aim_target=function() return position,raw end}
local api=Assist.install({info=function() end,warning=function(_,error) error(error) end},presentation,tracking)
local function aim() local p,q=presentation.weapon_aim_target('dominant');assert(p==position);return q end
near(aim(),0);api.observe(helper,time);assert(saves==1 and settings.input_settings.controller_aim_assist=='new_slim')
near(aim(),1);near(aim(),1);assert(calls==1,'multiple consumers advanced assist')
near(select(2,presentation.weapon_aim_target('support')),0)
targeting.unit=nil;near(aim(),0);targeting.unit=target_unit
blocked=true;near(aim(),0);blocked=false
gamepad=true;near(aim(),0);gamepad=false
buff=true;near(aim(),0);buff=false
tracking.right_aim_usable=false;near(aim(),0);tracking.right_aim_usable=true
tracking.last_transport_generation=2;near(aim(),0);api.observe(helper,time);near(aim(),1)
template={keywords={'ranged'}};near(aim(),0);api.observe(helper,time);near(aim(),1)
time=2;near(aim(),0);api.observe(helper,time);near(aim(),1)
unit={};near(aim(),0)
unit=helper._unit;settings.input_settings.controller_aim_assist='off';near(aim(),0)
api.observe(helper,time);assert(saves==1,'startup request must not override later choices')
print('Light correction bounds, staff support, shared samples, target/ownership/tracking resets and one-shot save pass')
