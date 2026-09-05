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

Recovery deployment 6f4f2da passed Ready preflight (120 rendered frames) in
artifacts/unattended/combat-loadorder-preflight-20260905.json and launched with
manual startup in combat-loadorder-live-20260905.log. Fresh mod initialization
completed through the visual-settings policy at 00:38:31.016 with no new mod
errors; game remains responsive. This fixes the earlier eager-load failure.
Fresh range stereo and worn melee/block checks are still pending at this point.

Recovery run reached range stereo: deferred PlayerUnitDataExtension read hook
attached at 00:40:04.848; rigid hands ready at 00:40:11.373. shared_ready >2850,
recent fresh throughput about 59fps, zero reused frames and two startup pose
mismatches. No new mod errors. Crash recovery is established; worn attack and
block acceptance is still pending.

Offline foundation added: darktidevr_melee_contact_policy.lua implements only
continuous per-target cooldown eligibility. It is not imported by the live mod
and has no physics/damage connection. Different targets have independent gates;
light/heavy share each target's deadline, heavy starts unavailable, stationary
contact requalifies after expiry, and no global cadence/motion/cleave limit exists.
The test covers repeated/duplicate contacts, multiple enemies, initial heavy,
mode changes, new targets, recharge preserving history and no banked burst.
Direct LuaJIT test passes; compiler gate now covers 15 chunks. Collision geometry,
stock damage adapter, authority and visual acceptance remain future integration.

The user accepted hand-directed melee on the recovered combat-direction run:
attacks now go where the hand aims rather than where they look. Preserve this
working path. Blocking cannot yet be tested, so its direction remains unverified.
Do not count the melee acceptance as acceptance of left-hand alignment, block
cost/orientation, or the not-yet-integrated continuous physical melee system.

Added offline rotational sweep planning while the accepted build remains live.
It retains stationary overlap, subdivides rotation by maximum corner travel,
and reports invalid history, tracking resets and budget overflow without making
an artificial long sweep. It does not call game physics or alter cooldowns.
Documented stock raw-query result caps (5/20/20 boxes, 20 sphere): collection
saturation must be addressed separately from removing finite cleave. Exact arc
coverage, collision collection and damage integration remain unimplemented.

Validation: configured windows-vs2022 with DARKTIDEVR_ENABLE_HEADSET_TESTS=OFF;
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure -R
'^(melee_contact_policy|melee_sweep_plan|lua_source_compile|lua_source_invariants)$'
passed 4/4. Lua compile gate includes 16 mod chunks. No deployment or headset
test was run concurrently with the user's game, and no live acceptance is claimed
for this offline foundation.

Reviewed the remaining blur paths. CameraManager writes dof_enabled into the
shading environment after mood blending; SystemView and several constant UI
elements write fullscreen_blur_enabled/amount directly. Added a final clamp for
these three scalars at ShadingEnvironment.apply in the visual-settings module.
This leaves exposure, bloom and unrelated environment values intact and preserves
the original apply arguments/returns. ScriptWorld applies the environment at
the render boundary, so resource blends cannot undo this clamp before that call.

Queued for the next deployment, not applied to the user's ongoing accepted run.
CTest visual_settings, lua_source_compile and lua_source_invariants passed 3/3;
the regression simulates direct camera writes, repeat mood blends and two scene
environments and verifies values at the original apply boundary.

At 00:54:52.709 UTC the recovered combat-loadorder run crashed on the renderer
thread after approximately 16 minutes. Assertion: engine ObjectLUT handle
134217785 (type 2) did not match stored handle 536870969 (type 8), in
d3d12_resource_manager.h:88. This is distinct from the earlier Lua boot failure.
No recent melee/menu transition or Lua error preceded the crash; tracking input
was idle while world rendering continued. The XR harness subsequently printed
result=pass for its own shutdown, which does not establish game stability.

Local dump/PE inspection (ignored artifacts/diagnostics scripts and dependencies)
identifies D3D12Dispatcher::dispatch and the level_world render pass. Stack RVAs
include 0x7c73fe, 0x7c797c, 0x7ab790, 0x769225 and 0x388f6b. The failing binding
record contains the asserted handle; individual buffer/mesh ownership and the
reason for the stale handle remain unresolved. Do not infer that no native
hook appears in this stack means the mod cannot have caused an earlier lifetime
problem. Do not silently roll back the accepted pool/worker/LOD settings on this
evidence alone. No physical-melee foundation or scene-blur follow-up was deployed
to this run, so those queued changes did not cause this crash.

Fatshark documented this assertion class in an older Arbites character-creation
issue, reportedly fixed in 1.8.1. Different trigger/build; supporting context,
not a diagnosis of this incident:
https://forums.fatsharkgames.com/t/known-issue-crash-in-arbites-character-creation/109333

Ready preflight passed 120/120 frames for the next run:
artifacts/unattended/environment-blur-preflight-20260905.json. Deployed a02521a
with manual startup and pre-armed Psykhanium entry; active log is
environment-blur-live-20260905.log. Visual-settings initialization completed at
01:04:06.836 and synchronized stereo at 01:04:52.942, then 01:04:58.721 after
loading. shared_ready reached 661 with approximately 60 fresh pairs/s, zero
reused frames and one startup pose mismatch. No claim of crash resolution or
worn blur/block/left-hand acceptance. Offline melee modules remain unimported.

Follow-up launcher reporting now retains the exact game process handle before
running the XR viewer, reports game.result separately, and fails on a nonzero
game exit even when the XR viewer returns success. It never looks the old PID
up after exit. Running/unavailable results are explicit; exit code 0 alone is
not a stability verdict or proof that an engine did not exit after logging a
crash. This follow-up applies to the next launcher invocation, not the already
running environment-blur session.

Validation uses hidden child processes with an input handshake: observes them
while running, then verifies retained exit codes 0 and 17. CTest launcher exit,
startup-focus and play-transition checks passed. The broader launcher check
found that the early-failure fixture predated automatic worker configuration;
it now accepts either missing setup prerequisite before one-shot arming, mocks
physical cores and passes. The worker tool reports a specific missing-settings
error. No real game settings or input are touched by these fixtures.

The engine's crash dump is only about 1.3 MB and lacks the broader resource
ownership data. Downloaded Microsoft's signed ProcDump 12.01 into ignored
artifacts/diagnostics/procdump and attached a one-shot diagnostic to the current
exact game process: -ma -r 1 -a -e 1 -f E0000000 -n 1. It monitors the custom
engine exception seen in this crash, uses a clone for collection, writes locally
under artifacts/diagnostics/full-crashes, and does not queue reports to WER or
kill the game after collection. No system-wide debugger registration was made.
The current process/monitor identities are in ignored procdump-watch.json;
the watch log is UTF-16LE (read with -Encoding Unicode).

Cancel an active watcher gracefully with procdump64.exe -cancel followed by the
recorded target game PID when development ends; do not kill the watcher during
capture. It normally exits with its target or after the one captured dump.
No dump has been captured at setup, and attachment is not evidence of a fix.
Documentation: https://learn.microsoft.com/en-us/sysinternals/downloads/procdump

Continued offline physical-melee geometry: darktidevr_melee_volume.lua resolves
normal attack box overrides and effective width/height/range modifiers, preserves
matrix versus older spline axis conventions, and supplies the centre offset and
maximum corner radius for sweep planning. Sphere actions retain their own radius.
It has no live import or physics/damage/render side effects. Direct pinned-LuaJIT
test passes (dimensions, override precedence, both axes, all-corner bound, sphere,
immutability and invalid inputs); source compiler gate passes 17 chunks.

The two Quest recordings requested around 11:10 Brisbane were copied locally
for sharing only. The user explicitly said they are unrelated to current work;
do not use them for implementation decisions or visual acceptance.

The environment-blur run crashed at 01:20:27.795 UTC, again approximately
16m28s after launch, but at a different frame count (93,505 recent presents
versus 78,241 previously). This time handle 67108868/type 1 mismatched stored
536870916/type 8 on worker wt_4. ProcDump matched E0000000 but clone collection
failed after the target exited (0x800707D1); no full dump was retained. The
watcher exited after its single attempt. Do not claim capture succeeded.

Both mini dumps contain the 4,194,304-entry ObjectLUT and show early IDs replaced
by type-8 records. Inspection of RenderResourceHandleAllocator::new_handle
(RVA 0x5b7870) shows free-list reuse with generation advancement, or a fresh
cursor masked to 22 bits. This supports investigating handle exhaustion/wrap;
the fixed table capacity alone does not prove exhaustion or identify a leak.

Added an opt-in native resource-handle trace module. Presence of
darktidevr_resource_handle_trace.flag beside the installed mod's other flags
registers exact-prologue-guarded allocate/release detours before hook enable.
It preserves return values and allocator behavior, counts by type, and sparsely
logs returned index/generation plus game caller RVAs (first 8, then every 65,536
allocations/type). Output is TEMP/darktidevr-resource-handles-PID.log. Counts
start at installation and are aggregate across allocator instances; owner
pointers in samples allow distinguishing instances. No lifetime fix is claimed.
The trace is absent from normal runs when the flag is absent.

Validation: Release native_capture build with project warnings as errors passed
after fixing a compile typo. CTest native_capture_hooks, melee_volume,
lua_source_compile and lua_source_invariants passed 4/4. Live diagnostic
deployment and actual trace samples remain the next check.

The native trace armed successfully in the next live run, with fresh stereo and
nonzero shared_ready. By 277.766 seconds it recorded 1,245,184 type-8 allocations
and 46,006 releases on the sampled allocator. Its index increased to 1,236,474.
Sustained samples point to 0x5b8154 <- 0x3eb846 <- 0x3ebea4 <- 0x383a87,
within RenderGui command processing from RenderWorld::update_state. This is
actual accumulating GUI resource-handle evidence, not just LUT capacity.
Switching the existing full-second-eye flag at 01:43:01 UTC did not arrest growth:
subsequent 65,536-allocation intervals released only about 90 handles each.

Added a temporary marker-reprojection opt-out, polled alongside the existing
second-eye diagnostic flag every 120 renders. The installed mod-root file
`darktidevr_marker_reprojection_disabled.flag` containing `enabled` disables
retained left-eye capture and right-eye replay; removing it restores reprojection.
Captured-command cleanup remains unconditional within the existing marker path.
Normal configuration is unchanged. This is a causal diagnostic, not an accepted
visual configuration or a lifetime fix. LuaJIT 17-chunk gate and CTest source
invariants pass. Next deployment compares allocation growth with markers off/on.

The same-process marker comparison isolated the accumulating path: disabled at
01:46:41.400 UTC, enabled again around 01:48:03, then disabled again. Type-8
allocation sampling stopped during the disabled intervals and resumed rapidly
when enabled (65,536 new allocations per ~8.4 seconds, only ~50 releases).
The run retained normal stereo submission throughout. This implicates retained
marker capture/recreation, not the accepted texture pool or LOD settings.

Replaced the per-frame retained primitive capture/destroy hooks with a dedicated
immediate screen GUI per source renderer. Marker and interaction left-eye draws
route through it within a scope that restores the renderer even on errors. The
GUI is hidden between eyes, allowing the existing right-eye reprojection to draw
normally; subsequent frames reuse the same GUI. Source renderer destruction
releases it before stock teardown. Projection, symmetric shrink and interaction
pivot calculations are unchanged. The temporary reprojection switch remains for
comparison, defaulting on when its disable flag is absent.

Offline validation: CTest marker_gui, lua_source_compile and lua_source_invariants
3/3 pass. Lifecycle test covers 1,000 eye pairs with one GUI allocation, visibility,
return values including nil, draw-error restoration and idempotent destruction.
Live allocation stability and worn marker appearance remain unverified for this
candidate until the next deployment.

The immediate-GUI candidate reached fresh Psykhanium stereo and exceeded 9,000
shared-ready frames by 01:55 UTC. Type-8 tracing still had only its startup
65,536-allocation sample at 56.203 seconds; the old retained path added another
65,536 about every eight seconds. This establishes that the rapid allocation
path is absent over the initial several-minute observation, not that total
allocations are exactly flat or that long-session/worn acceptance is complete.
Marker reprojection disable flag is absent; production prepared-second-eye path
is restored by normal sync. Resource tracing remains opt-in and enabled for this
ongoing diagnostic session.

Additional stock melee review documented dynamic shield/hit-zone priority,
stateful action hit/proc ownership and the need to copy reusable physics results
across subdivision queries. Physical contact damage remains disabled.

Added the offline melee contact collector: snapshot reusable query values,
resolve one best-priority contact per target across substeps, and leave cooldown
state separate. Its test combines 100 targets and repeated substeps with the
existing cooldown policy, proving no 20-result truncation or reset bypass in
this layer. Physics/obstruction, liveness, stock priority calculation and damage
remain adapter responsibilities; no live import or deployment. CTest collector,
Lua source compiler and source invariants passed 3/3 (19 Lua chunks).

Offline timing helper now resolves explicitly selected stock action chains using
adapter-supplied effective scales and input-ready offsets. Source inspection
found that heavy hold input timing is separate from scaled chain timing; this
is documented with already-held input caveats. CTest timing, Lua source compiler
and invariants passed 3/3 (20 chunks). No live import or changed cooldown behavior.

Read-only snapshots of the live traced allocator at 01:58:55, 02:00:02 and
02:02:46 UTC all show fresh_cursor=85,363; free-list count fluctuates around
1,923-1,941. These observations use only the traced allocator's known fields,
with exact target-executable/PID verification, without modifying the game.
The replacement is past ten minutes; the prior crash window was ~16.5 minutes.

Follow-up ownership review added explicit marker GUI cleanup on mod disable and
unload, in addition to renderer destruction. The test now covers multiple
renderer owners and repeated cleanup. CTest marker_gui/compiler/invariants
passed 3/3. This lifecycle-only follow-up is not yet deployed; the uninterrupted
soak still runs a0fa2eb so its existing elapsed time is preserved.

At 02:12:07 UTC the immediate-GUI run had exceeded 20 minutes from process start
(01:51:31), passing the prior ~16.5-minute crash window. shared_ready exceeded
70,000 with continuing ~60 fresh stereo pairs/second. The allocator fresh cursor
remained exactly 85,363 across all read-only snapshots through this checkpoint;
free-list count was 1,923. The trace checkpoint is ignored under diagnostics.
This supports fixing the observed rapid retained-marker handle accumulation;
it does not establish 60-minute worn stability, transitions or visual acceptance.
The game remains running; the cleanup follow-up remains queued for next sync.

Hand-basis review checked the OpenXR standard grip axes:
https://registry.khronos.org/OpenXR/specs/1.0-khr/html/xrspec.html#semantic-path-standard-pose-identifiers
Grip +X points outward from the left palm and inward on the right. The current
cross(across,longitudinal) source basis also changes palm-relative sign between
hands, so its shared -grip-X target is intentional. Clarified the misleading
comment; no rotation or positional calibration changed. This does not resolve
the pending worn left-wrist placement verdict.

Subsequent user feedback accepted left-hand alignment. The marker baseline is
also accepted for initial release; very slight asymmetry at extreme screen edges
is explicitly deferred to POST-RELEASE.md. Left-hand blocking remains untested.

The user requested the headset for non-VD use and offline development on melee,
HUD and DLSS. Requested normal game window closure, verified the game processes
exited, and restored Quest proximity automation with Enable followed by Status.
The device does not expose a durable query for that broadcast override. Do not
restart the game or run XR preflight during this offline period. The recorded
20-minute stability checkpoint stands; this ended session is not a completed
60-minute worn/transition acceptance run.

Added MOTION-SMOOTHING.md with primary-source research and an integration policy:
adaptive aim stabilization, minimal melee/block lag, once-per-sample stereo
ownership, explicit pose-time semantics, and reset on discontinuities. No filter
or live behavior was changed. Documentation review only; existing offline Lua
checks remain the latest code validation.

Offline HUD follow-up: its draw hook now restores the original renderer and
element list after failures anywhere in spatial drawing, queue construction,
fixed drawing or the dependency sample. Previously only the fixed draw error
path restored both fields. Preserve all stock return values, including nils.
The new hud_panel fixture injects each failure and checks recovery, then checks
one fixed-HUD authoring pass across two eyes. Windows CMake configured with
DARKTIDEVR_ENABLE_HEADSET_TESTS=OFF; CTest hud_panel, lua_source_compile and
lua_source_invariants passed 3/3. No deployment or visual acceptance claimed.

Added offline melee simulation ownership: an advancing fixed tick may query
even with an unchanged stationary controller pose, while duplicate/replayed
ticks cannot spend cooldowns again. Tracking loss consumes the tick but does
not clear target history. CTest melee_simulation, lua_source_compile and
lua_source_invariants passed 3/3 (21 Lua chunks), including the combined contact
collector/cooldown fixture. No live import, damage adapter or network support.

Offline DLSS review tightened unknown-frame and counter-wrap handling in
streamline_stereo_inputs.h. Built darktidevr-streamline-stereo-inputs-tests and
darktidevr_native_capture in Windows Release with TreatWarningsAsErrors=true;
CTest streamline_input_readiness and streamline_stereo_inputs passed 2/2.
The accepted live DLL has not been replaced. REMAINING-DEVELOPMENT.md maps the
three requested bodies of work to their actual implementation seams, including
the still-missing DLSS-G tag/constants submission stage and ABI version check.

HUD lifecycle follow-up now releases its panel on mod disable/unload before
world teardown. Failed final material binding cleans up partial resources and
falls back to stock HUD drawing. The fixture verifies idempotent cleanup and
injects a binding failure after target creation. The source invariant initially
failed because it required the former direct binding-call spelling; updated it
to the protected call while retaining the completed-copy target requirement.
CTest hud_panel/compiler/invariants then passed 3/3. Still offline and undeployed.

Added the unimported, non-damaging melee overlap adapter using stock
PhysicsWorld.immediate_overlap box/sphere forms, explicit filter/rewind inputs
and a once-applied rotated volume offset. It snapshots all raw actor candidates;
no contact normals, damage eligibility or proven engine capacity are inferred.
The mocked fixture checks 100 candidates, query reuse, invalid geometry and an
incomplete result list. Windows CTest melee_probe/compiler/invariants passed
3/3 (22 Lua chunks). No headset use, deployment or live collision validation.

HUD targets now rebuild when the UI extent or HUD owner changes, migrating
retained records through the existing cleanup path. Stable frames reuse the same
targets. The fixture covers extent doubling, owner replacement, restoration and
release counts. CTest hud_panel/compiler/invariants passed 3/3. GPU completion
and visual transition acceptance remain untested; no deployment was performed.

Read installed sl*.dll file versions offline: all inspected Streamline modules
report 2.7.30.0. Downloaded official v2.7.30 include files into ignored diagnostics
and added an optional ABI-reference target, enabled only by an explicit external
include directory. The first compile correctly rejected access to the SDK's
private viewport field; replaced that check with a constructed-object byte-copy
comparison. Structure sizes/member offsets and the viewport value now pass,
with an explicit SDK version assertion. Windows Release /W4 /WX build passes;
CTest streamline_abi_reference passes. No external SDK files were added to Git
and no Streamline DLL was loaded or replaced for this validation.

Prepared offline StreamlineEyeTags for immutable depth/motion/HUD-less inputs
and separate left/right packed backbuffer extents. No API calls or GPU ownership
were added. The nonmovable owner keeps internal resource references stable;
failed preparation invalidates prior data. Tests cover subrects, input aliases,
dimensions and overflow, while the SDK-reference fixture compares GUIDs,
structure versions, buffer types and lifecycle values. Both Windows Release
test targets built with warnings as errors and CTest passed 2/2. The native live
path does not yet consume or submit these prepared tags.

Extended the offline melee probe with fixed-orientation box/sphere sweeps,
explicit capacity/rewind, immediate contact-scalar copying and saturation
reporting. Stock ActionSweep provides the box form; HitScan demonstrates sphere
rewind arguments. The fixture checks transformed centres, retained contacts
after query reuse, saturated versus empty results and invalid limits. CTest
melee_probe/compiler/invariants passed 3/3. Rotational orchestration and stock
stationary hilt-to-tip contact resolution remain separate integration work.

Added the offline stock hit-zone adapter: preserves dynamic shield priority and
weapon-specific tables, excludes self/dead/unregistered targets and omits the
stock head-facing rejection. Unknown hit zones remain unresolved for obstruction
handling. The combined collector fixture covers raised/lowered shields, priority
overrides, scenery and false/nil target-registration results. CTest hit-zone/
compiler/invariants passed 3/3 (23 Lua chunks). A process check found no remaining
Darktide or XR-harness process; no headset access was needed.

Extended the offline sweep planner with scalar pose snapshots and normalized,
shortest-arc spherical interpolation. Tests cover engine-input reuse, opposite
quaternion signs, invalid rotations, and a two-metre tip moving through a
180-degree arc with bounded substep travel. CTest melee_sweep_plan/compiler/
invariants passed 3/3. This is collision interpolation, not live hand smoothing.

Version-matched DLSS review also confirmed that input reuse on non-presenting
queues requires the plugin input-processing fence/value obtained on the Present
thread. Added that requirement to the prepared-tag contract and remaining work.
GetState's presentation count is since the previous query, so future submission
must coordinate with existing game queries. Documentation/comment change only.

Connected the offline melee diagnostic pass: fixed-tick claim, scalar history,
shortest-arc substeps, current overlap, and both box sweep orientations. Corrected
the primitive to compute start/end centre offsets from their respective actual
rotations while selecting the fixed query orientation independently. Tests cover
tip-only turns, duplicate/resimulated ticks, tracking recovery, reference changes,
long gaps and query exceptions. CTest diagnostics/probe/compiler/invariants
passed 4/4 (24 Lua chunks). No damage or live hook was added.

Latest user steering: stop switching between work areas; take one to completion.
Melee is the sole active area from this point. HUD and DLSS are parked. The
headset remains reserved for non-VD use, so live testing must wait for the user
to resume it; continue melee implementation and offline validation meanwhile.

VD resumed at the user's request; unattended testing is authorized while they
are away. Applied proximity Disable then Status. Ready preflight at 02:58:50 UTC
passed 120/120 renderable frames (VDXR 1.0.10), with Darktide closed. Report:
artifacts/unattended/melee-resumed-preflight-20260905.json (ignored, device-local).

Added an opt-in fixed-simulation melee query diagnostic. It only runs for the
local player in shooting_range/training_grounds, observes an actual selected
sweep action, and keeps that volume active while idle. Weapon changes clear the
volume, tracking/resimulation flags enter the simulation gate, and adapter
exceptions latch until the flag is toggled off/on. Origin remains provisional
controller grip; no damage, cooldown consumption or visual acceptance is claimed.
Enable with installed darktidevr_melee_probe.flag containing enabled.
CTest melee_live_probe/melee_diagnostics/lua_source_compile/lua_source_invariants
passed 4/4; pinned compiler passed 25 chunks. Native Release built with warnings
as errors. Live engine query and calibration evidence remain pending.

Added a stationary contact-manifold scan using the stock thin OBB cross-section
(local Z, half-length endpoints); spheres retain their stock initial-overlap
sweep. The diagnostic pass now includes it on fresh and stationary poses without
requiring movement. Geometry/copying and orchestration tests passed with compiler
and invariants (4/4). This change is queued after the first live diagnostic run.

First unattended diagnostic run deployed 0692567 and reached tg_shooting_range.
The browser initially retained focus; one bounded activation allowed the existing
foreground-only startup helper to continue. No focus loop was introduced.
At 03:13:12 UTC the adapter observed forcesword_p1_m3/action_left_heavy,
resolved the stock OBB (corner radius 3.0075 m), and completed continuous engine
queries (3 per sampled tick), no adapter errors. No targets were in the blade
volume, so this is query/API evidence, not enemy damage or occlusion acceptance.
XR reached 8,112 shared_ready/checked_ready/rendered_tag_ready, with ~59 fresh
pairs/s, zero interval fallback and one cumulative pose mismatch during startup.
Closed normally to deploy stationary manifold and timing diagnostics.

Added explicit windup-to-light/heavy timing resolution. Normal cadence follows
light -> start_attack -> next windup -> light, using the stock action handler's
effective scale and availability checks. Heavy charge includes the unscaled
hold-input threshold. Conditional/unknown routes reject with a diagnostic reason.
CTest timing/live_probe/compiler/invariants passed 4/4 (25 Lua chunks).

User redirected development to HUD and will perform melee contact verification.
Stopped the synthetic melee session and disabled the installed melee probe flag.
Second run confirmed four queries per sampled tick (including stationary contact
scan), no query errors, and live force-sword timing light=.35 s/heavy=.45 s.
Reached 9,113 shared-ready frames with ~55.7 fresh pairs/s and no interval fallback.
No enemy contacts or physical damage were verified. Unfinished synthetic target
query code was saved in a path-limited Git stash, not deployed.
HUD work continues on codex/hud-completion-2026-09-05.

HUD copy ordering: copy the previously authored frame before queuing new target
writes, and hide the world panel until a copy has been accepted. Copy exceptions
now disable the experimental panel and restore fixed status on the stock renderer
without drawing spatial elements twice. Fixture covers first-frame readiness,
once-per-frame copy, and failure fallback. CTest hud_panel/compiler/invariants
passed 3/3 (25 Lua chunks). GPU output validation follows in a dedicated HUD run.

HUD live a937f84: target creation/retained transfer succeeded (5 moved, 0 failed),
2496x1404 target and 1 m world surface logged, but shared-eye capture showed no
fixed status. Disable restored stock health/weapon/status correctly. Captures:
artifacts/diagnostics/hud-copy-20260905/{left,right,left-disabled}.png.
Next candidate keeps the terminal dependency sample inside the viewport with
zero alpha, testing whether offscreen culling pruned the target pass. No visible
corner pixel is intended. CTest HUD/compiler/invariants passed 3/3; live pending.

User reported fullscreen launches. Active root user_settings.config had
fullscreen=true/screen_mode=fullscreen, while the pre-worker backup had false/
window. Launch command and mod/scripts do not request fullscreen; trigger remains
unknown. Closed the game, backed up current config locally, restored only those
two root fields to false/window, preserving the VR resolution and graphics.
Verify persistence during the next launch. Backup is ignored machine-specific
artifacts/unattended/user-settings-before-window-restore-20260905.config.

Transparent terminal dependency candidate bcda7c0 still showed no fixed HUD in
shared-eye captures (artifacts/diagnostics/hud-transparent-20260905). Windowed
root settings remained false/window through startup and range entry. Disabled
HUD and requested normal closure. Added explicit diagnostic flag command: cyan
world backing plus magenta offscreen-target patch and opaque terminal sample,
only for separating geometry/content/pass-scheduling failures. Normal enable
keeps the dependency transparent. Pinned Lua compilation passed 25 chunks.

Geometry diagnostic 508b916 produced the cyan backing plane in shared-eye output,
but not the magenta texture marker. Thus the 3D surface renders; missing content
is upstream in target rendering/binding/copy. Capture:
artifacts/diagnostics/hud-diagnostic-20260905/left.png (right also saved).
Next diagnostic adds dedicated-world render submission counts and an explicit
source flag command to compare original target versus display copy. Source is
only a temporary diagnostic binding; normal enable restores display_copy.
CTest HUD/compiler/invariants passed 3/3. Closed the diagnostic run for sync.

Direct source-target diagnostic b9bcc02 also showed only the cyan backing, no
magenta marker (artifacts/diagnostics/hud-source-20260905/left.png). Restored stock
HUD afterward; fresh-pair rate recovered from ~26.6/s during source binding to
~60/s after disable. Direct source binding remains diagnostic-only.
The attempted separate ScriptWorld.render counter hook was rejected by DMF as an
active rehook, so its absent logs were not evidence of a missing world submission.
Moved observation into the existing stereo render hook. Lua gate passed 25 chunks.

Existing-hook observation 8228f83 confirmed dedicated HUD-world submission with
one active viewport and authored target state. Added sameworld diagnostic mode to
compare authoring through the existing gameplay UI renderer/GUI. Borrowed world
and renderer are never destroyed; targets/material/world GUI remain owned. The
ownership fixture initially lacked a borrowed GUI mock, corrected to represent
the live renderer; HUD test then passed. Lua compiler/invariants also passed.
Normal enable retains the dedicated-world path until this A/B is evaluated.

Sameworld A/B a5dceb7 still displayed only backing geometry. Borrowed gameplay
world logged continuing render submissions with two viewports. Screenshot:
artifacts/diagnostics/hud-sameworld-20260905/left.png. Returned to stock HUD.
Stock UIRenderer.script_draw_bitmap_3d passes material flags only for material
names, not existing handles; corrected the HUD call to that contract. The target
marker now uses Gui2.rect with explicit render_pass and a normal layer, matching
stock rectangle authoring. Lua gate passed 25 chunks; visual result pending.

71e7d4c still showed backing only (hud-material-20260905/left.png). Further stock
API comparison showed Gui2.bitmap_3d receives a Vector3 size from UIResolution,
while the prototype supplied Vector2. Corrected size to Vector3(width,height,0)
and added a draw-call contract fixture for size/UV types and material-handle
flags. HUD fixture passed; pinned Lua compiler passed 25 chunks. Visual pending.

HUD size candidate d2314a3 still showed cyan backing without target contents.
User moved the headset and observed old rectangles remaining at earlier poses,
eventually covering the view. Confirmed the HUD world GUI was retained despite
per-frame bitmap/backing creation. Changed it to immediate mode so the engine
expires previous frame geometry. Added a lifetime assertion to the HUD fixture;
HUD test passed and LuaJIT compiled all 25 chunks. The accumulated backing means
previous captures do not independently prove the target texture was empty: old
opaque geometry could occlude later panels. Recheck after the lifetime fix.
Official engine API documents immediate mode for World.create_world_gui:
https://help.autodesk.com/cloudhelp/2019/ENU/Max-Interactive-Help/lua_ref/obj_stingray_World.html

278a53b live check: fresh HUD target/init and nonzero shared_ready (~60 fps).
Both eyes showed one backing panel. Switching diagnostic to normal enable keeps
the same GUI/targets alive but stops drawing the backing; subsequent eye readback
showed it completely gone. This verifies frame expiration without relying on GUI
destruction. Captures: artifacts/diagnostics/hud-lifetime-20260905/{left,right,
left-cleared}.png. No synthetic headset motion used. HUD texture remains absent.
Next candidate removes GUI_RENDER_PASS_LAYER from the world presentation material;
stock UIRenderer adds that flag only for a named render pass. Target authoring
retains its existing flag. Diagnostic mode additionally draws a stock weapon HUD
icon to distinguish bitmap geometry from target sampling. Lua gate and HUD test
passed; live result pending.

World-material candidate e4fabfc still showed cyan only; even the stock icon via
Gui2.bitmap_3d was absent. This narrows the issue to bitmap presentation rather
than demonstrating an empty target. Next candidate uses the stock Gui.bitmap_3d
signature for the target and a second known-icon sample, retaining the Gui2 icon
in diagnostic mode for comparison. Fixture checks the legacy argument contract.

User requested 10% less panel height and width inside binocular overlap. Height
is now 1.0125 m at the same 1 m distance. Width intersects both recentered eye
frusta at all four panel corners, accounting for IPD and optical yaw/pitch, and
adds a 4% inset. Offline independent corner-reprojection checks and HUD fixture
passed; LuaJIT passed all 25 chunks. Legacy bitmap candidate c816276 still lacked
both icons behind the cyan backing; changed diagnostic backing to an outline so
depth ordering cannot hide the center bitmap samples in the next check.

d42e8a7 live readback showed all four outline edges inside both eye images at
1.476 m wide, 1.0125 m high, 1 m distance. Both bitmap API icon samples remained
absent even without opaque backing. User requested another uniform reduction to
80% of this size; applied after the binocular fit, retaining the same distance.
Expected current headset dimensions approximately 1.181 x 0.810 m. HUD fixture
checks the 80% scale and shortened height; Lua compiler and HUD fixture passed.

80% scale verified live in both eye captures (hud-scaled-20260905); logged
1.181 x 0.810 m at 1 m. Correction to bitmap diagnostics: weapon_icon_container
is a placeholder replaced by HudElementPlayerWeapon.set_icon, so its absence
does not establish a broken bitmap path. Replaced it with the fixed infinite
symbol used directly by stock HUD, plus a rect_3d material sample. Legacy
bitmap offsets now explicitly use Vector3 as documented by the engine API.

Fixed-symbol check 7ceebb6 still showed neither bitmap symbol. The rect_3d
optional-material sample produced a solid white square, not the symbol, so this
does not prove texture sampling. Next diagnostic reverses the plane normal for
one symbol to distinguish textured backface culling from two-sided colored
rectangles; panel size remains unchanged. LuaJIT passed all 25 chunks.

Breakthrough: 7e078a7 opposite-face symbol is visibly rendered in shared-eye
capture hud-facing-20260905/left.png, while the original-facing copies remain
absent. The texture surface was back-facing; colored rectangles hid that fact.
Applied viewer-facing basis to the panel and reversed U coordinates to preserve
text reading direction. Removed redundant symbol diagnostics. HUD fixture now
checks front-facing basis, U reversal and final scale. HUD test and 25-chunk
LuaJIT gate passed. Actual target contents still require next live readback.

1254f90 front-facing panel still lacks target content in both display-copy and
source binding captures (hud-front-20260905). Added symbol flag to test the exact
Gui2/UV-reversed presentation path using the known fixed symbol, and enlarged the
explicit diagnostic terminal sample to 320x180 for sameworld target inspection.
Normal mode keeps its transparent one-pixel dependency. Lua/HUD checks passed.

a182a8f symbol command shows the fixed symbol across the exact Gui2 panel,
confirming the front-facing/UV presentation path. Sameworld with enlarged screen
sample produces a visible magenta diagnostic in the top-left while the world
panel is blank. Restored the world render-target material's stock
GUI_RENDER_PASS_LAYER variant: removing it earlier was based on an unproven
assumption before the backface issue was known. Lua/HUD tests passed.

1439946 sampling variant still has no panel contents. Stock ScannerDisplayView
uses overlay_offscreen for its UI-to-world capture world (and no visible terminal
sample). Changed dedicated HUD viewport from overlay to overlay_offscreen to
match that offscreen use case. LuaJIT gate passed; runtime result pending.

25c6143 overlay_offscreen still showed outline without contents. Stock tactical
mask draws at matching screen positions, whereas item atlas materials expose
local rows/columns/grid_index UV selection. Next candidate uses the stock
item_container_square world material with use_render_target=1, placeholder=0,
one row/column, index 0, binding the completed copy to render_target. This keeps
authoring unchanged and tests local-UV sampling instead of screen-space masking.
Pinned compiler and HUD fixture passed.

680e643 atlas material remains blank for copy and direct source. Reworked the
normal capture path to bind the owned render target as the dedicated overlay
viewport's back_buffer (stock RenderTargetIconGeneratorBase contract). Fixed UI
now draws normally into that viewport, without a named pass or terminal sample.
The source target remains owned by the resource renderer; its destruction
metadata is restored for cleanup. Sameworld retains the older path only as a
diagnostic comparison. Fixture asserts viewport binding, absence of nested pass
redirection, and existing lifecycle/fallback checks. LuaJIT and HUD tests passed.

f3b1373 finally displays actual HUD contents; user confirmed visibility but
vertical inversion. Shared-eye readback after disabling diagnostics also retains
the magenta test patch, proving the viewport target needs an explicit frame clear.
Next revision reverses V UVs and clears the owned viewport to_screen pass before
new HUD authoring, once per frame. Panel dimensions stay at the accepted 80%.
Pinned LuaJIT gate (25 chunks) and hud_panel CTest passed, including upright UV
and once-per-frame clear assertions. Live visual verification pending.

e09af9c live readback confirms upright HUD in both eyes. A diagnostic-to-normal
transition reduced magenta pixels from 14,622 to zero without reallocating the
capture target: per-frame clearing is working. Live shared_ready exceeded 35k.
User requests 2x object sizing while preserving panel geometry. Fixed element
update/draw callbacks now use 2x effective scale, unwind settings on errors, and
restore original callbacks/scenegraphs on cleanup. Visibility/update callbacks
also route retained widget operations to their actual capture renderer.
Tag prompt investigation found stock centre-screen marker selection overriding
hand ray results, plus SmartTagging's interaction line missing from stereo
replay. Candidate selects from hand smart-targeting data and redraws the prompt
beside its marker for each eye. Forced tag scans and interaction checks receive
scoped local hand poses; other players and shared camera components stay intact.
LuaJIT gate, HUD, marker GUI and melee-aim fixtures passed. Live check pending.
