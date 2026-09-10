# Distinct-image gaps and repeat bursts

Average delivery FPS can hide clusters of repeated images. The viewer now adds
bounded, allocation-free cadence counters to its existing 120-frame report.
After successful `xrEndFrame`, it observes whether a stereo world image was
submitted and whether the original/generated distinct-image counters advanced.

The report includes observed distinct/repeated slots, repeat runs ended by a
distinct image, the longest repeat run observed, and the largest interval
between distinct images using `predictedDisplayTime`. This is submitted-image
cadence on the runtime timeline, not physical display latency, GPU timestamps,
or a percentile. Actual headset behavior still needs a renderable physical
session and user-worn acceptance.

Continuity breaks at fallback/no world submission, gameplay-generation changes,
and non-increasing runtime timestamps. Report resets preserve an unfinished
repeat run and the previous distinct timestamp. Thus a run can start before a
report window and finish inside it; `repeat_run_peak` is its full observed
length, while `cadence_repeats` counts only slots in that window. Clock breaks
are counted instead of generating invalid gaps.

The simulator analyzer uses the same generation and warm-up selection as its
FPS summary. It reports cadence coverage separately; absent fields in older
captures remain unknown. Partial, negative or nonfinite records are rejected.
A window with no observed distinct gap cannot claim a maximum gap.

Windows x64 viewer build and the focused `delivery_cadence` CTest pass. The
sequence checks cover a burst spanning reports, fallback, clock regression and
a valid signed-timeline zero crossing. All seven Python analyzer tests pass,
including warm-up selection, legacy absence and malformed cadence rejection.
Consumer candidate SHA-256:
`987C5909AEB326067C7C213DF8D4701BEA74329F6E6108747AC753D11A1D3827`.

The 120 Hz/cap120 FG mission capture reports 119.86 distinct pairs/s across
110.00 analyzed seconds. Its 16 repeated images form 16 isolated one-slot runs;
the longest run is one. There are no clock breaks. The largest predicted-time
gap is 18.90 ms, but even windows without repeats reach roughly 14–15 ms.
Inspection confirms that simulator `3C3F41C3...` predicts `now + period` after
its timer wakes, so host wake jitter enters this timeline. Do not interpret that
maximum as measured physical stutter. A separate fixed-refresh prediction
experiment is needed before comparing timeline-gap values across runtimes.

Clean exit, zero pose mismatches and exact restoration pass. Local evidence:
`synthetic-solo-cadence-120-a-20260910` under ignored artifacts. This single
run's higher average than earlier controls does not establish a telemetry or
copy-change performance gain.
