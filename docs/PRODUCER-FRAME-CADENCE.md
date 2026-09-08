# Source cadence from producer metadata

Status, 8 September 2026: Windows x64 Release candidate built, five focused
checks pass, **not deployed**. The uninterrupted SoloPlay session still uses
the earlier timing-only viewer. This correction is separate from the optional
[precise poll wait](XR-PRECISE-PAIR-WAIT.md), which remains off by default.

## Confirmed source error

The viewer previously passed its current `predictedDisplayTime` to the source
cadence estimator when ingesting an original. A viewer that consumes only every
second publication from a 60 Hz producer therefore estimates a 30 Hz source.
At a 120 Hz display, that estimate schedules the matching original two display
slots after its generated image instead of one. Every third publication becomes
an apparent 20 Hz source and a three-slot delay. This can extend a delay after
missed source images; whether it caused the observed September 8 sustained
slowdown remains unproven.

The corrected estimator uses the original transport's existing producer
`tick_ms` and publication `sequence`. Elapsed producer time is divided by the
sequence gap before applying the existing 3:1 smoothing. Runtime prediction
time is used only for the resulting display deadline; absolute timestamps from
these two clocks are never mixed. The transport layout and native producer are
unchanged. The sequence counts successfully recorded original publications,
not arbitrary game frames, so the estimate describes that source stream.

Missing timestamps/sequences, clock rollback, sequence rollback and gaps of at
least 250 ms reset the estimate. Identical metadata is ignored. Repeated coarse
ticks retain the earlier anchor and all intervening sequence intervals.
Multiplication occurs only after bounding elapsed time below 250 ms. Existing
runtime slot rounding and the one-slot default remain unchanged.

The existing producer timestamp is coarse: Microsoft's
[GetTickCount64 documentation](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-gettickcount64)
describes typical 10–16 ms resolution. Smoothing and sequence normalization
reduce that quantization's effect, but this is not a per-frame high-resolution
timestamp or GPU completion time. Adding a new producer clock/transport is not
part of this focused correction.

## Validation

The actual cadence helper is exercised against a 60 Hz source consumed at
strides of one, two and three, preserving its roughly 16.67 ms source period and
one 8.333 ms display slot. A true 30 Hz producer retains roughly 33.33 ms and two
slots. Checks also cover duplicate/coarse ticks, loading gaps, clock/sequence
rollback, missing time, 15.625 ms quantization and genuine slowdown/recovery.
These are deterministic source/consumer fixtures, not synthetic headset input.

Release harness and generated-frame-state test builds pass in
`build/xr-frame-stage-timing`. Five focused CTests pass in 0.37 s:
`generated_frame_state`, `pair_poll_wait`, `frame_stage_timing`,
`xr_frame_stage_analysis`, and `xr_harness_help`. Transport tests use isolated
mapping names and do not replace the live game's mappings. Evidence:
`artifacts/unattended/producer-frame-cadence-{build,test-build,tests}-20260908.log`.

Live comparison must retain the stock input/weapon/SoloPlay/shader deployment,
use default Ready for a new session and change only the viewer transactionally.
Keep the precise wait off when isolating this cadence correction. Compare
producer original rate with ingested/submitted originals, generated ordering,
poll/runtime/GPU waits and sustained recovery after natural stalls. Worn
smoothness and in-mission gameplay acceptance remain pending user observation.

## Read-only producer observation

A 60-second reader of the existing original metadata mapping deliberately
requested 30 ms between reads, without opening an XR session, signaling fences
or writing transport state. It observed 1,927 new samples: 636 one-sequence gaps,
1,286 two-sequence gaps and four three-sequence gaps (plus the initial anchor).
After 16 warmup samples the candidate estimated a mean 18.682 ms source period;
publication endpoints measured 53.709/s. Thus real coarse producer metadata
retains the source rate when this separate reader skips publications. This is
metadata validation, not GPU completion or a deployed viewer speedup. Evidence:
`artifacts/unattended/producer-cadence-probe-20260908/{capture.log,summary.json}`.
