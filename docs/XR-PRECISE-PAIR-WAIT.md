# Optional precise source polling

Status, 8 September 2026: built and checked offline, **not deployed**. The live
SoloPlay/Psykhanium session retains the timing-only viewer from
[the stage investigation](XR-FRAME-STAGE-TIMING.md). Preserve its uninterrupted
run to capture any recurrence of the sustained delivery decline.

## Evidence and limits

The source-availability loop requests `sleep_for(500us)` between fence/cadence
checks. In an isolated Windows x64 Release process, 2,000 alternating samples
after 100 warmup iterations measured:

| Wait | Mean | Median | 95th percentile | Maximum |
| --- | ---: | ---: | ---: | ---: |
| Existing standard sleep | 14.5204 ms | 15.1395 ms | 15.6776 ms | 16.2436 ms |
| High-resolution waitable timer | 1.02514 ms | 1.0269 ms | 1.0414 ms | 1.406 ms |

These measurements use the actual candidate helper and alternate order every
iteration. No timer-resolution, priority, graphics, runtime or headset setting
was changed. They are scheduler observations in a separate process, not a
controlled in-game speedup or proof of the earlier slowdown's cause. The live
process loads a runtime and has different scheduling conditions. At about
31 minutes it still delivers roughly 53 original + 53 generated pairs/s.

Microsoft documents that applications without their own timer-resolution
request may retain the default resolution on recent Windows; Windows 11 also
has an occlusion caveat. The high-resolution waitable timer flag is supported
from Windows 10 version 1803. Relative due times use negative 100 ns units.
Actual precision still depends on hardware and scheduling:
[timeBeginPeriod](https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod),
[CreateWaitableTimerExW](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-createwaitabletimerexw),
[SetWaitableTimerEx](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-setwaitabletimerex).

## Candidate behavior

Only `DTVR_XR_PRECISE_PAIR_WAIT=1` in the launch process enables the new wait.
Unset, zero and other values retain the existing standard sleep. One auto-reset
high-resolution timer belongs to the viewer's frame thread. Every poll arms a
single relative 500 us deadline. It makes no periodic or system-wake request,
uses no callback and does not change global/process timer resolution.

Creation, arm or wait failure is explicit. The helper closes a failed timer once
and uses ordinary sleeps thereafter, including the failed poll, so failure
cannot create a busy loop. The OS wait has a 100 ms failure bound. Normal
tracking service, source selection, original/generated ordering, stale fallback
and outer source deadlines are unchanged. This is an optional pacing candidate,
not a change to game input, combat rules or rendering geometry.

Every 120 loops the additional `pair_poll_sleep` stage records actual poll call
count and mean/max duration. It is contained within `pair_wait`, which is itself
contained within `active_loop`; these durations must not be added together.
The log records requested/actual wait mode and cumulative failures. A window
that changes to fallback is labeled `mixed_failure` and excluded from grouped
analysis. Standard, precise and legacy/unreported mode windows are kept apart.
For old logs, missing poll instrumentation remains unobserved, distinct from a
new window with zero poll calls.

## Validation and next live comparison

Windows x64 Release harness and test build pass in `build/xr-frame-stage-timing`.
Four focused CTests pass in 0.34 s: `pair_poll_wait`, `frame_stage_timing`,
`xr_frame_stage_analysis` and `xr_harness_help`. The wait tests cover real repeated
timer use and injected creation/arm/wait failures, retirement, fallback and
ownership. Five Python cases include mode separation and optional observation
coverage. No fragile performance threshold is used as a unit-test assertion.

Run the optional native timing distribution with:

```powershell
& 'build/xr-frame-stage-timing/tests/xr_harness/Release/darktidevr-pair-poll-wait-tests.exe' --benchmark
```

Evidence is under `artifacts/unattended/xr-precise-pair-wait-{build,tests,benchmark}-20260908.log`.
The separate preliminary experiment is in `short-wait-benchmark-20260908/`.

Before any live comparison, save the uninterrupted baseline and correlate the
source wait, runtime wait, GPU-fence wait, producer rate and headset health.
Use default Ready before a new session and a transactional viewer-only update.
Start with the default standard path to measure actual poll durations in the
runtime process; compare the precise path under matching presentation/settings.
Keep native capture, Lua, shaders and SoloPlay settings fixed. Record fresh Lua
and shared-stereo readiness, source/generated delivery, fallback and pose
mismatches; compare sustained behavior, not just initial FPS. Restore the launch
process environment afterwards. Worn smoothness and mission acceptance remain
separate user observations.
