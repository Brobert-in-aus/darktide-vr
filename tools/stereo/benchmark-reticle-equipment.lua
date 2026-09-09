-- Compare actual private lookup helpers without game hooks or a physics world.
local ffi = require('ffi')
ffi.cdef[[int __stdcall QueryPerformanceCounter(int64_t* value);
int __stdcall QueryPerformanceFrequency(int64_t* value);]]
local counter, frequency = ffi.new('int64_t[1]'), ffi.new('int64_t[1]')
assert(ffi.C.QueryPerformanceFrequency(frequency) ~= 0)
local function now()
    assert(ffi.C.QueryPerformanceCounter(counter) ~= 0)
    return tonumber(counter[0]) / tonumber(frequency[0])
end
local function load_lookup(path, visual)
    local file = assert(io.open(path, 'rb'))
    local source = file:read('*a'); file:close()
    local boundary = assert(source:find('function controller_aim.install(', 1, true))
    local chunk = assert(loadstring(source:sub(1, boundary - 1) ..
        '\nreturn is_local_visual_unit', '@' .. path))
    local environment = {
        require = function() return {} end,
        ScriptUnit = {has_extension = function(_, system)
            assert(system == 'visual_loadout_system'); return visual.current
        end},
    }
    setfenv(chunk, setmetatable(environment, {__index = _G}))
    return assert(chunk())
end
local visual = {current = {_first_person_unit = {}, _equipment = {}}}
local owner, outside = {}, {}
local extension = {_unit = owner}
local baseline = load_lookup(assert(arg[1], 'baseline module required'), visual)
local candidate = load_lookup(assert(arg[2], 'candidate module required'), visual)
local function compare(unit, expected)
    assert(baseline(extension, unit) == expected)
    assert(candidate(extension, unit) == expected)
end
compare(nil, false); compare(owner, true); compare(visual.current._first_person_unit, true)
compare(outside, false)
for slot_index = 1, 6 do
    local slot = {unit_1p = {}, unit_3p = {}, attachments_by_unit_1p = {}, attachments_by_unit_3p = {}}
    for group = 1, 3 do
        slot.attachments_by_unit_1p[group] = {{}, {}, {}}
        slot.attachments_by_unit_3p[group] = {{}, {}, {}}
    end
    visual.current._equipment[slot_index] = slot
end
visual.current._equipment.ignored = 17
for _, slot in pairs(visual.current._equipment) do
    if type(slot) == 'table' then
        compare(slot.unit_1p, true); compare(slot.unit_3p, true)
        for _, set in ipairs({slot.attachments_by_unit_1p, slot.attachments_by_unit_3p}) do
            for _, group in pairs(set) do
                for _, unit in ipairs(group) do compare(unit, true) end
            end
        end
    end
end
local last = visual.current._equipment[6]
local final_attachment = last.attachments_by_unit_3p[3][3]
local first_set = last.attachments_by_unit_1p
last.attachments_by_unit_1p = nil
compare(final_attachment, true); compare(outside, false)
last.attachments_by_unit_1p = first_set
last.attachments_by_unit_3p[3][3] = outside
compare(final_attachment, false); compare(outside, true)
last.attachments_by_unit_3p[3][3] = final_attachment
local equipment = visual.current._equipment
visual.current._equipment = nil; compare(outside, false)
visual.current._equipment = equipment
local saved = visual.current
visual.current = nil; compare(outside, false); visual.current = saved
local variants = {baseline = baseline, candidate = candidate}
for _, workload in ipairs({{name = 'miss', unit = outside, expected = false},
        {name = 'last_attachment', unit = final_attachment, expected = true},
        {name = 'owner', unit = owner, expected = true}}) do
    for trial = 1, 5 do
        local order = trial % 2 == 1 and {'baseline', 'candidate'} or {'candidate', 'baseline'}
        for _, name in ipairs(order) do
            local lookup = variants[name]
            for _ = 1, 3000 do assert(lookup(extension, workload.unit) == workload.expected) end
            collectgarbage('collect'); collectgarbage('stop')
            local memory, start = collectgarbage('count'), now()
            for _ = 1, 100000 do assert(lookup(extension, workload.unit) == workload.expected) end
            local elapsed, growth = (now() - start) * 1000, collectgarbage('count') - memory
            collectgarbage('restart'); collectgarbage('collect')
            print(string.format('workload=%s version=%s trial=%d calls=100000 wall_ms=%.4f heap_growth_kib=%.4f',
                workload.name, name, trial, elapsed, growth))
        end
    end
end
print('PASS equipment_and_attachment_identity=preserved missing_sets=preserved live_mutation=preserved')
