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
    surface = "world", text_mode = "slug", text_origin = "top", layer_base = 1000,
    material_names = setmetatable({}, {__mode = "k"}), world_materials = {}}
MarkerWorld.state = state

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

local surfaces = {screen = true, world = true}
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
    -- Plane-local coordinates must not be rounded to whole pixels.
    if settings then settings.snap_pixel_positions = false end
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
        return with_gui(scope, nil, function()
            return api.Gui2.bitmap_3d(gui, instance, nil, tm,
                (position[3] or 0) + start_layer(self) + state.layer_base, args)
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
    if scope.surface == "world" then layer = layer + state.layer_base end
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
    if scope.surface == "world" then layer = layer + state.layer_base end
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
function MarkerWorld.route(name, func, renderer, ...)
    local scope = state.scope
    local converter = scope and state.api and scope.renderer == renderer and converters[name]
    if not converter then return func(renderer, ...) end
    return converter(scope, func, renderer, ...)
end

return MarkerWorld
