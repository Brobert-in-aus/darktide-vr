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
    info=function() end})
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
print("HUD draw restoration across failures, return values and once-per-frame authoring passed")
