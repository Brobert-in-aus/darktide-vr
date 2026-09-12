local context=dofile(arg[1])
local server={is_server=function(self) assert(self); return true end}
local client={is_server=function() return false end}
local missing={}
local broken={is_server=function() error("session retiring") end}
local invalid={is_server=function() return "true" end}
for _,session in ipairs({server,client,missing,broken,invalid}) do
    assert(context.body_mode("hub",session))
    assert(not context.aim_mode("hub",session))
    for _,range in ipairs({"shooting_range","training_grounds"}) do
        assert(context.body_mode(range,session) and context.aim_mode(range,session))
    end
    for _,mode in ipairs({"coop_complete_objective","survival","expedition","prologue"}) do
        -- Presentation and stock input admit both established authorities;
        -- the local-authority aim route admits only the owning process.
        assert(context.body_mode(mode,session)==(session==server or session==client))
        assert(context.aim_mode(mode,session)==(session==server))
        assert(context.local_mission(mode,session)==(session==server))
        assert(context.remote_mission(mode,session)==(session==client))
    end
    local expected_authority = nil
    if session==server then expected_authority = true elseif session==client then expected_authority = false end
    assert(context.authority(session)==expected_authority)
    assert(not context.remote_mission("hub",session) and not context.remote_mission("shooting_range",session))
    for _,mode in ipairs({"default","unknown","loading","prologue_hub","hub_singleplay"}) do
        assert(not context.body_mode(mode,session) and not context.aim_mode(mode,session))
    end
end
assert(not context.aim_mode(nil,server) and not context.body_mode(nil,server))
-- The onboarding hub reports as the hub: same level, template and locomotion.
assert(context.game_mode_name({game_mode_name=function() return "prologue_hub" end})=="hub")
assert(context.game_mode_name({game_mode_name=function() return "hub_singleplay" end})=="hub_singleplay")
-- The owner's setting reader can withdraw remote admission at any query; a
-- failing or non-boolean reader admits nothing, and never touches local modes.
for _,reader in ipairs({function() return false end,function() error('retiring settings') end,
        function() return 'true' end}) do
    context.remote_missions_allowed=reader
    assert(not context.remote_mission("coop_complete_objective",client))
    assert(not context.body_mode("coop_complete_objective",client))
    assert(context.body_mode("coop_complete_objective",server) and context.body_mode("hub",client))
end
context.remote_missions_allowed=function() return true end
assert(context.remote_mission("coop_complete_objective",client))
assert(not context.aim_mode("coop_complete_objective",nil))
assert(context.input_service_enabled({is_null_service=function() return false end}))
assert(not context.input_service_enabled({is_null_service=function() return true end}))
assert(not context.input_service_enabled(nil))
assert(not context.input_service_enabled({}))
assert(not context.input_service_enabled({is_null_service=function() return nil end}))
for _,owner in ipairs({true,17,'invalid',setmetatable({}, {
        __index=function() error('retired proxy lookup') end})}) do
    assert(not context.local_authority(owner),'Invalid owner authorized simulation')
    assert(context.ui_blocks_gameplay(owner),'Invalid owner authorized UI input')
    assert(not context.device_axes(owner),'Invalid owner selected device axes')
    assert(not context.input_service_enabled(owner),'Invalid input service admitted controller actions')
end
local proxy=setmetatable({}, {__index={is_server=function(self)
    assert(getmetatable(self)); return true
end,using_input=function(self) assert(getmetatable(self)); return false end}})
assert(context.local_authority(proxy) and not context.ui_blocks_gameplay(proxy),
    'Valid inherited owner methods lost their self receiver')
-- Authority is checked on each call, never latched across host loss/loading.
local owns=true
local changing={is_server=function() return owns end}
assert(context.aim_mode("coop_complete_objective",changing))
owns=false
assert(not context.aim_mode("coop_complete_objective",changing))
print("gameplay_context=pass explicit_modes local_authority missing_retiring_sessions host_loss baseline_preserved")
local player={}
local handler={_player=player}
player.input_handler=handler
local players={local_player=function(self,index) assert(self and index==1); return player end}
assert(context.local_input_handler(handler,players))
Unit={alive=function(unit) return unit=='live' end}
assert(context.local_input_unit(handler,players)==nil)
player.player_unit='live'
assert(context.local_input_unit(handler,players)=='live')
player.player_unit='dead'
assert(context.local_input_unit(handler,players)==nil)
player.player_unit='live'
assert(not context.local_input_handler({_player=player},players),'Retired handler authorized input')
assert(not context.local_input_handler({_player={}},players),'Foreign player authorized input')
assert(context.local_input_unit({_player=player},players)==nil)
for _,invalid_owner in ipairs({{},true,17,setmetatable({}, {__index=function() error('retired lookup') end})}) do
    assert(not context.local_input_handler(handler,invalid_owner))
    assert(not context.local_input_handler(invalid_owner,players))
    assert(context.local_input_unit(handler,invalid_owner)==nil)
    assert(context.local_input_unit(invalid_owner,players)==nil)
end
assert(not context.local_input_handler(handler,nil))
player=nil
assert(not context.local_input_handler(handler,players))

-- Exercise the actual main-mod mode seam as well as its shared policy. Lookup
-- can throw before a retiring manager's method is even obtained.
local file=assert(io.open(arg[2],'r')); local source=file:read('*all'); file:close()
local first=assert(source:find('local function active_game_mode_name()',1,true))
local last=assert(source:find('\npresentation.gameplay_context =',first,true))
local environment={presentation={gameplay_context=context},Managers={state={}}}
setmetatable(environment,{__index=_G})
local chunk=assert(loadstring(source:sub(first,last-1)..'\nreturn active_game_mode_name'))
setfenv(chunk,environment)
local active_mode=chunk()
local current_first=assert(source:find('function presentation.current_game_mode_name()',1,true))
local current_last=assert(source:find('\nfunction presentation.apply_offline_benchmark_spin',current_first,true))
local current_chunk=assert(loadstring(source:sub(current_first,current_last-1)))
setfenv(current_chunk,environment); current_chunk()
for _,active_mode in ipairs({active_mode,environment.presentation.current_game_mode_name}) do
environment.Managers={state={}}
environment.Managers.state.game_mode=setmetatable({}, {__index=function() error('mode owner retired during lookup') end})
assert(active_mode()==nil,'Retired mode lookup escaped into gameplay')
for _,owner in ipairs({{},true,17,
        {game_mode_name=function() error('mode owner retired during call') end}}) do
    environment.Managers.state.game_mode=owner
    assert(active_mode()==nil)
end
environment.Managers.state.game_mode=nil; assert(active_mode()==nil)
for _,value in ipairs({true,17,{}}) do
    environment.Managers.state.game_mode={game_mode_name=function() return value end}
    assert(active_mode()==nil,'Non-string mode was accepted')
end
local current_mode='shooting_range'
environment.Managers.state.game_mode=setmetatable({}, {__index={game_mode_name=function(self)
    assert(getmetatable(self)); return current_mode
end}})
assert(active_mode()=='shooting_range')
current_mode='hub'; assert(active_mode()=='hub','Mode lookup cached a retired context')
environment.Managers=nil; assert(active_mode()==nil)
end
print('game_mode_lookup=pass actual_seam protected_lookup_call strict_type inherited_receiver current_mode')
