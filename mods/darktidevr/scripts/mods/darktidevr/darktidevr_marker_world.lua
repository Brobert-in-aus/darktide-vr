-- World-surface markers. Every primitive a stock world-marker widget draws is
-- placed on a plane through the marker's world anchor, facing the shared head
-- centre, sized so one primary-projection pixel keeps its angle at that
-- distance. The stock widget draws unchanged; while it draws, the renderer's
-- 2D entry points are converted into its 3D counterparts (bitmap_3d,
-- slug_text_3d, slug_icon_3d, rect_3d) with a transform.
--
-- Two surfaces:
--  "world" (default): the transform places the surface in the level world
--    on a world GUI and the engine renders it for both eyes (worn: correct
--    stereo). The draws are issued the way the HUD panel issues its own
--    world quad, with no render pass and no material flags: with the HUD
--    renderer's pass and flags attached they depth-tested against the
--    scene; the HUD panel, drawn bare, shows in front of everything.
--  "screen": the transform is each eye's own projection of the plane into
--    the overlay GUI, drawn by the first-eye draw and the right-eye replay.
--    Kept for comparison; its per-eye scale did not match the render.
--
-- This module owns no engine hooks. The marker metrics module owns the single
-- hook on each 2D renderer entry point and calls `route`; the marker GUI
-- module owns the renderer destroy hook and calls `destroy`.
local MarkerWorld = {}

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

-- Plane basis and per-pixel size for one anchor. Pure: plain {x,y,z} tables
-- in, unit axes and the metre size of one primary-projection pixel at the
-- anchor's distance out. `flip` reverses the facing convention.
function MarkerWorld.geometry(Plane, anchor, head_center, head_right, head_up,
        tangent_per_pixel, flip)
    local plane, reason = Plane.create(anchor, head_center, head_right, head_up,
        tangent_per_pixel, {x = 0, y = 0})
    if not plane then return nil, reason end
    local pixel_size = plane.distance * tangent_per_pixel
    if not finite(pixel_size) or pixel_size <= 0 then return nil, "invalid_scale" end
    local function unit(v)
        return {x = v.x / pixel_size, y = v.y / pixel_size, z = v.z / pixel_size}
    end
    local right, up, normal = unit(plane.x_axis), unit(plane.y_axis), plane.normal
    local sign = flip and -1 or 1
    return {
        right = {x = right.x * sign, y = right.y * sign, z = right.z * sign},
        forward = {x = normal.x * sign, y = normal.y * sign, z = normal.z * sign},
        up = up,
        anchor = {x = anchor.x, y = anchor.y, z = anchor.z},
        pixel_size = pixel_size,
        distance = plane.distance,
    }
end

-- Pass types whose draws the routing covers. A widget with any other pass
-- keeps the stock 2D route so a marker is never half on the plane.
local routed_pass_types = {
    texture = true, texture_uv = true, text = true, rect = true,
    slug_icon = true, logic = true,
}
function MarkerWorld.admits(widget)
    local passes = widget and widget.passes
    if type(passes) ~= "table" or #passes == 0 then return false, "no_passes" end
    for i = 1, #passes do
        local pass = passes[i]
        local kind = type(pass) == "table" and pass.pass_type
        if not routed_pass_types[kind] then return false, tostring(kind) end
        if pass.retained_mode then return false, "retained" end
    end
    return true
end

local state = {scope = nil, eye = nil, guis = {}, errors = 0, api = nil,
    surface = "atlas", text_mode = "slug", text_origin = "top", layer_base = 1000,
    material_names = setmetatable({}, {__mode = "k"}), world_materials = {},
    material_values = setmetatable({}, {__mode = "k"}), atlas_skipped = 0,
    -- Bumped on every recorded value, so a target that has applied a
    -- handle's values can skip replaying them until they change.
    material_revisions = setmetatable({}, {__mode = "k"})}
MarkerWorld.state = state

-- Diagnostics. `dump` logs every routed draw for the next frames; `probe`
-- draws, over each world-surface bitmap, a second quad with the HUD
-- panel's material (a placeholder texture instead of its render target):
-- if that quad shows in front of the scene while the bitmap does not, depth
-- testing is decided by the material.
local panel_material_name = "content/ui/materials/icons/items/containers/item_container_square"
function MarkerWorld.set_dump(frames)
    state.dump = tonumber(frames) or 1
    return true
end
function MarkerWorld.set_probe(enabled)
    state.probe = enabled == true
    return true
end
local function dump(kind, detail, x, y, w, h, layer)
    if not state.dump or state.dump <= 0 or not state.api.log then return end
    state.api.log(string.format(
        "DARKTIDEVR_MARKER_PLANE draw kind=%s detail=%s x=%.1f y=%.1f w=%.1f h=%.1f layer=%s",
        kind, tostring(detail), x, y, w, h, tostring(layer)))
end
function MarkerWorld.end_dump_frame()
    if state.dump and state.dump > 0 then state.dump = state.dump - 1 end
end
local function probe_material(gui)
    local entry = state.world_materials[gui]
    if not entry then
        entry = {}
        state.world_materials[gui] = entry
    end
    local instance = entry["<probe>"]
    if not instance then
        local api = state.api
        instance = api.Gui.create_material(gui, panel_material_name)
        if api.Material then
            api.Material.set_scalar(instance, "use_placeholder_texture", 1)
            api.Material.set_scalar(instance, "use_render_target", 0)
            api.Material.set_scalar(instance, "rows", 1)
            api.Material.set_scalar(instance, "columns", 1)
            api.Material.set_scalar(instance, "grid_index", 0)
        end
        entry["<probe>"] = instance
    end
    return instance
end

-- Layer added to every world-surface draw. The HUD panel draws its quad at
-- layer 1000 and shows in front of everything; marker passes sit at single
-- digits. Whether the layer decides that is what the setting tests.
function MarkerWorld.set_layer_base(value)
    value = tonumber(value)
    if not value then return false, "a number" end
    state.layer_base = value
    return true
end

-- Per-pass materials. Passes with material values or scale_to_material draw
-- through a material instance the renderer created for its own 2D GUI, with
-- "ui_scale" set to pixels per logical unit; the material sizes its frame
-- from that. On the world surface the same name gets its own instance on
-- the world GUI, with ui_scale in metres per logical unit, so a 9-slice
-- frame keeps its proportions. The owner of the renderer's create_material
-- hook reports each handle's name here.
function MarkerWorld.note_material(handle, name)
    if handle ~= nil and type(name) == "string" then
        state.material_names[handle] = name
    end
end

-- The owner of the Material setter hooks reports every value set on a
-- handle this module knows by name, so the atlas instance replays them.
function MarkerWorld.note_value(setter, handle, key, ...)
    if handle == nil or key == nil or not state.material_names[handle] then return end
    local values = state.material_values[handle]
    if not values then
        values = {}
        state.material_values[handle] = values
    end
    values[key] = {setter, select("#", ...), ...}
    state.material_revisions[handle] = (state.material_revisions[handle] or 0) + 1
end

local function world_material(scope, self, material, gui)
    if type(material) == "string" then return material end
    local name = state.material_names[material]
    if not name then return material end
    local api = state.api
    local entry = state.world_materials[gui]
    if not entry then
        entry = {}
        state.world_materials[gui] = entry
    end
    local instance = entry[name]
    if not instance then
        instance = api.Gui.create_material(gui, name)
        entry[name] = instance
    end
    if api.Material then
        api.Material.set_scalar(instance, "ui_scale", (self.scale or 1) * scope.pixel_size)
    end
    return instance
end

local surfaces = {screen = true, world = true, atlas = true}
function MarkerWorld.set_surface(mode)
    if surfaces[mode] then state.surface = mode; return true end
    return false, "screen or world"
end

-- How routed text is drawn: "slug" (the renderer's 3D slug text, laid out
-- here), "rect" (a marker box where the text would be), "2d" (text stays on
-- the flat route while everything else is on the plane).
local text_modes = {slug = true, rect = true, ["2d"] = true}
function MarkerWorld.set_text_mode(mode)
    if text_modes[mode] then state.text_mode = mode; return true end
    return false, "slug, rect or 2d"
end

-- Where the 3D text call anchors its position: "top" (the glyphs hang below
-- it) or "bottom" (they stand on it). Worn evidence decides.
local text_origins = {top = true, bottom = true}
function MarkerWorld.set_text_origin(mode)
    if text_origins[mode] then state.text_origin = mode; return true end
    return false, "top or bottom"
end

-- `api` supplies UIRenderer, UIFonts, Vector2, Vector3, Color, Gui, Gui2,
-- World, Matrix4x4, material_flags(renderer, flags) and log(line) so the
-- module stays testable.
function MarkerWorld.configure(api)
    state.api = api
end

function MarkerWorld.gui_for(renderer)
    local api = state.api
    local entry = state.guis[renderer]
    if not entry then
        entry = {world = renderer.world,
            gui = api.World.create_world_gui(renderer.world, api.Matrix4x4.identity(),
                1, 1, "immediate")}
        state.guis[renderer] = entry
    end
    return entry.gui
end

function MarkerWorld.destroy(renderer)
    local entry = state.guis[renderer]
    if entry then
        state.guis[renderer] = nil
        local materials = state.world_materials[entry.gui]
        state.world_materials[entry.gui] = nil
        if materials and state.api.Gui.destroy_material then
            for _, instance in pairs(materials) do
                pcall(state.api.Gui.destroy_material, entry.gui, instance)
            end
        end
        state.api.World.destroy_gui(entry.world, entry.gui)
    end
end

function MarkerWorld.destroy_all()
    for renderer in pairs(state.guis) do MarkerWorld.destroy(renderer) end
end

-- A scope describes one surface: {renderer, surface, eyes = {left = {tm,
-- origin_x, origin_y}, right = {...}}, pixel_size, tm, gui}. The screen
-- surface uses eyes[eye] (pixel units, the eye's projection); the world
-- surface uses tm/gui/pixel_size (metres). `eye` is "left" or "right".
function MarkerWorld.draw(scope, eye, draw, ...)
    local previous_scope, previous_eye = state.scope, state.eye
    local settings = scope.renderer.render_settings
    local snap = settings and settings.snap_pixel_positions
    -- Plane-local coordinates must not be rounded to whole pixels; the atlas
    -- draws stock 2D and keeps the stock setting.
    if settings and scope.surface ~= "atlas" then settings.snap_pixel_positions = false end
    state.scope, state.eye = scope, eye
    local results = {pcall(draw, ...)}
    state.scope, state.eye = previous_scope, previous_eye
    if settings then settings.snap_pixel_positions = snap end
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

-- Resolve the transform, origin, pixel scale and GUI for the current draw.
local function frame(scope)
    if scope.surface == "world" then
        return scope.tm, scope.origin_x, scope.origin_y, scope.pixel_size, scope.gui
    end
    local eye = scope.eyes and scope.eyes[state.eye or "left"]
    if not eye then return nil end
    return eye.tm, eye.origin_x, eye.origin_y, 1, nil
end

local function with_gui(scope, gui, fn, ...)
    local renderer = scope.renderer
    local original = renderer.gui
    if gui then renderer.gui = gui end
    local results = {pcall(fn, ...)}
    renderer.gui = original
    if not results[1] then
        state.errors = state.errors + 1
        error(results[2], 0)
    end
    return unpack(results, 2)
end

local converters = {}

-- Stock colour handling: alpha multiplied by the render settings' alpha, the
-- channels by their intensity; nil stays nil (engine default).
local function tint(self, color)
    if not color then return nil end
    local settings = self.render_settings
    local alpha = settings and settings.alpha_multiplier or 1
    local intensity = settings and settings.color_intensity_multiplier or 1
    return state.api.Color(color[1] * alpha, color[2] * intensity, color[3] * intensity,
        color[4] * intensity)
end

local function start_layer(self)
    local settings = self.render_settings
    return settings and settings.start_layer or 0
end

-- The world surface draws bare, as the HUD panel does (Gui2.bitmap_3d with
-- no material flags and no render pass); the screen surface goes through
-- the renderer's 3D function, which adds the overlay's pass and flags.
local function draw_bitmap(scope, self, material, position, size, uvs, color)
    local tm, ox, oy, ps, gui = frame(scope)
    local api = state.api
    local offset = api.Vector3((position[1] - ox) * ps, (position[2] - oy) * ps, 0)
    local extent = api.Vector3(size[1] * ps, size[2] * ps, 0)
    if scope.surface == "world" then
        local args = {position_offset = offset, size = extent, color = tint(self, color),
            snap_pixel_positions = false}
        if uvs then
            args.uv00 = api.Vector2(uvs[1][1], uvs[1][2])
            args.uv11 = api.Vector2(uvs[2][1], uvs[2][2])
        end
        local instance = world_material(scope, self, material, gui)
        local layer = (position[3] or 0) + start_layer(self) + state.layer_base
        dump("bitmap", type(material) == "string" and material or
            (state.material_names[material] or "handle"), position[1] - ox, position[2] - oy,
            size[1], size[2], layer)
        return with_gui(scope, nil, function()
            local result = api.Gui2.bitmap_3d(gui, instance, nil, tm, layer, args)
            if state.probe then
                api.Gui2.bitmap_3d(gui, probe_material(gui), nil, tm, layer + 1,
                    {position_offset = offset, size = extent, color = api.Color(255, 255, 255, 255),
                     snap_pixel_positions = false})
            end
            return result
        end)
    end
    return with_gui(scope, gui, api.UIRenderer.script_draw_bitmap_3d, self, material, tm,
        offset, position[3] or 0, extent, color, uvs, nil)
end

converters.script_draw_bitmap = function(scope, func, self, material, position, size,
        color, retained_id)
    local tm = frame(scope)
    if retained_id or not tm then
        return func(self, material, position, size, color, retained_id)
    end
    return draw_bitmap(scope, self, material, position, size, nil, color)
end

converters.script_draw_bitmap_uv = function(scope, func, self, material, position, size,
        uvs, color, retained_id)
    local tm = frame(scope)
    if retained_id or not tm then
        return func(self, material, position, size, uvs, color, retained_id)
    end
    return draw_bitmap(scope, self, material, position, size, uvs, color)
end

converters.script_draw_text = function(scope, func, self, text, font_size, font_type,
        position, size, color, options, retained_id)
    local mode = state.text_mode
    local tm, ox, oy, ps, gui = frame(scope)
    if retained_id or mode == "2d" or not tm then
        return func(self, text, font_size, font_type, position, size, color, options,
            retained_id)
    end
    local api = state.api
    local layer = position[3] or 0
    if mode == "rect" then
        local box = size and api.Vector2(size[1] * ps, size[2] * ps) or
            api.Vector2(100 * ps, font_size * ps)
        return with_gui(scope, gui, function()
            return api.Gui.rect_3d(gui or self.gui, tm,
                api.Vector2((position[1] - ox) * ps, (position[2] - oy) * ps), layer, box,
                api.Color(200, 255, 0, 255))
        end)
    end
    -- The engine's 3D slug text takes no layout box and no layout options
    -- (given either it rejects the call), so the text is laid out here: its
    -- extent is measured at the 2D size, the box's alignment becomes an
    -- offset, and the call gets only the position, font size and colour.
    local dx, dy = 0, 0
    local height = font_size
    if type(options) == "table" and api.UIRenderer.text_size then
        local ok, width, measured = pcall(api.UIRenderer.text_size, self, text, font_type,
            font_size, size, options, true)
        if ok and type(width) == "number" and type(measured) == "number" then
            height = measured
            if size then
                local gui_enum = api.Gui
                local horizontal = options.horizontal_alignment
                local vertical = options.vertical_alignment
                if horizontal == gui_enum.HorizontalAlignCenter then
                    dx = (size[1] - width) * 0.5
                elseif horizontal == gui_enum.HorizontalAlignRight then
                    dx = size[1] - width
                end
                if vertical == gui_enum.VerticalAlignCenter then
                    dy = (size[2] - height) * 0.5
                elseif vertical == gui_enum.VerticalAlignTop then
                    dy = size[2] - height
                end
            end
        end
    end
    -- The offsets above place the text's bottom edge; if the call anchors the
    -- glyphs' top, raise the position by the text height.
    if state.text_origin == "top" then dy = dy + height end
    local x = (position[1] + dx - ox) * ps
    local y = (position[2] + dy - oy) * ps
    if not state.text_logged and api.log then
        state.text_logged = true
        api.log(string.format(
            "DARKTIDEVR_MARKER_PLANE first_text surface=%s mode=%s origin=%s font=%s size_px=%s layer=%s box=%s offset=%.1f,%.1f height=%.1f",
            state.surface, mode, state.text_origin, tostring(font_type), tostring(font_size),
            tostring(layer), tostring(size ~= nil), dx, dy, height))
    end
    if scope.surface == "world" then
        -- Bare slug text: the font's own render flags only.
        local font_data = api.UIFonts and api.UIFonts.data_by_type(font_type)
        if not font_data then
            return func(self, text, font_size, font_type, position, size, color, options,
                retained_id)
        end
        dump("text", text, position[1] + dx - ox, position[2] + dy - oy, size and size[1] or 0,
            size and size[2] or 0, layer + start_layer(self) + state.layer_base)
        return with_gui(scope, nil, function()
            return api.Gui.slug_text_3d(gui, text, font_data.path, font_size * ps, tm,
                api.Vector3(x, y, 0), layer + start_layer(self) + state.layer_base,
                tint(self, color), "flags", font_data.render_flags or 0)
        end)
    end
    return with_gui(scope, gui, api.UIRenderer.script_draw_text_3d, self, text,
        font_size * ps, font_type, tm, api.Vector3(x, y, 0), layer, nil, color, nil, nil)
end

converters.draw_rect = function(scope, func, self, position, size, color, retained_id)
    local tm, ox, oy, ps, gui = frame(scope)
    if retained_id or not tm then return func(self, position, size, color, retained_id) end
    -- Stock scales logical units here and applies start layer, alpha and
    -- intensity before Gui2.rect; do the same for rect_3d.
    local api = state.api
    local scale = self.scale or 1
    local settings = self.render_settings
    local layer = (position[3] or 0) + (settings and settings.start_layer or 0)
    local alpha = settings and settings.alpha_multiplier or 1
    local intensity = settings and settings.color_intensity_multiplier or 1
    local tinted = color and api.Color(color[1] * alpha, color[2] * intensity,
        color[3] * intensity, color[4] * intensity) or api.Color(255, 255, 255, 255)
    if scope.surface == "world" then
        layer = layer + state.layer_base
        dump("rect", "", position[1] * scale - ox, position[2] * scale - oy,
            size[1] * scale, size[2] * scale, layer)
    end
    return with_gui(scope, gui, function()
        return api.Gui.rect_3d(gui or self.gui, tm,
            api.Vector2((position[1] * scale - ox) * ps, (position[2] * scale - oy) * ps),
            layer, api.Vector2(size[1] * scale * ps, size[2] * scale * ps), tinted)
    end)
end

converters.draw_slug_icon = function(scope, func, self, resource, index, position, size,
        color, optional_material, material_flags, retained_id)
    local tm, ox, oy, ps, gui = frame(scope)
    if retained_id or not tm then
        return func(self, resource, index, position, size, color, optional_material,
            material_flags, retained_id)
    end
    -- Same route as the stock rotated icon: the transform and the offset in
    -- plane-local units.
    local api = state.api
    local scale = self.scale or 1
    local settings = self.render_settings
    local layer = (settings and settings.start_layer or 0) + math.max(position[3] or 0, 1)
    local alpha = settings and settings.alpha_multiplier or 1
    local intensity = settings and settings.color_intensity_multiplier or 1
    local tinted = api.Color(color[1] * alpha, color[2] * intensity,
        color[3] * intensity, color[4] * intensity)
    local params = {}
    if optional_material then
        params[#params + 1] = "material"; params[#params + 1] = optional_material
    end
    -- The world surface carries no material flags (they bound the draw to the
    -- HUD's depth-tested pass); the screen surface keeps the stock ones.
    local flags = scope.surface ~= "world" and api.material_flags and
        api.material_flags(self, material_flags)
    if flags then
        params[#params + 1] = "material_flags"; params[#params + 1] = flags
    end
    if scope.surface == "world" then
        layer = layer + state.layer_base
        dump("icon", tostring(resource) .. "#" .. tostring(index), position[1] * scale - ox,
            position[2] * scale - oy, size[1] * scale, size[2] * scale, layer)
    end
    return with_gui(scope, gui, function()
        return api.Gui.slug_icon_3d(gui or self.gui, resource, index, tm,
            api.Vector3((position[1] * scale - ox) * ps, (position[2] * scale - oy) * ps, 0),
            layer, api.Vector2(size[1] * scale * ps, size[2] * scale * ps), tinted,
            unpack(params))
    end)
end

-- Called by the owner of the renderer hooks with the hooked name, the stock
-- function and its arguments. Outside a marker draw, for another renderer,
-- or for a name without a converter, the stock call runs.
-- Atlas surface: the stock call itself, on the atlas renderer, with the
-- marker's anchor moved to its cell centre. Scaled entry points (script_*)
-- shift in pixels, unscaled ones (draw_rect, draw_slug_icon) in logical units.
local atlas_converters = {}

local function pack(...)
    return {n = select("#", ...), ...}
end

local function atlas_call(scope, self, func, ...)
    local target = scope.atlas.renderer()
    if not target then return nil end
    local settings, scale, inverse = target.render_settings, target.scale, target.inverse_scale
    local factor = scope.factor or 1
    target.render_settings = self.render_settings
    target.scale = self.scale and self.scale * factor
    target.inverse_scale = target.scale and 1 / target.scale or self.inverse_scale
    local profile = state.api.profile
    local mark = profile and profile.begin()
    local results = pack(pcall(func, target, ...))
    if mark then profile.finish("marker.atlas_call", mark) end
    target.render_settings, target.scale, target.inverse_scale = settings, scale, inverse
    if not results[1] then
        state.errors = state.errors + 1
        error(results[2], 0)
    end
    return unpack(results, 2, results.n)
end

-- nil means the handle cannot be drawn on the atlas GUI: the draw is skipped
-- (a source-GUI handle on another GUI fails in the renderer).
local function atlas_material(scope, material)
    if material == nil or type(material) == "string" then return material, true end
    local name = state.material_names[material]
    if not name then return nil, false end
    local values = state.material_values[material]
    local factor = scope.factor or 1
    if factor ~= 1 and values and values.ui_scale then
        -- ui_scale is pixels per logical unit; the copy draws `factor` larger.
        local scaled = {}
        for key, record in pairs(values) do scaled[key] = record end
        local ui_scale = values.ui_scale
        scaled.ui_scale = {ui_scale[1], ui_scale[2], (tonumber(ui_scale[3]) or 1) * factor}
        values = scaled
    end
    -- At factor 1 `values` is the recorded table itself, so its revision
    -- stamps the call and the atlas skips a replay it has already applied
    -- (profile doc: the replay ran on every primitive of every frame).
    local stamp = factor == 1 and state.material_revisions[material] or nil
    local instance = scope.atlas.material(material, name, values, stamp)
    return instance, instance ~= nil
end

-- Positions move to the target: the cell or mirror offset (target pixels),
-- and a mirror's `factor` about the target origin. Pixel entry points
-- (script_*) pass no `logical_scale`; the logical ones (draw_rect,
-- draw_slug_icon) pass the renderer scale, and their factor is applied
-- through the target renderer's scale instead.
-- The largest offset a routed draw has asked for, from its cell's centre, in
-- target pixels. A marker's content is not clipped to its cell: the hand
-- displays' sliver beside the ammo count was content laid out past the cell
-- edge, and the pickup markers' sliver (worn, 17 September) is the same
-- question with nothing measuring it. Reported when a new maximum stands for
-- a second, so a log carries the worst case without a line per draw.
-- Kept PER CLAIMANT, not as one maximum over everything that claims a cell.
-- One conflated maximum cannot say which claimant sets the cell size: on
-- 18 September it produced a width and a height that could not have come from
-- the same marker, and the atlas was resized from them. `per[claimant]` is
-- what a grid can actually be designed against -- if the popup is the only
-- thing needing 428 px, the other cells do not.
--
-- A claimant is one of Darktide's twenty world-marker TEMPLATE names
-- (nameplate, objective, beacon, ...), not the word "marker": pooling every
-- marker type together rebuilds the same conflation one level down, in the
-- bucket with the most varied content (review, 18 September). The two HUD
-- elements that claim cells whole are named `hud_interaction_popup` and
-- `hud_tag_prompt`, prefixed because one of those template names is itself
-- "interaction" -- a different thing, and a different size, from the popup.
state.extent = {dx = 0, dy = 0, at = nil, per = {}}
-- `dtvr_marker_plane drop|text|origin` change what is being measured while a
-- sizing session is under way -- `drop` moves the very origin every extent is
-- taken from -- so a maximum spanning one of those is a number no
-- configuration ever produced. Start again, and say so in the log rather than
-- letting the next report look like a quiet one (review, 18 September).
function MarkerWorld.forget_extents(why)
    local extent = state.extent
    -- `extent.at` is deliberately left alone: it is the last report's time,
    -- not a measurement, and clearing it sends the next draw down the "start
    -- the clock" branch, pushing the first report a full second past it --
    -- losing the short-lived claimant a reset exists to watch (review,
    -- 18 September).
    extent.dx, extent.dy, extent.per = 0, 0, {}
    if state.api and state.api.log then
        state.api.log("DARKTIDEVR_MARKER extents reset=" .. tostring(why))
    end
    return true
end
-- The report runs on every call, not only when a new maximum arrives: a
-- maximum that lands less than a second after the last report and is never
-- beaten again was simply never said, and a marker on screen for half a
-- second -- an interaction prompt, a tag -- is exactly that (review,
-- 18 September). That is how a run reported a smaller worst case than it saw.
local function observe_extent(x, y, scope_atlas, width, height, claimant)
    local extent = state.extent
    local who = claimant or "?"
    local slot = extent.per[who]
    if not slot then
        slot = {dx = 0, dy = 0, reported_dx = 0, reported_dy = 0, boxless = 0}
        extent.per[who] = slot
    end
    -- Text drawn with no layout box is measured by its anchor alone and
    -- contributes ZERO width, so a cell could be sized without the widest
    -- thing on it (review, 18 September). Only `script_draw_text` can arrive
    -- without a size; every other converter passes one. The engine can say
    -- how wide such text is, but not for free on a per-draw path, so this
    -- COUNTS the blind spot rather than closing it: if a run says boxless=0
    -- there is nothing to buy, and if it does not, the count says how much
    -- the measurement is missing before anything is paid for it.
    if width == nil and height == nil then
        slot.boxless = (slot.boxless or 0) + 1
    end
    -- A draw's box, not its anchor. `position` is one corner and the size
    -- runs from it, so both corners are watched: an anchor at +10 with a
    -- 40 px size reaches 50, and measuring only the anchor said 10 (18
    -- September, sizing the atlas).
    local x2 = x + (tonumber(width) or 0)
    local y2 = y + (tonumber(height) or 0)
    local ax = math.max(x < 0 and -x or x, x2 < 0 and -x2 or x2)
    local ay = math.max(y < 0 and -y or y, y2 < 0 and -y2 or y2)
    if ax > extent.dx then extent.dx = ax end
    if ay > extent.dy then extent.dy = ay end
    if ax > slot.dx then slot.dx = ax end
    if ay > slot.dy then slot.dy = ay end
    local now = Application and Application.time_since_launch and Application.time_since_launch()
    if not now then return end
    if not extent.at then extent.at = now; return end
    if now - extent.at < 1 then return end
    extent.at = now
    local atlas = scope_atlas
    if not (state.api and state.api.log) then return end
    -- Every claimant that has grown since it was last said, not only the one
    -- drawing now: a claimant that reached its worst case and then left the
    -- screen still has to be reported, and the tick it grew on may be a
    -- different claimant's.
    for name, each in pairs(extent.per) do
        if each.dx > each.reported_dx + 0.5 or each.dy > each.reported_dy + 0.5 then
            each.reported_dx, each.reported_dy = each.dx, each.dy
            state.api.log(string.format(
                "DARKTIDEVR_MARKER extents claimant=%s max_dx=%.1f max_dy=%.1f half_cell=%.1f,%.1f boxed=1 boxless=%d",
                name, each.dx, each.dy, (atlas and atlas.CELL_WIDTH or 0) * 0.5,
                (atlas and atlas.CELL_HEIGHT or 0) * 0.5, each.boxless or 0))
        end
    end
end

local function shifted(scope, position, logical_scale, size)
    local factor = scope.factor or 1
    -- The cell question only. The HUD panel's mirror scope draws in full
    -- screen pixels about an origin of zero and has no cell at all, so
    -- including it would saturate the maximum and mask what this measures.
    if not scope.mirror and scope.atlas then
        local unit = logical_scale or 1
        observe_extent((position[1] or 0) * unit * factor - scope.origin_x,
            (position[2] or 0) * unit * factor - scope.origin_y, scope.atlas,
            size and (size[1] or 0) * unit * factor,
            size and (size[2] or 0) * unit * factor, scope.claimant)
    end
    local dx = scope.atlas_x - scope.origin_x
    local dy = scope.atlas_y - scope.origin_y
    local unit = logical_scale
    if not unit then
        return state.api.Vector3(position[1] * factor + dx, position[2] * factor + dy,
            position[3] or 0)
    end
    return state.api.Vector3(position[1] + dx / (unit * factor), position[2] + dy / (unit * factor),
        position[3] or 0)
end

local function sized(scope, size)
    local factor = scope.factor or 1
    if factor == 1 or not size then return size end
    return state.api.Vector3(size[1] * factor, size[2] * factor, size[3] or 0)
end

atlas_converters.script_draw_bitmap = function(scope, func, self, material, position, size,
        color, retained_id)
    if retained_id then
        if scope.mirror then return nil end
        return func(self, material, position, size, color, retained_id)
    end
    local instance, ok = atlas_material(scope, material)
    if not ok then state.atlas_skipped = state.atlas_skipped + 1; return nil end
    dump("atlas_bitmap", state.material_names[material] or material, position[1] - scope.origin_x,
        position[2] - scope.origin_y, size[1], size[2], position[3])
    return atlas_call(scope, self, func, instance, shifted(scope, position, nil, size),
        sized(scope, size), color)
end

atlas_converters.script_draw_bitmap_uv = function(scope, func, self, material, position, size,
        uvs, color, retained_id)
    if retained_id then
        if scope.mirror then return nil end
        return func(self, material, position, size, uvs, color, retained_id)
    end
    local instance, ok = atlas_material(scope, material)
    if not ok then state.atlas_skipped = state.atlas_skipped + 1; return nil end
    return atlas_call(scope, self, func, instance, shifted(scope, position, nil, size),
        sized(scope, size), uvs, color)
end

atlas_converters.script_draw_text = function(scope, func, self, text, font_size, font_type,
        position, size, color, options, retained_id)
    if retained_id then
        if scope.mirror then return nil end
        return func(self, text, font_size, font_type, position, size, color, options, retained_id)
    end
    dump("atlas_text", text, position[1] - scope.origin_x, position[2] - scope.origin_y,
        size and size[1] or 0, size and size[2] or 0, position[3])
    return atlas_call(scope, self, func, text, font_size * (scope.factor or 1), font_type,
        shifted(scope, position, nil, size), sized(scope, size), color, options)
end

atlas_converters.draw_rect = function(scope, func, self, position, size, color, retained_id)
    if retained_id then
        if scope.mirror then return nil end
        return func(self, position, size, color, retained_id)
    end
    return atlas_call(scope, self, func, shifted(scope, position, self.scale or 1, size),
        size, color)
end

atlas_converters.draw_slug_icon = function(scope, func, self, resource, index, position, size,
        color, optional_material, material_flags, retained_id)
    if retained_id then
        if scope.mirror then return nil end
        return func(self, resource, index, position, size, color, optional_material,
            material_flags, retained_id)
    end
    local instance, ok = atlas_material(scope, optional_material)
    if not ok then state.atlas_skipped = state.atlas_skipped + 1; return nil end
    -- The size goes to `shifted` like every other converter's: an icon is
    -- precisely the square, tall draw the boxing was added to catch, and this
    -- one was still being measured by its anchor alone (review,
    -- 18 September).
    return atlas_call(scope, self, func, resource, index,
        shifted(scope, position, self.scale or 1, size),
        size, color, instance, material_flags)
end

-- Mirror: while `fn` runs, every routed draw on `renderer` runs as stock and
-- then once more on `target` (an atlas-like {renderer(), material()}), scaled
-- by `factor` about the target origin and moved by dx, dy target pixels, e.g.
-- the constant elements onto the HUD panel's target at the panel's scale.
function MarkerWorld.mirror(target, renderer, factor, dx, dy, fn, ...)
    local previous = state.mirror
    state.mirror = {renderer = renderer, atlas = target, mirror = true, factor = factor or 1,
        atlas_x = dx or 0, atlas_y = dy or 0, origin_x = 0, origin_y = 0}
    local results = pack(pcall(fn, ...))
    state.mirror = previous
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2, results.n)
end

function MarkerWorld.route(name, func, renderer, ...)
    local scope = state.scope
    local mirror = state.mirror
    if mirror and mirror.renderer == renderer and not (scope and scope.renderer == renderer) then
        local results = pack(func(renderer, ...))
        local converter = atlas_converters[name]
        if converter and state.api then
            local ok, err = pcall(converter, mirror, func, renderer, ...)
            if not ok then
                state.mirror_errors = (state.mirror_errors or 0) + 1
                if state.mirror_errors == 1 and state.api.log then
                    state.api.log("DARKTIDEVR_HUD mirror_draw_failed call=" .. tostring(name) ..
                        " error=" .. tostring(err))
                end
            else
                state.mirror_draws = (state.mirror_draws or 0) + 1
            end
        end
        return unpack(results, 1, results.n)
    end
    if not scope or not state.api or scope.renderer ~= renderer then
        return func(renderer, ...)
    end
    local converter
    if scope.surface == "atlas" then
        converter = atlas_converters[name]
    else
        converter = converters[name]
    end
    if not converter then return func(renderer, ...) end
    return converter(scope, func, renderer, ...)
end

return MarkerWorld
