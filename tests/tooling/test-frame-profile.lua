-- The frame profiler's aggregation: per-frame and per-call figures, ordering,
-- the top-N cut, and that bad samples are ignored.
local Profile = dofile(assert(arg[1]))
local function near(a, b, e, m)
    assert(math.abs(a - b) < (e or 1e-9), (m or 'mismatch') .. ': ' .. tostring(a) .. ' vs ' .. tostring(b))
end

local acc = Profile.new()
-- Two frames: a cheap section called twice a frame, a dear one once a frame.
for _ = 1, 2 do
    Profile.add(acc, 'cheap', 0.0001)
    Profile.add(acc, 'cheap', 0.0003)
    Profile.add(acc, 'dear', 0.002)
    Profile.frame(acc)
end
local rows, summary = Profile.report(acc)
assert(summary.frames == 2)
near(summary.total_ms, 4.8, 1e-9, 'all sections, in ms')
near(summary.per_frame_ms, 2.4, 1e-9)
assert(rows[1].name == 'dear' and rows[2].name == 'cheap', 'highest total first')
near(rows[1].per_frame_ms, 2.0); near(rows[1].mean_us, 2000); near(rows[1].max_us, 2000)
assert(rows[1].calls == 2)
near(rows[2].per_frame_ms, 0.4); near(rows[2].mean_us, 200); near(rows[2].max_us, 300)
assert(rows[2].calls == 4)

-- Bad samples are dropped rather than poisoning a mean.
Profile.add(acc, 'cheap', 0 / 0); Profile.add(acc, 'cheap', -1); Profile.add(acc, 'cheap', nil)
assert(acc.sections.cheap.calls == 4)

-- The top-N cut keeps the dearest and the summary still counts everything.
local many = Profile.new()
for i = 1, 20 do Profile.add(many, 's' .. i, i * 1e-4) end
Profile.frame(many)
local top, all = Profile.report(many, 3)
assert(#top == 3 and top[1].name == 's20' and top[3].name == 's18')
near(all.total_ms, 21.0, 1e-9, 'the cut does not change the total')

-- No frames yet: per-frame figures are zero, not a division by zero.
local empty = Profile.new()
Profile.add(empty, 'x', 0.001)
local r0, s0 = Profile.report(empty)
assert(s0.per_frame_ms == 0 and r0[1].per_frame_ms == 0)

-- A tie in total is broken by name, so the order is stable between reports.
local tie = Profile.new()
Profile.add(tie, 'b', 0.001); Profile.add(tie, 'a', 0.001); Profile.frame(tie)
local tr = Profile.report(tie)
assert(tr[1].name == 'a' and tr[2].name == 'b')

assert(Profile.REPORT_LINES <= 60, 'bounded, so a forgotten flag cannot fill a log')
print('frame_profile=pass figures ordering top_cut bad_samples no_frames stable')
