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
}

function Bindings.widgets()
    local widgets = {}
    for _,control in ipairs(Bindings.controls) do
        local options = {}
        for _,action in ipairs(Bindings.actions) do
            options[#options+1] = {text="vr_action_"..action.id,value=action.id}
        end
        widgets[#widgets+1] = {setting_id="vr_bind_"..control.id,type="dropdown",
            default_value=control.default,options=options}
    end
    local hub = {}
    for _,control in ipairs(Bindings.controls) do
        local options = {{text="vr_action_inherit",value="inherit"}}
        for _,action in ipairs(Bindings.actions) do
            options[#options+1]={text="vr_action_"..action.id,value=action.id}
        end
        hub[#hub+1]={setting_id="vr_hub_bind_"..control.id,type="dropdown",
            default_value=control.id=="right_grip" and "inventory" or "inherit",options=options}
    end
    widgets[#widgets+1]={setting_id="controller_hub_bindings",type="group",sub_widgets=hub}
    return {setting_id="controller_bindings",type="group",sub_widgets=widgets}
end

function Bindings.install(mod)
    local api = {held=0,bindings={},revision=0,context="combat"}
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
        if type(id)=="string" and (id:sub(1,8)=="vr_bind_" or id:sub(1,12)=="vr_hub_bind_" or id=="vr_turn_mode") then
            dirty=true
            api.revision=api.revision+1
        end
    end
    local function selection(control)
        local selected=masks[mod:get("vr_bind_"..control.id)] or masks[control.default]
        if api.context=="hub" then
            local override=mod:get("vr_hub_bind_"..control.id)
            if override==nil then override=control.id=="right_grip" and "inventory" or "inherit" end
            selected=masks[override] or selected
        end
        return selected
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
    function api.sample(enabled, physical, stick_x, stick_y, stick_usable, generation, mode)
        local context=mode=="hub" and "hub" or "combat"
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
                    if value >= (was_held and 0.45 or 0.65) then
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
        local next_held = 0
        if active then
            local available = bit.band(physical,bit.bnot(blocked))
            for _,control in ipairs(Bindings.controls) do
                if bit.band(available,control.bit)~=0 then
                    next_held = bit.bor(next_held,resolved[control.id])
                end
            end
        end
        local pressed = bit.band(next_held,bit.bnot(api.held))
        -- Losing the stick's tracking/validity cancels its contribution. Keep
        -- semantic history for healthy button aliases so they do not retrigger.
        local released = bit.band(api.held,bit.bnot(next_held),bit.bnot(cancelled_axes))
        api.held = next_held
        return pressed,next_held,released
    end
    return api
end

return Bindings
