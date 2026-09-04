# Development session — 2026-09-05

Branch: `codex/live-validation-2026-09-05`, based on `a71a602`.
The unrelated untracked image remains untouched.

## Startup and user observations

Applied Quest proximity Disable, then Status: awake with display held.
Ready preflight passed with 120/120 rendered VDXR frames. Built Release with
warnings as errors and deployed the maintained baseline through the normal
Lua compiler gate. The initial real-tracking launch used `-EnterPsykhanium`.

The user closed the game during hub loading. This was not an unexplained
crash. The viewer exited cleanly with zero fresh shared pairs; it did not
establish gameplay stereo acceptance. Local evidence is
`artifacts/unattended/live-validation-20260905.log`.

The user reported two blocking issues: laser hover worked but trigger
selection did nothing, and the game repeatedly reclaimed desktop focus/cursor
after Alt-Tab. They selected the character using the keyboard.

## Input candidate

The primary-click activation guard previously reset on presentation sequence
changes, including the periodic unchanged-state heartbeats. It also cleared
its activation timestamp on a ray miss without reliably starting it again.
Extracted a tested primary-input state machine keyed by active menu, mode and
writer generation. Heartbeats and ray misses no longer reset arming. Held
entry input still requires release and settling, and moving onto a panel with
an already held trigger does not click.

Removed repeated foreground activation from startup key dispatch. Startup
keys are sent only while the authenticated game process owns foreground.
Removed foreground activation from native mouse-action injection; its existing
foreground guard now rejects background movement/actions. The explicit
one-time Fatshark launcher Play operation remains separate from runtime input.

Added `-ManualCharacterSelect` to pause startup automation at character select
while retaining `-EnterPsykhanium` pre-launch arming. This allows direct laser
selection validation without automated Enter masking the result.

## Validation

Commands from the repository root (CMake/CTest used VS2022 bundled executables):

```powershell
tools/quest/set-proximity-override.ps1 -Action Disable
tools/quest/set-proximity-override.ps1 -Action Status
cmake --preset windows-vs2022 -DDARKTIDEVR_ENABLE_HEADSET_TESTS=OFF
cmake --build build/windows-vs2022 --config Release -- /m /p:TreatWarningsAsErrors=true
ctest --test-dir build/windows-vs2022 -C Release -j 4 --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File tests/launcher/validate-early-failure.ps1
tools/unattended/invoke-unattended-preflight.ps1 -XrFrames 120 -OutputPath artifacts/unattended/input-fixes-preflight-20260905.json
tools/stereo/start-darktide-vr.ps1 -EnterPsykhanium -ManualCharacterSelect
git diff --check
```

Release build and all 46 CTests passed. Primary-input regression covers
heartbeat arming, ray misses, one edge per pull, held-entry suppression,
writer restart, mode transitions and same-mode reentry. Startup focus test
stubs native/COM calls and verifies background input suppression, foreground
dispatch and suspension after Alt-Tab without touching real desktop input.
The launcher early-failure regression passed again after adding the manual
character-selection option. LuaJIT compiled all 12 chunks/descriptors.
The sequential Ready preflight passed after testing.

Current candidate output: `artifacts/unattended/input-fixes-live-20260905.log`.
Trigger selection, Alt-Tab behavior, fresh gameplay stereo initialization and
nonzero `shared_ready` are pending live verification. Hands, weapon finger
animation, marker edges and lighting still require the worn checks listed in
CURRENT-STATUS. No synthetic controller movement was requested or enabled.
Proximity automation remains disabled for the ongoing development session;
restore it when development ends. No Mac-specific validation applies.

## Second live finding: stale presses activated later hover

The user rejected the first input candidate: hover initially failed, social
strike-team selection opened unexpectedly, and hovering Play later selected
the character without a new deliberate pull. Logs confirm a missed press was
left unconsumed: primary sequence 5 missed at 23:00:58.355 UTC and activated
`counts_background` at 23:00:58.605; sequence 6 missed at 23:01:13.268 and
activated `play_button` at 23:01:14.301. This was a delayed semantic edge,
not evidence of intentional selection. Earlier trigger telemetry is not user
acceptance. Initial hover remains a separate live check.

That run did reach the Psykhanium: fresh stereo initialization at 23:01:42.558,
rigid hands ready at 23:01:42.807 and `shared_ready` above 8,000. It was closed
for the next deployment, not accepted visually.

The next candidate samples pointer/edge state once per UI frame and consumes
unhandled primary edges before the following UI update. This prevents a
missed press from following later hover onto a button. The executable Lua
widget regression covers miss/next-frame expiry, stable sampling within a
frame and availability of a fresh press. Lua compile/invariant, menu widget
and launcher focus/transition tests passed (5/5 targeted CTests).

Added `-ManualStartup` to suppress all title/character key automation while
retaining pre-launch range arming. Current launch is:

```powershell
tools/stereo/start-darktide-vr.ps1 -EnterPsykhanium -ManualStartup
```

Evidence: `artifacts/unattended/manual-input-live-20260905.log` and the
successful sequential `manual-input-preflight-20260905.json`. The user must
advance the title manually. Verify immediate hover, one action per deliberate
pull, no later activation after pressing empty space, and Alt-Tab behavior.

The manual run reached fresh stereo and rigid-hands initialization at
23:05:46.044 UTC, copied 20 finger joints per hand, and advanced `shared_ready`
past 4,700. No startup key helper was running. The log records two desktop
mouse presses missing semantic Play geometry; each was consumed by the next
frame instead of persisting until later hover. This is diagnostic evidence,
not worn input acceptance.

The same trace exposes a second hover problem: source 1024x614 points around
(790,465) were compared directly against a 1280x768 authored Play rectangle
starting at (883,564). Correct mapping puts the source point inside Play.
Prepared widget hit-test scaling to RESOLUTION_LOOKUP dimensions, retaining
explicit portrait layout dimensions for vendor-transformed pointers so they
are not scaled twice. Added regression cases using those observed dimensions
and an empty-space miss. Lua gate and all three relevant CTests passed.
The coordinate follow-up was deployed after closing the preceding run and
passing sequential Ready preflight. Current output is
`artifacts/unattended/menu-coordinate-live-20260905.log`; its preflight is
`menu-coordinate-preflight-20260905.json`. Launch still uses `-ManualStartup`.
Fresh initialization and direct input acceptance for this latest run are pending.

## Accepted input and new gameplay findings

The user confirmed character-selection highlight and selection worked on the
coordinate candidate. Finger animation is also accepted. Left-hand alignment
remains wrong. Do not ask repeated questions: the user is frequently typing
feedback and explicitly requested that questions stop.

New reported issues: melee swings need both hands to follow the stock attack
animation with IK disabled until a proper melee system exists; a right-side
enemy's shield disappears a few metres away and reappears closer; crosshair
depth hits an invisible surface in empty space near enemies; loading screens
show one white/teal pixel at bottom right.

Retrieved and inspected the newest Quest screenshot,
`VirtualDesktop.Android-20260905-090631.jpg`, saved only as ignored local
`artifacts/unattended/quest-crosshair-20260905-090631.jpg`. It shows the reticle
in the gap between enemies and the missing shield on the enemy at right.
The screenshot alone does not establish the collision surface or LOD cause.

Prepared/deployed candidate:

- The existing melee owner recognized windup/sweep in live logs, but returning
  before IK left independent rigid-hand roots frozen. Both proxy wrists now
  copy authoritative gameplay hand position/rotation during that interval,
  retaining finger animation. Optional tracked weapon posing also yields.
- The reticle accepted every named damage zone, including `afro`. Stock
  `scripts/utilities/attack/hit_scan.lua` treats that zone as suppression/near
  miss and continues without impact. The reticle now excludes it while
  retaining body, shield and static surfaces.
- Camera visibility expansion is canceled by post projection in the visible
  image. The World.update_lod_levels hook temporarily uses the unexpanded
  rendered FOV, then restores the visibility FOV even on failure. This is a
  candidate for the shield disappearance, not confirmation of its cause.
- Window capture writes its cyan laser swatch only while a menu pointer is
  active. Loading frames no longer expose it, and loading does not submit
  pointer quads.

Release viewer and capture-test builds passed with warnings as errors. LuaJIT
compiled all 12 chunks. Targeted Lua source/invariant, projection math, reticle
surface and capture recovery checks passed. The capture test's old assertion
requiring the swatch during idle was updated to the new contract; an exact
corner background-colour assertion was unsuitable for the resampled window
edge, so the regression checks swatch absence while retaining the existing
pointer-visible swatch assertion. Projection tests verify restored FOV on
success/failure; surface tests retain body/shield/world while rejecting local
body, broad capsules and suppression volumes.

Current manual launch: `-EnterPsykhanium -ManualStartup`, with output in
`artifacts/unattended/melee-visual-live-20260905.log`. Sequential Ready preflight
passed in `melee-visual-preflight-20260905.json`. All new visual behavior is
pending live acceptance. Extra suppression-skip/LOD diagnostic logging was
added after this deployment and compiled successfully; it will take effect
on the next sync. No left calibration change was made.

This run reached fresh synchronized stereo at 23:19:09.980 UTC and rigid hands
ready at 23:19:10.046; `shared_ready` exceeded 663 with zero reused frames and
one startup pose mismatch. The late logging-only additions passed Lua source,
invariant, projection and reticle-surface checks. New visual acceptance remains
pending. Keep the live session available for the user's unsolicited feedback.

## Staff and marker follow-up

The user accepted reticle depth and sword swings. Staff melee/push on right
grip still failed: animation ownership had been restricted to slot_primary.
The shared policy now accepts sweep, push and melee_explosive in either slot,
and ranged windups only when their allowed chain leads into a melee attack.
Projectile charging remains tracked. The melee_animation_owner regression
covers these cases, including staff windup and non-melee ranged charging.

The user reported slight eye-to-eye asymmetry while world item markers shrink
at the shared screen boundary. Stock _apply_scale interpolates mutable size,
offset and pivot arrays during draw; right-eye replay repeated that interpolation.
Replay now reuses the primary draw's scale state.

The shield still disappears too close. Retrieved and inspected the latest Quest
screenshot as ignored artifacts/unattended/quest-weapon-visibility-20260905-092223.jpg;
it also shows missing shaft sections on a mace roughly 3m away by user estimate.
The FOV adjustment has not resolved this. Stock minion weapon slots use their
own LOD objects rather than the character clothing LOD group. No global
high-detail override has been applied. Equipment visibility remains open.

LuaJIT compiled all 12 chunks; targeted source/invariant, projection, reticle
and melee checks passed 5/5. Ready preflight passed 120/120 frames in
artifacts/unattended/staff-marker-preflight-20260905.json. The preceding game
had closed normally. Launched the follow-up with -EnterPsykhanium -ManualStartup,
output artifacts/unattended/staff-marker-live-20260905.log. This deployment also
includes the previously pending LOD and suppression-skip telemetry. Fresh stereo
initialization and worn acceptance for this run still need verification.

Fresh synchronized initialization appeared at 23:32:21.278 UTC, followed by
rigid hands ready at 23:32:21.341. shared_ready exceeded 1622. LOD telemetry
confirms the scoped hook runs: visible FOV 1.7279 versus visibility FOV 2.2220,
tangent scale 1.7248. This proves application of the candidate, not resolution
of the missing equipment.

### Mesh-streaming research requested by the user

Fatshark's engine developer explains a known failure where the vertex-buffer
budget makes models compete for higher-detail meshes, including nearby weapons:
https://forums.fatsharkgames.com/t/models-looks-strange/100232
The developer recommends disabling mesh streaming as a diagnostic, warning
that keeping it disabled can cause stalls and increased mesh VRAM usage.

In March 2025 the developer confirmed the override can live in user_settings.config:
https://forums.fatsharkgames.com/t/mesh-streaming-not-working-correctly/83361
Use mesh_streamer_settings = { disable = true }. Reports of incomplete nearby
meshes persist into January 2026 in the acknowledged issue:
https://forums.fatsharkgames.com/t/mesh-streaming-not-working-and-textures-getting-loaded-lod-error/63975

The lodbgone author's March 2026 explanation says Lua LOD requests do not
guarantee mesh residency and describes the mod as experimental:
https://www.nexusmods.com/warhammer40kdarktide/mods/743?tab=posts

Local settings_common.ini currently has mesh streaming enabled, limit=700;
the user's mesh_streamer_settings section is empty and lod_object_multiplier=1.
These settings have not been changed. Next equipment diagnostic: compare with
streaming disabled at a normal restart, preserve the prior section for restoration,
and measure fresh stereo throughput as well as worn shield/mace visibility.
Keep the live staff/marker run available meanwhile; do not force input or focus.

## Heading mismatch and streaming comparison

The user accepted symmetric marker shrinking, then reported movement and melee
facing approximately 90 degrees right of their visible facing direction.
Live logs confirm independent headings (for example head_ypr yaw=-1.4764 and
gameplay yaw=2.8820). observe_controller_aim seeded heading from stock spawn yaw
and only integrated physical yaw changes, preserving that initial discrepancy.
It also throttled orientation updates to every fifteenth call. Rendering now
uses an immutable scene anchor, so the old feedback-avoidance rationale no longer
applies: gameplay now consumes head_aim_yaw directly, normalized to [0,2pi),
once per new sample. Modal cameras remain untouched until exit.

The gameplay_heading regression executes the actual seam with mocked game
services and checks initial 90-degree error, negative yaw, successive samples,
owner replacement and modal entry/exit. Lua source/invariant, melee owner and
heading CTests passed 4/4. Marker acceptance does not establish hand alignment.
Staff stock windup/stab/heavy-stab ownership is present in logs but still needs
the user's visual acceptance.

Added tools/stereo/set-mesh-streaming-diagnostic.ps1 with Inspect/Disable/Restore.
It refuses mutation while Darktide runs, saves the original override separately,
and restores only that property so later calibration/settings changes survive.
An isolated fixture passed inherited/false/true original values, repeated apply,
and unrelated calibration edits across restoration. Fixture process checks were
mocked; the real user settings remained untouched during fixture validation.
The live staff/marker run was asked to close normally for the heading deployment
and streaming comparison. Last throughput was 53.6 fresh pairs/sec, shared_ready
19622, zero reused frames and five pose mismatches accumulated during startup.

After the game closed, applied set-mesh-streaming-diagnostic.ps1 -Action Disable;
Inspect confirmed user_disable=true. Its ignored state records the original
inherited setting. Restore with the same tool's -Action Restore while the game
is closed; do not restore a whole old user config over later calibration edits.
Ready preflight passed in heading-streaming-preflight-20260905.json. The new
manual-startup output is artifacts/unattended/heading-streaming-live-20260905.log.
Streaming disable is a diagnostic, not yet a production default. Fresh stereo
and worn direction/equipment acceptance remain pending for this run.

Fresh range stereo initialized at 23:40:34.361 UTC and rigid hands at
23:40:34.428. shared_ready exceeded 5270, zero reused frames, two startup pose
mismatches; recent throughput is 52.6-53.5 fresh pairs/sec. GPU memory usage
sampled at 10375/24564 MiB. Absolute head yaw and gameplay yaw agree modulo
2pi in the live trace (with the expected preceding-sample delta during turns).
This is mechanism validation; the user's direction/equipment verdict is pending.
The new heading regression rejects the prior cf537dc source as expected.

The user accepted heading alignment. Disabling mesh streaming did not improve
the issue. They observed terrain objects changing detail at the same roughly
3m boundary while moving back and forth, confirming a distance-dependent LOD
transition. The current config uses DLSS Quality (not Ultra Performance) and
lod_object_multiplier=1. Next comparison restores streaming and changes only
the LOD multiplier to 3, retaining the established stereo projection/lighting
path. If the threshold moves correspondingly, this isolates the distance control.

Streaming was restored successfully after normal game closure. Changed the one
lod_object_multiplier assignment from 1 to 3, recording the original in ignored
artifacts/unattended/lod-distance-diagnostic.json. Ready preflight passed in
lod-distance-preflight-20260905.json; launch output is
artifacts/unattended/lod-distance-live-20260905.log, again -ManualStartup with
Psykhanium pre-armed. No new Lua/native behavior was changed for this comparison.
At session end restore the LOD value if the diagnostic is rejected; preserve it
only if accepted as a useful setting. Streaming's saved diagnostic state is inactive.
