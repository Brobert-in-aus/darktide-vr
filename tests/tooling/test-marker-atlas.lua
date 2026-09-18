-- Marker atlas: resources set up as the HUD panel's, one frame's cells shown
-- only after the copy of that frame, cell allocation and the quad's UVs.
local Atlas = dofile(arg[1])

local calls = {}
local function record(name, result)
    return function(...) calls[#calls + 1] = {name = name, ...} return result end
end
local function find(name)
    for i = #calls, 1, -1 do if calls[i].name == name then return calls[i] end end
end
local ui = {}
local api = {
    Managers = {ui = {create_world = record("create_world", "render_world"),
        create_viewport = record("create_viewport", "viewport"),
        destroy_world = record("destroy_world")}},
    UIRenderer = {
        create_viewport_renderer = function() return {gui = "queue_gui", gui_retained = "retained"} end,
        create_resource_renderer = function() return {gui = "queue_gui", render_target = "capture",
            base_render_pass = "pass", render_pass_flag = "flag", render_target_material = "rt_mat"} end,
        destroy = record("renderer_destroy")},
    Renderer = {create_resource = record("create_resource", "display"),
        copy_render_target_rect = record("copy"), destroy_resource = record("destroy_resource")},
    World = {create_world_gui = record("create_world_gui", "world_gui"), destroy_gui = record("destroy_gui")},
    ScriptWorld = {destroy_viewport = record("destroy_viewport")},
    Gui = {create_material = function(gui, name) return gui .. ":" .. name end,
        destroy_material = record("destroy_material"), render_pass = record("render_pass")},
    Gui2 = {bitmap_3d = record("bitmap_3d")},
    Material = {set_scalar = record("set_scalar"), set_resource = record("set_resource")},
    Matrix4x4 = {identity = function() return "identity" end},
    Vector2 = function(x, y) return {x, y} end,
    Vector3 = function(x, y, z) return {x, y, z} end,
    Color = function(a, r, g, b) return {a, r, g, b} end,
    log = function() end,
}
Atlas.configure(api)
assert(Atlas.ensure("game_world"))
local state = Atlas.state
assert(state.resource.render_target == nil and state.resource.base_render_pass == nil and
    state.resource.render_pass_flag == nil, "the viewport owns the output binding")
assert(find("create_viewport")[5] == 1 and find("create_viewport")[8].back_buffer == "capture")
assert(find("set_resource")[3] == "display", "the world material samples the completed copy")
assert(state.world_gui == "world_gui" and find("create_world_gui")[1] == "game_world")

-- Frame 1: cells claimed, nothing shown yet (no completed copy).
local CW, CH = Atlas.CELL_WIDTH, Atlas.CELL_HEIGHT
local x, y = Atlas.claim(1, {x = 0, y = 2, z = 0})
assert(x == CW * 0.5 and y == CH * 0.5 and find("render_pass")[4] == true,
    "the first cell's centre, and the target cleared each frame")
local x2, y2 = Atlas.claim(1, {x = 1, y = 2, z = 0})
local x3, y3 = Atlas.claim(1, {x = 2, y = 2, z = 0})
assert(x2 == CW * 1.5 and y2 == CH * 0.5, "the second cell is the next column")
assert(x3 == CW * 0.5 and y3 == CH * 1.5, "the third wraps to the next row")
local function frame_for(anchor) return "tm", 0.002 end
assert(Atlas.draw("game_world", frame_for) == 0 and not find("copy"))

-- Frame 2: the copy runs first, then frame 1's cells are shown.
assert(Atlas.begin_frame(2) and find("copy")[1] == "capture" and find("copy")[6] == "display")
assert(Atlas.draw("other_world", frame_for) == 0, "cells never draw into another world")
assert(Atlas.draw("game_world", frame_for) == 3)
local quad = find("bitmap_3d")
local args = quad[6]
assert(quad[2] == state.world_material and quad[4] == "tm" and quad[5] == 1000)
-- The cell less its gutter: the quad and its UVs shrink together, so a texel
-- keeps its size in the world and a minified sample (a distant pickup's
-- marker) stays clear of the neighbouring cell.
assert(Atlas.GUTTER == 8)
assert(math.abs(args.size[1] - (CW - 16) * 0.002) < 1e-9 and
    math.abs(args.size[2] - (CH - 16) * 0.002) < 1e-9, 'the cell less its gutter')
assert(math.abs(args.position_offset[1] + (CW - 16) * 0.001) < 1e-9, 'still centred on the anchor')
local iu, iv = Atlas.GUTTER / Atlas.WIDTH, Atlas.GUTTER / Atlas.HEIGHT
-- The third cell is column 0, row 1: its far V edge is two cell heights down.
assert(math.abs(args.uv00[1] - (0.5 - iu)) < 1e-9 and
    math.abs(args.uv00[2] - (2 * CH / Atlas.HEIGHT - iv)) < 1e-9 and
    math.abs(args.uv11[1] - iu) < 1e-9 and
    math.abs(args.uv11[2] - (CH / Atlas.HEIGHT + iv)) < 1e-9,
    "the third cell, U and V reversed as on the HUD panel quad")
for i = 1, Atlas.CELLS do assert(Atlas.claim(2, {x = i, y = 2, z = 0})) end
local none, why = Atlas.claim(2, {x = 0, y = 0, z = 0})
assert(not none and why == "atlas_full")

-- Stale cells stop showing when the marker pass stops starting frames.
Atlas.draw("game_world", frame_for); Atlas.draw("game_world", frame_for)
assert(Atlas.draw("game_world", frame_for) == 0)

-- A per-pass handle gets one instance on the atlas GUI, its values replayed.
local instance = Atlas.material("handle", "frame", {ui_scale = {"set_scalar", 1, 2}})
assert(instance == "queue_gui:frame" and Atlas.material("handle", "frame") == instance)
assert(find("set_scalar")[1] == instance and find("set_scalar")[2] == "ui_scale" and find("set_scalar")[3] == 2)

-- A stamp names the values' revision: replayed once, skipped while the stamp
-- holds, replayed on a new stamp, and always replayed without one.
local function count(name)
    local n = 0
    for _, c in ipairs(calls) do if c.name == name then n = n + 1 end end
    return n
end
local sets = count("set_scalar")
Atlas.material("handle", "frame", {ui_scale = {"set_scalar", 1, 3}}, 7)
assert(count("set_scalar") == sets + 1 and find("set_scalar")[3] == 3, "the first stamp replays")
Atlas.material("handle", "frame", {ui_scale = {"set_scalar", 1, 3}}, 7)
assert(count("set_scalar") == sets + 1, "the same stamp skips the replay")
Atlas.material("handle", "frame", {ui_scale = {"set_scalar", 1, 4}}, 8)
assert(count("set_scalar") == sets + 2 and find("set_scalar")[3] == 4, "a new stamp replays")
Atlas.material("handle", "frame", {ui_scale = {"set_scalar", 1, 4}})
assert(count("set_scalar") == sets + 3, "no stamp: replayed as before")
-- A material the GUI cannot create: nil back, nothing replayed, no throw
-- (the stamp must not be recorded against a nil instance).
local create = api.Gui.create_material
api.Gui.create_material = function() return nil end
assert(Atlas.material("orphan", "frame", {ui_scale = {"set_scalar", 1, 5}}, 9) == nil)
assert(count("set_scalar") == sets + 3 and next(state.applied) ~= nil, "nothing replayed for a nil instance")
api.Gui.create_material = create

-- A map change drops the old world's GUI without calling into that world.
local before = #calls
Atlas.forget_world()
for i = before + 1, #calls do assert(calls[i].name ~= "destroy_gui", "the dying world is not called") end
assert(state.resource == nil and state.world_gui == nil and not state.ready)
assert(Atlas.ensure("game_world"))

-- A different world rebuilds; destroy restores ownership and releases all.
local resource = state.resource
Atlas.destroy()
assert(resource.render_target == "capture" and find("destroy_gui")[2] == "world_gui")
assert(find("destroy_resource")[1] == "display" and find("destroy_world")[2] == "render_world")
assert(state.resource == nil and not state.ready and #state.shown == 0)
assert(next(state.applied) == nil, "the stamps die with the instances")
assert(not Atlas.claim(3, {x = 0, y = 0, z = 0}))

-- Camera updates without a marker frame release the atlas while its world
-- is alive (a mission's resources must not outlive the mission in its GUI).
assert(Atlas.ensure("game_world") and Atlas.begin_frame(4))
for _ = 1, Atlas.IDLE_RELEASE_FRAMES do Atlas.draw("game_world", frame_for) end
assert(state.resource ~= nil, "released before the idle threshold")
local worlds_destroyed = 0
for _, call in ipairs(calls) do if call.name == "destroy_world" then worlds_destroyed = worlds_destroyed + 1 end end
assert(Atlas.draw("game_world", frame_for) == 0 and state.resource == nil and
    find("destroy_gui")[1] == "game_world", "an idle atlas must release")
local after_release = 0
for _, call in ipairs(calls) do if call.name == "destroy_world" then after_release = after_release + 1 end end
assert(after_release == worlds_destroyed + 1)
assert(Atlas.ensure("game_world") and Atlas.claim(5, {x = 0, y = 2, z = 0}), "rebuilds on the next marker")
-- A clocked atlas (the hand overlays) counts time, not draw calls: several
-- camera updates in one game frame keep showing its cells.
local now = 10
local clocked = Atlas.new({name = "overlay", log_tag = "OVERLAY", cell_width = 960, cell_height = 1080,
    columns = 4, rows = 2, clock = function() return now end})
clocked.configure(api)
assert(clocked.ensure("game_world") and clocked.CELL_WIDTH == 960 and clocked.WIDTH == 3840)
assert(clocked.claim(now, {x = 0, y = 0, z = 0}))
now = 10.011; assert(clocked.claim(now, {x = 0, y = 0, z = 0}))
for _ = 1, 6 do assert(clocked.draw("game_world", frame_for) == 1, "shown across repeated camera updates") end
now = 10.2
assert(clocked.draw("game_world", frame_for) == 0 and clocked.state.resource ~= nil, "stale after 0.1 s, not yet idle")
now = 11.5
assert(clocked.draw("game_world", frame_for) == 0 and clocked.state.resource == nil, "idle after a second")
-- A stamp from ahead of the clock makes every age negative, which without a
-- guard reads as "drawn just now" for ever: the cells last claimed would keep
-- showing and the resources would never be released, which is the crash on
-- mission unload this release exists to avoid (review, 18 September).
local backwards = Atlas.new({name = "overlay", log_tag = "OVERLAY", cell_width = 960, cell_height = 1080,
    columns = 4, rows = 2, clock = function() return now end})
backwards.configure(api)
assert(backwards.ensure("game_world") and backwards.claim(now, {x = 0, y = 0, z = 0}))
now = 11.6
assert(backwards.claim(now, {x = 0, y = 0, z = 0}))
assert(backwards.draw("game_world", frame_for) == 1, "shown at the time it was claimed")
now = 0.5
assert(backwards.draw("game_world", frame_for) == 0 and backwards.state.resource == nil,
    "a stamp from the future is stale and idle at once, not fresh for ever")
assert(backwards.ensure("game_world") and backwards.claim(now, {x = 0, y = 0, z = 0}),
    "and the next marker rebuilds it on the new clock")
-- The demand above the ceiling, which is the number the grid must be sized
-- from: the full line fires AT the ceiling and says nothing about how many
-- were wanted (18 September).
do
    local counted = Atlas.new({name = "demand", log_tag = "DEMAND", cell_width = 64,
        cell_height = 64, columns = 2, rows = 2, clock = function() return 1 end})
    counted.configure(api)
    assert(counted.ensure("game_world"))
    for i = 1, 4 do assert(counted.claim(1, {key = "k" .. i})) end
    assert(counted.state.peak_wanted == 4, "four fit in four cells")
    for i = 5, 20 do assert(not counted.claim(1, {key = "k" .. i})) end
    assert(counted.state.peak_wanted == 20,
        "the demand above the ceiling is counted: " .. counted.state.peak_wanted)
    assert(counted.state.wanted == 20)
    -- Reported below the ceiling too: a run that never overflows still has to
    -- say how close it came, and the first measurement run said nothing at
    -- all because nothing overflowed (18 September).
    local said = {}
    local quiet = Atlas.new({name = "quiet", log_tag = "QUIET", cell_width = 64,
        cell_height = 64, columns = 4, rows = 4, clock = function() return 1 end})
    quiet.configure(setmetatable({log = function(line) said[#said + 1] = line end}, {__index = api}))
    assert(quiet.ensure("game_world"))
    for i = 1, 8 do assert(quiet.claim(1, {key = "q" .. i})) end
    assert(#said > 0, "eight of sixteen cells said nothing about the demand")
    assert(said[#said]:find("wanted=8"), "the last line names the peak: " .. tostring(said[#said]))
    assert(said[#said]:find("cells=16"), "and the ceiling it is measured against")
end

-- A full atlas has to say WHICH display went missing. The hand overlays name
-- their anchors; a marker's anchor is a position, and the one run where this
-- fired said `anchor=?` (hook-arity-smoke-20260918).
assert(Atlas.claimant_name({key = "teammate_3"}) == "teammate_3", "a named anchor")
assert(Atlas.claimant_name({id = 7}) == "7", "an id will do")
assert(Atlas.claimant_name({slot = "slot_primary"}) == "slot_primary")
assert(Atlas.claimant_name(nil) == "?" and Atlas.claimant_name("x") == "?")
assert(Atlas.claimant_name({}) == "unnamed", "an anchor with nothing to say so")
local boxed = {position = {unbox = function() return "v(1,2,3)" end}}
assert(Atlas.claimant_name(boxed) == "at v(1,2,3)", "a marker says where it is")
assert(Atlas.claimant_name({position = {unbox = function() error("gone") end}}) == "unnamed",
    "an anchor whose position throws is still named, not an error")
assert(Atlas.claimant_name({x = 12.34, y = 56.78}) == "at 12.3,56.8", "a plain point")
-- The grid, and the measurement it was sized from. `extents ... boxed=1` in
-- the hub on 18 September: a marker's drawing needs 425 x 15 about the cell's
-- centre. The width is nearly spent; the height was eleven times what
-- anything used, so it was halved -- sixteen markers instead of eight, and
-- half the transparent quad on every marker, every frame.
assert(Atlas.CELLS == 16, "the atlas holds sixteen markers: " .. Atlas.CELLS)
assert(Atlas.CELL_WIDTH * 0.5 - Atlas.GUTTER >= 433,
    "a marker needs 425 px of half-width plus the gutter")
assert(Atlas.CELL_HEIGHT * 0.5 - Atlas.GUTTER >= 23,
    "a marker needs 15 px of half-height plus the gutter")
assert(Atlas.CELL_HEIGHT * 0.5 - Atlas.GUTTER >= 23 * 3,
    "and the margin over the measurement is thin: one quiet scene is thin evidence")
assert(Atlas.WIDTH <= 2048 and Atlas.HEIGHT <= 2048,
    "the atlas texture must not grow to buy cells")
print("marker_atlas.result=pass")
