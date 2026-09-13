-- Marker atlas: the HUD panel's route for world markers. Routed marker draws
-- run through the stock 2D renderer into one cell of an offscreen target
-- (every material, frame and text layout exactly as on screen); a world quad
-- through the marker's anchor then shows that cell with the HUD panel's
-- material, which is drawn in front of the scene. The target is set up as
-- the HUD panel's is: its own UI world, an overlay viewport writing the
-- capture target, and a completed copy that the world material samples.
local Atlas = {}

local CELL_WIDTH, CELL_HEIGHT, COLUMNS, ROWS = 1024, 512, 2, 4
local WIDTH, HEIGHT = CELL_WIDTH * COLUMNS, CELL_HEIGHT * ROWS
Atlas.CELL_WIDTH, Atlas.CELL_HEIGHT = CELL_WIDTH, CELL_HEIGHT
Atlas.WIDTH, Atlas.HEIGHT, Atlas.CELLS = WIDTH, HEIGHT, COLUMNS * ROWS

local panel_material_name = "content/ui/materials/icons/items/containers/item_container_square"
local target_material_name = "content/ui/materials/render_target_masks/ui_render_target_straight_blur"

local state = {generation = 0, pending = {}, shown = {}, frame = 0, stamp = -math.huge,
    materials = {}, skipped = 0}
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
    state.pending, state.shown, state.materials = {}, {}, {}
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
        state.api.log(string.format("DARKTIDEVR_MARKER_ATLAS create_failed step=%s error=%s",
            step, tostring(detail)))
    end
    Atlas.destroy()
    return false
end

local function create(world)
    local api = state.api
    state.generation = state.generation + 1
    local name = "darktidevr_markers_" .. tostring(state.generation)
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
        api.log(string.format("DARKTIDEVR_MARKER_ATLAS created width=%d height=%d cells=%d generation=%d",
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
    api.Gui.render_pass(state.queue.gui, 0, "to_screen", true)
    state.authored_t = t
    return true
end

-- A cell for one marker this frame: its centre in target pixels, where the
-- marker's anchor lands. nil when the atlas is unavailable or full.
function Atlas.claim(t, anchor)
    if not Atlas.begin_frame(t) then return nil, "atlas" end
    local index = #state.pending + 1
    if index > COLUMNS * ROWS then return nil, "atlas_full" end
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
function Atlas.material(handle, name, values)
    local resource = state.resource
    if not resource then return nil end
    local api = state.api
    local instance = state.materials[handle]
    if not instance then
        instance = api.Gui.create_material(resource.gui, name)
        state.materials[handle] = instance
    end
    if values then
        for key, record in pairs(values) do
            local setter = api.Material[record[1]]
            if setter then pcall(setter, instance, key, unpack(record, 3, record[2] + 2)) end
        end
    end
    return instance
end

-- Called once per camera update with the world being drawn. `frame_for(anchor)` returns the quad's
-- transform (right = viewer left, forward = toward the viewer, up = up, at
-- the anchor, as the HUD panel faces its quad) and metres per pixel.
function Atlas.draw(world, frame_for)
    state.frame = state.frame + 1
    -- Cells recorded in another world (the one before a map change) never
    -- draw: their GUI belongs to that world.
    if not state.ready or not state.world_gui or state.world ~= world or
            state.frame - state.stamp > 2 then return 0 end
    local api = state.api
    local drawn = 0
    for _, record in ipairs(state.shown) do
        local ok, tm, pixel_size = pcall(frame_for, record.anchor)
        if ok and tm and pixel_size then
            local w, h = CELL_WIDTH * pixel_size, CELL_HEIGHT * pixel_size
            local u0 = (record.x - CELL_WIDTH * 0.5) / WIDTH
            local u1 = (record.x + CELL_WIDTH * 0.5) / WIDTH
            local v0 = (record.y - CELL_HEIGHT * 0.5) / HEIGHT
            local v1 = (record.y + CELL_HEIGHT * 0.5) / HEIGHT
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
