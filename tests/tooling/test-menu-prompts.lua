local Prompts=dofile(arg[1])
local localized=dofile(arg[2])
local hooks,active={ },true
local Text,InputUtils={ },{apply_color_to_input_text=function(text) return "<tint>"..text end}
package.loaded["scripts/utilities/ui/text"]=Text
package.loaded["scripts/managers/input/input_utils"]=InputUtils
Color={ui_input_color=function() return {} end}
local mod={localize=function(_,key) return assert(localized[key]).en end,
    hook=function(_,class,name,fn) hooks[class]=hooks[class] or {}; hooks[class][name]=fn end}
local menu=Prompts.install(mod,function() return active end)
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
