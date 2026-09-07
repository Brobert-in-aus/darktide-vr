local file=assert(io.open(arg[1],'r'))
local source=file:read('*all'); file:close()
local Context=dofile(arg[2])
local first=assert(source:find('function presentation.update_psykhanium(manager, t)',1,true))
local last=assert(source:find('\nfunction presentation.update_system_menu_test',first,true))
local env={presentation={},mod={info=function() end,error=function() end}}
setmetatable(env,{__index=_G})
env.presentation.current_game_mode_name=function()
    return Context.game_mode_name(env.Managers and env.Managers.state and env.Managers.state.game_mode)
end
local chunk=assert(loadstring(source:sub(first,last-1)))
setfenv(chunk,env); chunk()
local update=env.presentation.update_psykhanium
local ui={view_active=function(_,view) assert(view=='training_grounds_view'); return true end}
local function reset(stage)
    env.presentation.psykhanium={stage=stage,deadline=100}
    env.Managers={state={game_mode={game_mode_name=function() return stage=='wait_for_hub' and 'hub' or 'shooting_range' end},
        mission={mission_name=function() return 'tg_shooting_range' end}},
        backend={authenticated=function() return true end}}
end
local function stays(stage)
    update(ui,1); assert(env.presentation.psykhanium.stage==stage)
end
for _,stage in ipairs({'wait_for_hub','wait_shooting_range'}) do
    reset(stage); env.Managers=nil; stays(stage)
    reset(stage); env.Managers={}; stays(stage)
    for _,owner in ipairs({false,17,{},setmetatable({}, {__index=function() error('owner retired') end})}) do
        reset(stage); env.Managers.state.game_mode=owner; stays(stage)
        reset(stage)
        if stage=='wait_for_hub' then env.Managers.backend=owner
        else env.Managers.state.mission=owner end
        stays(stage)
    end
end
reset('wait_for_hub'); env.Managers.backend.authenticated=function() return false end
stays('wait_for_hub')
reset('wait_for_hub'); update(ui,1)
assert(env.presentation.psykhanium.stage=='select_shooting_range')
for _,mode in ipairs({'hub','training_grounds','coop_complete_objective'}) do
    reset('wait_shooting_range'); env.Managers.state.game_mode.game_mode_name=function() return mode end
    stays('wait_shooting_range')
end
reset('wait_shooting_range'); env.Managers.state.mission.mission_name=function() return 'other' end
stays('wait_shooting_range')
reset('wait_shooting_range')
local mission={name='tg_shooting_range'}
setmetatable(mission,{__index={mission_name=function(self) assert(self==mission); return self.name end}})
env.Managers.state.mission=mission; update(ui,1)
assert(env.presentation.psykhanium.stage=='complete')
reset('wait_for_hub'); update(ui,101)
assert(env.presentation.psykhanium.stage=='blocked' and env.presentation.psykhanium.last_error=='timeout')
print('psykhanium_entry=pass retiring_queries mode_and_mission_confirmation timeout')
