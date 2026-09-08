local root=arg[1]
local function module(name)return dofile(root..'/darktidevr_'..name..'.lua')end
local Wheel,Gesture,Context,Navigation=module('communication_wheel'),module('communication_gesture'),
    module('communication_context'),module('communication_navigation')
local source
if arg[2] then
    local file=assert(io.open(arg[2]..'/scripts/ui/hud/elements/smart_tagging/hud_element_smart_tagging.lua','r'))
    source=file:read('*a');file:close()
end
local function fixture()
    local f={frame=0,owner={},eligible=true,queue={},effects=0,pops=0,presentations=0,base_stops=0}
    local input={keyboard=false,blocked=false}
    function input:get(name)
        if self.blocked then return false end
        if name=='com_wheel' then return self.keyboard end
        if name=='cursor' or name=='navigate_controller_right' or name=='look_raw_controller' then return {0,0,0}end
        return 'stock:'..name
    end
    function input:is_null_service()return self.blocked end
    local Hud={}
    local settings={com_wheel_delay=0,com_wheel_single_tap='location',com_wheel_double_tap='danger'}
    local function defer(fn)if f.defer_error then error('defer failure')end;f.queue[#f.queue+1]=fn end
    function Hud:_on_com_wheel_start(t)self._com_wheel_context.input_start_time=t end
    function Hud:_on_com_wheel_stop(t,renderer,render_settings,service)
        f.base_stops=f.base_stops+1
        defer(function()self:_on_com_wheel_stop_callback(t,renderer,render_settings,service)end)
    end
    function Hud:_on_com_wheel_stop_callback(t)
        if self._wheel_active and self.selected then f.effects=f.effects+1
        elseif t-self._com_wheel_context.input_start_time<=0.3 then
            self._com_wheel_context.single_tap_location_tag={spawn_time=self._com_wheel_context.input_start_time+0.3,position={},tag_type='location'}
        end
        self._com_wheel_context.input_start_time=nil
    end
    function Hud:_handle_com_wheel(t,renderer,render_settings,service)
        local held=service:get('com_wheel')
        local context=self._com_wheel_context
        if held and not context.input_start_time then self:_on_com_wheel_start(t)
        elseif not held and context.input_start_time then self:_on_com_wheel_stop(t,renderer,render_settings,service)end
        if context.input_start_time and t>context.input_start_time and not self._wheel_active then
            self._wheel_active=true;self:_push_cursor()
        elseif not context.input_start_time and self._wheel_active then self._wheel_active=false;self._close_delay=0 end
        local pending=context.single_tap_location_tag
        if pending and t>=pending.spawn_time then self:_trigger_smart_tag();context.single_tap_location_tag=nil end
    end
    function Hud:_update_wheel_presentation(dt,t,renderer,render_settings,service)
        f.presentations=f.presentations+1
        local cursor=service:get('cursor');self.selected=cursor[1]>960 and 1 or 2
        assert(service:get('other')=='stock:other')
    end
    function Hud:_on_wheel_closed()
        if self._wheel_active or self._close_delay~=nil then self:_pop_cursor()end
        self._wheel_active=false;self._close_delay=nil
    end
    function Hud:update(dt,t,renderer,render_settings,service)
        if f.update_error then error('update failure')end
        if self._wheel_active then self:_update_wheel_presentation(dt,t,renderer,render_settings,service)end
        if self._close_delay~=nil then
            self._close_delay=nil;self:_pop_cursor();return 'updated',nil,17
        end
        self:_handle_com_wheel(t,renderer,render_settings,service)
        return 'updated',nil,17
    end
    function Hud:destroy()self:_on_wheel_closed();self.destroyed=true end
    if source then
        local env=setmetatable({HudElementSmartTagging=Hud,InputDevice={gamepad_active=false},DOUBLE_TAP_DELAY=0.3,
            Managers={save={account_data=function()return {input_settings=settings}end},event={trigger=function()end},
                telemetry_reporters={reporter=function()return {register_event=function()end}end}},
            Vo={on_demand_vo_event=function()f.effects=f.effects+1 end},
            Vector3Box=setmetatable({unbox=function(v)return v end},{__call=function(_,v)return v end})},{__index=_G})
        for _,names in ipairs({{'_handle_com_wheel','_should_draw_wheel'},
                {'_on_wheel_closed','_handle_selected_marker'}, {'_on_com_wheel_stop_callback','_get_chat_channel_by_tag'}})do
            local first=assert(source:find('HudElementSmartTagging.'..names[1]..' =',1,true))
            local last=assert(source:find('\nHudElementSmartTagging.'..names[2]..' =',first,true))
            setfenv(assert(loadstring(source:sub(first,last-1),'@cached-smart-tagging')),env)()
        end
    end
    local hud=setmetatable({_com_wheel_context={},_tag_context={},_entries={},owner=f.owner,
        _parent={player_unit=function()return f.owner end}},{__index=Hud})
    function hud:_push_cursor()self._cursor_pushed=true end
    function hud:_pop_cursor()if self._cursor_pushed then f.pops=f.pops+1;self._cursor_pushed=nil end end
    function hud:_trigger_smart_tag()f.effects=f.effects+1 end
    function hud:_find_best_smart_tag_interaction()return nil,nil,{} end
    function hud:_is_wheel_entry_hovered()
        if self.selected then return {option={voice_event_data={voice_tag_concept='mock',voice_tag_id='mock'}}}end
    end
    local mod={hook=function(_,class,name,hook)
        assert(class=='HudElementSmartTagging');local original=assert(Hud[name])
        Hud[name]=function(...)return hook(original,...)end
    end}
    local api=Wheel.install(mod,{Gesture=Gesture,Context=Context,Navigation=Navigation,
        current=function(owner)return owner==f.owner and f.eligible end,
        hud_owner=function(h,owner)return h.owner==owner end,
        dimensions=function()return 1920,1080 end,vector=function(x,y,z)return {x,y,z}end,defer=defer})
    f.api,f.hud,f.input=api,hud,input
    function f:sample(held,x,y)
        self.frame=self.frame+1;return api.sample(self.frame,self.owner,self.eligible,held,x or 0,y or 0)
    end
    function f:update()
        local a,b,c=hud:update(0.1,self.frame*0.1,{}, {scale=1},input)
        assert(a=='updated' and b==nil and c==17)
    end
    function f:open()
        self:sample(false);self:sample(false)
        self.previous=hud._com_wheel_context
        assert(self:sample(true,0.8));self:update()
        self.owned=hud._com_wheel_context;assert(self.owned~=self.previous)
        assert(self:sample(true,0.8));self:update()
        assert(self:sample(true,0.8));self:update()
        assert(hud._wheel_active and hud.selected==1 and self.effects==0)
    end
    return f
end

local f=fixture();f:open()
local selected,presentations=f.hud.selected,f.presentations
assert(f:sample(false));f:update();f:update()
assert(#f.queue==1 and f.effects==0 and f.hud.selected==selected and f.presentations==presentations)
f.queue[1]();f.queue[1]();assert(f.effects==1 and f.base_stops==0)
for _=1,3 do assert(f:sample(false,0.8));f:update()end
assert(f.hud._com_wheel_context==f.previous and f.pops==1)
assert(not f:sample(false,0,0),'gameplay stick must rearm only at neutral')
f.api.cancel()

-- Idle keyboard route and its existing context remain stock-owned.
f=fixture();f:sample(false);f:sample(false);local previous=f.hud._com_wheel_context
f.input.keyboard=true;f:update();f:sample(false);f:update()
assert(f.hud._com_wheel_context==previous and f.hud._wheel_active)
assert(f:sample(true,0.8));f:update() -- Busy stock wheel must reject VR acquisition.
assert(f.hud._com_wheel_context==previous)
f.input.keyboard=false;f:sample(false);f:update();assert(f.base_stops==1)
f.api.cancel()

for _,reason in ipairs({'ineligible','owner','null','deferred_null','destroy'})do
    f=fixture();f:open();f:sample(false);f:update();local callback=f.queue[1]
    if reason=='ineligible' then f.eligible=false;assert(not f:sample(false))
    elseif reason=='owner' then f.owner={};f:update()
    elseif reason=='null' then f.input.blocked=true;f:update()
    elseif reason=='deferred_null' then f.input.blocked=true
    else f.hud:destroy()end
    callback();callback()
    assert(f.effects==0 and f.pops==1 and next(f.owned)==nil,'cancelled release escaped: '..reason)
    assert(f.hud._com_wheel_context==f.previous)
end

-- A press/release without an admitted HUD must not strand the stick claim.
f=fixture();f:sample(false);f:sample(false);assert(f:sample(true,0.8))
assert(not f:sample(false,0.8) and #f.queue==0)

-- Pending short-tap ownership survives release until the stock delayed action.
for _,cancel_pending in ipairs({false,true})do
    f=fixture();f:sample(false);f:sample(false);previous=f.hud._com_wheel_context
    assert(f:sample(true));f:update();local owned=f.hud._com_wheel_context
    assert(f:sample(false));f:update();f.queue[1]()
    assert(owned.single_tap_location_tag and f.effects==0 and f.hud._com_wheel_context==owned)
    if cancel_pending then f.api.cancel()end
    for _=1,4 do f:sample(false);f:update()end
    assert(f.effects==(cancel_pending and 0 or 1) and f.hud._com_wheel_context==previous)
    f.api.cancel()
end

-- Calls outside the owned update cannot advance its context or schedule work.
f=fixture();f:open();presentations=f.presentations
f.hud:_handle_com_wheel(10,{}, {},f.input)
f.hud:_on_com_wheel_stop(10,{}, {},f.input)
f.hud:_update_wheel_presentation(0.1,10,{}, {},f.input)
assert(#f.queue==0 and f.presentations==presentations)
f.api.cancel()

for _,failure in ipairs({'defer','update','callback'})do
    f=fixture();f:open()
    if failure=='callback' then
        f:sample(false);f:update()
        function f.hud:_on_com_wheel_stop_callback()error('callback failure')end
        local ok,err=pcall(f.queue[1]);assert(not ok and tostring(err):find('callback failure',1,true))
    else
        f[failure..'_error']=true;f:sample(false)
        local ok,err=pcall(f.update,f);assert(not ok and tostring(err):find(failure..' failure',1,true))
    end
    assert(f.hud._com_wheel_context==f.previous and f.effects==0 and f.pops==1)
    f.api.cancel()
end
print('communication_wheel=pass owned lifecycle deferred exactly-once release cancellation keyboard pending taps and neutral rearm')
if source then print('communication_wheel_stock=pass actual cached handling/close/release callback; all communication effects mocked')end
