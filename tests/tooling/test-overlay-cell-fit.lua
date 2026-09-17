-- Every hand display draws into one cell of the hand overlay's atlas, and the
-- cell's size follows the eye target, which follows Virtual Desktop's FOV
-- tangent. Twice now a display laid out for the 2112-wide eye has spilled into
-- its neighbour's cell at 1908: the wrist display's bars beside the ammo count
-- (worn, 16 and 17 September) and an item name on the forearm holsters. Each
-- was found by measuring one module after the user saw it. This measures them
-- all, at every tangent worth caring about, before anyone sees anything.
local Overlay = dofile(assert(arg[1]))
local Wrist = dofile(assert(arg[2]))
local Radial = dofile(assert(arg[3]))
local Counts = dofile(assert(arg[4]))
local Readout = dofile(assert(arg[5]))

-- The eye targets: 100 per cent of Virtual Desktop's FOV tangent, the 90 the
-- user runs, and 80 as the next step down. Height comes with width, but only
-- the width matters here: every layout below is wider than it is tall.
local TARGETS = {
    {name = "100% tangent", width = 2112, height = 2304},
    {name = "90% tangent", width = 1908, height = 2076},
    {name = "80% tangent", width = 1700, height = 1850},
}

local failures = {}
local function check(target, display, half_width_metres, pixel_metres)
    local cell = Overlay.cell_width({width = target.width, height = target.height})
    local room = cell * 0.5 - Overlay.CELL_MARGIN
    local half_pixels = half_width_metres / pixel_metres
    local line = string.format("%-22s %-13s half=%6.1f px room=%6.1f px", target.name, display, half_pixels, room)
    if half_pixels > room then
        failures[#failures + 1] = line .. "  SPILLS by " .. string.format("%.1f px", half_pixels - room)
    end
    return half_pixels <= room
end

for _, target in ipairs(TARGETS) do
    local cell = Overlay.cell_width({width = target.width, height = target.height})

    -- The wrist display fits itself to the cell, so it must pass at every
    -- target by construction: that is what Wrist.pixel_metres is for.
    check(target, "wrist", Wrist.LAYOUT_HALF_WIDTH, Wrist.pixel_metres(cell))

    -- The item radial: each label sits where its own sector puts it, which is
    -- not the full radius except straight up, so the offsets come from
    -- label_offset rather than from the radius. Text is fitted by the overlay
    -- rather than clipped, so what must hold is that a label is never dropped
    -- (no room at all) and never shrunk below half what was asked for. At the
    -- user's 90 per cent tangent every label keeps its full size; at 80 the
    -- two side labels shrink, which is recorded here rather than failed.
    local widest = Overlay.estimated_width("Device", Radial.LABEL_PX)
    for index = 1, #Radial.OPTIONS do
        local x = Radial.label_offset(index, #Radial.OPTIONS, Radial.RADIUS)
        local room = Overlay.text_room(x / Radial.PIXEL_METRES, cell, nil)
        local font = Overlay.fitted_font(Radial.LABEL_PX, widest, room)
        if not font or font < Radial.LABEL_PX * 0.5 then
            failures[#failures + 1] = string.format(
                "%-22s radial %-7s room=%.1f px for %.1f px of text, font=%s",
                target.name, Radial.OPTIONS[index].label, room, widest, tostring(font))
        end
    end

    -- The holster counts and the ammo readout draw about their anchor; the
    -- ring is the readout's widest mark.
    check(target, "holster count", Counts.FONT_SIZE * Counts.PIXEL_METRES * 0.5, Counts.PIXEL_METRES)
    check(target, "ammo ring", Readout.RING_RADIUS, Readout.PIXEL_METRES / Readout.PANEL_DENSITY)
end

if #failures > 0 then
    for _, line in ipairs(failures) do io.write(line, "\n") end
    error(#failures .. " overlay layout(s) do not fit their cell", 0)
end

-- And the guard itself: a layout that does not fit must be caught. The wrist
-- display's own pre-17-September constant is the worked example -- 0.066 m of
-- layout at a fixed 0.0002625 m per pixel is 251 px, against 229 px of room
-- in the 90 per cent tangent's 477 px cell.
local cell_90 = Overlay.cell_width({width = 1908, height = 2076})
local fixed_half = Wrist.LAYOUT_HALF_WIDTH / Wrist.PIXEL_METRES
assert(fixed_half > cell_90 * 0.5 - Overlay.CELL_MARGIN,
    "the test cannot see the spill it was written for")
assert(Wrist.LAYOUT_HALF_WIDTH / Wrist.pixel_metres(cell_90) <= cell_90 * 0.5 - Overlay.CELL_MARGIN,
    "the wrist display's fit does not cure it")

print("overlay_cell_fit=pass wrist radial holster_count ammo_ring at 2112/1908/1700")
