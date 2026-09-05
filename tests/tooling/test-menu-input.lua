local menu = assert(loadfile(arg[1]))()
if arg[2] then
    local count,interactive,loading,spatial=0,0,0,0
    for name in io.lines(arg[2]) do
        name=name:gsub("%s+$", "")
        local mode=menu.view_mode(name)
        count=count+1
        if name=='blank_view' or name=='scanner_display_view' then
            assert(mode==nil); spatial=spatial+1
        elseif mode==2 then loading=loading+1
        else assert(mode==5 or mode==6,'uncovered registered view: '..name)
            interactive=interactive+1 end
    end
    assert(count==72 and interactive==63 and loading==7 and spatial==2)
    print('menu_registry: 72 views covered (63 interactive, 7 loading, 2 spatial/blank)')
end
for _,name in ipairs({'inventory_view','inventory_weapons_view','inventory_weapon_details_view',
        'inventory_cosmetics_view','options_view','talent_builder_view','mastery_view'}) do
    assert(menu.native_view(name),'native menu child escaped its family: '..name)
end
assert(not menu.native_view('loading_view') and not menu.native_view('mission_intro_view'))
local function vector(x,y,z) return {x,y,z} end
local null = {get=function() return false end}
local source = {
    _actions={left_pressed={key_alias='left'}}, _aliases={left={'mouse_left'}},
    get=function(_,key) return key=='hotkey_system' or key=='right_pressed' end,
    get_default=function() return false end,
    null_service=function() return null end,
    identity=function(self) return self end,
}
local p={available=true,active=true,x=768,y=432,source_width=1536,source_height=864,
    transport_generation=1,primary_down=false,primary_pressed=false,scroll_steps=0}
local state={}
local function sample(frame,owner) return menu.sample(state,p,frame,owner or 'inventory',2496,2688) end
local s=sample(1)
assert(s.x==1248 and s.y==1344 and not s.pressed)
p.primary_down,p.primary_pressed=true,true
s=sample(2); assert(s.pressed and s.held)
local proxy=menu.proxy(source,null,s,vector)
assert(proxy:get('left_pressed') and proxy:get('left_hold'))
assert(proxy:get('cursor')[1]==1248 and proxy:get('cursor')[2]==1344)
assert(not proxy:get('right_pressed') and proxy:get('hotkey_system'))
assert(proxy:null_service()==null and proxy:identity()==source)
assert(not proxy:get_with_filters('left_pressed',{mouse_left=true}))
assert(proxy:get_with_filters('left_pressed',{}))
assert(sample(2)==s, 'update/draw/eye passes must share an immutable input frame')
p.primary_pressed=false
p.x=800
s=sample(3); assert(not s.pressed and s.held and s.dx==52 and s.dy==0)
p.active=false
s=sample(4); assert(s.held and s.x==1300 and s.y==1344 and s.dx==0,'off-panel drag jumped')
p.primary_down=false
s=sample(5); assert(s.released and not s.held)
s=sample(6); assert(not s.released and s.x==-10000)
-- New modal ownership drains the opening edge and a held trigger.
p.active,p.primary_down,p.primary_pressed=true,true,true
s=sample(7,'options'); assert(not s.pressed and not s.held)
s=sample(8,'options'); assert(not s.pressed)
p.primary_down,p.primary_pressed=false,false
sample(9,'options')
p.primary_down,p.primary_pressed=true,true
s=sample(10,'options'); assert(s.pressed)
p.available=false
s=sample(11,'options'); assert(s.released and s.override and not s.held)
s=sample(12,'options'); assert(not s.override and not s.released)
assert(menu.proxy(source,null,s,vector)==source,'desktop fallback lost')
p.available=true
s=sample(13,'options'); assert(not s.pressed,'tracking reacquisition manufactured a click')
p.primary_down,p.primary_pressed=false,false
sample(14,'options')
p.primary_down,p.primary_pressed=true,true
s=sample(15,'options'); assert(s.pressed)
p.transport_generation=2
s=sample(16,'options'); assert(not s.pressed and not s.held,'transport restart inherited press')
p.primary_down,p.primary_pressed=false,false
p.scroll_steps,p.back_pressed=2,true
s=sample(17,'options')
proxy=menu.proxy(source,null,s,vector)
assert(proxy:get('scroll_axis')[2]==2 and proxy:get('back'))
-- Stock hit testing divides the canvas cursor by its actual renderer scale.
for _,extent in ipairs({{1536,864},{1920,1080},{2496,2688}}) do
    for _,scale in ipairs({1,1.3,2.08}) do
        local q={available=true,active=true,x=extent[1]/2,y=extent[2]/2,
            source_width=extent[1],source_height=extent[2],transport_generation=1}
        local hit=menu.sample({},q,1,'menu',2496,2688)
        assert(math.abs(hit.x/scale-1248/scale)<1e-9 and math.abs(hit.y/scale-1344/scale)<1e-9)
    end
end
-- Exercise the real adapter seam, including the engine's null input service.
local hook,legacy_hook,direct_hook
local consumed={primary=0,back=0,scroll=0}
local presentation={mode=5,read_menu_pointer=function() return p end,
    consume_menu_primary=function(q) consumed.primary=consumed.primary+1; q.primary_pressed=false end,
    consume_menu_back=function(q) consumed.back=consumed.back+1; q.back_pressed=false end,
    consume_menu_scroll=function(q) consumed.scroll=consumed.scroll+1; q.scroll_steps=0 end}
menu.install({hook=function(_,class,name,fn)
    if class=='UIManager' then assert(name=='input_service'); hook=fn
    elseif class=='InputManager' then direct_hook=fn
    else legacy_hook=fn end
end},presentation)
Vector3=vector
RESOLUTION_LOOKUP={width=2496,height=2688}
p.frame_id,p.primary_down,p.primary_pressed=20,false,false
local handler={_view_handler={_active_views_array={'inventory','options'},_num_active_views=2}}
local service,blocked,gamepad=hook(function() return source,null,true end,handler)
assert(service~=source and blocked==null and gamepad==false)
assert(service:null_service():get('left_pressed')==false)
assert(hook(function() return null,null,false end,handler)==null)
assert(not presentation.read_legacy_menu_pointer().primary_pressed)
assert(consumed.back==1 and consumed.scroll==1)
p.frame_id,p.scroll_steps,p.back_pressed=21,1,true
local frame_service=hook(function() return source,null,false end,handler)
assert(frame_service:get('scroll_axis')[2]==1 and frame_service:get('back'))
assert(consumed.back==2 and consumed.scroll==2)
frame_service=hook(function() return source,null,false end,handler)
assert(frame_service:get('scroll_axis')[2]==1 and consumed.scroll==2)
p.frame_id=22
frame_service=hook(function() return source,null,false end,handler)
assert(frame_service:get('scroll_axis')[2]==0 and not frame_service:get('back'))
-- Constant-element dialogs share the manager service, but opening one drains
-- the triggering press. Closing it cannot click through into the underlying view.
handler._active_popups={{id='confirm'}}
p.frame_id,p.primary_down,p.primary_pressed=23,true,true
frame_service=hook(function() return source,null,false end,handler)
assert(not frame_service:get('left_pressed'))
Managers={ui=handler}
source.null_service=function() return null end
local direct=direct_hook(function() return source end,{},'View')
assert(direct~=source)
assert(hook(function() return direct,null,false end,handler)==direct,
    'manager wrapped an already adapted direct View service twice')
assert(direct_hook(function() return source end,{},'Ingame')==source)
p.frame_id,p.primary_down,p.primary_pressed=24,false,false
hook(function() return source,null,false end,handler)
p.frame_id,p.primary_down,p.primary_pressed=25,true,true
frame_service=hook(function() return source,null,false end,handler)
assert(frame_service:get('left_pressed'))
handler._active_popups={}
frame_service=hook(function() return source,null,false end,handler)
assert(not frame_service:get('left_pressed'))
presentation.hook_legacy_menu('FakeView','draw',function() error('legacy handler ran') end)
local a,b,c=legacy_hook(function() return 1,nil,3 end)
assert(a==1 and b==nil and c==3,'native bypass changed the stock return contract')
presentation.mode=1
assert(hook(function() return source,null,false end,handler)==source)
print('menu_input: coordinate mapping, button lifecycle, modal handoff, tracking loss, filters and null services passed')
