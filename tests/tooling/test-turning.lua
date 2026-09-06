local Turning=dofile(arg[1])
local settings={}
local mod={get=function(_,key) return settings[key] end}
local api=Turning.install(mod)
local t,gen,recenter,context=0,1,1,{}
local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a).." ~= "..tostring(b)) end
local function sample(x,enabled,usable,dt)
    t=t+(dt or .01)
    return api.sample(enabled~=false,x,usable~=false,gen,recenter,context,t)
end
near(sample(1),0) -- Never inherit a deflected stick on entry.
near(sample(0),0)
near(sample(1),-math.pi/200) -- Default 90 deg/s, full right.
near(api.sample(true,1,true,gen,recenter,context,t),0) -- Same time is not integrated twice.
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
for _,widget in ipairs(Turning.widgets().sub_widgets) do
    assert(text[widget.setting_id].en and text[widget.setting_id.."_description"].en)
    for _,option in ipairs(widget.options or {}) do assert(text[option.text].en) end
end
print("turning=pass smooth snap neutral tracking context clock settings")
