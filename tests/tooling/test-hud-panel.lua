local failure, calls = nil, {}
local function stage(name)
    calls[name] = (calls[name] or 0) + 1
    if failure == name then error("injected " .. name) end
end
local renderer_api = {
    clear_render_pass_queue=function() stage("queue") end,
    add_render_pass=function() stage("pass") end,
}
package.loaded["scripts/managers/ui/ui_renderer"] = renderer_api
package.loaded["scripts/managers/ui/ui_widget"] = {}
package.loaded["scripts/foundation/utilities/script_world"] = {}
Gui = {bitmap=function() stage("bitmap") end}
Gui.render_pass = function(_, _, name, clear)
    assert(name == "to_screen" and clear == true)
    stage("capture_clear")
end
Renderer = {copy_render_target_rect=function() stage("copy") end}
Vector3, Vector2, Color = function() end, function() end, function() end
local panel = dofile(arg[1])
local hooks = {}
panel.install({hook=function(_, _, method, callback) hooks[method] = callback end,
    info=function() end, error=function() end})
-- Inject already-created resources to isolate the real draw hook from engine
-- allocation. This test exercises restoration, not GPU target correctness.
local state
for i=1,20 do
    local name, value = debug.getupvalue(panel.enabled, i)
    if name == "state" then state = value; break end
end
assert(state)
local spatial = {__class_name="HudElementWorldMarkers"}
local fixed = {__class_name="HudElementPlayerHealth"}
local elements, renderer = {spatial, fixed}, {}
local owner = {_elements_array=elements, _ui_renderer=renderer}
state.owner, state.source_renderer = owner, renderer
state.target_width, state.target_height = 1920, 1080
state.enabled, state.layout_logged = true, true
state.resource_renderer = {render_target={}, render_target_material={}}
state.queue_renderer = {gui={}}
state.display_target = {}
local function stock(self)
    if self._ui_renderer == renderer then
        assert(#self._elements_array == 1 and self._elements_array[1] == spatial)
        stage("spatial")
        return "stock", nil, 7, nil
    end
    assert(self._ui_renderer == state.resource_renderer)
    assert(#self._elements_array == 1 and self._elements_array[1] == fixed)
    stage("fixed")
end
for _, point in ipairs({"spatial", "queue", "pass", "fixed", "bitmap"}) do
    failure, state.last_authored_t = point, nil
    local ok, err = pcall(hooks.draw, stock, owner, .01, 1, {})
    assert(not ok and tostring(err):find("injected " .. point, 1, true))
    assert(owner._elements_array == elements and owner._ui_renderer == renderer,
        "HUD owner leaked temporary state after " .. point)
    assert(state.last_authored_t == nil, "failed draw marked complete")
end
failure, calls = nil, {}
local function pack(...) return {n=select("#", ...), ...} end
local result = pack(hooks.draw(stock, owner, .01, 2, {}))
assert(result.n == 4 and result[1] == "stock" and result[2] == nil and result[3] == 7)
hooks.draw(stock, owner, .01, 2, {}) -- Same frame, second eye.
assert(calls.spatial == 2 and calls.fixed == 1 and calls.copy == nil)
assert(not state.display_ready)
hooks.draw(stock, owner, .01, 2.1, {})
assert(calls.copy == 1 and state.display_ready)
assert(owner._elements_array == elements and owner._ui_renderer == renderer)
-- Explicit disable/unload uses this same public entry point. A shared queue GUI
-- belongs to the queue renderer, so destroy the resource renderer before it.
local destroyed = {}
renderer_api.destroy = function(resource)
    assert(not destroyed[resource], "duplicate renderer destruction")
    destroyed[resource] = true
    if resource == state.queue_renderer then
        assert(destroyed[state.resource_renderer], "queue destroyed before target")
    end
end
Renderer.destroy_resource = function(resource)
    assert(not destroyed[resource], "duplicate target destruction")
    destroyed[resource] = true
end
local target_renderer, queue_renderer, display = state.resource_renderer,
    state.queue_renderer, state.display_target
panel.set_enabled(false)
panel.set_enabled(false)
assert(not panel.enabled() and destroyed[target_renderer] and
    destroyed[queue_renderer] and destroyed[display])
assert(state.resource_renderer == nil and state.display_target == nil)
-- Failure after all target objects exist must release them and draw the stock
-- HUD. It must not leave a half-bound panel eligible for the next frame.
local released = 0
Managers = {ui={create_world=function() return {} end,
    create_viewport=function(_,_,_,kind,_,_,_,targets)
        assert(kind == "overlay" and targets.back_buffer == state.capture_target,
            "HUD viewport must render into its owned capture target")
        return {}
    end,
    destroy_world=function() released = released + 1 end}}
package.loaded["scripts/foundation/utilities/script_world"].destroy_viewport =
    function() released = released + 1 end
renderer_api.create_viewport_renderer = function() return {gui={},gui_retained={}} end
renderer_api.create_resource_renderer = function(_, gui)
    return {gui=gui, render_target_material={}, render_target={}}
end
renderer_api.destroy = function() released = released + 1 end
Renderer.create_resource = function() return {} end
Renderer.destroy_resource = function() released = released + 1 end
World = {create_world_gui=function(_, _, _, _, lifetime)
    assert(lifetime == "immediate", "per-frame HUD draws must not retain old head poses")
    return {}
end,
    destroy_gui=function() released = released + 1 end}
Gui.create_material = function() return {} end
Gui.destroy_material = function() released = released + 1 end
Material = {set_scalar=function() end,set_resource=function() error("binding failure") end}
Matrix4x4 = {identity=function() return {} end}
GuiMaterialFlag = {GUI_RENDER_PASS_LAYER=1}
renderer.world = {}
state.pending_world = renderer.world
panel.set_enabled(true)
local fallback = false
hooks.draw(function(self)
    fallback = true
    assert(self._elements_array == elements and self._ui_renderer == renderer)
end, owner, .01, 3, {})
assert(fallback and state.creation_failed and state.resource_renderer == nil)
assert(released == 7, "partial target creation leaked owned resources")
panel.set_enabled(false)
assert(released == 7, "cleanup retried already released resources")
-- Reuse one allocation during stable rendering; rebuild for actual extent or
-- owner changes. This must not regress into per-eye/per-frame target churn.
Material.set_resource = function() end
local routed_calls = 0
local function fixed_update(_, _, _, target, settings)
    assert(target == state.resource_renderer, "fixed update used stock renderer")
    assert(math.abs(settings.scale - 2.08) < 1e-6 and math.abs(settings.inverse_scale - 1/2.08) < 1e-6)
    routed_calls = routed_calls + 1
    if failure == "fixed_update" then error("injected fixed update") end
    return "updated", nil, 3
end
fixed.update = fixed_update
fixed.set_visible = function(_, _, target)
    assert(target == state.resource_renderer, "fixed visibility used stock renderer")
end
state.pending_world = renderer.world
panel.set_enabled(true)
hooks.draw(stock, owner, .01, 4, {})
assert(calls.capture_clear == 1, "owned capture must clear before each new frame")
hooks.draw(stock, owner, .01, 4, {})
assert(calls.capture_clear == 1, "second eye must not clear the same frame again")
local settings = {scale=1.3,inverse_scale=1/1.3}
local function update_owner(self)
    self._elements_array[2]:set_visible(false, self._ui_renderer)
    return self._elements_array[2]:update(.01, 4, self._ui_renderer, settings)
end
local update_result = pack(hooks.update(update_owner, owner, .01, 4, {}))
assert(update_result.n == 3 and update_result[1] == "updated" and update_result[3] == 3)
assert(routed_calls == 1 and settings.scale == 1.3 and state.updating_owner == nil)
failure = "fixed_update"
assert(not pcall(hooks.update, update_owner, owner, .01, 4, {}))
assert(settings.scale == 1.3 and settings.inverse_scale == 1/1.3 and state.updating_owner == nil)
failure = nil
assert(state.capture_target and state.resource_renderer.render_target == nil
    and state.resource_renderer.base_render_pass == nil,
    "direct viewport UI must not also redirect a named render pass")
local first_target = state.display_target
assert(state.target_width == 1920 and state.target_height == 1080)
hooks.draw(stock, owner, .01, 5, {})
assert(state.display_target == first_target and released == 7)
RESOLUTION_LOOKUP = {scale=2}
hooks.draw(stock, owner, .01, 6, {})
assert(state.display_target ~= first_target and released == 14)
assert(state.target_width == 3840 and state.target_height == 2160)
local second_target = state.display_target
local next_owner = {_elements_array=elements, _ui_renderer=renderer}
hooks.draw(stock, next_owner, .01, 7, {})
assert(state.owner == next_owner and state.display_target ~= second_target and released == 21)
assert(next_owner._elements_array == elements and next_owner._ui_renderer == renderer)
-- A failed copy must not hide fixed status or leave the experimental panel
-- active with a stale texture. Spatial elements are not redrawn in fallback.
failure = "copy"
local fallback_fixed = 0
hooks.draw(function(self)
    assert(self._ui_renderer == renderer)
    if self._elements_array[1] == fixed then fallback_fixed = fallback_fixed + 1 end
end, next_owner, .01, 8, {})
assert(fallback_fixed == 1 and not panel.enabled() and not state.display_ready)
assert(next_owner._elements_array == elements and next_owner._ui_renderer == renderer)
panel.set_enabled(false)
assert(released == 28)
assert(fixed.update == fixed_update, "cleanup must restore original callbacks")
-- The same-world diagnostic borrows the game's renderer/world. It owns only
-- its target renderer/material, display target and world GUI.
failure = nil
state.same_world_probe = true
renderer.gui, renderer.gui_retained = {}, {}
state.pending_world = renderer.world
panel.set_enabled(true)
hooks.draw(stock, owner, .01, 9, {})
assert(state.queue_renderer == renderer and state.borrowed_renderer)
hooks.draw(stock, owner, .01, 10, {})
local v3meta = {__add=function(a) return a end}
Vector3 = function(x,y,z) return setmetatable({x,y,z,kind="v3"},v3meta) end
v3meta.__unm=function(v) return Vector3(-v[1],-v[2],-v[3]) end
Vector2 = function(x,y) return {x,y,kind="v2"} end
Quaternion = {forward=function() return Vector3(0,1,0) end,
    right=function() return Vector3(1,0,0) end,up=function() return Vector3(0,0,1) end}
Matrix4x4.set_right, Matrix4x4.set_forward, Matrix4x4.set_up, Matrix4x4.set_translation =
    function(tm,v) tm.right=v end,function(tm,v) tm.forward=v end,function() end,function() end
local bitmap_drawn = false
Gui2 = {bitmap_3d = function(_,material,flags,tm,_,options)
    local offset,size=options.position_offset,options.size
    assert(material == state.world_material)
    assert(flags == nil and tm.right[1] == -1 and tm.forward[2] == -1,
        "textured HUD must face the viewer")
    assert(options.uv00[1] == 1 and options.uv11[1] == 0,
        "viewer-facing HUD must undo horizontal mirroring")
    assert(options.uv00[2] == 1 and options.uv11[2] == 0,
        "captured HUD must read upright on the world panel")
    assert(offset.kind == "v3" and offset[3] == 0 and size.kind == "v3")
    assert(math.abs(size[1] - 0.8) < 1e-6 and math.abs(size[2] - 0.81) < 1e-6)
    bitmap_drawn = true
end}
panel.draw(renderer.world,Vector3(0,0,0),{})
assert(bitmap_drawn)
panel.set_enabled(false)
assert(released == 32, "borrowed gameplay renderer/world were destroyed")
print("HUD error restoration, stereo authoring and idempotent resource cleanup passed")
local function pose(x,angle)
    return {x=x,y=0,z=0,qx=0,qy=0,qz=math.sin(angle/2),qw=math.cos(angle/2)}
end
local initial = panel.follow_pose(nil,pose(0,0),0)
local followed = panel.follow_pose(initial,pose(.1,math.rad(4)),1/60)
assert(followed.x > 0 and followed.x < .1 and followed.qz > 0 and followed.qz < math.sin(math.rad(2)))
assert(panel.follow_pose(followed,pose(.2,0),1/60) == followed, "second eye advanced follow")
local reset = panel.follow_pose(followed,pose(10,0),2/60)
assert(reset.x == 10, "teleport must reset follow")
local same_rotation = pose(0,0)
same_rotation.qw = -1
assert(math.abs(panel.follow_pose(initial,same_rotation,1/60).qw) == 1,
    "equivalent quaternion signs must not rotate the panel")
local sixty,one_twenty = initial,initial
for i=1,60 do sixty=panel.follow_pose(sixty,pose(.1,0),i/60) end
for i=1,120 do one_twenty=panel.follow_pose(one_twenty,pose(.1,0),i/120) end
assert(math.abs(sixty.x-one_twenty.x) < 1e-9, "follow depends on frame rate")
