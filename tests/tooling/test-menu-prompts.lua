local Prompts=dofile(arg[1])
local localized=dofile(arg[2])
local hooks,active={ },true
local Text,InputUtils={ },{apply_color_to_input_text=function(text) return "<tint>"..text end}
package.loaded["scripts/utilities/ui/text"]=Text
package.loaded["scripts/managers/input/input_utils"]=InputUtils
Color={ui_input_color=function() return {} end}
local mod={localize=function(_,key) return assert(localized[key]).en end,
    hook=function(_,class,name,fn) hooks[class]=hooks[class] or {}; hooks[class][name]=fn end}
local secondary=false
local menu=Prompts.install(mod,function() return active end,function() return secondary end)
local function stock_input(service,alias) return "keyboard:"..tostring(alias),nil,service end
local function input(service,alias,tint)
    return menu.input_text(service,alias,tint) or stock_input(service,alias,tint)
end
local function stock_hint(action,name,context,service,tint)
    local text=input(service or "View",action,tint)
    return text.." "..name,nil,9
end
local function hint(action,service,tint)
    return hooks[Text].localize_with_button_hint(stock_hint,action,"Action",nil,service,tint)
end
assert(hint("back")=="[B / Menu] Action")
for _,action in ipairs({"left_pressed","left_released","left_hold"}) do
    assert(hint(action)=="[Point + RT] Action")
end
assert(hint("back","View",true)=="<tint>[B / Menu] Action")
assert(hint("confirm_pressed")=="keyboard:confirm_pressed Action")
assert(hint("gamepad_confirm_pressed")=="keyboard:gamepad_confirm_pressed Action")
assert(hint("right_pressed")=="keyboard:right_pressed Action")
secondary=true
for _,action in ipairs({"right_pressed","right_released","right_hold"}) do
    assert(hint(action)=="[Point + LT] Action")
end
assert(hint("right_pressed","Ingame")=="keyboard:right_pressed Action")
secondary=false
assert(hint("right_pressed")=="keyboard:right_pressed Action","old transport advertised secondary")
assert(hint("back_released")=="keyboard:back_released Action")
assert(hint("back","Ingame")=="keyboard:back Action")
assert(input("View","back")=="keyboard:back","label leaked outside a known action")
local a,b,c=hint("back"); assert(a=="[B / Menu] Action" and b==nil and c==9)
local legend=hooks.ViewElementInputLegend
local function widget(self,entry)
    entry.widget.content.text=hint(entry.input_action)
    entry.recalcultate_text_width=true
end
local entry={input_action="confirm_pressed",widget={content={}},on_pressed_callback=function() end}
legend._update_widget_text(widget,{},entry)
assert(entry.widget.content.text=="[Point + RT] Action" and entry.recalcultate_text_width)
assert(hint("confirm_pressed")=="keyboard:confirm_pressed Action","click scope leaked")
local readonly={input_action="confirm_pressed",widget={content={}}}
legend._update_widget_text(widget,{},readonly)
assert(readonly.widget.content.text=="keyboard:confirm_pressed Action")
local ok=pcall(legend._update_widget_text,function() error("stock legend") end,{},entry)
assert(not ok and hint("confirm_pressed")=="keyboard:confirm_pressed Action")
ok=pcall(hooks[Text].localize_with_button_hint,function() error("stock text") end,"back","Back")
assert(not ok and input("View","back")=="keyboard:back")
local refresh=0
local owner={_entries={entry},_update_widget_text=function(self,item)
    refresh=refresh+1; legend._update_widget_text(widget,self,item)
end}
local function update(self) return 1,nil,3 end
local a,b,c=legend.update(update,owner)
assert(a==1 and b==nil and c==3 and refresh==1)
legend.update(update,owner); assert(refresh==1)
active=false
legend.update(update,owner); assert(refresh==2 and entry.widget.content.text=="keyboard:confirm_pressed Action")
assert(hint("back")=="keyboard:back Action")
assert(not legend._handle_input,"prompt feature changed interaction routing")
print("menu_prompts=pass exact_routes clickable_legends scopes stock_fallback caches")

-- Optional third argument loads the inspected stock formatter/legend methods.
-- Localization and device aliases are isolated; this is not rendered UI QA.
if arg[3] then
    local function stock_method(path,first_marker,last_marker,environment)
        local file=assert(io.open(arg[3]..'/scripts/'..path..'.lua','r'))
        local source=file:read('*all'); file:close()
        local first=assert(source:find(first_marker,1,true))
        local last=assert(source:find(last_marker,first,true))
        local chunk=assert(loadstring(source:sub(first,last-1),'@'..path))
        setfenv(chunk,setmetatable(environment,{__index=_G})); chunk()
    end
    active,secondary=true,true
    InputUtils.input_text_for_current_input_device=input
    local function localize(key,has_context,context)
        if key=='loc_input_hold' then return 'Hold' end
        if key=='loc_input_release' then return 'Release' end
        if key=='loc_input_legend_text_template' then return '%s: %s' end
        assert(has_context==(context~=nil))
        return key..(context and ' '..context.target or '')
    end
    local ui={get_input_alias_key=function(_,action,service)
        assert(service=='View' or service=='Ingame')
        return 'stock_alias_'..action
    end,get_action_type=function(_,action)
        if action:match('_hold$') then return 'held' end
        if action:match('_released$') then return 'released' end
        return 'pressed'
    end}
    stock_method('utilities/ui/text','TextUtilities.localize_with_button_hint =',
        '\nTextUtilities.add_button_hint =',
        {TextUtilities=Text,InputUtils=InputUtils,Managers={ui=ui},Localize=localize})
    local format=Text.localize_with_button_hint
    Text.localize_with_button_hint=function(...) return hooks[Text].localize_with_button_hint(format,...) end
    assert(Text.localize_with_button_hint('left_hold','Operate',{target='device'},nil,'%s / %s',true,true)==
        'Hold <tint>[Point + RT] / Operate device')
    assert(Text.localize_with_button_hint('right_released','Remove',nil,'View',nil,true)==
        'Release [Point + LT] Remove')
    assert(Text.localize_with_button_hint('back','Back')=='[B / Menu] Back')
    assert(Text.localize_with_button_hint('confirm_pressed','Confirm')==
        'keyboard:stock_alias_confirm_pressed Confirm')
    assert(Text.localize_with_button_hint('left_hold','Attack',nil,'Ingame',nil,true)==
        'Hold keyboard:stock_alias_left_hold Attack')
    secondary=false
    assert(Text.localize_with_button_hint('right_pressed','Remove')==
        'keyboard:stock_alias_right_pressed Remove')
    secondary=true
    local stock_legend={}
    stock_method('ui/view_elements/view_element_input_legend/view_element_input_legend',
        'ViewElementInputLegend._update_widget_text =',
        '\nViewElementInputLegend._draw_widgets =',
        {ViewElementInputLegend=stock_legend,Text=Text,
         DefaultViewInputSettings={service_type='View'},Localize=localize})
    local entry={input_action='confirm_pressed',display_name='Continue',suffix=' (3)',
        widget={content={}},on_pressed_callback=function() error('Hint formatting activated a button') end}
    legend._update_widget_text(stock_legend._update_widget_text,{},entry)
    assert(entry.widget.content.text=='[Point + RT]: Continue (3)' and entry.recalcultate_text_width)
    entry.on_pressed_callback=nil
    legend._update_widget_text(stock_legend._update_widget_text,{},entry)
    assert(entry.widget.content.text=='keyboard:stock_alias_confirm_pressed: Continue (3)')
    entry.input_action='right_released'
    legend._update_widget_text(stock_legend._update_widget_text,{},entry)
    assert(entry.widget.content.text=='Release [Point + LT]: Continue (3)')
    active=false
    legend._update_widget_text(stock_legend._update_widget_text,{},entry)
    assert(entry.widget.content.text=='Release keyboard:stock_alias_right_released: Continue (3)')
    print('PASS: stock shared formatter/legend preserve aliases, hold/release, context, tint, patterns, suffixes and callback ownership')
    print('LIMIT: isolated localization/device text; no live label, sizing or talent acceptance')
end
