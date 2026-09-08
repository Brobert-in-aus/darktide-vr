-- Scoped input for ChatManager's cached Ingame input service.
-- Stock owns voice mode and microphone operations; this only contributes an
-- explicitly held input within one owner/sample-checked update callback.
local Talk={}
local scopes=setmetatable({},{__mode='k'})
local function pack(...)return {n=select('#',...),...}end
local function usable(source)
    return source and type(source.get)=='function' and type(source.has)=='function' and
        not (source.is_null_service and source:is_null_service()) and
        not (source.null_service and source==source:null_service())
end

function Talk.with_input(manager,held,is_current,update,...)
    assert(type(manager)=='table' and type(is_current)=='function' and type(update)=='function',
        'invalid push-to-talk adapter')
    local source=manager._input_service
    local inject=held==true and usable(source)
    local previous=scopes[manager]
    local scope={}
    scopes[manager]=scope
    local active=true
    local proxy
    if inject then proxy=setmetatable({get=function(_,name,...)
        if name=='voip_push_to_talk' and active and scopes[manager]==scope and manager._input_service==proxy and
            is_current()==true and usable(source) and source:has(name) then return true end
        return source:get(name,...)
    end},{__index=function(_,name)
        local value=source[name]
        if type(value)=='function' then return function(_,...)return value(source,...)end end
        return value
    end})
    manager._input_service=proxy end
    local result=pack(pcall(update,manager,...))
    active=false
    scopes[manager]=previous
    -- Preserve an input-service replacement made during the real update.
    if proxy and manager._input_service==proxy then manager._input_service=source end
    if not result[1] then error(result[2],0) end
    return unpack(result,2,result.n)
end
return Talk
