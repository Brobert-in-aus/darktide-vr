-- Marker atlas: the HUD panel's route for world markers. Routed marker draws
-- run through the stock 2D renderer into one cell of an offscreen target
-- (every material, frame and text layout exactly as on screen); a world quad
-- through the marker's anchor then shows that cell with the HUD panel's
-- material, which is drawn in front of the scene. The target is set up as
-- the HUD panel's is: its own UI world, an overlay viewport writing the
-- capture target, and a completed copy that the world material samples.
-- Atlas.new(options) makes another independent atlas (the hand overlays):
-- options name (resource prefix), log_tag, cell_width, cell_height, columns
-- and rows, and clock (a function returning the main time): with a clock,
-- cells go stale after STALE_SECONDS and resources idle out after
-- IDLE_RELEASE_SECONDS instead of counting draw calls, which run more than
-- once per game frame (worn, 15 September evening: the hand overlays
-- flickered). The module itself is the marker atlas.
local panel_material_name = "content/ui/materials/icons/items/containers/item_container_square"
local target_material_name = "content/ui/materials/render_target_masks/ui_render_target_straight_blur"

local function new(options)
    options = options or {}
    local Atlas = {}

    -- Measured 18 September in the hub, with the drawing's own size included
    -- rather than only where it is anchored (`extents ... boxed=1`): the box a
    -- marker needs is 425 x 15 about the cell's centre, against a half-cell of
    -- 512 x 256. So the width is nearly right -- 18 per cent of headroom -- and
    -- the height was eleven times what anything used.
    --
    -- Halving it buys two things. The atlas holds sixteen markers instead of
    -- eight, and `atlas_full cells=8` had already fired in the Psykhanium,
    -- which is a nearly empty room: past the ceiling a marker is simply not
    -- drawn. And the quad shrinks with the cell, so every marker stops paying
    -- for half a cell of transparent overdraw on every frame.
    --
    -- A further halving (32 cells) is available and not taken: one quiet
    -- scene is thin evidence, and the extents line reports against the
    -- half-cell every run, so the margin can be watched before it is spent.
    local CELL_WIDTH, CELL_HEIGHT = options.cell_width or 1024, options.cell_height or 256
    local COLUMNS, ROWS = options.columns or 2, options.rows or 8
    local NAME, TAG = options.name or "darktidevr_markers", options.log_tag or "DARKTIDEVR_MARKER_ATLAS"
    local WIDTH, HEIGHT = CELL_WIDTH * COLUMNS, CELL_HEIGHT * ROWS
    Atlas.CELL_WIDTH, Atlas.CELL_HEIGHT = CELL_WIDTH, CELL_HEIGHT
    -- The gutter: each cell is shown without its outer GUTTER texels, and the
    -- quad is that much smaller so nothing is rescaled. A marker far away is
    -- drawn many times smaller than its cell, and a minified sample reaches
    -- past half a texel into the neighbouring cell (worn, 17 September: a
    -- sliver beside distant pickups' markers after the half-texel inset had
    -- cured the hand displays). Eight texels covers an eightfold reduction.
    Atlas.GUTTER = 8
    -- The visible cell's UV rectangle and size in pixels for a cell centred
    -- at (x, y): u0, v0, u1, v1, width, height. Pure.
    function Atlas.visible_cell(x, y)
        local g = Atlas.GUTTER
        return (x - CELL_WIDTH * 0.5 + g) / WIDTH, (y - CELL_HEIGHT * 0.5 + g) / HEIGHT,
            (x + CELL_WIDTH * 0.5 - g) / WIDTH, (y + CELL_HEIGHT * 0.5 - g) / HEIGHT,
            CELL_WIDTH - 2 * g, CELL_HEIGHT - 2 * g
    end
    Atlas.WIDTH, Atlas.HEIGHT, Atlas.CELLS = WIDTH, HEIGHT, COLUMNS * ROWS

    local state = {generation = 0, pending = {}, shown = {}, frame = 0, stamp = -math.huge,
        materials = {}, skipped = 0, wanted = 0, peak_wanted = 0, peak_logged = 0,
        -- Per instance, the caller's stamp for the values last replayed
        -- onto it; dies with the instances.
        applied = {}}
    Atlas.state = state

    -- `api` supplies Managers, UIRenderer, Renderer, World, ScriptWorld, Gui,
    -- Gui2, Material, Matrix4x4, Vector2, Vector3, Color and log(line).
    function Atlas.configure(api)
        state.api = api
    end

    local function release(fn, ...)
        if fn then pcall(fn, ...) end
    end

    function Atlas.destroy()
        local api = state.api
        if not api then return end
        if state.world and state.world_gui then
            release(api.World.destroy_gui, state.world, state.world_gui)
        end
        local resource = state.resource
        if resource then
            for _, instance in pairs(state.materials) do
                release(api.Gui.destroy_material, resource.gui, instance)
            end
            -- Restore ownership metadata before stock destruction.
            if state.capture then resource.render_target = state.capture end
            if resource.render_target_material and resource.gui then
                release(api.Gui.destroy_material, resource.gui, resource.render_target_material)
            end
            release(api.UIRenderer.destroy, resource, state.render_world)
        end
        if state.queue then release(api.UIRenderer.destroy, state.queue, state.render_world) end
        if state.render_world and state.viewport_name then
            release(api.ScriptWorld.destroy_viewport, state.render_world, state.viewport_name)
        end
        if state.render_world then
            release(api.Managers.ui.destroy_world, api.Managers.ui, state.render_world)
        end
        if state.display then release(api.Renderer.destroy_resource, state.display) end
        state.resource, state.queue, state.render_world, state.viewport_name = nil, nil, nil, nil
        state.capture, state.display, state.world, state.world_gui = nil, nil, nil, nil
        state.world_material, state.authored_t, state.ready = nil, nil, false
        state.pending, state.shown, state.materials, state.applied = {}, {}, {}, {}
    end

    -- The game world is being torn down (map change): its world GUI and the
    -- material on it die with it, so drop those handles without calling into
    -- that world, then release the offscreen resources, which belong to our own
    -- UI world. The next claim builds everything for the new world.
    function Atlas.forget_world()
        state.world, state.world_gui, state.world_material = nil, nil, nil
        Atlas.destroy()
    end

    local function fail(step, detail)
        state.failed = true
        if state.api.log then
            state.api.log(string.format(TAG .. " create_failed step=%s error=%s",
                step, tostring(detail)))
        end
        Atlas.destroy()
        return false
    end

    local function create(world)
        local api = state.api
        state.generation = state.generation + 1
        local name = NAME .. "_" .. tostring(state.generation)
        local ok, value = pcall(api.Managers.ui.create_world, api.Managers.ui,
            name .. "_world", 199, "ui")
        if not ok or not value then return fail("render_world", value) end
        state.render_world = value
        ok, value = pcall(api.UIRenderer.create_viewport_renderer, state.render_world,
            name .. "_queue", "custom_size", WIDTH, HEIGHT)
        if not ok or not value then return fail("queue", value) end
        state.queue = value
        ok, value = pcall(api.UIRenderer.create_resource_renderer, state.render_world,
            state.queue.gui, state.queue.gui_retained, name .. "_target", target_material_name,
            WIDTH, HEIGHT, true)
        if not ok or not value then return fail("target", value) end
        state.resource = value
        state.capture = value.render_target
        state.viewport_name = name .. "_viewport"
        ok, value = pcall(api.Managers.ui.create_viewport, api.Managers.ui, state.render_world,
            state.viewport_name, "overlay", 1, nil, nil, {back_buffer = state.capture})
        if not ok or not value then return fail("viewport", value) end
        -- The viewport owns the output binding; the renderer authors plain UI.
        state.resource.render_target = nil
        state.resource.base_render_pass = nil
        state.resource.render_pass_flag = nil
        ok, value = pcall(api.Renderer.create_resource, "render_target", "R8G8B8A8", nil,
            WIDTH, HEIGHT, name .. "_display")
        if not ok or not value then return fail("display", value) end
        state.display = value
        ok, value = pcall(api.World.create_world_gui, world, api.Matrix4x4.identity(), 1, 1,
            "immediate")
        if not ok or not value then return fail("world_gui", value) end
        state.world, state.world_gui = world, value
        ok, value = pcall(api.Gui.create_material, state.world_gui, panel_material_name)
        if not ok or not value then return fail("world_material", value) end
        state.world_material = value
        ok, value = pcall(function()
            api.Material.set_scalar(state.world_material, "use_placeholder_texture", 0)
            api.Material.set_scalar(state.world_material, "use_render_target", 1)
            api.Material.set_scalar(state.world_material, "rows", 1)
            api.Material.set_scalar(state.world_material, "columns", 1)
            api.Material.set_scalar(state.world_material, "grid_index", 0)
            api.Material.set_resource(state.world_material, "render_target", state.display)
        end)
        if not ok then return fail("binding", value) end
        if api.log then
            api.log(string.format(TAG .. " created width=%d height=%d cells=%d generation=%d",
                WIDTH, HEIGHT, COLUMNS * ROWS, state.generation))
        end
        return true
    end

    -- The world the quads are drawn in (the HUD renderer's world).
    function Atlas.ensure(world)
        if not state.api or state.failed or not world then return false end
        if state.resource and state.world ~= world then Atlas.destroy() end
        if not state.resource then return create(world) end
        return true
    end

    -- Once per UI frame: copy the previous frame's completed target to the
    -- display copy (its cells become the shown records) and clear the target
    -- for this frame's cells.
    function Atlas.begin_frame(t)
        if not state.resource then return false end
        if state.authored_t == t then return true end
        local api = state.api
        if state.authored_t ~= nil then
            local ok, detail = pcall(api.Renderer.copy_render_target_rect, state.capture,
                0, 0, 1, 1, state.display, 0, 0, 1, 1)
            if not ok then return fail("copy", detail) end
            state.shown = state.pending
            state.ready = true
        end
        state.pending = {}
        state.stamp = state.frame
        state.stamp_t = options.clock and options.clock() or nil
        api.Gui.render_pass(state.queue.gui, 0, "to_screen", true)
        state.authored_t = t
        return true
    end

    -- A cell for one marker this frame: its centre in target pixels, where the
    -- marker's anchor lands. nil when the atlas is unavailable or full.
    -- What a claimant can be called in a log line. The hand displays name
    -- their anchors and markers do not, so fall back to whatever the anchor
    -- can be identified by; `anchor=?` told nobody which display went missing
    -- in the one run where this fired (hook-arity-smoke-20260918). Pure.
    function Atlas.claimant_name(anchor)
        if type(anchor) ~= "table" then return "?" end
        for _, field in ipairs({"key", "id", "name", "slot", "kind"}) do
            local value = anchor[field]
            if type(value) == "string" or type(value) == "number" then
                return tostring(value)
            end
        end
        -- A marker's anchor is a position: say where, which at least
        -- distinguishes one claimant from another in the same frame.
        local position = anchor.position
        if type(position) == "table" and type(position.unbox) == "function" then
            local ok, point = pcall(position.unbox, position)
            if ok and point then return "at " .. tostring(point) end
        end
        if anchor.x and anchor.y then
            return string.format("at %.1f,%.1f", anchor.x, anchor.y)
        end
        return "unnamed"
    end

    function Atlas.claim(t, anchor)
        if not Atlas.begin_frame(t) then return nil, "atlas" end
        local index = #state.pending + 1
        -- How many were WANTED, not merely how many fit. `#pending` stops at
        -- the ceiling, so counting that says ceiling+1 for ever and tells
        -- nobody how big the grid should be; count the attempts in a frame,
        -- which all share one `t` (18 September).
        if state.wanted_t ~= t then state.wanted_t, state.wanted = t, 0 end
        state.wanted = state.wanted + 1
        if state.wanted > state.peak_wanted then
            state.peak_wanted = state.wanted
            -- Reported as the peak grows, not only once it overflows: a run
            -- that never fills the atlas still has to say how close it came,
            -- and the first measurement run reported nothing at all because
            -- nothing overflowed (18 September). Throttled by growth, so a
            -- busy scene does not fill the log a line at a time.
            if state.api and state.api.log and state.wanted >= 2 and
                    state.wanted >= state.peak_logged + math.max(2, COLUMNS * ROWS * 0.25) then
                state.peak_logged = state.wanted
                state.api.log(string.format(
                    "%s demand cells=%d wanted=%d claimant=%s", TAG,
                    COLUMNS * ROWS, state.wanted, Atlas.claimant_name(anchor)))
            end
        end
        if index > COLUMNS * ROWS then
            -- Every caller answers this by hiding, so a full atlas reads as a
            -- display quietly going missing with nothing in the log to say
            -- why. Said once per session; the count is what a report needs.
            if not state.full_logged and state.api and state.api.log then
                state.full_logged = true
                state.api.log(string.format(
                    "%s atlas_full cells=%d columns=%d rows=%d claimant=%s",
                    TAG, COLUMNS * ROWS, COLUMNS, ROWS,
                    Atlas.claimant_name(anchor)))
            end
            return nil, "atlas_full"
        end
        local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
        local x, y = column * CELL_WIDTH + CELL_WIDTH * 0.5, row * CELL_HEIGHT + CELL_HEIGHT * 0.5
        state.pending[index] = {anchor = anchor, x = x, y = y}
        return x, y
    end

    function Atlas.renderer()
        return state.resource
    end

    -- Per-pass material handles belong to the source renderer's GUI; the target
    -- GUI gets its own instance per handle, with the handle's recorded values
    -- (material values, ui_scale) replayed every draw. `values` maps a key to
    -- {setter, n, ...}.
    -- `stamp`, when given, names the revision of `values`: once replayed
    -- onto the instance the same stamp skips the replay, which otherwise ran
    -- for every primitive of every frame (profile doc). Without a stamp the
    -- values are replayed as before.
    function Atlas.material(handle, name, values, stamp)
        local resource = state.resource
        if not resource then return nil end
        local api = state.api
        local instance = state.materials[handle]
        if not instance then
            instance = api.Gui.create_material(resource.gui, name)
            state.materials[handle] = instance
            -- No instance: the primitive is skipped by the caller, as before;
            -- the stamp must not be recorded against nil (review, 16 September).
            if not instance then return nil end
        end
        if values and (stamp == nil or state.applied[instance] ~= stamp) then
            local profile = api.profile
            local mark = profile and profile.begin()
            for key, record in pairs(values) do
                local setter = api.Material[record[1]]
                if setter then pcall(setter, instance, key, unpack(record, 3, record[2] + 2)) end
            end
            if mark then profile.finish("marker.material_values", mark) end
            if stamp ~= nil then state.applied[instance] = stamp end
        end
        return instance
    end

    -- Called once per camera update with the world being drawn. `frame_for(anchor)` returns the quad's
    -- transform (right = viewer left, forward = toward the viewer, up = up, at
    -- the anchor, as the HUD panel faces its quad) and metres per pixel.
    -- Camera updates without a marker frame before the atlas lets go of its
    -- resources. Its GUI keeps what it drew (the tag wheel's materials, marker
    -- icons), some from a mission's own packages; the atlas's UI world outlives
    -- the mission, and two mission-end unloads crashed on a resource it still
    -- held. Markers stop drawing before every unload (cutscene, end screen).
    Atlas.IDLE_RELEASE_FRAMES = 30
    Atlas.STALE_SECONDS = 0.1
    Atlas.IDLE_RELEASE_SECONDS = 1
    -- Whether the claimed cells are too old to show, and whether to let go of
    -- the resources: by the clock when there is one, else by draw calls.
    local function staleness()
        local now = options.clock and options.clock()
        if now and state.stamp_t then
            local age = now - state.stamp_t
            -- A stamp from ahead of the clock makes every age negative, which
            -- reads as "drawn just now" for ever: the cells last claimed would
            -- keep showing and the resources would never be released, which is
            -- the crash on mission unload this release exists to avoid. Since
            -- nothing else explains a clock that went backwards, let go at
            -- once; the next marker rebuilds (review, 18 September).
            if age < 0 then return true, true end
            return age > Atlas.STALE_SECONDS, age > Atlas.IDLE_RELEASE_SECONDS
        end
        if options.clock then return true, false end
        local age = state.frame - state.stamp
        return age > 2, age > Atlas.IDLE_RELEASE_FRAMES
    end

    function Atlas.draw(world, frame_for)
        state.frame = state.frame + 1
        local stale, idle = staleness()
        if state.resource and state.world == world and idle then
            Atlas.destroy()
            if state.api and state.api.log then
                state.api.log(TAG .. " released reason=idle")
            end
            return 0
        end
        -- Cells recorded in another world (the one before a map change) never
        -- draw: their GUI belongs to that world.
        if not state.ready or not state.world_gui or state.world ~= world or
                stale then return 0 end
        local api = state.api
        local drawn = 0
        for _, record in ipairs(state.shown) do
            local ok, tm, pixel_size = pcall(frame_for, record.anchor)
            if ok and tm and pixel_size then
                -- The cell less its gutter (Atlas.visible_cell).
                local u0, v0, u1, v1, visible_w, visible_h = Atlas.visible_cell(record.x, record.y)
                local w, h = visible_w * pixel_size, visible_h * pixel_size
                -- Local x runs to the viewer's left, so U is reversed; local y
                -- runs up, so V (top = 0) is reversed.
                api.Gui2.bitmap_3d(state.world_gui, state.world_material, nil, tm, 1000,
                    {position_offset = api.Vector3(-w * 0.5, -h * 0.5, 0),
                     size = api.Vector3(w, h, 0), color = api.Color(255, 255, 255, 255),
                     uv00 = api.Vector2(u1, v1), uv11 = api.Vector2(u0, v0),
                     snap_pixel_positions = false})
                drawn = drawn + 1
            end
        end
        return drawn
    end

    return Atlas
end

local Markers = new()
Markers.new = new
return Markers
