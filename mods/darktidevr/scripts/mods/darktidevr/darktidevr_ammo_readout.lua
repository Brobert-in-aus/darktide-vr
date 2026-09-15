-- Diegetic ammo count: a small world-space readout beside the dominant hand
-- while a ranged weapon is wielded (clip and reserve, or heat), instead of on
-- the HUD panel. Option "vr_ammo_readout", default off. Reads the same slot
-- component fields as the stock HudElementPlayerWeapon; draws after the hand
-- pose in the same world GUI style as the crosshair feedback.
local Readout = {}

-- Just above the hand, level with the gun, now it draws in front of the
-- scene (worn, 15 September evening; it was 9 cm up to clear the gun).
Readout.OFFSET_UP = 0.03        -- metres above the grip
-- Towards the body's midline, away from the gun (3 cm more, worn, 15
-- September evening).
Readout.OFFSET_INWARD = 0.08
-- Worn, 15 September evening: 5 cm further toward the end of the hand (along
-- the aim), then 6 cm away from the eye (drawn toward the eye it filled the
-- view while aiming; staying visible is a rendering matter, not position).
Readout.OFFSET_FORWARD = 0.05
Readout.AWAY_FROM_EYE = 0.06
-- Relative to the gun (user, 15 September evening), not the hand: in the
-- gun's frame from its attach node at the controller grip, along the barrel,
-- toward the body's midline and along the gun's up. Starting from where the
-- hand-relative placement showed it (worn screenshot 19:04): beside the
-- receiver, just ahead of the hand. The hand drawn from the hidden
-- character's animation moved with the weapon and while strafing.
Readout.GUN_FORWARD = 0.08
Readout.GUN_SIDE = 0.04
Readout.GUN_UP = 0.0
Readout.PIXEL_METRES = 0.0011   -- world size of one font pixel (layout unit)
-- The overlay panel draws several panel pixels per layout pixel, for sharp
-- text at hand distance.
Readout.PANEL_DENSITY = 3
Readout.FONT_SIZE = 30          -- clip count (or heat)
Readout.SMALL_FONT_SIZE = 15    -- reserve under it
Readout.RING_RADIUS = 0.030     -- metres; the ring encloses both lines
Readout.RING_THICKNESS = 0.0045 -- metres
Readout.RING_SEGMENTS = 96
-- Digit extents below each line's text position, as fractions of that
-- line's font size. Measured in the eye render on 15 September against the
-- dash bar (drawn at an exact position): both lines' digits span 0.33-0.80
-- at 0.5 m. Worn at hand distance the small reserve renders relatively
-- larger (0.63 of the clip's height, not 0.5), which is how it overlapped the
-- clip on 14 September, so the reserve's extent is taken generously. The
-- stack's spacing: a gap above and below the dash between them.
Readout.CLIP_GLYPH_TOP = 0.33
Readout.CLIP_GLYPH_BOTTOM = 1.0   -- 0.80 measured; the dash touched it at 0.5 m
Readout.RESERVE_GLYPH_TOP = 0.30
Readout.RESERVE_GLYPH_BOTTOM = 0.90
Readout.STACK_GAP = 0.12        -- of the clip font size, above and below the dash
Readout.DASH_LENGTH = 1.0       -- of the reserve font size
Readout.DASH_THICKNESS = 0.14   -- of the reserve font size

-- Vertical layout of the stacked readout, centred on 0 (y up): the text
-- positions of the clip and reserve and the dash's centre, for font sizes
-- size (clip) and small (reserve). Glyph boxes do not overlap.
function Readout.stack_layout(size, small)
    local clip_height = (Readout.CLIP_GLYPH_BOTTOM - Readout.CLIP_GLYPH_TOP) * size
    local reserve_height = (Readout.RESERVE_GLYPH_BOTTOM - Readout.RESERVE_GLYPH_TOP) * small
    local gap, dash = Readout.STACK_GAP * size, Readout.DASH_THICKNESS * small
    local top = (clip_height + gap + dash + gap + reserve_height) * 0.5
    return {
        clip_y = top + Readout.CLIP_GLYPH_TOP * size,
        dash_y = top - clip_height - gap - dash * 0.5,
        reserve_y = top - clip_height - gap - dash - gap + Readout.RESERVE_GLYPH_TOP * small,
        dash_length = Readout.DASH_LENGTH * small,
        dash_thickness = dash,
        height = top * 2,
    }
end
-- Pieces of the reload donut: the dim full track, then the filled arc from
-- the top clockwise. Each piece is a short straight quad centred at `angle`
-- (radians clockwise from the top), slightly overlapping its neighbours so
-- the ring reads solid; the last filled piece is shortened to the exact
-- progress so the fill moves smoothly.
function Readout.ring_arcs(progress)
    local arcs = {}
    local n = Readout.RING_SEGMENTS
    local step = 2 * math.pi / n
    local full = 2 * Readout.RING_RADIUS * math.sin(step * 0.5) * 1.15
    for i = 0, n - 1 do
        arcs[#arcs + 1] = {angle = (i + 0.5) * step, length = full, track = true}
    end
    progress = math.max(0, math.min(1, progress or 0))
    local filled = progress * n
    local whole = math.floor(filled)
    for i = 0, whole - 1 do
        arcs[#arcs + 1] = {angle = (i + 0.5) * step, length = full}
    end
    local part = filled - whole
    if part > 0.01 then
        arcs[#arcs + 1] = {angle = (whole + part * 0.5) * step, length = full * part}
    end
    return arcs
end
Readout.TEST_FLAG = "./../mods/darktidevr/darktidevr_ammo_readout_test.flag"

-- Ammo and heat of a slot component. nil when the slot shows neither (a
-- force staff: peril stays on the HUD).
function Readout.values(slot, Ammo, clip_count)
    if type(slot) ~= "table" then return nil end
    local result = {}
    local max_reserve = slot.max_ammunition_reserve
    if Ammo and type(max_reserve) == "number" and max_reserve > 0 then
        local in_use = {}
        if Ammo.clips_in_use(slot, in_use) then
            local clip, clip_max = 0, 0
            for i = 1, clip_count or 1 do
                if in_use[i] then
                    clip = clip + (Ammo.current_ammo_in_clips(slot, i) or 0)
                    clip_max = clip_max + (Ammo.max_ammo_in_clips(slot, i) or 0)
                end
            end
            result.clip, result.clip_max = clip, clip_max
            result.reserve, result.reserve_max = slot.current_ammunition_reserve or 0, max_reserve
        end
    end
    local heat = slot.overheat_current_percentage
    if type(heat) == "number" and heat > 0 then result.heat = math.min(heat, 1) end
    if not result.clip and not result.heat then return nil end
    return result
end

-- A melee weapon with special charges: charges left and whether the special
-- is active. nil for melee weapons without charges. The maximum is the slot's
-- max_num_special_charges or, for charge specials such as the Skitarius arc
-- maul (WeaponSpecialHitCharges: 0-40 stored, gained over time and on hits),
-- the template tweak data's max_charges; an activation_cost_divisor turns the
-- stored count into the charges the player sees (40 / 8 = 5 per charge).
function Readout.melee_values(slot, tweak)
    if type(slot) ~= "table" then return nil end
    local max = slot.max_num_special_charges
    if (type(max) ~= "number" or max <= 0) and type(tweak) == "table" then max = tweak.max_charges end
    if type(max) ~= "number" or max <= 0 then return nil end
    local stored = math.max(0, math.min(max, slot.num_special_charges or 0))
    local divisor = type(tweak) == "table" and tweak.activation_cost_divisor
    if type(divisor) == "number" and divisor >= 1 then
        return {charges = math.floor(stored / (max / divisor) + 1e-6), charges_max = divisor,
            active = slot.special_active == true}
    end
    return {charges = stored, charges_max = max, active = slot.special_active == true}
end

-- Display text and colour: white, amber from 20 % left (stock's low-ammo
-- threshold) or 75 % heat, red when the clip is empty or heat is past 90 %.
function Readout.text(values)
    if not values then return nil end
    if values.charges then
        return string.format("%d/%d", values.charges, values.charges_max), values.charges == 0 and "critical" or "normal"
    end
    local parts = {}
    if values.clip then parts[#parts + 1] = string.format("%d | %d", values.clip, values.reserve) end
    if values.heat then parts[#parts + 1] = string.format("%d%%", math.floor(values.heat * 100 + 0.5)) end
    local level = "normal"
    local total_max = (values.clip_max or 0) + (values.reserve_max or 0)
    if values.clip and total_max > 0 and (values.clip + values.reserve) / total_max <= 0.2 then level = "low" end
    if values.heat and values.heat >= 0.75 then level = "low" end
    if (values.clip and values.clip == 0) or (values.heat and values.heat >= 0.9) then level = "critical" end
    return table.concat(parts, "  "), level
end

-- The stacked layout: the clip count (or heat) large in the ring's centre, the
-- reserve (or heat, for a weapon with both) small beneath it.
function Readout.lines(values)
    if not values then return nil end
    if values.charges then return string.format("%d/%d", values.charges, values.charges_max), nil end
    if values.clip then
        return tostring(values.clip), values.heat and string.format("%d  %d%%", values.reserve,
            math.floor(values.heat * 100 + 0.5)) or tostring(values.reserve)
    end
    return string.format("%d%%", math.floor(values.heat * 100 + 0.5)), nil
end

Readout.COLORS = {normal = {230, 235, 245, 240}, low = {235, 255, 190, 60}, critical = {235, 255, 70, 50}}

-- Colour as the clip runs down: white when full, yellow at half, orange just
-- before empty, red at 0. Heat-only weapons run the same scale on the heat left
-- before overheating (red from 95 % heat).
local WHITE, YELLOW, ORANGE, RED = {240, 245, 250}, {255, 225, 80}, {255, 140, 35}, {255, 55, 45}
local function mix(a, b, f)
    return {a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f}
end
-- Colour of an amount against its capacity: white at capacity, yellow at half,
-- orange nearly empty, red at 0.
function Readout.fill_color(amount, capacity)
    if type(amount) ~= "number" or type(capacity) ~= "number" or capacity <= 0 then return WHITE end
    if amount <= 0 then return RED end
    local fraction = math.max(0, math.min(1, amount / capacity))
    if fraction >= 0.5 then return mix(YELLOW, WHITE, (fraction - 0.5) / 0.5) end
    return mix(ORANGE, YELLOW, fraction / 0.5)
end

-- The clip count's colour (clip against clip size); heat-only weapons on the
-- heat left. The reserve line uses fill_color(reserve, reserve_max).
function Readout.color(values)
    if not values then return WHITE end
    -- Special active: the power field's blue.
    if values.charges then
        if values.active then return {110, 190, 255} end
        return Readout.fill_color(values.charges, values.charges_max)
    end
    local fraction
    if values.clip and values.clip_max and values.clip_max > 0 then
        return Readout.fill_color(values.clip, values.clip_max)
    elseif values.heat then
        if values.heat >= 0.95 then return RED end
        fraction = 1 - values.heat
    else
        return WHITE
    end
    fraction = math.max(0, math.min(1, fraction))
    if fraction >= 0.5 then return mix(YELLOW, WHITE, (fraction - 0.5) / 0.5) end
    return mix(ORANGE, YELLOW, fraction / 0.5)
end

-- Reload progress from the stock weapon action component: a reload action's
-- elapsed share of its (time-scaled) duration. A reload that ends before its
-- end time without adding ammo was interrupted (sprint, swap, dodge): the
-- readout shakes for SHAKE_SECONDS and the ring goes. Stock reloads often
-- chain into firing or aiming before their end time once the ammo is in, so
-- ammo added counts as finished (review, 14 September).
Readout.SHAKE_SECONDS = 0.4
function Readout.reload_tracker()
    local tracker = {}
    local active, shake_until
    function tracker.update(kind, start_t, end_t, t, clip)
        local reloading = type(kind) == "string" and kind:match("^reload") ~= nil and
            type(start_t) == "number" and type(end_t) == "number" and end_t > start_t
        if reloading then
            if not active or active.start_t ~= start_t then
                active = {start_t = start_t, end_t = end_t, clip = clip}
            end
            active.end_t = end_t
        elseif active then
            local ammo_added = type(clip) == "number" and type(active.clip) == "number" and clip > active.clip
            if t < active.end_t - 0.15 and not ammo_added then shake_until = t + Readout.SHAKE_SECONDS end
            active = nil
        end
        local progress = active and math.max(0, math.min(1, (t - active.start_t) / (active.end_t - active.start_t)))
        local shake = shake_until and t < shake_until and (shake_until - t) / Readout.SHAKE_SECONDS or nil
        if shake_until and t >= shake_until then shake_until = nil end
        return progress, shake
    end
    return tracker
end

function Readout.install(mod, presentation, observation)
    -- The pure helpers, for the forearm holster labels.
    local api = {Readout = Readout}
    local logged_slot
    local world, gui, failed, logged
    local UIFonts, Ammo, NetworkConstants
    local test_poll, test_mode = 0, nil
    local tracker = Readout.reload_tracker()
    function api.destroy()
        if gui and world then pcall(World.destroy_gui, world, gui) end
        world, gui = nil, nil
    end
    local showing_t
    local function hide() showing_t = nil; if gui then Gui.set_visible(gui, false) end end
    -- The panel's ranged weapon element stays hidden while its count shows at
    -- the hand (one frame of grace for draw order).
    if mod.hook then
        mod:hook("HudElementPlayerWeapon", "draw", function(func, self, ...)
            local now = Managers and Managers.time and Managers.time:time("main")
            if showing_t and now and now - showing_t < 0.1 and self._slot_name == "slot_secondary" then
                return
            end
            return func(self, ...)
        end)
    end
    local function read_test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_mode end
        test_poll = 60
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Readout.TEST_FLAG, "r")
        if not file then test_mode = nil; return nil end
        local value = file:read("*all"); file:close()
        test_mode = type(value) == "string" and value:match("^%s*front%s*$") and "front" or nil
        -- The test flag also cycles a 3 s reload, every other one interrupted
        -- at 60 %, so the ring and the shake show without a gun.
        return test_mode
    end
    local function slot_values(unit)
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        local inventory = unit_data and unit_data:read_component("inventory")
        if inventory and inventory.wielded_slot == "slot_primary" then
            local weapon = ScriptUnit.has_extension(unit, "weapon_system")
            local template = weapon and weapon:weapon_template()
            return Readout.melee_values(unit_data:read_component("slot_primary"), template and template.weapon_special_tweak_data)
        end
        if not inventory or inventory.wielded_slot ~= "slot_secondary" then return nil end
        Ammo = Ammo or require("scripts/utilities/ammo")
        NetworkConstants = NetworkConstants or require("scripts/network_lookup/network_constants")
        local count = NetworkConstants.clips_in_use and NetworkConstants.clips_in_use.max_size or 1
        -- Peril stays on the HUD, where it usually lives (user, 15 September
        -- evening): a staff shows nothing here.
        return Readout.values(unit_data:read_component("slot_secondary"), Ammo, count)
    end
    -- The wielded ranged weapon's values, for other features (haptics).
    api.slot_values = slot_values
    local function draw(game_world, unit)
        local test = read_test_flag()
        if not unit or (not test and not mod:get("vr_ammo_readout")) or presentation.mode ~= 1 or
                presentation.gameplay_context.ui_blocks_gameplay(Managers.ui) then
            hide(); return
        end
        local values = slot_values(unit)
        if test and not logged_slot then
            logged_slot = true
            local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
            local inventory = unit_data and unit_data:read_component("inventory")
            local primary = unit_data and unit_data:read_component("slot_primary")
            mod:info("DARKTIDEVR_AMMO_READOUT test_slot wielded=%s melee_charges=%s/%s special_active=%s values=%s",
                tostring(inventory and inventory.wielded_slot), tostring(primary and primary.num_special_charges),
                tostring(primary and primary.max_num_special_charges), tostring(primary and primary.special_active),
                tostring(values ~= nil))
        end
        if not values and test then values = {clip = 32, clip_max = 40, reserve = 60, reserve_max = 400} end
        local text, level = Readout.text(values)
        if not text then hide(); return end
        local now = Managers.time:time("gameplay")
        local progress, shake
        if test then
            local cycle = now % 8
            local interrupted = cycle >= 4
            local phase = interrupted and cycle - 4 or cycle
            local kind = (phase < (interrupted and 1.8 or 3)) and "reload_state" or nil
            progress, shake = tracker.update(kind, now - phase, now - phase + 3, now, values.clip)
        else
            local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
            local action = unit_data and unit_data:read_component("weapon_action")
            local weapon = ScriptUnit.has_extension(unit, "weapon_system")
            local template = weapon and weapon:weapon_template()
            local settings = action and template and template.actions and action.current_action_name and
                template.actions[action.current_action_name]
            progress, shake = tracker.update(settings and settings.kind, action and action.start_t,
                action and action.end_t, now, values.clip)
        end
        local eye, eye_rotation
        if presentation.eye_pose then eye, eye_rotation = presentation.eye_pose(unit) end
        if not eye or not eye_rotation then hide(); return end
        local anchor
        if test then
            anchor = eye + Quaternion.forward(eye_rotation) * 0.5
        elseif presentation.gun_aim and presentation.gun_aim.gun_pose and presentation.gun_aim.gun_pose() then
            local side = presentation.weapon_hand_roles.physical("dominant")
            local gun_position, gun_rotation = presentation.gun_aim.gun_pose()
            local right = Quaternion.right(gun_rotation)
            local midline = side == "left" and right or -right
            anchor = gun_position + Quaternion.forward(gun_rotation) * Readout.GUN_FORWARD +
                midline * Readout.GUN_SIDE + Quaternion.up(gun_rotation) * Readout.GUN_UP
        else
            -- No gun placed (melee charges): beside the hand.
            local side = presentation.weapon_hand_roles.physical("dominant")
            -- The controller grip, as the gun and the forearm holsters use:
            -- the drawn wrist followed the character's animation (animation
            -- audit, 16 September, item F).
            local grip = presentation.weapon_grip_target("dominant")
            if not grip then hide(); return end
            local flat_right = Quaternion.right(eye_rotation)
            local inward = side == "left" and flat_right or -flat_right
            anchor = grip + Vector3.up() * Readout.OFFSET_UP + inward * Readout.OFFSET_INWARD
            local aim
            if presentation.weapon_aim_target then
                local _, rotation = presentation.weapon_aim_target("dominant")
                aim = rotation
            end
            if aim then anchor = anchor + Quaternion.forward(aim) * Readout.OFFSET_FORWARD end
            local offset = eye - anchor
            local distance = Vector3.length(offset)
            if distance > 1e-4 then
                anchor = anchor - offset * (Readout.AWAY_FROM_EYE / distance)
            end
        end
        -- In front of the scene: 2D UI on the hand overlay's panel at the anchor
        -- (darktidevr_hand_overlay), laid out in metres, x to the viewer's
        -- right and y up, one font pixel PIXEL_METRES wide as before.
        world = game_world
        local overlay = presentation.hand_overlay
        local density = Readout.PANEL_DENSITY
        local canvas = overlay and overlay.canvas(game_world, "ammo_readout", anchor, Readout.PIXEL_METRES / density)
        if not canvas then hide(); return end
        local ps = Readout.PIXEL_METRES
        local size = Readout.FONT_SIZE * ps
        local primary, secondary = Readout.lines(values)
        local c = Readout.color(values)
        -- An interrupted reload shakes the readout sideways, fading out.
        local dx = shake and math.sin(now * 55) * 0.006 * shake or 0
        local small = Readout.SMALL_FONT_SIZE * ps
        -- Measured in the eye render: the text position is above the glyphs,
        -- whose tops sit 0.32 and bottoms 0.80 of the font size below it;
        -- the 2D text is centred on the glyphs' middle, 0.56 below.
        local layout = Readout.stack_layout(size, small)
        local primary_y = secondary and layout.clip_y or size * 0.56
        canvas.text(primary, Readout.FONT_SIZE * density, dx, primary_y - size * 0.56, {240, c[1], c[2], c[3]})
        if secondary then
            -- The reserve fades on its own capacity, independently of the clip.
            local r = values.clip and Readout.fill_color(values.reserve, values.reserve_max) or c
            canvas.text(secondary, Readout.SMALL_FONT_SIZE * density, dx, layout.reserve_y - small * 0.56, {230, r[1], r[2], r[3]})
            -- The dash between them: a bar, so it never depends on the font's glyph.
            canvas.rect(dx, layout.dash_y, layout.dash_length, layout.dash_thickness, {200, r[1], r[2], r[3]})
        end
        if progress then
            -- Reload ring: squares along the circle (2D rectangles do not
            -- rotate), a dim full track under the part filled clockwise from
            -- the top.
            local thickness = Readout.RING_THICKNESS
            for _, arc in ipairs(Readout.ring_arcs(progress)) do
                local steps = math.max(1, math.ceil(arc.length / thickness))
                local step_angle = arc.length / Readout.RING_RADIUS / steps
                local first = arc.angle - step_angle * (steps - 1) * 0.5
                local color = {arc.track and 70 or 230, c[1], c[2], c[3]}
                for k = 0, steps - 1 do
                    local a = first + step_angle * k
                    canvas.rect(dx + math.sin(a) * Readout.RING_RADIUS, math.cos(a) * Readout.RING_RADIUS,
                        thickness, thickness, color)
                end
            end
        end
        showing_t = not test and Managers.time:time("main") or nil
        if not logged then
            logged = true
            mod:info("DARKTIDEVR_AMMO_READOUT first_draw text=%s level=%s test=%s", text, level, tostring(test))
        end
    end
    function api.draw(game_world, unit)
        if failed then return end
        local ok, err = pcall(draw, game_world, unit)
        if not ok then
            api.destroy(); failed = true
            mod:warning("DARKTIDEVR_AMMO_READOUT error=%s", tostring(err))
        end
    end
    return api
end

return Readout
