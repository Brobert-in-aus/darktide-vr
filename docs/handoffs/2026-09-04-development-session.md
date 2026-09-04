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

The first manual log contains repeated left flag changes between 3 and 15
while the right often remains at 15. The initial interpretation as invalid
position tracking was wrong: the bridge assigns orientation-valid=1 and
position-valid=2, so 3 still has both valid components. Lua incorrectly tested
mask 5, requiring tracked orientation while omitting position validity. That
mismatch could freeze a valid inferred pose, but the user explicitly confirmed
that left-hand misalignment is not a tracking issue. Investigate the transform
separately; do not dismiss it as tracking loss.

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

## Second worn result and next candidate

The user confirmed: markers align with the lighting correction off; the
crosshair no longer flickers, but the edge of its transparent square is
visible; the left glove remains misaligned and this is definitely not tracking.
The comparison run completed with 21,187 fresh pairs and 5,504 reticle frames.
Of those, 4,691 used aim samples newer than frame start, which the old check
would have rejected. The game was asked to close normally for the next build.

The next candidate restores the production lighting correction and applies
its 1.2 post-projection scale to CPU marker coordinates about the backbuffer
center. Both the initial marker calculation and replay projection delta use
the same helper. This is awaiting worn acceptance. The documented default
backbuffer coordinate convention is in the
[Stingray Camera API](https://help.autodesk.com/cloudhelp/2018/ENU/Max-Interactive-Help/lua_ref/obj_stingray_Camera.html).

Rigid-hand mode now bypasses the old arm-length retargeting step. The generic
proxy handle is the left rigid root, so the former order changed only that
root's arm skeleton before placing its wrist, while the right root retained
its authored skeleton. No right-hand offset or anatomical rotation was changed.
All six Lua controller validity checks now use bridge mask 3 instead of 5.

The crosshair submits an inset 37x37 region inside its existing 41x41 atlas,
leaving transparent texels outside the compositor's sampled rectangle. Quad
size is adjusted proportionally to preserve the visible crosshair size.
The rebuilt `window_capture_recovery` test passed, including checks that the
filter footprint contains zero color and alpha. Source parsing still passes
at 198/198 locals. The Release harness was rebuilt.

Current manual launch:

```powershell
tools\stereo\start-darktide-vr.ps1 -DurationSeconds 28800 -GameStartTimeoutSeconds 600 -EnterPsykhanium -ManualLauncherPlay
```

Output: `artifacts/unattended/manual-marker-hand-fix-20260904.log`.
This restores the default enabled clustered-light correction during sync.
Next ask the user to check left glove stability/alignment, binocular markers
with lighting enabled, and disappearance of the crosshair square.

The fresh candidate logged lighting correction active at 06:14:58 UTC and
rigid hands ready at 06:15:51 UTC, then advanced `shared_ready` beyond 2,400.
No marker reprojection failure was logged. Review of the previous three logs
confirmed the asymmetric retarget was actually applied: each logged
`arm_bone_scale=1.0675` immediately after rigid-hands readiness. The new run has
only the earlier gameplay-avatar retarget (`0.9628`) and no rigid-root retarget.

## Third worn result: edge behavior remains asymmetric

The user reports the left glove remains wrong (possibly slightly worse).
Bypassing the asymmetric retarget is not an accepted alignment fix. Markers
align centrally with lighting restored and shrink equally, but visibility at
opposite eye edges remains asymmetric. Crosshair-square acceptance is pending.

The next candidate changes binocular clamping to match the actual recentered
symmetric camera projections: primary uses runtime view 0, replay uses view 1;
positions convert through each camera's optical centre and horizontal half-FOV.
The old clamp used reversed raw asymmetric frusta despite rendering through
rotated symmetric cameras. Added passive per-hand wrist target and glove-joint
error logging every 600 placements to separate skeleton placement from visible
attachment alignment. No hand offset was changed for this diagnostic.

Validation: proximity Disable then Status (Awake); VD Streamer and VDXR checked;
`build/windows-vs2022/tests/xr_harness/Debug/darktidevr-xr-harness.exe --frames 30 --debug-layer --require-openxr --require-rendering --xr-frames 120`
passed (`artifacts/unattended/marker-edge-preflight.log`).
`tools/stereo/test-darktide-lua-source.ps1` passed at 198/198 locals.
Manual launch uses the same command as above, with output in
`artifacts/unattended/manual-marker-edge-diagnostic-20260904.log`.
Fresh initialization, nonzero shared_ready and worn acceptance remain pending.

Fourth worn result: marker edges improved, but markers pile up at the left
edge of the left eye and disappear quickly on the right edge of the right eye.
Crosshair square is gone (accepted); committed atlas fix as `3133791`.
The user moved both gloves extensively. Across 34 periodic samples per side,
maximum left wrist error was 0.000001 m, right 0; both glove-to-skeleton wrist
errors were 0. This excludes positional joint-link drift at the sampled points,
not a wrong anatomical orientation, wrist calibration or skin bind pose.

Fresh console `console-2026-09-04-06.27.44-067ed82e-2597-4cf5-8bf2-37c03fee09f0.log`
logged recentered projection at 06:31:46 and rigid hands ready at 06:31:52.
Harness shared_ready exceeded 16,349 with no reuse. Launch is valid.
The game initially waited at character selection; the user continued manually.

Prepared (not yet deployed) the next marker policy correction: only templates
that allow screen clamping may stack at the binocular edge. Other markers are
hidden at the shared boundary in both eyes. The previous clamp ignored
`template.screen_clamp` and `marker.block_screen_clamp`, keeping markers alive
at one edge until the primary camera's stock visibility eventually culled them.
Source gate passed again at 198/198 locals. Current run remains open for a
manual left-palm orientation check before selecting another calibration change.

Prepared additional passive pre-render checking: every 600 placements, box the
solved wrist pose, then compare it at the active world's render boundary.
This tests whether later game updates mutate the root after placement. Source
gate passed again. No calibration or right-hand offset changed.
The prior manual session exited. Next launch (automatic launcher activation,
state-gated startup only, no synthetic body/controller movement):
`tools/stereo/start-darktide-vr.ps1 -DurationSeconds 28800 -GameStartTimeoutSeconds 600 -EnterPsykhanium`
Output: `artifacts/unattended/manual-marker-policy-prerender-20260904.log`.
Quest Disable/Status reapplied; Awake and display suspend blocker confirmed.
Fresh initialization and shared_ready for this new run remain pending.

The automatic launch reached gameplay without manual menu assistance. Fresh
console `console-2026-09-04-06.41.43-b89dc922-13c4-45a7-9337-a8d12f22f75a.log`
logged recentered stereo at 06:42:39; shared_ready exceeded 2,419 with no reuse
or pose mismatches. Early pre-render samples on both hands report zero
position drift and zero rotation drift after placement. Wrist target errors
are at most 0.000008 m in these samples, and glove-joint errors remain zero.
Marker-policy worn acceptance and the left palm-orientation report are pending.

## Hub findings and weapon-dependent hand behavior

User reports per-eye lighting asymmetry in the hub. Both unarmed gloves are
medially offset; the previously good right-hand observation was in the
Psykhanium while wielding a weapon. Do not treat the right wrist calibration
as accepted globally. Off-hand finger poses must follow weapon actions (for
example open palm while blocking). Pinned world markers now retain size and
nearly match, with small increasing positional divergence when looking away.

The production light correction was active in the affected hub run: shader
patch counters exceeded 200,000 with zero rejects/missing roots/resources.
This is visual failure despite an active mechanism, not a disabled flag.
The missed range entry is logged: `source_back` immediately closed
training_grounds_view at 06:42:34; state then timed out waiting for options.

Prepared changes (source gate passes at 198/198): baseline stale Back events
when opening a new menu; cache authored hand anatomical basis before importing
finger animations; copy matching gameplay finger-joint local rotations into
the independent glove rigs while preserving tracked wrists; reproject pinned
marker directions through both full optical rotations, including vertical
position, instead of applying horizontal-only correction with shared Y.
None of these is a claimed fix for the medial wrist offset or hub lighting.

Temporarily enabled MatchedOrientation in the live hub at 06:50:52 for a manual
lighting isolation check. Requested user observation, then restored Disabled
so the diagnostic cannot remain enabled while unattended. No result yet.

## September 5 commit checkpoint

The accumulated September 4 follow-ups are ready to commit as one coherent
manual-validation candidate. The rigid one-sided glove roots now reuse the
accepted anatomical hand-frame mapping and calibrated grip-to-wrist
translation. Each root caches its authored palm/finger basis before importing
gameplay finger animation, then copies matching finger-joint rotations from the
authoritative gameplay skeleton while controller tracking retains wrist
ownership. Arm-length retargeting now runs only on the older articulated proxy
path, avoiding the former left-root-only deformation. Passive placement and
pre-render telemetry remains in place; the most recent worn diagnostic already
excluded later root drift and glove-to-skeleton joint drift.

All controller aim/grip validity tests now use the bridge's documented valid
bit mask 3 rather than mask 5. Opening a new menu baselines any stale Back edge
before the view begins consuming input, preventing a prior screen's release
from immediately dismissing the Psykhanium/options view.

The pending spatial-visibility candidate now derives clustered-light
post-projection expansion from the union of both rotated eye cones rather than
a fixed 1.2 multiplier. CPU world-marker projection consumes the same scale.
Binocular marker clamping uses the recentered symmetric camera model, respects
each template's screen-clamp policy, and reprojects a pinned marker's complete
direction through both optical rotations instead of sharing vertical position.
These changes address the observed central alignment, edge pile-up and oblique
view divergence, but final marker and lighting acceptance still requires a
direct headset check.

The synthetic body-inspection pose is reduced from 70 degrees to 55 degrees
down so both hands remain usable for inspection. Per the manual-visual-check
policy, this is test support rather than evidence of worn glove acceptance.

Validation completed for this checkpoint:

```powershell
tools\quest\set-proximity-override.ps1 -Action Disable
tools\quest\set-proximity-override.ps1 -Action Status
tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 120
tools\stereo\test-darktide-lua-source.ps1
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr-synthetic-head-tests -- /p:TreatWarningsAsErrors=true
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release -R '^synthetic_head_path$' --output-on-failure
git diff --check
```

The September 5 preflight passed with one awake authorized Quest, the
proximity override active, VirtualDesktopXR rendering 120/120 frames and no
Darktide process. The Lua source/syntax gate passed at 198/198 file-scope
locals, `git diff --check` passed, and the Release `synthetic_head_path` test
passed. No final aggregate Darktide launch was performed after the last marker,
finger-animation and light-visibility changes. Next use a real-tracking manual
Psykhanium/hub session to check both unarmed and wielded palm placement,
weapon-dependent finger poses, pinned-marker behavior at every eye edge, and
per-eye lighting parity. Do not treat the source checks or XR smoke run as worn
visual acceptance.
