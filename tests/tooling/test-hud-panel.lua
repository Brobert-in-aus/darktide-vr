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
assert(calls.spatial == 2 and calls.fixed == 1 and calls.copy == 1)
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
    create_viewport=function() return {} end,
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
World = {create_world_gui=function() return {} end,
    destroy_gui=function() released = released + 1 end}
Gui.create_material = function() return {} end
Gui.destroy_material = function() released = released + 1 end
Material = {set_resource=function() error("binding failure") end}
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
state.pending_world = renderer.world
panel.set_enabled(true)
hooks.draw(stock, owner, .01, 4, {})
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
panel.set_enabled(false)
assert(released == 28)
print("HUD error restoration, stereo authoring and idempotent resource cleanup passed")
