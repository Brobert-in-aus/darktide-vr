# Unattended development session — 2026-08-26

## Active scope

Execution follows `docs/phase1/unattended-development-plan-2026-08-26.md`.
The Quest remains EAC-inactive and testing is limited to synthetic OpenXR,
character select, the non-interactive hub and the single-player Psykhanium.

## Accepted checkpoints

### Preflight and runtime health

Added `tools/unattended/invoke-unattended-preflight.ps1`. It:

- requires exactly one authorized Quest and verifies its model;
- reapplies the temporary proximity override unless explicitly skipped;
- records only the Quest model/count and power state, not its serial or IP;
- verifies Virtual Desktop and the active OpenXR runtime;
- distinguishes Darktide, its launcher and its crash reporter by exact process
  name/path rather than broad process-name matches;
- records EAC state and hashes the game, deployed mod/native files and current
  source/build outputs; and
- optionally runs a bounded synthetic OpenXR smoke test.

Live validation submitted 600/600 rendered frames through VirtualDesktopXR at
approximately 117 Hz. The first `xrCreateInstance` call was retried internally
by the existing harness and the same run then completed successfully, so no
Virtual Desktop restart was justified.

### Billboard producer discovery foundation

- The retired live descriptor-table/shadow-heap billboard write mode now fails
  closed. Its bounded selector/counters and the accepted per-PSO shader fallback
  remain available.
- Diagnostic resource hooks now track buffer `Map`/`Unmap`, associate the CPU
  base with the recorded GPU virtual-address range, and expose aggregate counts.
- An exact reflected `c_billboard` observation records whether it came from a
  persistent engine mapping and exports a selected persistent CPU address only
  when that address remains valid. A temporary diagnostic `Map` is never
  exported as a writer-breakpoint target.
- Added a production-independent Z-up cylindrical basis calculation with
  deterministic vertical/invalid-input fallback.

### Billboard producer localized and first safe patch

- The D3D12 bootstrap now reads an explicit diagnostic sidecar before native
  hook installation. This fixes the startup-order conflict where Lua requested
  diagnostics after the proxy had already installed the non-diagnostic hook
  set. Missing diagnostics now fail the Lua stereo setup closed rather than
  dereferencing a nil native interface.
- Exact billboard resources are normally mapped, copied and unmapped before
  their draw. Their Map stacks consistently resolve through
  `Darktide.exe+0x7d589d` to the Stingray upload flush beginning at
  `Darktide.exe+0x7d5840`.
- The upload flush is enabled only when the current executable matches a
  reviewed 12-byte signature. It exposes the persistent CPU staging allocation
  corresponding to each D3D12 upload resource without changing the upload.
- A bounded write watcher hit the selected staging address 32/32 times at the
  instruction ending at `Darktide.exe+0x670395`. Disassembly identifies the
  writer as the SIMD per-instance matrix composer beginning at
  `Darktide.exe+0x66fa70`; the write itself is the 16-byte store at `+0x670390`.
- The first horizon-lock path now writes only six approved basis floats in the
  persistent staging CBV after exact reflected billboard identity is proven.
  It does not alter descriptor heaps, root tables or GPU-visible allocations.
- A 35-second clean character-select soak recorded 11,404 exact billboard CBVs
  and exactly 11,404 staging patches, with the fingerprinted upload hook active
  and no Lua, engine, D3D12 device-removal or device-hung error.

The standalone debugger watcher is diagnostic-only. It produced the needed
writer evidence, but Darktide exited after debugger detachment and opened Crash
Reporter. Do not repeat that attachment in ordinary validation; no crash report
was submitted.

### Fullscreen menu presentation without pointer

- Added a versioned, single-writer shared presentation-state transport named
  `Local\DarktideVR-presentation-state-v1`. Its seqlock snapshot carries mode,
  transition sequence, source extent/crop and maximum panel dimensions.
- The native API publishes `stereo_world`, `flat_loading_or_cinematic`,
  `world_anchored_menu`, `flat_menu` and `disabled/error`. The legacy binary
  event remains as a compatibility fallback, but all new transitions use one
  monotonic transport-level sequence.
- The Lua UI-manager hook maintains the fullscreen-view stack, records view
  flags, recognizes loading/cinematic and explicit menu views, and waits twelve
  updates after the stack empties before restoring stereo. This avoids an old
  UI-world teardown incorrectly overriding the live lobby state.
- Flat modes now fit the captured aspect ratio within a 2 m by 2 m maximum,
  anchor approximately 2 m from the transition-time head pose, discard head
  pitch/roll, and remain fixed in LOCAL space.
- Live logs proved the exact sequence `loading` (2), `stereo_world` (3),
  `flat_menu` for `system_view` (4), then `stereo_world` (5) after close.
- A five-minute XR run recorded 5,564 flat-fallback submissions followed by
  14,744 fresh shared-eye pairs, zero reused frames and zero pair-driven
  timeouts. Only two pose-sequence mismatches occurred; maximum measured angular
  lag was 0.049 degrees.
- Quest evidence is archived at
  `artifacts/unattended/menu-xr/darktidevr-menu-panel.png` and
  `artifacts/unattended/menu-xr/darktidevr-menu-closed.png`: the first shows the
  system menu once on the spatial panel, and the second shows restored stereo.

Two early live attempts exceeded Lua 5.1's 200-local chunk limit. Presentation
state was collapsed into one table, startup then remained clean, and the final
chunk has 196 top-level locals. This was recovered before the accepted run.

### Controller, pointer and Psykhanium foundation

- Added `Local\DarktideVR-controller-state-v1`, a versioned seqlock transport
  for both hands' aim/grip poses, tracking flags, trigger/squeeze/thumbsticks,
  buttons and sample timing. Readers reject malformed and stale snapshots.
- The OpenXR harness now creates Touch-controller and Khronos-simple actions,
  publishes controller samples, and maps the tracked right-hand aim ray to the
  spatial flat panel. This stage is observation-only and cannot inject input.
- Added deterministic panel intersection/crop-to-source-pixel math plus a menu
  input edge state machine. Entering a menu cannot synthesize a click, leaving
  releases any held button, and move/down/up/scroll/back events are explicit.
- A 300-frame VDXR theatre smoke published all 300 controller samples. The
  controllers were asleep, so zero frames were marked tracked; the untracked
  fail-closed path was therefore exercised without user interaction.
- Added an explicitly gated `--enable-menu-input` Windows adapter. It converts
  captured source pixels through the current DPI-aware Darktide client rectangle
  into absolute virtual-desktop coordinates, requires exactly one matching
  foreground window, maps trigger/scroll/Back through `SendInput`, and always
  releases a synthetic left button if focus or menu ownership is lost. The
  ordinary stereo launcher keeps it disabled unless `-EnableMenuInput` is
  supplied.
- The adapter's first 10-second VDXR safety smoke generated 1,079 controller
  samples with sleeping controllers and exactly zero pointer events or injected
  inputs. Unit coverage includes a negative-origin multi-monitor desktop and
  rejects off-source/off-desktop coordinates.
- Added a test-only synthetic two-controller path for unattended runs. Its
  six-phase cycle sweeps each hand across the panel, crosses both, exits through
  both viewport edges, exceeds the 1.5 m reach envelope, invalidates tracking,
  and reacquires. It emits no buttons or triggers and requires the explicit
  `--synthetic-controller-path` flag.
- A 12-second live VDXR system-menu run completed 1,300 synthetic frames and
  every phase (240/240/240/220/180/180 frames). It evaluated 480 in-reach
  right-hand rays with 400 panel hits. Menu injection remained disabled, so it
  dispatched exactly zero OS input events.
- An explicit follow-up with the Windows menu adapter enabled dispatched all
  260 valid synthetic pointer moves into the foreground Darktide client. The
  off-panel, over-reach and invalid-tracking phases dispatched nothing, and the
  button-free path did not select or close any menu item.
- Head-pose transport v6 now carries runtime IPD measured from the two OpenXR
  view poses. The game uses that calibrated separation rather than a hardcoded
  population average. Ogryn scale IPD and physical head translation by
  `1.61 / 1.21` while retaining the game-native elevated clean camera; 64 mm is
  only the pre-XR initialization fallback.
- The same live runtime reported 62.81 mm calibrated eye separation. Startup,
  character-select, hub entry and the system-menu fallback remained clean with
  the matched v6 Lua/native deployment.
- Added an observation-only native controller export: two aim poses, two grip
  poses, tracking flags, analog actions, buttons, sequence and timestamp are
  now available to Lua without changing gameplay input. Lua logs the first
  genuinely tracked sample and otherwise remains inert.
- Current-source inspection identified the upstream aim split:
  `PlayerUnitFirstPersonExtension.fixed_update` authors the shared
  `first_person_component.rotation`, which the aim extension, weapon system,
  interactions and abilities consume. Controller aim must feed that shared
  gameplay rotation while the stereo render hook uses a separate body-yaw plus
  HMD basis; consumer-by-consumer weapon patches are not the selected route.
- Core math now provides an exact OpenXR-to-Darktide vector/quaternion/pose
  basis conversion and a recentered controller-pose primitive. Tests cover
  forward/up axes, quaternion/vector equivalence, translated controller poses,
  and a non-identity HMD recenter.
- Implemented controller-state transport v2. Each hand carries both absolute
  OpenXR LOCAL aim/grip poses for spatial menus and recentered, Z-up
  Darktide-basis poses for gameplay. The latter copy tracking validity only
  after the initial HMD recenter is known, and the native Lua export exposes
  that fail-closed body-local form. The transport round-trip and complete
  Release suite pass.
- A clean launcher-path deployment validated v2 against VDXR at character
  select. The synthetic provider was corrected to publish on every immersive
  XR frame rather than only while a flat menu panel was visible. A 12-second
  run published 865/865 controller samples, covered all six motion/invalidity
  phases (`180,180,145,120,120,120`), dispatched no menu input, and Lua logged
  the first tracked v2 sample with both aim flag sets equal to 15.
- Added a strictly observation-only controller-aim adapter at both production
  orientation classes: `DefaultPlayerOrientation` for combat and
  `HubPlayerOrientation` for the social hub. It converts the exported
  Darktide-basis quaternion through the engine's own
  `Quaternion.to_yaw_pitch_roll` and records controller and game orientation
  without authoring either. A clean hub run published 827 controller samples
  and logged multiple advancing observations (`class=hub`, sequences 1
  through 713, `write=disabled`) with no script error or gameplay write.
- Completed the missing world-space composition at that observation seam. The
  hub's initial body yaw is captured once per XR controller sequence epoch and
  multiplied by the exported body-local controller rotation. A clean
  launcher-path VDXR run published 578/578 controller samples; Lua observed
  tracked flags `15/15`, sample ages from 0.213 to 16.567 ms, an anchor yaw of
  3.1415 radians and the expected composed target
  `3.1415,-0.3094,0.0758`, still with `write=disabled`.
- Stingray quaternion/vector values returned to Lua are frame-temporary and
  cannot be retained in mod tables. An earlier observer retained one and later
  failed `Quaternion.multiply` with `Vector4 expected, got userdata`. The
  accepted path stores only yaw/pitch/roll scalars and reconstructs both
  quaternions immediately at the orientation hook; the clean run produced no
  safe-hook, script or quaternion error.
- Added a normal-off, file-armed controller-aim authoring gate plus
  `tools/stereo/set-controller-aim-test.ps1`. The orientation hook clears pose
  usability before every native read, requires tracked position/orientation and
  a -5--100 ms sample age, composes the body yaw with body-local aim, writes
  yaw/pitch only, and forces gameplay roll to zero. The HMD render basis remains
  on the independent stereo camera path.
- Disabled and enabled hub runs both passed. The armed run published 456
  controller samples, kept menu input at zero, performed 302 bounded orientation
  writes, held yaw at 3.1415, and changed pitch from 6.2832 to 5.9745 (the
  modulo-2-pi representation of the -0.3087 target). Roll remained 0.0000 and
  no script/safe-hook error occurred. The flag was returned to `disabled`
  immediately after the run.
- The fail-closed path now emits transition-only suspension telemetry. A
  577-sample synthetic run suspended authoring at sequence 301 when tracking
  flags became zero, resumed after reacquisition, and suspended again when the
  final sample aged to 105.142 ms after XR stopped. A controller-sequence epoch
  change also blocks its first sample so a complete fresh sample must arrive
  before writes resume. The run completed 403 writes with no script error and
  restored the file flag to `disabled`.
- Added a guarded one-shot `dtvr_enter_psykhanium` workflow derived from the
  game's own training-view path. It consumes a local flag, waits for hub game
  mode plus backend authentication, opens the training view, resolves the
  Shooting Range option by semantic key, verifies that the options context is
  mission `tg_shooting_range`, and only then confirms `play_button`.
- Live evidence proved automatic character-select -> hub -> training-menu ->
  private Psykhanium entry and `GameplayStateRun`, with
  `DARKTIDEVR_PSYKHANIUM result=pass game_mode=training_grounds`.
- That transition exposed a stereo teardown ordering bug: by the time a new
  `CameraManager` is observed, Stingray may already have destroyed the old
  world's `viewports` table. Teardown now clears mod references and leaves the
  old right-eye viewport to normal world destruction; it no longer queries the
  stale `ScriptWorld`.
- The corrected private-Psykhanium run remained clean for a 30-second game
  soak, then a 30-second VDXR projection run submitted 1,794/1,794 frames with
  1,793 fresh stereo pairs, zero reused frames or pair timeouts, one pose-pair
  mismatch, and 0.041 degrees maximum measured angular lag. Controller state
  was published on all 1,794 frames and remained safely untracked while the
  controllers slept.
- Two later attempts to enter from a populated public hub reproduced a
  base-game teardown race: `PlayerHuskLocomotionExtension.post_update` queried
  a missing remote-husk `parent_unit_id` during `wait_shooting_range` and the
  title crashed. A 30-second hub soak did not prevent it. No VR hook appeared
  in either stack. Arming the one-shot transition at character select, before
  the public hub populated, completed cleanly with
  `result=pass game_mode=training_grounds`; this is the selected unattended
  sequencing path. An unexercised error-swallowing guard was removed rather
  than retained.
- The test-only controller writer then passed in the Psykhanium. A 600-frame XR
  run produced 539 combat-orientation writes through
  `DefaultPlayerOrientation`, kept the 4.7124-radian body anchor, authored the
  -0.3079 pitch and zero roll, suspended on synthetic tracking loss and stale
  post-session data, and emitted no menu input.
- A downstream `PlayerUnitFirstPersonExtension.fixed_update` observer converted
  the component rotation immediately and proved the shared weapon/action seam
  receives the authored value. At controller sequences 120, 240, 361 and 481,
  `first_person_component.rotation` was consistently
  `-1.5708,-0.3079,0.0000` with forward ray
  `0.9530,0.0000,-0.3031`. No downstream component or script error occurred.
- Live input inventory confirmed that the active `Ingame` service exposes the
  complete primary-action family: `action_one_pressed`, `action_one_hold` and
  `action_one_release`, all under alias `action_one`. Current extracted source
  confirms `action_one_pressed` is an ephemeral input which is OR-accumulated
  by `HumanInputHandler.pre_update` and copied exactly once into the next fixed
  input frame.
- Added a normal-off `darktidevr_primary_action_test.flag` gate and helper. It
  consumes only `fire_once`, waits for `training_grounds`/`shooting_range`, an
  enabled aim-authoring gate and a fresh tracked right-hand pose, then places a
  single `action_one_pressed` edge into Darktide's own ephemeral cache. It
  cannot inject twice in one process and never arms in the hub or menus.
- The first clean early-transition validation armed at controller sequence
  9298, injected the pressed edge once, and observed `fixed_cache=true` on
  fixed frame 1474. Source review then showed the equipped sword begins from
  `action_one_hold`, so the final synthetic event models one complete button
  click: pressed plus held for exactly one fixed frame, followed by release.
- The corrected click passed end to end at controller sequence 5796. Fixed
  frame 1913 contained `pressed=true, held=true` and the local weapon state
  immediately became `action_melee_start_left`; frame 1914 contained
  `release=true, held=false`. The correlated authored forward ray was
  `0.9533,-0.0009,-0.3021`. It produced no repeated attack, script error or
  safe-hook error.
- Added the first production-shaped controller binding foundation. Native
  `GameplayInputMapper` maps Quest trigger/squeeze/face/stick-click/menu state
  to 11 semantic actions with analog hysteresis and exact edge generation.
  Context shutdown releases all held actions once. A normal-off Lua adapter,
  additionally restricted to private training modes, injects the nine action
  families owned by `HumanInputHandler`; tag/menu remain explicitly pending at
  their separate consumers. Enable only for a bounded test with
  `tools/stereo/set-gameplay-input-test.ps1 -Mode Enabled`.
- The synthetic path gained a second explicit
  `--synthetic-gameplay-input` gate. Default synthetic controller runs still
  publish zero buttons/triggers; the extra gate deterministically covers every
  direct action for unattended Shooting Range validation.
- The first disabled-adapter startup check parsed and registered all mod hooks,
  authenticated and reached character select cleanly. The subsequent hub load
  crashed before Psykhanium entry in unmodified
  `PlayerHuskLocomotionExtension.post_update` because network object 126 lacked
  `parent_unit_id`. No controller harness was running, the gameplay adapter was
  disabled, and the crash stack contained no mod hook. Preserve this as an
  external hub-transition failure rather than evidence about the adapter.
  A fresh launcher-authenticated rerun reproduced the exit during the lobby
  load before the one-shot Psykhanium flag was consumed, again with no XR
  harness and the adapter flag disabled. End-to-end action validation therefore
  moved behind this external hub-session blocker; startup/parser validation is
  complete.
- Menu input now honors the same gameplay/UI boundary in both processes. Lua
  enables gameplay edges only in `stereo_world` while
  `Managers.ui:inputs_in_use()` is false. The XR harness composites a visible
  high-contrast cursor into the GDI-captured menu panel because the OS cursor
  is absent from `StretchBlt`; its normalized coordinate is identical to the
  Windows click mapping. Held stick scrolling repeats after 350 ms at 10 Hz
  with bounded catch-up. Pixel, mapping, edge and repeat tests pass.
- Eagerly requiring `PlayerUnitWeaponExtension` from mod initialization caused
  a reproducible module-load loop at `scripts/utilities/action/action_handler`.
  The observer now uses DMF's delayed string-class hook; the next clean run
  logged the delayed hook applying when the extension became available and
  completed normally. Do not reintroduce an eager require for this class.
- Live testing found that the older Testify example's hardcoded
  `option_button_3` is stale: Horde now occupies option 1, making option 3
  Advanced Training. That route had produced the misleading
  `game_mode=training_grounds` pass and equipped `unarmed_training_grounds`.
  The semantic resolver selected the current Shooting Range at index 4, the
  options view reported `mission_name=tg_shooting_range`, and the loaded world
  passed as `game_mode=shooting_range mission=tg_shooting_range`.
- In that exact mission, slot 1 held `forcesword_p1_m3` and the bounded click
  entered `action_melee_start_left`. A clean rerun selected slot 2 before the
  pulse; the context was `slot_secondary`, template `forcestaff_p4_m1`, and the
  same one-frame pressed/held plus next-frame release sequence immediately
  entered the ranged projectile action `rapid_left` at controller sequence
  12281. The force-staff projectile path consumes
  `first_person_component.rotation`, then applies weapon spread/targeting in
  `ActionSpawnProjectile:_fire_projectile`; it does not increment the generic
  hitscan `action_shoot.num_shots_fired` counter observed by the current probe.
- Added delayed, read-only observers at all three projectile-locomotion
  handoffs. A clean launcher-path rerun selected the same force staff and
  injected at sequence 14138. `rapid_left` began on fixed frame 2532, released
  on 2533, and the authoritative manual-physics handoff reported direction
  `0.9549,-0.0008,-0.2971` against authored first-person forward
  `0.9539,0.0008,-0.3000`. The small difference is the weapon's normal spread;
  the input-to-gameplay-aim-to-projectile chain is now closed without changing
  origin, spread, targeting, cadence or damage.
- Added a normal-off live weapon inventory request and expanded it across the
  first-person skeleton, wielded weapon, all 1P attachment units and semantic
  FX sources. In the exact Shooting Range mission the force staff root was
  identical to first-person `j_rightweaponattach`; the 187-node first-person
  rig contains `j_righthand`/`j_lefthand`, while the visible staff is seven
  linked 1P attachment units. Its charge, muzzle and overheat aliases resolve
  to `fx_overheat` on attachment 4. This rules out per-mesh attachment edits as
  the primary tracked-weapon seam.
- Added a separate normal-off weapon-pose trace. It reconstructs the right grip
  in game world space from the recenter-relative Darktide-basis controller pose
  and the pre-HMD camera anchor, then compares it with the animated hand,
  `j_rightweaponattach` and wielded weapon root. A clean synthetic run emitted
  142 samples over every sweep/outside/reach/loss phase. The attachment and
  weapon roots remained coincident to `0.000000` m through idle and weapon-swap
  animation, while the target crossed the view and reached roughly 3.0 m away
  during the deliberate over-reach phase. No gameplay or visual transform was
  authored, and the trace flag was returned to `disabled`.
- Darktide's Lua 5.1 mod chunk is at its top-level local-variable ceiling. One
  additional `local function` caused DMF to receive a nil compiled function and
  disable the stereo mod at initialization. Diagnostic helpers now live on the
  existing `presentation` table; future helpers must not add top-level locals
  without first consolidating existing ones.
- Implemented the first normal-off tracked weapon-presentation gate. Source
  inspection identified `PlayerUnitFirstPersonExtension.update_unit_position`
  as the production post-animation seam: it restores the stock root, updates
  animation variables and calls `World.update_unit_and_children`. Earlier
  fixed-update writes were correctly rejected as a visual result because their
  measured post-hand error remained unchanged and the later method overwrote
  them.
- The accepted hook runs after that method, derives the actual scene-graph root
  by walking six parents from `j_righthand`, applies the world-space delta that
  maps the animated hand to the tracked grip, and explicitly propagates the
  changed unit/children once. It is limited to the private training modes,
  requires a fresh valid grip and an unparented 1P root, and rejects wrist
  displacement above 0.75 m.
- A clean synthetic VDXR run accepted 458 presentation frames. Every sampled
  post-write hand position had `0.000000` m target error, post-hand yaw/pitch/
  roll exactly matched the target, and the right weapon attachment stayed
  coincident with the linked weapon root at `0.000000` m. Outside/over-reach
  phases were blocked and tracking loss produced no write. The gate was
  returned to `disabled`; controller aim and gameplay origin remained disabled
  and unchanged throughout.

### Vendor/NPC-anchored menu transport

- Upgraded the shared presentation mapping to
  `Local\DarktideVR-presentation-state-v2`. It appends a seqlock-protected,
  validated body-relative panel pose while preserving the old publication API
  for stereo, loading and generic flat-menu modes. `world_anchored_menu` now
  fails closed unless that pose is present, finite, normalized and within a
  100 m transport bound.
- Added the inverse Darktide-to-OpenXR vector/quaternion/pose conversion and a
  tested reconstruction primitive:
  `initial_hmd_recenter * darktide_to_openxr(body_panel_pose)`. The OpenXR
  harness snapshots this result only when the menu presentation sequence
  changes, so later headset motion cannot drag an NPC panel.
- Added a production-shaped `ViewInteraction:_start` observer. It acts only
  after the exact requested view is active, captures the interactee's
  `ui_interaction_marker` (unit root fallback), places a horizon-locked 2 m by
  2 m board 0.25 m toward the player, and converts it through the inverse of
  the clean pre-HMD camera transform already used by tracked weapons. Closing
  that view invalidates the anchor. Cinematic substitutions, unavailable
  stereo/body poses, dead units and distances outside 0.25--10 m retain the
  generic head-anchored menu fallback.
- The complete Debug build and all 27 CTests pass, including new transport,
  inverse-basis round-trip and anchored-pose reconstruction coverage. Live
  vendor validation is deferred: two launcher-path attempts crashed during hub
  transition in unmodified `PlayerHuskLocomotionExtension.post_update` before
  any vendor request, adapter enablement or synthetic harness run.

## Validation commands

```powershell
$cmake = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
& $cmake --preset windows-vs2022
& $cmake --build --preset windows-vs2022-debug
& (Join-Path (Split-Path $cmake) 'ctest.exe') --preset windows-vs2022-debug
& .\tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 600
& .\tools\stereo\set-controller-aim-test.ps1 -Enabled
& .\tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 300 -SyntheticControllerPath
& .\tools\stereo\request-primary-action-test.ps1
& .\tools\stereo\request-weapon-inventory.ps1
& .\tools\stereo\set-weapon-pose-trace.ps1 -Mode Enabled
& .\tools\stereo\set-weapon-presentation-test.ps1 -Mode Enabled
& .\tools\stereo\set-gameplay-input-test.ps1 -Mode Disabled
```

Results: all 27 Debug CTest tests passed. The native-capture test now installs the
diagnostic hook set, creates/maps/unmaps an upload buffer and verifies exactly
one matched Map and Unmap. Core math covers cardinal headings, pitched and
vertical views, and non-finite billboard inputs. Presentation tests cover the
shared transport, horizon-locked panel pose and aspect-preserving extent. New
controller and pointer tests cover snapshot freshness/validity, finite panel
intersection, crop mapping, menu input transitions, runtime-IPD transport, and
the complete synthetic offscreen/over-reach/tracking-loss cycle.

The controller-binding validation built every Debug target and passed all 27
tests, including the new gameplay mapper and opt-in synthetic button cycle.
The Release native capture and XR harness also built successfully. Live
validation used the
EAC-stopped character-select boundary and preserved the required ten-second
Steam close grace between normal runs.

## Next action

Keep the new vendor transport normal-on but avoid repeated hub launches until a
clean hub session is available. Then open a non-purchasing vendor through its
ordinary interaction, verify the board is stationary in `LOCAL`, exercise only
a tab/back control, and confirm stereo restoration. Meanwhile continue the
independent billboard producer investigation and offline full-IK/control
architecture. When the hub transition is healthy, retry the private Shooting
Range action audit with both gameplay gates bounded and disabled everywhere
else.
