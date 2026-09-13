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
sample(true,16+32,786432+8224,786432+8224,0) -- Paired controls: Y items, A jump/dodge.
sample(false,16+32,0,0,786432+8224)
sample(true,16+32,0,0,0)
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
-- Right stick up defaults to the class ability (the Psykhanium onboarding
-- waits for it); the other directions stay unbound.
assert(p==16 and h==16 and r==0,'right stick up must default to the weapon switch')
p,h,r=default_mapper.sample(true,0,0,-1,true,1)
assert(p==4104 and h==4104,'right stick down must default to interact/reload')
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
assert(#directional.controls_for_action('reload')==0) -- reload's default is RS down, reassigned to inspect here.
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
grip_sample(512,2048,2048,0,false,grip_request)
grip_request.acquire=true
grip_sample(512,0,2048,0,false,grip_request) -- Moving a held grip into range is not a press.
grip_sample(0,0,0,2048,false,grip_request)
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
-- X from the legacy setting plus the right-stick-down default.
assert(migrated_settings.vr_action_bind_interact==8+4096 and migrated_settings.vr_action_bind_reload==8+4096)
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

-- A new HUD action has no default assignment and uses ordinary held/rearm
-- semantics when deliberately bound. Existing mappings remain independent.
local overlay_settings={}
local overlay_mod={get=function(_,key)return overlay_settings[key]end}
local overlay_mapper=Bindings.install(overlay_mod)
assert(#overlay_mapper.controls_for_action('tactical_overlay')==0)
overlay_settings.vr_action_bind_tactical_overlay=256
overlay_mod.on_setting_changed('vr_action_bind_tactical_overlay')
overlay_mapper.sample(true,256)
overlay_mapper.sample(true,0)
local overlay_pressed,overlay_held=overlay_mapper.sample(true,256)
assert(bit.band(overlay_pressed,2097152)~=0 and bit.band(overlay_held,2097152)~=0)
overlay_pressed,overlay_held=overlay_mapper.sample(true,256)
assert(overlay_pressed==0 and bit.band(overlay_held,2097152)~=0)
overlay_mapper.sample(false,256)
overlay_pressed,overlay_held=overlay_mapper.sample(true,256)
assert(overlay_pressed==0 and overlay_held==0, 'Held overlay reopened after routing loss')
print('tactical_overlay_binding=pass default_unassigned explicit_hold neutral_rearm')

local conflict_settings={vr_action_bind_device=8,vr_action_bind_cycle_pocketables=8,
    vr_action_bind_pocketable=0,vr_action_bind_stim=0,vr_turn_mode='smooth'}
local conflict_commands,conflict_messages={},{}
local conflict_mod={get=function(_,key)return conflict_settings[key]end,
    command=function(_,name,_,fn)conflict_commands[name]=fn end,
    echo=function(_,format,...)conflict_messages[#conflict_messages+1]=string.format(format,...)end,
    localize=function(_,key)return assert(text[key],key).en end}
local conflict_mapper=Bindings.install(conflict_mod)
local overlaps=conflict_mapper.wield_conflicts()
assert(#overlaps==1 and overlaps[1].control=='x' and #overlaps[1].actions==2)
assert(overlaps[1].actions[1]=='device' and overlaps[1].actions[2]=='cycle_pocketables')
overlaps[1].actions[1]='mutated'
assert(conflict_mapper.wield_conflicts()[1].actions[1]=='device', 'Report exposed mutable cached state')
conflict_commands.dtvr_binding_conflicts()
assert(conflict_messages[1]:find('combat bindings:',1,true) and conflict_messages[1]:find('X',1,true))
assert(conflict_settings.vr_action_bind_device==8 and conflict_settings.vr_action_bind_cycle_pocketables==8)
conflict_settings.vr_hub_action_bind_device=0
conflict_settings.vr_hub_action_bind_cycle_pocketables=-1
conflict_mapper.sample(true,0,0,0,true,1,'hub')
assert(#conflict_mapper.wield_conflicts()==0, 'Hub override was ignored')
conflict_commands.dtvr_binding_conflicts()
assert(conflict_messages[2]:find('No overlapping weapon or item selectors in hub',1,true))
conflict_settings.vr_action_bind_device=8192
conflict_settings.vr_action_bind_cycle_pocketables=8192
conflict_mod.on_setting_changed('vr_action_bind_device')
conflict_mapper.sample(true,0,0,0,true,1,'combat')
assert(#conflict_mapper.wield_conflicts()==0, 'Turning-owned horizontal action was reported as usable')
conflict_settings.vr_turn_mode='off';conflict_mod.on_setting_changed('vr_turn_mode')
assert(conflict_mapper.wield_conflicts()[1].control=='right_stick_left')
conflict_settings.vr_action_bind_cycle_pocketables=0
conflict_mod.on_setting_changed('vr_action_bind_cycle_pocketables')
assert(#conflict_mapper.wield_conflicts()==0, 'Remapped conflict stayed cached')
conflict_settings.vr_action_bind_device=2048 -- right stick up carries the weapon switch by default
conflict_mod.on_setting_changed('vr_action_bind_device')
local quick_overlap=conflict_mapper.wield_conflicts()
assert(#quick_overlap==1 and quick_overlap[1].control=='right_stick_up' and quick_overlap[1].actions[1]=='quick_wield')
print('wield_binding_conflicts=pass current_profile aliases remap horizontal_gate no_setting_writes')
local talk_settings={}
local talk_mod={get=function(_,key)return talk_settings[key]end}
local talk_mapper=Bindings.install(talk_mod)
assert(#talk_mapper.controls_for_action('push_to_talk')==0)
talk_settings.vr_action_bind_push_to_talk=32+2048+8192
talk_mod.on_setting_changed('vr_action_bind_push_to_talk')
local talk_controls=talk_mapper.controls_for_action('push_to_talk')
assert(#talk_controls==1 and talk_controls[1]=='a','PTT accepted a virtual navigation axis')
talk_mapper.sample(true,0,0,0,true,1,'combat')
local tp,th=talk_mapper.sample(true,32,0,1,true,1,'combat')
assert(bit.band(tp,8388608)~=0 and bit.band(th,8388608)~=0)
local _,_,tr=talk_mapper.sample(true,0,0,1,true,1,'combat')
assert(bit.band(tr,8388608)~=0,'Axis assignment kept physical PTT release held')
-- 13 September layout: X crouches, Y cycles carried items. A saved layout
-- moves once, and only where crouch and the item actions still sit on the old
-- defaults; any other layout is kept exactly.
do
    local defaults={}
    for _,control in ipairs(Bindings.controls) do defaults[control.id]=control.default end
    assert(defaults.x=='crouch' and defaults.y=='pocketable_device','X must default to crouch, Y to items')
    local function migrated(saved)
        local writes={}
        local swap_mod={get=function(_,key) return saved[key] end,
            set=function(_,key,value) saved[key]=value;writes[#writes+1]=key end}
        Bindings.install(swap_mod)
        return saved,writes
    end
    -- Untouched defaults move; everything else stays, and it runs once.
    local saved,writes=migrated({vr_action_bind_crouch=16,vr_action_bind_cycle_pocketables=8,
        vr_action_bind_device=8,vr_action_bind_jump=32,vr_hub_action_bind_crouch=-1,
        vr_action_bind_sprint=128+16})
    assert(saved.vr_action_bind_crouch==8 and saved.vr_action_bind_cycle_pocketables==16 and
        saved.vr_action_bind_device==16,'default crouch and items must move to the new buttons')
    assert(saved.vr_action_bind_jump==32 and saved.vr_hub_action_bind_crouch==-1 and
        saved.vr_action_bind_sprint==128+16,'other bindings stay, including a custom Y')
    assert(saved.vr_bindings_xy_swapped==true and #writes==4)
    local _,again=migrated(saved)
    assert(#again==0 and saved.vr_action_bind_crouch==8,'the migration runs once')
    -- Crouch moved elsewhere: nothing moves, X and Y keep their actions.
    saved=migrated({vr_action_bind_crouch=32,vr_action_bind_cycle_pocketables=8,
        vr_action_bind_device=8,vr_action_bind_dodge=16})
    assert(saved.vr_action_bind_crouch==32 and saved.vr_action_bind_cycle_pocketables==8 and
        saved.vr_action_bind_device==8 and saved.vr_action_bind_dodge==16,'a custom crouch keeps the layout')
    -- Already on the new layout: kept, not reversed.
    saved=migrated({vr_action_bind_crouch=8,vr_action_bind_cycle_pocketables=16,vr_action_bind_device=16})
    assert(saved.vr_action_bind_crouch==8 and saved.vr_action_bind_cycle_pocketables==16 and
        saved.vr_action_bind_device==16,'a player-made new layout must not be reversed')
    -- Crouch on Y plus another button: a choice, kept.
    saved=migrated({vr_action_bind_crouch=16+128,vr_action_bind_cycle_pocketables=8,vr_action_bind_device=8})
    assert(saved.vr_action_bind_crouch==16+128 and saved.vr_action_bind_device==8)
    -- Fresh install: nothing saved, nothing written but the flag.
    saved,writes=migrated({})
    assert(#writes==1 and saved.vr_bindings_xy_swapped==true and saved.vr_action_bind_crouch==nil)
end
-- A press selecting several wield targets is a cycle over them, device first,
-- then pocketable, small pocketable and (with quick wield) the weapon; it
-- keeps one direct selector.
do
    local QUICK, POCKETABLE, STIM, DEVICE, CYCLE, JUMP = 16, 65536, 131072, 262144, 524288, 32
    local function inv(wielded, device, pocketable, small)
        return {wielded_slot=wielded, slot_device=device and 'auspex' or 'not_equipped',
            slot_pocketable=pocketable and 'ammo' or 'not_equipped',
            slot_pocketable_small=small and 'stim' or 'not_equipped'}
    end
    local press = Bindings.wield_press
    local shared = DEVICE + CYCLE
    -- Default Y (device and item cycle).
    assert(press(shared, inv('slot_primary', true, true, true)) == DEVICE, 'a weapon held brings out the device')
    assert(press(CYCLE, inv('slot_secondary', true, true, true)) == DEVICE, 'the cycle alone starts at the device')
    assert(press(shared, inv('slot_device', true, true, true)) == POCKETABLE, 'the device steps to the pocketable')
    assert(press(shared, inv('slot_pocketable', true, true, true)) == STIM, 'the pocketable steps to the small one')
    assert(press(shared, inv('slot_pocketable_small', true, true, true)) == DEVICE, 'the small pocketable wraps to the device')
    assert(press(shared, inv('slot_pocketable', true, true, false)) == DEVICE, 'an empty small slot is skipped')
    assert(press(shared, inv('slot_device', true, false, true)) == STIM, 'the device reaches an only small pocketable')
    assert(press(shared, inv('slot_device', true, false, false)) == DEVICE, 'nothing else to cycle to keeps the device')
    assert(press(shared, inv('slot_primary', false, true, true)) == POCKETABLE, 'without a device the cycle starts at the pocketable')
    assert(press(shared + JUMP, inv('slot_device', true, true, true)) == POCKETABLE + JUMP, 'other actions in the press stay')
    -- Single selectors and the device-less cycle keep stock behaviour.
    assert(press(DEVICE, inv('slot_primary', true, true, true)) == DEVICE, 'a device-only press is unchanged')
    assert(press(CYCLE, inv('slot_pocketable', false, true, true)) == CYCLE, 'the stock cycle without a device is unchanged')
    assert(press(QUICK, inv('slot_device', true, true, true)) == QUICK, 'quick wield alone is unchanged')
    -- Stim and ammo crate on one button alternate.
    assert(press(POCKETABLE + STIM, inv('slot_primary', true, true, true)) == POCKETABLE, 'from a weapon the first selected item')
    assert(press(POCKETABLE + STIM, inv('slot_pocketable', true, true, true)) == STIM)
    assert(press(POCKETABLE + STIM, inv('slot_pocketable_small', true, true, true)) == POCKETABLE,
        'selected items only: the device is not in this cycle')
    -- Quick wield on an item button is the last step, back to the weapon.
    assert(press(QUICK + STIM, inv('slot_primary', true, true, true)) == STIM)
    assert(press(QUICK + STIM, inv('slot_pocketable_small', true, true, true)) == QUICK, 'the item steps back to the weapon')
    assert(press(QUICK + CYCLE, inv('slot_pocketable_small', true, true, true)) == QUICK)
    assert(press(QUICK + STIM, inv('slot_primary', true, true, false)) == QUICK, 'no item equipped leaves the weapon swap')
    -- The item cycle with a direct item on the same button stays one selector.
    local mixed = press(CYCLE + STIM, inv('slot_device', true, true, true))
    assert(mixed == POCKETABLE, 'cycle plus a direct item still delivers one selector')
    assert(press(shared, nil) == shared and press(JUMP, inv('slot_primary', true, true, true)) == JUMP)
end
print('push_to_talk_binding=pass default_unassigned physical-only aliases and release')
