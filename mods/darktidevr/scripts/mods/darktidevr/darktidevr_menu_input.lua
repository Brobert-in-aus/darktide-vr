-- Adapt XR to the engine's menu input contract. The engine owns hit geometry,
-- clipping, control lifetimes and the input/null-service choice for each view.
local MenuInput = {}
local function null_reference(input)
    local method=input and input.null_service
    return method and method(input)
end
local native_views = {options_view=true,player_character_options_view=true,
    custom_settings_view=true,masteries_overview_view=true,
    mastery_view=true,talent_builder_view=true,broker_stimm_builder_view=true}
-- All additional interactive families in the stock Views registry. Loading,
-- cinematics, blank transitions and the in-world scanner are excluded.
for name in ("system_view news_view cosmetics_inspect_view class_selection_view " ..
    "end_view end_player_view mission_board_view lobby_view main_menu_view " ..
    "barber_vendor_background_view character_appearance_view contracts_background_view " ..
    "contracts_view marks_vendor_view marks_goods_vendor_view credits_vendor_view " ..
    "credits_vendor_background_view main_menu_background_view mission_voting_view " ..
    "social_menu_view social_menu_roster_view training_grounds_view " ..
    "training_grounds_options_view credits_view live_events_view credits_goods_vendor_view " ..
    "cosmetics_vendor_view cosmetics_vendor_background_view havoc_background_view " ..
    "havoc_play_view havoc_reward_presentation_view group_finder_view penance_overview_view " ..
    "report_player_view expedition_view horde_play_view dlc_purchase_view player_survey_view " ..
    "live_event_skulls_guns_progress_view"):gmatch("%S+") do native_views[name] = true end
function MenuInput.native_view(name)
    return type(name) == "string" and
        (native_views[name] == true or name:match("^inventory_") ~= nil)
end
function MenuInput.view_mode(name)
    if MenuInput.native_view(name) or
            (type(name)=="string" and name:match("^crafting_")) then return 5 end
    if name=="store_view" or name=="store_item_detail_view" or
            name=="premium_currency_purchase_view" then return 6 end
    if name=="splash_view" or name=="title_view" or name=="loading_view" or
            name=="mission_intro_view" or name=="video_view" or
            name=="splash_video_view" or name=="cutscene_view" then return 2 end
end

-- Menu hotkeys with a keyboard default and no pointer route (special menus
-- such as the end of mission screen) answer to a fixed controller button,
-- keyed by the action's key alias: E (hotkey_menu_special_1) is Y, Q
-- (hotkey_menu_special_2) is X, the end screen's continue is the right
-- trigger, and Space on the social list is A. B stays back and the triggers
-- stay pointer clicks. Overlap with gameplay bindings does not matter in a
-- menu. darktidevr_controller_prompts.lua labels the same buttons.
MenuInput.menu_buttons = {hotkey_menu_special_1 = "y", hotkey_menu_special_2 = "x",
    continue_end_view = "rt", social_show_list = "a"}

-- Per-button edges for one UI frame. A button held when the owner changes
-- must be released before it presses.
local function sample_buttons(state, buttons, changed)
    local previous = state.buttons or {}
    state.buttons = previous
    local result, active = {}, false
    for id, down in pairs(buttons or {}) do
        local button = previous[id]
        if not button then
            button = {held = false, armed = not down}
            previous[id] = button
        end
        if changed then button.held, button.armed = false, not down end
        local was_held = button.held
        local pressed = down and button.armed and not was_held
        if pressed then button.held = true end
        local released = was_held and not down
        if not down then button.held, button.armed = false, true end
        result[id] = {pressed = pressed, held = button.held, released = released}
        active = active or down or released
    end
    return result, active
end

function MenuInput.sample(state, pointer, frame, owner, width, height, buttons)
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
    local rejection
    if pointer.primary_pressed and not pressed then
        rejection = not valid and "unavailable" or not inside and "outside" or
            changed and "owner_changed" or "release_required"
    end
    if pressed then state.held = true end
    local released = was_held and (not valid or not pointer.primary_down)
    if released then state.held = false end
    if not pointer.primary_down then state.armed = true end
    -- Lost tracking cancels a held press once. Reacquisition while held must
    -- not start a second drag or activate a different control.
    if not valid then state.armed = false end
    -- Keep the secondary lifecycle independent, with the same ownership and
    -- tracking quarantine as primary. A new modal never inherits either hold.
    local secondary_was_held = state.secondary_held == true
    if changed then
        state.secondary_held = false
        state.secondary_armed = not pointer.secondary_down
        secondary_was_held = false
    end
    local secondary_pressed = inside and not changed and state.secondary_armed and
        pointer.secondary_pressed == true
    if secondary_pressed then state.secondary_held = true end
    local secondary_released = secondary_was_held and (not valid or not pointer.secondary_down)
    if secondary_released then state.secondary_held = false end
    if not pointer.secondary_down then state.secondary_armed = true end
    if not valid then state.secondary_armed = false end
    local dx, dy = 0, 0
    if inside then
        local x = pointer.x * width / pointer.source_width
        local y = pointer.y * height / pointer.source_height
        if not changed and state.inside then dx, dy = x-state.x, y-state.y end
        state.x, state.y = x, y
    end
    local retain_position = state.held or released or state.secondary_held or secondary_released
    local button_sample, buttons_active = sample_buttons(state, buttons, changed)
    local sample = {
        override = valid or released or secondary_released or buttons_active,
        buttons = button_sample,
        x = (inside or retain_position) and state.x or -10000,
        y = (inside or retain_position) and state.y or -10000,
        pressed = pressed == true, released = released,
        held = state.held == true,
        secondary_pressed = secondary_pressed == true,
        secondary_released = secondary_released,
        secondary_held = state.secondary_held == true,
        rejection = rejection,
        dx = dx, dy = dy,
        back = valid and not changed and pointer.back_pressed == true,
        scroll = inside and not changed and (pointer.scroll_steps or 0) or 0,
    }
    state.frame, state.owner = frame, owner
    state.generation, state.sample = pointer.transport_generation, sample
    state.inside = inside
    return sample
end

function MenuInput.character_select_readiness(view, input_blocked)
    local buttons = view._widgets_by_name
    local play = buttons and buttons.play_button and buttons.play_button.content
    local blocked = input_blocked or view._input_disabled or
        view._profiles_wait_overlay_active or view._server_migration_element
    local reason = input_blocked and "stock_null_service" or
        view._input_disabled and "view_disabled" or
        view._profiles_wait_overlay_active and "profiles_sync" or
        view._server_migration_element and "server_migration" or "ready"
    local start_ready = not blocked and play and play.visible and
        play.hotspot and not play.hotspot.disabled
    if not blocked and not start_ready then
        reason = view._waiting_on_character and "character_sync" or "start_not_ready"
    end
    return not not (not blocked), not not start_ready, reason
end

local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local desktop_pointer_actions = {"left_pressed", "left_hold", "left_released",
    "right_pressed", "right_hold", "right_released", "middle_pressed", "middle_hold", "middle_released"}

function MenuInput.proxy(source, null_service, sample, vector, read_desktop, width, height)
    if not sample.override then return source end
    -- Stock mouse events need their physical point immediately, including the
    -- release frame; they must not wait for the XR publisher to observe them.
    -- Snapshot the physical desktop point once for this UI frame.
    -- An active XR gesture keeps its target until its release has been routed.
    if not sample.desktop_cursor_checked then
        sample.desktop_cursor_checked = true
        if read_desktop and not sample.held and not sample.released and not sample.pressed and
                not sample.secondary_held and not sample.secondary_released and not sample.secondary_pressed and
                (sample.scroll or 0)==0 then
            local wheel = source:get("scroll_axis")
            local dx = wheel and (wheel.x or wheel[1]) or 0
            local dy = wheel and (wheel.y or wheel[2]) or 0
            local desktop_event = finite(dx) and finite(dy) and (dx~=0 or dy~=0)
            if not desktop_event then
                for _,action in ipairs(desktop_pointer_actions) do
                    if source:get(action)==true then desktop_event=true; break end
                end
            end
            if desktop_event then
                local ok,x,y,w,h,foreground = pcall(read_desktop)
                if ok and foreground==true and finite(x) and finite(y) and finite(w) and finite(h) and
                        finite(width) and finite(height) and w>0 and h>0 and width>0 and height>0 then
                    -- Keep off-window mouse positions outside the canvas so a
                    -- drag/release cannot jump to an unrelated controller hit.
                    sample.desktop_cursor_x, sample.desktop_cursor_y = x*width/w, y*height/h
                end
            end
        end
    end
    local proxy = {}
    function proxy:get(action)
        if action == "cursor" then
            return vector(sample.desktop_cursor_x or sample.x, sample.desktop_cursor_y or sample.y, 0)
        end
        if action == "left_pressed" then return sample.pressed or source:get(action) end
        if action == "left_released" then return sample.released or source:get(action) end
        if action == "left_hold" then return sample.held or source:get(action) end
        if action == "right_pressed" then return sample.secondary_pressed or source:get(action) end
        if action == "right_released" then return sample.secondary_released or source:get(action) end
        if action == "right_hold" then return sample.secondary_held or source:get(action) end
        if action == "scroll_axis" then
            local mouse = source:get(action)
            if not mouse then return vector(0, sample.scroll, 0) end
            return vector(mouse.x or mouse[1], (mouse.y or mouse[2]) + sample.scroll,
                mouse.z or mouse[3])
        end
        if action == "mouse_move" then
            local mouse = source:get(action)
            if mouse then return mouse end
            return vector(sample.dx, sample.dy, 0)
        end
        if action == "back" then return sample.back or source:get(action) end
        -- A menu hotkey answers to its controller button, per the action's
        -- own type (pressed, held or released) on its key alias.
        local rule = source._actions and source._actions[action]
        local button_id = rule and MenuInput.menu_buttons[rule.key_alias]
        local button = button_id and sample.buttons and sample.buttons[button_id]
        if button then
            local down = rule.type == "held" and button.held or
                rule.type == "released" and button.released or
                (rule.type ~= "held" and rule.type ~= "released") and button.pressed
            if down then return true end
        end
        -- XR adds controls to the stock service; mouse buttons and keyboard
        -- confirmation remain available alongside the tracked pointer.
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

function MenuInput.advance_startup(request, view, blocked, t)
    if not request.armed or request.done then return false end
    if request.owner and request.owner ~= view then
        request.done = true
        return false
    end
    request.owner = view
    local _, ready = MenuInput.character_select_readiness(view, blocked)
    local ui = Managers and Managers.ui
    if not ready or view._is_main_menu_open or
            (ui and ui._active_popups and ui._active_popups[1]) then
        request.ready_since = nil
        return false
    end
    request.ready_since = request.ready_since or t
    if t - request.ready_since < 1 then return false end
    local callback = view._widgets_by_name.play_button.content.hotspot.pressed_callback
    if type(callback) ~= "function" then return false end
    -- Consume before invoking stock behavior: never replay after returning to
    -- character select, a callback error, or a deferred state transition.
    request.done = true
    callback()
    return true
end

function MenuInput.install(mod, presentation)
    local state = {}
    local startup = {}
    local files = Mods and Mods.lua and Mods.lua.io
    if files then
        local path = "./../mods/darktidevr/darktidevr_start_character.flag"
        local flag = files.open(path, "r")
        if flag then
            local value = flag:read("*all")
            flag:close()
            local consumed = files.open(path, "w")
            if consumed then
                consumed:write("consumed")
                consumed:close()
                startup.armed = value:match("^start%s*$") ~= nil
            end
        end
    end
    local proxies = setmetatable({}, {__mode="k"})
    presentation.native_menu_input_enabled = true
    presentation.native_menu_view = MenuInput.native_view
    presentation.native_menu_mode = MenuInput.view_mode
    -- Observe stock gates; never bypass backend readiness or replay a press.
    -- Bound logs per view lifetime and to the first ten seconds after update.
    local readiness = setmetatable({}, {__mode="k"})
    mod:hook_safe("MainMenuView", "update", function(self, dt, t, input)
        local observed, reference = pcall(null_reference,input)
        local null = not input or not observed or input == reference
        if MenuInput.advance_startup(startup, self, null, t) then
            mod:info("DARKTIDEVR_STARTUP character_select=start_requested source=one_shot")
        end
        local current = readiness[self]
        if not current then current = {start=t, samples=0}; readiness[self] = current end
        if current.samples >= 16 or t - current.start > 10 then return end
        local list_ready, start_ready, reason = MenuInput.character_select_readiness(self, null)
        local signature = reason .. tostring(list_ready) .. tostring(start_ready)
        if current.signature == signature then return end
        current.signature, current.samples = signature, current.samples + 1
        mod:info("DARKTIDEVR_MENU_READINESS view=main_menu elapsed=%.3f list_input=%s start_ready=%s reason=%s",
            t - current.start, tostring(list_ready), tostring(start_ready), reason)
    end)
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
    -- Both regular views and constant elements (confirmation popups, etc.)
    -- obtain input here. The view handler alone does not cover modal dialogs.
    local function route_service(func, self, ...)
        local source, null_service, gamepad = func(self, ...)
        -- One shared input_service hook: DMF replaces duplicate hooks owned by
        -- this mod. Gameplay hotkeys retain stock ownership and return values.
        if source~=null_service and presentation.gameplay_ui then
            source=presentation.gameplay_ui.route_hotkey_input(source,self,...)
        end
        -- The editor uses mode 5 for desktop rendering, but its controls need
        -- the complete mouse service. Real menus/popups retain the XR route.
        local hud = presentation.hud_panel
        local handler = self._view_handler
        local desktop_editor = hud and hud.editing() and
            not (self._active_popups and self._active_popups[1]) and
            not (handler and (handler._num_active_views or 0) > 0)
        if not presentation.native_menu_input_enabled or
                (presentation.mode ~= 5 and presentation.mode ~= 6) or desktop_editor then
            state = {}
            return source, null_service, gamepad
        end
        -- Respect ImGui, disabled input, and the view handler's own suppression.
        if source == null_service then
            -- A modal/ImGui/input block may leave the same view owner in place.
            -- Retire its XR gesture without reading blocked input. The first
            -- recovered sample then drains queued edges and requires release
            -- before another hold; it cannot replay clicks made while blocked.
            state = {}
            return source, null_service, gamepad
        end
        if proxies[source] then return source, null_service, false end
        local pointer = presentation.read_menu_pointer()
        local handler = self._view_handler
        local owner = handler and handler._active_views_array and
            handler._active_views_array[handler._num_active_views]
        local data = owner and handler._active_views_data and handler._active_views_data[owner]
        owner = (self._active_popups and self._active_popups[1]) or
            (data and data.instance) or owner
        local buttons = presentation.read_menu_buttons and presentation.read_menu_buttons() or nil
        local sample = MenuInput.sample(state, pointer, pointer.frame_id or 0, owner,
            RESOLUTION_LOOKUP.width, RESOLUTION_LOOKUP.height, buttons)
        if pointer.primary_pressed and sample.rejection then
            mod:info("DARKTIDEVR_MENU_INPUT rejected frame=%d reason=%s",
                pointer.frame_id or 0, sample.rejection)
        end
        -- The immutable frame sample serves every stock update/draw query.
        -- Drain transport counters now so scroll/back cannot repeat next frame
        -- merely because the per-view legacy handlers no longer consume them.
        if pointer.primary_pressed then presentation.consume_menu_primary(pointer) end
        if pointer.secondary_pressed then presentation.consume_menu_secondary(pointer) end
        if pointer.back_pressed then presentation.consume_menu_back(pointer) end
        if (pointer.scroll_steps or 0) ~= 0 then presentation.consume_menu_scroll(pointer) end
        local proxy = MenuInput.proxy(source, null_service, sample, Vector3,
            presentation.read_desktop_mirror, RESOLUTION_LOOKUP.width, RESOLUTION_LOOKUP.height)
        if proxy ~= source then proxies[proxy] = true end
        if sample.override then gamepad = false end
        return proxy, null_service, gamepad
    end
    mod:hook("UIManager", "input_service", route_service)
    -- Some mission-board, live-event and constant-element controls fetch View
    -- input directly. Ingame is delegated only to an explicitly scoped HUD
    -- adapter; chat and ImGui services retain their stock input.
    mod:hook("InputManager", "get_input_service", function(func, self, name, ...)
        local source = func(self, name, ...)
        if presentation.gameplay_ui then
            source=presentation.gameplay_ui.route_ingame_input(source,name)
        end
        if name ~= "View" or not Managers or not Managers.ui then return source end
        local observed, null_service = pcall(null_reference,source)
        if not observed or not null_service then
            -- Stock already returned this service. An optional XR eligibility
            -- query must not turn that return into an error during retirement.
            state = {}
            return source
        end
        local proxy = route_service(function()
            return source, null_service, false
        end, Managers.ui)
        return proxy
    end)
end

return MenuInput
