bit = require("bit")
local hook
local hooks={}
local mod={hook=function(_,class,method,fn)
    hooks[class..'.'..method]=fn
    if class=='HudElementSmartTagging' and method=='_handle_tagging' then hook=fn end
end}
local unit={}
local retiring=false
local api=dofile(arg[1]).install(mod,function()
    if retiring then error('player manager retired') end
    return unit
end)
local opened,blocked=0,false
local manager={using_input=function() return blocked end,
    view_active=function(_,name) assert(name=='system_view'); return false end,
    open_view=function(_,name) assert(name=='system_view'); opened=opened+1 end}
api.sample(true,1024); api.update_menu(manager); api.update_menu(manager)
assert(opened==1)
blocked=true
api.sample(true,1024); api.update_menu(manager)
blocked=false; api.update_menu(manager)
assert(opened==1,'Blocked menu request replayed later')
api.sample(false,1024); api.update_menu(manager); assert(opened==1)
local null={get=function() return false end}; null.null_service=function() return null end
local keyboard=false
local source
source={get=function(self,name)
    assert(self==source)
    return name=='smart_tag' and keyboard or (name=='unrelated' and 7 or false)
end,null_service=function() return null end}
local hud={_parent={player_unit=function() return unit end}}
local remote={_parent={player_unit=function() return {} end}}
local seen={}
local function stock(self,t,renderer,settings,input)
    seen[#seen+1]=input:get('smart_tag')
    if input~=null then assert(input:get('unrelated')==7 and input:null_service()==null) end
    return 'stock',nil,9
end
api.sample(true,256)
hook(stock,remote,1,{}, {},source)
assert(not seen[#seen],'Tag injected into another player HUD')
local a,b,c=hook(stock,hud,1,{}, {},source)
assert(a=='stock' and b==nil and c==9 and seen[#seen])
hook(stock,hud,1,{}, {},source); assert(seen[#seen],'Duplicate same-frame read lost input')
hook(stock,hud,2,{}, {},source); assert(not seen[#seen],'Tag edge became a held input')
api.sample(true,256)
hook(stock,hud,3,{}, {},null); assert(not seen[#seen])
hook(stock,hud,3,{}, {},source); assert(not seen[#seen],'Blocked edge returned within same frame')
hook(stock,hud,4,{}, {},source); assert(not seen[#seen],'Blocked tag replayed')
api.sample(true,1280) -- Opening a menu takes precedence over tagging.
hook(stock,hud,5,{}, {},source); assert(not seen[#seen])
keyboard=true
api.sample(false,0)
hook(stock,hud,6,{}, {},source); assert(seen[#seen],'Keyboard tag was suppressed')
keyboard=false
api.sample(true,256)
local ok=pcall(hook,function() error('stock failure') end,hud,7,{}, {},source)
assert(not ok and source:get('smart_tag')==false,'Stock error mutated original input')
local retained_tag
api.sample(true,256)
hook(function(self,t,renderer,settings,input)
    retained_tag=input
    assert(input:get('smart_tag'))
end,hud,7.1,{}, {},source)
assert(not retained_tag:get('smart_tag'),'Retained tag proxy outlived HUD handler')
api.sample(true,256)
hook(function(self,t,renderer,settings,input)
    assert(not retained_tag:get('smart_tag'),'Old tag proxy revived in a later handler')
    assert(input:get('smart_tag'))
    hook(function()
        assert(not input:get('smart_tag'),'Nested remote HUD inherited tag injection')
    end,remote,7.2,{}, {},source)
    assert(input:get('smart_tag'),'Nested HUD did not restore outer tag scope')
    api.sample(true,256)
    assert(not input:get('smart_tag'),'Tag proxy borrowed a newer input sample')
end,hud,7.2,{}, {},source)
keyboard=true
assert(retained_tag:get('smart_tag'),'Expired tag proxy suppressed keyboard input')
keyboard=false
api.sample(true,256)
assert(not pcall(hook,function(self,t,renderer,settings,input)
    retained_tag=input
    error('tag handler failed')
end,hud,7.3,{}, {},source))
assert(not retained_tag:get('smart_tag'),'Failed tag handler left its proxy active')
api.sample(true,256)
hook(function(self,t,renderer,settings,input)
    unit={}
    assert(not input:get('smart_tag'),'Active tag proxy crossed player replacement')
end,hud,7.4,{}, {},source)
api.sample(true,256)
local predicate_tag_null={get=function()return false end,is_null_service=function()return true end}
hook(function(self,t,renderer,settings,input)
    assert(input==predicate_tag_null and not input:get('smart_tag'))
end,hud,7.5,{}, {},predicate_tag_null)
print('gameplay_ui_input=pass menu=semantic tag=stock_input inherited_edges=not_replayed')

local inventory_hook=assert(hooks['UIManager._update_view_hotkeys'])
assert(not hooks['UIManager.input_service'],'Duplicate menu input hook')
local function service_hook(func,self,service,...)
    return api.route_hotkey_input(func(self,service,...),self,service)
end
local ui={}
local inventory_keyboard=false
local inventory_source={get=function(_,name)
    return name=='hotkey_inventory' and inventory_keyboard or false
end,null_service=function() return null end}
local function get_source() return inventory_source end
local function stock_hotkeys(self)
    local input=service_hook(get_source,self)
    assert(input:null_service()==null)
    return input:get('hotkey_inventory'),nil,23
end
api.sample(true,32768)
local requested,empty,last=inventory_hook(stock_hotkeys,ui)
assert(requested and empty==nil and last==23)
assert(not inventory_hook(stock_hotkeys,ui),'Inventory request replayed')
api.sample(true,32768)
inventory_hook(function() end,ui) -- Stock modal/transition early return.
assert(not inventory_hook(stock_hotkeys,ui),'Blocked inventory replayed')
api.sample(true,32768)
inventory_hook(function(self)
    assert(service_hook(function() return null end,self)==null,'Null service bypassed')
    assert(not service_hook(get_source,{},'View'):get('hotkey_inventory'),'Wrong manager')
    assert(not service_hook(get_source,self,'Ingame'):get('hotkey_inventory'),'Wrong service')
end,ui)
api.sample(true,32768)
assert(not pcall(inventory_hook,function() error('stock failure') end,ui))
assert(not service_hook(get_source,ui):get('hotkey_inventory'),'Scope leaked after error')
inventory_keyboard=true
api.sample(false,0)
assert(inventory_hook(stock_hotkeys,ui),'Keyboard inventory suppressed')
inventory_keyboard=false
api.sample(true,32768+1024)
assert(not inventory_hook(stock_hotkeys,ui),'Inventory competed with menu')
local retained_inventory
api.sample(true,32768)
inventory_hook(function(self)
    retained_inventory=service_hook(get_source,self)
    assert(retained_inventory:get('hotkey_inventory'))
end,ui)
assert(not retained_inventory:get('hotkey_inventory'),'Retained inventory proxy outlived stock scope')
api.sample(true,32768)
inventory_hook(function(self)
    assert(not retained_inventory:get('hotkey_inventory'),'Old proxy revived in a new inventory scope')
    local fresh=service_hook(get_source,self)
    assert(fresh:get('hotkey_inventory'))
    api.sample(true,32768)
    assert(not fresh:get('hotkey_inventory'),'Proxy borrowed a new active input sample')
    api.sample(false,0)
    assert(not fresh:get('hotkey_inventory'),'Proxy ignored routing loss inside the stock handler')
end,ui)
api.sample(true,32768)
assert(not pcall(inventory_hook,function(self)
    retained_inventory=service_hook(get_source,self)
    error('stock failure with retained proxy')
end,ui))
assert(not retained_inventory:get('hotkey_inventory'),'Failed stock scope left an active proxy')
api.sample(true,32768)
inventory_hook(function(self)
    local input=service_hook(get_source,self)
    unit={}
    assert(not input:get('hotkey_inventory'),'Proxy crossed a player replacement inside the handler')
end,ui)
inventory_keyboard=true
assert(retained_inventory:get('hotkey_inventory'),'Expired proxy suppressed independent keyboard input')
inventory_keyboard=false
api.sample(true,32768)
inventory_hook(function(self)
    local predicate_null={get=function()return false end,is_null_service=function()return true end}
    assert(api.route_hotkey_input(predicate_null,self,'View')==predicate_null,
        'Null service predicate bypassed')
end,ui)
print('inventory_hotkey=pass stock_gates=preserved no_replay=true')

-- UI requests belong to the player present when input was sampled. The HUD
-- object may survive a respawn, including a duplicate read at the same time.
api.sample(true,256)
hook(stock,hud,8,{}, {},source); assert(seen[#seen])
unit={}
hook(stock,hud,8,{}, {},source)
assert(not seen[#seen],'Cached tag crossed a player replacement')
api.sample(true,256)
unit={}
hook(stock,hud,9,{}, {},source)
assert(not seen[#seen],'Pending tag crossed a player replacement')
api.sample(true,1024)
unit={}
api.update_menu(manager)
assert(opened==1,'Pending menu crossed a player replacement')
api.sample(true,32768)
unit={}
assert(not inventory_hook(stock_hotkeys,ui),'Pending inventory crossed a player replacement')
api.sample(true,256)
retiring=true
assert(pcall(hook,stock,hud,10,{}, {},source),'Retiring owner lookup escaped tag adapter')
assert(not seen[#seen])
retiring=false
hook(stock,hud,10,{}, {},source)
assert(not seen[#seen],'Retired tag returned on manager recovery')
api.sample(true,32768)
retiring=true
assert(not inventory_hook(stock_hotkeys,ui),'Retiring owner admitted inventory')
retiring=false
assert(not inventory_hook(stock_hotkeys,ui),'Retired inventory replayed')
api.sample(true,1024)
retiring=true
assert(pcall(api.update_menu,manager),'Retiring owner escaped menu adapter')
retiring=false
api.update_menu(manager)
assert(opened==1,'Retired menu replayed')
retiring=true
assert(pcall(api.sample,true,256),'Retiring owner escaped sample')
retiring=false
hook(stock,hud,11,{}, {},source)
assert(not seen[#seen],'Request without a sample owner replayed')
api.sample(true,256)
hook(stock,hud,12,{}, {},source); assert(seen[#seen],'Fresh owner could not tag')
local old_owner=unit
unit={}
hook(stock,remote,12,{}, {},source)
unit=old_owner
hook(stock,hud,12,{}, {},source)
assert(not seen[#seen],'A cached HUD revived a cancelled request when the old owner returned')
print('ui_request_ownership=pass replacement=cancelled retiring_lookup=cancelled fresh_request=accepted')

local tactical=assert(hooks['HudElementTacticalOverlay.update'])
assert(not hooks['InputManager.get_input_service'], 'Tactical input duplicated the central service hook')
local keyboard_overlay=false
local overlay_source={get=function(_,name)
    return name=='tactical_overlay_hold' and keyboard_overlay or (name=='unrelated' and 13 or false)
end,is_null_service=function()return false end,null_service=function()return null end}
local retained_proxy
local function overlay_stock(self)
    local routed=api.route_ingame_input(overlay_source,'Ingame')
    retained_proxy=routed
    assert(routed:get('unrelated')==13 and routed:null_service()==null and not routed:is_null_service())
    assert(api.route_ingame_input(overlay_source,'View')==overlay_source)
    assert(api.route_ingame_input(null,'Ingame')==null)
    return routed:get('tactical_overlay_hold'),nil,27
end
api.sample(true,0,2097152)
assert(api.route_ingame_input(overlay_source,'Ingame')==overlay_source, 'Hold leaked outside HUD update')
local held,empty,value=tactical(overlay_stock,hud)
assert(held and empty==nil and value==27)
assert(not retained_proxy:get('tactical_overlay_hold'), 'Retained proxy injected outside its scope')
local old_tactical_proxy=retained_proxy
tactical(function(self)
    assert(not old_tactical_proxy:get('tactical_overlay_hold'),'Old overlay proxy revived in a later HUD scope')
    local input=api.route_ingame_input(overlay_source,'Ingame')
    assert(input:get('tactical_overlay_hold'))
    api.sample(true,0,2097152)
    assert(not input:get('tactical_overlay_hold'),'Overlay proxy borrowed a newer input sample')
end,hud)
assert(not tactical(overlay_stock,remote), 'Another player HUD received hold')
tactical(function(self)
    assert(api.route_ingame_input(overlay_source,'Ingame'):get('tactical_overlay_hold'))
    assert(not tactical(overlay_stock,remote), 'Nested remote HUD inherited local scope')
    assert(api.route_ingame_input(overlay_source,'Ingame'):get('tactical_overlay_hold'))
end,hud)
assert(not pcall(tactical,function()error('overlay update failed')end,hud))
assert(api.route_ingame_input(overlay_source,'Ingame')==overlay_source, 'Failed update leaked scope')
api.sample(true,0,0);assert(not tactical(overlay_stock,hud), 'Released overlay remained held')
api.sample(true,1024,2097152);assert(not tactical(overlay_stock,hud), 'Menu did not take precedence')
api.sample(false,0,2097152);assert(not tactical(overlay_stock,hud), 'Inactive input remained held')
keyboard_overlay=true;assert(tactical(overlay_stock,hud), 'Keyboard overlay was suppressed')
keyboard_overlay=false
api.sample(true,0,2097152)
local original_unit=unit;unit={}
assert(not tactical(overlay_stock,hud), 'Hold crossed player replacement')
unit=original_unit
assert(not tactical(overlay_stock,hud), 'Returning player revived old hold')
api.sample(true,0,2097152);retiring=true
assert(not tactical(overlay_stock,hud), 'Retiring manager admitted hold')
retiring=false
assert(not tactical(overlay_stock,hud), 'Manager recovery revived old hold')
print('tactical_overlay_input=pass scoped_hold release null owner nested_restore keyboard no_duplicate_hook')

if arg[2] then
    local path=arg[2]..'/scripts/ui/hud/elements/tactical_overlay/hud_element_tactical_overlay.lua'
    local file=assert(io.open(path,'r'));local source_text=file:read('*a');file:close()
    local first=assert(source_text:find('HudElementTacticalOverlay.update =',1,true))
    local last=assert(source_text:find('\nHudElementTacticalOverlay._update_left_panel_elements =',first,true))
    local stock_class={super={update=function()end}}
    local changes={}
    local blocked_overlay=false
    null.is_null_service=function()return true end
    local env=setmetatable({HudElementTacticalOverlay=stock_class,InputDevice={gamepad_active=false},
        Managers={ui={using_input=function(_,ignore_hud)assert(ignore_hud);return blocked_overlay end},
            input={get_input_service=function(_,name)return api.route_ingame_input(overlay_source,name)end},
            event={trigger=function(_,name,active)assert(name=='event_set_tactical_overlay_state');changes[#changes+1]=active end},
            telemetry_reporters={reporter=function()return {register_event=function()end}end}}}, {__index=_G})
    setfenv(assert(loadstring(source_text:sub(first,last-1),'@'..path)),env)()
    local actual={_parent=hud._parent,_active=false,_gamepad_active=false,_game_mode_name='hub'}
    for _,name in ipairs({'_update_contracts','_update_achievements','_update_live_event',
        '_update_right_panel_widgets','_sync_mission_info','_sync_circumstance_info',
        '_update_left_panel_elements','_start_animation','_update_materials_collected',
        '_update_right_timer_text','_buffs_navigation','_update_visibility'}) do actual[name]=function()end end
    api.sample(true,0,2097152)
    tactical(stock_class.update,actual,0.016,1,{}, {},overlay_source)
    assert(actual._active and #changes==1 and changes[1]==true)
    tactical(stock_class.update,actual,0.016,2,{}, {},overlay_source)
    assert(actual._active and #changes==1, 'Holding repeated the stock activation')
    api.sample(true,0,0)
    tactical(stock_class.update,actual,0.016,3,{}, {},overlay_source)
    assert(not actual._active and #changes==2 and changes[2]==false)
    api.sample(true,0,2097152);blocked_overlay=true
    tactical(stock_class.update,actual,0.016,4,{}, {},overlay_source)
    assert(not actual._active and #changes==2, 'Stock menu gate was bypassed')
    print('tactical_overlay_stock=pass actual_update hold release no_repeated_activation menu_gate')
end
