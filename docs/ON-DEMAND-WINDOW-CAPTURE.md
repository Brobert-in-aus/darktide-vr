# On-demand desktop fallback capture

The physical viewer previously captured and converted the game window about
30 times per second even while displaying shared stereo images. Stereo and
native menu textures do not consume that window image. The gameplay reticle is
painted independently into its atlas, so it also does not require fresh desktop
captures during stereo.

The candidate replaces the always-running capture loop with a demand-controlled
worker. Startup and genuine window fallback enable capture. Shared stereo,
cached/generated stereo and native shared UI pause it. A condition variable
keeps the idle worker asleep; enabling it wakes it immediately. One capture
already in progress may finish after a pause request. Slow captures do not cause
a burst of catch-up calls. The last complete image remains available for fallback.

The main thread still checks source-window lifetime, and existing image ownership,
error publication, pointer overlays, shared UI, reticle painting and GPU fences
are retained. No GPU wait was removed. This does not change stereo eye histories
or claim to remove Virtual Desktop's own encoder work.

`openxr.theatre_capture_policy=on_demand` identifies the candidate. State changes
log `openxr.theatre_capture_active` and the attempt count; the final
`openxr.theatre_capture_attempts` lets a live test check that captures stop during
sustained stereo and resume for actual window fallback.

## Validation and deployment status

Windows x64 Release build succeeds for the viewer and focused tests in
`build/xr-window-capture-demand`. CTest `capture_worker` and
`window_capture_recovery` pass 2/2. The worker test covers an initially idle worker,
disabling while a callback is in flight, no further captures while paused,
resumption, idle shutdown and invalid cadence rejection. The existing window test
checks capture/recovery content and lifetime behavior. No game Lua changed.

Candidate viewer SHA-256:
`8957F0AD0E71808846445ED6C44A5C99ACAFCFCF0C7E29A13014CEB9F1E0AFD1`.
This records the original build, not a permanently reserved output path. Later
11 September direct-copy development rebuilt `build/xr-window-capture-demand`;
rebuild the focused `9856e00` source and verify its identity before the pending
physical comparison. Do not substitute that directory's current executable.
The benchmark viewer's source revision `a8061e8` and the pre-change HEAD have no
differences under src/core, src/bridge or src/xr; the new viewer change is isolated
to capture scheduling and counters.

Two physical Ready attempts failed, including a retry after explicitly waking
the Quest. No physical game session was launched on either failed check. Virtual
Desktop was not restarted. Normal proximity automation was restored afterward.
The candidate has not replaced the accepted installed viewer, and **no FPS gain
or worn visual acceptance is claimed**. Pending: matched physical-viewer control,
confirmed pause/resume counters, startup/fallback recovery and user visual check
when the headset stream is available. Continue independent development meanwhile.

Build/test receipts: ignored `artifacts/unattended/capture-demand-*-20260911.log`.
