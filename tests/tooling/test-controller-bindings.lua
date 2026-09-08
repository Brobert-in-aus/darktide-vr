bit = require("bit")
local Bindings = dofile(arg[1])
local settings, callbacks = {}, 0
local mod = {get=function(_,key) return settings[key] end,
    on_setting_changed=function() callbacks=callbacks+1 end}
local mapper = Bindings.install(mod)
local function sample(active,physical,p,h,r)
    local ap,ah,ar=mapper.sample(active,physical)
    assert(ap==p and ah==h and ar==r,
        string.format("got %d,%d,%d expected %d,%d,%d",ap,ah,ar,p,h,r))
end
sample(true,0,0,0,0)
sample(true,1,1,1,0)
sample(true,1,0,1,0)
sample(true,0,0,0,1)
sample(true,8+32,4104+8224,4104+8224,0) -- Original paired controls.
sample(false,8+32,0,0,4104+8224)
sample(true,8+32,0,0,0)
sample(true,0,0,0,0)
sample(true,256+1024,1280,1280,0)
sample(true,0,0,0,1280)

-- A live remap cancels the old action, suppresses its replacement and leaves
-- keyboard/UI callbacks intact. Each held physical control rearms separately.
sample(true,1,1,1,0)
settings.vr_bind_right_trigger='combat_ability'
mod.on_setting_changed('vr_bind_right_trigger')
assert(callbacks==1)
sample(true,1,0,0,0)
sample(true,1+4,4,4,0)
sample(true,4,0,4,0)
sample(true,1+4,2048,2052,0)
sample(true,0,0,0,2052)

-- Aliases aggregate at the semantic action level, including combined/split
-- actions: a second hold cannot retrigger or release a still-held first action.
settings.vr_bind_a='jump'
settings.vr_bind_b='jump_dodge'
mod.on_setting_changed('vr_bind_a')
sample(true,0,0,0,0)
sample(true,32,32,32,0)
sample(true,32+64,8192,8224,0)
sample(true,64,0,8224,0)
sample(true,0,0,0,8224)
settings.vr_bind_a='reload'
settings.vr_bind_x='interact_reload'
mod.on_setting_changed('vr_bind_a')
sample(true,0,0,0,0)
sample(true,32,4096,4096,0)
sample(true,40,8,4104,0)
sample(true,8,0,4104,0)
sample(true,0,0,0,4104)

settings.vr_bind_right_trigger='unbound'
settings.vr_bind_left_trigger='invalid_old_setting'
mod.on_setting_changed('vr_bind_right_trigger')
sample(true,0,0,0,0)
sample(true,3,2,2,0)
mod.on_setting_changed('hud_size') -- Unrelated setting must not quarantine fire.
sample(true,3,0,2,0)
sample(false,0,0,0,2)
sample(true,3,0,0,0)
sample(true,0,0,0,0)
sample(true,3,2,2,0)

-- Options/defaults/localization and actual game input names share the catalog.
local text=dofile(arg[2])
local stock=dofile(arg[3])
local names={}
for _,name in ipairs(stock.actions) do names[name]='held' end
for _,name in ipairs(stock.ephemeral_actions) do names[name]='edge' end
for _,binding in ipairs(mapper.bindings) do
    for _,name in ipairs(binding.held) do assert(names[name]=='held',name) end
    for _,kind in ipairs({'pressed','released'}) do
        for _,name in ipairs(binding[kind]) do assert(names[name]=='edge',name) end
    end
end
local widgets=Bindings.widgets()
local action_count=0
for _,action in ipairs(Bindings.actions) do
    if action.mask>0 and bit.band(action.mask,action.mask-1)==0 then action_count=action_count+1 end
end
assert(#widgets.sub_widgets==action_count+1)
local used={}
local function check_widget(widget)
    assert(not used[widget.setting_id]); used[widget.setting_id]=true
    assert(pcall(string.format,text[widget.title or widget.setting_id].en))
    if widget.sub_widgets then
        for _,child in ipairs(widget.sub_widgets) do check_widget(child) end
        return
    end
    local found=false
    for _,option in ipairs(widget.options) do
        assert(pcall(string.format,text[option.text].en))
        found=found or option.value==widget.default_value
    end
    assert(found)
end
for _,widget in ipairs(widgets.sub_widgets) do check_widget(widget) end

-- Hub overrides inherit saved combat controls; context changes cannot turn
-- an old hold into an attack or a charged-release edge.
local profile_settings={vr_bind_x='interact',vr_bind_right_grip='special'}
local profile_mod={get=function(_,key) return profile_settings[key] end}
local profiles=Bindings.install(profile_mod)
local function context(mode,physical,p,h,r)
    local ap,ah,ar=profiles.sample(true,physical,0,0,true,1,mode)
    assert(ap==p and ah==h and ar==r,'Unexpected context edges')
end
context('hub',4,0,0,0)
assert(profiles.controls_for_action('inventory')[1]=='right_grip')
context('hub',0,0,0,0)
context('hub',4,32768,32768,0)
context('shooting_range',4,0,0,0)
assert(#profiles.controls_for_action('inventory')==0)
context('shooting_range',0,0,0,0)
context('shooting_range',4,4,4,0)
context('hub',4,0,0,0)
context('hub',0,0,0,0)
context('hub',8,8,8,0)
profile_settings.vr_hub_bind_x='inventory'
profile_mod.on_setting_changed('vr_hub_bind_x')
context('hub',8,0,0,0)
context('hub',0,0,0,0)
context('hub',8,32768,32768,0)
context('mission',8,0,0,0)
context('mission',0,0,0,0)
context('mission',8,8,8,0)
assert(profile_settings.vr_bind_x=='interact','Hub override overwrote combat setting')
local directional_settings={vr_turn_mode='off',vr_bind_right_stick_up='combat_ability',vr_bind_right_stick_down='inspect',
    vr_bind_right_stick_left='reload',vr_bind_right_stick_right='reload'}
local directional_mod={get=function(_,key) return directional_settings[key] end}
local directional=Bindings.install(directional_mod)
local function stick(enabled,x,y,usable,generation,p,h,r,physical)
    local ap,ah,ar=directional.sample(enabled,physical or 0,x,y,usable,generation)
    assert(ap==p and ah==h and ar==r,
        string.format('stick got %d,%d,%d expected %d,%d,%d',ap,ah,ar,p,h,r))
end
stick(true,0,1,true,1,0,0,0) -- Entry while deflected: no inherited action.
stick(true,0,0,true,1,0,0,0)
stick(true,0,.64,true,1,0,0,0)
stick(true,0,.65,true,1,2048,2048,0)
stick(true,0,.5,true,1,0,2048,0) -- Hysteresis prevents noisy retriggering.
stick(true,0,.44,true,1,0,0,2048)
stick(true,.8,.8,true,1,2048,2048,0) -- Exact diagonal belongs only to vertical.
stick(true,.81,.8,true,1,4096,4096,2048) -- Crossing sector releases the old action.
stick(true,-.8,0,true,1,0,4096,0) -- Horizontal aliases do not retrigger.
stick(true,0,0,true,1,0,0,4096)
stick(true,0,-.8,true,1,16384,16384,0)
stick(false,0,-.8,true,1,0,0,0)
stick(true,0,-.8,true,1,0,0,0)
stick(true,0,0,true,1,0,0,0)
stick(true,0,1,true,1,2048,2048,0)
stick(true,0,1,false,1,0,0,0)
stick(true,0,1,true,1,0,0,0) -- Tracking reacquisition requires neutral.
stick(true,0,0,true,1,0,0,0)
stick(true,0,1,true,1,2048,2048,0)
stick(true,0,1,true,2,0,0,0) -- Writer restart cancels without a release.
stick(true,0,0,true,2,0,0,0)
stick(true,0,1,true,2,2048,2048,0)
directional_settings.vr_bind_right_stick_up='special'
directional_mod.on_setting_changed('vr_bind_right_stick_up')
stick(true,0,1,true,2,0,0,0)
stick(true,0,0,true,2,0,0,0)
stick(true,0,1,true,2,4,4,0)
stick(true,0/0,1,true,2,0,0,0)
stick(true,0,1,true,2,0,0,0) -- Invalid axes invalidate the old latch.
stick(true,0,0,true,2,0,0,0,2048) -- Unknown native bits cannot impersonate directions.
local default_mapper=Bindings.install({get=function() end})
default_mapper.sample(true,0,0,0,true,1)
local p,h,r=default_mapper.sample(true,0,1,1,true,1)
assert(p==0 and h==0 and r==0,'new direction defaults were not unbound')
print('controller_bindings=pass defaults aliases remap_cancel context_handoff directional_hysteresis tracking generation stock_names options')
-- Mission slots use ordinary stock wield edges. Held bindings and a second
-- alias cannot repeat slot changes; an inactive transition requires release.
for id,expected in pairs({pocketable='wield_3',stim='wield_4',device='wield_5',
        cycle_pocketables='wield_3_gamepad',inspect_target='interact_inspect_pressed'}) do
    local slots=Bindings.install({get=function(_,key)
        if key=='vr_bind_x' or key=='vr_bind_y' then return id end
    end})
    slots.sample(true,0)
    local pressed,held=slots.sample(true,8)
    local delivered={}
    for _,binding in ipairs(slots.bindings) do
        if bit.band(pressed,binding.mask)~=0 then
            for _,name in ipairs(binding.pressed) do delivered[#delivered+1]=name end
            assert(#binding.held==0 and #binding.released==0,'Slot must be edge-only')
        end
    end
    assert(#delivered==1 and delivered[1]==expected,'Incorrect stock slot action')
    assert(slots.sample(true,8+16)==0,'Second alias repeated wield')
    assert(slots.sample(true,16)==0,'Releasing first alias repeated wield')
    slots.sample(false,16)
    assert(slots.sample(true,16)==0,'Held slot leaked across blocked input')
    slots.sample(true,0)
    assert(slots.sample(true,16)==pressed and held==pressed)
end
-- Turning owns horizontal axes, while vertical shortcuts and native buttons
-- continue. Switching it off while deflected must not trigger the old shortcut.
directional_settings.vr_turn_mode='smooth'
directional_settings.vr_bind_right_stick_up='combat_ability'
directional_mod.on_setting_changed('vr_turn_mode')
stick(true,0,0,true,2,0,0,0)
stick(true,1,1,true,2,2048,2048,0)
assert(#directional.controls_for_action('reload')==1) -- X default, no RS directions.
directional_settings.vr_turn_mode='off'
directional_mod.on_setting_changed('vr_turn_mode')
stick(true,1,0,true,2,0,0,0)
stick(true,1,0,true,2,0,0,0)
stick(true,0,0,true,2,0,0,0)
stick(true,1,0,true,2,4096,4096,0)
-- Losing an axis must neither release nor retrigger a healthy button alias.
local aliases=Bindings.install({get=function(_,key)
    if key=='vr_bind_right_trigger' or key=='vr_bind_right_stick_up' then return 'combat_ability' end
end})
aliases.sample(true,0,0,0,true,1)
local ap,ah,ar=aliases.sample(true,1,0,1,true,1)
assert(ap==2048 and ah==2048 and ar==0)
ap,ah,ar=aliases.sample(true,1,0,1,false,1)
assert(ap==0 and ah==2048 and ar==0,'Lost axis retriggered or released a healthy button alias')
ap,ah,ar=aliases.sample(true,0,0,1,false,1)
assert(ap==0 and ah==0 and ar==2048,'Healthy button release was swallowed after axis loss')
aliases.sample(true,0,0,0,true,1)
assert(aliases.sample(true,0,0,1,true,1)==2048)
ap,ah,ar=aliases.sample(true,0,0,1,false,1)
assert(ap==0 and ah==0 and ar==0,'Axis-only cancellation emitted a charged release')
aliases.sample(true,0,0,0,true,1)
aliases.sample(true,1,0,1,true,1)
ap,ah,ar=aliases.sample(true,0,0,1,false,1)
assert(ap==0 and ah==0 and ar==2048,'Same-frame healthy button release was swallowed by axis loss')
-- A physically held but blocked alias never contributed and cannot turn a
-- cancelled axis into a release when that blocked button returns neutral.
aliases.sample(false,1,0,0,true,1)
aliases.sample(true,1,0,0,true,1)
aliases.sample(true,1,0,1,true,1)
ap,ah,ar=aliases.sample(true,0,0,1,false,1)
assert(ap==0 and ah==0 and ar==0,'Blocked alias manufactured a release during axis cancellation')

-- A contextual support grip owns the physical gesture, before remapped actions
-- are aggregated. Other controls bound to either action remain independent.
local grip_settings={}
local grip_mod={get=function(_,key) return grip_settings[key] end}
local grip_mapper=Bindings.install(grip_mod)
local grip_request={control='left_grip',owner={},acquire=true,retain=true,action='alternate'}
local function grip_sample(physical,p,h,r,owned,request,enabled,generation,mode)
    local gp,gh,gr=grip_mapper.sample(enabled~=false,physical,0,0,true,generation or 1,
        mode or 'combat',request)
    assert(gp==p and gh==h and gr==r,
        string.format('support grip got %d,%d,%d expected %d,%d,%d',gp,gh,gr,p,h,r))
    assert(grip_mapper.support_grip.held==owned,'Incorrect contextual grip ownership')
end
grip_sample(0,0,0,0,false,grip_request)
grip_sample(512,2,2,0,true,grip_request)
assert(grip_mapper.support_grip.pressed)
grip_sample(512,0,2,0,true,grip_request)
grip_sample(512+2,0,2,0,true,grip_request)
grip_sample(2,0,2,0,false,grip_request)
assert(grip_mapper.support_grip.released,'Physical support release was lost')
grip_sample(0,0,0,2,false,grip_request)
grip_request.acquire=false
grip_sample(512,512,512,0,false,grip_request)
grip_request.acquire=true
grip_sample(512,0,512,0,false,grip_request) -- Moving a held grip into range is not a press.
grip_sample(0,0,0,512,false,grip_request)
grip_sample(512,2,2,0,true,grip_request)
grip_request.retain=false
grip_sample(512,0,0,0,false,grip_request)
assert(grip_mapper.support_grip.cancelled,'Tracking/retention loss did not cancel')
grip_request.retain=true
grip_sample(512,0,0,0,false,grip_request)
grip_sample(0,0,0,0,false,grip_request)
grip_sample(512,2,2,0,true,grip_request)
grip_request.owner={}
grip_sample(512,0,0,0,false,grip_request) -- Weapon replacement requires neutral.
grip_sample(0,0,0,0,false,grip_request)
grip_sample(512+2,2,2,0,true,grip_request)
grip_sample(512+2,0,2,0,false,nil) -- An ordinary aim alias survives cancellation.
grip_sample(512,0,0,2,false,nil) -- Its real release must still be delivered.
grip_sample(0,0,0,0,false,grip_request)
grip_sample(512+2,2,2,0,true,grip_request)
grip_sample(512,0,0,2,false,nil) -- Same-frame alias release survives support cancellation.
grip_sample(0,0,0,0,false,grip_request)
grip_settings.vr_bind_right_trigger='blitz'
grip_mod.on_setting_changed('vr_bind_right_trigger')
grip_sample(0,0,0,0,false,grip_request)
grip_sample(512+1,514,514,0,true,grip_request)
grip_sample(1,0,512,2,false,grip_request) -- Displaced blitz alias is not suppressed.
grip_sample(0,0,0,512,false,grip_request)
for _,transition in ipairs({'disabled','generation','context','remap'}) do
    grip_sample(512,2,2,0,true,grip_request)
    if transition=='remap' then
        grip_settings.vr_bind_left_grip='primary'
        grip_mod.on_setting_changed('vr_bind_left_grip')
    end
    grip_sample(512,0,0,0,false,grip_request,transition~='disabled',
        transition=='generation' and 2 or 1,transition=='context' and 'hub' or 'combat')
    grip_sample(512,0,0,0,false,grip_request)
    grip_sample(0,0,0,0,false,grip_request)
end
-- Future handedness selects a physical grip without swapping tracking channels.
grip_request.control='right_grip'
grip_sample(4,2,2,0,true,grip_request)
grip_sample(0,0,0,2,false,grip_request)
grip_request.action='unbound'
grip_sample(4,0,0,0,true,grip_request) -- Support can hold without requesting ADS.
grip_sample(0,0,0,0,false,grip_request)
print('support_grip=pass fresh_press aliases cancellation neutral roles optional_ads')

-- Inverting the menu must preserve every legacy semantic binding, including
-- combined actions, duplicate aliases and hub overrides.
local migrated_settings={vr_bind_a='jump_dodge',vr_bind_b='jump',vr_bind_x='interact_reload',
    vr_bind_right_stick_up='combat_ability',vr_hub_bind_x='inspect_target',vr_turn_mode='smooth'}
local migrated_mod={get=function(_,key) return migrated_settings[key] end,
    set=function(_,key,value) migrated_settings[key]=value end,
    localize=function(_,key) return assert(text[key],key).en end}
local before=Bindings.install(migrated_mod)
local expected={}
for _,mode in ipairs({'combat','hub'}) do
    before.sample(true,0,0,0,true,1,mode)
    expected[mode]={}
    for _,action in ipairs(Bindings.actions) do
        expected[mode][action.id]=table.concat(before.controls_for_action(action.id),',')
    end
end
local menu=Bindings.widgets(migrated_mod)
local after=Bindings.install(migrated_mod)
for _,mode in ipairs({'combat','hub'}) do
    after.sample(true,0,0,0,true,1,mode)
    for _,action in ipairs(Bindings.actions) do
        assert(table.concat(after.controls_for_action(action.id),',')==expected[mode][action.id],mode..':'..action.id)
    end
end
assert(migrated_settings.vr_action_bind_jump==32+64,'Migration dropped an alias')
assert(migrated_settings.vr_action_bind_interact==8 and migrated_settings.vr_action_bind_reload==8)
local jump_row
for _,row in ipairs(menu.sub_widgets) do
    if row.setting_id=='vr_action_bind_jump' then jump_row=row end
end
local found_alias=false
for _,option in ipairs(jump_row.options) do
    if option.value==96 then found_alias=option.text:find('A',1,true) and option.text:find('B',1,true) end
end
assert(found_alias,'Dropdown does not show preserved aliases')
after.sample(true,0,0,0,true,1,'combat')
after.sample(true,32,0,0,true,1,'combat')
migrated_settings.vr_action_bind_jump=8
migrated_mod.on_setting_changed('vr_action_bind_jump')
local p,h,r=after.sample(true,32,0,0,true,1,'combat')
assert(p==0 and h==0 and r==0,'Action-first remap synthesized an input edge')
after.sample(true,0,0,0,true,1,'combat')
p,h,r=after.sample(true,8,0,0,true,1,'combat')
assert(p==4104+32 and h==p,'Shared-control actions were displaced by reassignment')
Bindings.widgets(migrated_mod)
assert(migrated_settings.vr_action_bind_jump==8,'Reopening menu repeated migration')
migrated_settings.vr_action_bind_jump=0
migrated_mod.on_setting_changed('vr_action_bind_jump')
assert(#after.controls_for_action('jump')==0,'Unbound action fell back to a legacy binding')
print('action_binding_menu=pass migration aliases shared_control remap_neutral hub no_repeat')
