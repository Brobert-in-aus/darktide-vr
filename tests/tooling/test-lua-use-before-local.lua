-- A module that reads a name before the line declaring it a local reads the
-- global of that name instead, which is nil: the compile gate accepts it and
-- the module fails only when the game loads it. On 17 October 2026 that took
-- the whole mod down at the first launch on game 1.13.2 --
-- `calibration.profile_height = ...` two lines above `local calibration = {}`
-- -- and no test loaded the file.
--
-- Every chunk's bytecode is listed and each global read (GGET) or write
-- (GSET) is checked against the names the same file declares as top-level
-- locals. A hit is a name used above its declaration (or shadowing a global
-- the file also means to use, which is as wrong). Every file given is checked.
-- jit.bc ships beside the interpreter (src/jit/bc.lua), not on the default path.
package.path = (arg[-1] or ''):gsub('[^/\\]+$', '') .. '?.lua;' .. package.path
local bc = require('jit.bc')

local failures, checked = {}, 0
for i = 1, #arg do
    local path = arg[i]
    local source = assert(io.open(path, 'rb')):read('*a')
    local locals = {}
    for line in (source .. '\n'):gmatch('([^\n]*)\n') do
        local name = line:match('^local%s+function%s+([%a_][%w_]*)')
        if name then
            locals[name] = true
        else
            local names = line:match('^local%s+([%a_][%w_%s,]*)')
            if names then
                for each in names:gmatch('[%a_][%w_]*') do locals[each] = true end
            end
        end
    end
    local chunk = assert(loadstring(source, '@' .. path))
    local listing = {}
    bc.dump(chunk, {write = function(_, text) listing[#listing + 1] = text end, flush = function() end}, true)
    listing = table.concat(listing)
    local reported = {}
    for op, name in listing:gmatch('(G[GS]ET)%s+%d+%s+%d+%s+;%s+"([%a_][%w_]*)"') do
        if locals[name] and not reported[name] then
            reported[name] = true
            failures[#failures + 1] = string.format('%s: %s of "%s", which the file declares as a local',
                path:match('[^/\\]+$'), op, name)
        end
    end
    checked = checked + 1
end
assert(checked > 0, 'no files given')
if #failures > 0 then
    error('use before local:\n  ' .. table.concat(failures, '\n  '), 0)
end
print(string.format('lua_use_before_local=pass files=%d', checked))
