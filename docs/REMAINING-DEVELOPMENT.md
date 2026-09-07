# Remaining development: melee, HUD and DLSS

## Current priority order: end of 6 September 2026

This list supersedes task ordering and pending labels in the chronological
details below. Development resumed on 7 September; the user has since returned
home and established a working headset session. Continue from the
[current handoff](handoffs/2026-09-07-development.md); record worn checks only
when actually observed. Earlier at-work/pending labels below are historical.
Latest steering: restore free 6DoF with a 10 cm collider chase using ordinary
movement inputs and acceleration/braking prediction. The
[roomscale candidate](ROOMSCALE-COLLIDER-FOLLOW.md) passes offline checks; the
user closed VD and requested the ranged-weapon pass when worn checks are needed.
Prioritize ranged aim/reticle agreement and firing across all families next.
Firing-only aim switching remains on hold. The
[server capability assessment](ONLINE-SERVER-CAPABILITY-ASSESSMENT.md) is complete;
the user accepted the deployed one-metre staff visual convergence candidate.
Earlier 7 September steering: investigate online-server missions alongside local
missions. See [online requirements](ONLINE-MISSION-REQUIREMENTS.md) for the stock
input route, authority limits and implementation/validation sequence. This is
the active investigation; remote mission gameplay remains disabled.
The user's next instruction is implemented as a deployed
[Psykhanium online-rules candidate](PSYKHANIUM-ONLINE-RULES.md): stock input-frame
aim and origins, with explicit range-only training and live-validation limits.
The user confirms reticle-directed, face-origin shots from forcestaff_p4_m1;
this is not acceptance of other weapons or an official online mission.
Updated after the user's follow-up: DLSS image quality is active again, blur
first; performance investigation is active work. See [mission readiness](MISSION-READINESS.md)
for the smaller set needed before a first end-to-end mission attempt.

1. **Finish controller contexts and the broad binding-hint pass.** Deploy/test the
   saved hub/combat profiles and inventory shortcut; verify remap persistence,
   neutral/release guards, keyboard/mouse coexistence and matching hints. Complete
   the automated source/runtime review across menus, notifications and tutorials.
   Use the talent-points [I] reminder and talent deactivation right-click as
   acceptance cases. The shared onboarding fix is prepared; talent deactivation
   must remain untouched as an isolated patch, per the user's instruction.
   7 September: saved profiles deployed and initialized in hub; worn checks
   pending while the user is at work. Shared LT secondary-click transport/input
   and common hints are now an offline candidate, with no talent-specific patch.
   The current source inventory covers 138 hint calls in 47 files. Stock null
   input services now block controller/synthetic delivery; handler, unit, remap
   and queued-HUD ownership checks pass offline. Stock held=false release rules
   remain a limitation; suppressing explicit release edges is not universal
   charged-action cancellation. Worn reminder and talent checks remain pending.
2. **Enable mission gameplay and verify transition stability.** Extend the explicit
   hub/range-only VR input/body and range-only hand-aim gates with appropriate
   mission ownership/replication handling; removing guards alone is insufficient.
   Verify the selected loadout and essential objective/team interactions, then
   launch/loading, extraction/results and return to hub. Manual hub-to-Psykhanium, menu/popup close,
   loading and Custom HUD editor transitions need a focused regression check.
   Existing material-lifetime/resume fixes are candidates; distinguish actual
   recurrence from the historical base-game remote-husk race. Confirm early
   character-select clicks after stock readiness. Hub automatic-entry leakage is
   already fixed and its retry passed; do not reopen that resolved bug.
   7 September: a shared local-authority mission policy is an offline candidate
   (the latest integrated offline suite passes 121/121). Remote-server missions remain gated. See
   [mission authority](MISSION-AUTHORITY-AUDIT.md); no mission/SoloPlay acceptance.
   Launcher cleanup now attempts later flags, owned-process cleanup and range
   request retirement even when an earlier restoration fails. Eight focused
   offline checks pass; live transition and cleanup acceptance remain pending.
   Automatic hub/range launches now also reject flat-fallback-only viewer
   success using completed shared-stereo counters. Eight focused checks pass;
   fresh Lua initialization and worn visual acceptance remain separate checks.
   The spectator candidate uses the jump control (A by default) and matching
   hints through a separate camera reader. Stock cycling/rescue contracts and
   independent input cancellation pass offline; observer comfort and actual
   mission lifecycle remain pending.
3. **Finish ranged-weapon functionality across classes.** Verify actual firing,
   gun/reticle alignment, muzzle origins and impacts with hand aim away from head
   direction for every gun/flame/staff/projectile/throw mode. Preserve stock
   spread/homing and exclude self-collision only where justified. Candidates are
   not worn-accepted across families. Mission pose transport and remaining throws
   remain open; include staff as a regression control. The user has bought ranged
   guns on their Psyker: equip them through the Operative menu for aim/muzzle/impact
   checks. Exact models are not yet inventoried; do not assume all families covered.
   The read-only local catalogue has 30 Psyker-tagged ranged templates (22
   hitscan, four pellet and four staff), but no owned-inventory response. Stock
   firing/targeting/throw and pellet/hitscan contract checks now pass with engine
   and damage substitutes. This narrows source coverage, not live acceptance.
4. **Fix DLSS image quality, blur first.** Reactivated by the user. Treat blur and
   duplicated/displaced HUD elements as possibly separate issues; isolate and fix
   blur first, then investigate duplication/displacement. Do not assume a common
   pose cause or repeat the rejected approach without new evidence. Generated
   stereo delivery is working; the old output-association blocker is resolved.
   7 September: [matched opaque UI detail](DLSS-UI-DETAIL.md) is now measurable
   offline with stricter completed-capture identity checks. The saved static
   sample with optional UI input retains 95.9–97.8% contrast in selected opaque
   pairs; this does not resolve motion blur or describe the current default.
5. **Performance optimization.** Investigate the framerate loss when enabling
   DLSS, separating super resolution from frame generation with controlled
   comparisons. Revisit the measured two-eye FG cost without assuming it is all
   unavoidable. Also perform a general CPU/GPU/frame-pacing pass in representative
   combat, including HUD/marker and stereo-render overhead. This is active work,
   no longer solely post-release profiling. Preserve the pool/worker rollback.
   7 September: the offline native candidate now measures Present with a
   high-resolution clock, preserving fractional milliseconds and labelling
   the new clock in logs. Existing measurements cannot be retroactively refined;
   controlled live SR/FG comparisons remain pending.
6. **Complete physical melee.** User owns complex contact verification. Finish
   continuous contact/obstruction, per-target cooldowns using real combo timing,
   heavy-charge rules, and dedicated stock damage/proc/prediction ownership.
   Follow TRACKED-MELEE-DESIGN, including the selected cleave policy. The current
   query probe applies no damage. Button-driven hand-aimed melee is accepted.
7. **Implement handedness.** Follow HANDEDNESS-AUDIT: dominant/support roles,
   anatomical hands, weapon attachments/models, block/cast/throw/contact origins,
   effects, two-hand poses and accurate controls. Do not globally mirror the
   skeleton or swap raw tracking as a shortcut. A shared role foundation now
   routes combat consumers and passes the 107-test offline suite, with runtime
   still fixed to the accepted right-dominant policy. Attachment/effect mapping,
   input rearming, presets and pointer choice remain before exposing the feature.
8. **Test SoloPlay for in-mission functionality, after Psykhanium acceptance.**
   The user supplied `_downloads/SoloPlay` (Nexus mod 176). Keep this fairly late:
   first get the planned VR functionality working properly in Psykhanium, then
   check SoloPlay compatibility and use it for mission combat, objectives,
   interactions, performance and lifecycle tests. Use the supplied standalone
   copy, not the older copy under `_downloads/deluxghost-darktide-mods` by accident.
   This is a future test task; nothing has been installed or launched for it.
   SoloPlay results do not establish online mission-server compatibility.
9. **Finish release configuration and usability checks.** Validate non-default
   HUD sliders, binding/menu ergonomics and remaining controller glyphs. Preserve
   the separate Custom HUD dependency/licensing policy; complete portable setup,
   runtime/resolution lifecycle and machine-configuration handling. Worker policy
   must use physical cores. Existing HUD/menu options are implemented, not a new
   task to rebuild them.
   The ordinary launcher, development sync and readiness preflight discover Steam libraries and
   the Darktide app manifest, retaining explicit GameRoot selection for multiple
   copies. Ten focused checks pass. This is existing-installation portability,
   not a clean installer or live launch validation.
10. **Post-initial-release optimization/polish.** LOD policy beyond machine-local
   LOD 9, tiny extreme-edge marker asymmetry, selective smoke-only suppression,
   and remaining nonessential visual polish. General/DLSS performance is now
   tracked in active priority 5. Keep the rolled-back pool/worker tuning trial off.

Completed/accepted: smooth and snap turning; tested menu changes; left and right
hand alignment; hand-directed button melee; the hub launch stale-request fix.
Candidate 04b6053 (hub/combat bindings, stock inventory hotkey delivery, shared
onboarding/tutorial hints) was deployed on 7 September after Ready preflight.
Hub launch and stereo initialization passed; that run is now closed and normal
proximity behavior restored. Worn controller/hint acceptance remains pending. See the current
handoff for exact tests and evidence.

## Historical subsystem detail and evidence

Entries below preserve earlier findings and implementation history. Their older
"next", "pending", and "current task" statements do not override the list above.

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

### F3 regression follow-up (6 September 2026)

The Custom HUD desktop editor now has its own final overlay viewport and explicit
menu route under DLSS. Live display and return to generated stereo pass; user
layout dragging/persistence and worn readability remain to check. Maintain this
open/close check in DLSS menu-transition acceptance. Original performance versus
the user's approximately 70-fps pre-DLSS baseline remains a separate open task.

### September 6 worn feedback after editor recovery

F3 editor visible/functional: user PASS. Reopening was reported; one late
open/close pair was the agent's explicit visual check. No repeating F3 script was
found; diagnostic HUD flag is consumed and dependency keybind is pressed-only.
Do not add automated F3 inputs while the user tests.
Generated motion now feels consistent with reported frame rate: user PASS.
Remaining image-quality issue: blur around HUD and world item markers. Inspect
true premultiplied UI colour/alpha isolation; current FG tags HUDless only.
A separate stock-centre-crosshair suppression is prepared and passes LuaJIT and
hud_panel tests; deployed live confirmation remains pending. WeaponCounter is
weapon-specific charge/lockout UI, not the crosshair. User layout is unchanged.

## 6 September task change requested by user

Park the DLSS HUD pose-mismatch investigation. Track duplicated/displaced HUD
and blur around HUD/world markers separately; both remain unresolved. Latest
combined capture showed stationary current-coordinate UI and stable timing only,
not worn motion acceptance. The separate-layer route stays inactive. Next active
backlog item is right-stick turning: smooth default, 45/90-degree snap options.

### Right-stick turning implementation checkpoint

The requested smooth default and 45/90-degree snap options are implemented, with
configurable smooth speed and a turning-Off mode for horizontal shortcuts.
Offline input/heading/options/aim regressions and 32-chunk LuaJIT validation pass.
Live initialization and worn checks remain; do not mark comfort/pivot accepted.

User confirms both smooth and snap turning work. Requested turning modes are
accepted; native-menu binding hints are now the active backlog item.

### Right wrist candidate: same rigid calibration policy as left

The right-hand helper retained a mixed body/grip-space correction after the
accepted left fix. Right now uses the mirrored rigid grip-space vector, retaining
neutral calibration; shared IK/glove/reach callers use that one helper. Seven
targeted regressions and the 33-chunk LuaJIT gate pass. Hub unarmed and subsequent
weapon-equipped placement remain for worn validation; no visual pass is claimed.

### Additional worn acceptance and hint coverage (6 September)

User confirms the unarmed right hand is fixed (2477d82). The retry reached
hub_ship with automatic Psykhanium entry explicitly disabled and nonzero shared
stereo readiness. The earlier menu acceptance covers tested routes, not every
prompt: the hub unused-talent-points notification still says press [I].
Add a broad binding-hint pass across menus, notifications, tutorials and
contextual popups. Identify each action's actual controller route before changing
its label; if no route exists, add/plan that route rather than displaying a
nonfunctional button. Keyboard/mouse must remain available.

Hub/combat profiles are prepared offline; see INPUT-REVISION-AUDIT. Preserve talent deactivation's right-click hint as the user's explicit check for the broader automated binding audit. Neither that hint nor the notification [I] has been relabelled in isolation.
