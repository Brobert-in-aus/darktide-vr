-- World-surface markers. Every primitive a stock world-marker widget draws is
-- re-issued as a 3D GUI draw on a plane through the marker's world anchor,
-- facing the shared head centre, at the size the primary projection gives its
-- pixels at that distance. One mod-owned world GUI in the level world carries
-- them, so the engine renders one surface that both eyes see natively: no
-- second-eye replay, and text, icons, rectangles and direct draws all converge.
--
-- This module owns no engine hooks. The marker metrics module owns the single
-- hook on each 2D renderer entry point and calls `route` from it; the marker
-- GUI module owns the renderer destroy hook and calls `destroy`. While a
-- marker is being drawn, `route` converts the call into the renderer's own 3D
-- counterpart (bitmap_3d, slug_text_3d, slug_icon_3d, rect_3d) with the
-- plane's transform. Nothing crosses renderers: the same renderer, its own
-- render settings and materials, only a different GUI and a transform.
local MarkerWorld = {}

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

-- Plane basis and per-pixel size for one anchor. Pure: takes plain {x,y,z}
-- tables, returns unit axes and the metre size of one primary-projection pixel
-- at the anchor's distance. `flip` reverses the facing convention (the HUD
-- panel's textured quad needed right and forward reversed to face the viewer;
-- direct glyphs may not).
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

-- Screen pixel to plane-local metres: (px - origin) * pixel_size.
function MarkerWorld.local_point(scope, x, y)
    return (x - scope.origin_x) * scope.pixel_size,
        (y - scope.origin_y) * scope.pixel_size
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

local state = {scope = nil, guis = {}, errors = 0, api = nil}
MarkerWorld.state = state

-- `api` supplies UIRenderer, Vector2, Vector3, Color, Gui, World, Matrix4x4
-- and material_flags(renderer, flags) so the module stays testable.
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
        state.api.World.destroy_gui(entry.world, entry.gui)
    end
end

function MarkerWorld.destroy_all()
    for renderer in pairs(state.guis) do MarkerWorld.destroy(renderer) end
end

-- Draw `draw(...)` with every routed primitive on the plane described by
-- `scope` = {renderer, gui, tm, origin_x, origin_y, pixel_size}. The renderer's
-- pixel snapping is off for the duration: plane-local metres must not be
-- rounded to whole pixels.
function MarkerWorld.draw(scope, draw, ...)
    local previous = state.scope
    local settings = scope.renderer.render_settings
    local snap = settings and settings.snap_pixel_positions
    if settings then settings.snap_pixel_positions = false end
    state.scope = scope
    local results = {pcall(draw, ...)}
    state.scope = previous
    if settings then settings.snap_pixel_positions = snap end
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

local function with_gui(scope, fn, ...)
    local renderer = scope.renderer
    local original = renderer.gui
    renderer.gui = scope.gui
    local results = {pcall(fn, ...)}
    renderer.gui = original
    if not results[1] then
        state.errors = state.errors + 1
        error(results[2], 0)
    end
    return unpack(results, 2)
end

local converters = {}

converters.script_draw_bitmap = function(scope, func, self, material, position, size,
        color, retained_id)
    if retained_id then return func(self, material, position, size, color, retained_id) end
    local api = state.api
    local x, y = MarkerWorld.local_point(scope, position[1], position[2])
    local ps = scope.pixel_size
    return with_gui(scope, api.UIRenderer.script_draw_bitmap_3d, self, material,
        scope.tm, api.Vector3(x, y, 0), position[3] or 0,
        api.Vector3(size[1] * ps, size[2] * ps, 0), color, nil, nil)
end

converters.script_draw_bitmap_uv = function(scope, func, self, material, position, size,
        uvs, color, retained_id)
    if retained_id then
        return func(self, material, position, size, uvs, color, retained_id)
    end
    local api = state.api
    local x, y = MarkerWorld.local_point(scope, position[1], position[2])
    local ps = scope.pixel_size
    return with_gui(scope, api.UIRenderer.script_draw_bitmap_3d, self, material,
        scope.tm, api.Vector3(x, y, 0), position[3] or 0,
        api.Vector3(size[1] * ps, size[2] * ps, 0), color, uvs, nil)
end

converters.script_draw_text = function(scope, func, self, text, font_size, font_type,
        position, size, color, options, retained_id)
    if retained_id then
        return func(self, text, font_size, font_type, position, size, color, options,
            retained_id)
    end
    local api = state.api
    local x, y = MarkerWorld.local_point(scope, position[1], position[2])
    local ps = scope.pixel_size
    local box = size and api.Vector2(size[1] * ps, size[2] * ps) or nil
    return with_gui(scope, api.UIRenderer.script_draw_text_3d, self, text,
        font_size * ps, font_type, scope.tm, api.Vector3(x, y, 0),
        position[3] or 0, box, color, options, nil)
end

converters.draw_rect = function(scope, func, self, position, size, color, retained_id)
    if retained_id then return func(self, position, size, color, retained_id) end
    -- Stock scales logical units here and applies start layer, alpha and
    -- intensity before Gui2.rect; do the same for rect_3d.
    local api = state.api
    local scale = self.scale or 1
    local settings = self.render_settings
    local layer = (position[3] or 0) + (settings and settings.start_layer or 0)
    local alpha = settings and settings.alpha_multiplier or 1
    local intensity = settings and settings.color_intensity_multiplier or 1
    local x, y = MarkerWorld.local_point(scope, position[1] * scale, position[2] * scale)
    local ps = scope.pixel_size
    local tinted = color and api.Color(color[1] * alpha, color[2] * intensity,
        color[3] * intensity, color[4] * intensity) or api.Color(255, 255, 255, 255)
    return with_gui(scope, function()
        return api.Gui.rect_3d(scope.gui, scope.tm, api.Vector2(x, y), layer,
            api.Vector2(size[1] * scale * ps, size[2] * scale * ps), tinted)
    end)
end

converters.draw_slug_icon = function(scope, func, self, resource, index, position, size,
        color, optional_material, material_flags, retained_id)
    if retained_id then
        return func(self, resource, index, position, size, color, optional_material,
            material_flags, retained_id)
    end
    -- Same route as the stock rotated icon: the plane transform and the
    -- offset in plane-local units.
    local api = state.api
    local scale = self.scale or 1
    local settings = self.render_settings
    local layer = (settings and settings.start_layer or 0) + math.max(position[3] or 0, 1)
    local alpha = settings and settings.alpha_multiplier or 1
    local intensity = settings and settings.color_intensity_multiplier or 1
    local tinted = api.Color(color[1] * alpha, color[2] * intensity,
        color[3] * intensity, color[4] * intensity)
    local x, y = MarkerWorld.local_point(scope, position[1] * scale, position[2] * scale)
    local ps = scope.pixel_size
    local params = {}
    if optional_material then
        params[#params + 1] = "material"; params[#params + 1] = optional_material
    end
    local flags = api.material_flags and api.material_flags(self, material_flags)
    if flags then
        params[#params + 1] = "material_flags"; params[#params + 1] = flags
    end
    return with_gui(scope, function()
        return api.Gui.slug_icon_3d(scope.gui, resource, index, scope.tm,
            api.Vector3(x, y, 0), layer,
            api.Vector2(size[1] * scale * ps, size[2] * scale * ps), tinted,
            unpack(params))
    end)
end

-- Called by the owner of the renderer hooks with the hooked name, the stock
-- function and its arguments. Outside a marker draw, or for a renderer other
-- than the scope's, or for a name without a converter, the stock call runs.
function MarkerWorld.route(name, func, renderer, ...)
    local scope = state.scope
    local converter = scope and state.api and scope.renderer == renderer and converters[name]
    if not converter then return func(renderer, ...) end
    return converter(scope, func, renderer, ...)
end

return MarkerWorld
