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
-- Authority is checked on each call, never latched across host loss/loading.
local owns=true
local changing={is_server=function() return owns end}
assert(context.aim_mode("coop_complete_objective",changing))
owns=false
assert(not context.aim_mode("coop_complete_objective",changing))
print("gameplay_context=pass explicit_modes local_authority missing_retiring_sessions host_loss baseline_preserved")
