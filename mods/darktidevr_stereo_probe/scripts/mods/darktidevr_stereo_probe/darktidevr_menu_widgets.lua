-- Widget geometry and XR input state, independent of view hooks.
local widgets = {}

function widgets.install(mod, presentation)
function presentation.begin_menu_pointer_frame(pointer)
    pointer.frame_id = (pointer.frame_id or 0) + 1
    -- A click that missed all controls is spent, not queued for later hover.
    pointer.primary_consumed_sequence = pointer.primary_press_sequence
    pointer.primary_pressed = false
    pointer.frame_sampled = false
end

function presentation.claim_menu_pointer_sample(pointer)
    if pointer.frame_sampled then
        return false
    end
    pointer.frame_sampled = true
    return true
end

function presentation.aligned_pass_origin(base_left, base_top, base_width,
        base_height, pass_style)
    if not pass_style then
        return base_left, base_top
    end
    local size = pass_style.size or { base_width, base_height }
    local width = size[1] or base_width
    local height = size[2] or base_height
    local left = base_left
    local top = base_top
    if pass_style.horizontal_alignment == "right" then
        left = left + base_width - width
    elseif pass_style.horizontal_alignment == "center" then
        left = left + (base_width - width) * 0.5
    end
    if pass_style.vertical_alignment == "bottom" then
        top = top + base_height - height
    elseif pass_style.vertical_alignment == "center" then
        top = top + (base_height - height) * 0.5
    end
    local offset = pass_style.offset or { 0, 0, 0 }
    return left + (offset[1] or 0), top + (offset[2] or 0)
end

function presentation.widget_contains_menu_pointer(instance, widget, pointer,
        pass_style)
    if not pointer or not pointer.active or not instance or not instance._ui_scenegraph or
            not widget then
        return false, nil
    end
    local scenegraph_id = widget.scenegraph_id
    local scene = scenegraph_id and instance._ui_scenegraph[scenegraph_id]
    local world = scene and scene.world_position
    local offset = widget.offset or { 0, 0, 0 }
    local base_size = widget.content and widget.content.size
    if not base_size and widget.style and widget.style.hotspot then
        base_size = widget.style.hotspot.size
    end
    base_size = base_size or (scene and scene.size)
    local size = pass_style and pass_style.size or base_size
    if not world or not base_size or not base_size[1] or not base_size[2] or
            not size or not size[1] or not size[2] then
        return false, nil
    end
    local scale = RESOLUTION_LOOKUP.scale or 1
    -- Capture pixels can be smaller than the authored UI canvas (for example
    -- 1024x614 desktop capture versus 1280x768 character-select layout).
    -- Explicit vendor projection already names its portrait layout extent.
    local resolution_width = pointer.layout_width or RESOLUTION_LOOKUP.width
    local resolution_height = pointer.layout_height or RESOLUTION_LOOKUP.height
    if not pointer.source_width or pointer.source_width <= 0 or
            not pointer.source_height or pointer.source_height <= 0 or
            not resolution_width or not resolution_height then
        return false, nil
    end
    local pointer_x = pointer.x * resolution_width / pointer.source_width
    local pointer_y = pointer.y * resolution_height / pointer.source_height
    local base_left = world[1] + (offset[1] or 0)
    local base_top = world[2] + (offset[2] or 0)
    local left, top = presentation.aligned_pass_origin(
        base_left, base_top, base_size[1], base_size[2], pass_style)
    left = left * scale
    top = top * scale
    local width = size[1] * scale
    local height = size[2] * scale
    return pointer_x >= left and pointer_x <= left + width and
        pointer_y >= top and pointer_y <= top + height,
        {
            pointer_x = pointer_x,
            pointer_y = pointer_y,
            left = left,
            top = top,
            width = width,
            height = height,
        }
end

function presentation.is_dropdown_widget(widget)
    local content = widget and widget.content
    return widget and (widget.type == "dropdown" or
        (content and type(content.options) == "table" and
            content.option_hotspot_1 ~= nil))
end

function presentation.is_slider_widget(widget)
    local content = widget and widget.content
    return content and type(content.slider_value) == "number" and
        type(content.entry) == "table"
end

function presentation.widget_hotspot_entries(widget, include_dropdown_options)
    local content = widget and widget.content
    if not content then
        return {}
    end
    local entries = {}
    local seen = {}
    local authored = {}
    local passes = widget.passes or {}
    for i = 1, #passes do
        local pass = passes[i]
        if pass.pass_type == "hotspot" then
            local content_id = pass.content_id or "hotspot"
            local hotspot = pass.content_id and content[pass.content_id] or
                content.hotspot or content
            if type(hotspot) == "table" then
                authored[hotspot] = true
            end
            local style_id = pass.style_id or content_id
            local style = widget.style and widget.style[style_id] or pass.style
            local visible = not style or style.visible ~= false
            if visible and type(pass.visibility_function) == "function" then
                local ok, result = pcall(
                    pass.visibility_function, content, style)
                visible = ok and result and true or false
            end
            if visible and presentation.is_dropdown_widget(widget) and
                    string.match(content_id, "^option_hotspot_%d+$") then
                visible = include_dropdown_options and
                    content.exclusive_focus and true or false
            end
            if visible and type(hotspot) == "table" and not seen[hotspot] then
                seen[hotspot] = true
                entries[#entries + 1] = {
                    hotspot = hotspot,
                    content_id = content_id,
                    style_id = style_id,
                    style = style,
                }
            end
        end
    end
    -- DMF's dropdown blueprint materializes option_hotspot_N and the matching
    -- styles directly on the widget. In the current runtime build those
    -- entries are not retained in widget.passes, even though the renderer uses
    -- them and the blueprint update consumes their on_pressed state. Enumerate
    -- the authored fields themselves so the visible overlay, rather than the
    -- collapsed rows behind it, owns XR input.
    if include_dropdown_options and presentation.is_dropdown_widget(widget) and
            content.exclusive_focus then
        local count = tonumber(content.num_visible_options) or 0
        for i = 1, count do
            local content_id = "option_hotspot_" .. tostring(i)
            local hotspot = content[content_id]
            local style = widget.style and widget.style[content_id]
            if type(hotspot) == "table" and style and
                    style.visible ~= false and not seen[hotspot] and
                    not authored[hotspot] then
                seen[hotspot] = true
                entries[#entries + 1] = {
                    hotspot = hotspot,
                    content_id = content_id,
                    style_id = content_id,
                    style = style,
                }
            end
        end
    end
    local fallback_style = widget.style and widget.style.hotspot
    if type(content.hotspot) == "table" and not authored[content.hotspot] and
            not seen[content.hotspot] and
            (not fallback_style or fallback_style.visible ~= false) then
        entries[#entries + 1] = {
            hotspot = content.hotspot,
            content_id = "hotspot",
            style_id = "hotspot",
            style = widget.style and widget.style.hotspot,
        }
    end
    return entries
end

function presentation.widget_hotspot(widget)
    local content = widget and widget.content
    if content and content.hotspot then
        return content.hotspot
    end
    local entries = presentation.widget_hotspot_entries(widget)
    return entries[1] and entries[1].hotspot or nil
end

function presentation.clear_widget_hotspot_forces(widget)
    -- Clear even stale authored dropdown option fields. They are deliberately
    -- excluded from normal hit-testing unless the owning OptionsView says this
    -- is its one authoritative selected widget.
    local content = widget and widget.content
    if not content then
        return
    end
    local function clear(hotspot)
        if type(hotspot) == "table" then
            hotspot.force_hover = false
            hotspot.force_input_pressed = false
        end
    end
    clear(content.hotspot)
    for key, value in pairs(content) do
        if type(key) == "string" and key:match("^option_hotspot_%d+$") then
            clear(value)
        end
    end
    for _, pass in ipairs(widget.passes or {}) do
        if pass.pass_type == "hotspot" then
            clear(pass.content_id and content[pass.content_id] or
                content.hotspot or content)
        end
    end
end

function presentation.widget_hotspot_at_pointer(instance, widget, pointer,
        include_dropdown_options)
    local entries = presentation.widget_hotspot_entries(
        widget, include_dropdown_options)
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if not entry.hotspot.disabled then
            local hit = presentation.widget_contains_menu_pointer(
                instance, widget, pointer, entry.style)
            if hit then
                return entry
            end
        end
    end
    return nil
end

function presentation.log_focused_dropdown_geometry(instance, widget, pointer)
    if not pointer.primary_pressed or not widget or
            not presentation.is_dropdown_widget(widget) or
            not widget.content or not widget.content.exclusive_focus then
        return
    end
    local entries = presentation.widget_hotspot_entries(widget, true)
    for i = 1, #entries do
        local entry = entries[i]
        local hit, geometry = presentation.widget_contains_menu_pointer(
            instance, widget, pointer, entry.style)
        if geometry then
            mod:info(
                "DARKTIDEVR_MENU_INPUT dropdown_geometry widget=%s hotspot=%s hit=%s pointer=%.1f,%.1f bounds=%.1f,%.1f,%.1f,%.1f",
                tostring(widget.name),
                tostring(entry.content_id),
                tostring(hit),
                geometry.pointer_x,
                geometry.pointer_y,
                geometry.left,
                geometry.top,
                geometry.width,
                geometry.height)
        end
    end
end

function presentation.log_slider_geometry(instance, widget, pointer)
    if not pointer.primary_pressed or
            not presentation.is_slider_widget(widget) then
        return
    end

    local entries = {}
    local seen = {}
    local passes = widget.passes or {}
    for i = 1, #passes do
        local pass = passes[i]
        local style_id = pass.style_id or pass.content_id
        local style_name = string.lower(tostring(style_id or ""))
        if (string.find(style_name, "slider", 1, true) or
                string.find(style_name, "hotspot", 1, true)) and
                not seen[style_name] then
            seen[style_name] = true
            local style = widget.style and widget.style[style_id] or pass.style
            local hit, geometry = presentation.widget_contains_menu_pointer(
                instance, widget, pointer, style)
            if geometry then
                entries[#entries + 1] = string.format(
                    "%s:%s:%.1f,%.1f,%.1f,%.1f",
                    tostring(style_id),
                    hit and "hit" or "miss",
                    geometry.left,
                    geometry.top,
                    geometry.width,
                    geometry.height)
            end
        end
    end

    mod:info(
        "DARKTIDEVR_MENU_INPUT slider_geometry widget=%s type=%s value=%.4f step=%s pointer=%d,%d passes=%s",
        tostring(widget.name),
        tostring(widget.type),
        widget.content.slider_value,
        tostring(widget.content.step_size),
        pointer.x,
        pointer.y,
        #entries > 0 and table.concat(entries, "|") or "none")
end

function presentation.slider_track_geometry(instance, widget, pointer)
    local style = widget and widget.style
    if not style then
        return false, nil
    end
    local track_style = style.track_hotspot or
        style.slider_track_background
    if not track_style then
        return false, nil
    end
    return presentation.widget_contains_menu_pointer(
        instance, widget, pointer, track_style)
end

function presentation.set_slider_from_pointer(instance, widget, pointer)
    local _, geometry = presentation.slider_track_geometry(
        instance, widget, pointer)
    if not geometry or geometry.width <= 0 then
        return false
    end
    local value = math.clamp(
        (geometry.pointer_x - geometry.left) / geometry.width, 0, 1)
    local step = widget.content.step_size
    if type(step) == "number" and step > 0 then
        value = math.clamp(
            math.floor(value / step + 0.5) * step, 0, 1)
    end
    widget.content.slider_value = value
    return true, value
end

function presentation.update_slider_drag(instance, pointer)
    local drag = presentation.slider_drag
    if not drag or drag.instance ~= instance then
        return false
    end
    local widget = drag.widget
    if not pointer.available then
        -- A missing transport sample is not a release. Preserve the last XR
        -- value until a fresh sample explicitly reports button-up.
        widget.content.drag_active = true
        widget.content.slider_value = drag.value
        return true
    end
    if pointer.primary_down then
        widget.content.drag_active = true
        if pointer.active then
            local updated, value = presentation.set_slider_from_pointer(
                instance, widget, pointer)
            if updated then
                drag.value = value
            end
        else
            widget.content.slider_value = drag.value
        end
        return true
    end
    -- Engine updates between the two eye draws may resynchronize content from
    -- the old setting. Restore the last XR-authored value before releasing so
    -- the blueprint's drag_previously_active path commits that value.
    widget.content.slider_value = drag.value
    widget.content.drag_active = false
    mod:info(
        "DARKTIDEVR_MENU_INPUT slider_drag_end widget=%s value=%.4f sequence=%d",
        tostring(widget.name),
        drag.value,
        pointer.last_sequence)
    presentation.slider_drag = nil
    return false
end

function presentation.begin_slider_drag(instance, widget, pointer)
    local hit = presentation.slider_track_geometry(instance, widget, pointer)
    if not hit then
        return false
    end
    local updated, value = presentation.set_slider_from_pointer(
        instance, widget, pointer)
    if not updated then
        return false
    end
    widget.content.drag_active = true
    presentation.slider_drag = {
        instance = instance,
        widget = widget,
        value = value,
    }
    mod:info(
        "DARKTIDEVR_MENU_INPUT slider_drag_begin widget=%s value=%.4f sequence=%d",
        tostring(widget.name), value, pointer.last_sequence)
    return true
end

end

return widgets
