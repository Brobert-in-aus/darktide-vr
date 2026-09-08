# Optional precise source polling

Status, 8 September 2026: built and checked offline, then deployed as a focused
viewer-only trial at 15:58 Brisbane. The uninterrupted timing-only baseline from
[the stage investigation](XR-FRAME-STAGE-TIMING.md) reproduced the sustained
decline and was saved before starting the comparison. The later producer-cadence
correction is not included in this trial. See the live checkpoint below.

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
That historical sample subsequently declined; see the
[runtime trace](VDXR-SUBMISSION-SLOWDOWN.md). Public VDXR
[initialization](https://github.com/mbucchia/VirtualDesktop-OpenXR/blob/main/virtualdesktop-openxr/instance.cpp)
calls its [high-precision timer setup](https://github.com/mbucchia/VirtualDesktop-OpenXR/blob/main/virtualdesktop-openxr/utils.h),
which requests high timer resolution and disables the window-occlusion timer
throttling policy. This further limits how representative the separate-process
standard-sleep benchmark is of a VDXR process; installed timing remains the
authority for this trial, not that isolated comparison.

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

## Live trial, 15:58 Brisbane

The original session ended after the sustained decline was captured. Its
launcher exited zero, restored temporary flags and removed its remaining owned
flat game process. Complete logs and final analysis are saved under
`artifacts/unattended/soloplay-sustained-baseline-20260908/`. Both device-health
collectors completed their 20-minute bounds and their owned logcat children are
gone. Both ETW sessions were stopped; no trace remains armed.

Default Ready passes in `precise-pair-wait-ready-20260908.json/.log`. Installed
46 Lua chunks compile, accepted capture/bootstrap hashes are unchanged, and
only the viewer executable was replaced through the deployment transaction.
Runtime source is the PR #53 candidate `ba91dcc`; it was built before commit,
so embedded revision metadata can precede that source commit. Its preserved
source matches that commit and SHA-256 is
`71FA143A0ED283934CDBC2526E353C6586D6A967F734345B4CDFBE1355071B53`.

Receipt: `artifacts/unattended/precise-pair-wait-live-deployment-20260908.json`.
Backup manifest:
`precise-pair-wait-live-backup-20260908/deployment-2bb666399f3f48c581d4aaddcd9025f2/manifest.json`
under the same directory. Recovery root is `build/windows-vs2022`. The saved
baseline executable hash is
`1A90F97FE597B811EA7A0463E34F0FFB38043CE1EA090B76EF628447CC7DA6D8`.

The usual launcher starts with `-SkipDeploymentSync -EnterPsykhanium
-EnableHudPanel -DlssGeneratedStereo` and process-local
`DTVR_XR_PRECISE_PAIR_WAIT=1`, restored in its shell's `finally`. Game PID 84828
starts 15:58:54, viewer PID 54364 starts 15:58:58, launcher session 94365. Log:
`artifacts/unattended/soloplay-precise-pair-wait-session-20260908.log`. Its normal
eight-hour deadline is approximately 23:58 Brisbane, subject to the user's
explicit stop instruction. No native, Lua, shader, SoloPlay or runtime setting
changed. No solo mission was launched.

Fresh Psykhanium pass at 05:59:58.383 UTC, stock rules at 05:59:59.058 and both
rigid hands ready at 05:59:59.340. At shared-ready 907 the viewer delivers
53.86 original + 53.86 generated pairs/s with zero interval fallback/reuse/pose
mismatch. A nearby 120-loop sample reports 695 poll sleeps averaging 0.991 ms,
5.761 ms whole source wait, 2.998 ms GPU-fence wait and 0.118 ms `xrEndFrame`.
Precise mode is active and failures are zero. Fresh rate is similar to the old
fresh baseline; sustained recurrence, rather than this initial rate, is the
next test. This is delivery/initialization evidence, not worn acceptance.

### Foreground interruption, observed 16:40 Brisbane

Both original processes remain alive. Generated delivery stopped at about
1,330 seconds of accumulated viewer active-loop time, before the earlier
baseline's slowdown onset. Producer health independently shows evaluations
stopping when `foreground` becomes zero (health sample 1,323). A brief later
foreground interval resumes evaluations and generated delivery, then both stop
again. Saved game settings still enable DLSS frame generation. This correlates
the interruption with focus; it does not identify which application caused it.

The 5–20 minute active-time bins average 53.77–53.82 original and generated
pairs/s, approximately 0.994 ms poll sleeps and 0.125–0.127 ms `xrEndFrame`.
Later background-only bins deliver roughly 77 original pairs/s and zero
generated pairs; they cannot establish sustained generated-mode performance.
The observational split is saved in
`artifacts/unattended/precise-pair-wait-interrupted-trend-20260908.json`.
Active-loop time excludes logging and is not exact wall-clock elapsed time.

A single focus-restoration attempt at 16:42 returned success but did not
persist; a subsequent read found a browser foreground and producer evaluations
still unchanged. Do not repeatedly steal desktop focus. Keep the session
available, continue offline work, and treat this sustained comparison as
interrupted until a sufficiently long foreground interval can be observed.
The precise wait is **not established as a slowdown fix**.
