bit=require('bit')
local Bindings=dofile(arg[1])
local Prompts=dofile(arg[2])
local localized=dofile(arg[3])
local hooks,settings,active={},{},true
local utils={apply_color_to_input_text=function(text,color) assert(color=='tint'); return '<tint>'..text end}
local Text={}
package.loaded['scripts/utilities/ui/text']=Text
package.loaded['scripts/managers/input/input_utils']=utils
local fit_calls=0
package.loaded['scripts/managers/ui/ui_renderer']={scaled_font_size_by_width=function(renderer,text,font,size,width)
    assert(renderer.scale==2 and width==58 and size==20)
    fit_calls=fit_calls+1
    return 15
end}
Color={ui_input_color=function() return 'tint' end}
local mod={get=function(_,key) return settings[key] end,
    localize=function(_,key) assert(localized[key],key); return localized[key].en end,
    hook=function(_,class,name,fn)
        hooks[class]=hooks[class] or {}; assert(not hooks[class][name],name)
        hooks[class][name]=fn
    end}
local bindings=Bindings.install(mod)
local menu=dofile(arg[4]).install(mod,function() return active end)
Prompts.install(mod,bindings,function() return active end,menu)
-- Stock tutorial refresh only watches keyboard aliases/device changes. A VR
-- remap must also invalidate its cached description, including VR loss/recovery.
local tutorial, tutorial_info={}, {input_descriptions={{input_action='action_one'}}}
local function tutorial_refresh(info,stock_result)
    return assert(hooks.HudElementPrologueTutorialInfoBox._should_update_input,
        'Tutorial has no binding-revision refresh')(function(self,passed)
            assert(self==tutorial and passed==info); return stock_result or false
        end,tutorial,info)
end
assert(not tutorial_refresh(nil))
assert(tutorial_refresh(tutorial_info))
assert(not tutorial_refresh(tutorial_info),'Unchanged tutorial refreshed every frame')
settings.vr_bind_right_trigger='alternate'; mod.on_setting_changed('vr_bind_right_trigger')
assert(tutorial_refresh(tutorial_info),'VR remap left tutorial hint cached')
assert(not tutorial_refresh(tutorial_info))
assert(tutorial_refresh(tutorial_info,true),'Stock keyboard refresh was suppressed')
active=false; assert(tutorial_refresh(tutorial_info)); assert(not tutorial_refresh(tutorial_info))
active=true; assert(tutorial_refresh(tutorial_info))
settings.vr_bind_right_trigger=nil; mod.on_setting_changed('vr_bind_right_trigger')
local stock_calls=0
local function stock(service,alias,tint)
    stock_calls=stock_calls+1
    return 'keyboard:'..tostring(alias),nil,service,tint
end
local function text(alias,service,tint)
    return hooks[utils].input_text_for_current_input_device(stock,service or 'Ingame',alias,tint)
end
local function scope(class,method,fn,...)
    return hooks[class][method](fn,...)
end
assert(text('action_one')=='keyboard:action_one','scope leaked outside HUD')
assert(hooks[Text].localize_with_button_hint(function()
    return text('back','View')
end,'back','Back')=='[B\194\160/\194\160Menu]','shared hook lost menu labels')
assert(text('back','View')=='keyboard:back','menu label leaked out of action context')
scope('HudElementWieldInfo','_create_entry',function()
    assert(text('action_one')=='[RT]')
    assert(text('weapon_extra')=='[R\194\160Grip]')
    assert(text('combat_ability')=='[L\194\160Grip]','combat ability defaults to the left grip')
    assert(text('smart_tag')=='[R3]')
    assert(text('com_wheel')=='[Unbound]')
    assert(text('voip_push_to_talk')=='[Unbound]')
    assert(text('interact')=='[RS\194\160Down]' and text('weapon_reload')=='[RS\194\160Down]')
    assert(text('wield_1')=='[Unbound]','direct slot selection pretended to be bound')
    assert(text('unrecognized')=='keyboard:unrecognized')
    assert(text('action_one','View')=='keyboard:action_one','desktop menu changed')
    assert(text('action_one','Ingame',true)=='<tint>[RT]')
    local a,b,c=scope('HudElementPlayerWeapon','_update_input',function()
        assert(text('wield_1')=='[RS\194\160Up]' and text('wield_2')=='[RS\194\160Up]','switch badge must show only the control')
        assert(text('wield_3')=='[Unbound]')
        return 7,nil,9
    end)
    assert(a==7 and b==nil and c==9)
    assert(text('wield_1')=='[Unbound]','nested scope context leaked')
end)
assert(text('smart_tag')=='keyboard:smart_tag')
settings.vr_action_bind_communication_wheel=256
mod.on_setting_changed('vr_action_bind_communication_wheel')
scope('HudElementWieldInfo','_create_entry',function()assert(text('com_wheel')=='[R3]')end)
settings.vr_action_bind_communication_wheel=2048
mod.on_setting_changed('vr_action_bind_communication_wheel')
scope('HudElementWieldInfo','_create_entry',function()assert(text('com_wheel')=='[Unbound]')end)
settings.vr_action_bind_communication_wheel=nil
mod.on_setting_changed('vr_action_bind_communication_wheel')
settings.vr_action_bind_push_to_talk=256
mod.on_setting_changed('vr_action_bind_push_to_talk')
scope('HudElementWieldInfo','_create_entry',function()assert(text('voip_push_to_talk')=='[R3]')end)
settings.vr_action_bind_push_to_talk=nil
mod.on_setting_changed('vr_action_bind_push_to_talk')
-- Direct slots keep distinct hints; cycling is never advertised as selecting
-- a particular slot. Defaults remain unbound until the user assigns a control.
settings.vr_bind_x='unbound' -- X carries the item defaults; the stick must label alone here
for id,alias in pairs({pocketable='wield_3',stim='wield_4',device='wield_5',
        cycle_pocketables='wield_3_gamepad',inspect_target='interact_inspect'}) do
    settings.vr_bind_right_stick_up=id
    mod.on_setting_changed('vr_bind_right_stick_up')
    scope('HudElementWieldInfo','_create_entry',function()
        assert(text(alias)=='[RS\194\160Up]','Slot binding hint missing')
        if id=='cycle_pocketables' then
            assert(text('wield_3')=='[Unbound]' and text('wield_4')=='[Unbound]')
        end
    end)
end
settings.vr_bind_right_stick_up=nil
settings.vr_bind_x=nil
mod.on_setting_changed('vr_bind_right_stick_up')
settings.vr_hub_bind_x='inspect_target'
mod.on_setting_changed('vr_hub_bind_x')
bindings.sample(true,0,0,0,true,1,'hub')
scope('HudElementInteraction','_update_interaction_input_text',function()
    assert(text('interact_inspect')=='[X]' and text('interact')=='[RS\194\160Down]')
    assert(text('weapon_inspect')=='[Unbound]','Target interaction pretended to inspect a weapon')
end)
bindings.sample(true,0,0,0,true,1,'shooting_range')
scope('HudElementInteraction','_update_interaction_input_text',function()
    assert(text('interact_inspect')=='[Unbound]' and text('interact')=='[RS\194\160Down]')
end)
settings.vr_hub_bind_x=nil
mod.on_setting_changed('vr_hub_bind_x')
local ok,err=pcall(function()
    scope('HudElementInteraction','_setup_interaction_information',function() error('stock failure') end)
end)
assert(not ok and err:find('stock failure'))
assert(text('action_one')=='keyboard:action_one','error leaked HUD scope')

settings.vr_bind_right_grip='combat_ability'
settings.vr_bind_r3='combat_ability'
mod.on_setting_changed('vr_bind_right_grip')
scope('HudElementPlayerAbility','_update_input',function()
    assert(text('combat_ability')=='[R\194\160Grip]')
    assert(text('weapon_extra')=='[Unbound]' and text('smart_tag')=='[Unbound]')
end)
-- Reading prompts immediately after a settings change must not consume the
-- gameplay mapper's pending held-button quarantine.
bindings.sample(true,0)
settings.vr_bind_right_trigger='combat_ability'
mod.on_setting_changed('vr_bind_right_trigger')
-- Right grip, R3, right trigger, plus the right-stick-up default.
assert(#bindings.controls_for_action('combat_ability')==4)
local p,h=bindings.sample(true,1)
assert(p==0 and h==0)

local updates,refreshes,resets=0,0,0
local element={_update_input=function() refreshes=refreshes+1 end,
    _reset_current_info=function() resets=resets+1 end}
local function update() updates=updates+1; return nil,5 end
local a,b=scope('HudElementPlayerAbility','update',update,element)
assert(a==nil and b==5 and updates==1 and refreshes==1)
scope('HudElementPlayerAbility','update',update,element)
assert(refreshes==1,'refreshed unchanged text every frame')
mod.on_setting_changed('vr_bind_r3')
scope('HudElementPlayerAbility','update',update,element)
assert(refreshes==2)
active=false
scope('HudElementPlayerAbility','update',update,element)
assert(refreshes==3)
scope('HudElementWieldInfo','_create_entry',function()
    local first,second,third=text('action_one')
    assert(first=='keyboard:action_one' and second==nil and third=='Ingame')
end)
local wield={_reset_current_info=function() resets=resets+1 end}
scope('HudElementWieldInfo','update',update,wield)
scope('HudElementWieldInfo','update',update,wield)
assert(resets==1)
active=true
scope('HudElementWieldInfo','update',update,wield)
assert(resets==2)
local style={size={60,50},font_size=20,font_type='hud'}
local badge={style={input_text=style},content={input_text='[Unbound]'}}
element._widgets_by_name={ability=badge}
scope('HudElementPlayerAbility','update',update,element,0.01,1,{scale=2})
assert(fit_calls==1 and style.font_size==15 and badge.dirty)
scope('HudElementPlayerAbility','update',update,element,0.01,2,{scale=2})
assert(fit_calls==1,'remeasured unchanged badge every frame')
active=false
scope('HudElementPlayerAbility','update',update,element,0.01,3,{scale=2})
assert(style.font_size==20 and fit_calls==1,'did not restore stock font outside VR')
assert(stock_calls>0)
for key in pairs(settings) do settings[key]=nil end
settings.vr_bind_right_stick_up='combat_ability'
settings.vr_bind_left_grip='unbound' -- the default ability control would label first
mod.on_setting_changed('vr_bind_right_stick_up')
active=true
scope('HudElementPlayerAbility','_update_input',function()
    assert(text('combat_ability')=='[RS\194\160Up]','directional binding hint missing')
end)
print('controller_prompts=pass scoped labels remap aliases unbound cache_refresh errors nil_returns')

bindings.sample(true,0,0,0,true,1,'hub')
scope('ConstantElementOnboardingHandler','_sync_onboarding_settings',function()
    assert(text('hotkey_inventory','View')=='[R\194\160Grip]','Hub notification missed profile')
    assert(text('right','View')=='keyboard:right','Talent right-click acceptance case changed')
end)
assert(text('hotkey_inventory','View')=='keyboard:hotkey_inventory','Notification scope leaked')
settings.vr_hub_bind_right_grip='unbound'
mod.on_setting_changed('vr_hub_bind_right_grip')
scope('ConstantElementOnboardingHandler','_sync_onboarding_settings',function()
    assert(text('hotkey_inventory','View')=='keyboard:hotkey_inventory','Unbound hotkey got a false VR hint')
end)
bindings.sample(true,0,0,0,true,1,'shooting_range')
scope('ConstantElementOnboardingHandler','_sync_onboarding_settings',function()
    assert(text('hotkey_inventory','View')=='keyboard:hotkey_inventory','Hub hint leaked into combat')
end)
scope('HudElementPrologueTutorialInfoBox','_get_input_description_text',function()
    assert(text('interact')=='[RS\194\160Down]','Tutorial missed shared action binding')
end)

-- Optional cached-source contract: execute the real tutorial and text utility
-- through both installed prompt hooks. Rendering/localization/input lookup are
-- doubles; the stock functions own alias selection and held/released wording.
if arg[5] and arg[6] then
    for key in pairs(settings)do settings[key]=nil end
    mod.on_setting_changed('vr_bind_right_trigger')
    active=true
    bindings.sample(true,0,0,0,true,1,'shooting_range')
    local device={gamepad_active=false}
    local keys={action_one={},action_two={}}
    local ui={get_input_alias_key=function(_,action,service)
        assert(service=='Ingame');return action
    end,get_action_type=function(_,action)
        return action=='action_one' and 'held' or 'released'
    end}
    local translations={loc_input_legend_text_template='%s %s',
        loc_input_hold='Hold',loc_input_release='Release',tutorial_action='Attack'}
    local stock_utils={input_text_for_current_input_device=function(...)
        return hooks[utils].input_text_for_current_input_device(stock,...)
    end}
    local modules={['scripts/managers/input/input_utils']=stock_utils,
        ['scripts/managers/input/input_device']=device}
    local environment=setmetatable({Managers={ui=ui},
        Localize=function(key)return assert(translations[key],key)end,
        class=function()return {}end,
        require=function(name)return modules[name] or {}end},{__index=_G})
    local function load_stock(path)
        local chunk=assert(loadfile(path));setfenv(chunk,environment);return chunk()
    end
    local actual_text=load_stock(arg[6])
    modules['scripts/utilities/ui/text']={localize_with_button_hint=function(...)
        return hooks[Text].localize_with_button_hint(actual_text.localize_with_button_hint,...)
    end}
    local actual=load_stock(arg[5])
    local element={_ui_manager=ui,_previous_keys_info={},_input_manager={
        alias_object=function()return {get_keys_for_alias=function(_,action)return keys[action]end}end}}
    local info={input_descriptions={{description='tutorial_action',
        input_action={keyboard='action_one',controller='action_two'}}}}
    local function description()
        return scope('HudElementPrologueTutorialInfoBox','_get_input_description_text',
            actual._get_input_description_text,element,info)
    end
    local function refresh()
        return scope('HudElementPrologueTutorialInfoBox','_should_update_input',
            actual._should_update_input,element,info)
    end
    assert(description()=='Hold [RT] Attack')
    assert(refresh() and not refresh())
    settings.vr_action_bind_primary=256
    mod.on_setting_changed('vr_action_bind_primary')
    assert(refresh() and not refresh(),'Stock tutorial missed a pure VR remap')
    assert(description()=='Hold [R3] Attack')
    active=false
    assert(refresh() and not refresh())
    assert(description()=='Hold keyboard:action_one Attack')
    active=true
    assert(refresh() and not refresh())
    assert(description()=='Hold [R3] Attack')
    device.gamepad_active=true
    assert(description()=='Release [LT] Attack')
    assert(device.gamepad_active,'Prompt changed global stock input mode')
    assert(text('action_two')=='keyboard:action_two','Stock tutorial leaked prompt scope')
    print('controller_prompts: actual stock tutorial/text preserve remaps, availability, device aliases and action wording')
end
