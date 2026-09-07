-- Complete the native mapper's UI actions through stock semantics. No keys,
-- cursor warps, retained menu requests or direct tag/network calls.
local Input = {}

function Input.install(mod, local_player_unit)
    local state = {sample=0}
    local api = {}
    local inventory_owner
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

    function api.sample(active, pressed)
        state.sample = state.sample + 1
        state.active = active == true
        state.menu = state.active and bit.band(pressed or 0,1024) ~= 0
        state.inventory = state.active and not state.menu and bit.band(pressed or 0,32768) ~= 0
        state.tag = state.active and not state.menu and not state.inventory and bit.band(pressed or 0,256) ~= 0
        state.owner = (state.menu or state.inventory or state.tag) and current_owner() or nil
    end

    -- Feed the stock hotkey owner, preserving its mode whitelist, transitions,
    -- modal gates and view validation. Expire even if stock never reads input.
    mod:hook("UIManager","_update_view_hotkeys",function(func,self,...)
        local previous=inventory_owner
        inventory_owner=state.active and state.inventory and request_owner_current() and self or nil
        state.inventory=false
        local function pack(...) return {n=select("#",...),...} end
        local result=pack(pcall(func,self,...))
        inventory_owner=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end)
    function api.route_hotkey_input(source,self,service)
        if inventory_owner~=self or (service and service~="View") or not source or
                (source.null_service and source==source:null_service()) then return source end
        return setmetatable({get=function(_,name,...)
            local value=source:get(name,...)
            return name=="hotkey_inventory" and true or value
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

    mod:hook("HudElementSmartTagging", "_handle_tagging",
        function(func,self,t,renderer,settings,source)
            local owner = current_owner()
            if not owner or owner ~= state.owner then
                state.owner = nil -- Cancel the sample across every HUD, even if an old owner returns.
                state.tag = false
                tag_frames[self] = nil
                return func(self,t,renderer,settings,source)
            end
            local local_hud = owner and self._parent and self._parent:player_unit() == owner
            if not local_hud then return func(self,t,renderer,settings,source) end
            local blocked = not source or (source.null_service and source == source:null_service())
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
            if not sample or blocked then return func(self,t,renderer,settings,source) end
            local proxy = setmetatable({get=function(_,name,...)
                local value = source:get(name,...)
                return name == "smart_tag" and true or value
            end},{__index=function(_,name)
                local value = source[name]
                if type(value)=="function" then
                    return function(_,...) return value(source,...) end
                end
                return value
            end})
            return func(self,t,renderer,settings,proxy)
        end)
    return api
end

return Input
