# Viewer frame-stage timing

8 September 2026. During the unchanged SoloPlay Psykhanium session, producer
health still reports about 59-60 original frames/s while viewer delivery falls
to roughly 30-38 fresh original/generated pairs/s. Captured evidence is under
`artifacts/unattended/soloplay-idle-slowdown-20260908/`. This is an uncontrolled
idle-session observation, not a graphics-settings comparison or a diagnosed
cause. Quest Inventory reports awake; producer windows have no focus transition
or original failure; viewer intervals have no fallback or pose mismatch. A GPU
snapshot has no active thermal/power throttle flag; it is not a temperature
history. The old viewer only logs individual waits of at least 100 ms, which
cannot distinguish ordinary but costly per-frame waits.

The timing candidate adds one `openxr.frame_stage_timing` row at the existing
120-loop report cadence. It uses the monotonic clock and reports call count,
mean and maximum observed wall duration for:

- Active loop, from its existing start through final event polling, excluding
  periodic logging and outer termination checks.
- Pair availability wait, including its tracking/event polling.
- `xrWaitFrame`, `xrBeginFrame` and the subsequent tracking update.
- Swapchain acquire/wait calls, with their actual call count across images.
- Viewer GPU-fence wait and `xrEndFrame`.

The row also identifies the completed-frame index and the latest runtime
display period. That period is an endpoint sample, not a window average.
Unobserved calls omit durations; a measured zero is retained. Invalid/nonfinite
durations and aggregate overflow are counted and excluded from the aggregates.
Windows reset after reporting. Final incomplete windows are not reported.

These are CPU-observed call durations, **not GPU timestamps, display latency or
frame-time percentiles**. Active-loop time contains the other stages; do not add
it to them. The named stages do not exhaust all loop work, so their residual is
unattributed. Existing waits, fences, image selection, poses and submission are
unchanged. A live trace is still needed to locate the current delay.

Windows x64 Release harness and the focused timing test build in the isolated
`build/xr-frame-stage-timing/` directory. This leaves the running viewer binary
untouched. The test passes (0.03 s; CTest total 0.06 s), covering fractional
means, multiple image waits, absent calls, measured zero, invalid/overflow input,
window metadata and independent reset. Build/configure logs are
`artifacts/unattended/xr-frame-stage-{configure,build}-20260908.log`.
Source under `src/core`, `src/bridge` and `src/xr` was unchanged from accepted
`23345e5` before this timing patch. No unrelated viewer change is needed.

## Live timing deployment

At 14:48 Brisbane, after graceful closure of PID 1976 and successful Ready,
the viewer alone was replaced transactionally. Receipt:
`artifacts/unattended/xr-frame-stage-deployment-20260908.json`; backup manifest:
`xr-frame-stage-viewer-backup-20260908/deployment-3e28de8239de4c0daebc5efb96969dfc/manifest.json`
under the same directory. Recovery root is `build/windows-vs2022`, not the game
installation. An initial broader-root request was rejected before writing
because its backup would have been inside that root; the narrower build root
correctly places the saved backup outside the deployment root.

New Darktide PID 120404, viewer PID 76636, launcher session 72645. Log:
`artifacts/unattended/soloplay-frame-stage-session-20260908.log`. Game started
14:48:16 Brisbane; launcher deadline is approximately 22:48 Brisbane. Psykhanium
passes at 04:49:34 UTC, then stock online-rule and rigid-hand readiness. Installed
46 Lua chunks compile and native/bootstrap hashes match the accepted deployment.
SoloPlay settings, Lua and shaders are unchanged.

At about 1,810 shared-ready frames the viewer delivers 53.48 original plus
53.48 generated pairs/s with zero interval fallback/reuse/pose mismatch. A nearby
120-loop timing window reports about 9.38 ms active loop, 5.74 ms source wait,
0.026 ms OpenXR frame wait, 3.20 ms GPU-fence wait and an 8.333 ms latest display
period. No invalid timing samples. Startup/menu windows are separate conditions.
This is a fresh-session baseline; restarting improved delivery, but the cause
of the earlier sustained decline remains undiagnosed. Continue observing for
recurrence rather than treating this restart or instrumentation as a fix.
