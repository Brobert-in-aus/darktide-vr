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
        create_material = function(gui, name) return {instance_of = name, gui = gui} end,
        destroy_material = record("destroy_material"),
        HorizontalAlignCenter = 11, HorizontalAlignRight = 12,
        VerticalAlignCenter = 21, VerticalAlignTop = 22},
    Gui2 = {bitmap_3d = record("gui2_bitmap3d")},
    Material = {set_scalar = record("set_scalar")},
    UIFonts = {data_by_type = function(kind) return {path = "font/" .. kind, render_flags = 16} end},
    World = {create_world_gui = function(world) return {world = world} end,
        destroy_gui = function(world, gui) gui.destroyed = true end},
    Matrix4x4 = {identity = function() return "identity" end},
    material_flags = function() return 7 end,
}
MarkerWorld.configure(api)
assert(MarkerWorld.state.surface == "atlas" and MarkerWorld.state.text_origin == "top")
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
        c[5] == 1103, "world surface: bare bitmap call on the world GUI, layer with the base")
    local args = c[6]
    assert(near(args.position_offset[1], 0.2) and near(args.position_offset[2], -0.1) and
        near(args.size[1], 0.1) and args.color[1] == 100 and args.snap_pixel_positions == false and
        args.uv00 == nil, "world surface in metres, tinted, unsnapped")
    call("script_draw_bitmap_uv", renderer, "m", V3(1000, 500, 1), V3(2, 2, 0), {{0, 0}, {1, 1}}, nil, nil)
    c = calls[#calls]
    assert(c.name == "gui2_bitmap3d" and c[6].uv00[1] == 0 and c[6].uv11[1] == 1 and c[6].color == nil)
    -- A per-pass material handle (scale_to_material) becomes the world GUI's
    -- own instance of the same name, with ui_scale in metres per logical unit.
    local handle = {}
    MarkerWorld.note_material(handle, "content/ui/materials/frame")
    call("script_draw_bitmap", renderer, handle, V3(1000, 500, 1), V3(2, 2, 0), nil, nil)
    c = calls[#calls]
    assert(c.name == "gui2_bitmap3d" and c[2].instance_of == "content/ui/materials/frame" and c[2].gui == gui,
        "world surface: own material instance for a handle")
    local scalar = calls[#calls - 1]
    assert(scalar.name == "set_scalar" and scalar[1] == c[2] and scalar[2] == "ui_scale" and
        near(scalar[3], 2 * 0.002), "ui_scale is renderer scale times pixel size")
    call("script_draw_bitmap", renderer, handle, V3(1000, 500, 1), V3(2, 2, 0), nil, nil)
    assert(calls[#calls][2] == c[2], "instance reused")
    local unknown = {}
    call("script_draw_bitmap", renderer, unknown, V3(1000, 500, 1), V3(2, 2, 0), nil, nil)
    assert(calls[#calls][2] == unknown, "an unknown handle passes through")
    call("script_draw_text", renderer, "hi", 30, "body", V3(1000, 500, 2), V2(200, 40), {255, 9, 9, 9},
        {horizontal_alignment = api.Gui.HorizontalAlignCenter}, nil)
    c = calls[#calls]
    assert(c.name == "slug3d" and c[1] == gui and c[2] == "hi" and c[3] == "font/body" and
        near(c[4], 0.06) and c[5] == "tm" and near(c[6][1], 0.16) and near(c[6][2], 0.04) and
        c[7] == 1102 and c[8][1] == 127.5 and c[9] == "flags" and c[10] == 16,
        "world surface: bare slug text with the font's own flags")
    call("draw_rect", renderer, V3(520, 240, 5), V3(10, 20, 0), {200, 255, 255, 255}, nil)
    c = calls[#calls]
    assert(c.name == "rect3d" and c[1] == gui and near(c[3][1], 0.08) and near(c[5][1], 0.04) and c[4] == 1105)
    call("draw_slug_icon", renderer, "res", 1, V3(500, 250, 0), V3(10, 10, 0), {255, 255, 255, 255},
        "mat", 3, nil)
    c = calls[#calls]
    assert(c.name == "icon3d" and c[1] == gui and c[6] == 1101 and c[9] == "material" and c[10] == "mat" and
        c[11] == nil, "world surface: icon keeps its material but carries no material flags")
    assert(MarkerWorld.set_layer_base(0) and MarkerWorld.state.layer_base == 0 and
        not MarkerWorld.set_layer_base("x"))
    MarkerWorld.set_layer_base(1000)
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

-- Destruction releases the renderer's world GUI and its material instances once.
MarkerWorld.destroy(renderer)
assert(gui.destroyed and MarkerWorld.state.guis[renderer] == nil)
assert(calls[#calls].name == "destroy_material" and MarkerWorld.state.world_materials[gui] == nil)
MarkerWorld.destroy(renderer)
MarkerWorld.gui_for(other)
MarkerWorld.destroy_all()
assert(next(MarkerWorld.state.guis) == nil)
assert(MarkerWorld.set_surface("world") and MarkerWorld.set_surface("screen") and
    MarkerWorld.set_surface("atlas") and not MarkerWorld.set_surface("nowhere"))

-- Atlas surface: the stock function itself on the atlas renderer, the anchor
-- moved to the cell centre (pixels for script_*, logical units otherwise),
-- per-handle material instances with their recorded values replayed, and
-- the atlas renderer's borrowed fields cleared afterwards.
local target = {gui = "atlas_gui"}
local instances, replayed = {}, {}
local atlas = {
    renderer = function() return target end,
    material = function(handle, name, values)
        instances[#instances + 1] = {handle = handle, name = name}
        for key, value in pairs(values or {}) do replayed[key] = value end
        return "instance:" .. name
    end,
}
local atlas_scope = {renderer = renderer, surface = "atlas", atlas = atlas,
    atlas_x = 512, atlas_y = 256, origin_x = 100, origin_y = 40}
local seen = {}
local function stock(name) return function(self, ...)
    seen[#seen + 1] = {name = name, self = self, scale = self.scale,
        settings = self.render_settings, ...}
    return name
end end
local handle = {}
MarkerWorld.note_material(handle, "content/ui/materials/hud/backgrounds/interaction_background")
MarkerWorld.note_value("set_scalar", handle, "ui_scale", 2)
MarkerWorld.note_value("set_scalar", {}, "ignored", 1)
MarkerWorld.draw(atlas_scope, "left", function()
    MarkerWorld.route("script_draw_bitmap", stock("bitmap"), renderer, handle,
        V3(144, 0, 3), V3(440, 111, 0), {255, 255, 255, 255})
    MarkerWorld.route("script_draw_text", stock("text"), renderer, "Title", 22, "proxima",
        V3(180, 40, 5), V3(390, 42, 0), {255, 1, 2, 3}, {})
    MarkerWorld.route("draw_rect", stock("rect"), renderer, V3(50, 10, 4), V3(220, 21, 0), nil)
    MarkerWorld.route("draw_slug_icon", stock("icon"), renderer, "res", 1, V3(0, 0, 1),
        V3(10, 10, 0), {255, 255, 255, 255}, nil, nil)
    MarkerWorld.route("script_draw_bitmap", stock("bitmap"), renderer, {}, V3(0, 0, 0),
        V3(1, 1, 0), nil)
end)
assert(#seen == 4, "an unknown material handle is not drawn on the atlas GUI")
assert(seen[1].self == target and seen[1].scale == 2 and seen[1].settings == renderer.render_settings)
assert(seen[1][1] == "instance:content/ui/materials/hud/backgrounds/interaction_background")
assert(seen[1][2][1] == 556 and seen[1][2][2] == 216 and seen[1][2][3] == 3 and seen[1][3][1] == 440,
    "script_draw_bitmap shifts by the cell offset in pixels and keeps its size")
assert(replayed.ui_scale and replayed.ui_scale[1] == "set_scalar" and replayed.ui_scale[3] == 2)
assert(seen[2][4][1] == 592 and seen[2][4][2] == 256 and seen[2][7] ~= nil, "text keeps its box and options")
assert(seen[3][1][1] == 256 and seen[3][1][2] == 118, "draw_rect shifts in logical units")
assert(seen[4][3][1] == 206 and seen[4][3][2] == 108)
assert(target.render_settings == nil and target.scale == nil and MarkerWorld.state.atlas_skipped == 1)
assert(renderer.render_settings.snap_pixel_positions == true, "the atlas keeps stock pixel snapping")
-- Mirror: each routed draw on the source runs as stock, then again on the
-- target moved by the mirror offset; retained draws are not repeated and the
-- stock result is returned.
seen = {}
local mirror_target = {gui = "panel_gui"}
local mirror_atlas = {
    renderer = function() return mirror_target end,
    material = function(h, name) return "panel:" .. name end,
}
local source = {gui = "overlay_gui", scale = 1, render_settings = {start_layer = 0}}
local results = {MarkerWorld.mirror(mirror_atlas, source, 1, 0, -1116, function()
    local a = MarkerWorld.route("script_draw_text", stock("text"), source, "hello", 20, "proxima",
        V3(40, 2000, 1), V3(300, 30, 0), {255, 255, 255, 255}, {})
    local b = MarkerWorld.route("script_draw_bitmap", stock("bitmap"), source, handle,
        V3(40, 1990, 0), V3(320, 200, 0), nil, 7)
    local c = MarkerWorld.route("draw_rect", stock("rect"), {gui = "other"}, V3(0, 0, 0), V3(1, 1, 0), nil)
    return a, b, c
end)}
assert(results[1] == "text" and results[2] == "bitmap" and results[3] == "rect")
assert(#seen == 4, "text twice, retained bitmap once, other renderer once")
assert(seen[1].self == source and seen[2].self == mirror_target)
assert(seen[2][4][1] == 40 and seen[2][4][2] == 884, "the copy moves by the mirror offset")
assert(seen[3].self == source and seen[3][5] == 7 and seen[4].self.gui == "other")
assert(mirror_target.render_settings == nil and MarkerWorld.state.mirror == nil)
-- A mirror factor draws the copy larger about the target origin: pixel calls
-- scale position, size and font size; logical calls go through the target's
-- scale; a recorded ui_scale is scaled for the copy's material instance.
seen = {}
local replayed_scale
mirror_atlas.material = function(h, name, values)
    replayed_scale = values and values.ui_scale and values.ui_scale[3]
    return "panel:" .. name
end
MarkerWorld.note_value("set_scalar", handle, "ui_scale", 1.1)
MarkerWorld.mirror(mirror_atlas, source, 2, 0, 0, function()
    MarkerWorld.route("script_draw_text", stock("text"), source, "hi", 20, "proxima",
        V3(40, 100, 1), V3(300, 30, 0), {255, 255, 255, 255}, {})
    MarkerWorld.route("script_draw_bitmap", stock("bitmap"), source, handle,
        V3(10, 20, 0), V3(30, 40, 0), nil)
    MarkerWorld.route("draw_rect", stock("rect"), source, V3(5, 6, 0), V3(7, 8, 0), nil)
end)
assert(seen[2].self == mirror_target and seen[2][2] == 40 and seen[2][4][1] == 80 and
    seen[2][4][2] == 200 and seen[2][5][1] == 600, "text copy scaled by the factor")
assert(seen[4][2][1] == 20 and seen[4][2][2] == 40 and seen[4][3][1] == 60 and replayed_scale == 2.2)
assert(seen[6].self == mirror_target and seen[6].scale == 2 and seen[6][1][1] == 5,
    "logical calls scale through the target renderer")
assert(mirror_target.scale == nil and source.scale == 1)
-- Extents, kept per claimant. Three call sites claim atlas cells and one
-- maximum over all of them describes no cell that anything actually needs:
-- on 18 September a width from the interaction popup and a height that could
-- not have come from it were read as one marker's worst case, and the atlas
-- was resized from the pair. Here the two claimants cross deliberately --
-- one wide and short, one narrow and tall -- so a conflated maximum
-- (470 x 200) is a box NEITHER of them asks for.
local extent_log = {}
api.log = function(line) extent_log[#extent_log + 1] = line end
local clock_now = 100
Application = {time_since_launch = function() return clock_now end}
atlas.CELL_WIDTH, atlas.CELL_HEIGHT = 1024, 512
local extent = MarkerWorld.state.extent
extent.dx, extent.dy, extent.at, extent.per = 0, 0, nil, {}
local function text_in(claimant, width, height)
    MarkerWorld.draw({renderer = renderer, surface = "atlas", atlas = atlas,
        atlas_x = 512, atlas_y = 256, origin_x = 0, origin_y = 0,
        claimant = claimant}, "left", function()
        MarkerWorld.route("script_draw_text", stock("text"), renderer, "x", 20,
            "proxima", V3(0, 0, 0), V3(width, height, 0), {255, 255, 255, 255}, {})
    end)
end
text_in("interaction", 470, 30)
text_in("marker", 60, 200)
assert(#extent_log == 0, "the first second is the clock being started, not a report")
assert(extent.per.interaction and extent.per.marker,
    "each claimant is measured under its own name, not pooled under one")
assert(near(extent.per.interaction.dx, 470) and near(extent.per.interaction.dy, 30),
    "the popup's box is measured against the popup")
assert(near(extent.per.marker.dx, 60) and near(extent.per.marker.dy, 200))
assert(near(extent.dx, 470) and near(extent.dy, 200),
    "the conflated maximum is 470 x 200 -- and neither claimant needs that cell")
assert(extent.per.interaction.dy < extent.per.marker.dy and
    extent.per.marker.dx < extent.per.interaction.dx,
    "sizing a cell from the conflated pair spends height on the wide claimant")

-- The tick is driven by whichever claimant happens to draw on it, so every
-- claimant that grew is said -- including one that has since left the screen.
clock_now = 102
text_in("marker", 10, 10)
local said = {}
for i = 1, #extent_log do
    local who = string.match(extent_log[i], "claimant=(%a+) ")
    assert(who, "every extents line names the claimant it measured: " .. extent_log[i])
    local dx, dy = string.match(extent_log[i], "max_dx=([%d%.]+) max_dy=([%d%.]+)")
    said[who] = {tonumber(dx), tonumber(dy)}
    assert(string.find(extent_log[i], "half_cell=512.0,256.0", 1, true),
        "the line carries the cell it is being judged against")
end
assert(said.interaction and near(said.interaction[1], 470) and near(said.interaction[2], 30),
    "a claimant that grew on an earlier tick is still reported by name")
assert(said.marker and near(said.marker[1], 60) and near(said.marker[2], 200),
    "a claimant reports its own worst case over the run, not its latest draw")
assert(#extent_log == 2, "one line per claimant, not one conflated line")

-- Nothing grew, so the next tick says nothing: the report is throttled per
-- claimant, not silenced globally by another claimant's growth.
clock_now = 104
text_in("marker", 10, 10)
assert(#extent_log == 2, "a claimant that has not grown is not repeated")
clock_now = 106
text_in("interaction", 471, 30)
assert(#extent_log == 3 and string.find(extent_log[3], "claimant=interaction", 1, true),
    "growth after another claimant reported is still said")

-- The throttle is the claimant's own. A smaller claimant growing INSIDE the
-- largest one's box moves nothing global -- 471 x 200 stays 471 x 200 -- and
-- a report gated on the overall maximum would say nothing, which is how a
-- short-lived claimant is silenced by a big one for a whole session.
clock_now = 108
text_in("marker", 100, 50)
assert(near(extent.dx, 471) and near(extent.dy, 200), "the overall maximum has not moved")
assert(#extent_log == 4, "a claimant growing inside another's box is still reported")
assert(string.find(extent_log[4], "claimant=marker max_dx=100.0 max_dy=200.0", 1, true),
    "and it is reported with its own worst case, width from now and height from before")
Application = nil

print("marker_world.result=pass")
