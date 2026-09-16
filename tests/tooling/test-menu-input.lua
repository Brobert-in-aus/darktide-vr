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
    function() return 100,200,0,500,true end,
    function() return 0/0,200,1000,500,true end,
}) do
    local routed=menu.proxy(desktop_source,null,{override=true,x=900,y=800,scroll=0},vector,read,2000,1000)
    assert(routed:get('cursor')[1]==900,'Invalid desktop point replaced XR input')
end
for _,point in ipairs({{-1,200},{1000,200},{100,500}}) do
    local mouse={get=function(_,name) return name=='left_hold' or name=='left_released' end}
    local routed=menu.proxy(mouse,null,{override=true,x=900,y=800,scroll=0},vector,
        function() return point[1],point[2],1000,500,true end,2000,1000)
    assert(routed:get('cursor')[1]==point[1]*2 and routed:get('cursor')[2]==point[2]*2,
        'A desktop drag outside the window jumped to the controller ray')
end
local idle_desktop={get=function() return vector(0,0,0) end}
local idle=menu.proxy(idle_desktop,null,{override=true,x=900,y=800,scroll=0},vector,
    function() error('Idle mouse requested a desktop point') end,2000,1000)
assert(idle:get('cursor')[1]==900,'Previous wheel event retained cursor ownership')
for _,action in ipairs({'left_pressed','left_hold','left_released','right_pressed','right_hold',
        'right_released','middle_pressed','middle_hold','middle_released'}) do
    local mouse={get=function(_,name) return name==action end}
    local routed=menu.proxy(mouse,null,{override=true,x=900,y=800,scroll=0},vector,desktop_cursor,2000,1000)
    assert(routed:get('cursor')[1]==200 and routed:get(action),
        'Desktop button phase used a delayed controller point: '..action)
end
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
-- Observe neutral after stock's temporary block before new navigation edges.
hook(function() return source,null,false end,handler)
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
local overlay=gameplay_hooks['HudElementTacticalOverlay.update']
local local_hud={_parent={player_unit=function()return gameplay_owner end}}
presentation.gameplay_ui.sample(true,0,2097152)
overlay(function()
    local routed=direct_hook(function()return source end,{},'Ingame')
    assert(routed:get('tactical_overlay_hold'), 'Central InputManager route missed tactical HUD hold')
end,local_hud)
assert(direct_hook(function()return source end,{},'Ingame')==source, 'Tactical route leaked outside HUD')
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

-- A mouse drag uses immediate stock events, not an extra XR press counter.
-- The controller may point elsewhere or resume its point on the release frame.
local mouse_events={}
local mouse_position=100
local mouse_source={get=function(_,name) return mouse_events[name] or false end,
    null_service=function() return null end}
presentation.read_desktop_mirror=function() return mouse_position,200,1000,500,true end
local mouse_presses,mouse_releases=0,0
for index,events in ipairs({{left_pressed=true,left_hold=true},{left_hold=true},{left_released=true}}) do
    mouse_events=events; mouse_position=100*index
    p.frame_id=2000+index
    p.primary_down,p.primary_pressed=false,false -- Native stream contains XR/test buttons only.
    local current=hook(function() return mouse_source,null,false end,handler)
    assert(math.abs(current:get('cursor')[1]-249.6*index)<1e-9,'Desktop drag lost its current point')
    if current:get('left_pressed') then mouse_presses=mouse_presses+1 end
    if current:get('left_released') then mouse_releases=mouse_releases+1 end
    assert(current:get('left_hold')==(events.left_hold or false))
end
assert(mouse_presses==1 and mouse_releases==1)
mouse_events={}; p.frame_id=2004
presentation.read_desktop_mirror=function() error('Released desktop retained cursor ownership') end
local after_mouse=hook(function() return mouse_source,null,false end,handler)
assert(after_mouse:get('cursor')[1]==p.x*RESOLUTION_LOOKUP.width/p.source_width)
print('menu_desktop_buttons=pass all_mouse_phases immediate_drag_point single_stock_click release_frame')

-- Stock can temporarily block this same view without replacing its owner.
-- Requests accumulated while blocked must not become clicks/back/scroll when
-- the service returns, and the blocked route must not read either pointer.
presentation.read_desktop_mirror=nil
local pointer_reads=0
presentation.read_menu_pointer=function()pointer_reads=pointer_reads+1;return p end
p.frame_id=3000
p.primary_down,p.primary_pressed,p.secondary_down,p.secondary_pressed=false,false,false,false
p.back_pressed,p.scroll_steps=false,0
hook(function()return mouse_source,null,false end,handler)
p.frame_id=3001
p.primary_down,p.primary_pressed,p.secondary_down,p.secondary_pressed=true,true,true,true
p.back_pressed,p.scroll_steps=true,2
local before_block_reads=pointer_reads
assert(hook(function()return null,null,false end,handler)==null)
assert(pointer_reads==before_block_reads,'Blocked route read controller input')
p.frame_id=3002
local recovered=hook(function()return mouse_source,null,false end,handler)
assert(not recovered:get('left_pressed') and not recovered:get('right_pressed'),
    'Click made during null input replayed when the same view recovered')
assert(not recovered:get('left_hold') and not recovered:get('right_hold'))
assert(not recovered:get('back') and recovered:get('scroll_axis')[2]==0)
assert(not p.primary_pressed and not p.secondary_pressed and not p.back_pressed and p.scroll_steps==0)
p.frame_id=3003
recovered=hook(function()return mouse_source,null,false end,handler)
assert(not recovered:get('left_hold') and not recovered:get('right_hold'))
p.frame_id=3004
p.primary_down,p.secondary_down=false,false
hook(function()return mouse_source,null,false end,handler)
p.frame_id=3005
p.primary_down,p.primary_pressed,p.secondary_down,p.secondary_pressed=true,true,true,true
recovered=hook(function()return mouse_source,null,false end,handler)
assert(recovered:get('left_pressed') and recovered:get('right_pressed'),'Fresh released/rearmed controls were blocked')
-- A directly fetched View service can also block an already-active gesture.
-- Recovery during that same frame must not inherit the previous sample.
p.frame_id=3006
p.primary_pressed,p.secondary_pressed=false,false
before_block_reads=pointer_reads
assert(direct_hook(function()return null end,{},'View')==null)
assert(pointer_reads==before_block_reads)
recovered=direct_hook(function()return mouse_source end,{},'View')
assert(not recovered:get('left_hold') and not recovered:get('right_hold'))
assert(not recovered:get('left_pressed') and not recovered:get('right_pressed'))
print('menu_null_recovery=pass blocked_requests_drained=true release_required=true no_blocked_pointer_reads=true')

for _,failure in ipairs({'lookup','query'}) do
    local retired={get=function()return false end}
    if failure=='lookup' then
        setmetatable(retired,{__index=function()error('retired menu service lookup')end})
    else
        retired.null_service=function()error('retired menu null query')end
    end
    before_block_reads=pointer_reads
    assert(direct_hook(function()return retired end,{},'View')==retired,
        'Retiring service prevented stock direct input return')
    assert(pointer_reads==before_block_reads,'Retiring service read XR pointer')
    readiness_hook({},0.01,0,retired) -- Optional observation must not throw.
    p.frame_id=p.frame_id+1
    recovered=direct_hook(function()return mouse_source end,{},'View')
    assert(not recovered:get('left_hold') and not recovered:get('right_hold'))
end
local without_null={get=function()return false end}
assert(direct_hook(function()return without_null end,{},'View')==without_null)
print('menu_retired_service=pass direct_stock_return_preserved=true readiness_probe_protected=true')

-- Menu hotkeys answer to fixed controller buttons by key alias and action
-- type; buttons held when a menu takes over must be released first, and a
-- button alone (pointer off the panel) still reaches the menu.
do
    local button_state={}
    local off_panel={available=false,active=false,transport_generation=1,
        primary_down=false,primary_pressed=false,scroll_steps=0}
    local actions={
        hotkey_menu_special_1={key_alias='hotkey_menu_special_1',type='pressed'},
        hotkey_menu_special_1_hold={key_alias='hotkey_menu_special_1',type='held'},
        hotkey_menu_special_2_released={key_alias='hotkey_menu_special_2',type='released'},
        continue_end_view={key_alias='continue_end_view',type='pressed'},
        hotkey_item_sort={key_alias='hotkey_item_sort',type='pressed'}}
    local hotkey_source={_actions=actions,get=function() return false end}
    local function frame(n,buttons,owner)
        return menu.sample(button_state,off_panel,n,owner or 'end_view',1920,1080,buttons)
    end
    local function buttons(y,x,rt) return {y=y,x=x,a=false,rt=rt} end
    local s=frame(1,buttons(true,false,true))
    local hot=menu.proxy(hotkey_source,null,s,vector)
    assert(not hot:get('hotkey_menu_special_1') and not hot:get('continue_end_view'),
        'buttons held when the menu opened pressed it')
    frame(2,buttons(false,false,false))
    s=frame(3,buttons(true,true,true)); hot=menu.proxy(hotkey_source,null,s,vector)
    assert(s.override and hot:get('hotkey_menu_special_1') and hot:get('hotkey_menu_special_1_hold') and
        hot:get('continue_end_view'),'Y presses E and RT the end screen continue')
    assert(not hot:get('hotkey_item_sort'),'an unmapped hotkey answered to a button')
    s=frame(4,buttons(true,false,true)); hot=menu.proxy(hotkey_source,null,s,vector)
    assert(not hot:get('hotkey_menu_special_1') and hot:get('hotkey_menu_special_1_hold') and
        hot:get('hotkey_menu_special_2_released') and not hot:get('continue_end_view'),
        'pressed fires once, held and released follow the button')
    s=frame(5,buttons(true,false,true),'other_view'); hot=menu.proxy(hotkey_source,null,s,vector)
    assert(not hot:get('hotkey_menu_special_1_hold') and not hot:get('continue_end_view'),
        'a new menu inherited held buttons')
    frame(6,buttons(false,false,false),'other_view')
    s=frame(7,buttons(true,false,false),'other_view'); hot=menu.proxy(hotkey_source,null,s,vector)
    assert(hot:get('hotkey_menu_special_1'))
    s=frame(8,nil,'other_view')
    assert(not s.override,'no buttons and no pointer keep the stock service')
    assert(menu.menu_buttons.hotkey_menu_special_1=='y' and menu.menu_buttons.hotkey_menu_special_2=='x')
    print('menu_hotkey_buttons=pass key_alias_types release_required owner_quarantine pointer_independent')
end

-- A named character (the unattended runner's "start:<name>"): selected through
-- the stock card selection, which also requests the profile from the backend,
-- then the same one-second settle before play. A name that is not in the list
-- is recorded and play proceeds with whatever is selected, rather than never
-- starting.
do
    local selected = {}
    ready_view._character_list_widgets = {
        {content = {profile = {name = 'Psykerson', character_id = 'p1'}}},
        {content = {profile = {name = 'Robobert', character_id = 'r1'}}},
    }
    ready_view._on_character_widget_selected = function(self, index, quiet)
        selected[#selected + 1] = index
        assert(quiet == true, 'no selection sound for a scripted pick')
    end
    assert(menu.character_index(ready_view, 'Robobert') == 2)
    assert(menu.character_index(ready_view, 'Psykerson') == 1)
    assert(menu.character_index(ready_view, 'Nobody') == nil and menu.character_index(nil, 'Robobert') == nil)
    assert(menu.character_index(ready_view, nil) == nil)

    local before = starts
    local named = {armed = true, character = 'Robobert'}
    assert(not menu.advance_startup(named, ready_view, false, 10))
    assert(not menu.advance_startup(named, ready_view, false, 10.5), 'still settling')
    assert(not menu.advance_startup(named, ready_view, false, 11), 'the pick happens here, not play')
    assert(#selected == 1 and selected[1] == 2 and named.selected_index == 2)
    assert(starts == before, 'play did not fire on the same frame as the pick')
    assert(not menu.advance_startup(named, ready_view, false, 11.5), 'settling again after the pick')
    assert(menu.advance_startup(named, ready_view, false, 12))
    assert(starts == before + 1 and #selected == 1, 'play once, pick once')
    assert(not named.character_missing)

    local missing = {armed = true, character = 'Nobody'}
    local before_missing, picks = starts, #selected
    assert(not menu.advance_startup(missing, ready_view, false, 20))
    assert(menu.advance_startup(missing, ready_view, false, 21), 'a missing name still starts')
    assert(missing.character_missing == true and #selected == picks, 'nothing picked')
    assert(starts == before_missing + 1)

    -- Without a name, nothing about the existing start changes.
    local plain = {armed = true}
    assert(not menu.advance_startup(plain, ready_view, false, 30))
    assert(menu.advance_startup(plain, ready_view, false, 31))
    assert(#selected == picks, 'no pick without a name')
    print('startup_character: named card picked through stock selection, settle, once, missing name falls through')
end
