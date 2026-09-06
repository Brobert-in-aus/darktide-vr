bit=require('bit')
local Bindings=dofile(arg[1])
local Prompts=dofile(arg[2])
local localized=dofile(arg[3])
local hooks,settings,active={},{},true
local utils={apply_color_to_input_text=function(text,color) assert(color=='tint'); return '<tint>'..text end}
package.loaded['scripts/managers/input/input_utils']=utils
local fit_calls=0
package.loaded['scripts/managers/ui/ui_renderer']={scaled_font_size_by_width=function(renderer,text,font,size,width)
    assert(renderer.scale==2 and width==60 and size==20)
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
Prompts.install(mod,bindings,function() return active end)
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
scope('HudElementWieldInfo','_create_entry',function()
    assert(text('action_one')=='[RT]')
    assert(text('weapon_extra')=='[R Grip]')
    assert(text('combat_ability')=='[Unbound]')
    assert(text('smart_tag')=='[R3]')
    assert(text('interact')=='[X]' and text('weapon_reload')=='[X]')
    assert(text('wield_1')=='[Unbound]','direct slot selection pretended to be bound')
    assert(text('unrecognized')=='keyboard:unrecognized')
    assert(text('action_one','View')=='keyboard:action_one','desktop menu changed')
    assert(text('action_one','Ingame',true)=='<tint>[RT]')
    local a,b,c=scope('HudElementPlayerWeapon','_update_input',function()
        assert(text('wield_1')=='[Y switch]' and text('wield_2')=='[Y switch]')
        assert(text('wield_3')=='[Unbound]')
        return 7,nil,9
    end)
    assert(a==7 and b==nil and c==9)
    assert(text('wield_1')=='[Unbound]','nested scope context leaked')
end)
assert(text('smart_tag')=='keyboard:smart_tag')
local ok,err=pcall(function()
    scope('HudElementInteraction','_setup_interaction_information',function() error('stock failure') end)
end)
assert(not ok and err:find('stock failure'))
assert(text('action_one')=='keyboard:action_one','error leaked HUD scope')

settings.vr_bind_right_grip='combat_ability'
settings.vr_bind_r3='combat_ability'
mod.on_setting_changed('vr_bind_right_grip')
scope('HudElementPlayerAbility','_update_input',function()
    assert(text('combat_ability')=='[R Grip]')
    assert(text('weapon_extra')=='[Unbound]' and text('smart_tag')=='[Unbound]')
end)
-- Reading prompts immediately after a settings change must not consume the
-- gameplay mapper's pending held-button quarantine.
bindings.sample(true,0)
settings.vr_bind_right_trigger='combat_ability'
mod.on_setting_changed('vr_bind_right_trigger')
assert(#bindings.controls_for_action('combat_ability')==3)
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
mod.on_setting_changed('vr_bind_right_stick_up')
active=true
scope('HudElementPlayerAbility','_update_input',function()
    assert(text('combat_ability')=='[RS Up]','directional binding hint missing')
end)
print('controller_prompts=pass scoped labels remap aliases unbound cache_refresh errors nil_returns')
