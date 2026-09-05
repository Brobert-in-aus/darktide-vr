local MarkerGui = {}
local entries = {}
local function pack(...)
    return { n = select("#", ...), ... }
end

-- Immediate drawings reuse the GUI's buffers. Creating/destroying retained
-- primitives every eye pair grows RenderGui resource handles in this engine.
function MarkerGui.draw(renderer, draw, ...)
    local entry = entries[renderer]
    if not entry then
        entry = { world = renderer.world,
            gui = World.create_screen_gui(renderer.world, "immediate") }
        entries[renderer] = entry
    end
    Gui.set_visible(entry.gui, true)
    entry.visible = true
    local original_gui = renderer.gui
    renderer.gui = entry.gui
    local result = pack(pcall(draw, ...))
    renderer.gui = original_gui
    if not result[1] then
        Gui.set_visible(entry.gui, false)
        entry.visible = false
        error(result[2], 0)
    end
    return unpack(result, 2, result.n)
end

function MarkerGui.hide()
    for _, entry in pairs(entries) do
        if entry.visible then
            Gui.set_visible(entry.gui, false)
            entry.visible = false
        end
    end
end

function MarkerGui.destroy(renderer)
    local entry = entries[renderer]
    if entry then
        entries[renderer] = nil
        World.destroy_gui(entry.world, entry.gui)
    end
end

function MarkerGui.install(mod, renderer_class)
    mod:hook(renderer_class, "destroy", function(func, renderer, ...)
        MarkerGui.destroy(renderer)
        return func(renderer, ...)
    end)
end

return MarkerGui
