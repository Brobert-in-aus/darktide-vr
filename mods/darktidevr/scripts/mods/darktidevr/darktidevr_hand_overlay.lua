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
-- panel's scale, and a cell is CELL pixels square.
local Overlay = {}

Overlay.CELL = 512
Overlay.COLUMNS, Overlay.ROWS = 4, 2

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

-- Pixel box for text centred (or aligned) at a cell pixel. Pure.
function Overlay.text_box(x, y, width, height, align)
    local left = x - width * 0.5
    if align == "left" then left = x elseif align == "right" then left = x - width end
    return left, y - height * 0.5
end

function Overlay.install(mod, presentation, Atlas, api)
    local atlas = Atlas.new({name = "darktidevr_hand_overlay", log_tag = "DARKTIDEVR_HAND_OVERLAY",
        cell_width = Overlay.CELL, cell_height = Overlay.CELL, columns = Overlay.COLUMNS, rows = Overlay.ROWS})
    atlas.configure(api)
    local UIRenderer = api.UIRenderer
    local UIFonts
    local anchors = {}
    local overlay = {atlas = atlas}

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
            local sx, sy = pixel(cx, cy)
            UIRenderer.draw_rect(renderer, api.Vector3(sx - pw * 0.5, sy - ph * 0.5, 10), api.Vector2(pw, ph), color)
        end
        -- Text centred vertically at (cx, cy); align "center", "left" or "right".
        function canvas.text(text, font_px, cx, cy, color, align)
            UIFonts = UIFonts or require("scripts/managers/ui/ui_fonts")
            local width, height = Overlay.CELL, font_px * 1.5
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
    function overlay.destroy() pcall(atlas.destroy) end
    function overlay.forget_world() pcall(atlas.forget_world) end
    return overlay
end

return Overlay
