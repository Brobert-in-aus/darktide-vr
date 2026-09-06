# Remaining development: melee, HUD and DLSS

Updated 6 September 2026. User accepts the e8bcfe4 packed-output checkpoint:
VR world rendering, loading screens and desktop mirror all work. Subsequent
opt-in development now delivers generated stereo to XR continuously. The user
confirms the generated-frame HUD flicker is fixed, but perceived performance
remains low; frame generation is not release-complete.

The [menu audit and rework](MENU-INTERACTION-AUDIT.md) replaces native-menu
rectangle reconstruction with stock UI input delivery and consistent DPI
handling. User now confirms Options cursor alignment and Operative highlight/
selection, plus premium-store input. After follow-up fixes for confirmation
popups and premium-store vertical compression, the user said "Menus seem good."
This is acceptance of tested routes, not every possible view. The source pass covers
all 72 registered views and direct View-service consumers. Pickup marker edge
asymmetry remains open.

Return-session follow-up: desktop wheel scrolling and a scrollbar drag failed
to move the Darktide VR Mod Options list at character selection. New right-stick
dropdowns remain unverified below the fold. Reproduce and inspect desktop versus
controller pointer ownership; the cause is not established. See the
[input audit](INPUT-REVISION-AUDIT.md).

The user has taken ownership of melee contact verification and explicitly moved
development to HUD and then DLSS. Preserve accepted HUD/menu behavior and
continue DLSS, completing one body of work before switching to the next. The
latest instruction permits switching on a documented DLSS blocker. The former
output-association blocker is resolved: the opt-in generated-stereo path has
delivered thousands of generated pairs. Pacing/performance is the current task;
the original-ring and distinct-image wait now deliver about 100–102 distinct
pairs/s in live intervals, with no cached submissions. Worn acceptance and the
remaining roughly 70-to-50 original render-rate regression remain open.
See the [continuous delivery handoff](handoffs/2026-09-06-dlss-output-boundary.md#continuous-generated-stereo-delivery).
The ranged aiming candidate is awaiting worn validation. Unattended follow-up
has progressed through HUD options/editor integration and input revision below.
The melee query prototype remains non-damaging; user verification is not a claim
that physical damage integration is complete.

## Feedback from the 6 September hub test

- Right hand is medially offset while unarmed in the hub. Compare both hands'
  grip-to-wrist transforms; the weapon-equipped pose may conceal the right-side
  issue. The cause is a hypothesis until traced; prior left-hand acceptance stays.
- Add right-thumbstick left/right turning: smooth by default, with selectable
  45-degree and 90-degree snap modes. Reserve the default horizontal axes for
  turning, resolve their interaction with optional shortcuts, and require neutral
  return for snap repetition and input/context changes.
- Add handedness support. Audit dominant/support-hand roles, aim, block, two-hand
  poses, attachments, effects and prompts before deciding which weapon assets
  need mirroring. A global negative scale is not an established implementation.
- Menu footer/back hints still show keyboard bindings (for example Esc). Existing
  VR label work covers scoped gameplay HUD hints; extend native-menu hints using
  their actual select/back routes without forcing global gamepad UI mode.
- Manual hub-to-Psykhanium entry crashed in mission-speaker popup material
  destruction. This signature differs from the historical remote-husk
  `parent_unit_id` race. Investigate GUI material ownership during HUD transfer
  and teardown. A candidate now releases all fixed-widget material caches before
  their capture GUI is destroyed; its regression passes. Live transition
  acceptance remains pending. See the [crash handoff](handoffs/2026-09-06-hud-material-transition.md).
- The subsequent transition reached gameplay on desktop but froze VR. Fresh
  pairs were rejected by an unchanged gameplay-generation resume gate. A pending
  commit now survives orientation-owner creation during loading and retries in
  gameplay after restoring heading. See the [resume fix](handoffs/2026-09-06-loading-generation-resume.md);
  worn transition acceptance remains pending.
- The first live NGX stereo-submit diagnostic intermittently displayed two
  side-by-side frames in VR during initial gameplay before settling to stereo.
  Inspect packed-output fallback and presentation transitions; successful API
  transactions do not establish visual acceptance of this diagnostic.

## Ranged weapon aiming backlog

6 September worn feedback rejects the current non-staff candidates: gun and
reticle directions do not align, a second crosshair remains on the HUD despite
Custom HUD hiding it, and ordinary shots do not visibly hit. Pushing the muzzle
into an enemy produces damage only on some shots. Inspect muzzle/hand transform
conventions, projectile/raycast origin and direction, and collision exclusions;
self-collision is a hypothesis, not an established cause. Audit the HUD crosshair
visibility route separately. Do not describe the candidate as working across
weapon families based on offline tests or initialization counters.

The [source audit and candidate](RANGED-WEAPON-AUDIT.md) identifies copied-class
hook bypass, post-increment simultaneous grouping and independent flame query
routes. The candidate directly hooks the five shooting classes before stock
preparation and passes offline regressions. The dual-shiv throwing special now
has its own guarded spawn/launch pose hooks with live initialization verified.
Live firing acceptance is pending. Generated grenade overhand/underhand routes
now couple action aim, delayed release and arc preview to the right hand;
physical arc/impact acceptance and mission-server pose transport remain open.
Zealot and Psyker knife spawn/launch now use explicit template guards; Psyker
retains its existing hand-authored smart targeting and homing policy. Knife
firing acceptance, luggable throws/drops and mission transport remain open.

User reports that ranged weapons other than the force staff do not fire along
the intended aim. Perform a pass across every class and ranged weapon family,
including every firing mode: hip fire, aimed fire, charged/released attacks,
burst/automatic fire, alternate/special attacks, hitscan and projectile weapons.
Check the reticule, muzzle origin, projectile/raycast direction and actual hit
location against hand aim while the head faces elsewhere. Include force staff
as a regression control; do not assume one shared firing hook covers all actions.
This is a newly reported functional bug, not a completed fix. Prior user
acceptance of hand-directed melee does not establish ranged aiming correctness.

## Melee implementation

Hand-directed button attacks and left-hand placement are accepted. Implement
physical contact according to [the selected rules](TRACKED-MELEE-DESIGN.md).
The offline foundations cover volume dimensions, rotational query planning,
contact deduplication, effective timing, per-target cooldowns and simulation
ownership. A non-damaging overlap adapter now has offline geometry/result tests;
an opt-in private-range adapter now connects it to fixed simulation. It observes
an actual selected sweep action and retains its volume while idle. The grip
origin is provisional, and no physical damage is applied.

Next integration work:

- [Timing audit completed](MELEE-TIMING-AUDIT.md): 0.35/0.45 s are not universal
  attack cooldowns. Combo transitions vary, minimum heavy input and automatic
  completion differ, and longer holds can grant windup/fully-charged bonuses.
  The resolver now exposes the separate auto-completion threshold and charge
  source. Carry these distinctions into the future damage/proc adapter.
- The bounded ordinary combo resolver now distinguishes a separate opener and
  repeating loop with per-step effective intervals. Same-named windup reentry
  refreshes timing in the opt-in probe. Live coverage across equipped weapons
  and conditional/unsupported routes remains open; do not use the first attack's
  0.35 s as a blanket cooldown or advance a combo separately for every enemy hit.
- Resolve the wielded weapon's explicit normal/heavy action routes and effective
  timing through its live action context; reject unsupported routes visibly in
  diagnostics rather than substituting guessed damage or timing.
- Integrate the non-damaging overlap adapter and add sweeps, preserving shield/world blocking
  and reporting saturated queries. Calibrate the grip-to-volume transform with
  a visible overlay when worn testing resumes.
  The live diagnostic report now resolves stock hit-zone/shield priority and
  deduplicates each target while retaining unresolved scenery; this is sampled
  reporting, not verified obstruction or damage eligibility.
- Introduce a dedicated stock damage context with explicit proc lifetimes and
  prediction ownership. Validate continuous contact and multiple targets before
  adding weapon specials. Do not invoke the stateful stock action hit routine
  indiscriminately on every overlap.

See [motion smoothing](MOTION-SMOOTHING.md): minimal physical-weapon lag, optional
light aim stabilization, one shared sample policy for presentation and attacks.
The reusable angular filter and opt-in menu-laser trial now pass offline tests;
weapon/grip integration and worn tuning remain open. Physical melee stays direct.

## HUD

Menu follow-up (6 September): immediately after character selection loads,
highlighting works but clicks appear unconsumed for about one second. Investigate
view enter/input-readiness gating and pointer click delivery against that precise
transition. Do not queue the missed click for later replay. A passive live trace
now measures 0.572 seconds of the stock transition null service before list and
Start readiness. A later native audit found and removed a separate 1.25-second
menu-age lockout while retaining release arming; see the
[diagnosis and bounded logging](MENU-INTERACTION-AUDIT.md). A controller click
during this interval was not reproduced, and any ignored click after readiness
remains open.

The fixed-panel prototype is in `darktidevr_hud_panel.lua`, disabled by default.
It separates spatial elements from fixed status elements and uses a dedicated
offscreen target plus a completed-copy resource for world presentation. World
markers retain the accepted immediate-GUI path. Extreme-edge marker asymmetry
is [post-release polish](POST-RELEASE.md), not a reason to redesign that baseline.

The draw hook now restores the stock renderer and full element list after any
partitioned draw failure. Its offline fixture covers error recovery and once-per-
frame fixed authoring across two eye draws. This establishes CPU state recovery,
not GPU copy ordering or worn legibility.

The panel now rebuilds on UI resolution or HUD-owner changes, reusing its targets
through stable frames. Offline tests cover these transitions and partial setup
cleanup. Binding the capture target as the viewport backbuffer now produces
visible HUD contents, confirmed by shared-eye readback and the user.

Next: verify hand-selected stereo tag prompts and transitions; then make
the fixed status layout configurable without moving world/depth markers onto
the panel. The panel is two metres away. After the user reported opposite
inner-edge clipping in the two eyes, centre it on the binocular intersection
and reduce uniform panel scale from 0.8 to 0.7 (12.5% smaller). User accepted
edge fit and requested a further 10% reduction for next launch: scale 0.63,
height 1.27575 m, width approximately 1.90 m. Internal
object scale and saved layout remain intact. The user
requested these reductions; both-eye readback confirms the outline fits, while
worn comfort still needs acceptance. World GUI draws now expire each frame,
fixing the user's observed accumulation at old head poses. The visible texture
initially arrived vertically inverted and retained old pixels. Both corrections
now pass shared-eye visual checks. Current effective object scale is 2.08x
(the user requested 80% of double, then another 30% increase). Buffs and combat
ability sit above the health bar, aligned to its left/right edges; their baseline
gap is now 80 logical units after the user reported overlap at 28. Panel following
was accepted in principle but softened to a critically damped spring for slower
acceleration, then a 4-degree angular deadband with no hard catch-up clamp.
The user accepted that follow feel. Translation now follows the current head
exactly, keeping the panel centre at its configured distance; only horizontal/vertical
angles follow smoothly, with roll removed. Weapon prompts now sit 220 logical
units above the health bar. These latest changes await worn acceptance.
Frame-rate independence and pose-reset behavior have offline coverage.
Retained update/visibility operations now route to their capture renderer.
Smart-tag popup stereo is user-confirmed; selection now uses the reticle hit
directly after the user reported the assisted target was still inconsistent.
Pickup targeting is user-confirmed, but popup edge-size asymmetry remains open.
The layout editor is exposed through VR mod options using Custom HUD as a
separately installed optional dependency. The inspected distribution has no
explicit redistribution license; no source is bundled or copied into the VR mod.
See [editor integration and dependency policy](HUD-EDITOR-INTEGRATION.md).
HUD sliders are implemented in Mod Options > Darktide VR: panel size (50–150%,
default 100%), distance (0.75–4 m, default 2 m), and text/icon size (50–150%,
default 100%). Defaults retain panel scale 0.63 and internal scale 2.08.
Distance scales the physical panel to preserve approximately the same angular
size. Internal scaling refreshes fixed HUD elements without changing saved
Custom HUD item positions or world markers. Live desktop input and menu reopen
were checked; worn acceptance of non-default values remains pending.
Gameplay bindings now expose the eleven existing button/trigger/grip channels
in Mod Options, retaining original defaults and adding combat ability plus
separate jump/dodge and interact/reload. Changing a held binding releases its old
action and requires release before the replacement can activate. Weapon,
ability, interaction and tag HUD prompts now display compact binding labels;
dedicated controller glyphs and tutorial/spectator/onboarding coverage remain.
The [input revision audit](INPUT-REVISION-AUDIT.md) maps current controls: right
stick scrolls menus and now offers four optional gameplay shortcuts, all unbound
by default. R3 tag and the left menu button
now reach stock HUD/UI handlers; live module initialization passes, with worn
button acceptance pending. All inherited gameplay holds are quarantined until
release on activation/reconnect. Use
the available controls to make the full layout more sensible. Review gameplay,
weapon specials, movement, interactions and menu
contexts together, including hold/toggle behavior and conflicting actions.
Remaining controller prompts, right-stick turning and revised ergonomic defaults
remain backlog work. The configurable mapping candidate needs worn validation.
Desktop layout editing now draws "Use the desktop view to edit your HUD layout."
into the shared HUD texture while the editor is open. It is removed on close.
An XR freeze occurred with synchronized producer frames continuing; the harness
now logs cached-pair gating reasons to diagnose recurrence. The prototype stays disabled by
default while loading, menus and transitions receive dedicated checks.

## DLSS

The packed-output rendering checkpoint e8bcfe4 is worn-accepted: world colour,
HUD, loading screens and desktop mirror all work. Native preparation and the
updated analyzer validate matching depth/motion/upscaler-input sizes and
runtime-sized upscaler output, HUD-less colour and named final eye textures.
See [current operation](CURRENT-STATUS.md) and the
[chronological handoff](handoffs/2026-09-05-dlss-offline.md) for flags and evidence.

The accepted fix gives the AMD swapchain wrapper genuine eye-sized resources,
while Streamline retains the real wide presentation buffer. Viewport mappings
alone did not isolate transient HDR/upscaler allocations. The HUD remains on
its separate path. Full-image desktop blits handle the wide destination;
loading uses the current engine buffer instead of a stale stereo frame.

Final dimensions are the active OpenXR runtime recommendation. Internal colour,
depth and motion dimensions come from the engine's actual DLSS quality-dependent
resources. Do not hardcode a headset size or Quality-mode scaling fraction.
Runtime changes currently require restart; unequal eye recommendations fail
explicitly. Existing 640..7680 validation bounds (3840 eye width in packed mode)
are supported-size limits, not clamped rendering targets.

Historical integration steps (superseded by continuous delivery below):

1. Bounded packed Present copy completed on 6 September with matching extents,
   fence completion and continuing fresh XR pairs. Worn visual acceptance of
   this additional step remains separate. See the
   [unattended handoff](handoffs/2026-09-06-dlss-unattended.md).
2. Wire paired constants/tags into the established Present route. Preserve
   partial-call failure cleanup and per-eye input completion-fence ownership;
   the opt-in one-shot submit probe now completes fresh-pair staging, Present,
   tag cleanup and input retirement. It uses the game's existing constants and
   observed tagging API. The native-target report also passes. The four-batch
   follow-up verifies fresh inputs and GPU-safe owner reuse; it has two ordinary
   Presents between batches. Later queries report two frames per eye since the
   previous query, not a proven generated stereo output. Extend this to
   successive frames with coherent history. Default launches do not stage new tags.
3. Establish generated-output identity tied to the submitted stereo batch.
   An asynchronous Present or nearby queue execution is only a candidate;
   input-retirement fences do not prove generated output is ready.
4. Publish only a complete, fence-ready generated stereo pair with coherent pose
   and transport identity. Continuous generation and XR publication are not done.
5. Replace the diagnostic engine-buffer owner's 16-image process-lifetime
   retention with verified GPU retirement/recycling. Validate repeated resize,
   menu/loading transitions, runtime resolution and DLSS quality changes before
   promoting these explicit diagnostic flags to release defaults.

Validation: native and XR Release builds pass, all 27 LuaJIT chunks compile,
eye-target lifecycle/resolution fixtures pass, and five focused Streamline/GPU
CTest cases pass. WARP verifies proxy identity/resize/RTV support and full-image
mirror blitting. The user accepted the final live world/loading/mirror result;
that acceptance does not extend to not-yet-enabled frame generation.

Current remaining work: validate the measured-cadence scheduler and distinct
image rates, improve low source throughput, then exercise repeated menu/loading
transitions and resolution/quality changes. The eight input owners and three
generated slots now recycle with completion fences; broader lifecycle and engine
buffer retirement still require review. Default launches retain the accepted
baseline. See the continuous delivery handoff for current commands and evidence.

The current machine retains LOD 9 and restored pool/workers 1024/13. Worker
tuning is opt-in with -TuneWorkerThreads. Release auto-configuration must use
physical cores, not logical processor count. Keep this separate from DLSS work.
