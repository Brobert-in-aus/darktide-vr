local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")
local ScriptWorld = require("scripts/foundation/utilities/script_world")

local HudPanel = {}
HudPanel.height = 1.125 * 0.9
HudPanel.distance = 1
HudPanel.scale = 0.8
HudPanel.object_scale = 2.08

-- Store scalar poses across frames: engine Vector3/Quaternion temporaries
-- cannot safely survive the frame that allocated them.
function HudPanel.follow_pose(previous, target, t)
    target.t = t
    if not previous or t - previous.t > 0.5 or t < previous.t then return target end
    if t == previous.t then return previous end
    local dx,dy,dz = target.x-previous.x,target.y-previous.y,target.z-previous.z
    if dx*dx+dy*dy+dz*dz > 0.25 then return target end
    local anchor = previous.goal or previous
    local goal = {x=target.x,y=target.y,z=target.z,
        qx=anchor.qx,qy=anchor.qy,qz=anchor.qz,qw=anchor.qw}
    local goal_dot = math.abs(anchor.qx*target.qx+anchor.qy*target.qy+
        anchor.qz*target.qz+anchor.qw*target.qw)
    if 2*math.acos(math.min(1,goal_dot)) > math.rad(4) then
        goal.qx,goal.qy,goal.qz,goal.qw = target.qx,target.qy,target.qz,target.qw
    end
    target = goal
    local dt = t-previous.t
    -- Translation tracks the current head exactly; only viewing angles lag.
    local result = {t=t,goal=goal,x=target.x,y=target.y,z=target.z}
    local function spring(key, goal, smooth_time)
        local omega = 2/smooth_time
        local change = previous[key]-goal
        local temp = ((previous["v"..key] or 0)+omega*change)*dt
        local decay = math.exp(-omega*dt)
        result[key] = goal+(change+temp)*decay
        result["v"..key] = ((previous["v"..key] or 0)-omega*temp)*decay
    end
    local dot = previous.qx*target.qx+previous.qy*target.qy+
        previous.qz*target.qz+previous.qw*target.qw
    local sign = dot < 0 and -1 or 1
    for _, key in ipairs({"qx","qy","qz","qw"}) do spring(key,target[key]*sign,0.32) end
    local length = math.sqrt(result.qx^2+result.qy^2+result.qz^2+result.qw^2)
    for _, key in ipairs({"qx","qy","qz","qw"}) do result[key] = result[key]/length end
    return result
end

local function pack(...)
    return {n=select("#", ...), ...}
end

local state = {
    enabled = false,
    diagnostic = false,
    symbol_probe = false,
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
    capture_target = nil,
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
    update_routes = {},
    updating_owner = nil,
    follow_pose = nil,
    layout_nodes = {},
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

local function place_status_node(element, id, x, y, scale)
    local node = element._ui_scenegraph and rawget(element._ui_scenegraph,id)
    if not node then return end
    local p = node.position
    if p[1] == x and p[2] == y and node.horizontal_alignment == "left" and
            node.vertical_alignment == "top" then return end
    if not state.layout_nodes[node] then
        state.layout_nodes[node] = {element=element,id=id,x=p[1],y=p[2],
            horizontal=node.horizontal_alignment,vertical=node.vertical_alignment}
    end
    element:set_scenegraph_position(id,x,y,nil,"left","top")
    local function refresh(instance)
        require("scripts/managers/ui/ui_scenegraph").update_scenegraph(instance._ui_scenegraph,scale)
        instance:set_dirty()
    end
    refresh(element)
    -- AbilityHandler forwards placement to its current cooldown instances.
    for _, data in pairs(element._instance_data_tables or {}) do
        if data.scenegraph_id == id then refresh(data.instance) end
    end
end

function HudPanel.layout_status(owner)
    local elements = owner._elements or {}
    local team = elements.HudElementTeamPanelHandler
    local panel
    for _, data in ipairs(team and team._player_panels_array or {}) do
        if data.scenegraph_id == "local_player" then panel = data.panel; break end
    end
    local bar = panel and panel._ui_scenegraph and rawget(panel._ui_scenegraph,"bar")
    if not bar or not bar.world_position or not bar.size then return end
    local x,y = bar.world_position[1],bar.world_position[2]
    local scale = require("scripts/utilities/ui/hud").hud_scale() * HudPanel.object_scale
    local buffs = elements.HudElementPlayerBuffs
    local ability = elements.HudElementPlayerAbilityHandler
    local buff_node = buffs and buffs._ui_scenegraph and rawget(buffs._ui_scenegraph,"background")
    local ability_node = ability and ability._ui_scenegraph and rawget(ability._ui_scenegraph,"slot_combat_ability")
    -- Leave room for the toughness strip/name above HP. Both groups share
    -- a baseline, with their outer edges tied to the actual live health bar.
    if buff_node then place_status_node(buffs,"background",x,y-80-buff_node.size[2],scale) end
    if ability_node then
        place_status_node(ability,"slot_combat_ability",
            x+bar.size[1]-ability_node.size[1],y-80-ability_node.size[2],scale)
    end
    local wield = elements.HudElementWieldInfo
    local wield_node = wield and wield._ui_scenegraph and rawget(wield._ui_scenegraph,"bounding_box")
    if wield_node then
        local screen_width = state.target_width or (RESOLUTION_LOOKUP and RESOLUTION_LOOKUP.width) or 1920
        place_status_node(wield,"bounding_box",(screen_width/scale-wield_node.size[1])*0.5,
            y-220-wield_node.size[2],scale)
    end
end

-- Stock UIHud.update passes its screen renderer to visibility and widget
-- refresh callbacks. Retained records now belong to the capture renderer.
-- Route these callbacks without running game/HUD updates a second time.
local function route_fixed_updates(owner)
    local _, fixed = partition_elements(owner._elements_array)
    for _, element in ipairs(fixed) do
        if element.on_resolution_modified then element:on_resolution_modified() end
        for _, name in ipairs({"begin_update", "update", "end_update", "draw", "set_visible"}) do
            local original = element[name]
            if type(original) == "function" then
                local record = {element=element,name=name,own=rawget(element,name)}
                local function route(renderer)
                    if state.updating_owner == owner and renderer == state.source_renderer then
                        return state.resource_renderer
                    end
                    return renderer
                end
                if name == "set_visible" then
                    record.wrapper = function(self, visible, renderer, ...)
                        return original(self, visible, route(renderer), ...)
                    end
                else
                    record.wrapper = function(self, dt, t, renderer, settings, ...)
                        renderer = route(renderer)
                        if renderer ~= state.resource_renderer or not settings then
                            return original(self, dt, t, renderer, settings, ...)
                        end
                        local scale, inverse = settings.scale, settings.inverse_scale
                        settings.scale = (scale or 1) * HudPanel.object_scale
                        settings.inverse_scale = 1 / settings.scale
                        local result = pack(pcall(original, self, dt, t, renderer, settings, ...))
                        settings.scale, settings.inverse_scale = scale, inverse
                        if not result[1] then error(result[2], 0) end
                        return unpack(result, 2, result.n)
                    end
                end
                element[name] = record.wrapper
                state.update_routes[#state.update_routes+1] = record
            end
        end
    end
end

local function destroy_resources()
    state.follow_pose = nil
    for _, record in pairs(state.layout_nodes) do
        record.element:set_scenegraph_position(record.id,record.x,record.y,nil,
            record.horizontal,record.vertical)
    end
    state.layout_nodes = {}
    for _, record in ipairs(state.update_routes) do
        if record.element[record.name] == record.wrapper then
            record.element[record.name] = record.own
        end
    end
    state.update_routes = {}
    if state.owner then
        local _, fixed = partition_elements(state.owner._elements_array or {})
        for _, element in ipairs(fixed) do
            if element.on_resolution_modified then element:on_resolution_modified() end
        end
    end
    if state.resource_renderer and state.source_renderer then
        transfer_fixed_records(state.owner, state.resource_renderer,
            state.source_renderer, nil)
    end
    if state.world and state.world_gui then
        pcall(World.destroy_gui, state.world, state.world_gui)
    end
    if state.resource_renderer then
        if state.capture_target then
            -- Restore ownership metadata before stock destruction. During
            -- drawing this renderer behaves as ordinary viewport UI.
            state.resource_renderer.render_target = state.capture_target
        end
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
    state.capture_target = nil
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
    if not state.borrowed_renderer then
        state.capture_target = resource_renderer.render_target
        state.render_viewport_name = name .. "_viewport"
        local viewport_ok, viewport = pcall(
            Managers.ui.create_viewport, Managers.ui, render_world,
            state.render_viewport_name, "overlay", 1, nil, nil,
            {back_buffer=state.capture_target})
        if not viewport_ok or not viewport then
            mod:error("DARKTIDEVR_HUD render_viewport_failed error=%s", tostring(viewport))
            destroy_resources()
            state.creation_failed = true
            return nil
        end
        state.render_viewport = viewport
        -- The viewport owns the output binding, like the stock icon generator.
        -- Author normal UI, without a second named offscreen pass or terminal
        -- screen sample. Resource ownership is restored during destruction.
        resource_renderer.render_target = nil
        resource_renderer.base_render_pass = nil
        resource_renderer.render_pass_flag = nil
    end
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
        -- Both the bitmap and diagnostic backing are authored every frame.
        -- Retained mode leaves every old head pose alive until GUI destruction.
        world, Matrix4x4.identity(), 1, 1, "immediate")
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
        -- Item atlas materials sample local UVs instead of masking a matching
        -- screen-space region of a render target.
        "content/ui/materials/icons/items/containers/item_container_square")
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
    local binding_ok, binding_error = pcall(function()
        Material.set_scalar(material, "use_placeholder_texture", 0)
        Material.set_scalar(material, "use_render_target", 1)
        Material.set_scalar(material, "rows", 1)
        Material.set_scalar(material, "columns", 1)
        Material.set_scalar(material, "grid_index", 0)
        Material.set_resource(material, "render_target", display_target)
    end)
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
    route_fixed_updates(owner)
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
    if command ~= "enable" and command ~= "disable" and command ~= "diagnostic" and command ~= "source" and command ~= "sameworld" and command ~= "symbol" then
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
    state.symbol_probe = command == "symbol"
    state.diagnostic = command == "diagnostic" or command == "source" or same_world or state.symbol_probe
    HudPanel.set_enabled(command ~= "disable")
    if state.world_material and state.resource_renderer then
        local target = command == "source" and (state.capture_target or state.resource_renderer.render_target) or state.display_target
        Material.set_resource(state.world_material,"render_target",target)
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
        if state.owner ~= self or not state.resource_renderer then
            return func(self, dt, t, input_service)
        end
        local previous = state.updating_owner
        state.updating_owner = self
        local result = pack(pcall(func, self, dt, t, input_service))
        state.updating_owner = previous
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
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
        HudPanel.layout_status(self)
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
                        state.capture_target or resource_renderer.render_target,
                        0, 0, 1, 1, state.display_target, 0, 0, 1, 1)
                    if not copied then
                        copy_failure = tostring(detail)
                        return spatial_result
                    end
                    state.display_ready = true
                end
                -- Retain the named-pass path only for same-world diagnostics.
                if state.capture_target then
                    -- Overlay viewports preserve their backbuffer by default.
                    -- Clear our owned target before authoring this frame's HUD.
                    Gui.render_pass(state.queue_renderer.gui, 0, "to_screen", true)
                else
                    UIRenderer.clear_render_pass_queue(state.queue_renderer)
                    UIRenderer.add_render_pass(state.queue_renderer, 0,
                        resource_renderer.base_render_pass, true,
                        resource_renderer.render_target)
                    UIRenderer.add_render_pass(state.queue_renderer, 1,
                        "to_screen", false)
                end
                self._elements_array = fixed
                self._ui_renderer = resource_renderer
                func(self, dt, t, input_service)
                self._ui_renderer = source_renderer
                if state.diagnostic then
                    Gui2.rect(state.queue_renderer.gui,Vector3(50,50,1),Vector3(400,200,0),
                        {render_pass=resource_renderer.base_render_pass,color=Color(255,255,0,255)})
                end
                -- This is a render dependency, not a visible corner pixel.
                if not state.capture_target then Gui.bitmap(
                    state.queue_renderer.gui,
                    resource_renderer.render_target_material,
                    "render_pass", "to_screen",
                    Vector3(0, 0, 1),
                    Vector3(state.diagnostic and 320 or 1, state.diagnostic and 180 or 1, 0),
                    Color(state.diagnostic and 255 or 0, 255, 255, 255)) end
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

function HudPanel.draw(world, position, rotation, overlap_width)
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
    -- Keep the panel level: head roll must not tilt its readable surface.
    rotation = Quaternion.look(Quaternion.forward(rotation), Vector3.up())
    local now = Managers and Managers.time and Managers.time:time("main")
    if now then
        local qx,qy,qz,qw = Quaternion.to_elements(rotation)
        state.follow_pose = HudPanel.follow_pose(state.follow_pose,
            {x=position.x,y=position.y,z=position.z,qx=qx,qy=qy,qz=qz,qw=qw},now)
        local pose = state.follow_pose
        rotation = Quaternion.from_elements(pose.qx,pose.qy,pose.qz,pose.qw)
    end
    rotation = Quaternion.look(Quaternion.forward(rotation), Vector3.up())
    local forward = Quaternion.forward(rotation)
    local tm = Matrix4x4.identity()
    -- Textured world GUI culls the back face; colored rectangles do not.
    -- Face the viewer, then reverse U below to preserve left-to-right text.
    Matrix4x4.set_right(tm, -Quaternion.right(rotation))
    Matrix4x4.set_forward(tm, -forward)
    Matrix4x4.set_up(tm, Quaternion.up(rotation))
    Matrix4x4.set_translation(tm, position + forward * HudPanel.distance)
    local width = (overlap_width or 1) * HudPanel.scale
    local height = HudPanel.height * HudPanel.scale
    if width <= 0 then return end
    if state.diagnostic then
        -- Outline leaves the bitmap test unobscured even if world-GUI depth
        -- ordering differs from screen-GUI layer ordering.
        for _, edge in ipairs({
            {-width*.5,-height*.5,width,.006},
            {-width*.5,height*.5-.006,width,.006},
            {-width*.5,-height*.5,.006,height},
            {width*.5-.006,-height*.5,.006,height}}) do
            Gui.rect_3d(state.world_gui,tm,Vector2(edge[1],edge[2]),999,
                Vector2(edge[3],edge[4]),Color(255,0,180,190))
        end
    end
    Gui2.bitmap_3d(
        state.world_gui,
        state.symbol_probe and "content/ui/materials/symbols/infinite" or state.world_material,
        nil,
        tm,
        1000,
        {position_offset=Vector3(-width*.5,-height*.5,0),
         size=Vector3(width,height,0),color=Color(255,255,255,255),
         uv00=Vector2(1,1),uv11=Vector2(0,0),snap_pixel_positions=false})
    if not state.logged then
        state.logged = true
        state.mod:info(
            "DARKTIDEVR_HUD world_surface distance_m=1.000 width_m=%.3f height_m=%.3f",
            width, height)
    end
end

return HudPanel
