local widgets = assert(loadfile(arg[1]))()
RESOLUTION_LOOKUP = { scale = 1, width = 100, height = 100 }
math.clamp = function(value, low, high) return math.max(low, math.min(high, value)) end
local p = { mode = 5 }
widgets.install({ info = function() end }, p)
local instance = { _ui_scenegraph = { row = { world_position = { 0, 0 }, size = { 100, 20 } } } }
local hotspot = { force_hover = true, force_input_pressed = true }
local widget = { scenegraph_id = "row", content = { hotspot = hotspot },
    style = { hotspot = { visible = false } },
    passes = { { pass_type = "hotspot" } } }
assert(#p.widget_hotspot_entries(widget) == 0, "hidden authored hotspot reappeared")
widget.style.hotspot.visible = true
widget.passes[1].visibility_function = function() return false end
assert(#p.widget_hotspot_entries(widget) == 0, "visibility callback was bypassed")
widget.passes = {}
assert(#p.widget_hotspot_entries(widget) == 1, "unrepresented hotspot lost fallback")
widget.style.hotspot.visible = false
assert(#p.widget_hotspot_entries(widget) == 0, "hidden fallback became interactive")
widget.type = "dropdown"
widget.content.exclusive_focus = false
widget.content.option_hotspot_9 = { force_hover = true, force_input_pressed = true }
p.clear_widget_hotspot_forces(widget)
assert(not hotspot.force_hover and not hotspot.force_input_pressed)
assert(not widget.content.option_hotspot_9.force_hover and not widget.content.option_hotspot_9.force_input_pressed)
widget.content.exclusive_focus = true
widget.content.num_visible_options = 1
widget.content.option_hotspot_1 = {}
widget.style.option_hotspot_1 = {}
widget.passes = { { pass_type = "hotspot", content_id = "option_hotspot_1",
    visibility_function = function() return false end } }
assert(#p.widget_hotspot_entries(widget, true) == 0, "dropdown fallback bypassed visibility")
widget.passes = {}
assert(#p.widget_hotspot_entries(widget, true) == 1)
local pointer = { active = true, available = true, primary_down = true,
    x = 55, y = 10, source_width = 100, source_height = 100, last_sequence = 1 }
widget.style.track_hotspot = { size = { 100, 20 } }
widget.content.slider_value = 0
widget.content.step_size = 0.1
assert(p.begin_slider_drag(instance, widget, pointer))
assert(math.abs(widget.content.slider_value - 0.6) < 1e-6)
widget.content.slider_value = 0
assert(p.update_slider_drag(instance, { available = false }))
assert(math.abs(widget.content.slider_value - 0.6) < 1e-6)
pointer.primary_down = false
assert(not p.update_slider_drag(instance, pointer))
assert(not widget.content.drag_active and p.slider_drag == nil)
pointer.source_width = 0
local hit, geometry = p.widget_contains_menu_pointer(instance, widget, pointer)
assert(not hit and geometry == nil, "invalid transport extent produced geometry")
local left, top = p.aligned_pass_origin(10, 20, 100, 50,
    { size = { 20, 10 }, horizontal_alignment = "right", vertical_alignment = "center", offset = { 2, 3 } })
assert(left == 92 and top == 43)
print("Menu widget visibility, cleanup, geometry, and drag contracts passed")
