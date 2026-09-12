-- World-surface marker routing: geometry, admission, and the conversion of the
-- stock 2D draw entry points into 3D draws with a per-eye (screen surface) or
-- world transform. Engine doubles only; the module places no hooks, its
-- owners call `route`.
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

-- Routing: the owner of each renderer hook calls route(name, stock, renderer, ...).
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
    text_size = function() return 40, 20 end,
}
local V3 = function(x, y, z) return {x, y, z, kind = "v3"} end
local V2 = function(x, y) return {x, y, kind = "v2"} end
local api = {
    UIRenderer = UIRenderer, Vector3 = V3, Vector2 = V2,
    Color = function(a, r, g, b) return {a, r, g, b} end,
    Gui = {rect_3d = record("rect3d"), slug_icon_3d = record("icon3d"),
        slug_text_3d = record("slug3d"),
        HorizontalAlignCenter = 11, HorizontalAlignRight = 12,
        VerticalAlignCenter = 21, VerticalAlignTop = 22},
    Gui2 = {bitmap_3d = record("gui2_bitmap3d")},
    UIFonts = {data_by_type = function(kind) return {path = "font/" .. kind, render_flags = 16} end},
    World = {create_world_gui = function(world) return {world = world} end,
        destroy_gui = function(world, gui) gui.destroyed = true end},
    Matrix4x4 = {identity = function() return "identity" end},
    material_flags = function() return 7 end,
}
MarkerWorld.configure(api)
assert(MarkerWorld.state.surface == "world" and MarkerWorld.state.text_origin == "top")
local function call(name, renderer, ...)
    return MarkerWorld.route(name, UIRenderer[name], renderer, ...)
end

local stock_gui = {}
local renderer = {world = {}, gui = stock_gui, scale = 2,
    render_settings = {snap_pixel_positions = true, start_layer = 100, alpha_multiplier = 0.5,
        color_intensity_multiplier = 1}}

-- Outside a scope every call passes through untouched.
call("script_draw_bitmap", renderer, "m", V3(10, 20, 3), V3(4, 4, 0), nil, nil)
assert(calls[#calls].name == "bitmap2d")

-- Screen surface: each eye has its own transform and anchor origin; pixel
-- units; the renderer's own GUI is used.
local scope = {renderer = renderer, surface = "screen",
    eyes = {left = {tm = "tm_left", origin_x = 1000, origin_y = 500},
            right = {tm = "tm_right", origin_x = 1040, origin_y = 500}}}
local other = {world = {}, gui = {}, scale = 1, render_settings = {}}
MarkerWorld.draw(scope, "left", function()
    assert(renderer.render_settings.snap_pixel_positions == false, "snapping off while routed")
    call("script_draw_bitmap", renderer, "m", V3(1100, 450, 3), V3(50, 25, 0), {255, 1, 2, 3}, nil)
    local c = calls[#calls]
    assert(c.name == "bitmap3d" and c[1] == renderer and c[2] == "m" and c[3] == "tm_left")
    assert(near(c[4][1], 100) and near(c[4][2], -50) and c[5] == 3, "pixels relative to the anchor")
    assert(near(c[6][1], 50) and near(c[6][2], 25), "size in pixels")
    assert(renderer.gui == stock_gui, "screen surface keeps the renderer's GUI")
    call("script_draw_bitmap_uv", renderer, "m", V3(1000, 500, 1), V3(2, 2, 0), "uvs", nil, nil)
    c = calls[#calls]
    assert(c.name == "bitmap3d" and c[8] == "uvs")
    -- Text: the 3D call takes no box and no options; alignment inside the
    -- 2D box becomes a measured offset ("hi" measures 40x20 px here), and
    -- the top origin raises the position by the text height.
    call("script_draw_text", renderer, "hi", 30, "body", V3(1000, 500, 2), V2(200, 40), nil,
        {horizontal_alignment = api.Gui.HorizontalAlignCenter,
         vertical_alignment = api.Gui.VerticalAlignCenter}, nil)
    c = calls[#calls]
    assert(c.name == "text3d" and near(c[3], 30) and c[5] == "tm_left" and c[7] == 2,
        "text: font size in pixels, layer kept")
    assert(near(c[6][1], 80) and near(c[6][2], 10 + 20), "centred in its 200x40 box, top origin")
    assert(c[8] == nil and c[10] == nil, "no box and no options reach the 3D call")
    assert(MarkerWorld.set_text_origin("bottom"))
    call("script_draw_text", renderer, "hi", 30, "body", V3(1000, 500, 2), V2(200, 40), nil,
        {vertical_alignment = api.Gui.VerticalAlignTop}, nil)
    c = calls[#calls]
    assert(near(c[6][1], 0) and near(c[6][2], 20), "top alignment with a bottom origin")
    assert(MarkerWorld.set_text_origin("top"))
    call("script_draw_text", renderer, "hi", 30, "body", V3(1000, 500, 2), nil, nil, nil, nil)
    c = calls[#calls]
    assert(c.name == "text3d" and near(c[6][1], 0) and near(c[6][2], 30), "box-less text: font height up")
    assert(MarkerWorld.set_text_mode("rect"))
    call("script_draw_text", renderer, "hi", 30, "body", V3(1000, 500, 2), V2(200, 40), nil, nil, nil)
    assert(calls[#calls].name == "rect3d" and calls[#calls][1] == stock_gui, "rect mode marks the text box")
    assert(MarkerWorld.set_text_mode("2d"))
    call("script_draw_text", renderer, "hi", 30, "body", V3(1000, 500, 2), V2(200, 40), nil, nil, nil)
    assert(calls[#calls].name == "text2d", "2d mode keeps text on the flat route")
    assert(not MarkerWorld.set_text_mode("bogus") and not MarkerWorld.set_text_origin("middle"))
    assert(MarkerWorld.set_text_mode("slug"))
    -- Logical rect: scaled by the renderer, start layer and alpha applied.
    call("draw_rect", renderer, V3(520, 240, 5), V3(10, 20, 0), {200, 255, 255, 255}, nil)
    c = calls[#calls]
    assert(c.name == "rect3d" and c[1] == stock_gui and c[2] == "tm_left" and near(c[3][1], 40) and
        near(c[3][2], -20) and c[4] == 105 and near(c[5][1], 20) and near(c[5][2], 40))
    assert(c[6][1] == 100, "rect alpha multiplied")
    call("draw_slug_icon", renderer, "res", 1, V3(500, 250, 0), V3(10, 10, 0), {255, 255, 255, 255},
        nil, nil, nil)
    c = calls[#calls]
    assert(c.name == "icon3d" and c[1] == stock_gui and c[4] == "tm_left" and c[6] == 101 and
        c[9] == "material_flags" and c[10] == 7)
    -- Retained requests, other renderers and names without a converter keep
    -- the stock route.
    call("script_draw_bitmap", renderer, "m", V3(0, 0, 0), V3(1, 1, 0), nil, "retained")
    assert(calls[#calls].name == "bitmap2d")
    call("script_draw_bitmap", other, "m", V3(0, 0, 0), V3(1, 1, 0), nil, nil)
    assert(calls[#calls].name == "bitmap2d")
    assert(MarkerWorld.route("draw_rect_rotated", function() return "stock" end, renderer) == "stock")
end)
assert(renderer.render_settings.snap_pixel_positions == true, "snapping restored")
assert(MarkerWorld.state.scope == nil and MarkerWorld.state.eye == nil)

-- The right eye's replay uses its own transform and origin.
MarkerWorld.draw(scope, "right", function()
    call("script_draw_bitmap", renderer, "m", V3(1100, 450, 3), V3(50, 25, 0), nil, nil)
    local c = calls[#calls]
    assert(c[3] == "tm_right" and near(c[4][1], 60) and near(c[4][2], -50))
end)

-- World surface: metres, the world GUI swapped in for each call and restored.
local gui = MarkerWorld.gui_for(renderer)
assert(gui and gui.world == renderer.world and MarkerWorld.gui_for(renderer) == gui,
    "one world GUI per renderer")
local world_scope = {renderer = renderer, surface = "world", gui = gui, tm = "tm",
    origin_x = 1000, origin_y = 500, pixel_size = 0.002}
local seen_gui_during_draw
MarkerWorld.draw(world_scope, "left", function()
    -- Bare Gui2 bitmap: no material flags, no render pass, layer with the
    -- start layer, colour tinted, metres.
    call("script_draw_bitmap", renderer, "m", V3(1100, 450, 3), V3(50, 25, 0), {200, 255, 255, 255}, nil)
    local c = calls[#calls]
    assert(c.name == "gui2_bitmap3d" and c[1] == gui and c[2] == "m" and c[3] == nil and c[4] == "tm" and
        c[5] == 103, "world surface: bare bitmap call on the world GUI")
    local args = c[6]
    assert(near(args.position_offset[1], 0.2) and near(args.position_offset[2], -0.1) and
        near(args.size[1], 0.1) and args.color[1] == 100 and args.snap_pixel_positions == false and
        args.uv00 == nil, "world surface in metres, tinted, unsnapped")
    call("script_draw_bitmap_uv", renderer, "m", V3(1000, 500, 1), V3(2, 2, 0), {{0, 0}, {1, 1}}, nil, nil)
    c = calls[#calls]
    assert(c.name == "gui2_bitmap3d" and c[6].uv00[1] == 0 and c[6].uv11[1] == 1 and c[6].color == nil)
    call("script_draw_text", renderer, "hi", 30, "body", V3(1000, 500, 2), V2(200, 40), {255, 9, 9, 9},
        {horizontal_alignment = api.Gui.HorizontalAlignCenter}, nil)
    c = calls[#calls]
    assert(c.name == "slug3d" and c[1] == gui and c[2] == "hi" and c[3] == "font/body" and
        near(c[4], 0.06) and c[5] == "tm" and near(c[6][1], 0.16) and near(c[6][2], 0.04) and
        c[7] == 102 and c[8][1] == 127.5 and c[9] == "flags" and c[10] == 16,
        "world surface: bare slug text with the font's own flags")
    call("draw_rect", renderer, V3(520, 240, 5), V3(10, 20, 0), {200, 255, 255, 255}, nil)
    c = calls[#calls]
    assert(c.name == "rect3d" and c[1] == gui and near(c[3][1], 0.08) and near(c[5][1], 0.04))
    call("draw_slug_icon", renderer, "res", 1, V3(500, 250, 0), V3(10, 10, 0), {255, 255, 255, 255},
        "mat", 3, nil)
    c = calls[#calls]
    assert(c.name == "icon3d" and c[1] == gui and c[9] == "material" and c[10] == "mat" and c[11] == nil,
        "world surface: icon keeps its material but carries no material flags")
    seen_gui_during_draw = renderer.gui
end)
assert(seen_gui_during_draw == stock_gui, "the renderer's own GUI is restored between routed calls")

-- A failing draw restores everything and propagates the error.
api.Gui2.bitmap_3d = function() error("boom", 0) end
local failed, err = pcall(MarkerWorld.draw, world_scope, "left", function()
    call("script_draw_bitmap", renderer, "m", V3(0, 0, 0), V3(1, 1, 0), nil, nil)
end)
assert(not failed and err == "boom")
assert(renderer.gui == stock_gui and renderer.render_settings.snap_pixel_positions == true)
assert(MarkerWorld.state.scope == nil and MarkerWorld.state.errors == 1)

-- Destruction releases the renderer's world GUI once.
MarkerWorld.destroy(renderer)
assert(gui.destroyed and MarkerWorld.state.guis[renderer] == nil)
MarkerWorld.destroy(renderer)
MarkerWorld.gui_for(other)
MarkerWorld.destroy_all()
assert(next(MarkerWorld.state.guis) == nil)
assert(MarkerWorld.set_surface("world") and MarkerWorld.set_surface("screen") and
    not MarkerWorld.set_surface("nowhere"))
print("marker_world.result=pass")
