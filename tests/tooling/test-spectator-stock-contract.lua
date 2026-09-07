-- Optional stock-source contract. Real local service selection, camera state
-- decisions and teammate selection; engine camera, mood and UI are sinks.
-- Usage: luajit test-spectator-stock-contract.lua <stock-source-root>
local function methods(path, first, last, prefix)
    local f=assert(io.open(arg[1]..'/scripts/'..path..'.lua','r'))
    local s=f:read('*all'); f:close()
    local a=assert(s:find(first,1,true)); local b=assert(s:find(last,a,true))
    assert(loadstring((prefix or '')..s:sub(a,b-1),'@'..path))()
end
CameraHandler={}; HumanGameplay={}
CameraModes={first_person='first_person',observer='observer',dead='dead'}
local camera_path='managers/player/player_game_states/camera_handler'
local human_path='managers/player/player_game_states/human_gameplay'
methods(camera_path,'CameraHandler.update =','\nCameraHandler.remove_all_moods =')
methods(camera_path,'CameraHandler._follow_owner =','\nlocal valid_follow_units =')
methods(camera_path,'CameraHandler._next_follow_unit =','\nCameraHandler._get_theme_shading_environment =',
    'local valid_follow_units = {}\n')
methods(camera_path,'CameraHandler._camera_root_orientation =','\nCameraHandler._switch_follow_target =')
methods(human_path,'HumanGameplay._input_active =','\nlocal ui_interaction_action =')
methods(human_path,'HumanGameplay.update =','\nHumanGameplay._update_spectating =')
table.clear=function(t) for k in pairs(t) do t[k]=nil end end
local own,one,two,bot='own','one','two','bot'
local alive,hogtied,rescued,dead,cinematic,safe,ui,imgui,pressed=true,false,false,false,false,false,false,false,false
local input_reads,null_reads,switches,weather,moods,camera_updates=0,0,0,0,0,0
local first_person_rotation,component_rotation={1,2,3},{4,5,6}
local extensions={}
local player={player_unit=own,unit_is_alive=function() return alive end}
local members={own,bot,one,two}
local side={side_id=1,player_units=members}
local owners={[own]=player,[one]={},[two]={},[bot]={}}
for unit,owner in pairs(owners) do
    owner.is_human_controlled=function() return unit~=bot end
end
ALIVE={[own]=true,[one]=true,[two]=true,[bot]=true}
PlayerUnitStatus={is_hogtied=function(c) return c.hogtied end,
    is_assisted=function(c) return c.rescued end,is_dead=function(c) return c.dead end}
ScriptUnit={has_extension=function(unit,name)
    if unit==own and name=='unit_data_system' then return {read_component=function(_,component)
        if component=='character_state' then return {hogtied=hogtied,dead=dead} end
        assert(component=='assisted_state_input'); return {rescued=rescued}
    end} end
    return extensions[unit] and extensions[unit][name]
end,extension=function(unit,name)
    assert(unit==one and name=='unit_data_system')
    return {read_component=function(_,component) assert(component=='first_person'); return {rotation=component_rotation} end}
end}
Quaternion={to_yaw_pitch_roll=function(rotation) return unpack(rotation) end}
Managers={state={cinematic={cinematic_active=function() return cinematic end},
    game_mode={game_mode=function() return {in_safe_zone=function() return safe end} end},
    extension={system=function(_,name) assert(name=='weather_system'); return {update_weather=function() weather=weather+1 end} end},
    player_unit_spawn={owner=function(_,unit) return owners[unit] end}},
    ui={using_input=function() return ui end,handle_view_hotkeys=function() end},
    imgui={using_input=function() return imgui end},time={has_timer=function() return false end}}
local null={get=function(_,name) assert(name=='spectate_next'); null_reads=null_reads+1; return false end}
local input={get=function(_,name) assert(name=='spectate_next'); input_reads=input_reads+1; return pressed end,
    null_service=function() return null end}
local handler=setmetatable({_player=player,_camera_follow_unit=own,_mode=CameraModes.first_person,
    _side_id=1,_first_person_spectating_mode=true,
    _side_system={side_by_unit={[own]=side},get_side=function(_,id) assert(id==1); return side end},
    _switch_follow_target=function(self,unit) switches=switches+1; self._camera_follow_unit=unit end,
    _update_follow=function() end,_update_player_mood=function() moods=moods+1 end,
    remove_all_moods=function() end,_update_camera_manager=function() camera_updates=camera_updates+1 end},
    {__index=CameraHandler})
player.camera_handler=handler
local followed
local gameplay=setmetatable({_player=player,_input=input,
    _player_orientation_class=function() return {} end,
    _update_spectating=function(_,unit) followed=unit end,_handle_huds=function() end},
    {__index=HumanGameplay})
local function step(expected,mode)
    followed='not-called'; HumanGameplay.update(gameplay,.01,10)
    assert(followed==expected,'Unexpected stock follow target: '..tostring(followed))
    assert(handler._mode==mode,'Unexpected stock camera mode: '..tostring(handler._mode))
end
pressed=true
step(own,'first_person'); assert(input_reads==0,'Live owner consumed spectator action')
hogtied=true
step(own,'observer'); assert(input_reads==0,'Entering hogtied state skipped owner transition')
step(one,'observer'); assert(input_reads==1,'Hogtied cycle did not read selected service')
step(two,'observer'); step(own,'observer') -- Hogtied cycle may include own unit.
rescued=true
step(own,'observer') -- Rescue transition takes precedence over the pressed action.
hogtied=false; rescued=false
step(own,'first_person')
dead=true
step(own,'dead')
safe=true
step(one,'observer')
step(one,'observer') -- Dead safe-zone branch retains its stock target policy.
dead=false; safe=false; alive=false
step(two,'observer'); step(one,'observer') -- Missing/unavailable owner is excluded.
local before=input_reads
ui=true; step(one,'observer'); assert(input_reads==before and null_reads>0)
ui=false; imgui=true; step(one,'observer'); assert(input_reads==before)
imgui=false; cinematic=true
local old_weather,old_switches=weather,switches
step(one,'observer'); assert(input_reads==before and weather==old_weather and switches==old_switches)
cinematic=false; step(two,'observer')
-- A destroyed local unit must not be required merely to select a teammate.
player.player_unit=nil; members[1]=bot; members[2]=one; members[3]=two; members[4]=nil
step(one,'observer')
pressed=false; ALIVE[one]=false
step(two,'observer') -- Lost follow target advances without an input edge.
ALIVE[one]=true
player.player_unit=own; members[1]=own; members[2]=bot; members[3]=one; members[4]=two
alive=true; pressed=false
step(own,'first_person'); assert(handler._side_id==1)
-- Actual selection excludes AI owners, wraps, handles an empty roster and
-- never manufactures a target when only the excluded owner remains.
members[3],members[4]=nil,nil
assert(handler:_next_follow_unit(own)==nil)
handler._camera_follow_unit=nil
assert(handler:_next_follow_unit(own)==nil)
members[1],members[2]=nil,nil
assert(handler:_next_follow_unit(nil)==nil)
handler._side_id=nil; assert(handler:_next_follow_unit(nil)==nil)
-- Observer root comes from the followed unit, including its fallback. This
-- is separate from the local HMD view and is not a VR comfort acceptance test.
handler._mode='observer'; handler._camera_follow_unit=one
extensions[one]={first_person_system={spectated_aim_rotation=function() return first_person_rotation end}}
local orientation={orientation=function() return 7,8,9 end,orientation_offset=function() return .1,.2,.3 end}
local y,p,r=handler:_camera_root_orientation(orientation)
assert(y==1 and p==2 and r==3)
extensions[one]=nil
y,p,r=handler:_camera_root_orientation(orientation); assert(y==4 and p==5 and r==6)
handler._first_person_spectating_mode=false
y,p,r=handler:_camera_root_orientation(orientation); assert(y==7.1 and p==8.2 and r==9.3)
assert(camera_updates>0 and moods>0)
print('PASS: actual stock spectator service selection, rescue/death lifecycle, human roster and observer aim')
