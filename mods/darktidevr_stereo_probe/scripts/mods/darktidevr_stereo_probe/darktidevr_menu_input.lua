-- Adapt XR to the engine's menu input contract. The engine owns hit geometry,
-- clipping, control lifetimes and the input/null-service choice for each view.
local MenuInput = {}
local native_views = {options_view=true,player_character_options_view=true,
    custom_settings_view=true,masteries_overview_view=true,
    mastery_view=true,talent_builder_view=true,broker_stimm_builder_view=true}
function MenuInput.native_view(name)
    return type(name) == "string" and
        (native_views[name] == true or name:match("^inventory_") ~= nil)
end

function MenuInput.sample(state, pointer, frame, owner, width, height)
    if state.frame == frame and state.owner == owner then return state.sample end
    local changed = state.owner ~= owner or state.generation ~= pointer.transport_generation
    local was_held = state.held == true
    if changed then
        state.held = false
        state.armed = not pointer.primary_down
        was_held = false
    end
    local valid = pointer.available and pointer.source_width and pointer.source_width > 0 and
        pointer.source_height and pointer.source_height > 0 and width > 0 and height > 0
    local inside = valid and pointer.active
    local pressed = inside and not changed and state.armed and pointer.primary_pressed == true
    if pressed then state.held = true end
    local released = was_held and (not valid or not pointer.primary_down)
    if released then state.held = false end
    if not pointer.primary_down then state.armed = true end
    -- Lost tracking cancels a held press once. Reacquisition while held must
    -- not start a second drag or activate a different control.
    if not valid then state.armed = false end
    local dx, dy = 0, 0
    if inside then
        local x = pointer.x * width / pointer.source_width
        local y = pointer.y * height / pointer.source_height
        if not changed and state.inside then dx, dy = x-state.x, y-state.y end
        state.x, state.y = x, y
    end
    local retain_position = state.held or released
    local sample = {
        override = valid or released,
        x = (inside or retain_position) and state.x or -10000,
        y = (inside or retain_position) and state.y or -10000,
        pressed = pressed == true, released = released,
        held = state.held == true,
        dx = dx, dy = dy,
        back = valid and not changed and pointer.back_pressed == true,
        scroll = inside and not changed and (pointer.scroll_steps or 0) or 0,
    }
    state.frame, state.owner = frame, owner
    state.generation, state.sample = pointer.transport_generation, sample
    state.inside = inside
    return sample
end

function MenuInput.proxy(source, null_service, sample, vector)
    if not sample.override then return source end
    local proxy = {}
    function proxy:get(action)
        if action == "cursor" then return vector(sample.x, sample.y, 0) end
        if action == "left_pressed" then return sample.pressed end
        if action == "left_released" then return sample.released end
        if action == "left_hold" then return sample.held end
        if action == "scroll_axis" then return vector(0, sample.scroll, 0) end
        if action == "mouse_move" then return vector(sample.dx, sample.dy, 0) end
        if action == "back" then return sample.back or source:get(action) end
        -- One pointer owner: a stationary OS cursor or confirm button must not
        -- activate a different control behind the tracked ray.
        if action:match("^right_") or action:match("^middle_") or
                action:match("^confirm_") then return false end
        return source:get(action)
    end
    function proxy:null_service() return null_service end
    function proxy:get_with_filters(action, locked)
        local rule = source._actions and source._actions[action]
        local aliases = rule and source._aliases and source._aliases[rule.key_alias]
        for input in pairs(locked or {}) do
            for _, alias in ipairs(aliases or {}) do
                if input == alias then return source:get_default(action) end
            end
        end
        return self:get(action)
    end
    return setmetatable(proxy, {__index=function(_, key)
        local value = source[key]
        if type(value) == "function" then
            return function(_, ...) return value(source, ...) end
        end
        return value
    end})
end

function MenuInput.install(mod, presentation)
    local state = {}
    presentation.native_menu_input_enabled = true
    presentation.native_menu_view = MenuInput.native_view
    function presentation.using_native_menu_input()
        return presentation.native_menu_input_enabled and
            (presentation.mode == 5 or presentation.mode == 6)
    end
    function presentation.hook_legacy_menu(class, method, callback)
        mod:hook(class, method, function(func, ...)
            if presentation.using_native_menu_input() then return func(...) end
            return callback(func, ...)
        end)
    end
    local inert = {available=false,active=false,primary_pressed=false,
        back_pressed=false,scroll_steps=0,primary_down=false}
    function presentation.read_legacy_menu_pointer()
        if presentation.native_menu_input_enabled and
                (presentation.mode == 5 or presentation.mode == 6) then return inert end
        return presentation.read_menu_pointer()
    end
    mod:hook("UIViewHandler", "_get_input", function(func, self)
        local source, null_service, gamepad = func(self)
        if not presentation.native_menu_input_enabled or
                (presentation.mode ~= 5 and presentation.mode ~= 6) then
            state = {}
            return source, null_service, gamepad
        end
        -- Respect ImGui, disabled input, and the view handler's own suppression.
        if source == null_service then return source, null_service, gamepad end
        local pointer = presentation.read_menu_pointer()
        local owner = self._active_views_array and self._active_views_array[self._num_active_views]
        local data = owner and self._active_views_data and self._active_views_data[owner]
        owner = data and data.instance or owner
        local sample = MenuInput.sample(state, pointer, pointer.frame_id or 0, owner,
            RESOLUTION_LOOKUP.width, RESOLUTION_LOOKUP.height)
        -- The immutable frame sample serves every stock update/draw query.
        -- Drain transport counters now so scroll/back cannot repeat next frame
        -- merely because the per-view legacy handlers no longer consume them.
        if pointer.primary_pressed then presentation.consume_menu_primary(pointer) end
        if pointer.back_pressed then presentation.consume_menu_back(pointer) end
        if (pointer.scroll_steps or 0) ~= 0 then presentation.consume_menu_scroll(pointer) end
        local proxy = MenuInput.proxy(source, null_service, sample, Vector3)
        if sample.override then gamepad = false end
        return proxy, null_service, gamepad
    end)
end

return MenuInput
