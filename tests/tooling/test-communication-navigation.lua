local Navigation=dofile(arg[1])
local function vector(x,y,z)return {x,y,z}end
local sample={held=true,claim_stick=true,token=17,x=0.5,y=-0.25}
local null={get=function()return false end,is_null_service=function()return true end}
local calls,current=0,true
local source
source={get=function(self,name)
    assert(self==source);calls=calls+1
    if name=='cursor' then return {10,20,0}end
    if name=='navigate_controller_right' or name=='look_raw_controller' then return {0,0,0}end
    return 'keyboard',nil,19
end,null_service=function(self)assert(self==source);return null end}
local function owns(token)assert(token==17);return current end
local retained
local a,b,c=Navigation.with_input(source,sample,1920,1080,vector,owns,function(input)
    retained=input
    local cursor=input:get('cursor');assert(cursor[1]==1440 and cursor[2]==675)
    local stick=input:get('navigate_controller_right');stick[1]=999
    assert(input:get('navigate_controller_right')[1]==0.5 and sample.x==0.5)
    assert(input:get('look_raw_controller')[2]==-0.25)
    sample.x=0.9
    assert(input:get('navigate_controller_right')[1]==0.5,'adapter borrowed a mutable frame sample')
    assert(input:null_service()==null)
    local x,y,z=input:get('unrelated');assert(x=='keyboard' and y==nil and z==19)
    current=false;assert(input:get('cursor')[1]==10,'cancelled token still overrides input')
    current=true
    return 1,nil,3
end)
assert(a==1 and b==nil and c==3)
assert(retained:get('cursor')[1]==10,'retained proxy escaped scope')
assert(not pcall(Navigation.with_input,source,sample,1920,1080,vector,owns,function(input)
    retained=input;error('stock presentation failed')
end))
assert(retained:get('cursor')[1]==10,'failed presentation leaked proxy')
for _,invalid in ipairs({
    {held=false,claim_stick=true,token=17,x=0,y=0},
    {held=true,claim_stick=false,token=17,x=0,y=0},
    {held=true,claim_stick=true,token=17,x=2,y=0},
    {held=true,claim_stick=true,token=17,x=0,y=0/0},
})do
    Navigation.with_input(source,invalid,1920,1080,vector,owns,function(input)assert(input==source)end)
end
Navigation.with_input(null,sample,1920,1080,vector,owns,function(input)assert(input==null)end)
Navigation.with_input(source,sample,0,1080,vector,owns,function(input)assert(input==source)end)
assert(calls==4,'owned navigation reads must not poll unrelated stock cursor input')
print('communication_navigation: private vectors, token/scope expiration, stock input and sparse returns pass')

if arg[2] then
    local path=arg[2]..'/scripts/ui/hud/elements/smart_tagging/hud_element_smart_tagging.lua'
    local file=assert(io.open(path,'r'));local code=file:read('*a');file:close()
    local first=assert(code:find('HudElementSmartTagging._update_wheel_presentation =',1,true))
    local last=assert(code:find('\nHudElementSmartTagging._is_wheel_entry_hovered =',first,true))
    local Hud={}
    local stock_math=setmetatable({
        distance_2d=function(x,y,a,b)return math.sqrt((a-x)^2+(b-y)^2)end,
        angle=function(x,y,a,b)return math.atan2(b-y,a-x)end,
        radians_to_degrees=function(n)return n*180/math.pi end},{__index=math})
    local env=setmetatable({HudElementSmartTagging=Hud,InputDevice={gamepad_active=true},
        RESOLUTION_LOOKUP={},math=stock_math,Localize=function(text)return text end},{__index=_G})
    setfenv(assert(loadstring(code:sub(first,last-1),'@'..path)),env)()
    local function hud()
        local h={_entries={},_widgets_by_name={wheel_background={content={},style={mark={color={0}}}}}}
        for i=1,8 do
            h._entries[i]={option={display_name='option_'..i},
                widget={content={angle=(i-1)*math.pi/4,hotspot={}}}}
        end
        return h
    end
    local function equal(actual,expected)
        for i=1,8 do
            assert(actual._entries[i].widget.content.hotspot.force_hover==expected._entries[i].widget.content.hotspot.force_hover)
        end
        local a,b=actual._widgets_by_name.wheel_background,expected._widgets_by_name.wheel_background
        assert(math.abs(a.content.angle-b.content.angle)<1e-9)
        assert(a.content.force_hover==b.content.force_hover and a.content.text==b.content.text)
        assert(a.style.mark.color[1]==b.style.mark.color[1])
    end
    local cases=0
    for _,size in ipairs({{1920,1080},{2496,2688}})do
        env.RESOLUTION_LOOKUP.width=size[1];env.RESOLUTION_LOOKUP.height=size[2]
        for _,scale in ipairs({1,1.5})do
            for i=0,9 do
                local angle=i*math.pi/4
                local radius=i==8 and 0 or (i==9 and 0.05 or 0.8)
                local s={held=true,claim_stick=true,token=17,x=math.sin(angle)*radius,y=math.cos(angle)*radius}
                local stock_source={get=function(_,name)
                    if name=='navigate_controller_right' then return vector(s.x,s.y,0)end
                    if name=='cursor' then return vector(10,20,0)end
                end}
                local baseline=hud()
                env.InputDevice.gamepad_active=true
                Hud._update_wheel_presentation(baseline,0.01,1,{}, {scale=scale},stock_source)
                assert(baseline._widgets_by_name.wheel_background.content.force_hover==(i<8),
                    'outer directions must select and center/deadzone samples must remain unselected')
                for _,gamepad in ipairs({false,true})do
                    env.InputDevice.gamepad_active=gamepad
                    local actual=hud()
                    local original_x,original_y=s.x,s.y
                    Navigation.with_input(stock_source,s,size[1],size[2],vector,owns,function(input)
                        Hud._update_wheel_presentation(actual,0.01,1,{}, {scale=scale},input)
                    end)
                    assert(env.InputDevice.gamepad_active==gamepad and s.x==original_x and s.y==original_y)
                    equal(actual,baseline);cases=cases+1
                end
            end
        end
    end
    print('communication_navigation_stock: '..cases..' actual presentation cases preserve selection in mouse/gamepad modes')
end
