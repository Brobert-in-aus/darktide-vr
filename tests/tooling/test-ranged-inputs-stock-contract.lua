-- Execute each ranged template's literal input table and stock parser elements
-- using real VR binding output. Pass a newline manifest from the source audit.
-- Optional fourth argument: a locally reviewed Lua table of saved bindings.
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
local settings=arg[4] and dofile(arg[4]) or {}
assert(type(settings)=='table','binding settings must be a table')
local function mapper_new() return Bindings.install({get=function(_,key)return settings[key]end}) end
local resolved=mapper_new()
resolved.sample(true,0,0,0,true,1,'combat')
local selected,seen={},{}
for _,action in ipairs({'primary','alternate','special','reload'}) do
    local controls=resolved.controls_for_action(action)
    assert(#controls>0,'combat action has no controller route: '..action)
    local id=controls[1]
    print('ranged_input_route '..action..'='..id)
    if not seen[id] then
        local found
        for _,control in ipairs(Bindings.controls) do if control.id==id then found=control;break end end
        selected[#selected+1]=assert(found,'unknown selected control')
        seen[id]=true
    end
end
-- Four combat actions need at most four representative controls. Enumerate
-- physically possible combinations, including stick sectors after remapping.
-- Aliases are not an exhaustive-controller test; each action needs one route.
local physical_states={}
for mask=0,2^#selected-1 do
    local physical,x,y,valid=0,0,0,true
    for index,control in ipairs(selected) do
        if bit.band(mask,2^(index-1))~=0 then
            if control.axis=='x' then
                if x~=0 and x~=control.sign then valid=false end
                x=control.sign
            elseif control.axis=='y' then
                if y~=0 and y~=control.sign then valid=false end
                y=control.sign
            else physical=bit.bor(physical,control.bit) end
        end
    end
    if valid then
        if x~=0 and y~=0 then x=x/math.sqrt(2);y=y/math.sqrt(2) end
        physical_states[#physical_states+1]={physical,x,y}
    end
end
local function sample(mapper,state)
    return mapper.sample(true,state[1],state[2],state[3],true,1,'combat')
end
local raw_cases={}
for _,prior in ipairs(physical_states) do
    for _,physical in ipairs(physical_states) do
        local mapper=mapper_new()
        mapper.sample(true,0,0,0,true,1,'combat')
        sample(mapper,prior)
        local pressed,held,released=sample(mapper,physical)
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
local template_count,element_count,timed_count=0,0,0
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
                -- Fire/alternate/special/reload use the selected physical
                -- profile. Inspection and explicit wielding are separate UI
                -- controls and are checked for mapping only.
                if input:find('^action_[ot]') or input:find('^weapon_extra_') or input:find('^weapon_reload_') then
                    for _,toggle in ipairs({false,true}) do
                        local completed=false
                        for _,raw in ipairs(raw_cases) do
                            if element.input_setting then raw[element.input_setting.setting]=toggle end
                            local t=element.duration or 0
                            -- At the deadline stock duration elements complete
                            -- regardless of has_input. First require admission
                            -- with this real mapper state at interval start.
                            local initial_failed=element.duration and
                                parser:_evaluate_element(element,raw,{true,1,0},0)
                            if not initial_failed then
                                local failed,done=parser:_evaluate_element(element,raw,{true,1,0},t)
                                if not failed and done then completed=true; break end
                            end
                        end
                        assert(completed,path..': no VR transition satisfies '..action_name..'/'..input..' toggle='..tostring(toggle))
                    end
                    element_count=element_count+1
                    if element.duration and element.duration>0 then timed_count=timed_count+1 end
                end
            end
        end
    end
    template_count=template_count+1
end
assert(template_count>0)
print('PASS ranged stock inputs: '..template_count..' actual template tables, '..element_count..' combat input elements, hold/toggle ADS, '..#raw_cases..' real VR transitions, profile='..(arg[4] and 'supplied' or 'defaults'))
print('ranged_timed_input_admission='..timed_count..' interval_start_and_deadline')
print('LIMIT: element admission, not full action hierarchy, ammunition/charge availability or live firing')
