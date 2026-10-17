-- Complete the native mapper's UI actions through stock semantics. No keys,
-- cursor warps, retained menu requests or direct tag/network calls.
local Input = {}
local function query_usable(source)
    return source~=nil and not (source.is_null_service and source:is_null_service()) and
        not (source.null_service and source==source:null_service())
end
local function usable(source)
    -- Eligibility is optional VR work. A retiring service may throw even during
    -- method lookup; skip injection so the stock consumer still owns its update.
    local ok,result=pcall(query_usable,source)
    return ok and result==true
end

-- The menu control: a tap opens the system menu when it is let go, a hold
-- shows the tactical overlay for as long as it is held (the gamepad's View and
-- Start, on the one Quest menu button). The overlay never opened in VR before
-- (17 October review): its action had no control.
Input.MENU_HOLD_SECONDS = 0.35

function Input.install(mod, local_player_unit, clock, read_menu_button)
    local state = {sample=0}
    clock = clock or function()
        local time = Managers and Managers.time
        return time and time:has_timer("main") and time:time("main") or os.clock()
    end
    local api = {}
    local inventory_owner
    local tactical_owner
    local tag_owner
    local tag_frames = setmetatable({}, {__mode="k"})

    local function current_owner()
        local ok, owner = pcall(local_player_unit)
        return ok and owner or nil
    end

    local function request_owner_current()
        if state.owner ~= nil and current_owner() == state.owner then return true end
        state.owner = nil
        return false
    end

    function api.sample(active, pressed, held)
        state.sample = state.sample + 1
        state.active = active == true
        local menu_down = state.active and bit.band(held or 0,1024) ~= 0
        local now = clock()
        if menu_down and not state.menu_down then state.menu_since = now end
        local overlay = menu_down and state.menu_since ~= nil and now - state.menu_since >= Input.MENU_HOLD_SECONDS
        -- A tap, released before it became a hold: the menu, on the release.
        state.menu = state.active and state.menu_down == true and not menu_down and not state.menu_overlay
        state.menu_overlay = menu_down and (state.menu_overlay or overlay) or false
        state.menu_down = menu_down
        if not menu_down then state.menu_since = nil end
        -- The menu control takes precedence while it is down, as the menu did
        -- when it opened on the press.
        local menu_busy = state.menu or menu_down
        state.inventory = state.active and not menu_busy and bit.band(pressed or 0,32768) ~= 0
        state.tag = state.active and not menu_busy and not state.inventory and bit.band(pressed or 0,256) ~= 0
        state.tactical = state.active and not state.menu and not state.inventory and
            (bit.band(held or 0,2097152) ~= 0 or state.menu_overlay)
        -- The overlay's tab swap shares the interact control, as stock shares
        -- E and the gamepad's X between them.
        state.swap = state.tactical and bit.band(pressed or 0,8) ~= 0
        state.owner = (state.menu or state.inventory or state.tag or state.tactical) and current_owner() or nil
    end

    local function local_tactical_owner(self)
        return request_owner_current() and self._parent and self._parent:player_unit()==state.owner
    end
    -- Stock re-fetches Ingame input inside update. Scope the existing central
    -- input-manager route; do not install a competing get_input_service hook.
    local function tactical_scope(owner_test,func,self,...)
        local ok,local_hud=false,false
        if state.active and state.tactical then ok,local_hud=pcall(owner_test,self) end
        if not tactical_owner and (not ok or not local_hud) then return func(self,...) end
        local previous=tactical_owner
        tactical_owner=ok and local_hud and {hud=self,sample=state.sample} or nil
        local function pack(...) return {n=select('#',...),...} end
        local result=pack(pcall(func,self,...))
        tactical_owner=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
    mod:hook('HudElementTacticalOverlay','update',function(func,self,...)
        return tactical_scope(local_tactical_owner,func,self,...)
    end)
    -- The mission-buff choice reads the same hold to show the overlay behind
    -- it. While a choice is open the game hands gameplay a null input and the
    -- mod a menu mode, so the gameplay sample above is never active there
    -- (17 October review: the scope was a no-op). The menu button is read
    -- from the controller state instead and timed here.
    local buff_scope, buff_since
    mod:hook('ConstantElementMissionBuffs','update',function(func,self,...)
        local ok,down=false,false
        if read_menu_button then ok,down=pcall(read_menu_button) end
        local now=clock()
        if ok and down==true then buff_since=buff_since or now else buff_since=nil end
        local hold=buff_since~=nil and now-buff_since>=Input.MENU_HOLD_SECONDS
        if not hold and not buff_scope then return func(self,...) end
        local previous=buff_scope
        buff_scope=hold and {element=self} or nil
        local function pack(...) return {n=select('#',...),...} end
        local result=pack(pcall(func,self,...))
        buff_scope=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end)
    function api.route_ingame_input(source,name)
        if name=='Ingame' and buff_scope and usable(source) then
            local scope=buff_scope
            return setmetatable({get=function(_,action,...)
                if action=='tactical_overlay_hold' and buff_scope==scope then return true end
                return source:get(action,...)
            end},{__index=function(_,key)
                local value=source[key]
                if type(value)=='function' then return function(_,...)return value(source,...)end end
                return value
            end})
        end
        if name~='Ingame' or not tactical_owner or not state.active or not state.tactical or
            not request_owner_current() or not usable(source) then return source end
        local scope_owner=tactical_owner
        return setmetatable({get=function(_,action,...)
            local value=source:get(action,...)
            local inject=(action=='tactical_overlay_hold' or (action=='tactical_overlay_swap' and state.swap)) and
                tactical_owner==scope_owner and
                state.sample==scope_owner.sample and state.active and state.tactical and request_owner_current()
            return inject and true or value
        end},{__index=function(_,key)
            local value=source[key]
            if type(value)=='function' then return function(_,...)return value(source,...)end end
            return value
        end})
    end

    -- Feed the stock hotkey owner, preserving its mode whitelist, transitions,
    -- modal gates and view validation. Expire even if stock never reads input.
    mod:hook("UIManager","_update_view_hotkeys",function(func,self,...)
        local previous=inventory_owner
        inventory_owner=state.active and state.inventory and request_owner_current() and
            {manager=self,sample=state.sample} or nil
        state.inventory=false
        local function pack(...) return {n=select("#",...),...} end
        local result=pack(pcall(func,self,...))
        inventory_owner=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end)
    function api.route_hotkey_input(source,self,service)
        if not inventory_owner or inventory_owner.manager~=self or (service and service~="View") or
                not usable(source) then return source end
        local scope=inventory_owner
        return setmetatable({get=function(_,name,...)
            local value=source:get(name,...)
            local inject=name=="hotkey_inventory" and inventory_owner==scope and
                state.sample==scope.sample and state.active and request_owner_current()
            return inject and true or value
        end},{__index=function(_,name)
            local value=source[name]
            if type(value)=="function" then return function(_,...) return value(source,...) end end
            return value
        end})
    end

    function api.update_menu(manager)
        local requested = state.menu
        state.menu = false -- Expire even when another UI owner blocks this frame.
        if not requested or not state.active or not request_owner_current() or not manager or
                manager:using_input() or manager:view_active("system_view") then return end
        manager:open_view("system_view")
    end

    -- `pressed` leads so the stock arguments can be a tail: naming them
    -- drops whatever the engine adds beyond them (17 September).
    local function run_tag(func,pressed,self,t,renderer,settings,source,...)
        -- Unowned/nested HUD handlers must not inherit an outer injection.
        -- Keep the ordinary no-request path free of proxy/scope allocation.
        if not pressed and not tag_owner then return func(self,t,renderer,settings,source,...) end
        local previous=tag_owner
        local scope=pressed and {hud=self,sample=state.sample} or nil
        tag_owner=scope
        local input=source
        if scope then
            input=setmetatable({get=function(_,name,...)
                local value=source:get(name,...)
                local inject=name=='smart_tag' and tag_owner==scope and
                    state.sample==scope.sample and state.active and request_owner_current()
                return inject and true or value
            end},{__index=function(_,name)
                local value=source[name]
                if type(value)=='function' then return function(_,...)return value(source,...)end end
                return value
            end})
        end
        local function pack(...)return {n=select('#',...),...}end
        local result=pack(pcall(func,self,t,renderer,settings,input,...))
        tag_owner=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end

    mod:hook("HudElementSmartTagging", "_handle_tagging",
        function(func,self,t,renderer,settings,source,...)
            local owner = current_owner()
            if not owner or owner ~= state.owner then
                state.owner = nil -- Cancel the sample across every HUD, even if an old owner returns.
                state.tag = false
                tag_frames[self] = nil
                return run_tag(func,false,self,t,renderer,settings,source,...)
            end
            local local_hud = owner and self._parent and self._parent:player_unit() == owner
            if not local_hud then return run_tag(func,false,self,t,renderer,settings,source,...) end
            local blocked = not usable(source)
            local previous = tag_frames[self]
            local sample
            if previous and previous.t == t and previous.sample == state.sample then
                sample = previous.pressed
            else
                sample = local_hud and state.active and state.tag and not blocked
                state.tag = false
                tag_frames[self] = {t=t,sample=state.sample,pressed=sample}
            end
            if blocked then tag_frames[self].pressed = false end
            return run_tag(func,sample and not blocked,self,t,renderer,settings,source,...)
        end)
    -- In stock play the middle mouse button carries both smart_tag and
    -- com_wheel, so a tap with nothing under the reticle becomes a location
    -- marker. Report this HUD's tag press for the frame so the wheel handler
    -- can see the same one-frame com_wheel press.
    function api.tag_tap_frame(hud,t)
        local frame=tag_frames[hud]
        return frame~=nil and frame.t==t and frame.sample==state.sample and frame.pressed==true
    end
    return api
end

return Input
