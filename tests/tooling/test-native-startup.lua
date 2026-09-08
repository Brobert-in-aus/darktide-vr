local startup = dofile(arg[1])
local root = "./../mods/darktidevr_stereo_probe/"
local files, opened, closed = {}, 0, 0
local function open(path, mode)
    assert(mode == "r")
    if files[path] == nil then return nil end
    opened = opened + 1
    return {
        read = function(_, request) assert(request == "*all"); return files[path] end,
        close = function() closed = closed + 1 end,
    }
end
local names = {
    "bin/darktidevr_diagnostic_render_hooks.flag",
    "bin/darktidevr_vertex_shader_dump.flag",
    "bin/darktidevr_billboard_shader_substitution.flag",
    "darktidevr_billboard_pixel_shader_probe.flag",
    "darktidevr_performance_pass_trace.flag",
    "darktidevr_performance_profile.flag",
    "darktidevr_offline_dual_view.flag",
    "darktidevr_billboard_draw_census.flag",
}
for mask = 0, 255 do
    files = {}
    local selected = {}
    for i, name in ipairs(names) do
        selected[i] = math.floor(mask / 2 ^ (i - 1)) % 2 == 1
        if selected[i] then files[root .. name] = i <= 3 and "disabled" or "enabled\n" end
    end
    local state = startup.read(open)
    assert(state.diagnostic_hooks == (selected[1] or selected[2] or selected[5] or selected[8]))
    assert(state.draw_census == selected[8])
    assert(state.vertex_dump == selected[2] and state.substitution == selected[3])
    assert(state.pixel_probe == selected[4] and state.pass_trace == selected[5])
    assert(state.performance_profile == (selected[6] or selected[5]))
    assert(state.offline_dual_view == selected[7])
end
for _, case in ipairs({
    {" \tENABLED\r\n", true}, {"enabled" .. string.rep(" ", 24), true},
    {"enabled" .. string.rep(" ", 25), false}, {"enabled extra", false},
    {"disabled", false}, {"", false}, {"\venabled", false},
}) do
    files = {}
    for i = 4, #names do files[root .. names[i]] = case[1] end
    local state = startup.read(open)
    assert(state.pixel_probe == case[2] and state.pass_trace == case[2])
    assert(state.draw_census == case[2])
    assert(state.performance_profile == case[2] and state.offline_dual_view == case[2])
end
assert(opened == closed, "startup flag reader leaked a file")
print("native_startup=pass combinations=256 bounded_ascii_flags file_lifetime")
