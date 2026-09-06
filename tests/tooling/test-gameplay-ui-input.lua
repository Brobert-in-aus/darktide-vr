bit = require("bit")
local hook
local mod={hook=function(_,class,method,fn)
    assert(class=='HudElementSmartTagging' and method=='_handle_tagging'); hook=fn
end}
local unit={}
local api=dofile(arg[1]).install(mod,function() return unit end)
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
