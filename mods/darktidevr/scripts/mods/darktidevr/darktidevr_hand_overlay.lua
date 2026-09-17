-- Hand overlays: the ammo counter, wrist display and holster labels draw in
-- front of everything else, whatever the distance (user, 15 September
-- evening). World-GUI rect_3d and slug_text_3d are depth-tested by the scene
-- (13 September marker work), so each display instead draws ordinary 2D UI
-- (UIRenderer.draw_rect and script_draw_text) into a cell of its own
-- offscreen atlas (darktidevr_marker_atlas, Atlas.new), and at the camera
-- update that cell is shown on a flat panel at the display's anchor, facing
-- the eye, with the HUD panel's material, which draws in front of the scene.
-- The panel sits at the anchor in the world, so both eyes see it in place.
-- Cells show one frame late; the panel's position is this frame's.
--
-- A display asks for a canvas each frame it shows and draws in metres around
-- its anchor (x to the viewer's right, y up); metres_per_pixel sets the
-- panel's scale.
--
-- The atlas is the size the GUI is laid out at, RESOLUTION_LOOKUP's width
-- and height (2112 x 2304 in the headset): a 2048 x 1024 atlas drew
-- everything half size, and 1920 x 1080 times the UI scale squashed it to
-- about half height (worn, 15 September evening). Cells are that target
-- divided into COLUMNS by ROWS.
local Overlay = {}

Overlay.COLUMNS, Overlay.ROWS = 4, 4
-- An anchor whose display has not drawn for this long is let go, and the sweep
-- runs no more often than this. The keys used to be a fixed handful of hand
-- displays; teammate anchors are one per player ever seen, each holding a
-- Vector3Box, so without a sweep a long session accumulates them (review,
-- 18 September).
Overlay.ANCHOR_IDLE_SECONDS = 10
Overlay.ANCHOR_SWEEP_SECONDS = 5

-- The keys to drop from `anchors` at time `t`: those not seen for
-- ANCHOR_IDLE_SECONDS. Pure, so a test can pin it.
function Overlay.stale_anchors(anchors, t)
    local stale
    for key, record in pairs(anchors) do
        if t - (record.seen_t or t) > Overlay.ANCHOR_IDLE_SECONDS then
            stale = stale or {}
            stale[#stale + 1] = key
        end
    end
    return stale
end

-- The atlas extent from the resolution lookup (width, height, scale). Pure.
function Overlay.extent(lookup)
    lookup = type(lookup) == "table" and lookup or {}
    local width, height = tonumber(lookup.width), tonumber(lookup.height)
    if width and height and width >= 64 and height >= 64 then
        return math.floor(width + 0.5), math.floor(height + 0.5)
    end
    local scale = (type(lookup.scale) == "number" and lookup.scale > 0) and lookup.scale or 1
    return math.floor(1920 * scale + 0.5), math.floor(1080 * scale + 0.5)
end

local function sub(a, b) return {a[1] - b[1], a[2] - b[2], a[3] - b[3]} end
local function cross(a, b) return {a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]} end
local function normalize(a)
    local l = math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
    if not (l > 1e-6) then return nil end
    return {a[1] / l, a[2] / l, a[3] / l}
end

-- The panel axes at anchor for an eye: right to the viewer's LEFT, forward
-- toward the viewer, up upright (the atlas quad's convention). Arrays. Nil
-- when the eye is on the anchor or straight above or below it. Pure.
function Overlay.facing(anchor, eye)
    local away = normalize(sub(anchor, eye))
    if not away then return nil end
    local viewer_right = normalize(cross(away, {0, 0, 1}))
    if not viewer_right then return nil end
    local up = cross(viewer_right, away)
    return {-viewer_right[1], -viewer_right[2], -viewer_right[3]}, {-away[1], -away[2], -away[3]}, up
end

-- The cell width for a resolution lookup, as the atlas is built. Pure.
function Overlay.cell_width(lookup)
    local width = Overlay.extent(lookup)
    return math.floor(width / Overlay.COLUMNS)
end

-- A rectangle (left, top, width, height, in pixels relative to the cell's
-- centre, y down) clipped to the cell less a one-pixel margin; nil when
-- nothing of it is inside. Nothing a display draws may reach a neighbour's
-- cell: worn 16 and 17 September, the wrist bars' left ends showed as a
-- sliver beside the ammo count once the eye target (and so the cell)
-- shrank with Virtual Desktop's FOV tangent. Pure.
-- The margin is the atlas's gutter (its outer 8 texels are not shown) and
-- one more.
Overlay.CELL_MARGIN = 9
function Overlay.clip_rect(left, top, width, height, cell_width, cell_height)
    local half_w = cell_width * 0.5 - Overlay.CELL_MARGIN
    local half_h = cell_height * 0.5 - Overlay.CELL_MARGIN
    local l, r = math.max(left, -half_w), math.min(left + width, half_w)
    local t, b = math.max(top, -half_h), math.min(top + height, half_h)
    if not (r > l) or not (b > t) then return nil end
    return l, t, r - l, b - t
end

-- The width a line of text may take, in pixels, at x pixels right of the
-- cell's centre: to both edges for centred text, to the far edge for
-- aligned text, less the margin. Pure.
function Overlay.text_room(x, cell_width, align)
    local half = cell_width * 0.5 - Overlay.CELL_MARGIN
    if align == "left" then return math.max(0, half - x) end
    if align == "right" then return math.max(0, half + x) end
    return math.max(0, 2 * (half - math.abs(x)))
end

-- The font size that makes a line of measured width fit the room: unchanged
-- when it fits, scaled down in proportion when it does not (the whole name
-- stays readable; text cannot be clipped to a cell the way rectangles are),
-- never below MIN_FONT_SCALE of what was asked, where the text is dropped
-- rather than spilled. Returns nil for "do not draw". Worn 17 September: an
-- item's name on the forearm holsters, 54 px tall and wider than the cell,
-- spilled into the cells either side ("item pickups still have a sliver").
-- Pure.
Overlay.MIN_FONT_SCALE = 0.35
function Overlay.fitted_font(font_px, width, room)
    if not (room > 0) then return nil end
    if not (width > room) then return font_px end
    local scale = room / width
    if scale < Overlay.MIN_FONT_SCALE then return nil end
    return math.floor(font_px * scale)
end
-- A width estimate when the renderer cannot measure: bold proportional
-- digits and capitals run about 0.6 em. Pure.
function Overlay.estimated_width(text, font_px)
    return #tostring(text or "") * font_px * 0.6
end

-- Pixel box for text centred (or aligned) at a cell pixel. Pure.
function Overlay.text_box(x, y, width, height, align)
    local left = x - width * 0.5
    if align == "left" then left = x elseif align == "right" then left = x - width end
    return left, y - height * 0.5
end

function Overlay.install(mod, presentation, Atlas, api)
    local UIRenderer = api.UIRenderer
    local UIFonts
    local anchors = {}
    local overlay = {}
    local atlas, atlas_extent
    local function clock() return Managers.time and Managers.time:time("main") or nil end
    -- The atlas for the current UI scale, rebuilt when it changes.
    local function current_atlas()
        local width, height = Overlay.extent(RESOLUTION_LOOKUP)
        local key = width .. "x" .. height
        if atlas and atlas_extent ~= key then pcall(atlas.destroy); atlas = nil end
        if not atlas then
            atlas = Atlas.new({name = "darktidevr_hand_overlay", log_tag = "DARKTIDEVR_HAND_OVERLAY",
                cell_width = math.floor(width / Overlay.COLUMNS), cell_height = math.floor(height / Overlay.ROWS),
                columns = Overlay.COLUMNS, rows = Overlay.ROWS, clock = clock})
            atlas.configure(api)
            atlas_extent = key
            overlay.atlas = atlas
        end
        return atlas
    end

    -- A canvas for this frame at position (Vector3), or nil when the atlas is
    -- unavailable or full. key names the display. Every display in one frame
    -- shares the main clock's time, which is what starts the atlas frame.
    function overlay.canvas(world, key, position, metres_per_pixel)
        local t = Managers.time and Managers.time:time("main")
        if not t then return nil end
        local anchor = anchors[key]
        if not anchor then
            anchor = {key = key, position = Vector3Box(position)}
            anchors[key] = anchor
        else
            anchor.position:store(position)
        end
        anchor.metres = metres_per_pixel
        anchor.seen_t = t
        if not overlay.swept_t or t - overlay.swept_t > Overlay.ANCHOR_SWEEP_SECONDS then
            overlay.swept_t = t
            for _, stale in ipairs(Overlay.stale_anchors(anchors, t) or {}) do
                anchors[stale] = nil
            end
        end
        local atlas = current_atlas()
        if not atlas.ensure(world) then return nil end
        local x, y = atlas.claim(t, anchor)
        if not x then return nil end
        local renderer = atlas.renderer()
        renderer.scale, renderer.inverse_scale, renderer.render_settings = 1, 1, nil
        local mpp = metres_per_pixel
        local canvas = {}
        local function pixel(mx, my) return x + mx / mpp, y - my / mpp end
        -- A rectangle centred at (cx, cy), w by h metres; color {a, r, g, b}.
        function canvas.rect(cx, cy, w, h, color)
            local pw, ph = w / mpp, h / mpp
            local left, top, cw, ch = Overlay.clip_rect(cx / mpp - pw * 0.5, -cy / mpp - ph * 0.5, pw, ph,
                atlas.CELL_WIDTH, atlas.CELL_HEIGHT)
            if not left then return end
            UIRenderer.draw_rect(renderer, api.Vector3(x + left, y + top, 10), api.Vector2(cw, ch), color)
        end
        -- Text centred vertically at (cx, cy); align "center", "left" or "right".
        function canvas.text(text, font_px, cx, cy, color, align)
            UIFonts = UIFonts or require("scripts/managers/ui/ui_fonts")
            -- Fitted to the cell: measured by the renderer when it can.
            local measured
            if UIRenderer.text_size then
                local ok, w = pcall(UIRenderer.text_size, renderer, text, "proxima_nova_bold", font_px)
                if ok and type(w) == "number" and w > 0 then measured = w end
            end
            font_px = Overlay.fitted_font(font_px, measured or Overlay.estimated_width(text, font_px),
                Overlay.text_room(cx / mpp, atlas.CELL_WIDTH, align))
            if not font_px then return end
            local width, height = atlas.CELL_WIDTH, font_px * 1.5
            local sx, sy = pixel(cx, cy)
            local left, top = Overlay.text_box(sx, sy, width, height, align)
            local options = UIFonts.get_font_options_by_style({text_horizontal_alignment = align or "center",
                text_vertical_alignment = "center"})
            UIRenderer.script_draw_text(renderer, text, font_px, "proxima_nova_bold", api.Vector3(left, top, 11),
                api.Vector2(width, height), color, options)
        end
        return canvas
    end

    -- At the camera update: every cell on its panel.
    function overlay.draw(world)
        if not atlas then return 0 end
        return atlas.draw(world, function(anchor)
            local eye
            if presentation.eye_pose then eye = presentation.eye_pose(nil) end
            if not eye or not anchor.position or not anchor.metres then return nil end
            local p = anchor.position:unbox()
            local right, forward, up = Overlay.facing({Vector3.x(p), Vector3.y(p), Vector3.z(p)},
                {Vector3.x(eye), Vector3.y(eye), Vector3.z(eye)})
            if not right then return nil end
            local tm = Matrix4x4.identity()
            Matrix4x4.set_right(tm, Vector3(right[1], right[2], right[3]))
            Matrix4x4.set_forward(tm, Vector3(forward[1], forward[2], forward[3]))
            Matrix4x4.set_up(tm, Vector3(up[1], up[2], up[3]))
            Matrix4x4.set_translation(tm, p)
            return tm, anchor.metres
        end)
    end
    -- The cell width displays lay themselves out within.
    function overlay.cell_width() return Overlay.cell_width(RESOLUTION_LOOKUP) end
    function overlay.destroy() if atlas then pcall(atlas.destroy) end end
    function overlay.forget_world() if atlas then pcall(atlas.forget_world) end end
    return overlay
end

return Overlay
