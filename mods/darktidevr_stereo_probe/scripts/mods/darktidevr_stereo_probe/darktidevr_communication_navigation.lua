-- Supply an owned wheel gesture to stock presentation.
-- No global gamepad-mode change, button injection, cursor warp or game events.
local Navigation={}
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function pack(...)return {n=select('#',...),...}end

function Navigation.with_input(source,sample,width,height,vector,is_current,draw,...)
    assert(type(vector)=='function' and type(is_current)=='function' and type(draw)=='function',
        'invalid wheel navigation adapter')
    local valid=type(sample)=='table' and sample.held==true and sample.claim_stick==true and
        finite(sample.token) and sample.token>0 and sample.token%1==0 and
        finite(sample.x) and finite(sample.y) and math.abs(sample.x)<=1 and math.abs(sample.y)<=1 and
        finite(width) and finite(height) and width>0 and height>0
    if not valid or not source or (source.is_null_service and source:is_null_service()) or
        (source.null_service and source==source:null_service()) then return draw(source,...) end
    local x,y,token=sample.x,sample.y,sample.token
    local active=true
    local proxy=setmetatable({get=function(_,name,...)
        if (name=='cursor' or name=='navigate_controller_right' or name=='look_raw_controller') and
            active and is_current(token)==true then
            -- Stock gamepad presentation mutates navigation into screen
            -- coordinates. Every read needs a private engine vector.
            if name=='cursor' then return vector(width*0.5+x*width*0.5,height*0.5-y*height*0.5,0) end
            return vector(x,y,0)
        end
        return source:get(name,...)
    end},{__index=function(_,name)
        local value=source[name]
        if type(value)=='function' then return function(_,...)return value(source,...)end end
        return value
    end})
    local result=pack(pcall(draw,proxy,...))
    active=false
    if not result[1] then error(result[2],0) end
    return unpack(result,2,result.n)
end
return Navigation
