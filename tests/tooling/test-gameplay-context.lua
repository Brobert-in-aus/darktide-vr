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
        assert(context.body_mode(mode,session)==(session==server))
        assert(context.aim_mode(mode,session)==(session==server))
    end
    for _,mode in ipairs({"default","unknown","loading","prologue_hub","hub_singleplay"}) do
        assert(not context.body_mode(mode,session) and not context.aim_mode(mode,session))
    end
end
assert(not context.aim_mode(nil,server) and not context.body_mode(nil,server))
assert(not context.aim_mode("coop_complete_objective",nil))
for _,owner in ipairs({true,17,'invalid',setmetatable({}, {
        __index=function() error('retired proxy lookup') end})}) do
    assert(not context.local_authority(owner),'Invalid owner authorized simulation')
    assert(context.ui_blocks_gameplay(owner),'Invalid owner authorized UI input')
    assert(not context.device_axes(owner),'Invalid owner selected device axes')
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
assert(not context.local_input_handler({_player=player},players),'Retired handler authorized input')
assert(not context.local_input_handler({_player={}},players),'Foreign player authorized input')
for _,invalid_owner in ipairs({{},true,17,setmetatable({}, {__index=function() error('retired lookup') end})}) do
    assert(not context.local_input_handler(handler,invalid_owner))
    assert(not context.local_input_handler(invalid_owner,players))
end
assert(not context.local_input_handler(handler,nil))
player=nil
assert(not context.local_input_handler(handler,players))
