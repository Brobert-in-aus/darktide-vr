-- DMF keeps one hook per mod per function, whatever the hook type: a second
-- mod:hook, mod:hook_safe or mod:hook_origin on the same object and method is
-- ignored with "Attempting to rehook active hook". A keyboard and mouse change
-- once did that to HumanInputHandler.fixed_update and silently dropped the
-- controller input and online-rules capture. Every file given is one mod.
local seen, count = {}, 0
-- A variable object (the class a hook_require callback receives) is named by
-- the nearest preceding hook_require path.
local function object_key(expression, text, start)
    expression = expression:gsub('%s+', '')
    if expression:match('^[%a_][%w_]*$') then
        local required
        for path in text:sub(1, start):gmatch('hook_require%(%s*["\'](.-)["\']') do required = path end
        if required then return 'require:'..required end
    end
    local path = expression:match('^require%(["\'](.-)["\']%)$')
    if path then return 'require:'..path end
    local name = expression:match('^["\'](.-)["\']$')
    if name then return 'class:'..name end
    local class = expression:match('^CLASS%.([%w_]+)$')
    if class then return 'class:'..class end
    return 'expression:'..expression
end
for i = 1, #arg do
    local file = assert(io.open(arg[i], 'r'))
    local text = file:read('*all'); file:close()
    local position = 1
    while true do
        local start, finish = text:find('mod:hook[_%a]*%(', position)
        if not start then break end
        local kind = text:sub(start + 4, finish - 1)
        position = finish + 1
        if kind == 'hook' or kind == 'hook_safe' or kind == 'hook_origin' then
            -- The object expression runs to the first comma outside brackets.
            local depth, cursor = 0, finish + 1
            while cursor <= #text do
                local char = text:sub(cursor, cursor)
                if char == '(' or char == '{' or char == '[' then depth = depth + 1
                elseif char == ')' or char == '}' or char == ']' then depth = depth - 1
                elseif char == ',' and depth == 0 then break end
                cursor = cursor + 1
            end
            local object = text:sub(finish + 1, cursor - 1)
            local method = text:match('^%s*["\']([%w_]+)["\']', cursor + 1)
            if method then
                local key = object_key(object, text, start)..'.'..method
                local line = select(2, text:sub(1, start):gsub('\n', '')) + 1
                local where = arg[i]:match('[^/\\]+$')..':'..line
                assert(not seen[key], string.format('%s hooks %s again (first at %s); DMF ignores the second hook',
                    where, key, tostring(seen[key])))
                seen[key] = where
                count = count + 1
            end
        end
    end
end
assert(count > 50, 'hook scan found too few hooks: '..count)
print(string.format('dmf_unique_hooks=pass hooks=%d files=%d', count, #arg))
