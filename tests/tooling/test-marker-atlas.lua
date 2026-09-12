-- Marker atlas: resources set up as the HUD panel's, one frame's cells shown
-- only after the copy of that frame, cell allocation and the quad's UVs.
local Atlas = dofile(arg[1])

local calls = {}
local function record(name, result)
    return function(...) calls[#calls + 1] = {name = name, ...} return result end
end
local function find(name)
    for i = #calls, 1, -1 do if calls[i].name == name then return calls[i] end end
end
local ui = {}
local api = {
    Managers = {ui = {create_world = record("create_world", "render_world"),
        create_viewport = record("create_viewport", "viewport"),
        destroy_world = record("destroy_world")}},
    UIRenderer = {
        create_viewport_renderer = function() return {gui = "queue_gui", gui_retained = "retained"} end,
        create_resource_renderer = function() return {gui = "queue_gui", render_target = "capture",
            base_render_pass = "pass", render_pass_flag = "flag", render_target_material = "rt_mat"} end,
        destroy = record("renderer_destroy")},
    Renderer = {create_resource = record("create_resource", "display"),
        copy_render_target_rect = record("copy"), destroy_resource = record("destroy_resource")},
    World = {create_world_gui = record("create_world_gui", "world_gui"), destroy_gui = record("destroy_gui")},
    ScriptWorld = {destroy_viewport = record("destroy_viewport")},
    Gui = {create_material = function(gui, name) return gui .. ":" .. name end,
        destroy_material = record("destroy_material"), render_pass = record("render_pass")},
    Gui2 = {bitmap_3d = record("bitmap_3d")},
    Material = {set_scalar = record("set_scalar"), set_resource = record("set_resource")},
    Matrix4x4 = {identity = function() return "identity" end},
    Vector2 = function(x, y) return {x, y} end,
    Vector3 = function(x, y, z) return {x, y, z} end,
    Color = function(a, r, g, b) return {a, r, g, b} end,
    log = function() end,
}
Atlas.configure(api)
assert(Atlas.ensure("game_world"))
local state = Atlas.state
assert(state.resource.render_target == nil and state.resource.base_render_pass == nil and
    state.resource.render_pass_flag == nil, "the viewport owns the output binding")
assert(find("create_viewport")[5] == 1 and find("create_viewport")[8].back_buffer == "capture")
assert(find("set_resource")[3] == "display", "the world material samples the completed copy")
assert(state.world_gui == "world_gui" and find("create_world_gui")[1] == "game_world")

-- Frame 1: cells claimed, nothing shown yet (no completed copy).
local x, y = Atlas.claim(1, {x = 0, y = 2, z = 0})
assert(x == 512 and y == 256 and find("render_pass")[4] == true, "the target is cleared each frame")
local x2, y2 = Atlas.claim(1, {x = 1, y = 2, z = 0})
local x3, y3 = Atlas.claim(1, {x = 2, y = 2, z = 0})
assert(x2 == 1536 and y2 == 256 and x3 == 512 and y3 == 768)
local function frame_for(anchor) return "tm", 0.002 end
assert(Atlas.draw(frame_for) == 0 and not find("copy"))

-- Frame 2: the copy runs first, then frame 1's cells are shown.
assert(Atlas.begin_frame(2) and find("copy")[1] == "capture" and find("copy")[6] == "display")
assert(Atlas.draw(frame_for) == 3)
local quad = find("bitmap_3d")
local args = quad[6]
assert(quad[2] == state.world_material and quad[4] == "tm" and quad[5] == 1000)
assert(math.abs(args.size[1] - 2.048) < 1e-9 and math.abs(args.size[2] - 1.024) < 1e-9)
assert(args.uv00[1] == 0.5 and args.uv00[2] == 0.5 and args.uv11[1] == 0 and args.uv11[2] == 0.25,
    "the third cell, U and V reversed as on the HUD panel quad")
for i = 1, Atlas.CELLS do assert(Atlas.claim(2, {x = i, y = 2, z = 0})) end
local none, why = Atlas.claim(2, {x = 0, y = 0, z = 0})
assert(not none and why == "atlas_full")

-- Stale cells stop showing when the marker pass stops starting frames.
Atlas.draw(frame_for); Atlas.draw(frame_for)
assert(Atlas.draw(frame_for) == 0)

-- A per-pass handle gets one instance on the atlas GUI, its values replayed.
local instance = Atlas.material("handle", "frame", {ui_scale = {"set_scalar", 1, 2}})
assert(instance == "queue_gui:frame" and Atlas.material("handle", "frame") == instance)
assert(find("set_scalar")[1] == instance and find("set_scalar")[2] == "ui_scale" and find("set_scalar")[3] == 2)

-- A different world rebuilds; destroy restores ownership and releases all.
local resource = state.resource
Atlas.destroy()
assert(resource.render_target == "capture" and find("destroy_gui")[2] == "world_gui")
assert(find("destroy_resource")[1] == "display" and find("destroy_world")[2] == "render_world")
assert(state.resource == nil and not state.ready and #state.shown == 0)
assert(not Atlas.claim(3, {x = 0, y = 0, z = 0}))
print("marker_atlas.result=pass")
