-- Caller samples a fresh physical hold BEFORE both
-- gameplay stick consumers and supplies exact owner/generation/routing checks.
-- Stock owns wheel behavior and intentional deferred communication effects.
local Wheel={}
local function pack(...)return {n=select('#',...),...}end
local function query_usable(input)
    return input and not (input.is_null_service and input:is_null_service()) and
        not (input.null_service and input==input:null_service())
end
local function usable(input)
    -- Deferred release can outlive the HUD input proxy. Treat failed method
    -- lookup/query as lost input ownership so cancellation still runs.
    local ok,result=pcall(query_usable,input)
    return ok and result==true
end

function Wheel.install(mod,config)
    local gesture=config.Gesture.new(0.25)
    local state={}
    local update_scope
    local api={}
    local function valid(hud)
        return state.owner~=nil and state.sample~=nil and
            config.current(state.owner)==true and config.hud_owner(hud,state.owner)==true
    end
    local function current(hud)
        local ok,result=pcall(valid,hud)
        return ok and result==true
    end
    local function cancel()
        local owned=state.owned
        state.owned=nil;state.sample=nil;state.owner=nil
        if owned then owned.context.cancel() else gesture.cancel() end
    end
    local function fail(err)
        local cleaned,cleanup=pcall(cancel)
        if not cleaned then err=tostring(err)..'; cancel: '..tostring(cleanup) end
        error(err,0)
    end
    function api.cancel()cancel()end
    function api.sample(frame,owner,eligible,held,x,y)
        local sampled=gesture.sample(frame,owner,eligible,held,x,y)
        state.owner=owner;state.sample=sampled
        if sampled.cancelled or (not state.owned and sampled.released) then
            cancel();return false
        end
        return sampled.claim_stick
    end
    local function scope_for(hud)
        local owned=state.owned
        if owned and owned.hud==hud then return owned end
    end
    local function inside(owned)
        return update_scope and update_scope.owned==owned and update_scope.sample==state.sample
    end

    mod:hook('HudElementSmartTagging','update',function(func,self,...)
        local owned=scope_for(self)
        if owned and (not current(self) or not owned.context.current()) then cancel();owned=nil end
        if not owned and not state.owned and state.sample and state.sample.pressed and current(self) then
            local context=config.Context.acquire(self,gesture.cancel)
            if not context then cancel() else
                owned={hud=self,context=context,token=state.sample.token}
                state.owned=owned
            end
        end
        if not owned and not update_scope then return func(self,...) end
        local previous=update_scope
        update_scope=owned and {owned=owned,sample=state.sample} or nil
        local result=pack(pcall(func,self,...))
        update_scope=previous
        if not result[1] then
            if owned and state.owned==owned then fail(result[2]) end
            error(result[2],0)
        end
        if owned and state.owned==owned and owned.release_taken and owned.context.finish() then
            state.owned=nil
            assert(gesture.closed(owned.token),'wheel release closed without its gesture token')
        end
        return unpack(result,2,result.n)
    end)

    mod:hook('HudElementSmartTagging','_handle_com_wheel',function(func,self,t,renderer,settings,input)
        local owned=scope_for(self)
        if not owned then return func(self,t,renderer,settings,input) end
        -- Never let an unscoped reentrant call operate the owned stock context.
        if not inside(owned) then return end
        if not current(self) or not usable(input) then cancel();return func(self,t,renderer,settings,input) end
        if owned.handled_t==t then return end
        owned.handled_t=t
        local sample,scope=state.sample,update_scope
        local proxy=setmetatable({get=function(_,name,...)
            if name=='com_wheel' and state.owned==owned and update_scope==scope and
                state.sample==sample and current(self) then return sample.held end
            return input:get(name,...)
        end},{__index=function(_,name)
            local value=input[name]
            if type(value)=='function' then return function(_,...)return value(input,...)end end
            return value
        end})
        return func(self,t,renderer,settings,proxy)
    end)

    mod:hook('HudElementSmartTagging','_update_wheel_presentation',function(func,self,dt,t,renderer,settings,input)
        local owned=scope_for(self)
        if not owned then return func(self,dt,t,renderer,settings,input) end
        if not inside(owned) then return end
        if not current(self) or not usable(input) then cancel();return end
        -- Preserve the last intentional selection throughout deferred release
        -- and close delay. Do not replace it with the neutral release sample.
        if not state.sample.held then return end
        local sample,scope=state.sample,update_scope
        local width,height=config.dimensions()
        return config.Navigation.with_input(input,sample,width,height,config.vector,function(token)
            return state.owned==owned and state.sample==sample and update_scope==scope and
                owned.token==token and current(self)
        end,function(proxy)return func(self,dt,t,renderer,settings,proxy)end)
    end)

    mod:hook('HudElementSmartTagging','_on_com_wheel_stop',function(func,self,t,renderer,settings,input)
        local owned=scope_for(self)
        if not owned then return func(self,t,renderer,settings,input) end
        if not inside(owned) or not current(self) or state.sample.held or owned.release_queued then return end
        owned.release_queued=true
        -- Stock stop only schedules this callback. Capture our token now and
        -- consume it at execution, after rechecking ownership and routing.
        config.defer(function()
            if state.owned~=owned then return end
            if not current(self) or not owned.context.current() or not usable(input) then cancel();return end
            if not gesture.take_release(owned.token) then return end
            local ok,err=pcall(self._on_com_wheel_stop_callback,self,t,renderer,settings,input)
            if not ok then fail(err) end
            owned.release_taken=true
        end)
    end)

    mod:hook('HudElementSmartTagging','destroy',function(func,self,...)
        if scope_for(self) then cancel() end
        return func(self,...)
    end)
    return api
end
return Wheel
