-- The options tree itself. A malformed one is not a small bug: DMF throws
-- while registering the mod and nothing loads at all, and a setting that
-- quietly disappears in a reorganisation takes the player's saved value with
-- it (the ids are the saved keys). Walked here against the rules DMF applies
-- in mods/dmf/scripts/mods/dmf/modules/core/options.lua.
local data_path = assert(arg[1])
local localization_path = assert(arg[2])
local mod_root = assert(arg[3])

local localization = dofile(localization_path)

-- Enough of a mod object for the data file: it localizes two strings and
-- loads three sibling modules by their in-game path.
local mod = {}
function mod:localize(key) return key end
function mod:io_dofile(path)
    local name = path:match("([^/]+)$")
    return dofile(mod_root .. "/" .. name .. ".lua")
end
-- The controller bindings build their widgets from saved values, filling in
-- the legacy defaults when there are none; a plain store is all they need.
local stored = {}
function mod:get(key) return stored[key] end
function mod:set(key, value) stored[key] = value end
rawset(_G, "get_mod", function() return mod end)
-- darktidevr_keyboard_mouse.widgets() looks for the on/off switch file
-- through Mods.lua when it is given no argument; without it, the plain
-- toggle is returned, which is what we want to walk.
rawset(_G, "Mods", nil)

local data = dofile(data_path)
assert(type(data) == "table" and type(data.options) == "table", "no options table")
local widgets = assert(data.options.widgets, "no widgets")

-- DMF unfolds sub_widgets only for these (options.lua: allowed_parent_widget_types).
local can_parent = {header = true, group = true, checkbox = true, dropdown = true}
-- Types that hold a value, and so need a saved key and a label.
local holds_value = {checkbox = true, dropdown = true, numeric = true, keybind = true}

local seen, order, problems = {}, {}, {}
local function fail(text) problems[#problems + 1] = text end

local function has_text(key)
    return type(key) == "string" and type(localization[key]) == "table" and
        type(localization[key].en) == "string" and #localization[key].en > 0
end

local function walk(list, depth, parent)
    for index, widget in ipairs(list) do
        local where = (parent or "root") .. "[" .. index .. "]"
        if type(widget) ~= "table" then
            fail(where .. " is a " .. type(widget) .. ", not a widget")
        else
            local id = widget.setting_id
            if type(id) ~= "string" or id == "" then
                fail(where .. " has no setting_id")
            else
                where = id
                if seen[id] then fail("two widgets share the setting_id " .. id) end
                seen[id] = {type = widget.type, depth = depth}
                order[#order + 1] = id
                -- A widget may name its own label instead of using its id
                -- (the controller bindings do, one per action).
                if not has_text(widget.title or id) then
                    fail(id .. " has no English label for " .. tostring(widget.title or id))
                end
            end
            local kind = widget.type
            if kind == nil then kind = "dropdown" end -- the file's one implicit type
            if widget.sub_widgets ~= nil then
                if not can_parent[kind] then
                    fail(where .. " is a " .. tostring(kind) ..
                        ", which DMF does not unfold sub_widgets for")
                elseif type(widget.sub_widgets) ~= "table" or #widget.sub_widgets == 0 then
                    fail(where .. " has an empty sub_widgets")
                else
                    walk(widget.sub_widgets, depth + 1, where)
                end
            elseif kind == "group" then
                fail(where .. " is a group with no sub_widgets, which DMF rejects")
            end
            if kind == "dropdown" then
                local options = widget.options
                if type(options) ~= "table" or #options == 0 then
                    fail(where .. " is a dropdown with no options")
                elseif options.localize ~= false then
                    for option_index, option in ipairs(options) do
                        if not has_text(option.text) then
                            fail(where .. " option " .. option_index .. " (" ..
                                tostring(option.text) .. ") has no English label")
                        end
                        if option.show_widgets then
                            for _, sub in ipairs(option.show_widgets) do
                                if not (widget.sub_widgets and widget.sub_widgets[sub]) then
                                    fail(where .. " option " .. option_index ..
                                        " shows sub_widget " .. tostring(sub) ..
                                        ", which does not exist")
                                end
                            end
                        end
                    end
                end
            end
            if kind == "numeric" then
                local range, default = widget.range, widget.default_value
                if type(range) ~= "table" or #range ~= 2 then
                    fail(where .. " is numeric with no range")
                elseif type(default) ~= "number" or default < range[1] or default > range[2] then
                    fail(where .. " defaults to " .. tostring(default) ..
                        " outside its range " .. tostring(range[1]) .. ".." .. tostring(range[2]))
                end
            end
            if holds_value[kind] and widget.default_value == nil then
                fail(where .. " holds a value with no default")
            end
        end
    end
end

walk(widgets, 1, nil)

-- Every setting the mod has ever shown. A reorganisation may move an id
-- anywhere in the tree; it may not lose one, because the id IS the saved key
-- and a player who loses it loses their choice (18 September).
local expected = {
    "movement_reference", "vr_crosshair_scale", "vr_aim_stabilization", "vr_sway_cancel",
    "ads_focus", "vr_ads_zoom", "vr_gun_pitch", "vr_sight_ads", "vr_two_hand_support",
    "vr_two_hand_grip_mode", "vr_virtual_stock", "vr_ammo_readout", "vr_weapon_charge_style",
    "vr_full_body_experimental", "body_mirror_keybind", "vr_forearm_holsters",
    "vr_holster_counts", "vr_item_radial", "vr_wrist_display", "vr_wrist_display_scale",
    "vr_haptics_mode", "vr_haptics_strength", "marker_plane", "vr_teammate_status",
    "vr_skull_throw", "vr_comms_gesture", "melee_preview_toggle", "melee_preview_keybind",
    "scanner_test_keybind", "hud_visible", "hud_editor", "hud_size", "hud_distance",
    "hud_internal_scale", "focus_warning", "hub_third_person", "spectate_third_person",
    "stereo_cinematics", "remote_mission_input", "psykhanium_online_rules",
    "vr_turn_mode", "vr_turn_speed", "keyboard_mouse_mode",
}
for _, id in ipairs(expected) do
    if not seen[id] then fail("the setting " .. id .. " is no longer in the menu") end
end

-- Sections: the top level should read as a short list of places to go, not
-- as the settings themselves.
local top_level_values = 0
for _, widget in ipairs(widgets) do
    if type(widget) == "table" and holds_value[widget.type] then
        top_level_values = top_level_values + 1
    end
end
if top_level_values > 2 then
    fail(top_level_values .. " settings sit at the top level, outside any section")
end

if #problems > 0 then
    for _, problem in ipairs(problems) do io.write("  ", problem, "\n") end
    error(#problems .. " problem(s) in the options tree", 0)
end

local deepest = 1
for _, entry in pairs(seen) do
    if entry.depth > deepest then deepest = entry.depth end
end
assert(deepest >= 3, "nothing is nested below a section any more")
print(string.format("options_data=pass widgets=%d deepest=%d sections=%d",
    #order, deepest, #widgets))
