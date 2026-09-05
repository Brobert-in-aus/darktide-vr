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

## Accepted LOD baseline and next candidate

User accepted lod_object_multiplier=3 as sufficient for initial release; finer
LOD tuning and selective smoke-cloud suppression are recorded in POST-RELEASE.md.
Smoke-only removal is deferred because the shader is shared with other particles
and SmokeFogSystem only identifies a subset of cloud effects.

The new melee candidate scopes first-person aim to the right controller for
stock sweep initialization/update, pushes and melee explosions, preserving
stock attack origin, reach and timing. Scoped component replacement restores on
errors and preserves multiple return values. Animated hands rotate about the
stock head pivot toward that aim and weapon attachment nodes follow the proxy.
This remains a worn acceptance candidate; left-hand alignment is unresolved.

VR visual policy forces DOF, motion blur, lens quality, colour fringe, distortion,
lens flares and sun flare off at startup, direct setting writes and settings
application. Fullscreen UI blur always returns disabled. The shared preset table
is copied when clamping values; unrelated settings remain intact.

Validation: LuaJIT source gate passed all 13 chunks, source invariants passed,
and CTest --test-dir build/windows-vs2022 -C Release --output-on-failure passed
51/51. New tests cover melee aim restoration/return values and visual policy
startup/preset/direct-write/apply behavior. No native source changed.

Applied active top-level max_worker_threads=7 for the 8-physical-core/16-logical
Ryzen 7 9800X3D. The nested detected_user_settings cache remains unchanged.
Release setup must derive physical cores minus one automatically, not hardcode7
or subtract from logical processors. Also trialled active feedback streamer
max_texture_pool_size 1024 -> 2048 on RTX4090; other streaming values unchanged.
Backups and trial metadata are ignored in artifacts/unattended. Both worker and
pool changes share this restart, so this is not a clean pool-only performance A/B.

Ready preflight passed 120 rendered frames in
artifacts/unattended/melee-effects-pool-preflight-20260905.json. Started with
-EnterPsykhanium -ManualStartup, log melee-effects-pool-live-20260905.log.
Fresh stereo and worn behavior still require confirmation for this candidate.

Worker automation follow-up: set-vr-worker-threads.ps1 reads Win32_Processor
NumberOfCores (summed across packages), calculates max(1, cores-1), and edits
only the active top-level assignment while closed. start-darktide-vr.ps1 calls
it before a fresh launch. Inspect on this host returned physical=8, workers=7.
Isolated settings fixtures with mocked 8/16 and 1/2 processors passed, including
preservation of the detected cache and unrelated values. This removes the
hardcoded-machine-value risk from the launcher; packaged setup must retain it.

Window inspection confirmed the new run is at the ordinary 'Press SPACE to
continue' title screen. No startup input was sent; manual startup is intentional.
Fresh stereo validation remains pending entry into the game.

Live run reached fresh stereo at 00:12:45 UTC, rigid hands ready at
00:12:45.698, shared_ready > 5479, recent fresh throughput about 58-60fps,
zero reused frames and two startup pose mismatches. GPU memory sampled at
9168/24564 MiB. Right-hand melee hook exercised at 00:14:25.999 onwards.
These observations establish code-path execution, not worn acceptance.

The live log revealed DMF rejected the separate visual-policy UI update hook
because this mod already owns that method. Candidate now invokes the policy
from the existing callback. The regression runs the real UI callback and rejects
duplicate registration; startup/preset/write/apply cases pass. This correction
is staged for the next restart, not yet installed in the current live run.

Left-wrist candidate removes the body-fixed portion of the correction for the
left hand only. The complete offset now rotates in grip space; at aligned grip
and body axes it matches the prior correction. Right-hand mapping is unchanged.
Quarter-turn and upside-down covariance checks pass on the new code and fail
on the preceding commit, as expected. LuaJIT 13 chunks and source invariants
pass. Exact left palm placement remains a worn acceptance question, not a test
assertion. Candidate staged while the user resumed gameplay; do not interrupt
that observation just to deploy these follow-ups.

User accepted the current performance configuration (possibly a little better):
keep feedback texture pool 2048, worker count 7 and LOD multiplier 3 for now.
This is acceptance of the combination, not proof of an isolated pool benefit.

User rejected melee direction: enemy at the right, reticle aimed at it, looking
forward and attacking still presents a forward swing. Do not mark hand-directed
melee fixed merely from the hook counter. Found another real defect in the
third-person animation aim callback: `local _, rotation = module and module.target()`
discards the second return through Lua's logical expression and always uses head
fallback. Candidate uses an explicit guard and direct two-value assignment.
The actual callback regression (hand right/head forward) fails the old code and
passes the candidate, including invalid-controller fallback. Periodic actual
hand/head direction vectors are added to melee diagnostics. Worn side-aimed
swing and hit verification remains required, including possible interaction
between stock animation constraints and proxy rotation. Next startup also logs
engine-reported texture pool and worker settings when available.

Deployed 1accaae after normal game closure and successful Ready preflight:
artifacts/unattended/wrist-animation-preflight-20260905.json (120 rendered frames).
Manual-startup run: artifacts/unattended/wrist-animation-live-20260905.log.
Launcher automatic physical-core calculation ran and retained seven workers.
This deployment contains left-grip-space correction, UI startup policy callback
fix and the animation rotation return-value fix. Verify new startup policy log,
engine pool/worker report, fresh stereo and real hand/attack behavior. Do not
reuse the prior run's acceptance/counters for these new changes.

Fresh startup now confirms DARKTIDEVR_VISUAL_SETTINGS blur_dof_lens=forced_off
at 00:22:45.150. No duplicate-hook warning. Application.settings() does not expose
feedback pool/worker values on this build (reported unavailable), so the effective
pool limit is not independently established by that API. Installed config remains
2048; do not mislabel the readback as verification. Fresh range rigid hands ready
at 00:23:40.364, shared_ready >1949, recent fresh throughput about 60fps with zero
reused frames and one startup pose mismatch. Worn direction/alignment pending.

Review of the same Lua return-value pattern found ViewInteraction's vendor-panel
callback also discarded pcall's second value. Fixed with an explicit manager
nil guard; the existing active-view check now receives the actual boolean.
LuaJIT 13-chunk gate passes. This small shop follow-up is staged locally and does
not change the current live run.

The user again rejected hand-directed melee and requested left-hand blocking.
Source investigation identified the stock hit filter's separate head-facing
is_within_default_view check. Candidate scopes that check to right-hand aim through
an action-local first-person-extension proxy; unrelated extension methods remain
bound to the original instance, and errors restore both action references.

Melee hand animation now reads the untouched first-person rig, with its root as
the rotation pivot, instead of reading the same third-person hand nodes that
receive the VR attachment writes. This avoids feedback from the previous VR
pose. This is a new candidate, not accepted visual behavior.

Left-hand block module scopes first_person reads during Block.is_blocking and
Block.attempt_block_break only, for the local player with valid controller aim.
It preserves stock block types, angles and stamina costs; the stock outer melee
arc may cover a full circle, with a cheaper inner arc. No shared component is
written. Tests cover both calls, remote isolation, error cleanup and missing pose.
Melee tests now include the actual extension-view delegation/restoration; a new
animation-source test distinguishes the untouched first-person rig from modified
third-person nodes. LuaJIT gate passed 14 chunks and source invariants passed.

Physical melee investigation: see ../TRACKED-MELEE-DESIGN.md. User explicitly
selected an always-active standard-sized combat volume, per-enemy attack-rate
cooldowns and unlimited cleave, rejecting the proposed global cadence/motion
threshold/stock cleave restrictions. Heavy contacts use charge-time per-enemy
cooldowns, initially unavailable. These requirements supersede earlier suggestions.
No always-active physical damage implementation has been enabled yet.

Deployed d982fb5 after successful Ready preflight (120 rendered frames):
artifacts/unattended/combat-direction-preflight-20260905.json. Active manual-startup
run is artifacts/unattended/combat-direction-live-20260905.log. This includes the
14th Lua module for block direction. Worn melee direction, block orientation,
first-person animation-source appearance and left-hand alignment remain pending.
The accepted pool/worker/LOD configuration is retained.

The d982fb5 live run failed mod initialization at 00:34:40.260. New combat
module eagerly required PlayerUnitDataExtension, which loaded network lookup
before ArchetypeTalents existed (pairs(nil) at network_lookup.lua:109). The game
process subsequently exited; this run is not accepted and supplied no fresh
stereo validation. Corrected to DMF hook_require so the callback attaches after
the game's normal class load. The regression now throws if that dependency is
required during mod boot, then explicitly supplies the deferred class and checks
block behavior. Updated test and 14-chunk compiler gate pass.
