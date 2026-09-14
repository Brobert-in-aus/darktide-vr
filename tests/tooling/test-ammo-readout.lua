-- Diegetic ammo readout: values from the stock slot component fields, text
-- and warning levels, and its wiring after the hand pose.
local Readout = dofile(assert(arg[1]))

local Ammo = {
    clips_in_use = function(slot, out)
        local any = false
        for i = 1, 2 do out[i] = slot.current_ammunition_clips_in_use[i] == true; any = any or out[i] end
        return any
    end,
    current_ammo_in_clips = function(slot, i) return slot.current_ammunition_clip[i] end,
    max_ammo_in_clips = function(slot, i) return slot.max_ammunition_clip[i] end,
}
local function gun(clip, reserve)
    return {max_ammunition_reserve = 400, current_ammunition_reserve = reserve,
        current_ammunition_clips_in_use = {true, false},
        current_ammunition_clip = {clip, 99}, max_ammunition_clip = {40, 99}}
end

local v = assert(Readout.values(gun(12, 180), Ammo, 2))
assert(v.clip == 12 and v.clip_max == 40 and v.reserve == 180 and v.reserve_max == 400 and not v.heat, "unused clip counted")
local text, level = Readout.text(v)
assert(text == "12 | 180" and level == "normal", text)
-- Stock low-ammo threshold: 20 % of clip plus reserve.
text, level = Readout.text(Readout.values(gun(10, 78), Ammo, 2))
assert(level == "low", level)
text, level = Readout.text(Readout.values(gun(0, 300), Ammo, 2))
assert(text == "0 | 300" and level == "critical")
-- Heat-only weapons (plasma, some staffs report heat without reserve).
v = assert(Readout.values({overheat_current_percentage = 0.5}, Ammo, 2))
text, level = Readout.text(v)
assert(text == "50%" and level == "normal", text)
assert(select(2, Readout.text({heat = 0.8})) == "low")
assert(select(2, Readout.text({heat = 0.95})) == "critical")
-- Both: ammo and heat side by side.
local both = gun(5, 100); both.overheat_current_percentage = 0.3
assert(Readout.text(Readout.values(both, Ammo, 2)) == "5 | 100  30%")
-- Nothing to show: melee slot fields, no reserve, no clips in use, cold.
assert(Readout.values({}, Ammo, 2) == nil)
assert(Readout.values({max_ammunition_reserve = 0, overheat_current_percentage = 0}, Ammo, 2) == nil)
local idle = gun(5, 5); idle.current_ammunition_clips_in_use = {false, false}
assert(Readout.values(idle, Ammo, 2) == nil)
assert(Readout.values(nil, Ammo, 2) == nil and Readout.text(nil) == nil)

-- Stacked lines: clip large, reserve small beneath; heat-only is one line.
local first, second = Readout.lines({clip = 12, reserve = 180})
assert(first == "12" and second == "180")
first, second = Readout.lines({clip = 5, reserve = 100, heat = 0.3})
assert(first == "5" and second == "100  30%")
first, second = Readout.lines({heat = 0.5})
assert(first == "50%" and second == nil)
assert(Readout.lines(nil) == nil)

-- Colour runs white (full) -> yellow (half) -> orange (nearly empty), red at 0.
local function rgb(values) local c = Readout.color(values); return math.floor(c[1] + .5), math.floor(c[2] + .5), math.floor(c[3] + .5) end
assert(select(3, rgb({clip = 40, clip_max = 40})) == 250, "full is not white")
local r, g, b = rgb({clip = 20, clip_max = 40})
assert(r == 255 and g == 225 and b == 80, "half is not yellow")
r, g, b = rgb({clip = 1, clip_max = 40})
assert(r == 255 and g < 145 and g > 135, "nearly empty is not orange")
r, g, b = rgb({clip = 0, clip_max = 40})
assert(r == 255 and g == 55 and b == 45, "empty is not red")
local g_prev = 999
for clip = 40, 1, -1 do
    local _, gg = rgb({clip = clip, clip_max = 40})
    assert(gg <= g_prev, "colour does not darken steadily as ammo runs down")
    g_prev = gg
end
assert(select(2, rgb({heat = 0.97})) == 55 and select(3, rgb({heat = 0})) == 250)
assert(select(3, rgb(nil)) == 250)
-- The reserve line fades on its own capacity: a full clip with a low reserve.
local full_clip = Readout.color({clip = 40, clip_max = 40, reserve = 20, reserve_max = 400})
local low_reserve = Readout.fill_color(20, 400)
assert(math.floor(full_clip[3] + .5) == 250, "clip colour follows the reserve")
assert(low_reserve[1] == 255 and low_reserve[2] < 160, "reserve at 5 % is not orange")
assert(Readout.fill_color(400, 400)[3] == 250 and Readout.fill_color(0, 400)[2] == 55)

-- Donut pieces: a full dim track, then the filled arc; the fill grows smoothly.
local function filled_length(progress)
    local total = 0
    for _, arc in ipairs(Readout.ring_arcs(progress)) do
        if not arc.track then total = total + arc.length end
    end
    return total
end
local track_count = 0
for _, arc in ipairs(Readout.ring_arcs(0)) do assert(arc.track); track_count = track_count + 1 end
assert(track_count == Readout.RING_SEGMENTS and filled_length(0) == 0)
local previous = 0
for step = 1, 200 do
    local length = filled_length(step / 200)
    assert(length >= previous, "fill went backwards")
    assert(length - previous < filled_length(1) / Readout.RING_SEGMENTS * 1.01, "fill jumped by more than one piece")
    previous = length
end
local last
for _, arc in ipairs(Readout.ring_arcs(0.5)) do if not arc.track then last = arc end end
assert(last.angle <= math.pi + 1e-9, "half fill passes the bottom")

-- Reload ring and interrupted-reload shake.
local tracker = Readout.reload_tracker()
local p, s = tracker.update(nil, 0, 0, 10)
assert(p == nil and s == nil)
p, s = tracker.update("reload_state", 10, 13, 10)
assert(p == 0 and s == nil)
p = tracker.update("reload_state", 10, 13, 11.5)
assert(math.abs(p - 0.5) < 1e-9)
-- Finished: the action ends at its end time, no shake.
tracker.update("reload_state", 10, 13, 12.95)
p, s = tracker.update(nil, 0, 0, 13.0)
assert(p == nil and s == nil, "a completed reload shook")
-- Interrupted by a sprint at 40 %: shake that fades, ring gone.
tracker.update("reload_state", 20, 23, 21.2)
p, s = tracker.update("sprint", 21.2, 21.3, 21.25)
assert(p == nil and s and math.abs(s - 1) < 1e-9, "no shake on interruption")
p, s = tracker.update(nil, 0, 0, 21.45)
assert(p == nil and s > 0 and s < 1, "shake does not fade")
p, s = tracker.update(nil, 0, 0, 21.7)
assert(s == nil, "shake did not stop")
-- Ammo in, then the reload chains early into aiming or firing: finished, no shake.
tracker.update("reload_state", 40, 43.3, 40, 0)
tracker.update("reload_state", 40, 43.3, 42.9, 30)
p, s = tracker.update("aim", 42.9, 50, 43.1, 30)
assert(p == nil and s == nil, "an early-chained finished reload shook")
-- A new reload restarts the ring from zero; a shotgun's reload kind counts too.
p = tracker.update("reload_shotgun", 30, 31, 30)
assert(p == 0)
p = tracker.update("reload_shotgun", 31, 32, 31.5)
assert(math.abs(p - 0.5) < 1e-9, "next shell did not restart the ring")

-- Drawn after the hand pose, and released with the other GUI resources.
local file = assert(io.open(assert(arg[2]), "rb")); local main = file:read("*a"); file:close()
local ik = assert(main:find("presentation.gun_aim.update(self._world, player_unit)", 1, true))
local draw = assert(main:find("presentation.ammo_readout.draw(self._world, player_unit)", 1, true))
assert(draw > ik, "readout drawn before the hand pose")
local state = assert(main:find("mod.on_game_state_changed = function", 1, true))
assert(main:find("presentation.ammo_readout.destroy", state, true), "readout GUI survives loading")
-- Stacked layout: clip above, dash, reserve below; glyph boxes never overlap,
-- the block is centred and fits inside the reload ring.
do
    local size, small = Readout.FONT_SIZE * Readout.PIXEL_METRES, Readout.SMALL_FONT_SIZE * Readout.PIXEL_METRES
    local l = Readout.stack_layout(size, small)
    local clip_top, clip_bottom = l.clip_y - Readout.GLYPH_TOP * size, l.clip_y - Readout.GLYPH_BOTTOM * size
    local reserve_top, reserve_bottom = l.reserve_y - Readout.GLYPH_TOP * small, l.reserve_y - Readout.GLYPH_BOTTOM * small
    local dash_top, dash_bottom = l.dash_y + l.dash_thickness * 0.5, l.dash_y - l.dash_thickness * 0.5
    assert(clip_bottom > dash_top and dash_bottom > reserve_top, "clip, dash and reserve overlap")
    assert(math.abs(clip_top + reserve_bottom) < 1e-9, "stack not centred")
    assert(clip_top - reserve_bottom < 2 * Readout.RING_RADIUS - 2 * Readout.RING_THICKNESS, "stack does not fit inside the ring")
    assert(l.dash_length > 0 and l.dash_thickness > 0)
end
print("ammo_readout=pass values text levels heat_only nothing_to_show after_hand_pose stack_layout")
