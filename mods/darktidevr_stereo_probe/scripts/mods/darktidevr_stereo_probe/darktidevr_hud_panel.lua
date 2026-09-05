local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")
local ScriptWorld = require("scripts/foundation/utilities/script_world")

local HudPanel = {}

local function pack(...)
    return {n=select("#", ...), ...}
end

local state = {
    enabled = false,
    diagnostic = false,
    same_world_probe = false,
    borrowed_renderer = false,
    render_submissions = 0,
    mod = nil,
    owner = nil,
    source_renderer = nil,
    queue_renderer = nil,
    resource_renderer = nil,
    render_world = nil,
    render_viewport = nil,
    render_viewport_name = nil,
    display_target = nil,
    display_ready = false,
    target_width = nil,
    target_height = nil,
    world = nil,
    world_gui = nil,
    world_material = nil,
    pending_world = nil,
    creation_failed = false,
    last_authored_t = nil,
    generation = 0,
    logged = false,
    layout_logged = false,
    flag_last_poll_t = -math.huge,
}

-- Scene-depth, projected-world and eye-edge elements remain on the stock
-- per-eye renderer. Fixed status elements are authored once into a dedicated
-- 16:9 screen-GUI target and the completed target is presented in 3D.
local spatial_elements = {
    HudElementWorldMarkers = true,
    HudElementInteraction = true,
    HudElementNameplates = true,
    HudElementSmartTagging = true,
    HudElementMinionShieldHealth = true,
    HudElementDamageIndicator = true,
}

local function partition_elements(elements)
    local spatial = {}
    local fixed = {}
    for i = 1, #elements do
        local element = elements[i]
        local name = element and element.__class_name
        if spatial_elements[name] then
            spatial[#spatial + 1] = element
        else
            fixed[#fixed + 1] = element
        end
    end
    return spatial, fixed
end

local function log_partition(mod, spatial, fixed)
    if state.layout_logged then
        return
    end
    state.layout_logged = true
    local spatial_names = {}
    local fixed_names = {}
    for i = 1, #spatial do
        spatial_names[#spatial_names + 1] = tostring(spatial[i].__class_name)
    end
    for i = 1, #fixed do
        fixed_names[#fixed_names + 1] = tostring(fixed[i].__class_name)
    end
    mod:info("DARKTIDEVR_HUD partition spatial=%s fixed=%s",
        table.concat(spatial_names, ","), table.concat(fixed_names, ","))
end

local function transfer_fixed_records(
        owner, source_renderer, target_renderer, mod)
    if not owner or not source_renderer or
            type(owner._elements_array) ~= "table" then
        return
    end
    local _, fixed = partition_elements(owner._elements_array)
    local retained = owner._elements_hud_retained_mode_lookup or {}
    local visible = owner._currently_visible_elements or {}
    local moved = 0
    local failed = 0
    for i = 1, #fixed do
        local element = fixed[i]
        local name = element.__class_name
        if retained[name] then
            local ok = true
            if element.set_visible then
                ok = pcall(element.set_visible, element, false,
                    source_renderer, true)
                if ok and target_renderer and visible[name] then
                    ok = pcall(element.set_visible, element, true,
                        target_renderer, true)
                end
            else
                local widgets = element._widgets or {}
                for j = 1, #widgets do
                    ok = pcall(UIWidget.destroy, source_renderer, widgets[j])
                    widgets[j].dirty = true
                    if target_renderer then
                        pcall(UIWidget.set_visible, widgets[j],
                            target_renderer, visible[name] == true)
                    end
                end
            end
            if ok then
                moved = moved + 1
            else
                failed = failed + 1
            end
        end
    end
    if mod then
        mod:info(
            "DARKTIDEVR_HUD retained_transfer moved=%d failed=%d target=%s",
            moved, failed, tostring(target_renderer ~= nil))
    end
end

local function target_extent()
    local scale = RESOLUTION_LOOKUP and RESOLUTION_LOOKUP.scale or 1
    return math.max(1, math.floor(1920 * scale + 0.5)),
        math.max(1, math.floor(1080 * scale + 0.5))
end

local function destroy_resources()
    if state.resource_renderer and state.source_renderer then
        transfer_fixed_records(state.owner, state.resource_renderer,
            state.source_renderer, nil)
    end
    if state.world and state.world_gui then
        pcall(World.destroy_gui, state.world, state.world_gui)
    end
    if state.resource_renderer then
        if state.resource_renderer.render_target_material and
                state.resource_renderer.gui then
            pcall(Gui.destroy_material, state.resource_renderer.gui,
                state.resource_renderer.render_target_material)
        end
        pcall(UIRenderer.destroy, state.resource_renderer,
            state.render_world)
    end
    if state.queue_renderer and not state.borrowed_renderer then
        pcall(UIRenderer.destroy, state.queue_renderer, state.render_world)
    end
    if state.render_world and state.render_viewport_name then
        pcall(ScriptWorld.destroy_viewport, state.render_world,
            state.render_viewport_name)
    end
    if state.render_world and not state.borrowed_renderer then
        pcall(Managers.ui.destroy_world, Managers.ui, state.render_world)
    end
    if state.display_target then
        pcall(Renderer.destroy_resource, state.display_target)
    end
    state.owner = nil
    state.source_renderer = nil
    state.queue_renderer = nil
    state.borrowed_renderer = false
    state.resource_renderer = nil
    state.render_world = nil
    state.render_viewport = nil
    state.render_viewport_name = nil
    state.display_target = nil
    state.display_ready = false
    state.target_width = nil
    state.target_height = nil
    state.world = nil
    state.world_gui = nil
    state.world_material = nil
    state.pending_world = nil
    state.creation_failed = false
    state.last_authored_t = nil
    state.render_submissions = 0
    state.logged = false
    state.layout_logged = false
end

local function create_resources(mod, owner, source_renderer, world)
    local width, height = target_extent()
    state.generation = state.generation + 1
    local name = "darktidevr_hud_" .. tostring(state.generation)
    state.borrowed_renderer = state.same_world_probe
    local render_world_ok, render_world = true, world
    if not state.borrowed_renderer then
        render_world_ok, render_world = pcall(Managers.ui.create_world, Managers.ui,
            name .. "_world", 199, "ui")
    end
    if not render_world_ok or not render_world then
        state.creation_failed = true
        mod:error("DARKTIDEVR_HUD render_world_failed error=%s",
            tostring(render_world))
        return nil
    end
    state.render_world = render_world
    if not state.borrowed_renderer then
        state.render_viewport_name = name .. "_viewport"
        local viewport_ok, viewport = pcall(
            Managers.ui.create_viewport, Managers.ui, render_world,
            state.render_viewport_name, "overlay", 1)
        if not viewport_ok or not viewport then
            mod:error("DARKTIDEVR_HUD render_viewport_failed error=%s", tostring(viewport))
            destroy_resources()
            state.creation_failed = true
            return nil
        end
        state.render_viewport = viewport
    end
    local queue_ok, queue_renderer = true, source_renderer
    if not state.borrowed_renderer then
        queue_ok, queue_renderer = pcall(UIRenderer.create_viewport_renderer,
            render_world, name .. "_queue", "custom_size", width, height)
    end
    if not queue_ok or not queue_renderer then
        mod:error("DARKTIDEVR_HUD queue_create_failed error=%s",
            tostring(queue_renderer))
        destroy_resources()
        state.creation_failed = true
        return nil
    end
    state.queue_renderer = queue_renderer
    state.world = world
    local target_ok, resource_renderer = pcall(
        UIRenderer.create_resource_renderer,
        render_world, queue_renderer.gui, queue_renderer.gui_retained,
        name .. "_target",
        "content/ui/materials/render_target_masks/ui_render_target_straight_blur",
        width, height, true)
    if not target_ok or not resource_renderer then
        mod:error("DARKTIDEVR_HUD target_create_failed error=%s",
            tostring(resource_renderer))
        destroy_resources()
        state.creation_failed = true
        return nil
    end
    state.resource_renderer = resource_renderer
    local display_ok, display_target = pcall(
        Renderer.create_resource,
        "render_target", "R8G8B8A8", nil,
        width, height, name .. "_display")
    if not display_ok or not display_target then
        mod:error("DARKTIDEVR_HUD display_create_failed error=%s",
            tostring(display_target))
        destroy_resources()
        state.creation_failed = true
        return nil
    end
    state.display_target = display_target
    local gui_ok, world_gui = pcall(
        World.create_world_gui,
        world, Matrix4x4.identity(), 1, 1)
    if not gui_ok or not world_gui then
        mod:error("DARKTIDEVR_HUD world_gui_failed error=%s",
            tostring(world_gui))
        destroy_resources()
        state.creation_failed = true
        return nil
    end
    state.world_gui = world_gui
    local material_ok, material = pcall(
        Gui.create_material, world_gui,
        "content/ui/materials/render_target_masks/ui_render_target_straight_blur",
        GuiMaterialFlag.GUI_RENDER_PASS_LAYER)
    if not material_ok or not material then
        mod:error("DARKTIDEVR_HUD world_material_failed error=%s",
            tostring(material))
        destroy_resources()
        state.creation_failed = true
        return nil
    end
    state.world_material = material
    -- Never sample the target while the dedicated UI pass can still be
    -- writing it. Worn hardware proved that the direct binding aliases the
    -- binocular world render into this panel after HUD startup. Present only
    -- the separate completed-copy resource; a one-frame-old HUD is safe,
    -- whereas an in-flight render target is not.
    local binding_ok, binding_error = pcall(
        Material.set_resource, material, "source", display_target)
    if not binding_ok then
        mod:error("DARKTIDEVR_HUD material_binding_failed error=%s",
            tostring(binding_error))
        destroy_resources()
        state.creation_failed = true
        return nil
    end
    state.owner = owner
    state.source_renderer = source_renderer
    state.target_width, state.target_height = width, height
    state.pending_world = world
    transfer_fixed_records(owner, source_renderer, resource_renderer, mod)
    mod:info(
        "DARKTIDEVR_HUD target_created width=%d height=%d generation=%d pass=%s source=display_copy",
        width, height, state.generation,
        tostring(resource_renderer.base_render_pass))
    return resource_renderer
end

local function update_enabled_flag(mod, t)
    if not Mods or not Mods.lua or not Mods.lua.io or
            t < state.flag_last_poll_t + 0.25 then
        return
    end
    state.flag_last_poll_t = t
    local path =
        "./../mods/darktidevr_stereo_probe/darktidevr_hud_panel.flag"
    local flag = Mods.lua.io.open(path, "r")
    if not flag then
        return
    end
    local request = flag:read("*all")
    flag:close()
    local command = request and request:match("^%s*(%a+)")
    if command ~= "enable" and command ~= "disable" and command ~= "diagnostic" and command ~= "source" and command ~= "sameworld" then
        return
    end
    local consumed = Mods.lua.io.open(path, "w")
    if consumed then
        consumed:write("consumed\n")
        consumed:close()
    end
    local same_world = command == "sameworld"
    if same_world ~= state.same_world_probe then destroy_resources() end
    state.same_world_probe = same_world
    state.diagnostic = command == "diagnostic" or command == "source" or same_world
    HudPanel.set_enabled(command ~= "disable")
    if state.world_material and state.resource_renderer then
        local target = command == "source" and state.resource_renderer.render_target or state.display_target
        Material.set_resource(state.world_material,"source",target)
        mod:info("DARKTIDEVR_HUD diagnostic_binding=%s",command == "source" and "source_target" or "display_copy")
    end
    mod:info("DARKTIDEVR_HUD enabled=%s source=flag",
        tostring(state.enabled))
end

function HudPanel.set_enabled(enabled)
    state.enabled = enabled == true
    if not state.enabled then
        destroy_resources()
    end
end

function HudPanel.enabled()
    return state.enabled
end

function HudPanel.install(mod)
    state.mod = mod
    mod:hook("UIHud", "update", function(func, self, dt, t, input_service)
        update_enabled_flag(mod, t or 0)
        return func(self, dt, t, input_service)
    end)

    mod:hook("UIHud", "draw", function(func, self, dt, t, input_service)
        if not state.enabled or not self._ui_renderer or
                type(self._elements_array) ~= "table" then
            return func(self, dt, t, input_service)
        end
        if state.resource_renderer then
            local width, height = target_extent()
            if state.owner ~= self or state.source_renderer ~= self._ui_renderer or
                    state.target_width ~= width or state.target_height ~= height then
                -- A new HUD owner or resolution cannot reuse the previous
                -- owner's render target and retained records.
                destroy_resources()
                state.pending_world = self._ui_renderer.world
            end
        end
        local resource_renderer = state.resource_renderer
        if not resource_renderer and not state.creation_failed and
                state.pending_world and
                self._ui_renderer.world == state.pending_world then
            resource_renderer = create_resources(
                mod, self, self._ui_renderer, state.pending_world)
        end
        if not resource_renderer then
            return func(self, dt, t, input_service)
        end
        local spatial, fixed = partition_elements(self._elements_array)
        log_partition(mod, spatial, fixed)
        local source_elements = self._elements_array
        local source_renderer = self._ui_renderer
        local copy_failure

        -- Every temporary mutation must unwind even if stock drawing, queue
        -- construction or the dependency sample throws. Restore before rethrow.
        local ok, result = pcall(function()
            self._elements_array = spatial
            local spatial_result = pack(func(self, dt, t, input_service))

            if state.last_authored_t ~= t then
                -- The preceding frame's UI pass has been submitted. Copy it
                -- before queuing this frame's writes; the engine owns GPU
                -- synchronization for this same resource-copy API used by its
                -- atlas generator. Never expose an uninitialized first frame.
                if state.last_authored_t ~= nil then
                    local copied, detail = pcall(Renderer.copy_render_target_rect,
                        resource_renderer.render_target,
                        0, 0, 1, 1, state.display_target, 0, 0, 1, 1)
                    if not copied then
                        copy_failure = tostring(detail)
                        return spatial_result
                    end
                    state.display_ready = true
                end
                -- Gui.render_pass is a frame queue, not persistent renderer state.
                -- Darktide's own resource-backed UI elements clear and rebuild this
                -- queue immediately before authoring every target frame.
                UIRenderer.clear_render_pass_queue(state.queue_renderer)
                UIRenderer.add_render_pass(state.queue_renderer, 0,
                    resource_renderer.base_render_pass, true,
                    resource_renderer.render_target)
                -- Match Darktide's tactical-overlay resource renderer exactly:
                -- its offscreen pass is followed by a terminal screen pass which
                -- samples the target. Without that dependency the dedicated UI
                -- world can prune the entire target branch, leaving even an
                -- immediate opaque diagnostic rectangle black. Draw the terminal
                -- sample inside the viewport with zero alpha. An offscreen
                -- sample may be culled before its dependency is scheduled.
                UIRenderer.add_render_pass(state.queue_renderer, 1,
                    "to_screen", false)
                self._elements_array = fixed
                self._ui_renderer = resource_renderer
                func(self, dt, t, input_service)
                self._ui_renderer = source_renderer
                if state.diagnostic then
                    Gui2.rect(state.queue_renderer.gui,Vector3(50,50,1),Vector3(400,200,0),
                        {render_pass=resource_renderer.base_render_pass,color=Color(255,255,0,255)})
                end
                -- This is a render dependency, not a visible corner pixel.
                Gui.bitmap(
                    state.queue_renderer.gui,
                    resource_renderer.render_target_material,
                    "render_pass", "to_screen",
                    Vector3(0, 0, 1),
                    Vector2(1, 1),
                    Color(state.diagnostic and 255 or 0, 255, 255, 255))
                state.last_authored_t = t
            end
            return spatial_result
        end)
        self._ui_renderer = source_renderer
        self._elements_array = source_elements
        if not ok then
            error(result, 0)
        end
        if copy_failure then
            mod:error("DARKTIDEVR_HUD copy_failed fallback=stock error=%s", copy_failure)
            HudPanel.set_enabled(false)
            -- Spatial elements already drew. Restore only fixed status on the
            -- stock renderer, with the same unwind guarantee as normal drawing.
            self._elements_array = fixed
            local fallback_ok, fallback_error = pcall(func, self, dt, t, input_service)
            self._elements_array = source_elements
            if not fallback_ok then error(fallback_error, 0) end
        end
        return unpack(result, 1, result.n)
    end)

    mod:hook("UIHud", "destroy", function(func, self, ...)
        if state.owner == self then
            destroy_resources()
        end
        return func(self, ...)
    end)
end

-- Called by the existing stereo render hook. DMF rejects registering another
-- hook for the same function within this mod, so instrumentation must share it.
function HudPanel.observe_render(world)
    if world ~= state.render_world then return end
    state.render_submissions = state.render_submissions + 1
    if state.render_submissions == 1 or (state.diagnostic and state.render_submissions % 300 == 0) then
        local queue = World.get_data(world,"render_queue")
        state.mod:info("DARKTIDEVR_HUD render_submissions=%d viewports=%d authored=%s display_ready=%s",
            state.render_submissions,queue and #queue or 0,tostring(state.last_authored_t),tostring(state.display_ready))
    end
end

function HudPanel.draw(world, position, rotation)
    if not state.enabled then
        return
    end
    if state.pending_world and state.pending_world ~= world then
        destroy_resources()
    end
    state.pending_world = world
    if not state.world_gui or not state.world_material or
            not state.display_target or not state.display_ready then
        return
    end
    local forward = Quaternion.forward(rotation)
    local tm = Matrix4x4.identity()
    Matrix4x4.set_right(tm, Quaternion.right(rotation))
    Matrix4x4.set_forward(tm, forward)
    Matrix4x4.set_up(tm, Quaternion.up(rotation))
    Matrix4x4.set_translation(tm, position + forward)
    local width = 2
    local target_width, target_height = target_extent()
    local height = width * target_height / target_width
    if state.diagnostic then
        -- Independent geometry check: cyan backing, magenta target patch.
        -- Only the explicit diagnostic command enables either marker.
        Gui.rect_3d(state.world_gui,tm,Vector2(-width*.5,-height*.5),999,
            Vector2(width,height),Color(255,0,80,90))
    end
    Gui2.bitmap_3d(
        state.world_gui,
        state.world_material,
        nil, -- Existing material handle: stock Gui2 calls only flag material names.
        tm,
        1000,
        {
            color = Color(255, 255, 255, 255),
            position_offset = Vector3(-width * 0.5, -height * 0.5, 0),
            size = Vector2(width, height),
            uv00 = Vector2(0, 0),
            uv11 = Vector2(1, 1),
        })
    if not state.logged then
        state.logged = true
        state.mod:info(
            "DARKTIDEVR_HUD world_surface distance_m=1.000 width_m=%.3f height_m=%.3f",
            width, height)
    end
end

return HudPanel
