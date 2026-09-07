-- Optional local-source contract. Executes literal stock input tables and the
-- stock parser; action kind/start-input metadata is read without running assets.
local root,support_path,bindings_path,manifest=assert(arg[1]),assert(arg[2]),assert(arg[3]),assert(arg[4])
local function read(path) local f=assert(io.open(path,'r')); local s=f:read('*a'); f:close(); return s end
local Support,Bindings=dofile(support_path),dofile(bindings_path)
bit=require('bit')
local parser_source=read(root..'/scripts/extension_systems/action_input/action_input_parser.lua')
local first=assert(parser_source:find('ActionInputParser._evaluate_element =',1,true))
local last=assert(parser_source:find('\nActionInputParser._progress_input_sequence =',first,true))
local Parser={}
setfenv(assert(loadstring(parser_source:sub(first,last-1))),
    setmetatable({ActionInputParser=Parser,ELEMENT_START_T=3},{__index=_G}))()
local supported,total,lasgun=0,0,false
for path in io.lines(manifest) do
    path=path:gsub('\r','')
    local text=read(root..'/'..path)
    local a=assert(text:find('weapon_template.action_inputs =',1,true),path)
    local b=assert(text:find('\nweapon_template%.[a-z_]+%s*=',a+1),path)
    local inherited=text:find('\ntable.add_missing(',a,true)
    if inherited and inherited<b then b=inherited end
    local env=setmetatable({weapon_template={},wield_inputs={}}, {__index=_G})
    local inputs=setfenv(assert(loadstring(text:sub(a,b-1)..'\nreturn weapon_template.action_inputs',path)),env)()
    local actions={}
    a=assert(text:find('weapon_template.actions =',1,true),path)
    b=text:find('\nweapon_template%.[a-z_]+%s*=',a+1) or #text
    for name,body in text:sub(a,b-1):gmatch('\n\t([%w_]+) = (%b{})') do
        actions[name]={kind=body:match('\n\t\tkind = "([^"]+)"'),
            start_input=body:match('\n\t\tstart_input = "([^"]+)"')}
    end
    local alternate=text:find('weapon_template.alternate_fire_settings = {',1,true) and {} or nil
    local template={actions=actions,action_inputs=inputs,alternate_fire_settings=alternate}
    total=total+1
    if path:find('/force_staffs/',1,true) or path:find('/plasma_rifles/',1,true) then
        assert(not Support.ads_supported(template),path..': charging secondary admitted as ADS')
    end
    if Support.ads_supported(template) then
        supported=supported+1
        if path:find('/lasgun_p3_m2.lua',1,true) then lasgun=true end
        local mapper=Bindings.install({get=function() end})
        local request={control='left_grip',owner={},acquire=true,retain=true,action='alternate'}
        local function sample(bits)
            local p,h,r=mapper.sample(true,bits,0,0,true,1,'combat',request)
            return {action_two_pressed=bit.band(p,2)~=0,action_two_hold=bit.band(h,2)~=0,
                action_two_release=bit.band(r,2)~=0,toggle_ads=false}
        end
        sample(0)
        local entering=sample(512)
        sample(514)
        local alias_held=sample(2)
        local leaving=sample(0)
        local checked_aim,checked_unaim=false,false
        for _,action in pairs(actions) do
            local input=inputs[action.start_input]
            if input and input.input_sequence and (action.kind=='aim' or action.kind=='unaim') then
                local step=input.input_sequence[1]
                local failed,done=Parser:_evaluate_element(step,action.kind=='aim' and entering or leaving,{true,1,0},0)
                assert(not failed and done,path..': stock '..action.kind..' rejected contextual hold/release')
                if action.kind=='unaim' then
                    local _,alias_exits=Parser:_evaluate_element(step,alias_held,{true,1,0},0)
                    assert(not alias_exits,path..': support release cancelled an independent aim alias')
                    checked_unaim=true
                else checked_aim=true end
            end
        end
        assert(checked_aim and checked_unaim,path..': missing executed aim/unaim pair')
    end
end
assert(lasgun and supported>0)
print(string.format('two_hand_stock=pass templates=%d supported_ads=%d excluded=%d',total,supported,total-supported))
print('LIMIT: literal input/parser admission; not full action chains, live accuracy, server or worn acceptance')
