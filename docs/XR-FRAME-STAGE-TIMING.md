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

Deployment and live trace are pending. Keep SoloPlay, native capture, bootstrap,
Lua, shaders and accepted weapon presentation intact. Before replacing the
viewer: close the game gracefully, wait for launcher cleanup, run Ready, and
save a one-file deployment transaction for the viewer executable.
