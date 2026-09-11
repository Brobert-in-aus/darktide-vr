# Simulator viewer window-capture control

The [mirror contract](DESKTOP-MIRROR-PERFORMANCE-CONTRACT.md) separates four
desktop costs: game mirror copies, DXGI presentation, Virtual Desktop encoding
and the XR viewer's own capture of the game window. The
[on-demand capture candidate](ON-DEMAND-WINDOW-CAPTURE.md) addresses only the
last one, and its comparison was blocked because the synthetic benchmark never
captured the desktop: the consumer starts before the game window exists, and
the viewer previously required the capture window at startup.

## Viewer change

`--capture-window-deferred` lets the viewer start without the window. The flat
capture swapchain and upload buffer are still created at startup; source
acquisition is retried from the frame loop every 500 ms until exactly one
visible window matches the title. A failed attempt releases any partially
constructed worker before the window object, so no capture thread can outlive
its source. Acquisition logs `openxr.capture_window=pending reason=...` once and
`openxr.capture_window=acquired frame=N` on success. Source-window loss still
ends the session cleanly, unchanged from the physical launcher's behaviour.

`--capture-window-policy on_demand|always` selects the capture worker policy.
`on_demand` remains the default and matches the existing candidate: captures
pause while shared stereo, cached/generated stereo or native UI supply the
image. `always` keeps the legacy 30 Hz capture loop running for a same-binary
cost comparison only; it is not a proposed default. Both options require
`--capture-window-title`. The final summary adds
`openxr.theatre_capture_window=acquired|pending|none`.

## Benchmark change

`run-synthetic-framegen-benchmark.ps1 -DesktopWindowCapture Off|OnDemand|Always`
passes the deferred capture arguments to the consumer, records
`desktop_window_capture` and `desktop_window_capture_policy` in the receipt,
and fails the run unless the requested policy, deferred acquisition and final
acquired state all appear in the consumer log. An `Off` control fails if any
capture policy line appears. `analyze-synthetic-framegen.py` adds a
`desktop_window_capture` block with policy, acquisition frame, attempt, failure
and update totals and the number of on-demand activity transitions. These are
viewer counters; they do not measure game mirror rendering or VD encoding.

## Shutdown defect found by the first capture trial

The first always-policy trial ran its full 90 seconds, then failed with
`Consumer did not stop cleanly`: the consumer logged
`openxr.capture_window=closed session_exit=clean` and never reached the summary.
An offline reproduction with a Character Map window on the simulator runtime
hung with both policies whenever the worker was enabled at shutdown.

Cause: `CaptureWorker::run` used the predicate return of
`condition_variable_any::wait(lock, stop_token, predicate)` as its loop
condition. That call returns the predicate, not the stop state, so an enabled
worker kept capturing after the stop request and the joining destructor never
returned. The on-demand physical viewer only avoided this because stereo had
already paused the worker when the game window closed; closing the game while
flat fallback capture is active would have hung it too. The loop now checks the
stop token itself. `capture_worker_tests` adds enabled-shutdown cases with a
trivial and a slow callback under the existing 10-second test timeout.

## Validation

Windows x64 Release build in `build/focused-simulator-window-capture`
(headset tests off). CTest `capture_worker`, `window_capture_recovery` and
`xr_harness_help` pass 3/3 after the worker fix. The viewer rejects the new
options without a title. An offline simulator reproduction that closes the
captured Character Map window exits with `result=pass` under both policies.
The PowerShell runner parses in Windows PowerShell 5.1 and the analyzer
compiles. Build/test logs: ignored `artifacts/unattended/window-capture-build*-20260911.log`.

Physical Ready failed before the trials (`openxr.system=hmd-unavailable`
through VDXR with the Quest awake), recorded in
`artifacts/unattended/window-capture-ready-20260911.{log,json}`; these are
authorized simulator fallback measurements, not headset results.

## 11 September simulator trials

Native ring trial DLL `D4AB131A...` with the ring flag enabled, accepted
installed native `FCCDD0DE...` restored after each run, simulator runtime
`CB8B5202...`, 2496x2688 per eye, Quality DLSS, FG off, unlimited cap, 120 Hz,
13 workers, stationary `cm_archives` difficulty 3, HUD/menu enabled, preview
off. Ninety seconds after workload readiness, ten seconds warm-up excluded.
The viewer is the focused build of this branch: `1DC6B93C...` before the
worker fix (a1, b) and `E8154112...` after it (b2, c, a2).

| Run | Viewer | Capture | Distinct native FPS | Analysed s | Capture attempts | Outcome |
| --- | --- | --- | ---: | ---: | ---: | --- |
| a1 | 1DC6B93C | off | 90.84609 | 77.93 | none | clean exit, restored, 0 mismatches |
| b | 1DC6B93C | always | not analysed | 113 live samples | acquired frame 2103 | full run, then the consumer hung on the worker join after the game window closed and was killed at the 15 s limit; files restored |
| b2 | E8154112 | always | 89.33027 | 80.60 | 2563, 1 failure (closed window) | clean exit, restored, 0 mismatches; runner regex defect fixed afterwards, analysed manually |
| c | E8154112 | on_demand | 91.65312 | 78.56 | 627 before stereo, then paused (1 transition, 0 failures) | clean exit, restored, 0 mismatches |
| a2 | E8154112 | off | 91.57163 | 79.94 | none | clean exit, restored, 0 mismatches |

GPU engine sampling observed no Streamer activity above 0.1% in any valid
sample (30/1, 27/0, 26/1 and 27/1 sampled/unavailable records for a1, b2, c
and a2); incomplete counter coverage means this is not proof of zero encoding.

Reading: on the same fixed viewer, always-on capture delivered 89.33 FPS
against 91.65 with on-demand capture and 91.57 with no capture, about 2.3 FPS
or 2.5% below both. On-demand and off are indistinguishable. The on-demand
worker captured only during the flat loading/menu phase (627 attempts) and
never during stereo. A single run per arm and the known run-to-run drift of
about 1 FPS make this a small, consistent signal, not a precise cost. It
measures the viewer's GDI capture and conversion only; game mirror rendering
and VD encoding were not varied, and the physical viewer's cost under active
VD streaming remains unmeasured.
No worn acceptance or physical headset claim is made; the on-demand policy
remains the candidate default and the always policy exists only for controls.

Evidence: ignored `artifacts/unattended/synthetic-window-capture-{a1-off,b-always,b2-always,c-ondemand,a2-off}-20260911`
and the matching `window-capture-*-run-20260911.log` files. Proximity
automation was restored after every run.
