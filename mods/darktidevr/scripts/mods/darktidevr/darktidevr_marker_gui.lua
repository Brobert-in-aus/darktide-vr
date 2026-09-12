local MarkerGui = {}
local entries = {}
local function finish_draw(renderer, original_gui, entry, ok, ...)
    renderer.gui = original_gui
    if not ok then
        Gui.set_visible(entry.gui, false)
        entry.visible = false
        error((...), 0)
    end
    return ...
end

-- UIHud reuses this table for every element, changing scale, alpha and
-- retained mode. A second-eye pass must retain the settings of its own draw,
-- not those left behind by the last fixed HUD element or layout editor.
function MarkerGui.snapshot_settings(settings)
    local snapshot = {}
    for key, value in pairs(settings) do snapshot[key] = value end
    return snapshot
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
    return finish_draw(renderer, original_gui, entry, pcall(draw, ...))
end

-- Hidden HUDs do not author a primary marker pass. Never replay its old
-- coordinates against a new camera or after an editor/menu changes ownership.
function MarkerGui.can_replay(context, owner, t)
    local visible = owner and owner._currently_visible_elements
    return context ~= nil and context.t == t and context.instance._parent == owner and
        visible ~= nil and visible.HudElementWorldMarkers == true
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

function MarkerGui.destroy_all()
    for renderer in pairs(entries) do
        MarkerGui.destroy(renderer)
    end
end

-- The one destroy hook this mod places on the renderer class; `on_destroy`
-- lets another owner (the world-surface markers) release its GUI too.
function MarkerGui.install(mod, renderer_class, on_destroy)
    mod:hook(renderer_class, "destroy", function(func, renderer, ...)
        MarkerGui.destroy(renderer)
        if on_destroy then pcall(on_destroy, renderer) end
        return func(renderer, ...)
    end)
end

return MarkerGui
