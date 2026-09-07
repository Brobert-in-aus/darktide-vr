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
