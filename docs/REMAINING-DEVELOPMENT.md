# Remaining development: melee, HUD and DLSS

Updated 5 September 2026. VD is now closed at the user's request. Continue
offline work only; a fresh Ready preflight is required before the next deployment
or live session. Worn acceptance remains separate.

The [menu audit and rework](MENU-INTERACTION-AUDIT.md) replaces native-menu
rectangle reconstruction with stock UI input delivery and consistent DPI
handling. Offline build and targeted tests pass; it is not deployed. Operative
clicks, Options pointer alignment and the full transition matrix need live
validation. Reticule recovery was user-confirmed before this rework. Pickup
marker edge asymmetry remains open.

The user has taken ownership of melee contact verification and explicitly moved
development to HUD. HUD is now the sole active area; melee and DLSS are parked.
The melee query prototype remains non-damaging; user verification is not a claim
that physical damage integration is complete.

## Melee

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
Entering desktop layout editing must display a clear message inside VR:
"Use the desktop view to edit your HUD layout." Keep that instruction visible
while editing and restore the normal VR HUD when the editor closes.
An XR freeze occurred with synchronized producer frames continuing; the harness
now logs cached-pair gating reasons to diagnose recurrence. The prototype stays disabled by
default while loading, menus and transitions receive dedicated checks.

## DLSS

The accepted graphics baseline uses DLSS Quality. Stereo frame generation is
unfinished. Existing native code observes Streamline, snapshots per-eye inputs,
packs stereo color, reserves transport and can stage a diagnostic backbuffer
copy. `STEREO_PRESENT_STAGE` explicitly reports `tags_staged=0` and no additional
Present submission. That is not a completed generated-stereo submission path.

The [current NVIDIA DLSS-G guide](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md)
requires independently tagged viewports sharing one backbuffer. It does not
support a separate swapchain per eye. Tagged inputs must remain valid through
Present and constants must correspond to the presented frame. This supports the
existing packed-stereo direction, but does not prove compatibility with the
game's installed integration. The current guide is version 2.12.0; our read-only
ABI mirror targets 2.7.30. Do not construct new API structures from that minimal
mirror without checking the exact installed version and matching headers.

The installed Streamline DLL file versions were checked offline: 2.7.30.0.
The optional `darktidevr-streamline-abi-reference` target now compares the mirror
against the official v2.7.30 headers (structure sizes and relevant member offsets,
plus a constructed viewport value). It compiles with warnings as errors and its
test passes. Supply `DARKTIDEVR_STREAMLINE_REFERENCE_INCLUDE_DIR` at configure
time to enable it; no SDK download or external headers are required by ordinary
builds. Reference headers remain outside Git. This validates layout, not runtime
API success or correct temporal inputs.

The [version-matched guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.7.30/docs/ProgrammingGuideDLSS_G.md)
also supports backbuffer subrect tags without supplying a backbuffer resource
pointer. It specifies input lifetime through Present and clearing tags when
inputs become invalid. The pending submission adapter must include cleanup as
well as successful per-eye tagging; a one-shot tag followed by target reuse is
insufficient.

`src/producer/streamline_eye_tags.h` now prepares one eye's depth, motion and
HUD-less tags plus its packed-backbuffer subrect, without calling Streamline.
The owner cannot be copied/moved because tags reference its resource array.
It rejects invalid dimensions, aliased input roles and stale state after failed
preparation. Tests compare its type identifiers, versions and lifecycle values
to the matching official SDK. Preparing both eyes independently does not prove
cross-eye input isolation; the existing pair policy remains required. Submission,
GPU lifetimes, per-frame constants and tag clearing are still integration work.

The [v2.7.30 DLSS-G state contract](https://github.com/NVIDIA-RTX/Streamline/blob/v2.7.30/include/sl_dlss_g.h)
requires waiting for the plugin's input-processing fence before modifying tagged
inputs on a non-presenting queue (and always with its no-client-queue-blocking
mode). Retrieve that fence/value on the Present thread. Returning from Present
or clearing a tag alone is not the retirement condition for our input snapshots.
The same state query reports presentations since the previous query; avoid
uncoordinated extra polling that consumes the game's counters.

Next: prepare version-matched per-eye tag/constants staging, validate backbuffer
subrects and input lifetimes, then establish generated-output identity and GPU
completion before publishing to the XR consumer. The desktop frame rate alone
does not prove additional stereo frames reached the headset. Preserve the
accepted reconstruction jitter; historical per-eye reset experiments worsened
quality and throughput.

Offline frame-identity checks now reject the unknown frame sentinel and prevent
unsigned counter wrap from appearing as adjacent source timing. Native Release
and the corresponding test target build with warnings as errors; both Streamline
tests pass. These changes do not enable frame generation or replace its remaining
integration and live acceptance work.
