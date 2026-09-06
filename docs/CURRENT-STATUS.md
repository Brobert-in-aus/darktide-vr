# Current status and operation

Updated 6 September 2026. This page supersedes historical feasibility documents
for current defaults and operating instructions.

## Supported development path

Windows x64, Steam Darktide, Quest through Virtual Desktop/VDXR. Integration
requires the exact guarded game executable accepted by the launcher scripts,
DMF and the installed stereo mod directories. Development sync updates an
existing installation; it is not a clean installer. General OpenXR runtime and
character/weapon coverage remains experimental.

The ranged coverage candidate includes concrete gun/flame preparation routes,
dual-shiv/ability-knife throws and coupled grenade aim/release/arc preview. These remain
private-range hand-pose candidates awaiting worn firing checks; mission-server
transport and other thrown abilities are not complete. See the
[weapon coverage audit](RANGED-WEAPON-AUDIT.md).

The production path uses same-tick native shared eye textures, tracked head and
controllers, rigid hand proxies, controller input/aim and a depth reticle.
The runtime supplies eye dimensions (the current VDXR setup recommends
2496x2688). Historical 1920x2160 and other dimensions are evidence, not defaults.
Clustered-light visibility correction and billboard substitution are enabled
by normal sync. Full-body and fixed HUD-panel presentation remain experimental.

## Launch

R3 tagging and the left menu button now have game-side delivery through stock
HUD/UI handlers. Inherited gameplay button holds require release after entering
gameplay or reconnecting. Live initialization passes; worn button acceptance is
pending. See the [input revision audit](INPUT-REVISION-AUDIT.md).
The Gameplay controller bindings section now remaps the eleven existing
button/trigger/grip controls, including combat ability and separate jump/dodge
or interact/reload choices. Original defaults remain. Menu pointer controls and
aim hands are unchanged. Weapon, ability, interaction and tag HUD hints now use
compact VR binding labels. Dedicated glyph artwork, remaining tutorial hints
and right-stick gameplay are pending; worn readability acceptance remains open.

Mod Options > Darktide VR exposes HUD size, distance, and text/icon size sliders.
Defaults (100%, 2 m, 100%) preserve the accepted HUD layout. Distance changes
retain approximately the same apparent size; internal scaling leaves saved
Custom HUD positions intact. These controls apply while the HUD panel is active
and do not enable the experimental panel themselves. See the
[HUD options validation](handoffs/2026-09-06-hud-options.md).
The same section provides a Toggle editor button for the separately installed
Custom HUD dependency. Close menus after selecting it to enter or leave desktop
layout editing. See [editor integration](HUD-EDITOR-INTEGRATION.md).

Build Release and the pinned LuaJIT validator as described in the root README.
With no existing XR viewer, run:

```powershell
tools/quest/set-proximity-override.ps1 -Action Disable
tools/quest/set-proximity-override.ps1 -Action Status
tools/unattended/invoke-unattended-preflight.ps1
tools/stereo/start-darktide-vr.ps1 -EnterPsykhanium -ManualStartup
```

Ready preflight enforces Streamer/VDXR/awake-Quest checks and renders an XR smoke
session. `-Mode Inventory` collects observations without claiming readiness or
applying the proximity override. Failed rendering checks save runtime diagnostics
and mark the report as not ready. Resume VD after a passthrough suspension and
retry; suspension alone does not require a restart.

Start performs a Lua compiler gate and syncs Release files while Darktide is
closed. It follows Steam and the normal Fatshark launcher. The XR runner checks
the exact executable hash and rejects active EAC. Psykhanium entry must be armed
before game startup. After deployment, check fresh stereo initialization and
nonzero `shared_ready`; a working XR fallback alone is insufficient.
`-ManualStartup` leaves title and character selection to the user while still
arming Psykhanium entry before launch. During development, preserve Alt-Tab
ownership: runtime input must never reactivate the game in the background.

## Acceptance still pending

The 6 September [ranged aiming candidate](RANGED-WEAPON-AUDIT.md) hooks the
concrete hitscan, pellet, projectile and flame action classes before stock shot
preparation, preserving recoil/spread and simultaneous grouping. Flame damage
and suppression queries also use hand pose. Offline regressions and fresh live
initialization pass; actual hand-versus-head firing alignment awaits worn checks.
It retains private-range authoring and does not enable mission-wide combat.

September 5 live input validation exposed dead laser clicks and focus stealing,
then delayed activation of a previously missed click. A candidate now preserves
click arming across heartbeats, expires missed clicks after their UI frame and
respects foreground ownership. The user accepted character-selection highlight
and selection on the coordinate candidate. Use
`-ManualStartup` with the launcher to disable title/character key automation.
See the [September 5 session](handoffs/2026-09-05-development-session.md).

Finger animation, reticle depth, sword swings and left-hand alignment are accepted.
Staff melee/push still failed; a follow-up now
includes ranged-slot melee, pushes and their melee windups. Marker replay now
reuses the first eye's eased size instead of advancing it twice; the user accepted
symmetric shrinking. Staff animation and removal of the loading-screen corner
swatch still await explicit worn acceptance. A new movement/melee heading offset
is fixed by using the rendered cyclopean yaw directly; the user accepted it.
Shield and nearby mace sections still disappear after separating LOD FOV from
visibility overscan. Disabling mesh streaming also made no visible difference;
the user confirmed terrain LOD transitions repeatedly at roughly 3m. Multiplier
3 extended the distance; the user subsequently raised this machine's setting
to 9 because transitions remained obvious. A portable release default is unproven.
Finer LOD tuning and selective smoke-cloud billboard suppression are tracked in
[post-release work](POST-RELEASE.md).

## This machine's configuration and release requirements

This workstation has a Ryzen 7 9800X3D: 8 physical cores, 16 logical processors.
The worker/texture-pool experiment was rolled back at the user's request:
max_worker_threads=13 and max_texture_pool_size=1024 are the recorded original
values; lod_object_multiplier=9 is retained. Default launches preserve them.
Development tuning requires explicit -TuneWorkerThreads and derives
max(1, physical core count - 1), never logical processors/hyperthreads. Eventual
release auto-configuration remains to be implemented and validated.

The user accepted hand-directed melee on the recovered combat-direction build.
Movement remains head-relative. Left-hand block direction is implemented but
untested. The user has now accepted left-hand alignment.

A follow-up blur guard now zeroes scene
depth-of-field and fullscreen-blur values immediately before the shading
environment is applied. This covers camera/mood and menu paths that write
environment values directly. Offline checks pass; the follow-up initialized
successfully in the next run at 01:04:06 UTC and reached fresh stereo rendering.

Two runs hit an engine graphics-resource handle mismatch after approximately
16.5 minutes. Allocation tracing isolated rapid handle accumulation to retained
world-marker capture: disabling reprojection stopped growth and re-enabling it
restored growth in the same process. A candidate now reuses an immediate marker
GUI and hides it between eyes, preserving the projection calculations. Offline
lifecycle checks pass. The candidate ran beyond 20 minutes without the prior
crash, with over 70,000 shared-ready frames and an unchanged fresh allocator
cursor of 85,363 across repeated snapshots. This removes the observed rapid
growth; longer worn/transition checks remain pending. The user accepted the
marker baseline, with very slight asymmetry at extreme edges deferred to
[post-release work](POST-RELEASE.md).
Hand-aim acceptance stands. See the session handoff for crash evidence.

Lighting parity in both hub and Psykhanium remains an outstanding worn check.
Left-hand placement is accepted; subtle extreme-edge marker polish is deferred.
The crosshair atlas-square fix was accepted; wrist joint-drift telemetry did not
prove overall glove alignment. See the [checkpoint](handoffs/2026-09-04-development-session.md).

Repository maintenance tests do not resolve these visual findings. A 60-minute
worn stability/transition session is still required for the Phase 1 exit gate.

## History and maintenance

- [Implementation and validation record](maintenance-plan-2026-09-05.md)
- [Phase 1 chronological history](phase1/development-history.md)
- [Design brief](DARKTIDE-VR-DESIGN-BRIEF.md)
- [Infrastructure](PROJECT-INFRASTRUCTURE.md)

Phase 0 observation policy, test-only feasibility models, and historical shader
probes document earlier experiments. They do not describe the current renderer
or establish current launch authorization. Keep diagnostic switches explicit;
do not turn old experiments into production defaults merely because they build.

Tracked physical melee has a separate [design and source investigation](TRACKED-MELEE-DESIGN.md):
always-active standard combat volume, per-enemy cooldowns and intentionally
unlimited cleave, with heavy readiness initially on cooldown. It is not enabled
in the current build. Interim hand-directed stock attacks are accepted;
left-hand blocking still needs worn validation. See the
[motion smoothing investigation](MOTION-SMOOTHING.md) for aim and weapon policy.

The user owns physical melee contact verification. Menus and the HUD baseline
have been accepted; DLSS is the current development task. Keep the configured
proximity override for this continuing live session and restore automation when
development ends.
Automated results do not establish worn visual or physical acceptance.
See [remaining development](REMAINING-DEVELOPMENT.md) for the current code seams
and next integration work in each area.

## Accepted packed-output checkpoint (5 September)

User confirms VR world rendering, loading screens and desktop mirror all work
on e8bcfe4. This fixes the oversized transparent-colour pass without changing
HUD composition. Eye size comes from OpenXR; DLSS internal dimensions come from
the engine's selected quality. No fixed headset resolution or quality ratio is
used. Current observed sizes are 2496x2688 per eye and 1664x1792 internal.

The AMD swapchain wrapper receives real eye-sized replacement buffers while
Streamline keeps the 4992x2688 packed presentation target. Desktop/loading
presentation blits fill the wide target from the appropriate monoscopic source.
Both original input-size guards and the stricter upscaler colour checks pass.

Reproduce this diagnostic checkpoint only after Ready preflight:

```powershell
tools/stereo/start-darktide-vr.ps1 -EnableHudPanel -EnterPsykhanium -StreamlineStereoSwapchainProbe -StreamlineTargetTokenProbe
```

This is **not completed DLSS frame generation**: default launches stage no new
stereo tags and no generated stereo is published to XR. The one-shot packed Present copy
passed unattended on 6 September with `-StreamlineStereoStageProbe`, including
GPU fence completion and continued fresh XR pairs. An additional explicit
`-StreamlineStereoSubmitProbe` now completes a fresh-pair API submission,
cleanup and input retirement; the native-target report also passes. Adding
`-StreamlineStereoSubmitFrames 4` passed four fresh batches with monotonic GPU
fences and safe input reuse. Two ordinary Presents intervened between batches;
this is not continuous stereo generation. Later state queries reported two
frames per eye, but that counter covers the interval since the previous query,
not an identified generated stereo output. Next is successive-frame history
and generated-output identity. Publication is blocked on a compatible output
observation boundary: the installed NGX evaluator validates its caller, so a
normal trampoline detour is unsuitable. No such hook was installed. Per the
user's instruction, development moves to the ranged aiming backlog after this
documented checkpoint. See the
[unattended continuation](handoffs/2026-09-06-dlss-unattended.md).
The diagnostic proxy retains at most 16 images until process exit; proper GPU
retirement/recycling is required for release. Restart after runtime resolution
changes; unequal per-eye recommendations are explicitly unsupported by the
current shared ABI. Details and validation are in the
[DLSS handoff](handoffs/2026-09-05-dlss-offline.md).
