-- Experimental keyboard and mouse play in VR. The mouse moves the aim, shown by
-- the world-depth reticle, inside a keyhole around the view. Past its edge the
-- mouse turns the camera; the head pushes the aim instead, so looking around
-- never turns the view. The HUD keeps its own head follow. Aim is held in
-- Darktide's yaw/pitch convention: yaw grows counter-clockwise, pitch is
-- signed and grows upward.
local KeyboardMouse = {}
local TAU = math.pi*2
KeyboardMouse.max_camera_pitch = math.rad(80)

local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function wrap(angle) return (angle+math.pi)%TAU-math.pi end
local function clamp(value, low, high) return math.max(low, math.min(high, value)) end
KeyboardMouse.wrap = wrap

-- With a KeyboardMouseOn file present the toggle's own title says the file
-- holds the mode on, so a forgotten rename does not look like a broken toggle.
function KeyboardMouse.widgets(switch_file)
    local lua = switch_file == nil and rawget(_G, "Mods") and Mods.lua
    if lua then switch_file = KeyboardMouse.find_switch(KeyboardMouse.windows_finder(lua.ffi), lua.io) end
    local locked = switch_file and switch_file ~= false
    return {setting_id="keyboard_mouse_mode",type="checkbox",default_value=false,
        title=locked and "keyboard_mouse_mode_switch_on" or nil,
        tooltip=locked and "keyboard_mouse_mode_switch_on_description" or nil,sub_widgets={
        {setting_id="keyboard_mouse_recenter_keybind",type="keybind",default_value={"z"},
            keybind_trigger="pressed",keybind_type="function_call",function_name="recenter_vr_view"},
        {setting_id="keyboard_mouse_disable_controllers",type="checkbox",default_value=true},
        {setting_id="keyboard_mouse_horizontal_only",type="checkbox",default_value=true},
        {setting_id="keyboard_mouse_deadzone",type="numeric",default_value=15,range={0,40},
            decimals_number=0,step_size_value=1},
    }}
end

-- Controllers are ignored only inside keyboard and mouse mode, and only while
-- its Disable controllers option is on. Otherwise both inputs simply add up.
function KeyboardMouse.controllers_disabled(get, forced)
    return (forced == true or get("keyboard_mouse_mode") == true) and
        get("keyboard_mouse_disable_controllers") ~= false
end

-- Out-of-game switch for a headset with no controllers to reach the in-game
-- toggle: the mod folder ships an empty KeyboardMouseOff, and renaming it so
-- its name contains KeyboardMouseOn (any extension, any case) holds this mode on
-- at every launch, with Disable controllers as set (on by default). Renaming it
-- back returns to the in-game toggle, which the file never changes.
KeyboardMouse.switch_pattern = "..\\mods\\darktidevr\\*KeyboardMouseOn*"
-- Names tried when the directory search is unavailable, e.g. without FFI.
KeyboardMouse.switch_names = {"./../mods/darktidevr/KeyboardMouseOn",
    "./../mods/darktidevr/KeyboardMouseOn.txt"}

-- The Lua io sandbox cannot list a folder; Windows can match the name.
function KeyboardMouse.windows_finder(ffi)
    if not ffi then return nil end
    local declared = pcall(ffi.cdef, [[
        typedef struct {
            unsigned long attributes;
            unsigned long times[6];
            unsigned long size_high, size_low, reserved0, reserved1;
            char name[260];
            char alternate[14];
        } darktidevr_find_data;
        void* FindFirstFileA(const char* pattern, darktidevr_find_data* data);
        int FindClose(void* handle);
    ]])
    local ok, kernel32 = pcall(ffi.load, "kernel32")
    if not ok or not kernel32 then return nil end
    return function(pattern)
        local data = ffi.new("darktidevr_find_data")
        local handle = kernel32.FindFirstFileA(pattern, data)
        if handle == nil or tonumber(ffi.cast("intptr_t", handle)) == -1 then return nil end
        kernel32.FindClose(handle)
        return ffi.string(data.name)
    end, declared
end

-- Returns the matching file name, or nil.
function KeyboardMouse.find_switch(finder, files)
    if finder then
        local ok, name = pcall(finder, KeyboardMouse.switch_pattern)
        if ok then return name end
    end
    for _, path in ipairs(KeyboardMouse.switch_names) do
        local file = files and files.open(path, "r")
        if file then file:close(); return path:match("[^/]+$") end
    end
end

-- Melee direction: the swing moves the way the cursor is moving when the
-- attack starts. dx/dy is recent mouse movement in view space (right, up).
-- authored is the weapon's unrolled first swing direction on the same axes and
-- sign says which way input roll turns it (+1 or -1). Returns the 45-degree
-- input roll, or 0 (the stock swing) when the mouse is not moving.
KeyboardMouse.melee_motion_window = 0.12
KeyboardMouse.melee_min_motion = math.rad(0.5)
function KeyboardMouse.melee_roll(dx, dy, authored, sign)
    if not finite(dx) or not finite(dy) or not finite(authored) or (sign ~= 1 and sign ~= -1) or
            dx*dx+dy*dy < KeyboardMouse.melee_min_motion^2 then return 0 end
    local step = math.pi/4
    local roll = sign*wrap(math.atan2(dy, dx)-authored)
    return (math.floor(roll/step+0.5)*step)%TAU
end

-- The requested swing direction in the headset's frame (right, up), where
-- left-to-right is 0 degrees and bottom-to-top 90. A moving cursor gives its
-- own direction; a still one swings from the reticle's place in the view
-- toward the view centre. rx/ry is the reticle's offset from that centre.
-- Returns nil when neither is measurable: the stock swing.
function KeyboardMouse.melee_direction(dx, dy, rx, ry)
    local min = KeyboardMouse.melee_min_motion
    if finite(dx) and finite(dy) and dx*dx+dy*dy >= min*min then return dx, dy end
    if finite(rx) and finite(ry) and rx*rx+ry*ry >= min*min then return -rx, -ry end
    return nil
end

-- The unrolled swing direction and roll sign from two sampled swings, each
-- given as its tip's start-to-end movement on the view's right/up axes.
function KeyboardMouse.swing_basis(zero_right, zero_up, rolled_right, rolled_up)
    if not finite(zero_right) or not finite(zero_up) or not finite(rolled_right) or not finite(rolled_up) or
            zero_right*zero_right+zero_up*zero_up < 1e-8 or rolled_right*rolled_right+rolled_up*rolled_up < 1e-8 then
        return nil
    end
    local authored = math.atan2(zero_up, zero_right)
    local turned = wrap(math.atan2(rolled_up, rolled_right)-authored)
    if math.abs(turned) < math.rad(10) then return nil end
    return authored, turned > 0 and 1 or -1
end

-- With controllers enabled, keyboard or mouse use suppresses controller aim
-- and hand tracking until this many seconds pass with neither, so a controller
-- lying on the desk cannot take the aim while the mouse is in use.
KeyboardMouse.controller_cooldown = 3
-- Metres the animated first-person hands are moved forward and down.
KeyboardMouse.hand_forward = 0.10
KeyboardMouse.hand_down = 0.10

-- Whether a stock input device is a keyboard or mouse in use this frame: a
-- press, a held button, or mouse or wheel movement.
function KeyboardMouse.device_activity(device)
    local kind = device and device.device_type
    if kind ~= "keyboard" and kind ~= "mouse" then return false end
    local raw = device._raw_device
    if not raw or (raw.active and not raw.active()) then return false end
    if raw.any_pressed() then return true end
    for i = 0, raw.num_buttons()-1 do
        if raw.button(i) > 0 then return true end
    end
    if kind == "mouse" then
        for _, name in ipairs({"mouse", "wheel"}) do
            local index = raw.axis_index(name)
            if index and Vector3.length_squared(raw.axis(index)) > 0 then return true end
        end
    end
    return false
end

function KeyboardMouse.options(get)
    local deadzone = get("keyboard_mouse_deadzone")
    if not finite(deadzone) then deadzone = 15 end
    return {deadzone=math.rad(clamp(deadzone, 0, 40)),
        horizontal_only=get("keyboard_mouse_horizontal_only") ~= false}
end

function KeyboardMouse.reset(state)
    state.aim_yaw, state.aim_pitch, state.camera_pitch = nil, nil, 0
    state.written_yaw, state.written_pitch = nil, nil
end

-- One aim update against the rendered view. Returns the camera yaw and pitch
-- to add; the caller applies them to the scene anchor before the next view.
-- Head movement first drags the aim to the keyhole edge, then the mouse delta
-- moves it and any excess beyond the edge becomes camera motion. With
-- horizontal-only mouselook the excess pitch is discarded: the aim stops at
-- the edge and the head looks up and down.
function KeyboardMouse.step(state, head_yaw, head_pitch, mouse_yaw, mouse_pitch, options, min_pitch, max_pitch)
    if not finite(head_yaw) or not finite(head_pitch) then return 0, 0 end
    mouse_yaw = finite(mouse_yaw) and mouse_yaw or 0
    mouse_pitch = finite(mouse_pitch) and mouse_pitch or 0
    min_pitch = finite(min_pitch) and min_pitch or -math.rad(89)
    max_pitch = finite(max_pitch) and max_pitch or math.rad(89)
    local deadzone = options and finite(options.deadzone) and math.max(0, options.deadzone) or math.rad(15)
    state.camera_pitch = finite(state.camera_pitch) and state.camera_pitch or 0
    -- Switching to horizontal-only levels a view tilted by earlier mouselook.
    if options and options.horizontal_only then state.camera_pitch = 0 end
    if not finite(state.aim_yaw) or not finite(state.aim_pitch) then
        state.aim_yaw, state.aim_pitch = wrap(head_yaw), clamp(head_pitch, min_pitch, max_pitch)
        return 0, 0
    end
    local yaw_offset = clamp(wrap(state.aim_yaw-head_yaw), -deadzone, deadzone)+mouse_yaw
    local yaw_turn = 0
    if yaw_offset > deadzone then yaw_turn, yaw_offset = yaw_offset-deadzone, deadzone
    elseif yaw_offset < -deadzone then yaw_turn, yaw_offset = yaw_offset+deadzone, -deadzone end
    local pitch_offset = clamp(state.aim_pitch-head_pitch, -deadzone, deadzone)
    -- The game's pitch limits bound the aim before the keyhole decides whether
    -- the camera moves, so pushing against a limit cannot tilt the view.
    pitch_offset = clamp(head_pitch+pitch_offset+mouse_pitch, min_pitch, max_pitch)-head_pitch
    local pitch_turn = 0
    local excess = pitch_offset > deadzone and pitch_offset-deadzone or
        pitch_offset < -deadzone and pitch_offset+deadzone or 0
    if excess ~= 0 then
        pitch_offset = pitch_offset-excess
        if not (options and options.horizontal_only) then
            local camera = clamp(state.camera_pitch+excess, -KeyboardMouse.max_camera_pitch,
                KeyboardMouse.max_camera_pitch)
            pitch_turn, state.camera_pitch = camera-state.camera_pitch, camera
        end
    end
    state.aim_yaw = wrap(head_yaw+yaw_turn+yaw_offset)
    state.aim_pitch = clamp(head_pitch+pitch_turn+pitch_offset, min_pitch, max_pitch)
    return yaw_turn, pitch_turn
end

-- Recentre keeps the aim where it is in the world and turns the scene so the
-- current view looks along it; any mouse camera pitch is levelled.
function KeyboardMouse.recenter(state, head_yaw)
    state.camera_pitch = 0
    if not finite(state.aim_yaw) or not finite(head_yaw) then return 0 end
    return wrap(state.aim_yaw-head_yaw)
end

-- DMF writes settings to disk only on a state change or a normal exit; a
-- force-quit would lose the input choice, so flush it at once.
local function save_settings()
    local dmf = rawget(_G, "get_mod") and get_mod("dmf")
    if dmf and dmf.save_unsaved_settings_to_file then pcall(dmf.save_unsaved_settings_to_file) end
end

-- At launch, a KeyboardMouseOn file holds the mode on for the session. It is an
-- override, never saved: once the file is renamed back, the next launch uses
-- the player's own saved setting again, so a controller player is never left
-- with controllers disabled by a mode the file alone had turned on. Disable
-- controllers stays the player's choice; it defaults to on.
function KeyboardMouse.detect_switch(mod, finder, files)
    local name = KeyboardMouse.find_switch(finder, files)
    if name and mod.info then
        mod:info("DARKTIDEVR_KBM switch_file=%s mode=keyboard_mouse controllers_disabled=%s saved_mode=%s", name,
            tostring(mod:get("keyboard_mouse_disable_controllers") ~= false),
            tostring(mod:get("keyboard_mouse_mode") == true))
    end
    return name
end

function KeyboardMouse.install(mod, finder)
    local api = {state={camera_pitch=0}, recenter_requests=0,
        roll_for=KeyboardMouse.melee_roll,
        melee_direction=KeyboardMouse.melee_direction,
        swing_basis=KeyboardMouse.swing_basis,
        controller_cooldown=KeyboardMouse.controller_cooldown,
        hand_forward=KeyboardMouse.hand_forward, hand_down=KeyboardMouse.hand_down}
    local state = api.state
    local lua = rawget(_G, "Mods") and Mods.lua
    api.switch_file = KeyboardMouse.detect_switch(mod,
        finder or KeyboardMouse.windows_finder(lua and lua.ffi), lua and lua.io)
    function api.enabled() return api.switch_file ~= nil or mod:get("keyboard_mouse_mode") == true end
    function api.controllers_disabled()
        return KeyboardMouse.controllers_disabled(function(key) return mod:get(key) end,
            api.switch_file ~= nil)
    end
    function api.options() return KeyboardMouse.options(function(key) return mod:get(key) end) end
    function api.reset(reason)
        KeyboardMouse.reset(state)
        state.owner, state.t, state.live_t = nil, nil, nil
        if reason and mod.info then mod:info("DARKTIDEVR_KBM aim_reset reason=%s", tostring(reason)) end
    end
    -- Record every orientation update, including those skipped for a repeated
    -- head pose. Another orientation class (a ledge, a forced view) updates the
    -- shared stock orientation in between; its yaw must not read as mouse input.
    function api.touch(owner, t, dt)
        local continuous = state.touch_owner == owner and finite(state.touch_t) and finite(t) and
            finite(dt) and t >= state.touch_t and t-state.touch_t <= dt*1.5+0.002
        state.touch_owner, state.touch_t = owner, t
        if not continuous then state.discontinuous = true end
    end
    -- Integrate the stock orientation's mouse delta since the last write.
    -- Returns the yaw and signed pitch to write, and the camera yaw to turn.
    function api.observe(owner, t, game_yaw, game_pitch, head_yaw, head_pitch, frozen, min_pitch, max_pitch)
        local fresh = state.owner == owner and finite(state.t) and t >= state.t and t-state.t <= 0.25 and
            finite(state.written_yaw) and not state.discontinuous
        state.discontinuous = false
        if not fresh then
            local had_aim = state.aim_yaw ~= nil
            KeyboardMouse.reset(state)
            if had_aim and mod.info then mod:info("DARKTIDEVR_KBM aim_reset reason=discontinuity") end
        end
        state.owner, state.t = owner, t
        local mouse_yaw, mouse_pitch = 0, 0
        if fresh and not frozen then
            mouse_yaw = wrap(game_yaw-state.written_yaw)
            mouse_pitch = wrap(game_pitch-state.written_pitch)
        end
        if mouse_yaw ~= 0 or mouse_pitch ~= 0 then
            local motion = state.motion or {}
            state.motion = motion
            motion[#motion+1] = {t=t, yaw=mouse_yaw, pitch=mouse_pitch}
            while #motion > 64 or (motion[1] and t-motion[1].t > 1) do table.remove(motion, 1) end
        end
        local yaw_turn = 0
        if not frozen or state.aim_yaw == nil then
            yaw_turn = KeyboardMouse.step(state, head_yaw, head_pitch, mouse_yaw, mouse_pitch,
                api.options(), min_pitch, max_pitch)
        end
        if state.aim_yaw == nil then return nil end
        state.written_yaw, state.written_pitch = state.aim_yaw%TAU, state.aim_pitch%TAU
        if not frozen then state.live_t = t end
        return state.written_yaw, state.written_pitch, yaw_turn
    end
    -- Mouse movement over the last melee window as view-space right/up angles.
    function api.mouse_motion(t)
        local dx, dy = 0, 0
        for _, sample in ipairs(state.motion or {}) do
            if finite(t) and sample.t <= t and t-sample.t <= KeyboardMouse.melee_motion_window then
                dx, dy = dx-sample.yaw, dy+sample.pitch
            end
        end
        return dx, dy
    end
    -- Choose the melee roll while idle and hold it through the attack and its
    -- combo, as wrist roll does. A weapon change starts a new choice.
    -- The second result is true on the first update of a held choice.
    function api.melee_roll(weapon, running, choose)
        if not weapon then state.melee = nil; return 0, false end
        local latch = state.melee
        if not latch or latch.weapon ~= weapon then latch = {weapon=weapon}; state.melee = latch end
        if not running then latch.roll, latch.held = choose() or 0, false end
        latch.roll = latch.roll or 0
        local held_now = running and not latch.held
        if running then latch.held = true end
        return latch.roll, held_now
    end
    -- Third-person hub: the stock mouse orbit swings the camera around the
    -- body, and a seated player cannot turn to follow it, so the view turns
    -- by the same yaw. Returns the orbit change since the last written yaw;
    -- zero across an owner change, a gap or another orientation class.
    function api.orbit_turn(owner, t, game_yaw, written_yaw)
        local fresh = state.orbit_owner == owner and finite(state.orbit_t) and finite(t) and
            t >= state.orbit_t and t-state.orbit_t <= 0.25 and not state.discontinuous
        state.discontinuous = false
        state.orbit_owner, state.orbit_t = owner, t
        if not fresh or not finite(game_yaw) or not finite(written_yaw) then return 0 end
        return wrap(game_yaw-written_yaw)
    end
    -- Called once per input update with the stock devices. Only gameplay
    -- counts (sampling true): in menus the viewer turns controller pointing
    -- into desktop mouse events. Returns true when suppression starts or ends.
    function api.sample_devices(devices, t, sampling)
        if not finite(t) then return false end
        local before = api.recent_input()
        state.input_now = t
        if finite(state.input_t) and state.input_t > t then state.input_t = nil end
        if sampling then
            for _, device in pairs(devices or {}) do
                local ok, active = pcall(KeyboardMouse.device_activity, device)
                if ok and active then state.input_t = t; break end
            end
        end
        return api.recent_input() ~= before
    end
    function api.recent_input()
        return finite(state.input_t) and finite(state.input_now) and
            state.input_now-state.input_t < KeyboardMouse.controller_cooldown
    end
    function api.live(t)
        return api.enabled() and finite(state.live_t) and finite(t) and t >= state.live_t and
            t-state.live_t <= 0.25 and state.aim_yaw ~= nil
    end
    function api.recenter(head_yaw)
        return KeyboardMouse.recenter(state, head_yaw)
    end
    local previous_setting_changed = mod.on_setting_changed
    mod.on_setting_changed = function(id, ...)
        if previous_setting_changed then previous_setting_changed(id, ...) end
        if id == "keyboard_mouse_mode" then
            api.reset("setting")
        end
        if id == "keyboard_mouse_mode" or id == "keyboard_mouse_disable_controllers" then
            save_settings()
            if api.on_mode_changed then api.on_mode_changed(api.enabled(), api.controllers_disabled()) end
        end
    end
    return api
end

return KeyboardMouse
