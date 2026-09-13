-- Label only routes that the menu adapter actually supplies. RT is a pointed
-- mouse click, not a keyboard/gamepad confirmation action.
local Prompts = {}
local direct = {back="vr_menu_back",left_pressed="vr_menu_point_select",
    left_released="vr_menu_point_select",left_hold="vr_menu_point_select",
    -- The cutscene and video legends carry a press callback, which would
    -- read as a pointed click; the skip needs no pointing, only the trigger.
    skip_cinematic="vr_menu_hold_skip",skip_cinematic_hold="vr_menu_hold_skip"}
local function pack(...) return {n=select("#",...),...} end

function Prompts.install(mod, enabled, secondary_enabled)
    local Text=require("scripts/utilities/ui/text")
    local InputUtils=require("scripts/managers/input/input_utils")
    local label, clickable
    local revisions=setmetatable({}, {__mode="k"})
    local api={}
    -- The gameplay prompt module owns the single DMF hook on InputUtils. DMF
    -- replaces a same-mod hook handler on duplicate registration.
    function api.secondary_available()
        return secondary_enabled ~= nil and secondary_enabled() == true
    end
    function api.input_text(service,alias,tint)
        if not label or service~="View" or not enabled() then return nil end
        local text=("["..mod:localize(label).."]"):gsub('%s','\194\160')
        if tint then text=InputUtils.apply_color_to_input_text(text,Color.ui_input_color(255,true)) end
        return text
    end
    -- A view whose own buttons have their own VR route labels them for the
    -- duration of `fn` (e.g. the end screen: vote by pointing, continue by
    -- holding the trigger), without relabelling the alias in other views.
    local scoped
    function api.with_labels(labels,fn,...)
        local previous=scoped
        scoped=labels
        local result=pack(pcall(fn,...))
        scoped=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
    mod:hook(Text,"localize_with_button_hint",function(func,action,name,context,service,...)
        local previous=label
        label=(service==nil or service=="View") and enabled() and
            (scoped and scoped[action] or direct[action] or
             ((action=="right_pressed" or action=="right_released" or action=="right_hold") and
              secondary_enabled and secondary_enabled() and "vr_menu_point_secondary") or
             (clickable and "vr_menu_point_select")) or nil
        local result=pack(pcall(func,action,name,context,service,...))
        label=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end)
    mod:hook("ViewElementInputLegend","_update_widget_text",function(func,self,entry,...)
        local previous=clickable
        clickable=entry and type(entry.on_pressed_callback)=="function"
        local result=pack(pcall(func,self,entry,...))
        clickable=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end)
    mod:hook("ViewElementInputLegend","update",function(func,self,...)
        local available=(enabled() and 1 or 0) +
            (secondary_enabled and secondary_enabled() and 2 or 0)
        if revisions[self]~=available then
            revisions[self]=available
            for _,entry in ipairs(self._entries or {}) do self:_update_widget_text(entry) end
        end
        return func(self,...)
    end)
    return api
end

return Prompts
