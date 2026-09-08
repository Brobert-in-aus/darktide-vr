local Context=dofile(arg[1])
local function fixture()
    local hud={_com_wheel_context={input_stop_time=7},_tag_context={},_entries={
        {widget={content={hotspot={is_hover=true}}}}},_last_widget_hover_data={index=1,t=7},closes=0}
    function hud:_on_wheel_closed()self.closes=self.closes+1;self._wheel_active=false;self._close_delay=nil end
    return hud
end
local hud=fixture()
local previous=hud._com_wheel_context
local revoked=0
local scope=assert(Context.acquire(hud,function()revoked=revoked+1 end))
assert(scope.current() and hud._com_wheel_context~=previous)
assert(not hud._entries[1].widget.content.hotspot.is_hover and not hud._last_widget_hover_data.index)
assert(not Context.acquire(hud,function()end),'duplicate acquisition before stock start')
local owned=hud._com_wheel_context
owned.input_start_time=8;owned.single_tap_location_tag={spawn_time=9};owned.is_double_tap=true
hud._wheel_active=true
assert(not scope.finish())
assert(scope.cancel() and revoked==1 and hud.closes==1 and next(owned)==nil)
assert(hud._com_wheel_context==previous and previous.input_stop_time==7 and not scope.current())
assert(not scope.cancel() and revoked==1 and hud.closes==1)
scope=assert(Context.acquire(hud,function()error('should not cancel normal finish')end))
assert(scope.finish() and hud._com_wheel_context==previous)

for _,field in ipairs({'input_start_time','single_tap_location_tag'}) do
    hud=fixture();hud._com_wheel_context[field]={}
    local before=hud._com_wheel_context
    assert(not Context.acquire(hud,function()end) and hud._com_wheel_context==before)
end
for _,field in ipairs({'_wheel_active','_close_delay'}) do
    hud=fixture();hud[field]=true
    assert(not Context.acquire(hud,function()end))
end
hud=fixture();hud._tag_context.input_start_time=1
assert(not Context.acquire(hud,function()end))

-- Lost/replaced owners must not close or replace a different wheel context.
hud=fixture();scope=assert(Context.acquire(hud,function()revoked=revoked+1 end))
local replacement={input_start_time=20};hud._com_wheel_context=replacement
assert(not scope.current() and not scope.finish())
assert(scope.cancel() and hud._com_wheel_context==replacement and hud.closes==0)
hud=fixture();previous=hud._com_wheel_context
scope=assert(Context.acquire(hud,function()end));hud.destroyed=true
assert(scope.cancel() and hud.closes==0 and hud._com_wheel_context==previous)

-- Revocation failure still attempts close and retires ownership; both errors survive.
hud=fixture();previous=hud._com_wheel_context
scope=assert(Context.acquire(hud,function()error('revoke failed')end))
owned=hud._com_wheel_context;owned.single_tap_location_tag={}
function hud:_on_wheel_closed()self.closes=self.closes+1;error('close failed')end
local ok,err=pcall(scope.cancel)
assert(not ok and tostring(err):find('revoke failed',1,true) and tostring(err):find('close failed',1,true))
assert(hud.closes==1 and hud._com_wheel_context==previous and next(owned)==nil and not scope.cancel())
hud=fixture();scope=assert(Context.acquire(hud,function()end));replacement={}
function hud:_on_wheel_closed()self._com_wheel_context=replacement end
scope.cancel();assert(hud._com_wheel_context==replacement)
print('communication_context=pass owned isolation cancellation pending taps retirement replacement failures')

if arg[2] then
    local path=arg[2]..'/scripts/ui/hud/elements/smart_tagging/hud_element_smart_tagging.lua'
    local file=assert(io.open(path,'r'));local source=file:read('*a');file:close()
    local Stock={}
    local env=setmetatable({HudElementSmartTagging=Stock,InputDevice={gamepad_active=false},
        Managers={save={account_data=function()return {input_settings={com_wheel_delay=0.3}}end},
            event={trigger=function()end}},Vector3Box={unbox=function(v)return v end}},{__index=_G})
    local function method(name,next_name)
        local first=assert(source:find('HudElementSmartTagging.'..name..' =',1,true))
        local last=assert(source:find('\nHudElementSmartTagging.'..next_name..' =',first,true))
        setfenv(assert(loadstring(source:sub(first,last-1),'@'..path)),env)()
    end
    method('_handle_com_wheel','_should_draw_wheel')
    method('_on_wheel_closed','_handle_selected_marker')
    local Gesture=dofile(arg[1]:gsub('darktidevr_communication_context.lua$','darktidevr_communication_gesture.lua'))
    local gesture=Gesture.new(0.25)
    local player={}
    gesture.sample(1,player,true,false,0,0)
    gesture.sample(2,player,true,false,0,0)
    gesture.sample(3,player,true,true,0,1)
    local release=gesture.sample(4,player,true,false,0,1)
    hud=fixture();hud._on_wheel_closed=Stock._on_wheel_closed
    local pops,tags,callbacks=0,0,0
    function hud:_pop_cursor()pops=pops+1 end
    function hud:_on_com_wheel_stop()callbacks=callbacks+1 end
    function hud:_trigger_smart_tag()tags=tags+1 end
    scope=assert(Context.acquire(hud,gesture.cancel))
    owned=hud._com_wheel_context
    owned.input_start_time=1;owned.single_tap_location_tag={spawn_time=2,position={},tag_type='fixture'}
    hud._wheel_active=true
    local function deferred()
        if scope.current() and gesture.take_release(release.token) then callbacks=callbacks+1 end
    end
    scope.cancel();deferred();deferred()
    Stock._handle_com_wheel(hud,3,nil,nil,{get=function()return false end})
    assert(pops==1 and tags==0 and callbacks==0 and next(owned)==nil)
    assert(not gesture.take_release(release.token),'cancel must revoke even a callback retaining only the token')
    print('communication_context_stock=pass actual close/input methods no delayed tap or deferred release after cancellation')
end
