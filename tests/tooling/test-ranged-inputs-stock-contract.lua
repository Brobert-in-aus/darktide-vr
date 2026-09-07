-- Execute each ranged template's literal input table and stock parser elements
-- using real VR binding output. Pass a newline manifest from the source audit.
local root,bindings_path,manifest=assert(arg[1]),assert(arg[2]),assert(arg[3])
local function read(path) local f=assert(io.open(path,'r')); local s=f:read('*all'); f:close(); return s end
local parser_source=read(root..'/scripts/extension_systems/action_input/action_input_parser.lua')
local a=assert(parser_source:find('ActionInputParser._evaluate_element =',1,true))
local b=assert(parser_source:find('\nActionInputParser._progress_input_sequence =',a,true))
local parser={}
setfenv(assert(loadstring(parser_source:sub(a,b-1))),
    setmetatable({ActionInputParser=parser,ELEMENT_START_T=3},{__index=_G}))()
local Bindings=dofile(bindings_path)
bit=require('bit')
local raw_cases={}
for prior=0,15 do
    for physical=0,15 do
        local mapper=Bindings.install({get=function() return nil end})
        mapper.sample(true,0,0,0,true,1,'combat')
        mapper.sample(true,prior,0,0,true,1,'combat')
        local pressed,held,released=mapper.sample(true,physical,0,0,true,1,'combat')
        local raw={}
        for _,binding in ipairs(Bindings.actions) do
            for _,phase in ipairs({{'pressed',pressed},{'held',held},{'released',released}}) do
                for _,input in ipairs(binding[phase[1]] or {}) do
                    raw[input]=bit.band(phase[2],binding.mask)~=0
                end
            end
        end
        raw_cases[#raw_cases+1]=raw
    end
end
local supported={}
for _,binding in ipairs(Bindings.actions) do
    for _,phase in ipairs({'pressed','held','released'}) do
        for _,name in ipairs(binding[phase] or {}) do supported[name]=true end
    end
end
local template_count,element_count=0,0
for path in io.lines(manifest) do
    path=path:gsub('\r','')
    local text=read(root..'/'..path)
    local first=assert(text:find('weapon_template.action_inputs =',1,true),path)
    local last=assert(text:find('\nweapon_template%.[a-z_]+%s*=',first+1),path)
    local inherited=text:find('\ntable.add_missing(',first,true)
    if inherited and inherited<last then last=inherited end
    local env=setmetatable({weapon_template={},wield_inputs={}}, {__index=_G})
    local inputs=setfenv(assert(loadstring(text:sub(first,last-1)..'\nreturn weapon_template.action_inputs',path)),env)()
    for action_name,action in pairs(inputs) do
        for _,element in ipairs(action.input_sequence or {}) do
            local input=element.input
            if input then
                assert(supported[input],path..': '..input..' missing binding channel')
                if element.hold_input then assert(supported[element.hold_input]) end
                -- All fire/alternate/special/reload channels have physical
                -- defaults. Inspection and explicit wielding are separate UI
                -- controls and are checked for mapping only.
                if input:find('^action_[ot]') or input:find('^weapon_extra_') or input:find('^weapon_reload_') then
                    for _,toggle in ipairs({false,true}) do
                        local completed=false
                        for _,raw in ipairs(raw_cases) do
                            if element.input_setting then raw[element.input_setting.setting]=toggle end
                            local t=element.duration or 0
                            local failed,done=parser:_evaluate_element(element,raw,{true,1,0},t)
                            if not failed and done then completed=true; break end
                        end
                        assert(completed,path..': no VR transition satisfies '..action_name..'/'..input..' toggle='..tostring(toggle))
                    end
                    element_count=element_count+1
                end
            end
        end
    end
    template_count=template_count+1
end
assert(template_count>0)
print('PASS ranged stock inputs: '..template_count..' actual template tables, '..element_count..' combat input elements, hold/toggle ADS, 256 real VR transitions')
print('LIMIT: element admission, not full action hierarchy, ammunition/charge availability or live firing')
