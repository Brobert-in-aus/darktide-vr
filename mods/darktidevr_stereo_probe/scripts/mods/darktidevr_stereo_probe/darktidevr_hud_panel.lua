local UIRenderer = require("scripts/managers/ui/ui_renderer")

local HudPanel = {}

local state = {
    -- Disabled until retained HUD records can be migrated/rebuilt against the
    -- offscreen pass. Leaving the prototype active suppresses stock fixed HUD.
    enabled = false,
    owner = nil,
    resource_renderer = nil,
    display_target = nil,
    world = nil,
    gui = nil,
    material = nil,
    last_authored_t = nil,
    last_copy_t = nil,
    generation = 0,
    logged = false,
    layout_logged = false,
}

-- These elements derive meaning from scene depth or screen-edge direction and
-- must remain in the ordinary per-eye HUD pass. Everything else is a fixed HUD
-- group and is authored once into the head-relative panel.
local spatial_elements = {
    HudElementWorldMarkers = true,
    HudElementInteraction = true,
    HudElementNameplates = true,
    HudElementSmartTagging = true,
    HudElementMinionShieldHealth = true,
    HudElementDamageIndicator = true,
}

local function destroy_world_surface()
    if state.world and state.gui then
        pcall(World.destroy_gui, state.world, state.gui)
    end
    state.world = nil
    state.gui = nil
    state.material = nil
end

local function destroy_resources()
    destroy_world_surface()
    local renderer = state.resource_renderer
    if renderer then
        if renderer.render_target_material and renderer.gui then
            pcall(Gui.destroy_material, renderer.gui,
                renderer.render_target_material)
        end
        if renderer.render_target then
            pcall(Renderer.destroy_resource, renderer.render_target)
        end
    end
    if state.display_target then
        pcall(Renderer.destroy_resource, state.display_target)
    end
    state.owner = nil
    state.resource_renderer = nil
    state.display_target = nil
    state.last_authored_t = nil
    state.last_copy_t = nil
    state.logged = false
    state.layout_logged = false
end

local function ensure_resources(mod, owner, source_renderer)
    if state.owner == owner and state.resource_renderer and
            state.display_target then
        return state.resource_renderer
    end
    destroy_resources()
    state.generation = state.generation + 1
    local pass_name = "darktidevr_hud_ui_" .. tostring(state.generation)
    local ok, renderer = pcall(
        UIRenderer.create_resource_renderer,
        source_renderer.world,
        source_renderer.gui,
        source_renderer.gui_retained,
        pass_name,
        "content/ui/materials/render_target_masks/ui_render_target_straight_blur",
        1920,
        1080,
        true)
    if not ok or not renderer then
        mod:error("DARKTIDEVR_HUD target_create_failed error=%s",
            tostring(renderer))
        return nil
    end
    -- Retained widget records belong to the source renderer/Gui. Register the
    -- retained Gui side once; the source immediate renderer is redirected and
    -- cleared once per update below, matching the proven menu-target path.
    if renderer.gui_retained and renderer.gui_retained ~= renderer.gui then
        Gui.render_pass(
            renderer.gui_retained, 0, renderer.base_render_pass, true,
            renderer.render_target)
    end
    local display_ok, display = pcall(
        Renderer.create_resource,
        "render_target", "R8G8B8A8", nil,
        1920, 1080, "darktidevr_hud_display")
    if not display_ok or not display then
        mod:error("DARKTIDEVR_HUD display_create_failed error=%s",
            tostring(display))
        if renderer.render_target then
            pcall(Renderer.destroy_resource, renderer.render_target)
        end
        return nil
    end
    state.owner = owner
    state.resource_renderer = renderer
    state.display_target = display
    mod:info(
        "DARKTIDEVR_HUD target_created width=1920 height=1080 generation=%d pass=%s",
        state.generation, pass_name)
    return renderer
end

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

function HudPanel.install(mod)
    mod:hook("UIHud", "update", function(func, self, dt, t, input_service)
        if not state.enabled or not self._ui_renderer or
                type(self._elements_array) ~= "table" then
            return func(self, dt, t, input_service)
        end
        local resource_renderer = ensure_resources(mod, self, self._ui_renderer)
        if not resource_renderer then
            return func(self, dt, t, input_service)
        end
        local spatial, fixed = partition_elements(self._elements_array)
        log_partition(mod, spatial, fixed)
        local source_elements = self._elements_array
        local source_renderer = self._ui_renderer

        self._elements_array = spatial
        func(self, dt, t, input_service)
        local spatial_using_input = self._element_using_input

        self._elements_array = fixed
        local source_base_render_pass = source_renderer.base_render_pass
        local source_render_pass_flag = source_renderer.render_pass_flag
        UIRenderer.clear_render_pass_queue(source_renderer)
        UIRenderer.add_render_pass(
            source_renderer, 0, resource_renderer.base_render_pass, true,
            resource_renderer.render_target)
        source_renderer.base_render_pass = resource_renderer.base_render_pass
        source_renderer.render_pass_flag = resource_renderer.render_pass_flag
        func(self, dt, t, input_service)
        self._element_using_input = spatial_using_input or
            self._element_using_input
        source_renderer.base_render_pass = source_base_render_pass
        source_renderer.render_pass_flag = source_render_pass_flag

        self._elements_array = source_elements
    end)

    mod:hook("UIHud", "draw", function(func, self, dt, t, input_service)
        if not state.enabled or not self._ui_renderer or
                type(self._elements_array) ~= "table" then
            return func(self, dt, t, input_service)
        end
        local resource_renderer = ensure_resources(mod, self, self._ui_renderer)
        if not resource_renderer then
            return func(self, dt, t, input_service)
        end
        local spatial, fixed = partition_elements(self._elements_array)
        log_partition(mod, spatial, fixed)
        local source_elements = self._elements_array
        local source_renderer = self._ui_renderer

        self._elements_array = spatial
        local result = func(self, dt, t, input_service)

        -- The target pass was registered once when the resource renderer was
        -- created. Its normal begin/end lifecycle selects that pass; never
        -- clear/re-add it here because Stingray retains GUI pass names.
        -- UIHud.draw is reached once per eye with the same simulation time.
        -- Author fixed HUD content only for the first eye and reuse that target
        -- for the second; spatial HUD elements continue to draw per eye.
        if state.last_authored_t ~= t then
            self._elements_array = fixed
            local source_base_render_pass = source_renderer.base_render_pass
            local source_render_pass_flag = source_renderer.render_pass_flag
            source_renderer.base_render_pass = resource_renderer.base_render_pass
            source_renderer.render_pass_flag = resource_renderer.render_pass_flag
            func(self, dt, t, input_service)
            source_renderer.base_render_pass = source_base_render_pass
            source_renderer.render_pass_flag = source_render_pass_flag
            state.last_authored_t = t
        end
        self._elements_array = source_elements
        return result
    end)

    mod:hook("UIHud", "destroy", function(func, self, ...)
        if state.owner == self then
            destroy_resources()
        end
        return func(self, ...)
    end)
end

function HudPanel.draw(world, position, rotation)
    if not state.enabled or not state.resource_renderer or
            not state.display_target then
        return
    end
    local copy_t = Managers.time and Managers.time:time("ui") or 0
    if state.last_copy_t ~= copy_t then
        pcall(
            Renderer.copy_render_target_rect,
            state.resource_renderer.render_target,
            0, 0, 1, 1,
            state.display_target,
            0, 0, 1, 1)
        state.last_copy_t = copy_t
    end
    if state.world ~= world then
        destroy_world_surface()
    end
    if not state.gui then
        local gui = World.create_world_gui(world, Matrix4x4.identity(), 1, 1)
        local material = Gui.create_material(
            gui,
            "content/ui/materials/render_target_masks/ui_render_target_straight_blur",
            GuiMaterialFlag.GUI_RENDER_PASS_LAYER)
        Material.set_resource(material, "source", state.display_target)
        state.world = world
        state.gui = gui
        state.material = material
    end

    local forward = Quaternion.forward(rotation)
    local tm = Matrix4x4.identity()
    Matrix4x4.set_right(tm, Quaternion.right(rotation))
    Matrix4x4.set_forward(tm, forward)
    Matrix4x4.set_up(tm, Quaternion.up(rotation))
    Matrix4x4.set_translation(tm, position + forward * 2)
    local width = 2
    local height = width * 9 / 16
    Gui2.bitmap_3d(
        state.gui,
        state.material,
        GuiMaterialFlag.GUI_RENDER_PASS_LAYER,
        tm,
        1000,
        {
            color = Color(255, 255, 255, 255),
            position_offset = Vector3(-width * 0.5, -height * 0.5, 0),
            size = Vector2(width, height),
            uv00 = Vector2(0, 0),
            uv11 = Vector2(1, 1),
        })
end

return HudPanel
