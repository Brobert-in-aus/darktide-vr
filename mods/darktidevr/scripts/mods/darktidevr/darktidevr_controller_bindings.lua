-- Native bits remain physical channels. Resolve gameplay semantics here so
-- the options and delivery share one catalog; menu pointer bindings stay native.
local Bindings = {}
-- Defaults follow the accepted play layout (12 September 2026, X and Y
-- swapped 13 September): triggers fire, right grip special, left grip class
-- ability, B blitz, X crouch (the thumb rolls onto it from the stick to
-- slide while sprinting), A jump/dodge, Y items, RS up weapon switch, RS
-- down interact/reload.
Bindings.controls = {
    {id="right_trigger", bit=1, default="primary"},
    {id="left_trigger", bit=2, default="alternate"},
    {id="right_grip", bit=4, default="special"},
    {id="left_grip", bit=512, default="combat_ability"},
    {id="x", bit=8, default="crouch"},
    {id="y", bit=16, default="pocketable_device"},
    {id="a", bit=32, default="jump_dodge"},
    {id="b", bit=64, default="blitz"},
    {id="l3", bit=128, default="sprint"},
    {id="r3", bit=256, default="tag"},
    {id="menu", bit=1024, default="menu"},
    {id="right_stick_up", bit=2048, default="quick_wield", axis="y", sign=1},
    {id="right_stick_down", bit=4096, default="interact_reload", axis="y", sign=-1},
    {id="right_stick_left", bit=8192, default="unbound", axis="x", sign=-1},
    {id="right_stick_right", bit=16384, default="unbound", axis="x", sign=1},
}
Bindings.actions = {
    {id="unbound", mask=0},
    {id="primary", hub=false, mask=1, pressed={"action_one_pressed"}, held={"action_one_hold"}, released={"action_one_release"}},
    {id="alternate", hub=false, mask=2, pressed={"action_two_pressed"}, held={"action_two_hold"}, released={"action_two_release"}},
    {id="special", hub=false, mask=4, pressed={"weapon_extra_pressed"}, held={"weapon_extra_hold"}, released={"weapon_extra_release"}},
    {id="interact", mask=8, pressed={"interact_pressed"}, held={"interact_hold"}},
    {id="reload", hub=false, mask=4096, pressed={"weapon_reload_pressed"}, held={"weapon_reload_hold"}},
    {id="interact_reload", mask=4104},
    -- Item selection shares one control: device and pocketable cycling.
    {id="pocketable_device", mask=786432},
    {id="quick_wield", hub=false, mask=16, pressed={"quick_wield"}},
    {id="jump", mask=32, pressed={"jump"}, held={"jump_held"}},
    {id="dodge", hub=false, mask=8192, pressed={"dodge"}},
    {id="jump_dodge", mask=8224},
    {id="crouch", mask=64, pressed={"crouch"}, held={"crouching"}},
    {id="sprint", mask=128, pressed={"sprint"}, held={"sprinting"}},
    {id="tag", mask=256},
    {id="blitz", hub=false, mask=512, pressed={"grenade_ability_pressed"}, held={"grenade_ability_hold"}, released={"grenade_ability_release"}},
    {id="combat_ability", hub=false, mask=2048, pressed={"combat_ability_pressed"}, held={"combat_ability_hold"}, released={"combat_ability_release"}},
    {id="inspect", hub=false, mask=16384, held={"weapon_inspect_hold"}},
    {id="menu", mask=1024},
    {id="inventory", mask=32768},
    {id="pocketable", hub=false, mask=65536, pressed={"wield_3"}},
    {id="stim", hub=false, mask=131072, pressed={"wield_4"}},
    {id="device", hub=false, mask=262144, pressed={"wield_5"}},
    {id="cycle_pocketables", hub=false, mask=524288, pressed={"wield_3_gamepad"}},
    {id="inspect_target", mask=1048576, pressed={"interact_inspect_pressed"}},
    {id="tactical_overlay", mask=2097152},
    {id="communication_wheel", mask=4194304, physical_only=true},
    {id="push_to_talk", mask=8388608, physical_only=true},
    -- Delivered only through a grip request (virtual holsters); no option.
    {id="melee", hub=false, mask=16777216, request_only=true, pressed={"wield_1"}},
    {id="ranged", hub=false, mask=33554432, request_only=true, pressed={"wield_2"}},
}
-- Actions a contextual grip request may hold instead of the grip's binding.
-- Reverse grip grace (user, 15 September evening): a grip press made while
-- the request says its hand is only approaching (support.approach, the hand
-- close to but not yet in the grip or holster zone) is held back for up to
-- REVERSE_GRACE_SECONDS. Still held when the hand arrives (support.acquire):
-- it takes the grip and the bound action never fires. Otherwise it goes to
-- its binding: late if still held, as a tap if already released. Requests
-- carry the input time as support.now.
Bindings.REVERSE_GRACE_SECONDS = 0.25
Bindings.REQUEST_ACTIONS = {unbound=0, alternate=2, blitz=512, pocketable=65536, stim=131072, device=262144,
    melee=16777216, ranged=33554432,
    -- Reach interactions: the grip interacts with what the hand reaches.
    interact=8}

-- The physical bit a contextual claim names. Only the grips were nameable,
-- which is all the virtual holsters and the two-hand grip need; any button may
-- be named now, so a claim can also suppress a control's own action for one
-- press. That is what the item radial needs and could not have
-- (docs/phase1/item-radial-2026-09-16.md). Axis directions are excluded: a
-- stick direction cannot hold a claim.
function Bindings.control_bit(id)
    if type(id)~='string' then return nil end
    for _,control in ipairs(Bindings.controls) do
        if control.id==id and not control.axis then return control.bit end
    end
end

local function atomic(action)
    return action.mask>0 and bit.band(action.mask,action.mask-1)==0
end
local function action_mask(id)
    for _,action in ipairs(Bindings.actions) do
        if action.id==id then return action.mask end
    end
end
local function legacy_mask(mod,control,hub)
    local selected=action_mask(mod and mod:get('vr_bind_'..control.id)) or action_mask(control.default)
    if hub then
        local override=mod and mod:get('vr_hub_bind_'..control.id)
        if override==nil then override=control.id=='right_grip' and 'inventory' or 'inherit' end
        selected=action_mask(override) or selected
    end
    return selected
end
local function legacy_controls(mod,action,hub)
    local controls=0
    for _,control in ipairs(Bindings.controls) do
        if not (action.physical_only and control.axis) and
            bit.band(legacy_mask(mod,control,hub),action.mask)~=0 then controls=bit.bor(controls,control.bit) end
    end
    return controls
end
local function valid_controls(value)
    return type(value)=='number' and value>=0 and value<=32767 and value==math.floor(value)
end

-- The 13 September layout change (crouch X, carried items Y) moves a saved
-- layout, once, only where both still sit exactly on the old defaults:
-- crouch on Y alone and both item actions on X alone. Every alpha.1 install
-- saved its per-action bindings on first launch, so a saved value cannot
-- tell an untouched default from a choice; a player who changed either of
-- the two, or already set up the new layout, keeps every binding as it is.
-- The older per-control settings are left alone too: installs that have
-- them converted them already, and a fresh conversion reads the new defaults.
local function swap_saved_xy(mod)
    if not mod or not mod.set or mod:get('vr_bindings_xy_swapped') then return end
    if mod:get('vr_action_bind_crouch')==16 and
            mod:get('vr_action_bind_cycle_pocketables')==8 and
            mod:get('vr_action_bind_device')==8 then
        mod:set('vr_action_bind_crouch',8)
        mod:set('vr_action_bind_cycle_pocketables',16)
        mod:set('vr_action_bind_device',16)
    end
    mod:set('vr_bindings_xy_swapped',true)
end
Bindings.swap_saved_xy=swap_saved_xy

-- One press may select several wield targets (a shared button: device and
-- item cycle, stim and ammo crate, quick wield and an item). The game applies
-- only one of several wield inputs, not a chosen one, so the scanner never came
-- out on the default Y. Such a press becomes a cycle over exactly the targets
-- it selects: device, pocketable, small pocketable, then the weapon when quick
-- wield is on the button (the item cycle selects all three item slots). Empty
-- slots are skipped; holding one of the steps moves to the next, anything else
-- starts at the first. The press keeps a single direct selector for the chosen
-- step. A single selector, and the item cycle alone without a device, keep
-- their stock behaviour. `inventory` holds the inventory component's
-- wielded_slot and slot_* item names ("not_equipped" when empty).
local QUICK_BIT, POCKETABLE_BIT, STIM_BIT, DEVICE_BIT, CYCLE_BIT = 16, 65536, 131072, 262144, 524288
local SELECTOR_BITS = QUICK_BIT + POCKETABLE_BIT + STIM_BIT + DEVICE_BIT + CYCLE_BIT
Bindings.SELECTOR_BITS = SELECTOR_BITS
function Bindings.wield_press(pressed, inventory)
    local selected = bit.band(pressed, SELECTOR_BITS)
    if not inventory or selected == 0 then return pressed end
    local function has(selector) return bit.band(selected, selector) ~= 0 end
    local function equipped(slot)
        local item = inventory[slot]
        return item ~= nil and item ~= "not_equipped"
    end
    local count = 0
    for _, selector in ipairs({QUICK_BIT, POCKETABLE_BIT, STIM_BIT, DEVICE_BIT, CYCLE_BIT}) do
        if has(selector) then count = count + 1 end
    end
    local cycle = has(CYCLE_BIT)
    if count == 1 and (not cycle or not equipped("slot_device")) then return pressed end
    local steps = {}
    for _, step in ipairs({{slot = "slot_device", selector = DEVICE_BIT},
            {slot = "slot_pocketable", selector = POCKETABLE_BIT},
            {slot = "slot_pocketable_small", selector = STIM_BIT}}) do
        if (cycle or has(step.selector)) and equipped(step.slot) then steps[#steps + 1] = step end
    end
    if has(QUICK_BIT) then steps[#steps + 1] = {weapon = true, selector = QUICK_BIT} end
    if #steps == 0 then return pressed end
    local wielded = inventory.wielded_slot
    local current
    for index, step in ipairs(steps) do
        if step.slot == wielded or
                (step.weapon and (wielded == "slot_primary" or wielded == "slot_secondary")) then
            current = index
        end
    end
    local target = current and steps[current % #steps + 1] or steps[1]
    return bit.bor(bit.band(pressed, bit.bnot(SELECTOR_BITS)), target.selector)
end

function Bindings.widgets(mod)
    swap_saved_xy(mod)
    local widgets,hub,gripping={},{},{}
    local function label(key) return mod and mod:localize(key) or key end
    for _,action in ipairs(Bindings.actions) do
        if atomic(action) and not action.request_only then
            local combat_key='vr_action_bind_'..action.id
            local combat=mod and mod:get(combat_key)
            if combat==nil then
                combat=legacy_controls(mod,action,false)
                if mod then mod:set(combat_key,combat) end
            end
            for _,context in ipairs({'combat','hub'}) do
                local is_hub=context=='hub'
                -- The hub has no combat, wielding or dodging: do not offer an
                -- override for an action the hub cannot perform.
                if is_hub and action.hub==false then break end
                local key=is_hub and 'vr_hub_action_bind_'..action.id or combat_key
                local current=mod and mod:get(key)
                if current==nil then
                    current=is_hub and legacy_controls(mod,action,true) or combat
                    if is_hub and current==legacy_controls(mod,action,false) then current=-1 end
                    if mod then mod:set(key,current) end
                end
                local options={localize=false,{text=label('vr_action_unbound'),value=0}}
                if is_hub then options[#options+1]={text=label('vr_action_inherit'),value=-1} end
                local known={[0]=true,[-1]=true}
                for _,control in ipairs(Bindings.controls) do
                    if not (action.physical_only and control.axis) then
                    options[#options+1]={text=label('vr_bind_'..control.id),value=control.bit}
                    known[control.bit]=true
                    end
                end
                -- Preserve existing aliases without silently dropping a control.
                -- Picking a single control later intentionally replaces that set.
                if valid_controls(current) and not known[current] and
                    not (action.physical_only and bit.band(current,30720)~=0) then
                    local labels={}
                    for _,control in ipairs(Bindings.controls) do
                        if bit.band(current,control.bit)~=0 then labels[#labels+1]=label('vr_bind_'..control.id) end
                    end
                    options[#options+1]={text=table.concat(labels,' / '),value=current}
                end
                local default=legacy_controls(nil,action,is_hub)
                if is_hub and default==legacy_controls(nil,action,false) then default=-1 end
                local target=is_hub and hub or widgets
                target[#target+1]={setting_id=key,title='vr_action_'..action.id,type='dropdown',
                    tooltip='controller_action_binding_description',default_value=default,options=options}
            end
            -- While a two-hand grip is held: every action starts on Same as
            -- combat, so the layer changes nothing until a control is chosen.
            local grip_options={localize=false,{text=label('vr_action_unbound'),value=0},
                {text=label('vr_action_inherit'),value=-1}}
            for _,control in ipairs(Bindings.controls) do
                if not (action.physical_only and control.axis) then
                    grip_options[#grip_options+1]={text=label('vr_bind_'..control.id),value=control.bit}
                end
            end
            gripping[#gripping+1]={setting_id='vr_grip_action_bind_'..action.id,title='vr_action_'..action.id,
                type='dropdown',tooltip='controller_action_binding_description',default_value=-1,options=grip_options}
        end
    end
    widgets[#widgets+1]={setting_id="controller_hub_bindings",type="group",sub_widgets=hub}
    widgets[#widgets+1]={setting_id="controller_grip_bindings",type="group",sub_widgets=gripping}
    return {setting_id="controller_bindings",type="group",sub_widgets=widgets}
end

function Bindings.install(mod)
    swap_saved_xy(mod)
    local api = {held=0,bindings={},revision=0,context="combat",
        wield_press=Bindings.wield_press,
        support_grip={held=false,pressed=false,released=false,cancelled=false}}
    local previous_physical, grip_claim = 0, nil
    local pending_press -- a held-back grip press: {bit, since}
    local previous_contributors=0
    local masks, resolved, grip_resolved, latched = {}, {}, {}, {}
    local dirty, blocked, active = true, 0, false
    local stick_held, stick_active = 0, false
    local stick_rearm = false
    local stick_generation
    for _,action in ipairs(Bindings.actions) do
        masks[action.id] = action.mask
        if action.pressed or action.held or action.released then
            api.bindings[#api.bindings+1] = {mask=action.mask,
                pressed=action.pressed or {},held=action.held or {},released=action.released or {}}
        end
    end
    local previous = mod.on_setting_changed
    mod.on_setting_changed = function(id)
        if previous then previous(id) end
        if type(id)=="string" and (id:sub(1,8)=="vr_bind_" or id:sub(1,12)=="vr_hub_bind_" or
                id:sub(1,15)=='vr_action_bind_' or id:sub(1,19)=='vr_hub_action_bind_' or
                id:sub(1,20)=='vr_grip_action_bind_' or id=="vr_turn_mode") then
            dirty=true
            api.revision=api.revision+1
        end
    end
    local selection_cache,grip_cache,selection_revision,selection_context={},{}
    local function refresh_selection()
        if selection_revision==api.revision and selection_context==api.context then return end
        for _,control in ipairs(Bindings.controls) do selection_cache[control.id]=0; grip_cache[control.id]=0 end
        for _,action in ipairs(Bindings.actions) do
            if atomic(action) and not action.request_only then
                local value=mod:get('vr_action_bind_'..action.id)
                if api.context=='hub' then
                    local hub_value=mod:get('vr_hub_action_bind_'..action.id)
                    if hub_value~=-1 then value=hub_value end
                end
                -- The grip layer applies in combat only (the hub has no guns).
                local grip_value=api.context~='hub' and mod:get('vr_grip_action_bind_'..action.id) or nil
                for _,control in ipairs(Bindings.controls) do
                    local assigned
                    if value==nil then
                        assigned=bit.band(legacy_mask(mod,control,api.context=='hub'),action.mask)~=0
                    else
                        assigned=valid_controls(value) and bit.band(value,control.bit)~=0
                    end
                    local grip_assigned=assigned
                    if valid_controls(grip_value) then grip_assigned=bit.band(grip_value,control.bit)~=0 end
                    if not (action.physical_only and control.axis) then
                        if assigned then selection_cache[control.id]=bit.bor(selection_cache[control.id],action.mask) end
                        if grip_assigned then grip_cache[control.id]=bit.bor(grip_cache[control.id],action.mask) end
                    end
                end
            end
        end
        selection_revision,selection_context=api.revision,api.context
    end
    local function selection(control)
        refresh_selection()
        return selection_cache[control.id]
    end
    local function grip_selection(control)
        refresh_selection()
        return grip_cache[control.id]
    end
    -- Prepare the profile before a HUD gesture claims the stick. Both the
    -- preclaim query and subsequent gameplay sample then share one revision.
    function api.prepare_context(mode)
        local context=mode=='hub' and 'hub' or 'combat'
        if context~=api.context then
            api.context=context;api.revision=api.revision+1
            dirty=true;stick_active=false;api.held=0
        end
    end
    function api.physical_hold(id,physical,mode)
        api.prepare_context(mode)
        local wanted=masks[id]
        if not wanted or wanted==0 then return false end
        -- Nothing held, which is most frames: no control can match, so the
        -- walk below is skipped (profile doc, the sampler gates).
        if (physical or 0)==0 then return false end
        for _,control in ipairs(Bindings.controls) do
            if not control.axis and bit.band(physical or 0,control.bit)~=0 and
                bit.band(selection(control),wanted)==wanted then return true end
        end
        return false
    end
    function api.controls_for_action(id)
        local wanted, controls = masks[id], {}
        if not wanted or wanted==0 then return controls end
        for _,control in ipairs(Bindings.controls) do
            local selected = selection(control)
            if (control.axis~="x" or mod:get("vr_turn_mode")=="off") and
                bit.band(selected,wanted)==wanted then controls[#controls+1]=control.id end
        end
        return controls
    end
    -- These selectors share the stock wield input list. Report overlap,
    -- without changing mappings or claiming equipment-aware fallback ordering.
    function api.wield_conflicts()
        local conflicts={}
        for _,control in ipairs(Bindings.controls) do
            if control.axis~='x' or mod:get('vr_turn_mode')=='off' then
                local selected=selection(control)
                local actions={}
                for _,id in ipairs({'quick_wield','pocketable','stim','device','cycle_pocketables'}) do
                    if bit.band(selected,masks[id])~=0 then actions[#actions+1]=id end
                end
                if #actions>1 then conflicts[#conflicts+1]={control=control.id,actions=actions} end
            end
        end
        return conflicts
    end
    if mod.command and mod.echo then
        mod:command('dtvr_binding_conflicts','Report overlapping weapon and item selectors in the current binding profile',function()
            local conflicts=api.wield_conflicts()
            if #conflicts==0 then
                mod:echo('No overlapping weapon or item selectors in %s bindings.',api.context)
            else
                local function label(key)return mod.localize and mod:localize(key) or key end
                for _,conflict in ipairs(conflicts) do
                    local names={}
                    for _,id in ipairs(conflict.actions) do names[#names+1]=label('vr_action_'..id) end
                    mod:echo('%s bindings: %s is assigned to %s. Each press steps through them in turn (device, ammo crate, stim, then weapon).',
                        api.context,label('vr_bind_'..conflict.control),table.concat(names,' / '))
                end
            end
        end)
    end
    -- Action mask the gestures hold this frame, over and above the bindings.
    -- Gestures OR into it; every sample consumes and clears it.
    api.forced = 0
    function api.sample(enabled, physical, stick_x, stick_y, stick_usable, generation, mode, support, exclusive_stick)
        api.prepare_context(mode)
        local reset_grip=dirty or enabled~=true or not active or
            generation~=stick_generation
        local grip=api.support_grip
        grip.held,grip.pressed,grip.released,grip.cancelled=false,false,false,false
        -- The eleven native channels occupy bits 0..10. Directional channels
        -- exist only here, so native input cannot impersonate a virtual shortcut.
        physical = bit.band(physical or 0,2047)
        if generation ~= stick_generation then
            -- A new publisher cancels the previous semantic hold. Do not emit
            -- an attack release from disappearance of its physical channels.
            stick_active=false; active=false; api.held=0
        end
        stick_generation = generation
        local axes_valid = enabled == true and stick_usable == true and
            type(stick_x)=="number" and type(stick_y)=="number" and
            stick_x>=-1 and stick_x<=1 and stick_y>=-1 and stick_y<=1
        -- An explicit HUD gesture owns every directional channel together.
        -- Ending/cancelling that claim cannot turn a still-deflected stick into
        -- a gameplay action, even if it changes sectors before reaching neutral.
        if exclusive_stick==true then stick_rearm=true end
        if stick_rearm and exclusive_stick~=true and axes_valid and
            math.max(math.abs(stick_x),math.abs(stick_y))<=0.25 then stick_rearm=false end
        axes_valid=axes_valid and not stick_rearm
        local cancelled_axes=0
        if stick_active and not axes_valid then
            for _,control in ipairs(Bindings.controls) do
                if control.axis and bit.band(stick_held,control.bit)~=0 then
                    cancelled_axes=bit.bor(cancelled_axes,latched[control.id] or resolved[control.id] or 0)
                end
            end
        end
        local next_stick = 0
        if axes_valid then
            for _,control in ipairs(Bindings.controls) do
                if control.axis and (control.axis~="x" or mod:get("vr_turn_mode")=="off") then
                    local value = (control.axis=="x" and stick_x or stick_y)*control.sign
                    local was_held = bit.band(stick_held,control.bit)~=0
                    local horizontal = math.abs(stick_x)>math.abs(stick_y)
                    local in_sector = (control.axis=="x" and horizontal) or
                        (control.axis=="y" and not horizontal)
                    if in_sector and value >= (was_held and 0.45 or 0.65) then
                        next_stick = bit.bor(next_stick,control.bit)
                    end
                end
            end
            if not stick_active then blocked=bit.bor(blocked,next_stick) end
        end
        stick_held, stick_active = next_stick, axes_valid
        physical = bit.bor(physical,next_stick)
        if dirty then
            -- Remap cancellation emits no physical release edge. Stock
            -- false-held action sequences retain their ordinary behavior.
            api.held=0
            for _,control in ipairs(Bindings.controls) do
                resolved[control.id] = selection(control)
                grip_resolved[control.id] = grip_selection(control)
                latched[control.id] = nil
            end
            blocked = physical -- No remap can turn an existing hold into a new action.
            dirty = false
        end
        if not enabled or not active then blocked=physical end
        active = enabled == true
        blocked = bit.band(blocked,physical)
        -- Only a fresh, unblocked physical grip may acquire contextual ownership.
        -- The caller supplies weapon/tracking identity and acquisition/retention
        -- tests; saved user bindings are never rewritten. No caller means the
        -- original mapper behavior, including ordinary keyboard coexistence.
        local request_bit=type(support)=='table' and Bindings.control_bit(support.control) or nil
        local request_mask=request_bit and Bindings.REQUEST_ACTIONS[support.action] or nil
        local request_valid=request_bit and request_mask~=nil and support.owner~=nil
        local cancelled_grip=0
        if grip_claim then
            local down=bit.band(physical,grip_claim.bit)~=0
            if reset_grip or not request_valid or support.owner~=grip_claim.owner or
                request_bit~=grip_claim.bit or request_mask~=grip_claim.mask or support.retain~=true then
                blocked=bit.bor(blocked,bit.band(physical,grip_claim.bit))
                cancelled_grip=grip_claim.mask
                grip.cancelled=true
                grip_claim=nil
            elseif not down and support.toggle==true then
                -- Toggle: letting go keeps the claim; the next press ends it.
                grip_claim.latched=true
            elseif not down then
                grip.released=true
                grip_claim=nil
            elseif grip_claim.latched and bit.band(previous_physical,grip_claim.bit)==0 then
                -- The ending press and its release stay out of the bound action.
                blocked=bit.bor(blocked,grip_claim.bit)
                grip.released=true
                grip_claim=nil
            end
        end
        -- Reverse grace: resolve a held-back press, or start one.
        local now=type(support)=='table' and type(support.now)=='number' and support.now or nil
        local held_back,tap_bit=0,0
        if pending_press then
            local down=bit.band(physical,pending_press.bit)~=0
            if reset_grip or not active then
                pending_press=nil
            elseif not down then
                tap_bit=pending_press.bit
                pending_press=nil
            elseif not grip_claim and request_valid and request_bit==pending_press.bit and
                    support.acquire==true and support.retain==true then
                grip_claim={bit=request_bit,mask=request_mask,owner=support.owner,layer=support.layer}
                grip.pressed=true
                pending_press=nil
            elseif not request_valid or support.approach~=true or not now or
                    now-pending_press.since>Bindings.REVERSE_GRACE_SECONDS then
                pending_press=nil -- Still held: it reaches its binding below, late.
            else
                held_back=pending_press.bit
            end
        end
        if not grip_claim and not pending_press and not reset_grip and active and request_valid and
            support.approach==true and support.acquire~=true and now and
            bit.band(physical,request_bit)~=0 and
            bit.band(bit.bor(blocked,previous_physical),request_bit)==0 then
            pending_press={bit=request_bit,since=now}
            held_back=request_bit
        end
        if not grip_claim and not reset_grip and active and request_valid and
            support.acquire==true and support.retain==true and
            bit.band(physical,request_bit)~=0 and
            bit.band(bit.bor(blocked,previous_physical),request_bit)==0 then
            grip_claim={bit=request_bit,mask=request_mask,owner=support.owner,layer=support.layer}
            grip.pressed=true
        end
        previous_physical=physical
        local next_held = 0
        local contributors,physical_releases=0,0
        if active then
            local available = bit.band(physical,bit.bnot(bit.bor(blocked,held_back)))
            -- A two-hand grip switches to the while-gripping bindings. Each
            -- control keeps the layer it was pressed in until it is released,
            -- so taking or leaving the grip never changes an action mid-press.
            local layer = grip_claim and grip_claim.layer=='gripping' and grip_resolved or resolved
            for _,control in ipairs(Bindings.controls) do
                if not reset_grip and bit.band(previous_contributors,control.bit)~=0 and
                    bit.band(physical,control.bit)==0 and (not control.axis or axes_valid) then
                    physical_releases=bit.bor(physical_releases,latched[control.id] or resolved[control.id])
                end
                if bit.band(available,control.bit)~=0 and
                    (not grip_claim or control.bit~=grip_claim.bit) then
                    if latched[control.id]==nil then latched[control.id]=layer[control.id] end
                    next_held = bit.bor(next_held,latched[control.id])
                    contributors=bit.bor(contributors,control.bit)
                else
                    latched[control.id]=nil
                end
            end
            if grip_claim then
                next_held=bit.bor(next_held,grip_claim.mask)
                grip.held=true
            end
            -- A gesture may hold an action no control is bound to (inspect by
            -- bringing the weapon to the face, push to talk with a hand at the
            -- ear). Each gesture ORs its action into api.forced before the
            -- sample and the sample clears it, so gestures never clobber one
            -- another and one that stops contributing lets go. The edges
            -- follow from the ordinary held comparison below, so a gesture
            -- that ends releases the action like a button.
            if type(api.forced)=='number' and api.forced~=0 then
                next_held=bit.bor(next_held,api.forced)
            end
            -- A held-back press released before the hand arrived: its bound
            -- action for this frame only (released on the next).
            if tap_bit~=0 then
                for _,control in ipairs(Bindings.controls) do
                    if control.bit==tap_bit then next_held=bit.bor(next_held,resolved[control.id] or 0) end
                end
            end
        else
            for _,control in ipairs(Bindings.controls) do latched[control.id]=nil end
        end
        previous_contributors=contributors
        local pressed = bit.band(next_held,bit.bnot(api.held))
        -- Losing the stick's tracking/validity cancels its contribution. Keep
        -- semantic history for healthy button aliases so they do not retrigger.
        -- A cancelled contributor must not swallow a healthy alias's real
        -- release in the same frame. Cancelled-only actions still emit no edge.
        local cancelled=bit.band(bit.bor(cancelled_axes,cancelled_grip),bit.bnot(physical_releases))
        local released = bit.band(api.held,bit.bnot(next_held),bit.bnot(cancelled))
        api.held = next_held
        api.forced = 0
        return pressed,next_held,released
    end
    return api
end

return Bindings
