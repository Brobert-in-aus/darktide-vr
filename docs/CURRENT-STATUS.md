# Current status and operation

Updated 5 September 2026. This page supersedes historical feasibility documents
for current defaults and operating instructions.

## Supported development path

Windows x64, Steam Darktide, Quest through Virtual Desktop/VDXR. Integration
requires the exact guarded game executable accepted by the launcher scripts,
DMF and the installed stereo mod directories. Development sync updates an
existing installation; it is not a clean installer. General OpenXR runtime and
character/weapon coverage remains experimental.

The production path uses same-tick native shared eye textures, tracked head and
controllers, rigid hand proxies, controller input/aim and a depth reticle.
The runtime supplies eye dimensions (the current VDXR setup recommends
2496x2688). Historical 1920x2160 and other dimensions are evidence, not defaults.
Clustered-light visibility correction and billboard substitution are enabled
by normal sync. Full-body and fixed HUD-panel presentation remain experimental.

## Launch

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

September 5 live input validation exposed dead laser clicks and focus stealing,
then delayed activation of a previously missed click. A candidate now preserves
click arming across heartbeats, expires missed clicks after their UI frame and
respects foreground ownership. The user accepted character-selection highlight
and selection on the coordinate candidate. Use
`-ManualStartup` with the launcher to disable title/character key automation.
See the [September 5 session](handoffs/2026-09-05-development-session.md).

Finger animation, reticle depth and sword swings are accepted. Left-hand
alignment remains unresolved. Staff melee/push still failed; a follow-up now
includes ranged-slot melee, pushes and their melee windups. Marker replay now
reuses the first eye's eased size instead of advancing it twice; the user accepted
symmetric shrinking. Staff animation and removal of the loading-screen corner
swatch still await explicit worn acceptance. A new movement/melee heading offset
is fixed by using the rendered cyclopean yaw directly; the user accepted it.
Shield and nearby mace sections still disappear after separating LOD FOV from
visibility overscan. Disabling mesh streaming also made no visible difference;
the user confirmed terrain LOD transitions repeatedly at roughly 3m. Multiplier
3 extends the distance and is accepted as sufficient for the initial release.
Finer LOD tuning and selective smoke-cloud billboard suppression are tracked in
[post-release work](POST-RELEASE.md).

## This machine's configuration and release requirements

This workstation has a Ryzen 7 9800X3D: 8 physical cores, 16 logical processors.
max_worker_threads=7 was applied on 5 September 2026 (top-level active setting).
Seven is this machine's setting, not a portable mod default. The launcher now
derives max(1, physical core count - 1) automatically, using physical
cores rather than logical processors/hyperthreads. Preserve this distinction in
installation and performance documentation.

The user accepted texture pool 2048, seven workers and LOD 3 for now. The pool
is machine-local; future release defaults still need comparison on other GPUs.

The user accepted hand-directed melee on the recovered combat-direction build.
Movement remains head-relative. Left-hand block direction is implemented but
untested; left-hand alignment still needs a worn verdict.

The September 4/5 candidate has outstanding worn checks for both unarmed and
wielded palm placement, pinned-marker
alignment at every eye edge, and lighting parity in both hub and Psykhanium.
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
in the current build. Interim stock attacks and left-hand blocking remain under
worn validation.
