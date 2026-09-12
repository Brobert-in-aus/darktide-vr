-- World-surface marker routing: geometry, admission, and the conversion of the
-- stock 2D draw entry points into 3D draws on the plane with the renderer's
-- own GUI restored afterwards. Engine doubles only.
local MarkerWorld = dofile(arg[1])
local Plane = dofile(arg[2])

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- Geometry: a marker 2 m ahead of a head at the origin, primary projection
-- with 2*tan(fov/2)/height = 0.001 per pixel: one pixel is 2 mm at the anchor.
local geometry, reason = MarkerWorld.geometry(Plane, {x = 0, y = 2, z = 0},
    {x = 0, y = 0, z = 0}, {x = 1, y = 0, z = 0}, {x = 0, y = 0, z = 1}, 0.001, false)
assert(geometry, reason)
assert(near(geometry.pixel_size, 0.002) and near(geometry.distance, 2))
assert(near(geometry.right.x, 1) and near(geometry.right.y, 0) and near(geometry.right.z, 0),
    "right axis must be the head's right for a centred anchor")
assert(near(geometry.up.z, 1) and near(geometry.forward.y, 1),
    "up follows the head's up, forward points from the head to the anchor")
local flipped = MarkerWorld.geometry(Plane, {x = 0, y = 2, z = 0}, {x = 0, y = 0, z = 0},
    {x = 1, y = 0, z = 0}, {x = 0, y = 0, z = 1}, 0.001, true)
assert(near(flipped.right.x, -1) and near(flipped.forward.y, -1) and near(flipped.up.z, 1),
    "flip reverses right and forward only")
assert(not MarkerWorld.geometry(Plane, {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0},
    {x = 1, y = 0, z = 0}, {x = 0, y = 0, z = 1}, 0.001), "zero distance is rejected")

-- Admission: only widgets whose passes the routing covers.
assert(MarkerWorld.admits({passes = {{pass_type = "texture"}, {pass_type = "text"},
    {pass_type = "rect"}, {pass_type = "slug_icon"}, {pass_type = "logic"}}}))
local ok, why = MarkerWorld.admits({passes = {{pass_type = "texture"}, {pass_type = "rotated_texture"}}})
assert(not ok and why == "rotated_texture")
ok, why = MarkerWorld.admits({passes = {{pass_type = "texture", retained_mode = true}}})
assert(not ok and why == "retained")
assert(not MarkerWorld.admits({passes = {}}))

-- Local points: pixels relative to the anchor's screen position, in metres.
local scope_geometry = {origin_x = 1000, origin_y = 500, pixel_size = 0.002}
local lx, ly = MarkerWorld.local_point(scope_geometry, 1100, 450)
assert(near(lx, 0.2) and near(ly, -0.1))

-- Routing through hooked renderer functions.
local calls = {}
local function record(name) return function(...) calls[#calls + 1] = {name = name, ...} return name end end
local UIRenderer = {
    script_draw_bitmap = record("bitmap2d"),
    script_draw_bitmap_uv = record("bitmap_uv2d"),
    script_draw_bitmap_3d = record("bitmap3d"),
    script_draw_text = record("text2d"),
    script_draw_text_3d = record("text3d"),
    draw_rect = record("rect2d"),
    draw_slug_icon = record("icon2d"),
    destroy = record("destroy"),
}
local hooks = {}
local mod = {hook = function(_, target, name, callback)
    local original = target[name]
    target[name] = function(...) return callback(original, ...) end
    hooks[name] = true
end}
local V3 = function(x, y, z) return {x, y, z, kind = "v3"} end
local V2 = function(x, y) return {x, y, kind = "v2"} end
local colors = {}
local api = {
    UIRenderer = UIRenderer, Vector3 = V3, Vector2 = V2,
    Color = function(a, r, g, b) local c = {a, r, g, b}; colors[#colors + 1] = c; return c end,
    Gui = {rect_3d = record("rect3d"), slug_icon_3d = record("icon3d")},
    World = {create_world_gui = function(world) return {world = world} end,
        destroy_gui = function(world, gui) gui.destroyed = true end},
    material_flags = function() return 7 end,
}
MarkerWorld.install(mod, api)
assert(hooks.script_draw_bitmap and hooks.draw_rect and hooks.destroy)

local stock_gui = {}
local renderer = {world = {}, gui = stock_gui, scale = 2,
    render_settings = {snap_pixel_positions = true, start_layer = 100, alpha_multiplier = 0.5,
        color_intensity_multiplier = 1}}
local gui = MarkerWorld.gui_for(renderer, api.World, {identity = function() return "identity" end})
assert(gui and gui.world == renderer.world and
    MarkerWorld.gui_for(renderer, api.World, {identity = function() return "identity" end}) == gui,
    "one world GUI per renderer")

-- Outside a scope every call passes through untouched.
UIRenderer.script_draw_bitmap(renderer, "m", V3(10, 20, 3), V3(4, 4, 0), nil, nil)
assert(calls[#calls].name == "bitmap2d")

local scope = {renderer = renderer, gui = gui, tm = "tm", origin_x = 1000, origin_y = 500,
    pixel_size = 0.002}
local seen_gui_during_draw
MarkerWorld.draw(scope, function()
    assert(renderer.render_settings.snap_pixel_positions == false, "snapping off while routed")
    UIRenderer.script_draw_bitmap(renderer, "m", V3(1100, 450, 3), V3(50, 25, 0), {255, 1, 2, 3}, nil)
    local c = calls[#calls]
    assert(c.name == "bitmap3d" and c[1] == renderer and c[2] == "m" and c[3] == "tm")
    assert(near(c[4][1], 0.2) and near(c[4][2], -0.1) and c[5] == 3)
    assert(near(c[6][1], 0.1) and near(c[6][2], 0.05), "bitmap size in metres")
    UIRenderer.script_draw_text(renderer, "hi", 30, "body", V3(1000, 500, 2), V2(200, 40), nil, nil, nil)
    c = calls[#calls]
    assert(c.name == "text3d" and near(c[3], 0.06) and c[5] == "tm" and near(c[6][1], 0) and
        c[7] == 2 and near(c[8][1], 0.4), "text: font size and box in metres, layer kept")
    -- Logical rect: scaled by the renderer, start layer and alpha applied.
    UIRenderer.draw_rect(renderer, V3(520, 240, 5), V3(10, 20, 0), {200, 255, 255, 255}, nil)
    c = calls[#calls]
    assert(c.name == "rect3d" and c[1] == gui and c[2] == "tm" and near(c[3][1], 0.08) and
        near(c[3][2], -0.04) and c[4] == 105 and near(c[5][1], 0.04) and near(c[5][2], 0.08))
    assert(c[6][1] == 100, "rect alpha multiplied")
    UIRenderer.draw_slug_icon(renderer, "res", 1, V3(500, 250, 0), V3(10, 10, 0), {255, 255, 255, 255},
        nil, nil, nil)
    c = calls[#calls]
    assert(c.name == "icon3d" and c[1] == gui and c[4] == "tm" and c[6] == 101 and c[9] == "material_flags" and c[10] == 7)
    -- Retained requests keep the stock route.
    UIRenderer.script_draw_bitmap(renderer, "m", V3(0, 0, 0), V3(1, 1, 0), nil, "retained")
    assert(calls[#calls].name == "bitmap2d")
    seen_gui_during_draw = renderer.gui
end)
assert(seen_gui_during_draw == stock_gui, "the renderer's own GUI is restored between routed calls")
assert(renderer.render_settings.snap_pixel_positions == true, "snapping restored")
assert(MarkerWorld.state.scope == nil)

-- A failing draw restores the GUI and snapping and propagates the error.
UIRenderer.script_draw_bitmap_3d = function() error("boom", 0) end
local failed, err = pcall(MarkerWorld.draw, scope, function()
    UIRenderer.script_draw_bitmap(renderer, "m", V3(0, 0, 0), V3(1, 1, 0), nil, nil)
end)
assert(not failed and err == "boom")
assert(renderer.gui == stock_gui and renderer.render_settings.snap_pixel_positions == true)
assert(MarkerWorld.state.scope == nil and MarkerWorld.state.errors == 1)

-- Renderer destruction releases its world GUI once.
UIRenderer.destroy(renderer)
assert(gui.destroyed and MarkerWorld.state.guis[renderer] == nil)
UIRenderer.destroy(renderer)
print("marker_world.result=pass")
