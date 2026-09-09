-- Offline comparison of the actual module's private scoped-pose helper.
-- No engine installation, tracking, graphics submission or gameplay simulation.
local ffi = require('ffi')
ffi.cdef[[int __stdcall QueryPerformanceCounter(int64_t* value);
int __stdcall QueryPerformanceFrequency(int64_t* value);]]
local counter, frequency = ffi.new('int64_t[1]'), ffi.new('int64_t[1]')
assert(ffi.C.QueryPerformanceFrequency(frequency) ~= 0)
local function now()
    assert(ffi.C.QueryPerformanceCounter(counter) ~= 0)
    return tonumber(counter[0]) / tonumber(frequency[0])
end
local function load_scope(path)
    local file = assert(io.open(path, 'rb'))
    local source = file:read('*a'); file:close()
    local boundary = assert(source:find('function controller_aim.install(', 1, true))
    local chunk = assert(loadstring(source:sub(1, boundary - 1) ..
        '\nreturn with_first_person_pose', '@' .. path))
    setfenv(chunk, setmetatable({require = function() return {} end}, {__index = _G}))
    return assert(chunk())
end
local function pack(...) return {n = select('#', ...), ...} end
local function validate(scope)
    local original = {position = {}, rotation = {}, other = {}}
    local action = {_first_person_component = original}
    local position, rotation, token = {}, {}, {}
    local function stock(self, value, trailing)
        assert(self == action and value == token and trailing == nil)
        local current = self._first_person_component
        assert(current ~= original and current.position == position and current.rotation == rotation)
        assert(current.other == original.other)
        return nil, 17, nil, token, nil
    end
    local result = pack(scope(action, position, rotation, stock, token, nil))
    assert(result.n == 5 and result[1] == nil and result[2] == 17 and
        result[3] == nil and result[4] == token and result[5] == nil)
    assert(action._first_person_component == original)
    assert(pack(scope(action, position, rotation, function() end)).n == 0)
    local ok, err = pcall(scope, action, position, rotation, function() error(token, 0) end)
    assert(not ok and err == token and action._first_person_component == original)
    local nested_position, nested_rotation = {}, {}
    scope(action, position, rotation, function(self)
        local outer = self._first_person_component
        scope(self, nested_position, nested_rotation, function(inner)
            assert(inner._first_person_component.position == nested_position)
            assert(inner._first_person_component.other == original.other)
        end)
        assert(self._first_person_component == outer)
    end)
    assert(action._first_person_component == original)
    for _, args in ipairs({{action, false, rotation}, {action, position, false}, {{}, position, rotation}}) do
        local before = args[1]._first_person_component
        local values = pack(scope(args[1], args[2], args[3], function(self)
            assert(self._first_person_component == before)
            return token, nil
        end))
        assert(values.n == 2 and values[1] == token and values[2] == nil)
    end
    return function()
        local a, b, c, d, e = scope(action, position, rotation, stock, token, nil)
        assert(a == nil and b == 17 and c == nil and d == token and e == nil)
        assert(action._first_person_component == original)
    end
end
local variants = {
    baseline = validate(load_scope(assert(arg[1], 'baseline module required'))),
    candidate = validate(load_scope(assert(arg[2], 'candidate module required'))),
}
for trial = 1, 5 do
    local order = trial % 2 == 1 and {'baseline', 'candidate'} or {'candidate', 'baseline'}
    for _, name in ipairs(order) do
        local call = variants[name]
        for _ = 1, 3000 do call() end
        collectgarbage('collect'); collectgarbage('stop')
        local memory, start = collectgarbage('count'), now()
        for _ = 1, 100000 do call() end
        local elapsed, growth = (now() - start) * 1000, collectgarbage('count') - memory
        collectgarbage('restart'); collectgarbage('collect')
        print(string.format('version=%s trial=%d calls=100000 wall_ms=%.4f heap_growth_kib=%.4f',
            name, trial, elapsed, growth))
    end
end
print('PASS returns=preserved errors=preserved nested_restoration=preserved bypass=preserved')
