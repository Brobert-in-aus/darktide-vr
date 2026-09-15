-- Execute the actual HUD hooks with the real online-rules admission policy.
local file=assert(io.open(arg[1])); local source=file:read('*all'); file:close()
local first=assert(source:find('mod:hook("HudElementSmartTagging", "_find_raycast_targets",',1,true))
local last=assert(source:find('\nfunction presentation.draw_tag_prompt',first,true))
local mode,live_hand,owner='shooting_range',false,'local'
local hooks,requests,forced={},0,0
mod={hook=function(_,class,name,fn) assert(class=='HudElementSmartTagging'); hooks[name]=fn end,
    hook_require=function() end,get=function() return true end,info=function() end}
local player={player_unit='local'}
Managers={player={local_player=function() return player end},
    state={game_session={is_server=function() return true end}},
    event={trigger=function(_,name) assert(name=='request_world_markers_list'); requests=requests+1 end}}
Unit={alive=function(unit) return unit=='local' or unit=='aim_enemy' end}
ScriptUnit={has_extension=function() return {can_tag=function() return true end} end}
callback=function() return function() end end
local state={authoring_enabled=true}
-- The hand the tag ray leaves: the off hand while the tag gesture says it is
-- pointing, else the weapon hand.
local tag_role='dominant'
local roles_asked={}
presentation={mode=1,gameplay_context=dofile(arg[3]),tag_role=function() return tag_role end,
    controller_aim={
    target=function(role) roles_asked[#roles_asked+1]=role; if live_hand then return 20,30 end end,
    cached_reticle_target=function() return 'reticle_point','aim_enemy' end}}
presentation.online_rules=dofile(arg[2]).install(mod,presentation,state,function() return mode end)
assert(loadstring(source:sub(first,last-1)))()
local head_marker={name='head',widget={content={distance=2}}}
local aim_marker={name='aim',widget={content={distance=7}}}
local raycast={unit='aim_enemy',static_hit_position='stock_point'}
local valid=true
local hud={_parent={player_unit=function() return owner end},
    _find_marker_by_unit=function(_,unit) return unit=='aim_enemy' and aim_marker or nil end,
    _is_marker_valid_for_tagging=function(_,unit,marker,distance)
        assert(unit==owner and marker==aim_marker and distance==7); return valid
    end}
local function stock_raycast(_,force)
    if force then forced=forced+1 end
    return raycast
end
hud._find_raycast_targets=function(self,force) return hooks._find_raycast_targets(stock_raycast,self,force) end
local function stock_marker() return head_marker,2 end
local function marker() return hooks._find_world_marker_target(stock_marker,hud,{}, {}) end
assert(hud:_find_raycast_targets(true)==raycast and forced==1,'Online tag bypassed stock forced targeting')
assert(roles_asked[1]=='dominant','the weapon hand by default')
tag_role='support'
hud:_find_raycast_targets(true)
assert(roles_asked[#roles_asked]=='support','the pointing hand while the tag gesture is on')
tag_role='dominant'
local selected,distance=marker()
assert(selected==aim_marker and distance==7,'Head-centred marker overrode simulation aim')
valid=false; selected,distance=marker(); assert(selected==nil and distance==math.huge)
valid=true; raycast={}; selected,distance=marker(); assert(selected==nil and distance==math.huge)
raycast={unit='aim_enemy'}
owner='remote'; assert(marker()==head_marker); owner='local'
state.authoring_enabled=false; assert(marker()==head_marker); state.authoring_enabled=true
presentation.mode=5; assert(marker()==head_marker); presentation.mode=1
Managers.state.game_session={is_server=function() return false end}; assert(marker()==head_marker)
Managers.state.game_session={is_server=function() error('retiring session') end}; assert(marker()==head_marker)
-- Existing local hand-origin path remains available outside the proving mode.
mode='hub'; live_hand=true
assert(marker()==aim_marker)
assert(hud:_find_raycast_targets(false).static_hit_position=='reticle_point')
assert(requests==4)
presentation.controller_aim.cached_reticle_target=function() end
local missing=hud:_find_raycast_targets(false)
assert(missing.unit==nil and missing.static_hit_position==nil,'Stale reticle target survived cache invalidation')
selected,distance=marker(); assert(selected==nil and distance==math.huge)
print('PASS: simulated tag target beats unrelated head marker; stock force update, validation and local hand path retained')
