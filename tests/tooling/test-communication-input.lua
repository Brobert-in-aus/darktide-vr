bit=require('bit')
local root=arg[1]
local Input=dofile(root..'/darktidevr_communication_input.lua')
local Bindings=dofile(root..'/darktidevr_controller_bindings.lua')
local Gesture=dofile(root..'/darktidevr_communication_gesture.lua')
local Turning=dofile(root..'/darktidevr_turning.lua')
local function fixture()
    local f={settings={vr_action_bind_communication_wheel=256,vr_turn_mode='snap45'},
        mode='shooting_range',world={},unit={},handler={},blocked=false,queued={}}
    local config,gesture= nil,Gesture.new(0.25)
    local mod={get=function(_,key)return f.settings[key]end,
        set=function(_,key,value)f.settings[key]=value end,localize=function(_,key)return key end}
    function mod:io_dofile(path)
        if path:match('communication_wheel$') then return {install=function(_,value)
            config=value
            return {cancel=gesture.cancel,sample=function(...)
                f.sample=gesture.sample(...);f.sample.owner=select(2,...);return f.sample.claim_stick
            end}
        end}end
        return dofile(root..'/'..assert(path:match('([^/]+)$'))..'.lua')
    end
    local observation={gameplay_input_active=true,right_aim_usable=true,right_stick_x=0,right_stick_y=0,
        last_transport_generation=1,head_recenter_generation=1}
    local input={enabled=true}
    local presentation={mode=1,gameplay_input_owner={f.handler,f.unit},
        is_first_person_body_mode=function(mode)return mode=='shooting_range' or mode=='hub'end,
        gameplay_context={local_input_unit=function(handler)return handler==f.handler and f.unit end,
            input_service_enabled=function(service)return service.enabled end,
            ui_blocks_gameplay=function()return f.blocked end}}
    local bindings=Bindings.install(mod);presentation.controller_bindings=bindings
    local api=Input.install(mod,presentation,observation,{mode=function()return f.mode end,world=function()return f.world end})
    local turning=Turning.install(mod)
    Managers={state={game_mode={register_physics_safe_callback=function(_,fn)f.queued[#f.queued+1]=fn end}}}
    RESOLUTION_LOOKUP={width=1920,height=1080};Vector3=function(x,y,z)return {x,y,z}end
    f.api,f.config,f.mod,f.bindings,f.observation,f.presentation,f.input=api,config,mod,bindings,observation,presentation,input
    function f:step(physical,x,y)
        self.t=(self.t or 0)+1
        observation.right_stick_x,observation.right_stick_y=x or 0,y or 0
        local claim=api.sample(self.handler,self.unit,input,observation.gameplay_input_active,physical,self.mode,self.world)
        local revision=bindings.revision
        local delta=turning.sample(true,x or 0,y or 0,true,observation.last_transport_generation,
            observation.head_recenter_generation,self.world,1+self.t*0.01,claim)
        local p,h,r=bindings.sample(true,physical,x or 0,y or 0,true,
            observation.last_transport_generation,self.mode,nil,claim)
        assert(bindings.revision==revision,'post-claim mapping changed the owner revision')
        return claim,delta,p,h,r
    end
    function f:open()
        self:step(0);self:step(0)
        local claim,delta=self:step(256,1,0)
        assert(claim and delta==0 and self.sample.pressed)
    end
    return f
end
local f=fixture();f:open()
assert(f.config.current(f.presentation.gameplay_input_owner)==false)
for _,reason in ipairs({'ui','input','unit','handler','mode','world','remap','generation','recenter','tracking','inactive','presentation'})do
    f=fixture();f:open();local owner=f.sample.owner
    assert(f.config.current(owner)==true,reason)
    if reason=='ui' then f.blocked=true
    elseif reason=='input' then f.input.enabled=false
    elseif reason=='unit' then f.unit={}
    elseif reason=='handler' then f.handler={}
    elseif reason=='mode' then f.mode='hub'
    elseif reason=='world' then f.world={}
    elseif reason=='remap' then f.mod.on_setting_changed('vr_action_bind_communication_wheel')
    elseif reason=='generation' then f.observation.last_transport_generation=2
    elseif reason=='recenter' then f.observation.head_recenter_generation=2
    elseif reason=='tracking' then f.observation.right_aim_usable=false
    elseif reason=='inactive' then f.observation.gameplay_input_active=false
    else f.presentation.mode=0 end
    assert(f.config.current(owner)==false,'stale deferred owner admitted: '..reason)
    f.api.cancel();assert(not f.config.current(owner))
end
f=fixture();f:open();local old_owner=f.sample.owner
f.settings.vr_hub_action_bind_communication_wheel=8;f.mode='hub'
assert(not f:step(8,1,0) and f.sample.cancelled and not f.config.current(old_owner))
assert(not f:step(8,1,0),'profile switch converted held button into a gesture')
f:step(0);assert(f:step(8,1,0) and f.sample.pressed)
f.api.cancel();f:step(8,1,0);assert(not f.sample.held)
f:step(0);assert(f:step(8,1,0))

-- The wheel cannot bind its own navigation axes, including corrupted saved or
-- legacy assignments. Aliased physical buttons are still supported.
f=fixture();f.settings.vr_action_bind_communication_wheel=256+2048+8192
f.mod.on_setting_changed('vr_action_bind_communication_wheel')
local controls=f.bindings.controls_for_action('communication_wheel')
assert(#controls==1 and controls[1]=='r3')
assert(not f.bindings.physical_hold('communication_wheel',2048+8192,'combat'))
assert(f.bindings.physical_hold('communication_wheel',256,'combat'))
local widgets=Bindings.widgets(f.mod)
for _,widget in ipairs(widgets.sub_widgets)do
    if widget.setting_id=='vr_action_bind_communication_wheel' then
        assert(widget.default_value==0)
        for _,option in ipairs(widget.options)do assert(option.value<2048,'wheel offered a navigation-axis binding')end
    end
end
f.settings.vr_action_bind_communication_wheel=nil
f.settings.vr_bind_right_stick_up='communication_wheel'
f.mod.on_setting_changed('vr_bind_right_stick_up')
assert(#f.bindings.controls_for_action('communication_wheel')==0)
local w,h=f.config.dimensions();assert(w==1920 and h==1080)
local calls=0;f.config.defer(function()calls=calls+1 end);assert(calls==0)
f.queued[1]();assert(calls==1)
print('communication_input=pass preclaim profile revision physical-only bindings routing generations tracking and deferred queue')
