local Prompts = {}
function Prompts.single_line(text)
    -- Keep each complete binding together in stock rich-text/word wrapping.
    return (text:gsub('%s','\194\160'))
end
local aliases = {
    action_one="primary",action_two="alternate",weapon_extra="special",
    interact="interact",weapon_reload="reload",quick_wield="quick_wield",
    jump="jump",dodge="dodge",crouch="crouch",sprint="sprint",
    smart_tag="tag",grenade_ability="blitz",combat_ability="combat_ability",
    weapon_inspect="inspect",menu="menu",
    wield_1=false,wield_2=false,wield_3="pocketable",wield_3_gamepad="cycle_pocketables",
    wield_4="stim",wield_5="device",interact_inspect="inspect_target",com_wheel="communication_wheel",
    tactical_overlay="tactical_overlay",
    voip_push_to_talk="push_to_talk",
}
local scopes = {
    {"HudElementPlayerWeapon","_update_input",true},
    {"HudElementPlayerAbility","_update_input"},
    {"HudElementPlayerSlotItemAbility","_update_input"},
    {"HudElementWieldInfo","_create_entry"},
    {"HudElementInteraction","_update_tag_input_information"},
    {"HudElementInteraction","_update_interaction_input_text"},
    {"HudElementInteraction","_setup_interaction_information"},
    {"HudElementSmartTagging","_update_tag_interaction_information"},
    {"ConstantElementOnboardingHandler","_sync_onboarding_settings"},
    {"HudElementPrologueTutorialInfoBox","_get_input_description_text"},
    {"HudElementTacticalOverlay","_update_right_hint"},
    {"HudElementSpectatorText","_get_cycle_input_text"},
}

function Prompts.install(mod, bindings, enabled, menu_prompts)
    local InputUtils = require("scripts/managers/input/input_utils")
    local UIRenderer = require("scripts/managers/ui/ui_renderer")
    local depth, weapon_switch = 0, false
    local revisions = setmetatable({}, {__mode="k"})
    local fitted = setmetatable({}, {__mode="k"})
    local function fit_ability_label(self,renderer)
        local widget=self._widgets_by_name and self._widgets_by_name.ability
        local style=widget and widget.style.input_text
        if not style or not style.size or not renderer or not renderer.scale then return end
        local text=widget.content.input_text or ""
        local previous=fitted[style]
        if not previous then
            previous={font=style.font_size}; fitted[style]=previous
        end
        local available=enabled()
        local width=math.max(1,style.size[1]-2)
        if previous.text==text and previous.scale==renderer.scale and
                previous.width==width and previous.available==available and
                previous.applied==style.font_size then return end
        style.font_size=available and UIRenderer.scaled_font_size_by_width(
            renderer,text,style.font_type,previous.font,width) or previous.font
        previous.text,previous.scale,previous.width,previous.available=text,renderer.scale,width,available
        previous.applied=style.font_size
        widget.dirty=true
    end
    -- Forward results on the Lua stack, including trailing nils, instead of
    -- allocating a result table for every HUD update and protected scope.
    local function finish_scope(previous_switch,ok,...)
        depth=depth-1; weapon_switch=previous_switch
        if not ok then error((...),0) end
        return ...
    end
    local function finish_update(self,renderer,...)
        fit_ability_label(self,renderer)
        return ...
    end
    mod:hook(InputUtils,"input_text_for_current_input_device",
        function(func,service,alias,tint)
            if menu_prompts then
                local menu_text=menu_prompts.input_text(service,alias,tint)
                if menu_text then return menu_text end
            end
            local action = aliases[alias]
            local inventory=service=="View" and alias=="hotkey_inventory" and bindings.context=="hub"
            if inventory then action="inventory" end
            if depth==0 or not enabled() or (service~="Ingame" and not inventory) or action==nil then
                return func(service,alias,tint)
            end
            local switch = weapon_switch and (alias=="wield_1" or alias=="wield_2")
            if switch then action="quick_wield" end
            local controls = bindings.controls_for_action(action)
            -- A hub hotkey without a controller assignment remains an accurate
            -- keyboard hint. Never advertise an unavailable inventory shortcut.
            if inventory and not controls[1] then return func(service,alias,tint) end
            local labels = {}
            -- One valid binding keeps compact HUD badges readable. All aliases
            -- remain usable and are listed individually in the options.
            if controls[1] then labels[1]=mod:localize("vr_prompt_"..controls[1]) end
            local text = #labels>0 and table.concat(labels," / ") or mod:localize("vr_action_unbound")
            -- The weapon-switch badge shows only the control ("[RS Down]"); the
            -- action is clear from where the badge sits.
            text=Prompts.single_line("["..text.."]")
            if tint then text=InputUtils.apply_color_to_input_text(text,Color.ui_input_color(255,true)) end
            return text
        end)
    for _,scope in ipairs(scopes) do
        local switching=scope[3] or false
        mod:hook(scope[1],scope[2],function(func,...)
            local previous_switch=weapon_switch
            depth=depth+1; weapon_switch=switching
            return finish_scope(previous_switch,pcall(func,...))
        end)
    end
    -- Localised strings carry input glyphs through the $INGAME_INPUT:...$
    -- macro (prologue popups, objective and area text). Expand it inside the
    -- scope so those read the controller too, and drop the localisation
    -- string cache whenever the mapping or VR availability changes, since it
    -- keeps an expanded glyph for the session.
    local has_macros,localization_macros=pcall(require,"scripts/managers/localization/localization_macros")
    local cache_revision
    local function refresh_localization_cache()
        local current=bindings.revision*2+(enabled() and 1 or 0)
        if cache_revision==current then return end
        cache_revision=current
        local localization=Managers and Managers.localization
        if localization and localization.reset_cache then pcall(localization.reset_cache,localization) end
    end
    if has_macros and type(localization_macros)=="table" and localization_macros.INGAME_INPUT then
        mod:hook(localization_macros,"INGAME_INPUT",function(func,...)
            refresh_localization_cache()
            local previous_switch=weapon_switch
            depth=depth+1; weapon_switch=false
            return finish_scope(previous_switch,pcall(func,...))
        end)
    end
    -- Stock prologue caching watches keyboard keys and device selection, which
    -- do not change when a VR control is remapped or tracking becomes unavailable.
    mod:hook("HudElementPrologueTutorialInfoBox","_should_update_input",function(func,self,info)
        local stock=func(self,info)
        if not info or not info.input_descriptions then return stock end
        local current=bindings.revision*2+(enabled() and 1 or 0)
        local changed=revisions[self]~=current
        revisions[self]=current
        return stock or changed
    end)
    -- These elements cache text across frames. Refresh just their input text
    -- when mappings or VR availability change, without forcing global input mode.
    for _,class in ipairs({"HudElementPlayerWeapon","HudElementPlayerAbility",
            "HudElementPlayerSlotItemAbility","HudElementWieldInfo"}) do
        local wield=class=="HudElementWieldInfo"
        mod:hook(class,"update",function(func,self,dt,t,renderer,...)
            refresh_localization_cache()
            local current=bindings.revision*2+(enabled() and 1 or 0)
            if revisions[self]~=current then
                revisions[self]=current
                if wield then self:_reset_current_info() else self:_update_input() end
            end
            return finish_update(self,renderer,func(self,dt,t,renderer,...))
        end)
    end
end

return Prompts
