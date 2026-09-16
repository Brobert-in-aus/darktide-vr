-- Per-frame cost of the mod's own Lua, by section (16 September 2026: the
-- day added seven per-frame samplers to the input and draw paths and nothing
-- measured any of them; every earlier performance pass was native or GPU).
-- Opt-in through darktidevr_frame_profile.flag; players never have it. Pure
-- aggregation here, engine side below.
--
-- Sections are timed with the native module's QueryPerformanceCounter
-- (dtvr_qpc_ticks / dtvr_qpc_frequency, which the render-timing diagnostic
-- already uses). Not Application.time_since_launch: that is frame-quantised,
-- and the first Hub run with it reported every section as exactly zero. Not
-- os.clock either, which is a millisecond on Windows. When the flag is off a
-- section costs one branch and a tail call.
local Profile = {}

Profile.FLAG = "./../mods/darktidevr/darktidevr_frame_profile.flag"
Profile.REPORT_SECONDS = 5
Profile.REPORT_LINES = 40
-- Enough rows for the outer sections and every nested one; with the cut at
-- twelve, the haptics sub-sections fell off the report and read as
-- "unaccounted" (hub-haptics3).
Profile.TOP = 40

-- A fresh accumulator. Pure.
function Profile.new()
    return {sections = {}, order = {}, frames = 0, top = 0}
end

-- Record one timed call of a section. Pure. A nested section (one timed
-- inside another) keeps its own row but is left out of the total, which
-- would otherwise count its time twice; until hub-marker1 every total with
-- the haptics sub-sections in it did.
function Profile.add(acc, name, seconds, nested)
    if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 then return end
    if not nested then acc.top = acc.top + seconds end
    local entry = acc.sections[name]
    if not entry then
        entry = {name = name, calls = 0, total = 0, max = 0}
        acc.sections[name] = entry
        acc.order[#acc.order + 1] = name
    end
    entry.calls = entry.calls + 1
    entry.total = entry.total + seconds
    if seconds > entry.max then entry.max = seconds end
end

-- One frame has passed. Pure.
function Profile.frame(acc)
    acc.frames = acc.frames + 1
end

-- The sections by total cost, highest first, with per-frame and per-call
-- figures in the units a log line wants (ms per frame, us per call). Pure.
function Profile.report(acc, top)
    local rows = {}
    for _, name in ipairs(acc.order) do
        local e = acc.sections[name]
        rows[#rows + 1] = {
            name = name, calls = e.calls,
            total_ms = e.total * 1000,
            per_frame_ms = acc.frames > 0 and e.total * 1000 / acc.frames or 0,
            mean_us = e.calls > 0 and e.total * 1e6 / e.calls or 0,
            max_us = e.max * 1e6,
        }
    end
    table.sort(rows, function(a, b)
        if a.total_ms ~= b.total_ms then return a.total_ms > b.total_ms end
        return a.name < b.name
    end)
    -- The total is the top-level sections only; the rows still list every
    -- section, nested ones included.
    local all = acc.top * 1000
    local limit = top or Profile.TOP
    if #rows > limit then
        local kept = {}
        for i = 1, limit do kept[i] = rows[i] end
        rows = kept
    end
    return rows, {frames = acc.frames, total_ms = all,
        per_frame_ms = acc.frames > 0 and all / acc.frames or 0}
end

-- Engine side.
-- ticks() returns the counter, frequency() its rate per second; both come
-- from the installer, since the native module handle is a local there.
function Profile.install(mod, ticks, frequency)
    local api = {}
    local acc = Profile.new()
    local enabled, poll, reports, next_report = false, 0, 0, nil
    local clock, per_tick = ticks, nil
    local function measure()
        local ok, hz = pcall(frequency)
        if ok and type(hz) == "number" and hz > 0 then per_tick = 1 / hz; return true end
        return false
    end

    local function flag()
        poll = poll - 1
        if poll > 0 then return enabled end
        poll = 300
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Profile.FLAG, "r")
        if not file then enabled = false; return false end
        local value = file:read("*all"); file:close()
        enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil and
            clock ~= nil and (per_tick ~= nil or measure())
        return enabled
    end

    function api.enabled() return enabled end

    -- Run fn with its arguments, timing it under name when the profile is
    -- on. Up to four results are returned, which covers every call site;
    -- more would need a table per call and this must not allocate.
    -- `depth` is how many sections are open, so a section that closes
    -- inside another is recorded as nested. An error thrown through a
    -- section leaves it open; frame() resets the depth, so the damage is
    -- the rest of that frame.
    local depth = 0
    function api.section(name, fn, a, b, c, d, e, f, g, h)
        if not enabled then return fn(a, b, c, d, e, f, g, h) end
        depth = depth + 1
        local started = clock()
        local r1, r2, r3, r4 = fn(a, b, c, d, e, f, g, h)
        local seconds = (clock() - started) * per_tick
        depth = depth - 1
        Profile.add(acc, name, seconds, depth > 0)
        return r1, r2, r3, r4
    end

    -- For a body too large to pass as one call (a whole hook): begin returns
    -- a mark, finish records the section. A path that leaves without finish
    -- records nothing for that call, which is why callers put finish on every
    -- return. Off, begin returns nil and finish is one branch.
    function api.begin()
        if not enabled then return nil end
        depth = depth + 1
        return clock()
    end
    function api.finish(name, mark)
        if mark == nil or not enabled then return end
        local seconds = (clock() - mark) * per_tick
        depth = depth - 1
        Profile.add(acc, name, seconds, depth > 0)
    end

    -- Once per input frame. Polls the flag, counts the frame, and every
    -- REPORT_SECONDS logs the top sections; bounded to REPORT_LINES reports a
    -- session, so a forgotten flag cannot fill a log.
    function api.frame(t)
        local was = enabled
        depth = 0
        flag()
        if not enabled then
            if was then acc = Profile.new(); next_report = nil end
            return
        end
        if not was then
            acc = Profile.new(); next_report = nil
            mod:info("DARKTIDEVR_FRAME_PROFILE enabled clock=qpc hz=%.0f", per_tick and 1 / per_tick or 0)
        end
        Profile.frame(acc)
        if type(t) ~= "number" then return end
        next_report = next_report or (t + Profile.REPORT_SECONDS)
        if t < next_report or reports >= Profile.REPORT_LINES then return end
        next_report, reports = t + Profile.REPORT_SECONDS, reports + 1
        local rows, summary = Profile.report(acc)
        mod:info("DARKTIDEVR_FRAME_PROFILE report=%d frames=%d mod_ms_per_frame=%.3f sections=%d",
            reports, summary.frames, summary.per_frame_ms, #acc.order)
        for _, row in ipairs(rows) do
            mod:info("DARKTIDEVR_FRAME_PROFILE section=%s ms_per_frame=%.4f calls=%d mean_us=%.1f max_us=%.1f",
                row.name, row.per_frame_ms, row.calls, row.mean_us, row.max_us)
        end
        -- Each report is a fresh window, so a change shows in the next one.
        acc = Profile.new()
    end

    return api
end

return Profile
