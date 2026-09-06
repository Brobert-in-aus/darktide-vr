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
    return {setting_id="controller_bindings",type="group",sub_widgets=widgets}
end

function Bindings.install(mod)
    local api = {held=0,bindings={},revision=0}
    local masks, resolved = {}, {}
    local dirty, blocked, active = true, 0, false
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
        if type(id)=="string" and id:sub(1,8)=="vr_bind_" then
            dirty=true
            api.revision=api.revision+1
        end
    end
    function api.controls_for_action(id)
        local wanted, controls = masks[id], {}
        if not wanted or wanted==0 then return controls end
        for _,control in ipairs(Bindings.controls) do
            local selected = masks[mod:get("vr_bind_"..control.id)] or masks[control.default]
            if bit.band(selected,wanted)==wanted then controls[#controls+1]=control.id end
        end
        return controls
    end
    function api.sample(enabled, physical)
        physical = physical or 0
        if dirty then
            for _,control in ipairs(Bindings.controls) do
                local requested = mod:get("vr_bind_"..control.id)
                resolved[control.id] = masks[requested] or masks[control.default]
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
        local released = bit.band(api.held,bit.bnot(next_held))
        api.held = next_held
        return pressed,next_held,released
    end
    return api
end

return Bindings
