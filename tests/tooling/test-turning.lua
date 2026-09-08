local Turning=dofile(arg[1])
local settings={}
local mod={get=function(_,key) return settings[key] end}
local api=Turning.install(mod)
local t,gen,recenter,context=0,1,1,{}
local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a).." ~= "..tostring(b)) end
local function sample(x,enabled,usable,dt,y)
    t=t+(dt or .01)
    return api.sample(enabled~=false,x,y or 0,usable~=false,gen,recenter,context,t)
end
near(sample(1),0) -- Never inherit a deflected stick on entry.
near(sample(0),0)
near(sample(1),-math.pi/200) -- Default 90 deg/s, full right.
near(api.sample(true,1,0,true,gen,recenter,context,t),0) -- Same time is not integrated twice.
near(sample(-1),math.pi/200)
near(sample(.625),-math.pi/400)
near(sample(.25),0)
near(sample(1,false),0)
near(sample(1),0)
near(sample(0),0)
near(sample(1),-math.pi/200)
near(sample(1,true,false),0)
near(sample(1),0)
near(sample(0),0)
gen=2; near(sample(1),0)
near(sample(0),0)
recenter=2; near(sample(1),0)
near(sample(0),0)
context={}; near(sample(1),0)
near(sample(0),0)
near(sample(1,true,true,.5),0) -- A hitch cannot cause a large turn.
near(sample(1),0)
near(sample(0),0)
near(sample(0/0),0); near(sample(1),0)
near(sample(0),0)
near(sample(math.huge),0); near(sample(1),0)
near(sample(0),0)
settings.vr_turn_mode="snap45"
near(sample(1),0); near(sample(0),0)
near(sample(.64),0); near(sample(.65),-math.pi/4)
near(sample(1),0); near(sample(-1),0) -- No opposite snap without neutral.
near(sample(0),0); near(sample(-1),math.pi/4)
settings.vr_turn_mode="snap90"
near(sample(-1),0); near(sample(0),0); near(sample(1),-math.pi/2)
settings.vr_turn_mode="off"
near(sample(0),0); near(sample(1),0)
settings.vr_turn_mode="smooth"; settings.vr_turn_speed=180
near(sample(1),0); near(sample(0),0); near(sample(1),-math.pi/100)
settings.vr_turn_speed=0/0
near(sample(1),0); near(sample(0),0); near(sample(1),-math.pi/200)

-- Frame-rate-independent integration for one second at full deflection.
for _,hz in ipairs({30,60,120}) do
    api=Turning.install(mod); t=0
    sample(0)
    local total=0
    for i=1,hz do total=total+sample(1,true,true,1/hz) end
    near(total,-math.pi/2)
end
local text=dofile(arg[2])
-- Check both turn modes against the actual shortcut mapper around the full
-- stick circle. No direction may turn and fire a vertical shortcut together.
bit=require('bit')
local Bindings=dofile(assert(arg[3]))
local sector_mod={get=function(_,key)
    if key=='vr_bind_right_stick_up' or key=='vr_bind_right_stick_down' then return 'combat_ability' end
    return settings[key]
end}
for _,mode in ipairs({'smooth','snap45','snap90'}) do
    settings.vr_turn_mode=mode
    for degrees=0,719 do
        local angle=math.rad(degrees/2)
        local x,y=math.cos(angle),math.sin(angle)
        local turns,shortcuts=Turning.install(sector_mod),Bindings.install(sector_mod)
        turns.sample(true,0,0,true,1,1,context,0)
        shortcuts.sample(true,0,0,0,true,1)
        local delta=turns.sample(true,x,y,true,1,1,context,.01)
        local pressed=shortcuts.sample(true,0,x,y,true,1)
        assert(delta==0 or pressed==0,'Turning overlapped a vertical shortcut')
        if math.abs(x)<=math.abs(y) then near(delta,0) end
        if math.abs(x)>math.abs(y) then assert(pressed==0) end
    end
end
settings.vr_turn_mode='snap45';api=Turning.install(mod);t=0
near(sample(0),0)
near(sample(.7,true,true,.01,.7),0) -- Exact 45 degrees goes to up/down.
near(sample(.71,true,true,.01,.7),-math.pi/4)
near(sample(0,true,true,.01,1),0)
near(sample(-1),0) -- Up was not neutral; cannot rearm another snap.
near(sample(0),0);near(sample(-1),math.pi/4)
near(sample(0),0);near(sample(1,true,true,.01,0/0),0)
near(sample(1),0) -- Invalid Y cannot retain the armed state.
for _,widget in ipairs(Turning.widgets().sub_widgets) do
    assert(text[widget.setting_id].en and text[widget.setting_id.."_description"].en)
    for _,option in ipairs(widget.options or {}) do assert(text[option.text].en) end
end
print("turning=pass smooth snap neutral tracking context clock settings")
