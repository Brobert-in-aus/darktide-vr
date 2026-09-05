# Remaining development: melee, HUD and DLSS

Updated 6 September 2026. User accepts the e8bcfe4 packed-output checkpoint:
VR world rendering, loading screens and desktop mirror all work. Subsequent
opt-in submission diagnostics preserve that rendering path. Actual stereo DLSS
generation and generated-pair XR publication are still incomplete.

The [menu audit and rework](MENU-INTERACTION-AUDIT.md) replaces native-menu
rectangle reconstruction with stock UI input delivery and consistent DPI
handling. User now confirms Options cursor alignment and Operative highlight/
selection, plus premium-store input. After follow-up fixes for confirmation
popups and premium-store vertical compression, the user said "Menus seem good."
This is acceptance of tested routes, not every possible view. The source pass covers
all 72 registered views and direct View-service consumers. Pickup marker edge
asymmetry remains open.

The user has taken ownership of melee contact verification and explicitly moved
development to HUD and then DLSS. Preserve accepted HUD/menu behavior and
continue DLSS, completing one body of work before switching to the next. The
latest instruction permits switching on a documented DLSS blocker: output
association is now blocked at the installed NGX caller-validation boundary.
The four-batch diagnostic passes, but generated XR publication remains disabled.
See the [blocker and resume plan](handoffs/2026-09-06-dlss-unattended.md).
The next active body is the all-family ranged aiming audit below.
The melee query prototype remains non-damaging; user verification is not a claim
that physical damage integration is complete.

## Ranged weapon aiming backlog

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

- Recheck the reported 0.35 s light / 0.45 s heavy timing assumptions against
  weapon action data and actual chaining. Determine whether 0.45 s is only the
  minimum heavy release time and whether holding longer increases damage (or
  changes its profile), including the full-charge threshold.
- Resolve light-attack intervals for every combo step: first swing versus
  repeated swings, per-step variation, earliest chain windows and attack-speed
  modifiers. Do not use the first attack's 0.35 s as a blanket combo cooldown.
- Resolve the wielded weapon's explicit normal/heavy action routes and effective
  timing through its live action context; reject unsupported routes visibly in
  diagnostics rather than substituting guessed damage or timing.
- Integrate the non-damaging overlap adapter and add sweeps, preserving shield/world blocking
  and reporting saturated queries. Calibrate the grip-to-volume transform with
  a visible overlay when worn testing resumes.
- Introduce a dedicated stock damage context with explicit proc lifetimes and
  prediction ownership. Validate continuous contact and multiple targets before
  adding weapon specials. Do not invoke the stateful stock action hit routine
  indiscriminately on every overlap.

See [motion smoothing](MOTION-SMOOTHING.md): minimal physical-weapon lag, optional
light aim stabilization, one shared sample policy for presentation and attacks.

## HUD

Menu follow-up (6 September): immediately after character selection loads,
highlighting works but clicks appear unconsumed for about one second. Investigate
view enter/input-readiness gating and pointer click delivery against that precise
transition. Do not queue the missed click for later replay. User observation is
unverified in code; retain this as backlog while completing DLSS.

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
The layout editor should be exposed through VR mod options. Before release,
check the original Custom HUD license/permission terms: determine whether we
can reuse/bundle it, what attribution is required, or make Custom HUD an optional
dependency for editing. Do not assume attribution alone grants permission.
Also add proper VR mod-menu options, configurable action/key bindings, and
three separate HUD sliders: panel size (uniform width/height scale), distance
from the player (metres), and internal UI scale (size of objects inside the
panel). Preserve saved layouts and make the distinction clear in option labels.
Changing distance alone changes angular size; users can adjust panel size to
compensate, as in the current doubled-distance/doubled-size setup. Also add
controller button glyphs/prompts instead of the current mouse/keyboard prompts.
Review the complete VR input layout before finalizing those bindings. User
reports that the right thumbstick and its click (R3) are unused; audit actual
action usage and use the available controls to make the full layout more
sensible. Review gameplay, weapon specials, movement, interactions and menu
contexts together, including hold/toggle behavior and conflicting actions.
Implement remapping and matching controller prompts with the revised defaults.
This is backlog work; no bindings changed in response to this feedback.
Entering desktop layout editing must display a clear message inside VR:
"Use the desktop view to edit your HUD layout." Keep that instruction visible
while editing and restore the normal VR HUD when the editor closes.
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

Remaining work, in order:

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

The current machine retains LOD 9 and restored pool/workers 1024/13. Worker
tuning is opt-in with -TuneWorkerThreads. Release auto-configuration must use
physical cores, not logical processor count. Keep this separate from DLSS work.
