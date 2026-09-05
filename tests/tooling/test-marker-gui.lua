local created, destroyed = 0, 0
World = {
    create_screen_gui = function(world, mode)
        assert(mode == "immediate")
        created = created + 1
        return { world = world }
    end,
    destroy_gui = function(world, gui)
        assert(gui.world == world and not gui.destroyed)
        gui.destroyed = true
        destroyed = destroyed + 1
    end,
}
Gui = { set_visible = function(gui, visible)
    assert(not gui.destroyed)
    gui.visible = visible
end }
local markers = dofile(arg[1])
local stock_gui, retained = {}, {}
local renderer = {world = {}, gui = stock_gui, gui_retained = retained}
local marker_gui
-- Simulate many eye pairs: no per-frame resource owners; other HUD remains
-- on its original GUI and only marker drawings are hidden for the second eye.
for frame = 1, 1000 do
    local a, b, c = markers.draw(renderer, function(value)
        marker_gui = renderer.gui
        assert(marker_gui ~= stock_gui and marker_gui.visible)
        assert(renderer.gui_retained == retained)
        return value, nil, 3
    end, frame)
    assert(a == frame and b == nil and c == 3)
    assert(renderer.gui == stock_gui)
    markers.hide()
    assert(not marker_gui.visible)
end
assert(created == 1 and destroyed == 0)
local ok, err = pcall(markers.draw, renderer, function() error("draw failed") end)
assert(not ok and err:find("draw failed", 1, true))
assert(renderer.gui == stock_gui and not marker_gui.visible)
-- Renderer teardown releases the extra GUI before the engine owns teardown.
local hooked
markers.install({hook = function(_, class, name, hook)
    assert(class == renderer and name == "destroy")
    hooked = hook
end}, renderer)
assert(hooked(function(owner, value)
    assert(owner == renderer and marker_gui.destroyed)
    return value
end, renderer, 42) == 42)
markers.destroy(renderer)
markers.hide()
assert(destroyed == 1)
markers.draw(renderer, function() end)
assert(created == 2)
local second = {world={}, gui={}}
markers.draw(second, function() end)
markers.destroy_all()
assert(created == 3 and destroyed == 3)
markers.destroy_all()
markers.destroy(renderer)
markers.destroy(second)
assert(destroyed == 3)
print("marker_gui=pass")
