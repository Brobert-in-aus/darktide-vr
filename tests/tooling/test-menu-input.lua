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
assert(proxy:get('right_pressed') and proxy:get('hotkey_system'))
assert(proxy:null_service()==null and proxy:identity()==source)
assert(not proxy:get_with_filters('left_pressed',{mouse_left=true}))
assert(proxy:get_with_filters('left_pressed',{}))
local desktop_values={left_pressed=true,left_released=true,left_hold=true,
    right_pressed=true,middle_hold=true,confirm_pressed=true,scroll_axis=vector(2,3,0)}
local desktop_source={get=function(_,key) return desktop_values[key] end}
local combined=menu.proxy(desktop_source,null,{override=true,scroll=2},vector)
for _,key in ipairs({'left_pressed','left_released','left_hold','right_pressed',
        'middle_hold','confirm_pressed'}) do assert(combined:get(key),key..' suppressed') end
assert(combined:get('scroll_axis')[1]==2 and combined:get('scroll_axis')[2]==5,
    'mouse wheel must combine with VR scrolling')
-- A desktop wheel event must use the desktop's physical cursor, even while a
-- stationary controller ray hits a different part of the menu.
local wheel_reads=0
local function desktop_cursor()
    wheel_reads=wheel_reads+1
    return 100,200,1000,500,true
end
local wheel_sample={override=true,x=900,y=800,scroll=0}
local wheel_proxy=menu.proxy(desktop_source,null,wheel_sample,vector,desktop_cursor,2000,1000)
assert(wheel_proxy:get('cursor')[1]==200 and wheel_proxy:get('cursor')[2]==400,
    'Desktop wheel used the controller cursor')
local repeated_wheel=menu.proxy(desktop_source,null,wheel_sample,vector,
    function() error('Resampled a cursor within the same UI frame') end,2000,1000)
assert(repeated_wheel:get('cursor')[1]==200 and wheel_reads==1)
assert(repeated_wheel:get('scroll_axis')[2]==3,'Desktop wheel magnitude changed')
for _,gesture in ipairs({'held','released','pressed','secondary_held','secondary_released','secondary_pressed','scroll'}) do
    local sample={override=true,x=900,y=800,scroll=0}; sample[gesture]=gesture=='scroll' and 1 or true
    local routed=menu.proxy(desktop_source,null,sample,vector,desktop_cursor,2000,1000)
    assert(routed:get('cursor')[1]==900 and wheel_reads==1,'Desktop wheel moved an XR gesture')
end
for _,read in ipairs({
    function() error('retired window') end,
    function() return 100,200,1000,500,false end,
    function() return -1,200,1000,500,true end,
    function() return 1000,200,1000,500,true end,
    function() return 100,500,1000,500,true end,
    function() return 100,200,0,500,true end,
    function() return 0/0,200,1000,500,true end,
}) do
    local routed=menu.proxy(desktop_source,null,{override=true,x=900,y=800,scroll=0},vector,read,2000,1000)
    assert(routed:get('cursor')[1]==900,'Invalid desktop point replaced XR input')
end
local idle_desktop={get=function() return vector(0,0,0) end}
local idle=menu.proxy(idle_desktop,null,{override=true,x=900,y=800,scroll=0},vector,
    function() error('Idle mouse requested a desktop point') end,2000,1000)
assert(idle:get('cursor')[1]==900,'Previous wheel event retained cursor ownership')
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
local hook,legacy_hook,direct_hook,readiness_hook
local readiness_logs=0
local consumed={primary=0,secondary=0,back=0,scroll=0}
local presentation={mode=5,read_menu_pointer=function() return p end,
    consume_menu_primary=function(q) consumed.primary=consumed.primary+1; q.primary_pressed=false end,
    consume_menu_secondary=function(q) consumed.secondary=consumed.secondary+1; q.secondary_pressed=false end,
    consume_menu_back=function(q) consumed.back=consumed.back+1; q.back_pressed=false end,
    consume_menu_scroll=function(q) consumed.scroll=consumed.scroll+1; q.scroll_steps=0 end}
menu.install({hook_safe=function(_,class,name,fn)
    assert(class=='MainMenuView' and name=='update'); readiness_hook=fn
end, info=function(_,format)
    if format:find('DARKTIDEVR_MENU_READINESS',1,true) then readiness_logs=readiness_logs+1 end
end, hook=function(_,class,name,fn)
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
-- Desktop editor output shares mode 5, but must retain native mouse buttons
-- and wheel through both service entry points. Actual menus still use XR.
presentation.mode=5
presentation.hud_panel={editing=function() return true end}
handler._view_handler._num_active_views=0
assert(hook(function() return source,null,true end,handler)==source)
assert(direct_hook(function() return source end,{},'View')==source)
assert(hook(function() return null,null,false end,handler)==null)
handler._active_popups={{id='editor_modal'}}
assert(hook(function() return source,null,false end,handler)~=source)
handler._active_popups={}
handler._view_handler._num_active_views=2
assert(hook(function() return source,null,false end,handler)~=source)
presentation.hud_panel=nil
presentation.mode=1
-- The gameplay hotkey layer must share this exact service hook, retain all
-- three return values and leave modal/null/keyboard semantics untouched.
bit=require('bit')
local gameplay_hooks={}
local gameplay_owner={}
presentation.gameplay_ui=dofile(arg[1]:gsub('darktidevr_menu_input.lua$',
    'darktidevr_gameplay_ui_input.lua')).install({hook=function(_,class,name,fn)
    assert(not (class=='UIManager' and name=='input_service'),'Duplicate shared service hook')
    gameplay_hooks[class..'.'..name]=fn
end},function() return gameplay_owner end)
local hotkey=gameplay_hooks['UIManager._update_view_hotkeys']
presentation.gameplay_ui.sample(true,32768)
hotkey(function(self)
    local routed,empty,pad=hook(function() return source,null,true end,self)
    assert(routed:get('hotkey_inventory') and empty==null and pad==true)
    assert(hook(function() return null,null,true end,self)==null)
end,handler)
assert(hook(function() return source,null,true end,handler)==source,'Hotkey scope leaked')
presentation.gameplay_ui=nil
print('menu_input: coordinate mapping, button lifecycle, modal handoff, tracking loss, filters and null services passed')
local view = {_widgets_by_name={play_button={content={visible=true,hotspot={disabled=false}}}}}
local list_ready,start_ready,reason=menu.character_select_readiness(view,false)
assert(list_ready and start_ready and reason=='ready')
list_ready,start_ready,reason=menu.character_select_readiness(view,true)
assert(not list_ready and not start_ready and reason=='stock_null_service')
view._waiting_on_character=true
view._widgets_by_name.play_button.content.hotspot.disabled=true
list_ready,start_ready,reason=menu.character_select_readiness(view,false)
assert(list_ready and not start_ready and reason=='character_sync')
view._profiles_wait_overlay_active=true
list_ready,start_ready,reason=menu.character_select_readiness(view,false)
assert(not list_ready and not start_ready and reason=='profiles_sync')
print('character_select_readiness: stock input and Start gates remain separate')
null.null_service=function(self) return self end
readiness_hook(view,0.01,0,null)
readiness_hook(view,0.01,0.01,null)
assert(readiness_logs==1,'repeated readiness state spammed logs')
view._profiles_wait_overlay_active=false
for i=1,30 do
    view._waiting_on_character=i%2==0
    readiness_hook(view,0.01,i/10,source)
end
assert(readiness_logs==16,'readiness log budget was not enforced')
local late_view={}
readiness_hook(late_view,0.01,0,source)
local count=readiness_logs
late_view._profiles_wait_overlay_active=true
readiness_hook(late_view,0.01,11,source)
assert(readiness_logs==count,'late readiness updates escaped the startup window')
local starts=0
local startup={armed=true}
local ready_view={_widgets_by_name={play_button={content={visible=true,hotspot={
    disabled=false,pressed_callback=function() starts=starts+1 end}}}}}
assert(not menu.advance_startup(startup,ready_view,true,0))
assert(not menu.advance_startup(startup,ready_view,false,1))
ready_view._is_main_menu_open=true
assert(not menu.advance_startup(startup,ready_view,false,2))
ready_view._is_main_menu_open=false
assert(not menu.advance_startup(startup,ready_view,false,3))
assert(menu.advance_startup(startup,ready_view,false,4))
assert(starts==1)
assert(not menu.advance_startup(startup,ready_view,false,5))
assert(not menu.advance_startup({},ready_view,false,6))
local replaced={armed=true}
assert(not menu.advance_startup(replaced,ready_view,false,0))
assert(not menu.advance_startup(replaced,{},false,2))
assert(replaced.done and starts==1)
print('startup_start: explicit arm, stock gates, settling, once-only and view ownership passed')

-- Secondary supports a pointed right click in any native menu. It is
-- independent of primary and cannot survive ownership or transport changes.
local secondary_state={}
local secondary_pointer={available=true,active=true,x=100,y=200,
    source_width=1000,source_height=1000,transport_generation=1,secondary_down=false}
local function secondary_sample(frame,owner)
    return menu.sample(secondary_state,secondary_pointer,frame,owner or 'menu',1000,1000)
end
secondary_sample(1)
secondary_pointer.secondary_down,secondary_pointer.secondary_pressed=true,true
local secondary_hit=secondary_sample(2)
assert(secondary_hit.secondary_pressed and secondary_hit.secondary_held and not secondary_hit.pressed)
local right_proxy=menu.proxy({get=function() return false end},null,secondary_hit,vector)
assert(right_proxy:get('right_pressed') and right_proxy:get('right_hold') and not right_proxy:get('left_pressed'))
secondary_pointer.secondary_pressed=false
secondary_pointer.active=false
secondary_hit=secondary_sample(3)
assert(secondary_hit.secondary_held and secondary_hit.x==100 and secondary_hit.y==200)
secondary_pointer.secondary_down=false
secondary_hit=secondary_sample(4)
assert(secondary_hit.secondary_released and not secondary_hit.secondary_held)
assert(not secondary_sample(5).secondary_released)
secondary_pointer.active=true
secondary_pointer.secondary_down,secondary_pointer.secondary_pressed=true,true
assert(not secondary_sample(6,'popup').secondary_pressed)
assert(not secondary_sample(7,'popup').secondary_held)
secondary_pointer.secondary_down,secondary_pointer.secondary_pressed=false,false
secondary_sample(8,'popup')
secondary_pointer.secondary_down,secondary_pointer.secondary_pressed=true,true
assert(secondary_sample(9,'popup').secondary_pressed)
secondary_pointer.available=false
secondary_hit=secondary_sample(10,'popup')
assert(secondary_hit.secondary_released and secondary_hit.override)
assert(not secondary_sample(11,'popup').override)
secondary_pointer.available=true
assert(not secondary_sample(12,'popup').secondary_pressed)
secondary_pointer.transport_generation=2
assert(not secondary_sample(13,'popup').secondary_pressed)
secondary_pointer.secondary_down,secondary_pointer.secondary_pressed=false,false
secondary_sample(14,'popup')
secondary_pointer.secondary_down,secondary_pointer.secondary_pressed=true,true
assert(secondary_sample(15,'popup').secondary_pressed)
-- The actual service owner consumes the secondary sequence once per frame.
presentation.mode=5
p.frame_id,p.secondary_down,p.secondary_pressed=100,false,false
hook(function() return desktop_source,null,false end,handler)
p.frame_id,p.secondary_down,p.secondary_pressed=101,true,true
local secondary_service=hook(function() return desktop_source,null,false end,handler)
assert(secondary_service:get('right_hold') and consumed.secondary==1)
local again=hook(function() return desktop_source,null,false end,handler)
assert(again:get('right_hold') and consumed.secondary==1)
print('menu_secondary: shared route, independent holds, tracking, modal/restart quarantine and edge consumption passed')

-- Both shared service entry points use the same physical/canvas mapping and
-- immutable point. Stock null-service suppression still wins before any read.
presentation.mode=5
presentation.read_desktop_mirror=desktop_cursor
desktop_source.null_service=function() return null end
p.frame_id,p.primary_down,p.primary_pressed=1000,false,false
p.secondary_down,p.secondary_pressed,p.scroll_steps=false,false,0
p.available,p.active=true,true
handler._active_popups={}
Managers.ui=handler
local reads_before=wheel_reads
hook(function() return desktop_source,null,false end,handler) -- Route the previous XR release first.
assert(wheel_reads==reads_before)
p.frame_id=1001
local routed=hook(function() return desktop_source,null,false end,handler)
assert(math.abs(routed:get('cursor')[1]-249.6)<1e-9 and math.abs(routed:get('cursor')[2]-1075.2)<1e-9)
local routed_direct=direct_hook(function() return desktop_source end,{},'View')
assert(routed_direct:get('cursor')[1]==routed:get('cursor')[1] and wheel_reads==reads_before+1)
assert(hook(function() return null,null,false end,handler)==null and wheel_reads==reads_before+1)
print('menu_desktop_wheel=pass physical_cursor immutable_frame xr_gesture_priority shared_services')
