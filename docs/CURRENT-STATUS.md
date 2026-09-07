# Current status and operation

Updated 7 September 2026. This page supersedes historical feasibility documents
for current defaults and operating instructions.

**Development resumed 7 September:** the user is at work and cannot verify in
headset today. Continue automated/offline work and record worn checks as pending.
The saved controller/onboarding candidate initialized in the hub after Ready
preflight, with fresh stereo messages and nonzero shared_ready. That run is
closed. All subsequent runtime candidates remain undeployed. Game/XR are closed
and normal proximity behavior is restored. ADB dismissed the inspected tracking
prompt, and a SideQuest-derived Guardian preference pause/resume route was
verified by headset logs. It did not fix rendering: the latest settled Ready
attempt created an OpenXR session but failed creating its first eye texture.
VDXR reports `-7000`; the application device reports no removal or D3D12 debug
messages. The internal cause and suspected accidental double tap remain
unestablished. Guardian was restored with logged confirmation, then proximity
Enable/Status ran. See [Quest recovery](QUEST-PASSTHROUGH-RECOVERY.md). Continue
useful offline work; repeat live readiness when new evidence justifies recovery.

Latest requested candidate: [Psykhanium online rules](PSYKHANIUM-ONLINE-RULES.md).
It defaults on for the next range visit, uses stock input history and firing
origins, and retains stock movement/combat rules. This source is not deployed;
actual online mission support and worn acceptance remain pending.

[Draft review #2](http://192.168.8.181:3000/robert/warhammer-40k-darktide-vr/pulls/2)
collects the continuation: shared LT menu secondary clicks, optional
item/stim/device and hub target bindings, corrected UI ownership guards,
scanner stick reference and luggable hand trajectories. See
[mission interaction coverage](MISSION-INTERACTION-AUDIT.md). Mission body/input
and hand aim require local simulation authority; remote-server missions remain
gated pending [attack ownership work](MISSION-AUTHORITY-AUDIT.md).

Offline [UI detail measurement](DLSS-UI-DETAIL.md), precise Present timing and
[health summaries](PERFORMANCE-HEALTH-ANALYSIS.md) improve the next image-quality
and performance investigation. Motion blur remains unresolved; no framerate
gain or worn acceptance is claimed. Existing old Present timings remain coarse.

Windows x64 full Release build succeeds with the spectator controller candidate
on `codex/spectator-controller-route-2026-09-07`; the XR harness remains
at `4298262`. Pinned LuaJIT compiles 37 chunks and the full offline CTest
checkpoint passes 116/116 in 15.52 seconds, with headset tests disabled and ordinary
D3D12 checks now explicitly skipping OpenXR discovery. The stock null-service
guards cover both render and fixed input updates through `596c459`. Optional
stock contracts through `b6f74b4` cover input history/replay, movement, combat,
objectives and supplies, including pellet batches, hitscan effects and stock
ledge/vault rules. Ledge discovery follows recorded hand aim; head-relative
walking does not independently redirect its search toward the headset. Engine
math, collision, damage and service endpoints have explicit fixture limits;
these do not establish online or worn acceptance. The local cached catalogue
identifies 30 Psyker-tagged ranged templates, not the user's owned guns. See the
[current handoff](handoffs/2026-09-07-development.md). A 20-minute task heartbeat
is active; continue the ordered todo until instructed to stop.

The undeployed spectator route follows the jump binding (A by default) with
matching hints and independent camera input rearming. It works without a local
character in the offline checks and preserves stock UI, rescue and target
decisions. Actual stock-method integration passes; observer view/comfort and
mission lifecycle still need live acceptance.

**Historical 6 September end-of-day checkpoint:** development was stopped; Darktide/XR were closed and
normal Quest proximity behavior is restored. Start tomorrow with the
[6 September handover](handoffs/2026-09-06-end-of-day.md) and
[current ordered todo list](REMAINING-DEVELOPMENT.md#current-priority-order-end-of-6-september-2026).
User accepts both turning modes, tested menu changes and the right unarmed wrist.
Hub/combat profile and shared notification/tutorial hint changes through 04b6053
pass offline validation but have not been deployed; installed Lua remains 2477d82.
The planned relaunch was cancelled for wind-down. Talent deactivation's right-click
hint is deliberately retained as a broad-pass check. Subsequent user direction
reactivates DLSS image-quality work: fix blur first, then duplicated/displaced
elements, which may be separate. DLSS-related and general performance optimization
are active tasks. See [first mission readiness](MISSION-READINESS.md) for the
explicit mission-mode/input/aim restrictions and minimum end-to-end test scope.
The 7 September continuation above supersedes this shutdown/deployment state.

## Supported development path

Windows x64, Steam Darktide, Quest through Virtual Desktop/VDXR. Integration
requires the exact guarded game executable accepted by the launcher scripts,
DMF and the installed stereo mod directories. Development sync updates an
existing installation; it is not a clean installer. General OpenXR runtime and
character/weapon coverage remains experimental.

The ordinary launcher, development sync and readiness preflight discover Darktide from
Steam's registry roots, library list and app manifest. Explicit `-GameRoot`
overrides discovery; multiple valid installations require an explicit choice.
Stale manifests without the executable are skipped, malformed metadata is
rejected and no files are changed by discovery. Modern/legacy library fixtures,
explicit selection, ambiguity and launcher regressions pass ten focused checks;
read-only discovery also finds this workstation's existing installation. Other
standalone diagnostics retain their own GameRoot parameters. The preflight's
discovery change passes parsing and existing discovery/readiness checks without
starting a live session. No clean-install
or live-launch acceptance is claimed.

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

Head-pose starvation during bounded DLSS submissions is diagnosed and corrected:
the pair-driven image wait now services fresh tracking independently. Before the
change, seven reads rejected 343�469 ms-old poses; the same four-batch test now
has zero failed reads. The delay comes from recreating two NVIDIA FG features
on each diagnostic entry/exit (328�391 ms Presents). Image submission remains
pair-driven, the 250 ms pose freshness gate is unchanged, and worn flicker
acceptance remains pending. See the [output-boundary handoff](handoffs/2026-09-06-dlss-output-boundary.md#head-pose-starvation-investigation).

## Launch

`-AutoEnterHub` arms a one-shot stock Start callback after character-select
readiness remains valid for a second. `-EnterPsykhanium` includes it;
`-ManualCharacterSelect` disables it. Live automatic Start is verified. Keyboard
Enter is intentionally suppressed by the VR pointer layer, so the helper only
sends title Space while foreground and observes the subsequent Start callback
and loading transition. It is bound to one game process/log, exits after startup,
and never steals focus. Per-launch logs are under ignored `artifacts/unattended`.

The bounded consecutive DLSS experiment passes eight stereo frames with 14
reported generated-eye Presents and 14 complete NGX evaluations completing on
the GPU. The `-DlssGeneratedStereo` development candidate now continuously
publishes generated stereo to XR using eight reusable input owners, three
generated-output slots and three queued originals with exact resource/pose
association. The queued run delivered over 2,640 generated pairs. The user
confirms HUD flicker is fixed by supplying final eye colour alongside separate
HUDless tags, but perceived framerate remains low. Active intervals delivered
roughly 29–31 originals/s plus generated images despite about 119 compositor
submissions/s; compositor submissions are not a distinct-image performance pass.
Spacing alone did not resolve perceived smoothness. Throughput measurement found
about 48 rendered pairs/s but only 28–35 original mailbox deliveries/s. The new
three-slot original transport bypasses that loss: live XR now receives about
48 originals plus 48 generated images/s, and 65 originals/s when NVIDIA stops
generation after foreground loss. The HUD fix remains accepted; overall
smoothness and the remaining reduction from the user's roughly 70 FPS baseline
remain open. The new frame loop waits for distinct images while tracking stays
independent: latest live intervals deliver 100–102 distinct pairs/s with zero
cached-image submissions, including about 50–51 originals/s. Runtime-reported
rate and worn smoothness still require user confirmation. Six focused tests,
including an isolated WARP original-ring ownership/pixel check, pass.
See the [continuous delivery handoff](handoffs/2026-09-06-dlss-output-boundary.md#continuous-generated-stereo-delivery).
A single
startup side-by-side frame is still reported by the user; investigate separately
from the previously corrected stale-pose wait dependency.

Optional menu-laser stabilization is available with `-MenuAimStabilization`.
Ordinary launches retain direct tracking. It shares one filtered ray between
hover, clicks and laser presentation; gameplay weapons remain direct. The trial
has offline reset/jitter/input checks but needs worn comfort/tuning acceptance.
See [motion smoothing](MOTION-SMOOTHING.md).

R3 tagging and the left menu button now have game-side delivery through stock
HUD/UI handlers. Inherited gameplay button holds require release after entering
gameplay or reconnecting. Live initialization passes; worn button acceptance is
pending. See the [input revision audit](INPUT-REVISION-AUDIT.md).
The Gameplay controller bindings section now remaps the eleven existing
button/trigger/grip controls plus four optional right-stick directions, including
combat ability and separate jump/dodge
or interact/reload choices. Original defaults remain. Menu pointer controls and
aim hands are unchanged. Weapon, ability, interaction and tag HUD hints now use
compact VR binding labels. Dedicated glyph artwork, remaining tutorial hints
and right-stick turning are pending; worn readability acceptance remains open.
Directional shortcuts default to Unbound and require neutral return after menu,
tracking or binding transitions; menu scrolling retains its existing controls.

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
observation boundary: the installed feature-library evaluator validates its
caller, so directly detouring that export is unsuitable. A guarded observer at
the outer NGX runtime export is now built, with a pinned parameter-ABI test and
bounded output-record analyzer. `-NgxOutputProbeAtStereoSubmit` reserves its
capture window for the first prepared stereo submission. The outer runtime and
feature-lifetime hooks now pass live compatibility: six complete observations
are identified as frame generation and match the per-eye input snapshot
addresses. Subsequent diagnostics establish the runtime-derived packed output
extent, correct left/right legacy backbuffer rectangles, and completion fences
on the actual NVIDIA compute queue for all six complete evaluations. Output pixel
ownership, source-frame association and continuous feature history remain open.
The four-batch diagnostic still causes
user-observed stereo/side-by-side flicker; visual acceptance is rejected.
The observer remains opt-in and does not publish generated XR output. See the
[current boundary candidate](handoffs/2026-09-06-dlss-output-boundary.md) and
[unattended continuation](handoffs/2026-09-06-dlss-unattended.md).
The diagnostic proxy retains at most 16 images until process exit; proper GPU
retirement/recycling is required for release. Restart after runtime resolution
changes; unequal per-eye recommendations are explicitly unsupported by the
current shared ABI. Details and validation are in the
[DLSS handoff](handoffs/2026-09-05-dlss-offline.md).

## DLSS Custom HUD editor recovery, 6 September 2026

F3 now uses a dedicated final desktop overlay and explicit menu presentation.
Live rendering shows the Custom HUD border, list and properties; closing it
resumes approximately 51 original + 51 generated distinct frames/s. Menu/binding
interruptions pause generation with GPU-safe input retirement rather than
permanently stopping it. The XR consumer can fall back to fresh legacy stereo if
the original ring expires. Dragging/persistence and worn acceptance remain open.
See docs/HUD-EDITOR-INTEGRATION.md and the ignored
artifacts/unattended/dlss-editor-overlay-live-20260906.log.
The original-render performance regression remains open; this does not declare
frame generation complete.

### 2026-09-06: base-framerate cost investigation, first measurement

Custom HUD right-click/scroll repair has user acceptance. Keyboard/mouse are
supplemented by VR input, not intentionally suppressed by the menu adapter.

New opt-in continuous-submission GPU timestamps use the existing performance
profile switch. Each input owner owns six queries and a 48-byte readback buffer.
The two eye captures and stereo packing/original publication are measured
separately. Results are read only when normal owner completion has already
retired; profiling introduces no fence waits. Default launches allocate none of
these resources. Timings survive the finite verbose-log budget, one aggregate
per 120 recycled owners. Missing profiling resources do not disable rendering.

Live run: artifacts/unattended/dlss-base-profile-20260906.log, PID 131700.
Archived evidence: artifacts/diagnostics/dlss-base-framerate-20260906/.
52 timing windows: median sum of capture-left, capture-right and pack/publication
GPU spans = 0.488 ms. Component medians 0.1384, 0.1407, 0.22325 ms (medians do not
add to the median of sums). These are GPU execution spans, not CPU submission
times, and do not include NVIDIA async generation or generated-output transport.
69 steady foreground/generation-active health windows: median engine 50 fps.
35 steady background/generation-inactive windows with original ring still live:
median engine 72 fps. Existing coarse Present CPU median was 0.0 vs 0.44 ms;
its timer granularity prevents interpreting 0.0 as zero cost. FG evaluates two
eye regions per original pair, 2496x2688 each, in a 4992x2688 packed target;
no extra evaluations or incorrectly doubled eye extent found in captured data.

This is NOT a controlled foreground FG-on/off A/B: user motion/scene/focus and
GPU scheduling can change. It narrows the cause: measured integration copies
are much smaller than the approximately 6 ms source-frame delta. NVIDIA's
Streamline 2.7.30 guide lists 2.77 ms at 4K on RTX 4090 for one 2x evaluation;
two large eye evaluations plausibly account for much of the delta, but that is
context, not measured attribution or proof that all overhead is unavoidable.
Source: https://raw.githubusercontent.com/NVIDIA-RTX/Streamline/v2.7.30/docs/ProgrammingGuideDLSS_G.md
Remain open: matched foreground A/B and precise GPU timeline of NVIDIA async
work, generated-output copying and rendering contention. Do not optimize away
ownership fences, alter required extents, or disable quality without evidence.

Validation: Release native and continuous-recovery targets built; ctest
continuous_recovery (profiling enabled across partial/complete captures and
pause/resume), original_stereo_ring, streamline_submission and
streamline_input_lifetime all passed. Live timing readback also verified.

HUD blur follow-up from user research: check motion vectors and depth beneath
HUD boundaries, not only HUDless color. Captured HUDless/final per-eye extents
match; no UI color/alpha is currently provided. Do not zero the world's velocity
under UI rectangles: that destroys background motion and our stabilized HUD and
world markers are not static screen-space overlays. Capture the actual separate
UI alpha/color or compose after generation. Unreal plugin composition settings
are not directly applicable to Darktide's engine. No blur fix claimed yet.

### 2026-09-06: foreground comparison and NGX GPU timings

The user disabled frame generation in the stock graphics menu. Same live process,
resolution and Quality SR setting, foreground gameplay: 75 steady off windows
median 70 fps versus 134 generation-active windows median 50 original fps.
This removes focus as the off switch; scene/head motion were not frozen, so it
remains an observational same-session comparison rather than a deterministic
benchmark. Both original-frame output paths continued rendering normally.

New opt-in NGX GPU profiler: 32 query/readback/fence owners, no waits, safe reset
of unsubmitted samples, exact post-submit fence retirement before reuse. Handles
both direct and compute lists; NVIDIA uses the compute queue here. Samples bracket
Evaluate and the following output work on that command list. They do not claim
independent-engine timelines outside that list. Default profiling remains off.

Live PID 140744, artifacts/unattended/dlss-ngx-compute-profile-20260906.log.
56 windows per eye: median GPU Evaluate 2.06335 ms left, 2.06055 ms right.
Post-evaluate work 0.0740 ms left and 0.0001 ms right; this run evaluated right
before left, and the stereo copy occurs after the second eye. Combined measured
NGX spans plus prior input/copy publication approximately 4.7 ms versus the
50-to-70-fps source-frame difference of 5.7 ms. No duplicate FG evaluations or
oversized eye subrect found. The former 30-original-fps issue is absent. Most of
the current base-rate reduction is explained by real two-eye generation work;
remaining queue/contention/scene variability is post-release profiling work,
not evidence of a particular fix to make now. No claim that every millisecond
is unavoidable, and no image quality or ownership safety was reduced.

Validation: Release native and GPU timing tests built; ngx_gpu_timing and
ngx_gpu_timing_compute both pass capacity/reset/completion/readback and both-eye
aggregation checks. original_stereo_ring, continuous_recovery and
ngx_command_observations also passed before compute-specific extension.
Evidence archived under artifacts/diagnostics/dlss-base-framerate-20260906/.
Frame generation remains OFF in the user's live graphics setting after this test.
Re-enable for the next deliberate generated-HUD validation, not as a silent
background setting change.

Next: user rapid-headshake evidence identifies an entire world-space HUD element
shifted/duplicated beside its correct position in generated frames. Acceptance
must include fast real head movement, not just stationary clarity. Prioritize a
separate UI color/alpha or post-generation composition path while preserving
background velocity; do not zero world motion under the HUD.

### HUD frame-generation isolation work, 2026-09-06

Per-eye UI colour/alpha submission and fenced capture ownership are implemented
and tested (b267429). The native transparent GUI replay experiment and paired
alpha readback checker are now implemented; they remain observation-only until
same-frame recomposition proves complete panel/marker coverage. No generated-HUD
visual fix is claimed yet. The desktop mirror live-FG-off fix (6f69762) is included
in the current test build. First replay test identified a missing viewport-hook
dependency; the corrected second run is being checked. Details and commands are
in docs/handoffs/2026-09-06-dlss-output-boundary.md.

### HUD alpha diagnostic crash correction (2026-09-06)

The third capture run crashed at its first eligible GUI replay. The engine reported
an access violation executing address zero; source audit found the capture clear
called original_clear_render_target_view, whose hook is installed only by broader
render diagnostics. The opt-in alpha capture does not enable those diagnostics.
The clear now uses the command-list COM method, as the existing menu capture does.
Target redirection additionally refuses to run without its required trampoline.
The temporary alpha-capture flag was removed after archiving the failed run.

Validation: Windows x64 Release native target built; five focused CTest cases
(ui_capture_blend, continuous_recovery, streamline_submission,
streamline_stereo_inputs, streamline_abi_reference) and all three Python alpha
checker tests passed. git diff --check passed. Live replay and complete UI coverage
remain unverified; no claim of corrected generated-frame HUD appearance yet.
Local evidence: artifacts/diagnostics/hud-alpha-capture-20260906/third-run-crash.tsv
and third-run-crash-console.log (excluded from Git).

### Transparent HUD composition verified in both eyes (2026-09-06)

The combined candidate capture was correctly rejected as fully opaque despite
zero RGB residual. Isolating VS 634962454189541227 / PS 4439945837785333492
identified the HUD panel; the other candidate is excluded. Replay now retains
the original draw's corrected billboard bindings until the duplicate completes.

The sixth run passed both alpha checks at runtime 2496x2688: zero missed changed
pixels, zero invalid premultiplied pixels, alpha range 0..255, zero residual pixels
above tolerance 3. Maximum channel error was 1.922 left / 1.490 right (8-bit).
The exported transparent image visibly contains the panel and world markers.
Evidence: artifacts/diagnostics/hud-alpha-capture-20260906/sixth-run-comparison.
This validates composition for the observed scene, not generated-frame visual
acceptance across all gameplay. Next: connect to fenced per-eye UI tag 23 inputs.
Release native build passed; live run remained stable with generated stereo.

### Opt-in UI alpha connected to generated stereo (2026-09-06)

DARKTIDEVR_STREAMLINE_UI_ALPHA=1 or the local temporary flag
`darktidevr-streamline-ui-alpha.enabled` now enables sustained HUD replay plus
UI tag 23. Each eye copies its matching-pose transparent source into its existing
fenced continuous owner before tagging; UI dimensions come from runtime textures.
Missing/rejected/stale captures skip the pair instead of reusing older UI.
The opt-in keeps replay running after diagnostic export. Default runs are unchanged
pending worn visual acceptance. No source-path flag or device ID is committed.

The seventh live run reported ui_alpha=1, generated stereo about 50+50 FPS,
nonzero shared_ready and no continuous-submission failure. Paired source readback
again passed: zero missing/invalid/residual pixels above tolerance, max channel
error 2.333 left / 1.471 right. User rapid-head-turn acceptance is pending.
Future readbacks can now inspect exact fenced UI owner textures (COPY_DEST) rather
than earlier replay sources; that small diagnostic change was built after this
launch and is not yet deployed. Release native and recovery targets built; the
five focused CTest cases passed. No Lua changes. Evidence: seventh-run-comparison
and seventh-run-tagged.tsv beneath the existing local HUD-alpha diagnostics dir.

### Worn acceptance failed; experimental UI submission disabled (2026-09-06)

User report: no improvement to HUD blurring, severe intermittent frame drops after
about 30 seconds. The live census shows known GUI draws increasingly rejected and
repeated present_binding_or_gap pause/resume cycles. The earlier composition pass
is limited to the sampled scene and is not acceptance of the generated image.
The game was closed and both temporary alpha flags removed. Keep this feature
opt-in; do not enable it in the default launcher.

Added direct read-only NGX boundary reporting for DLSSG.UI and its resource/extent
using keys found in the installed Streamline DLL, plus bounded rejected-draw
shader/depth/alpha details. An unsupported GUI draw now latches the experimental
route off for the session, clears its active bindings through the existing pause
path, and stays on original stereo rather than oscillating frame generation.
Native Release build and diff check passed. Boundary/rejection diagnostic pending.
Evidence: seventh-run-framedrops.tsv in the local HUD-alpha diagnostics directory.

### Ninth combined run and separate UI-layer foundation (2026-09-06)

The combined run supplies distinct NGX DLSSG.UI resources for both eyes, format 28,
runtime extent 2496x2688 at offset 0,0. Exact fenced-owner readback passed in both
eyes (zero missing/invalid/residual pixels; max error 1.933 / 1.455). Capture-only
alpha normalization eliminated the observed GUI rejections; generated stereo held
about 50+50 FPS beyond the previous 30-second failure window. Focus=0 periods are
reported separately. Worn blur acceptance is still pending/previously failed.
Local evidence: ninth-run-combined.tsv, ninth-run-ngx-ui.log, ninth-run-health.log,
and ninth-run-owned-comparison beneath the HUD-alpha diagnostics directory.

The consumer associates generated world images with an interpolated midpoint
pose. Excluded UI may instead retain endpoint coordinates; this is an active
hypothesis, not a proven new root cause. Building explicit UI separation avoids
requiring one image to share two source poses and guarantees UI stays outside FG.

Foundation now implemented but NOT connected to the live view: a premultiplied
OpenXR UI projection layer using runtime dimensions and explicit source poses;
optional paired original/UI shared textures protected by the same ring fences.
Original transport frame_index=1 indicates separated UI content; generated frame
indices retain their existing meaning. The WARP UI-ring test verifies both eye
colours/alpha, wrong-extent rejection, independent slot contents and ring reuse.
Native target, UI-layer library and original-ring tests built. Both normal and UI
ring tests passed. Full harness relink was deferred because the live harness exe
is running; no deployment of this foundation yet.
Remaining: consumer pairing/copy/layer integration, clean-world FG inputs, preserve
desktop mirror/menu behaviour, combined live stability and worn motion acceptance.

### 6 September: HUD/FG investigation parked by user

The user requested moving on from the pose-mismatch investigation. Duplicated or
displaced HUD elements and blur around HUD/world markers are separate unresolved
symptoms. Do not mark either fixed or attribute both to pose. Matched generated
readback confirms UI at current-frame coordinates in a stationary sample only;
that cannot establish motion behaviour. The latest combined run stayed about
50-52 real + generated pairs/s beyond 30 seconds without HUD replay rejection.
The separate UI-layer foundation remains inactive; the unfinished motion-trigger
experiment was removed. Full native/harness builds and focused checks passed.
See the DLSS output-boundary handoff for evidence and validation limits.
Development moves to right-stick smooth/snap turning.

### Right-stick turning implemented; live acceptance pending

Smooth default (90 degrees/s, adjustable 30-180), snap45, snap90 and Off are now
in Mod Options. Horizontal right-stick shortcuts are reserved while turning is
on; saved mappings remain available with turning Off. Neutral is required after
snap/menu/tracking/context/settings interruptions. Shared scene heading carries
the yaw for rendering, hands and locomotion; no mouse input is generated.
The 32-chunk LuaJIT gate and nine focused CTests pass. Worn turning direction,
comfort, pivot and hand/weapon alignment still need checking. See INPUT-REVISION-AUDIT.

Turning live initialization passed in the range: fresh shared stereo (ready 359),
about 51.6 real + 51.6 generated pairs/s, no fallback/pose mismatches or matching
Lua error. Deployed module matches source. Worn controls remain unverified;
no synthetic stick inputs were used. Keyboard/mouse routes remain unchanged.

User acceptance: both smooth and snap turning work (c27ee63). Turning is complete
for the requested modes; ongoing work is native-menu controller hints.

### Native-menu hint implementation

Known menu Back and pointed-click labels now use B / Menu and Point + RT.
Clickable stock input-legend footers use Point + RT; unsupported hotkeys remain
stock. Menu and gameplay labels share one InputUtils hook to avoid DMF replacing
an existing handler. Input routes, keyboard/mouse availability and gamepad mode
are unchanged. The 33-chunk LuaJIT gate and seven focused CTests pass. Live
readability/coverage checks remain; see INPUT-REVISION-AUDIT for exact scope.

Menu hints live-load successfully: fresh shared stereo (ready 652), no matching
Lua error, and exactly one shared InputUtils prompt hook. Footer appearance and
readability await observation; no further interaction-routing change was made.

User acceptance: menu changes verified (be43948). Work continues on the reported
right-wrist offset in the unarmed hub pose.

### Right unarmed wrist correction candidate (6 September)

The accepted left-hand fix used a rigid controller-relative wrist offset; right
still combined grip-up with body-right/body-forward/world-up residuals. Applying
the same rigid-vector policy to right preserves its neutral (+3,-4,+4 cm) offset
while rotating all components with grip yaw/roll. Left's accepted calculation is
unchanged. The shared helper covers articulated IK, rigid glove placement and
reach estimation; no weapon aim or attack direction code is changed.

Pinned LuaJIT passes 33 chunks. Seven focused CTests pass: wrist_transform,
turning, gameplay_heading, ranged_aim, melee_aim, animation_aim and
melee_animation_owner. The wrist fixture checks both neutral offsets, roll,
inversion, right yaw and body-heading independence. Worn right-hand placement
remains pending. The next launch goes to hub without automatic Psykhanium entry.

### Hub launch automation correction (6 September)

The first right-wrist hub run unexpectedly entered Psykhanium: the fresh console
reported armed source=one_shot_flag. The launcher previously left stale requests
untouched on hub launches and restored their old contents during cleanup.
Each closed-game launch now owns a unique enter/disabled request; hub launches
explicitly disable entry. Cleanup removes its own request without restoring an
older command, and cannot delete another launch's still-armed request. Attaching
to an existing game does not arm or disable range entry.

All five launcher CTests pass, including stale request ownership, early failure,
startup focus and play transition. The focus fixture was updated for the current
state/owner-guarded dispatcher; it also verifies stale title readiness cannot
inject into gameplay. No real desktop input is used by these tests. Retry log:
artifacts/unattended/right-wrist-hub-retry-20260906.log. Worn wrist acceptance
remains pending; automated readiness cannot establish alignment.

### Additional worn acceptance and hint coverage (6 September)

User confirms the unarmed right hand is fixed (2477d82). The retry reached
hub_ship with automatic Psykhanium entry explicitly disabled and nonzero shared
stereo readiness. The earlier menu acceptance covers tested routes, not every
prompt: the hub unused-talent-points notification still says press [I].
Add a broad binding-hint pass across menus, notifications, tutorials and
contextual popups. Identify each action's actual controller route before changing
its label; if no route exists, add/plan that route rather than displaying a
nonfunctional button. Keyboard/mouse must remain available.

## Hub/combat controller profiles candidate (6 September)

Following the user's request to reuse the limited controls by context, hub now
has per-control overrides with Same as combat inheritance. Existing vr_bind_*
settings are preserved as combat bindings. Right grip defaults to inventory in
hub and remains weapon special in combat; other hub controls inherit by default.
Movement/turning and native-menu pointing/back/scroll routes are unchanged.
Changing context cancels old semantic state without emitting charged-release
edges, and quarantines held controls until release/neutral. Hints can query the
same effective profile and revision rather than a second binding map.

Inventory is delivered through the stock UIManager hotkey owner, retaining its
mode whitelist, transition/modal/null-input gates and view validation. Requests
expire on a blocked update and never replay. One shared input_service hook
composes the existing menu pointer and the gameplay hotkey adapter; there is no
keyboard injection or global template mutation. Keyboard/mouse remain usable.

Pinned LuaJIT passes 33 chunks. Seven CTests pass: menu_input, turning,
menu_prompts, gameplay_ui_input, hud_options, controller_bindings,
controller_prompts. Tests cover hub/combat inheritance, held context switches,
stock hotkey gates, shared hook coexistence, return values and keyboard input.
Candidate is not yet deployed; current running hub stays on accepted 2477d82.

Broad hint audit acceptance cases: unused-talent-points notification showing [I],
and talent deactivation showing right-click. User explicitly requested leaving
the latter untouched as a check for the broader automated pass. Do not mark a
hint pass from source inventory alone or rename a shortcut without a working
controller route. Handedness source audit is recorded in HANDEDNESS-AUDIT.md;
left-handed gameplay is not implemented by these binding profiles.
