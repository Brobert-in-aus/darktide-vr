-- Native bits remain physical channels. Resolve gameplay semantics here so
-- the options and delivery share one catalog; menu pointer bindings stay native.
local Bindings = {}
Bindings.controls = {
    {id="right_trigger", bit=1, default="primary"},
    {id="left_trigger", bit=2, default="alternate"},
    {id="right_grip", bit=4, default="special"},
    {id="left_grip", bit=512, default="blitz"},
    {id="x", bit=8, default="interact_reload"},
    {id="y", bit=16, default="quick_wield"},
    {id="a", bit=32, default="jump_dodge"},
    {id="b", bit=64, default="crouch"},
    {id="l3", bit=128, default="sprint"},
    {id="r3", bit=256, default="tag"},
    {id="menu", bit=1024, default="menu"},
    {id="right_stick_up", bit=2048, default="unbound", axis="y", sign=1},
    {id="right_stick_down", bit=4096, default="unbound", axis="y", sign=-1},
    {id="right_stick_left", bit=8192, default="unbound", axis="x", sign=-1},
    {id="right_stick_right", bit=16384, default="unbound", axis="x", sign=1},
}
Bindings.actions = {
    {id="unbound", mask=0},
    {id="primary", mask=1, pressed={"action_one_pressed"}, held={"action_one_hold"}, released={"action_one_release"}},
    {id="alternate", mask=2, pressed={"action_two_pressed"}, held={"action_two_hold"}, released={"action_two_release"}},
    {id="special", mask=4, pressed={"weapon_extra_pressed"}, held={"weapon_extra_hold"}, released={"weapon_extra_release"}},
    {id="interact", mask=8, pressed={"interact_pressed"}, held={"interact_hold"}},
    {id="reload", mask=4096, pressed={"weapon_reload_pressed"}, held={"weapon_reload_hold"}},
    {id="interact_reload", mask=4104},
    {id="quick_wield", mask=16, pressed={"quick_wield"}},
    {id="jump", mask=32, pressed={"jump"}, held={"jump_held"}},
    {id="dodge", mask=8192, pressed={"dodge"}},
    {id="jump_dodge", mask=8224},
    {id="crouch", mask=64, pressed={"crouch"}, held={"crouching"}},
    {id="sprint", mask=128, pressed={"sprint"}, held={"sprinting"}},
    {id="tag", mask=256},
    {id="blitz", mask=512, pressed={"grenade_ability_pressed"}, held={"grenade_ability_hold"}, released={"grenade_ability_release"}},
    {id="combat_ability", mask=2048, pressed={"combat_ability_pressed"}, held={"combat_ability_hold"}, released={"combat_ability_release"}},
    {id="inspect", mask=16384, held={"weapon_inspect_hold"}},
    {id="menu", mask=1024},
    {id="inventory", mask=32768},
    {id="pocketable", mask=65536, pressed={"wield_3"}},
    {id="stim", mask=131072, pressed={"wield_4"}},
    {id="device", mask=262144, pressed={"wield_5"}},
    {id="cycle_pocketables", mask=524288, pressed={"wield_3_gamepad"}},
    {id="inspect_target", mask=1048576, pressed={"interact_inspect_pressed"}},
    {id="tactical_overlay", mask=2097152},
}

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
        if bit.band(legacy_mask(mod,control,hub),action.mask)~=0 then controls=bit.bor(controls,control.bit) end
    end
    return controls
end
local function valid_controls(value)
    return type(value)=='number' and value>=0 and value<=32767 and value==math.floor(value)
end

function Bindings.widgets(mod)
    local widgets,hub={},{}
    local function label(key) return mod and mod:localize(key) or key end
    for _,action in ipairs(Bindings.actions) do
        if atomic(action) then
            local combat_key='vr_action_bind_'..action.id
            local combat=mod and mod:get(combat_key)
            if combat==nil then
                combat=legacy_controls(mod,action,false)
                if mod then mod:set(combat_key,combat) end
            end
            for _,context in ipairs({'combat','hub'}) do
                local is_hub=context=='hub'
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
                    options[#options+1]={text=label('vr_bind_'..control.id),value=control.bit}
                    known[control.bit]=true
                end
                -- Preserve existing aliases without silently dropping a control.
                -- Picking a single control later intentionally replaces that set.
                if valid_controls(current) and not known[current] then
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
        end
    end
    widgets[#widgets+1]={setting_id="controller_hub_bindings",type="group",sub_widgets=hub}
    return {setting_id="controller_bindings",type="group",sub_widgets=widgets}
end

function Bindings.install(mod)
    local api = {held=0,bindings={},revision=0,context="combat",
        support_grip={held=false,pressed=false,released=false,cancelled=false}}
    local previous_physical, grip_claim = 0, nil
    local previous_contributors=0
    local masks, resolved = {}, {}
    local dirty, blocked, active = true, 0, false
    local stick_held, stick_active = 0, false
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
                id:sub(1,15)=='vr_action_bind_' or id:sub(1,19)=='vr_hub_action_bind_' or id=="vr_turn_mode") then
            dirty=true
            api.revision=api.revision+1
        end
    end
    local selection_cache,selection_revision,selection_context={}
    local function refresh_selection()
        if selection_revision==api.revision and selection_context==api.context then return end
        for _,control in ipairs(Bindings.controls) do selection_cache[control.id]=0 end
        for _,action in ipairs(Bindings.actions) do
            if atomic(action) then
                local value=mod:get('vr_action_bind_'..action.id)
                if api.context=='hub' then
                    local hub_value=mod:get('vr_hub_action_bind_'..action.id)
                    if hub_value~=-1 then value=hub_value end
                end
                for _,control in ipairs(Bindings.controls) do
                    local assigned
                    if value==nil then
                        assigned=bit.band(legacy_mask(mod,control,api.context=='hub'),action.mask)~=0
                    else
                        assigned=valid_controls(value) and bit.band(value,control.bit)~=0
                    end
                    if assigned then selection_cache[control.id]=bit.bor(selection_cache[control.id],action.mask) end
                end
            end
        end
        selection_revision,selection_context=api.revision,api.context
    end
    local function selection(control)
        refresh_selection()
        return selection_cache[control.id]
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
                    mod:echo('%s bindings: %s is assigned to %s. Simultaneous wield requests can select only one.',
                        api.context,label('vr_bind_'..conflict.control),table.concat(names,' / '))
                end
            end
        end)
    end
    function api.sample(enabled, physical, stick_x, stick_y, stick_usable, generation, mode, support)
        local context=mode=="hub" and "hub" or "combat"
        local reset_grip=dirty or enabled~=true or not active or
            generation~=stick_generation or context~=api.context
        local grip=api.support_grip
        grip.held,grip.pressed,grip.released,grip.cancelled=false,false,false,false
        if context~=api.context then
            api.context=context; api.revision=api.revision+1
            dirty=true; stick_active=false
            -- Cancel old context state without synthesizing release edges.
            -- Stock actions may still react to held=false. Physical inputs
            -- must return neutral before reuse.
            api.held=0
        end
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
        local cancelled_axes=0
        if stick_active and not axes_valid then
            for _,control in ipairs(Bindings.controls) do
                if control.axis and bit.band(stick_held,control.bit)~=0 then
                    cancelled_axes=bit.bor(cancelled_axes,resolved[control.id] or 0)
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
        local request_bit=type(support)=='table' and
            (support.control=='left_grip' and 512 or support.control=='right_grip' and 4) or nil
        local request_mask=request_bit and
            (support.action=='alternate' and 2 or support.action=='unbound' and 0) or nil
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
            elseif not down then
                grip.released=true
                grip_claim=nil
            end
        end
        if not grip_claim and not reset_grip and active and request_valid and
            support.acquire==true and support.retain==true and
            bit.band(physical,request_bit)~=0 and
            bit.band(bit.bor(blocked,previous_physical),request_bit)==0 then
            grip_claim={bit=request_bit,mask=request_mask,owner=support.owner}
            grip.pressed=true
        end
        previous_physical=physical
        local next_held = 0
        local contributors,physical_releases=0,0
        if active then
            local available = bit.band(physical,bit.bnot(blocked))
            for _,control in ipairs(Bindings.controls) do
                if not reset_grip and bit.band(previous_contributors,control.bit)~=0 and
                    bit.band(physical,control.bit)==0 and (not control.axis or axes_valid) then
                    physical_releases=bit.bor(physical_releases,resolved[control.id])
                end
                if bit.band(available,control.bit)~=0 and
                    (not grip_claim or control.bit~=grip_claim.bit) then
                    next_held = bit.bor(next_held,resolved[control.id])
                    contributors=bit.bor(contributors,control.bit)
                end
            end
            if grip_claim then
                next_held=bit.bor(next_held,grip_claim.mask)
                grip.held=true
            end
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
        return pressed,next_held,released
    end
    return api
end

return Bindings
