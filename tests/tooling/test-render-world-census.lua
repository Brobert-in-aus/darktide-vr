local module = dofile(arg[1])
local flag_text
Mods = { lua = { io = { open = function()
    if not flag_text then return nil end
    return { read = function(_, n) return flag_text:sub(1, n) end, close = function() end }
end } } }
Application = {}
local gameplay, portrait, target = {}, {}, {}
World = { get_data = function(world, key)
    if key == "name" then return world == gameplay and "level_world" or "portrait" end
    if key == "viewports" then return { player1 = target } end
    return { target }
end }
local hook, logs, errors = nil, {}, 0
local mod = {
    hook = function(_, _, _, fn) hook = fn end,
    info = function(_, format, ...) logs[#logs + 1] = string.format(format, ...) end,
    error = function() errors = errors + 1 end,
}
local function classify(world) return world == gameplay and "gameplay" or "other" end
for _, text in ipairs({ "", "disabled", "enabled" .. string.rep(" ", 25) }) do
    flag_text = text
    assert(module.install(mod, classify) == nil and hook == nil)
end
flag_text = "enabled\n"
local state = assert(module.install(mod, classify))
local calls = 0
local function render(world, camera, viewport, a, b)
    calls = calls + 1
    assert(world == portrait and camera == "camera" and viewport == target)
    assert(a == nil and b == 42)
    return nil, 7, "result"
end
for _ = 1, 120 do state.observe(gameplay) end
hook(render, portrait, "camera", target, nil, 42)
assert(state.records == 0)
state.observe(gameplay)
for _ = 1, 70 do
    local a, b, c = hook(render, portrait, "camera", target, nil, 42)
    assert(a == nil and b == 7 and c == "result")
end
assert(calls == 71 and state.records == 64 and state.complete and errors == 0)
assert(logs[2]:find("world=portrait class=other viewport=player1 queued=1", 1, true))
state = assert(module.install(mod, classify))
for _ = 1, 121 do state.observe(gameplay) end
World.get_data = function() error("invalid metadata") end
hook(render, portrait, "camera", target, nil, 42)
assert(calls == 72 and state.complete and errors == 1)
print("render_world_census=pass forwarding=72 bounded=64 metadata_failure=contained")
