-- Optional cached-source evidence: raw selector precedence, not mission behavior.
local root,bindings_path=assert(arg[1]),assert(arg[2])
bit=require('bit')
local path=root..'/scripts/extension_systems/action_input/action_input_parser.lua'
local file=assert(io.open(path,'r'));local source=file:read('*a');file:close()
local first=assert(source:find('ActionInputParser._evaluate_input =',1,true))
local last=assert(source:find('\nActionInputParser._progress_input_sequence =',first,true))
local Parser={}
setfenv(assert(loadstring(source:sub(first,last-1),'@'..path)),
    setmetatable({ActionInputParser=Parser},{__index=_G}))()
local settings={vr_action_bind_device=8,vr_action_bind_cycle_pocketables=8,
    vr_action_bind_interact=0,vr_action_bind_reload=0}
local mod={get=function(_,key)return settings[key] end}
local mapper=dofile(bindings_path).install(mod)
local function press(control)
    mapper.sample(true,0,0,0,true,1,'combat')
    local pressed=mapper.sample(true,control,0,0,true,1,'combat')
    local values={}
    for _,binding in ipairs(mapper.bindings) do
        for _,name in ipairs(binding.pressed) do values[name]=bit.band(pressed,binding.mask)~=0 end
    end
    return values
end
local input=press(8)
assert(input.wield_5 and input.wield_3_gamepad)
local cycle={input='wield_3_gamepad',value=true}
local device={input='wield_5',value=true}
local parser=setmetatable({},{__index=Parser})
local valid,selected=parser:_evaluate_input({inputs={cycle,device}},input)
assert(valid and selected=='wield_3_gamepad')
valid,selected=parser:_evaluate_input({inputs={device,cycle}},input)
assert(valid and selected=='wield_5')
-- Independent controls remove the raw-input ordering ambiguity.
settings.vr_action_bind_cycle_pocketables=16
mod.on_setting_changed('vr_action_bind_cycle_pocketables')
input=press(8)
assert(input.wield_5 and not input.wield_3_gamepad)
valid,selected=parser:_evaluate_input({inputs={cycle,device}},input)
assert(valid and selected=='wield_5')
input=press(16)
assert(input.wield_3_gamepad and not input.wield_5)
valid,selected=parser:_evaluate_input({inputs={device,cycle}},input)
assert(valid and selected=='wield_3_gamepad')
print('wield_overlap_stock=pass simultaneous selectors follow array order; separate selectors are unambiguous')
print('LIMIT: no equipment eligibility, queue/weapon execution, network or worn mission acceptance')
