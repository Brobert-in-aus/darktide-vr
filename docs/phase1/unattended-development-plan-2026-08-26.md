# Unattended development plan — 2026-08-26

## Objective and operating boundary

Use an unattended Quest 3/Virtual Desktop session to advance three production
features as far as automated evidence permits:

1. cylindrical, world-up particle billboarding;
2. readable and interactive fullscreen menus on a spatial panel; and
3. first-person VR input, initially with head-independent controller aiming and
   then tracked weapon presentation where the game architecture permits it.

The run remains EAC-inactive and limited to character select, the Mourningstar
without player interaction, and the single-player Psykhanium. It must not enter
matchmaking or a public mission. Visual/comfort judgements that require a worn
headset are explicitly deferred rather than inferred from the desktop mirror.

## Unattended control and recovery

Before feature work:

- verify exactly one authorized Quest with
  `tools\quest\set-proximity-override.ps1 -Action Status`;
- reapply `-Action Disable`, because the Quest broadcast has no durable query;
- verify Virtual Desktop/VDXR is available and the XR harness can enter
  `XR_VISIBLE`/`XR_FOCUSED` with the headset unworn;
- record the current game, mod, native-DLL, and source hashes;
- establish a clean character-select control capture and a 30-second XR soak;
- keep the headset powered and ventilated, and periodically check ADB and XR
  session health.

Every deploy follows the existing launch contract: close Darktide cleanly, wait
at least ten seconds for Steam to register exit, launch through the Fatshark
launcher, press its Play control, then advance the loaded splash screen. A
watchdog should distinguish launcher, game, crash reporter, and requested-exit
states; archive logs and close crash dialogs without submitting them.

Do not attribute an isolated XR initialization failure to Virtual Desktop by
default. First archive the failure, perform one ordinary clean retry, and check
whether the failure follows the current change. Roll back to the last known-good
game/mod/harness state when appropriate. Use the Virtual Desktop restart below
only when XR fails repeatedly, or when the same failure remains after that
known-good rollback:

1. stop the XR harness and close Virtual Desktop on both the PC and Quest;
2. reopen Virtual Desktop Streamer on the PC;
3. wait a full 30 seconds;
4. reopen Virtual Desktop on the Quest; and
5. run a small VDXR/OpenXR harness smoke test before launching Darktide again.

On this PC the interactive process is `VirtualDesktop.Streamer.exe` at
`C:\Program Files\Virtual Desktop Streamer\VirtualDesktop.Streamer.exe`; the
background service is not assumed to need termination. When Quest ADB is
online, discover and verify the installed Virtual Desktop package/activity,
then use bounded `am force-stop` and launch commands for the Quest side. Cache
neither its wireless address nor device serial in Git. If ADB remains offline,
do not continue an unbounded relaunch loop. After the ordinary retry and
known-good comparison have justified the VD recovery path, attempt the
documented ADB recovery and record that XR recovery is blocked if the Quest
application cannot be restarted unattended.

Each experiment is independently selectable and defaults off unless it has
passed its control run. A crash or device removal causes immediate rollback to
the last accepted binaries/configuration before changing workstreams. No more
than two identical crash reproductions are needed when the logs and dump agree.
Large captures remain timestamped artifacts rather than Git content.

## Workstream A — shared billboard-basis producer

### Rationale

Per-shader substitution is a proven diagnostic and safe fallback, but it does
not scale to an unknown number of subtle material permutations. The spherical
permutations already inspected share a 128-byte `c_billboard` constant holding
`view` and `view_proj`. The production target is the CPU producer of that
constant: preserve `view_proj` and camera translation/forward data, but replace
the billboard right/up basis with a yaw-projected right vector and Darktide's
world-Z up vector before command recording.

This is different from the rejected descriptor experiment. It does not alter a
bound descriptor heap or rewrite a GPU-visible allocation after state assembly.

### Implementation sequence

1. Disable the retired broad stride/descriptor-write prototype and retain only
   bounded identification counters.
2. Starting from a known `c_billboard` PSO draw, resolve the reflected CBV
   register and root binding to the exact `BufferLocation`, size, resource, and
   byte offset.
3. Extend mapped-upload tracking so every `ID3D12Resource::Map` result records
   its CPU base together with the resource's GPU virtual-address range. Confirm
   that the identified 128 bytes numerically follow the camera basis while
   `view_proj` remains eye-specific.
4. Export one selected CPU address and use a bounded hardware data breakpoint
   to capture the writing instruction and call stack. Prefer a scripted debugger
   attachment that logs and continues; use a temporary guarded-page/VEH probe
   only if the allocation rotates before a breakpoint can be armed.
5. Identify the highest stable engine call site that owns the billboard
   constant, record its module-relative address and surrounding instruction
   fingerprint, and hook it fail-closed for the exact inspected build.
6. At that producer, calculate horizontal right from the camera forward vector,
   normalize it with a degeneracy fallback, set up to `(0, 0, 1)`, and leave the
   projection and remaining matrix values untouched.
7. Retain PSO hashes only for observation: verify that all known spherical
   permutations consume changed data without individual shader replacements.
   Leave the tangent-driven axial permutation unchanged unless its output shows
   that it also needs a distinct correction.

### Unattended validation

- Unit-test the Z-up basis calculation at cardinal headings, near-vertical
  camera angles, and invalid/degenerate input.
- Assert that a patched 128-byte sample differs only at the approved basis
  offsets.
- Run a scripted camera-pitch/roll sweep with the headset stationary. Capture
  the desktop eye mirror before/after so smoke orientation can be reviewed
  later without subjecting the user to the diagnostic motion.
- Record per-hash draw counts, producer-hook hits, basis values, PSO failures,
  D3D12 errors, and device-removal reason.
- Soak character select for 30 seconds, transition through loading, and later
  repeat in the Psykhanium for muzzle smoke, explosions, fire and ambient fog.

Acceptance requires stable geometry, no new eye difference, no device loss,
and the same world-up result across every exercised spherical permutation. The
user still performs the final worn-headset smoke/particle judgement.

### Progress — 2026-08-26

Steps 1–5 are complete for executable revision 135417. The exact upload path,
persistent staging address and SIMD writer are evidence-backed and
fingerprinted. A separate staging API now performs the six-float basis patch;
the retired descriptor writer remains impossible to arm. The first 35-second
character-select soak passed with a one-to-one match between exact billboard
CBVs and patches. Scripted pitch/roll captures, broader material coverage and
the final worn-headset judgement remain outstanding.

## Workstream B — fullscreen menu presentation

### Presentation model

Fullscreen views are not part of the completed per-eye world resource; they are
composited into the desktop output later. For the first production path, opening
a fullscreen view therefore switches XR from stereo projection to the existing
flat capture panel. The menu and its background are shown once to both eyes,
while the game continues its normal UI update/input lifecycle.

Replace the overloaded binary `projection_active` signal with a small versioned
presentation state:

- `stereo_world`;
- `flat_loading_or_cinematic`;
- `world_anchored_menu`;
- `flat_menu`; and
- `disabled/error`.

Include a transition sequence, source dimensions/crop, and requested maximum
panel size. On every transition into a flat mode, anchor the panel from the
current head pose, horizon-lock it, place it approximately 2 m forward, and
then keep it fixed in LOCAL space. Fit the captured aspect ratio inside a
2 m by 2 m bounding box without stretching.

### View classification

Hook UI view open/close centrally and maintain a reference-counted stack.
Initially classify explicit fullscreen views—system/options, inventory,
mission/training-ground selection, crafting/vendors and popups—while logging
unknown views and their `views.lua` flags such as `disable_game_world`. Do not
switch modes for spatial HUD markers, chat, subtitles, interaction prompts or
communication wheels. A fail-safe timeout returns to stereo only after the
fullscreen stack is genuinely empty.

### Unattended validation

- Unit-test nested menu/open/close ordering, abrupt state destruction, loading
  transitions and error recovery.
- Open several known views by game callback, capture the desktop source and XR
  panel, and verify aspect/crop, panel anchoring and stereo restoration.
- Rotate the synthetic head pose after panel creation and assert that the panel
  remains fixed in LOCAL space.
- Exercise character select, hub system menu, training-ground menu, options and
  confirmation popup without requiring pointer input first.

### Progress — 2026-08-26

The versioned presentation transport, loading/system-menu classification,
horizon-locked LOCAL-space panel and automatic stereo restoration are complete.
Unit tests cover transport consistency, panel horizon lock and aspect fitting.
A live system-menu open/close run proved flat fallback and restoration to fresh
stereo pairs without reused frames or pair-driven timeouts. Pointer interaction,
nested/unknown menu coverage, vendor anchoring and final worn-headset panel
ergonomics remain outstanding.

### Hub vendor and NPC-anchored shop mode

Shop interactions receive more specific handling than generic fullscreen menus.
Darktide's `ViewInteraction:_start(interactor_unit, interactee_unit)` receives
the exact interacted unit immediately before it calls `Managers.ui:open_view`,
and `InteractorExtension:target_unit()` exposes the same target while the
interaction is active. Hook that seam and snapshot the interactee unit pose,
interaction/view name, and a stable world-up basis before the view transition
can discard the interaction state.

Vendor views are not uniform. `store_view`, crafting, contracts, barber,
credits, marks and cosmetics use different view classes; their declarations
commonly set `disable_game_world = true`, and several background views spawn a
separate `UIWorldSpawner` level containing a presentation copy of the vendor.
Accordingly, do not assume the stock shop screen is already spatial UI attached
to the hub NPC. Probe each vendor family for these layers:

1. the live hub world and interacted NPC;
2. the interactive 2D widget/UI pass; and
3. an optional vendor background world, camera and character copy.

The preferred production path keeps the stereo hub world visible, suppresses
only the vendor background world, renders the interactive widget layer once to
the menu texture, and places that texture in `world_anchored_menu` mode at an
authored transform relative to the interacted NPC. Start with a generic anchor
centred roughly in front of and above the NPC, facing the player's interaction
position and locked to world-up; record per-vendor offsets only where the hub
layout needs them. Freeze the anchor at open time unless the NPC genuinely
moves. This preserves the usual physical context without letting head motion
drag the shop along with the viewer.

If the UI pass cannot be separated from a vendor's background world, first try
capturing the complete stock view to the NPC-anchored panel. If the target unit
is invalid/despawned, its transform is implausible, the source is unavailable,
or the panel would be occluded/unreadable, fall back immediately to the existing
horizon-locked 2 m by 2 m `flat_menu` board approximately 2 m from the player.
Never leave a shop open with no visible or actionable UI. The same OpenXR ray to
panel-UV pointer works for both modes; only the panel transform and crop differ.

Instrument open/close with view name, interactee unit ID, captured and panel
poses, source layer, fallback reason, and pointer UV. Unattended tests should
open every reachable vendor family through the normal interaction callback,
move a synthetic head pose to confirm the board stays at the NPC, activate a
non-purchasing tab/back control, and verify stereo restoration. Purchases and
destructive character changes remain manual. Final user validation covers
legibility, occlusion, preferred NPC-relative placement and reach comfort.

## Workstream C — OpenXR controller and pointer foundation

Menus and first-person controls should share one controller transport rather
than create two incompatible input paths.

### Runtime input

Add a gameplay action set with standard OpenXR paths for both hands:

- aim and grip poses;
- trigger, squeeze and thumbstick values;
- primary/secondary, stick-click and menu buttons; and
- haptic output.

Provide bindings for Oculus Touch and the Khronos simple-controller profile,
then poll with `xrSyncActions` and locate pose spaces at the frame's predicted
display time. Publish a versioned shared-controller sample containing pose,
validity/tracking flags, analog values, button state, sequence and timestamp.
Never reuse a stale pose as live input; invalid tracking falls back to ordinary
keyboard/gamepad control.

The transport receives math/unit tests for handedness, recenter transforms,
edge generation and stale-state rejection. A synthetic provider, compiled only
for development, supplies deterministic controller rays while the physical
controllers are asleep or stationary.

The unattended synthetic loop exercises both hands independently and together:
left sweep, right sweep, crossed sweep, departure through opposite viewport
edges, a geometrically valid panel ray whose origin exceeds the 1.5 m reach
envelope, tracking loss, and reacquisition. It publishes no trigger or button
presses. The path requires the explicit `--synthetic-controller-path` harness
flag and cannot silently replace inactive production controllers.

### Runtime IPD and character scale

Base stereo separation is not a fixed headset-model or population-average IPD.
Each frame uses the distance between the two view poses returned by OpenXR
`xrLocateViews`. A 64 mm value exists only as a safe pre-XR initialization
fallback and is replaced as soon as a valid runtime sample arrives.

Ogryn scale both the runtime separation and physical head translation by
`1.61 / 1.21` (~1.3306), matching Darktide's reviewed Ogryn and baseline-human
player-height data. The game-native clean camera still supplies the taller
character viewpoint. This produces the smaller perceived world scale expected
for a larger body without discarding the user's calibrated IPD.

### Controller capacity and Darktide action mapping

Darktide's default gamepad layout consumes two analog sticks and 16 distinct
digital controls: two triggers, two shoulders, two stick clicks, four face
buttons, four D-pad directions, Back and Start. Several aliases are already
context-shared by the game—interact/reload, dodge/jump, tag/communication wheel,
and quick-wield/inspect—but they still occupy those 16 physical positions.

Quest Touch through the Oculus OpenXR interaction profile supplies the same two
sticks but only 11 generally bindable digital controls: two triggers, two
squeezes, two stick clicks, A/B/X/Y and the left menu button. The right Meta
button is runtime/system-owned and must never be intercepted. Therefore a
literal gamepad clone is **five buttons short**. Capacitive touch states and
hand-pose gestures are useful embellishments but are not dependable primary
actions and do not count toward the capacity budget.

Use a versioned, user-configurable VR binding layer that emits Darktide aliases,
not keyboard scan codes. The initial candidate mapping is:

| Quest input | Gameplay alias |
| --- | --- |
| Right trigger | primary attack/action one |
| Left trigger | ADS, block or action two |
| Right squeeze | weapon special |
| Left squeeze | blitz/grenade ability |
| A | jump/dodge |
| B | crouch/slide |
| X | interact or reload, using Darktide's existing context |
| Y tap | quick swap |
| Left-stick click | sprint |
| Right-stick click/hold | tag/communication wheel |
| Left menu tap | system menu |

Recover the missing gamepad capacity deliberately rather than with arbitrary
double-taps: holding Y opens an equipment/action radial for explicit melee,
ranged, blitz, deployable/auspex and inspect selection; holding the left menu
button opens the tactical overlay; and combat ability receives a configurable
two-button chord until user testing identifies the least disruptive dedicated
swap. Chords suppress their component actions for a short bounded recognition
window and must never delay attack, block, dodge or other latency-critical
inputs. Alternative profiles may trade a dedicated combat-ability button for
crouch, tag or weapon special. Physical crouch and auto-sprint can optionally
free inputs, but neither is required.

The right stick remains available for the already-planned snap/smooth body-turn
path whenever no radial is active. In menu presentation modes the binding
context changes atomically: controller ray plus trigger selects, B goes Back,
the sticks navigate/scroll, and menu closes the view. No gameplay alias may leak
on the frame that UI context opens or closes. Maintain pressed/held/released
edges once per fixed game tick, support left-handed stick/hand swaps, persist
profiles independently of Darktide's ordinary gamepad setting, and display the
resolved VR control in prompts rather than misleading Xbox glyphs.

Automated coverage exhaustively walks every gameplay and view alias, detects
unreachable or multiply-fired actions, tests chord/radial timing and context
transitions, and records action latency. Psykhanium validation covers every
weapon slot, ability, reload, interact, tag/wheel, movement action and menu
round-trip. The acceptance target is zero unreachable gameplay functions,
despite the five-button raw deficit.

#### Implemented direct-input foundation (2026-08-26)

`GameplayInputMapper` now converts the 11 directly usable Quest controls into
semantic Darktide actions and produces deterministic pressed, held and released
sets. Trigger and squeeze thresholds use 0.55 press / 0.45 release hysteresis.
Leaving gameplay releases every held action once, preventing attacks or
movement modifiers from leaking into menu/loading contexts. Native tests prove
that all 11 direct actions are reachable and that context loss is fail-closed.

The game-side adapter remains normal-off behind
`darktidevr_gameplay_input_test.flag` and is additionally restricted to the
Shooting Range/training game modes. It feeds Darktide's existing network input
families rather than keyboard scan codes. X intentionally emits both
interact/reload and A emits both jump/dodge, matching the game's own shared
gamepad aliases and leaving contextual resolution to existing gameplay code.
The smart-tag and menu bits are transported but are not yet injected through
`HumanInputHandler`, because those actions are consumed outside its networked
action list. Combat ability, tactical overlay and the explicit equipment radial
remain the three unresolved binding-layer functions; none is silently assigned
to a latency-sensitive chord.

The synthetic controller provider still emits poses only by default. Its
separate `--synthetic-gameplay-input` switch (which requires
`--synthetic-controller-path`) cycles all 11 direct controls across the existing
six deterministic path phases. This is intentionally noisy and is only for an
offline/private end-to-end run; ordinary synthetic pose tests cannot fire an
action accidentally.

### Spatial menu pointer

In `flat_menu` mode, intersect the dominant-hand aim ray with the exact LOCAL-
space panel plane. Convert the hit to normalized UV, then through the captured
source crop to client coordinates. For the first implementation, inject normal
Windows absolute mouse movement/button/wheel events into the foreground
Darktide client; this exercises the game's existing hotspots and preserves all
view-specific behavior. The XR harness draws its own cursor/laser if the capture
API does not include the OS cursor.

Map trigger to left click, secondary/menu to Back/Escape, and thumbstick Y to
scroll. Entering pointer mode must synthesize no click; leaving it must release
all held buttons, clear hover ownership and suppress the same controller edge
from becoming a gameplay attack. Keyboard/gamepad navigation remains available.

Automated tests use synthetic rays at panel corners/centre and verify exact
client coordinates. End-to-end tests activate known buttons and assert the
resulting Darktide view transition. Worn-headset feedback is needed only for
panel distance, laser feel, cursor size and dominant-hand ergonomics.

## Workstream D — deterministic Psykhanium entry

Darktide's training views provide the supported sequence. The older
`meat_grind_stress` Testify case is useful history but its option index is no
longer authoritative:

1. wait until the game is authenticated and in the hub;
2. open `training_grounds_view`;
3. resolve the option whose semantic key is
   `loc_training_grounds_view_shooting_range_text` and trigger its live widget;
4. wait for `training_grounds_options_view`;
5. trigger widget `play_button`; and
6. wait for game mode/presence `shooting_range`.

The current live option is index 4 because Horde was inserted at index 1; the
old hardcoded `option_button_3` now selects Advanced Training. The selected
option constructs the normal context for mission `tg_shooting_range`, and
`TrainingGroundsOptionsView:_start_training_grounds` resets multiplayer state,
boots a single-player session, changes mechanism and signals all players ready.
The development mod will reproduce the public view/widget callbacks rather than
invoke Testify-only APIs or fabricate the mechanism context.

The extracted Lua is an implementation map, not an assumed ABI: the live build
must expose the expected classes, view names and widgets before automation is
armed. A missing or renamed item stops the state machine and records the active
view inventory instead of guessing a replacement click.

Implement this as an opt-in state machine with authentication, view-active,
mission and timeout assertions. It must not move the mouse, walk through the
hub, alter progression gates, enter matchmaking, or retry blindly after a
server/login error. Add the reverse test path through the normal system-view
exit confirmation so repeated clean runs can return to the hub.

## Workstream E — first-person VR controls

### E1: conventional tracked-controller input

First establish parity with an ordinary gamepad:

- left stick supplies locomotion;
- right stick is reserved for future snap/smooth body yaw;
- trigger/grip/buttons map to Darktide's existing action aliases before the
  fixed-frame input cache, preserving pressed/held/released semantics exactly
  once per game tick; and
- UI mode owns these controls exclusively while a fullscreen menu is active.

Source inspection narrowed the aim integration point. Local-player
`PlayerUnitFirstPersonExtension.fixed_update` constructs
`first_person_component.rotation` from the input extension's yaw/pitch/roll plus
recoil. `PlayerUnitAimExtension`, the weapon system, interactions, abilities and
many action paths consume that shared rotation. Driving ordinary mouse look
from the controller would therefore aim correctly but would also rotate the VR
view and movement basis. Do not patch those consumers individually.

The intended split is one upstream gameplay-aim rotation plus an independent
VR render rotation: controller orientation supplies the shared gameplay/action
rotation, while the stereo camera hook composes its render basis from the
character/body yaw and HMD pose rather than rereading controller-driven pitch
and yaw. Thumbstick turning later changes the body/render-yaw accumulator
explicitly. This preserves one authoritative action direction without coupling
the user's head to the weapon.

Controller poses arrive in absolute OpenXR LOCAL space. Spatial-menu rays need
that absolute form, while gameplay aim needs a second body-local form:
`inverse(initial_hmd_recenter) * controller_pose`, followed by the exact basis
change from OpenXR (+X right, +Y up, -Z forward) to Darktide (+X right, +Y
forward, +Z up). The core conversion and recentered-controller primitive are
unit tested. Controller-state transport v2 now carries both forms. Absolute
poses remain available to the XR-side spatial-menu adapter; the native Lua
export exposes only the recentered Darktide-basis poses intended for gameplay.
Body-local tracking flags remain zero until the immutable HMD recenter anchor
exists, so startup cannot fabricate a usable weapon pose.

The synthetic provider publishes independently of menu-panel visibility so it
can exercise immersive gameplay consumers. Pointer raycasting and injection
remain separately gated on an actually submitted flat panel and the explicit
menu-input flag.

The safest initial aim seam is Darktide's `DefaultPlayerOrientation`. Convert
the dominant-hand OpenXR aim rotation into the game's Z-up world basis and feed
that as ordinary yaw/pitch aim. Existing weapon actions already consume
`first_person_component.rotation` for hitscan, projectiles, targeting, grenades,
melee sweeps and recoil. The rendered VR camera remains driven only by the HMD,
so controller aim/recoil can move the game weapon without rotating the user's
view. Initially, locomotion remains game-relative to this aim direction; a
separate head/body-relative movement transform follows once the core action path
is proven.

The observation-only implementation hooks both `DefaultPlayerOrientation` and
the hub-specific `HubPlayerOrientation`, uses the engine's own quaternion-to-
yaw/pitch conversion, and rate-limits telemetry to two seconds. It does not
write orientation. Live synthetic hub validation proved advancing controller
sequences reach this seam. The observer now captures the game body yaw once per
XR controller sequence epoch and composes it with the body-local controller
rotation. The accepted run retained the hub's 3.1415-radian world yaw while
adding the synthetic controller's -0.3094 pitch and 0.0758 roll; sample ages
were 0.213--16.567 ms and all telemetry remained `write=disabled`.

Do not persist Stingray quaternion/vector userdata across frames. Store plain
scalars and reconstruct temporary engine math values at the consuming hook.
The next authoring gate is an explicit test-only switch: write composed yaw and
pitch only, force gameplay roll to zero, require the dominant aim pose to be
position-valid and orientation-tracked with age between -5 and 100 ms, and
fail closed whenever tracking, freshness or the XR sequence epoch changes.
Controller aim must remain independent of the HMD render basis.

That test-only gate is now implemented and live-validated in the hub. A bounded
synthetic run published 456 controller samples and performed 302 writes. The
game yaw remained at the 3.1415-radian body anchor, pitch converged from 6.2832
to 5.9745 (equivalent to the -0.3087 target), and roll remained zero. It emitted
no menu input and produced no Lua/safe-hook error. The flag defaults to and was
restored to `disabled`; production runs therefore remain observation-only.
Before any button mapping, add a one-shot suspension record for invalid/stale
tracking and repeat this gate in the private Psykhanium while observing the
first-person component and authoritative shot direction.

The suspension record is now validated. Synthetic tracking loss produced one
`flags=0` suspension at sequence 301, reacquisition resumed authoring, and the
post-session snapshot produced one stale suspension at 105.142 ms. A sequence
epoch transition blocks its first snapshot as well. This removes the remaining
hub-side safety gate; the next run is the same writer plus downstream rotation
observation in the private Psykhanium.

The private-range gate now passes when armed at character select before the
public hub populates. Entering from an already populated hub twice hit the same
base-game remote-husk `parent_unit_id` teardown race, including after a
30-second soak; keep the early unattended sequence and do not ship an
unexercised error-swallowing patch. In the range, 600 XR samples produced 539
combat writes. The downstream first-person component matched
`-1.5708,-0.3079,0.0000` at four sampled sequences and exposed forward ray
`0.9530,0.0000,-0.3031`. The next gate can therefore be one explicitly armed,
synthetic primary-fire edge while recording the normal game action/impact path.

That first input boundary is now live-proven. The active `Ingame` service
contains `action_one_pressed`, `action_one_hold` and `action_one_release`; the
matching extracted `HumanInputHandler` source classifies pressed/released as
ephemeral inputs and copies their OR-accumulated value exactly once into a fixed
frame. The normal-off test gate therefore injects only one
`action_one_pressed` edge after the regular `pre_update` sampling, and only in
`training_grounds`/`shooting_range` while controller aim is armed and fresh.
At sequence 9298 the fixed cache accepted the first pressed-only probe on frame
1474 with forward ray `0.9532,0.0006,-0.3022`. The equipped sword's template
starts from `action_one_hold`, so the completed event now supplies pressed plus
held for one fixed frame and release on the next. At sequence 5796, frame 1913
reported `pressed=true, held=true` and immediately entered
`action_melee_start_left`; frame 1914 reported `release=true, held=false`.

The mission selector is now exact rather than mode-based: it semantically
resolved Shooting Range to current widget index 4, verified the options context,
and passed only after the world reported
`game_mode=shooting_range mission=tg_shooting_range`. With slot 2 selected, the
same bounded click entered `rapid_left` on `forcestaff_p4_m1` at sequence 12281.
Source inspection closes the pre-spread direction chain: that projectile action
reads `first_person_component.rotation` as `look_rotation`, then applies its
normal offset/spread/targeting before handing direction to projectile
locomotion. The delayed locomotion observer completed the post-spread chain on
the next clean run: sequence 14138 entered `rapid_left` on fixed frame 2532 and
the manual-physics handoff received direction
`0.9549,-0.0008,-0.2971`, compared with authored forward
`0.9539,0.0008,-0.3000`. The residual is normal weapon spread. Both projectile
and generic `ActionShoot` paths now have observation seams before this becomes
a general binding adapter.

This first gate deliberately keeps game-authoritative firing origins and reach.
It must not permit shooting around walls, longer melee reach, altered cadence,
or stronger aim assistance.

### E2: tracked weapon presentation

Once action direction is correct, identify the wielded first-person weapon unit,
attachment and muzzle nodes. Apply a post-animation visual transform so its
orientation follows the dominant-hand aim pose while preserving reload, recoil,
charge and weapon-special animation. Add hand-position translation only after
near-plane clipping, body intersection and muzzle alignment are measured.

For two-handed weapons, blend orientation toward the line between dominant and
support hands only while the support grip is held and within a configurable
capture region. This is stabilization of the physical pose, not additional
game aim assistance. Keep the authoritative hit ray/origin on the validated game
path until visual and gameplay alignment agree.

Live hierarchy evidence now fixes the first implementation seam. The force
staff root is coincident with the 1P skeleton's `j_rightweaponattach`, and all
seven visible 1P attachment units plus the resolved FX node inherit that chain.
The hands remain on the 187-node first-person skeleton. Drive the whole
presentation chain from a post-animation delta rather than rewriting individual
weapon meshes; retain the off-hand animation until a separate support-hand IK
constraint is available.

The normal-off pose trace also validates the controller-space conversion. Its
synthetic path crosses the viewport, leaves the panel, exceeds reach and loses
tracking; the trace reproduced those phases while the stock hand remained
unchanged, and measured attachment-root/weapon-root error at `0.000000` m.
The first authoring gate must reject stale/invalid samples and a configurable
maximum wrist displacement before changing the presentation rig.

That first gate is now implemented and live-validated. The selected seam is a
safe hook after `PlayerUnitFirstPersonExtension.update_unit_position`, because
that game method restores the stock 1P root, updates animation state and calls
`World.update_unit_and_children`. The mod maps the animated right hand to the
tracked grip through the hand's six-parent scene-graph root and performs one
explicit child propagation. Across 458 accepted synthetic writes, measured
post-hand position error and attachment-to-weapon-root error were both
`0.000000` m, with exact target orientation. Samples above 0.75 m and invalid
tracking remained fail-closed. The feature remains normal-off pending physical
controller grip-offset and weapon-family calibration.

True physical melee is a later feature. The initial implementation remains
button-driven, uses Darktide's normal sweep animations/damage windows and merely
aims the animation with the tracked controller. One-to-one swing collision would
require a separate reach, network, animation and balance design.

### E3: articulated body and full IK

Treat floating hands/weapons as a bring-up stage, not the final embodiment
model. Darktide maintains separate first-person and third-person units: the 1P
unit is positioned/rotated from `first_person_component` and drives dedicated
weapon animation, while the player unit has the complete character skeleton and
continues its third-person animation. The source also exposes familiar skeleton
nodes (`j_hips`, spine, neck/head, upper/lower arms) and an existing handle-based
foot-IK component. This makes a post-animation local-player IK layer plausible,
but does not prove that every player unit ships writable arm/foot handles. The
first investigation therefore enumerates live node names, scene-graph parents,
animation variables/constraints and mesh visibility on all four archetypes.

For the VR body path, keep the game locomotion root, collision, action state and
damage logic authoritative. Make the local third-person torso/body visible to
the VR cameras while hiding the head/inside-face geometry and avoiding duplicate
1P/3P weapons. Apply overrides after normal animation but before the stereo
world is captured, and drive both visual rigs from one solved pose where an
effect or weapon still depends on the first-person unit.

The solver hierarchy is:

- HMD drives head/neck pose relative to a calibrated eye-to-neck offset;
- pelvis remains based on the game character root, with height and horizontal
  offset inferred from the HMD and constrained to the capsule;
- chest/spine distribute the pelvis-to-head rotation with anatomical limits;
- shoulders derive from chest pose and per-character proportions;
- each arm uses continuous analytic two-bone shoulder/elbow/wrist IK, a stable
  chest-relative elbow pole vector, reach limits and anti-flip handling near
  full extension;
- controller grip poses drive wrists/hands through item-specific offsets;
- for two-handed items the dominant hand drives the weapon and its gameplay aim,
  while a weapon grip socket constrains the support hand and support arm; and
- legs initially retain Darktide locomotion animation and existing foot IK,
  with pelvis compensation blended conservatively rather than attempting to
  infer exact feet from two controllers.

With a headset and two controllers, head and hands are measured but pelvis,
elbows and legs are inferred. That is a useful full-body procedural avatar, not
true tracked full body. At startup enumerate the runtime's OpenXR extensions and
probe Meta/Facebook body-tracking support (including full-body variants) without
assuming Virtual Desktop/VDXR exposes it. If supported, add it as an optional
joint source behind the same solver; otherwise retain inferred lower body. Extra
trackers can be a later provider rather than a rewrite.

Blend IK weights by action/state instead of overriding the animation graph
blindly. Define explicit policies for idle/locomotion, ADS, melee/block, reload,
weapon special, grenade/ability, climb/ledge, stagger/downed, emote and
cinematic states. Invalid or stale tracking, an unknown skeleton, extreme reach
or an unsupported state fades back to stock animation. Networked pose replication
and gameplay-reach changes are out of scope for the offline/private initial path.

Unattended validation uses recorded synthetic HMD/controller trajectories and
an external debug camera/mirror to measure wrist error, joint-limit violations,
elbow discontinuities, shoulder stretch, head/body clipping, foot sliding and
1P/3P weapon duplication. Run the sequence on multiple body sizes/archetypes in
the hub and Psykhanium, then exercise locomotion, crouch, ADS, reload, block,
melee and weapon swap. Worn-headset approval is still required for embodiment,
arm proportions, chest/pelvis inference, near-body comfort and two-hand grip.

### Psykhanium test ladder

1. With synthetic controller data, verify coordinate conversion, action edges,
   aim quaternion continuity and invalid-pose fallback from logs alone.
2. Enter `tg_shooting_range` through the automated view sequence and confirm
   player/weapon extension discovery without modifying them.
3. Enable aim-only control; exercise fixed scripted aim directions and compare
   the engine orientation, first-person component, reticle and shot direction.
4. Enable button mapping and perform bounded single shots, ADS, reload, weapon
   swap, block and one melee attack against Psykhanium targets.
5. Enable visual weapon orientation and capture both eyes plus the mirror while
   sweeping a synthetic hand pose.
6. Run 30-second idle and action soaks, exit normally to the hub, and inspect
   Lua/D3D12/device logs.

The user validates live controller alignment, handedness, comfort, two-hand
capture distance and perceived recoil when available.

## Independent backlog to use when a primary stream blocks

These features can advance without invalidating the three main workstreams:

1. **Presentation lifecycle and recovery:** central state machine, re-anchoring,
   stale-resource fallback, clean XR/Game restart, and device-loss diagnostics.
2. **Comfort camera policy:** suppress game camera pitch/roll, bob, shake,
   forced turns and recoil while retaining translation; expose recenter plus
   dormant snap/smooth yaw paths.
3. **Audio listener orientation:** make spatial audio follow HMD orientation
   rather than controller aim/body heading.
4. **HUD completion:** finish binocular-overlap clamping, classify remaining
   screen-GUI layers, and place full HUD groups on stable panels where per-eye
   world projection is inappropriate.
5. **Runtime input configuration:** handedness, stick swap, seated/standing
   height, controller/HMD-relative locomotion, dead zones and bindings.
6. **Performance and pacing:** retain pair-driven submission, expand per-eye GPU
   timings, identify duplicated CPU/GPU work, and preserve runtime-directed
   resolution plus optional SSW/frame-generation behavior.
7. **Near-plane/body/weapon visibility:** prevent head-inside-body geometry,
   weapon clipping and asymmetric first-person shadows without changing combat.
8. **Haptics:** map existing attack/recoil/damage events to bounded OpenXR
   vibration after input parity is stable.
9. **Cutscene/downed/spectator policy:** extend the flat-panel fallback and avoid
   forced-camera discomfort before mission testing.
10. **Compatibility manifest and diagnostics:** fingerprint game/Lua/native
    builds, fail closed on unknown signatures, and generate a concise session
    report suitable for unattended review.
11. **Calibration, recenter and embodiment settings:** standing/seated modes,
    floor and eye height, arm-span/body-scale calibration, dominant hand,
    controller offsets, snap/smooth turn, vignette and per-user persistence.
12. **Weapon and ability compatibility matrix:** audit every weapon family,
    ironsight/scope, flashlight, charge/reload/special, grenade, psyker ability,
    deployable and auspex for pose, effects, reticle and gameplay-origin parity.
13. **Traversal and interaction-state matrix:** pickups, revives, carries,
    ladders, vaults, ledges, knockback, crouch/slide, elevators and moving
    platforms need explicit camera, body-IK and input-ownership policies.
14. **Text entry and communications:** spatial keyboard or desktop-keyboard
    handoff for chat/search/rename fields, correct focus, and safe dismissal.
15. **XR focus and dashboard lifecycle:** pause/recover safely across headset
    removal, OpenXR visibility/focus loss, Virtual Desktop overlays, controller
    sleep/reconnect and recenter events without stuck inputs.
16. **Packaging and user configuration:** reproducible installer/uninstaller,
    safe defaults, binding/presentation profiles, log bundle, version checks,
    rollback and separation from credentials or machine-specific state.

## Execution order and checkpoints

The unattended queue is:

1. preflight/watchdog and clean control capture;
2. billboard CBV-to-CPU mapping and writer trace;
3. flat-menu presentation without pointer;
4. OpenXR controller transport, binding profiles and synthetic provider;
5. synthetic off-viewport, over-reach, loss/reacquisition pointer loop;
6. spatial pointer and menu end-to-end callbacks;
7. automated Psykhanium entry/exit;
8. conventional controller aim and buttons;
9. tracked weapon orientation;
10. vendor/NPC-anchored shop presentation with generic-board fallback;
11. live skeleton/constraint inventory and articulated upper-body IK;
12. local full-body visibility, inferred pelvis/lower-body integration and
    optional runtime body-tracking provider; and
13. independent backlog items when a gate is blocked.

Checkpoint after every accepted gate with source, validation commands, hashes,
runtime counters and captured evidence. Do not combine an unvalidated renderer
hook with a new input or UI hook in the same live run. The user-feedback
gates are: final billboard appearance, menu/pointer ergonomics, live weapon
alignment/comfort, vendor-panel placement, and embodied-body comfort; all other
feasible verification should be completed before requesting those checks.
