local lines = {}
for i = 1, 201 do lines[i] = " local variable_" .. i .. " = 0" end
local chunk, message = loadstring(table.concat(lines, "\n"))
assert(not chunk and message:find("local variables"), message)
assert(loadstring("local x = 1; return x"))
assert(not loadstring("local = broken"))
print("luajit_compiler_contract=pass")
