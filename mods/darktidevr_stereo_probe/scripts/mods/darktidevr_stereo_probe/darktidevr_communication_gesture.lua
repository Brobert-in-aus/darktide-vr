-- Unloaded candidate: gesture ownership only, with no game or communication API.
-- Caller supplies one monotonic input frame, local owner, routing eligibility,
-- physical hold and raw right stick. It must suppress every gameplay stick route
-- while claim_stick is true, and cancel explicitly if its HUD adapter fails.
local Gesture={}
local function finite(value)
    return type(value)=='number' and value==value and value>-math.huge and value<math.huge
end
function Gesture.new(neutral_radius)
    assert(finite(neutral_radius) and neutral_radius>0 and neutral_radius<1, 'invalid neutral radius')
    local state={phase='rearm',generation=0}
    local api={}
    local function clear(owner)
        state.generation=state.generation+1
        state.phase='rearm'; state.owner=owner; state.release_pending=false
    end
    local function result(pressed,released,cancelled,x,y)
        local holding=state.phase=='holding'
        local claim=holding or state.phase=='closing' or state.phase=='rearm_owned'
        return {held=holding,pressed=pressed==true,released=released==true,
            cancelled=cancelled==true,claim_stick=claim,
            x=holding and x or 0,y=holding and y or 0,
            token=claim and state.generation or nil}
    end
    local function copy(value)
        local out={}; for key,item in pairs(value) do out[key]=item end; return out
    end
    function api.cancel()
        clear(nil); state.cached=nil
    end
    function api.sample(frame,owner,eligible,held,x,y)
        assert(finite(frame) and frame>=0 and frame%1==0, 'invalid input frame')
        local valid=eligible==true and owner~=nil and type(held)=='boolean' and
            finite(x) and finite(y) and math.abs(x)<=1 and math.abs(y)<=1
        local changed_owner=owner~=state.owner
        local backwards=state.frame~=nil and frame<state.frame
        if not valid or changed_owner or backwards then
            local cancelled=state.phase=='holding' or state.phase=='closing' or state.phase=='rearm_owned'
            clear(valid and owner or nil)
            state.frame=frame
            state.cached=result(false,false,cancelled,0,0)
            -- Even a neutral new owner needs a later frame before acquisition.
            return copy(state.cached)
        end
        if frame==state.frame and state.cached then return copy(state.cached) end
        state.frame=frame
        local neutral=x*x+y*y<=neutral_radius*neutral_radius
        local pressed,released=false,false
        if state.phase=='rearm' or state.phase=='rearm_owned' then
            if not held and neutral then
                state.phase='idle'
                state.generation=state.generation+1
            end
        elseif state.phase=='idle' and held then
            state.phase='holding'; state.generation=state.generation+1; pressed=true
        elseif state.phase=='holding' and not held then
            state.phase='closing'; state.release_pending=true; released=true
        end
        state.cached=result(pressed,released,false,x,y)
        return copy(state.cached)
    end
    -- Call inside the deferred stock callback, not when scheduling it. A token
    -- authorizes at most one intentional release, and cancellation revokes it.
    function api.take_release(token)
        if state.phase~='closing' or token~=state.generation or not state.release_pending then return false end
        state.release_pending=false
        return true
    end
    -- Call after stock's close delay/cursor cleanup. Neutral rearm is still
    -- required before gameplay stick input can resume; stale callbacks do nothing.
    function api.closed(token)
        if state.phase~='closing' or token~=state.generation or state.release_pending then return false end
        state.phase='rearm_owned'
        return true
    end
    return api
end
return Gesture
