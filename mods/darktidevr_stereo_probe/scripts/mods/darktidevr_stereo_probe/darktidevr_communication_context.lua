-- Unloaded ownership boundary. No input hooks or communication calls.
-- Caller must revoke its gesture/deferred callbacks before cancellation and
-- must not acquire while another route owns this HUD's wheel or tagging state.
local Context={}
local claims=setmetatable({},{__mode='k'})
local function busy(hud,context)
    return hud._wheel_active or hud._close_delay~=nil or
        context.input_start_time~=nil or context.single_tap_location_tag~=nil
end

function Context.acquire(hud,revoke)
    if type(hud)~='table' or hud.destroyed or type(revoke)~='function' or
        type(hud._com_wheel_context)~='table' or type(hud._tag_context)~='table' or
        type(hud._on_wheel_closed)~='function' then return nil,'invalid_owner' end
    local previous=hud._com_wheel_context
    if claims[hud] or busy(hud,previous) or hud._tag_context.input_start_time~=nil then return nil,'busy' end
    local owned={}
    local hover={}
    local active=true
    claims[hud]=owned
    hud._com_wheel_context=owned
    -- The previous route's hover grace must not select an entry for a new hold.
    hud._last_widget_hover_data=hover
    for _,entry in ipairs(hud._entries or {}) do
        local hotspot=entry.widget and entry.widget.content and entry.widget.content.hotspot
        if hotspot then hotspot.is_hover=false end
    end
    local api={}
    function api.current()
        return active and not hud.destroyed and hud._com_wheel_context==owned
    end
    function api.finish()
        if not api.current() then return false,'lost_owner' end
        if busy(hud,owned) then return false,'pending' end
        active=false
        if claims[hud]==owned then claims[hud]=nil end
        hud._com_wheel_context=previous
        return true
    end
    function api.cancel()
        if not active then return false,'retired' end
        active=false -- Retire even when revocation or stock cleanup throws.
        if claims[hud]==owned then claims[hud]=nil end
        local revoked,revoke_error=pcall(revoke)
        local closed,close_error=true,nil
        if hud._com_wheel_context==owned then
            -- Clear the owned table itself, so retained references cannot keep
            -- a delayed location tap or start/stop/double-tap state alive.
            for key in pairs(owned) do owned[key]=nil end
            hover.index=nil;hover.t=nil
            if not hud.destroyed then closed,close_error=pcall(hud._on_wheel_closed,hud) end
            -- A cleanup callback may replace the HUD context; never overwrite it.
            if hud._com_wheel_context==owned then hud._com_wheel_context=previous end
        end
        if not revoked then
            if not closed then revoke_error=tostring(revoke_error)..'; close: '..tostring(close_error) end
            error(revoke_error,0)
        end
        if not closed then error(close_error,0) end
        return true
    end
    return api
end
return Context
