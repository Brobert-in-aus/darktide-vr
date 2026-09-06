local widgets = assert(loadfile(arg[1]))()
RESOLUTION_LOOKUP = { scale = 1, width = 100, height = 100 }
math.clamp = function(value, low, high) return math.max(low, math.min(high, value)) end
local p = { mode = 5 }
widgets.install({ info = function() end }, p)
local edge = { primary_press_sequence = 5, primary_consumed_sequence = 4,
    primary_pressed = true, x = 10, y = 20 }
assert(p.claim_menu_pointer_sample(edge))
assert(not p.claim_menu_pointer_sample(edge), "widget passes resampled a pending click")
-- No widget accepted the press. Moving over a button next frame must not
-- resurrect it (live regression: social/play activated a second after miss).
p.begin_menu_pointer_frame(edge)
edge.x = 90
assert(edge.primary_consumed_sequence == 5 and not edge.primary_pressed,
    "missed click survived into later hover")
assert(p.claim_menu_pointer_sample(edge), "new UI frame did not sample")
assert(not p.claim_menu_pointer_sample(edge))
edge.primary_press_sequence = 6
edge.primary_pressed = edge.primary_press_sequence ~= edge.primary_consumed_sequence
assert(edge.primary_pressed, "fresh deliberate press was suppressed")
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
-- Captured pixels must map into the actual character-select canvas.
RESOLUTION_LOOKUP = { scale = 1, width = 1280, height = 768 }
local menu = { _ui_scenegraph = { play = {
    world_position = { 883, 564 }, size = { 327, 100 } } } }
local play = { scenegraph_id = "play", content = {} }
local captured = { active = true, x = 790, y = 465,
    source_width = 1024, source_height = 614 }
assert(p.widget_contains_menu_pointer(menu, play, captured),
    "scaled capture missed visible Play button")
captured.x = 400
assert(not p.widget_contains_menu_pointer(menu, play, captured),
    "empty capture space hit Play")
-- An explicitly transformed shop pointer retains its portrait coordinate space.
captured.x, captured.y = 950, 600
captured.source_width, captured.source_height = 2496, 2688
captured.layout_width, captured.layout_height = 2496, 2688
assert(p.widget_contains_menu_pointer(menu, play, captured),
    "vendor pointer was scaled twice")
print("Menu widget visibility, cleanup, geometry, and drag contracts passed")
local missed={primary_pressed=true,primary_press_sequence=4,
    secondary_pressed=true,secondary_press_sequence=9}
p.begin_menu_pointer_frame(missed)
assert(not missed.primary_pressed and missed.primary_consumed_sequence==4)
assert(not missed.secondary_pressed and missed.secondary_consumed_sequence==9,
    "unhandled secondary click was queued into a later UI frame")
