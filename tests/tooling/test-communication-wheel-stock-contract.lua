-- Optional cached-source contract. No game, chat, voice or tag calls are made.
local root=assert(arg[1], 'stock source root required')
local path=root..'/scripts/ui/hud/elements/smart_tagging/hud_element_smart_tagging.lua'
local file=assert(io.open(path,'r')); local source=file:read('*a'); file:close()
local Hud={}
local events={}
local env=setmetatable({HudElementSmartTagging=Hud,InputDevice={gamepad_active=false},
    Managers={save={account_data=function() return {input_settings={com_wheel_delay=0.3}} end},
        event={trigger=function(_,name,state) events[#events+1]={name,state} end}},
    Vector3Box={unbox=function(value)return value end}}, {__index=_G})
local function load_method(name,next_name)
    local first=assert(source:find('HudElementSmartTagging.'..name..' =',1,true))
    local last=assert(source:find('\nHudElementSmartTagging.'..next_name..' =',first,true))
    setfenv(assert(loadstring(source:sub(first,last-1),'@'..path)),env)()
end
load_method('_handle_com_wheel','_should_draw_wheel')
local function fixture()
    local self=setmetatable({_com_wheel_context={},starts=0,stops=0,pushes=0,tags=0}, {__index=Hud})
    function self:_on_com_wheel_start(t) self.starts=self.starts+1; self._com_wheel_context.input_start_time=t end
    -- Stock stop queues a physics-safe callback; keep the start until it runs.
    function self:_on_com_wheel_stop() self.stops=self.stops+1 end
    function self:_push_cursor() self.pushes=self.pushes+1 end
    function self:_should_draw_wheel_gamepad()return self.instant end
    function self:_trigger_smart_tag() self.tags=self.tags+1 end
    local input={held=false,get=function(s,name)assert(name=='com_wheel');return s.held end}
    return self,input
end
local hud,input=fixture()
input.held=true
hud:_handle_com_wheel(1,nil,nil,input)
assert(hud.starts==1 and not hud._wheel_active)
hud:_handle_com_wheel(1.3,nil,nil,input)
assert(not hud._wheel_active, 'opening uses strict greater-than delay')
hud:_handle_com_wheel(1.31,nil,nil,input)
assert(hud._wheel_active and hud.pushes==1 and hud.starts==1)
hud:_handle_com_wheel(1.31,nil,nil,input)
assert(hud.pushes==1 and hud.starts==1, 'held duplicate must not reopen')
input.held=false
hud:_handle_com_wheel(1.4,nil,nil,input)
assert(hud.stops==1)
hud:_handle_com_wheel(1.4,nil,nil,input)
assert(hud.stops==2, 'pending stock callback permits duplicate stop scheduling')
hud._com_wheel_context.input_start_time=nil -- Simulate physics callback completion.
hud:_handle_com_wheel(1.41,nil,nil,input)
assert(not hud._wheel_active and hud._close_delay==0 and hud.stops==2)

hud,input=fixture(); input.held=true
env.InputDevice.gamepad_active=true; hud.instant=true
hud:_handle_com_wheel(2,nil,nil,input)
assert(hud._wheel_active and hud.pushes==0, 'controller can open before delay without cursor push')
hud._com_wheel_context.input_start_time=nil; input.held=false
hud:_handle_com_wheel(2.1,nil,nil,input)
assert(hud._close_delay==0.15, 'controller closing retains stock delay')

hud,input=fixture(); input.held=true
hud:_handle_com_wheel(3,nil,nil,input)
local null={get=function()return false end}
hud:_handle_com_wheel(3.1,nil,nil,null)
assert(hud.stops==1, 'a blocked/null input is a release, not cancellation')
hud._com_wheel_context.input_start_time=nil
hud._com_wheel_context.single_tap_location_tag={spawn_time=4,position={},tag_type='mock'}
hud:_handle_com_wheel(3.9,nil,nil,null); assert(hud.tags==0)
hud:_handle_com_wheel(4,nil,nil,null); assert(hud.tags==1)
hud:_handle_com_wheel(4,nil,nil,null); assert(hud.tags==1)
print('communication_wheel_stock=pass delay, controller opening, deferred release, blocked input and pending tap')
print('LIMIT: mocked side effects; no mission, network, voice/chat or worn acceptance')
