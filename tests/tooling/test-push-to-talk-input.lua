local Talk=dofile(arg[1])
local current,keyboard,available,blocked=true,false,true,false
local source
source={has=function(self,name)assert(self==source);return name=='voip_push_to_talk' and available end,
    get=function(self,name)assert(self==source);if name=='voip_push_to_talk' then return keyboard end;return name,nil,9 end,
    is_null_service=function()return blocked end}
local manager={_input_service=source}
local retained
local function owns()return current end
local a,b,c=Talk.with_input(manager,true,owns,function(self,x)
    assert(self==manager and x==17);retained=self._input_service
    assert(retained:has('voip_push_to_talk') and retained:get('voip_push_to_talk'))
    local x,y,z=retained:get('other');assert(x=='other' and y==nil and z==9)
    current=false;assert(not retained:get('voip_push_to_talk'));current=true
    available=false;assert(not retained:get('voip_push_to_talk'));available=true
    blocked=true;assert(not retained:get('voip_push_to_talk'));blocked=false
    Talk.with_input(manager,false,owns,function(inner)
        assert(not inner._input_service:get('voip_push_to_talk'),'nested unheld update must suspend outer injection')
    end)
    assert(retained:get('voip_push_to_talk'),'outer scope must resume after nested update')
    local nested_ok=pcall(Talk.with_input,manager,false,owns,function()error('nested failure')end)
    assert(not nested_ok and retained:get('voip_push_to_talk'))
    return 'done',nil,17
end,17)
assert(a=='done' and b==nil and c==17 and manager._input_service==source)
assert(not retained:get('voip_push_to_talk'),'retained proxy must expire')
Talk.with_input(manager,true,owns,function(self)
    assert(self._input_service:get('voip_push_to_talk'))
    assert(not retained:get('voip_push_to_talk'),'old proxy cannot revive in a new update')
end)
keyboard=true
Talk.with_input(manager,false,owns,function(self)assert(self._input_service==source and source:get('voip_push_to_talk'))end)
current=false
Talk.with_input(manager,true,owns,function(self)assert(self._input_service:get('voip_push_to_talk'),'keyboard remains independent')end)
keyboard=false;current=true
local ok,err=pcall(Talk.with_input,manager,true,owns,function(self)retained=self._input_service;error('stock failure')end)
assert(not ok and tostring(err):find('stock failure',1,true) and manager._input_service==source)
assert(not retained:get('voip_push_to_talk'))
local replacement={}
Talk.with_input(manager,true,owns,function(self)retained=self._input_service;self._input_service=replacement
    assert(not retained:get('voip_push_to_talk'))end)
assert(manager._input_service==replacement)
manager._input_service=source;blocked=true
Talk.with_input(manager,true,owns,function(self)assert(self._input_service==source)end)
blocked=false
local null={get=function()return false end,has=function()return true end}
function null:null_service()return self end
manager._input_service=null
Talk.with_input(manager,true,owns,function(self)assert(self._input_service==null)end)
manager._input_service=source
-- Adapter-only eligibility probes must not prevent stock update/cleanup when
-- an input proxy retires. Stock may not use PTT input in its current voice mode.
for _,method in ipairs({'lookup','is_null_service','null_service'})do
    local retired={get=function()return false end,has=function()return true end}
    if method=='lookup' then
        setmetatable(retired,{__index=function()error('retired lookup')end})
    else retired[method]=function()error('retired query')end end
    manager._input_service=retired
    local updated=0
    Talk.with_input(manager,true,owns,function(self)
        updated=updated+1;assert(self._input_service==retired)
    end)
    assert(updated==1 and manager._input_service==retired)
end
manager._input_service=source
print('push_to_talk_input=pass scoped hold keyboard availability null replacement failure sparse returns')

if arg[2] then
    local path=arg[2]..'/scripts/managers/chat/chat_manager.lua'
    local file=assert(io.open(path,'r'));local text=file:read('*a');file:close()
    local helper_start=assert(text:find('local function _sound_setting_option_voice_chat()',1,true))
    local helper_end=assert(text:find('\nChatManager.init =',helper_start,true))
    local update_start=assert(text:find('ChatManager.update =',helper_end,true))
    local update_end=assert(text:find('\nlocal function login_state_enum',update_start,true))
    local mode=2
    local Stock={}
    local env=setmetatable({ChatManager=Stock,IS_WINDOWS=true,
        SOUND_SETTING_OPTIONS_VOICE_CHAT={muted=0,voice_activated=1,push_to_talk=2},
        Application={user_setting=function(group,key)assert(group=='sound_settings' and key=='voice_chat');return mode end}},
        {__index=_G})
    setfenv(assert(loadstring(text:sub(helper_start,helper_end-1)..text:sub(update_start,update_end-1),'@'..path)),env)()
    local calls={}
    manager={_input_service=source,_local_audio_info={is_mic_muted=true},_initialized=false}
    function manager:mute_local_mic(mute)calls[#calls+1]=mute;self._local_audio_info.is_mic_muted=mute end
    local function tick(held)Talk.with_input(manager,held,owns,Stock.update,0.01,1)end
    tick(true);assert(#calls==1 and calls[1]==false)
    tick(true);assert(#calls==1,'stock must not repeat an unchanged mute request')
    tick(false);assert(#calls==2 and calls[2]==true)
    tick(true);current=false;tick(true);assert(calls[#calls]==true,'lost routing returns to mute')
    keyboard=true;tick(false);assert(calls[#calls]==false,'keyboard push-to-talk remains usable')
    keyboard=false;current=true;tick(false)
    for _,setting in ipairs({0,1}) do
        mode=setting;local count=#calls;tick(true);tick(false)
        assert(#calls==count,'adapter must not override stock muted/voice-activated modes')
    end
    for _,method in ipairs({'lookup','is_null_service','null_service'})do
        local retired={has=function()return true end,get=function()return false end}
        if method=='lookup' then setmetatable(retired,{__index=function()error('retired stock proxy lookup')end})
        else retired[method]=function()error('retired stock proxy query')end end
        manager._input_service=retired
        for _,setting in ipairs({0,1})do
            mode=setting;local count=#calls;manager._t=nil;tick(true)
            assert(manager._t==1 and #calls==count,'adapter stopped the stock non-PTT update')
        end
        mode=2;manager._local_audio_info.is_mic_muted=false
        local count=#calls;tick(true)
        assert(#calls==count+1 and calls[#calls]==true,'adapter stopped stock PTT release cleanup')
        assert(manager._input_service==retired)
    end
    manager._input_service=source
    mode=nil;tick(true);assert(calls[#calls]==false,'Windows missing setting uses stock PTT default')
    print('push_to_talk_stock=pass actual ChatManager update hold release routing loss keyboard modes; microphone calls mocked')
end
