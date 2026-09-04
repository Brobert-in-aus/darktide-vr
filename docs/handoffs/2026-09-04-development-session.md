# Development session — 2026-09-04

## Current work

Branch: `dev/2026-09-04-hand-validation`, based on `06fd879`.
The session inherited uncommitted rigid-hand anatomical rotation, calibrated
wrist placement, a 55-degree inspection camera and their source/test updates.
The unrelated untracked image remains untouched.

The user is at the desk and prefers direct headset checks for hand alignment
and visual acceptance. Use real tracking for those checks; do not substitute
synthetic movement. This preference is also recorded in `AGENTS.md`.

## Preflight and validation

The first ADB check found no devices. A subsequent check found exactly one
authorized Quest 3, awake. Virtual Desktop Streamer was running and its VDXR
manifest existed. The proximity helper was run with `-Action Disable`, then
`-Action Status`. The renderable OpenXR smoke submitted 120/120 frames.
The fresh preflight report is
`artifacts/unattended/preflight-20260904T054916Z.json`.

Commands run successfully (CMake/CTest used the Visual Studio 2022 bundled
executables):

```powershell
tools\quest\set-proximity-override.ps1 -Action Disable
tools\quest\set-proximity-override.ps1 -Action Status
build\windows-vs2022\tests\xr_harness\Debug\darktidevr-xr-harness.exe --frames 30 --debug-layer --require-openxr --require-rendering --xr-frames 120
tools\stereo\test-darktide-lua-source.ps1
cmake --build build/windows-vs2022 --config Release --target darktidevr-synthetic-head-tests
ctest --test-dir build/windows-vs2022 -C Release -R '^synthetic_head_path$' --output-on-failure
tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 120
cmake --build build/windows-vs2022 --config Release --target darktidevr-xr-harness
git diff --check
```

The Lua gate passed with 198/198 file-scope locals and four parsed modules.
The rebuilt synthetic-head test passed.

## Runtime observations

An initial 150-second synthetic-body/weapon-matrix run synchronized the pending
Lua changes and reached gameplay. The fresh console logged
`DARKTIDEVR_IK rigid_hands=ready geometry=one_sided_profile_roots` at 05:51:33
UTC. Harness telemetry advanced `shared_ready` to 567, with one startup
pair-pose mismatch. The user confirmed arrival in the Psykhanium but could not
inspect alignment because synthetic poses owned the controls.

That run was deliberately interrupted to switch to real tracking. Its exit
code -1 is an interruption, not a successful completed acceptance run. The
wrapper restored temporary flags and closed its owned game process.

The first real-tracking relaunch failed because Windows denied foreground
activation of the Fatshark launcher. Cleanup closed the late-starting owned
game. The next attempt uses `-ManualLauncherPlay` so the user can press Play:

```powershell
tools\stereo\start-darktide-vr.ps1 -DurationSeconds 28800 -GameStartTimeoutSeconds 600 -EnterPsykhanium -SkipDeploymentSync -ManualLauncherPlay
```

Its output is captured in
`artifacts/unattended/manual-hands-20260904-retry.log`.
This real-tracking session reached gameplay and logged rigid hands ready at
05:53:54 UTC. The process command line contains no synthetic-control arguments.
Telemetry advanced `shared_ready` past 2,000 at approximately 60 fresh pairs/s,
with zero reused frames and one startup pair-pose mismatch.
Worn alignment acceptance is pending. Keep the session running for the user's
checks. No Mac-only validation is required for these Windows/Lua changes.

## Launcher transition fix

The Play helper now checks for a newly started game at the exact configured
path before attempting input. If activation/clicking throws, it allows up to
five seconds, bounded by the launch deadline, for that authenticated process
to appear. A successful transition returns without another click. Otherwise
the original exception is preserved. This prevents a manual Play press or a
retained launch request racing activation from being mislabeled as failure
and causing the wrapper to close the healthy game.

The new `launcher_play_transition` CTest extracts only the relevant PowerShell
functions and uses fake process and input implementations. Six cases cover
wrong-path/older process rejection, a game already starting before input, a
game appearing after activation failure, preserved failure when no valid game
appears, and a delivered click without falsely claiming game startup. It
executes no native input and does not interrupt the manual session.

Additional validation passed:

```powershell
tests\launcher\validate-play-transition.ps1
tools\stereo\test-darktide-lua-source.ps1
cmake --preset windows-vs2022
ctest --test-dir build/windows-vs2022 -C Release -R '^launcher_play_transition$' --output-on-failure
```

The fix has not yet been exercised in another real launch; preserve the live
session until the user's visual checks are complete.

## First worn observations and crosshair fix

The user reported that the right glove is good. Preserve its alignment. The
left glove is too far right at neutral and moves irregularly during rotation;
the movement does not look like a simple fixed offset or orbit. World markers
are misaligned between eyes, and the crosshair flickers.

The first manual log contains repeated left position-tracking loss (flags 3)
while the right remains fully tracked (flags 15), interspersed with left
reacquisition. Both controllers also lose position tracking at other times.
The Lua hold-last-pose behavior can explain irregular freeze/reacquire motion,
but the remaining left offset is not yet diagnosed. Ask for a check with the
left controller clearly visible to the headset before changing calibration.

That session exited when its captured game window closed, with 29,558 fresh
pairs, zero reused frames, one startup pair-pose mismatch, 12 window-capture
failures and one pair-driven timeout. It logged 1,589 reticle frames. All
synthetic counters were zero. The readback attempt after its exit was stopped
without captures. The temporary body-IK trace flag was restored to disabled.

The reticle consumer incorrectly evaluated newly read aim against
`frame_start`, which precedes XR/shared-pair waits. A valid sample published
during those waits was consequently rejected as future-dated. The harness now
samples `steady_clock::now()` after reading aim. It still rejects actually
future and expired samples. A new `gameplay_reticle_post_start_frames` counter
counts displayed reticles that the old comparison would have rejected.

Preflight passed again in
`artifacts/unattended/preflight-20260904T060349Z.json`. The Release harness and
`darktidevr-gameplay-aim-state-tests` were rebuilt. The
`gameplay_aim_state_transport` CTest passed, including the during-wait timeline
and rejection of genuinely future timestamps. Worn flicker acceptance remains
pending.

The next manual comparison uses the rebuilt reticle and temporarily disables
the clustered-light visibility correction to isolate its possible effect on
marker projection. This is an A/B diagnostic, not rejection of the lighting
fix. Restore the default correction after that comparison:

```powershell
tools\stereo\start-darktide-vr.ps1 -DurationSeconds 28800 -GameStartTimeoutSeconds 600 -EnterPsykhanium -ClusterLightVisibilityFix:$false -ManualLauncherPlay
```

Output: `artifacts/unattended/manual-reticle-marker-ab-20260904.log`.
