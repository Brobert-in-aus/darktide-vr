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
- An exact reflected `c_billboard` observation records both the bound upload
  resource and any engine scratch pointer. Scratch addresses are retained only
  for diagnostics; the accepted writer maps the exact GPU-visible resource at
  the draw boundary and never exports a temporary `Map` as a breakpoint target.
- Added a production-independent Z-up cylindrical basis calculation with
  deterministic vertical/invalid-input fallback.

### Billboard constant layout and accepted direct-CBV patch

- The D3D12 bootstrap now reads an explicit diagnostic sidecar before native
  hook installation. This fixes the startup-order conflict where Lua requested
  diagnostics after the proxy had already installed the non-diagnostic hook
  set. Missing diagnostics now fail the Lua stereo setup closed rather than
  dereferencing a nil native interface.
- Exact billboard resources are normally mapped, copied and unmapped before
  their draw. Their Map stacks consistently resolve through
  `Darktide.exe+0x7d589d` to the Stingray upload flush beginning at
  `Darktide.exe+0x7d5840`.
- The upload flush remains fingerprinted and diagnostic-only. It exposes a CPU
  scratch allocation, but direct mapping proved that allocation is not a byte
  mirror of the exact bound upload resource (`0/3825` matches).
- A bounded write watcher hit the selected staging address 32/32 times at the
  instruction ending at `Darktide.exe+0x670395`. Disassembly identifies the
  writer as the SIMD per-instance matrix composer beginning at
  `Darktide.exe+0x66fa70`; the write itself is the 16-byte store at `+0x670390`.
- Two scratch-arena write experiments reached the GPU and reproducibly ended in
  `DXGI_ERROR_DEVICE_HUNG`. The apparent stability of the older draw-time
  staging write was a timing illusion. Enabling that path now fails closed.
- `dxc -dumpbin` disassembly of all five captured billboard vertex shaders
  shows that `c_billboard[0].xy` is normalized and used as horizontal facing;
  registers 1-3 are not read by those vertex shaders and registers 4-7 form the
  world-to-clip matrix. The earlier six-float interpretation was incorrect.
- The accepted writer acts at exact reflected draw identity, requires
  `D3D12_HEAP_TYPE_UPLOAD`, maps the bound GPU-visible CBV before recording the
  draw, normalizes horizontal camera right and changes only register 0 XY. It
  does not rewrite descriptor heaps or root tables.
- A live character-select soak exceeded 7,800 direct patches without a device
  error. A subsequent 15-second synthetic pitch/roll XR run reached more than
  88,000 direct patches, submitted 1,105 frames / 1,104 fresh stereo pairs,
  reused no frames and recorded no pair timeout or device removal.

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
& .\tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 15 -SyntheticHeadSweep
& .\tools\stereo\request-primary-action-test.ps1
& .\tools\stereo\request-weapon-inventory.ps1
& .\tools\stereo\set-weapon-pose-trace.ps1 -Mode Enabled
& .\tools\stereo\set-weapon-presentation-test.ps1 -Mode Enabled
& .\tools\stereo\set-gameplay-input-test.ps1 -Mode Disabled
& .\tools\stereo\request-body-rig-inventory.ps1
& .\tools\stereo\set-body-ik-trace.ps1 -Mode Enabled
& .\tools\stereo\set-body-ik-presentation.ps1 -Mode Enabled
& .\tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 20 `
    -SyntheticControllerPath -SyntheticBodyPath
```

Results: all 29 Debug CTest tests passed. The native-capture test now installs the
diagnostic hook set, creates/maps/unmaps an upload buffer and verifies exactly
one matched Map and Unmap. It also proves retired descriptor/staging writes fail
closed and validates direct billboard direction gating. Core math covers cardinal headings, pitched and
vertical views, and non-finite billboard inputs. Presentation tests cover the
shared transport, horizon-locked panel pose and aspect-preserving extent. New
controller and pointer tests cover snapshot freshness/validity, finite panel
intersection, crop mapping, menu input transitions, runtime-IPD transport, and
the complete synthetic offscreen/over-reach/tracking-loss cycle.

### Full-body IK foundation

- Added a native analytic two-bone arm solver with reachable-annulus clamping,
  pole projection, stable bend fallback and non-finite input rejection.
- Exposed that exact implementation through the loaded native sidecar for Lua;
  the export is buffer-size checked and returns explicit clamp/fallback flags.
- Added a read-only, flag-gated local-player rig inventory and a separate
  normal-off solver trace. Neither path writes a body pose.
- A clean human hub inventory found 246 scene-graph items, the complete
  hips/spine/head and arm/leg chains, both hand and foot IK handles, and the
  live `aim_constraint_target`. Arm-chain local offsets are approximately
  0.2753/0.2748 m; live animated shoulder-to-elbow/elbow-to-wrist lengths were
  0.2615/0.2609 m left and 0.2618/0.2612 m right. Character select did not run
  this 3P update seam; the flag was consumed immediately after the hub player
  unit initialized.
- Added a separate `--synthetic-body-path` trajectory which preserves the
  existing absolute spatial-panel poses but replaces only recenter-relative
  hand poses with arm-scale sweeps, crossed hands, deliberate lateral/far
  over-reach and tracking loss. Its unit contract and the complete 29-test
  Debug suite pass.
- Live tracing exposed and fixed an anchor error before any body write: the
  generic controller helper is intentionally relative to the detached render
  camera, about 1.5 m behind this hub avatar. Body targets now translate the
  same immutable horizon orientation to the avatar `j_head` position. After
  correction, the initial sweeps solved unclamped at 0.24--0.51 m, the explicit
  far phase at sequences 246--299 clamped to the measured 0.522--0.523 m reach,
  and the invalid phase produced a matching 299--362 trace gap. Unclamped
  wrist error was 0.0000 m and clamped error equalled the unreachable excess.
- The final 20-second VDXR run submitted 1,111 frames (1,109 fresh pairs), with
  zero reuse/timeouts, two startup pose mismatches and a clean teardown. It
  produced no Lua, D3D12, native, device-hung or device-removal errors.
- The hub loaded and closed normally with no Lua, D3D12, device-hung or
  device-removal errors.
- Added the first normal-off arm authoring laboratory. It computes
  shortest-arc upper-arm and forearm deltas from the live animated chain,
  preserves the animation's existing twist, writes only the two local bone
  rotations, and propagates the player unit once through
  `World.update_unit_and_children`.
- The first guarded live attempt proved that `PlayerUnitAnimationExtension`
  does not expose a usable `_world`; the gate was detected but made zero bone
  writes. No skeleton mutation or error occurred. Authoring was therefore
  moved to the already verified
  `PlayerUnitFirstPersonExtension.update_unit_position` post-animation seam,
  which supplies the real level world and runs after stock animation restore.
- The corrected 20-second synthetic VDXR pass made 783 post-animation arm
  writes. Maximum measured solved-wrist error was 0.000018 m. Writes paused
  exactly across tracking loss (241 writes at sequence 300, 242 at sequence
  361), resumed on reacquisition, and far targets retained the solver's reach
  clamp. The bridge submitted 1,053 frames, 1,051 fresh pairs, zero reused
  frames/timeouts, and only the two expected startup pose mismatches. There
  were no Lua, D3D12, device-hung or device-removal errors.
- These writes were deliberately exercised on the hub's local third-person
  player model to validate the engine seam, not as a proposed hub feature. The
  hub must retain stock third-person animation. Product arm/hand authoring is
  now restricted to the private first-person `shooting_range` and
  `training_grounds` modes; missions remain disabled until the Psykhanium gate
  passes.
- Review found a same-process XR restart hazard before checkpointing: the
  authoring flag poll had used the shared XR sequence for cadence. It now uses
  a monotonic render-hook update counter, so a newly created bridge may restart
  its sequence at zero without delaying enable/disable changes. A clean
  redeploy then ran two eight-second synthetic XR sessions inside one Darktide
  process. The gate logged enabled, disabled, then enabled again; the second
  session resumed writes at reset sequence 12 and reached 750 cumulative
  writes with 0.000018 m maximum error. Both bridge runs passed with no reuse,
  timeouts, Lua errors or device errors.
- The first hand-orientation laboratory used a per-side calibration offset but
  exposed that Stingray quaternion userdata cannot be retained across frames;
  the writer failed closed. Calibration is now stored as four plain numeric
  components and reconstructed per update. A fault latch also prevents a
  failed writer from rearming until the external flag is explicitly disabled.
  This correction and hand orientation require validation in the Psykhanium,
  not the third-person hub.

### Worn billboard and 6DoF clamp check

- Worn character-select inspection falsified the current direct billboard-CBV
  candidate: smoke and other billboard sprites still tilt with headset pitch
  and roll. Although the interceptor observes and patches many draws, that
  activity is not evidence that it owns the visible sprites. Production draw
  patching is disabled again; the hook remains diagnostic-only.
- Disabling billboard diagnostics initially left the early D3D12 bootstrap
  flag enabled. The native layer correctly rejected Lua's contradictory
  diagnostic-hook selection with code 1, so stereo never initialized and the
  bridge showed only flat fallback. The stale flag has been moved aside.
- A first camera trace redeploy exceeded LuaJIT's file-scope local-variable
  ceiling and prevented the mod chunk compiling. Trace state now lives in the
  existing presentation table and the corrected mod initializes normally.
- The validated 6DoF camera composition is unchanged from checkpoint
  `27606c9`, apart from the intentional per-character scale multiplier (1.0
  for the tested Psyker). A clean instrumented run showed OpenXR translation
  entering Lua and the corresponding rotated delta in the final camera pose.
  Worn testing identified the apparent regression: XR established its recenter
  while the headset was lying on the desk. Picking it up moved beyond the
  0.25 m horizontal / 0.18 m vertical safety box, and subsequent small head
  movements never returned inside the box, so the hard-clamped pose appeared
  stationary. Translation worked normally when the headset remained within
  the box. This is a recenter/clamp UX defect, not a lost camera write.
- The recovery implementation now slides the box origin by rejected excess,
  so donning cannot strand the current pose far outside the boundary. The
  system Meta button remains reserved; its OpenXR `LOCAL` reference-space
  change is the explicit recenter signal. Worn validation passed: three Meta
  resets each produced `openxr.head_recenter=runtime-pending` followed by
  `openxr.head_recenter=applied`, while stereo remained live at roughly 108
  fresh pairs per second. Translation remained responsive after recenter.
- In first-person zones, sliding the box cannot remain camera-only. Its origin
  displacement must move the character root absolutely, while thumbstick
  locomotion independently retains Darktide's acceleration/deceleration and
  collision behavior. The head's position inside the box remains local camera
  translation. The third-person hub needs no body-root application.
- A separate XR-process restart reproduced a real transport lifecycle defect:
  Darktide continued advancing producer capture counters, but the restarted
  harness received zero fresh pairs from the named eye surfaces and silently
  displayed flat fallback. Reopening the same names did not reach the active
  generation; a clean Darktide restart restored fresh pairs. Do not conflate
  that shared-surface generation bug with the clamp symptom.

The controller-binding validation built every Debug target and passed all 29
tests, including the new gameplay mapper and opt-in synthetic button cycle.
The Release native capture and XR harness also built successfully. Live
validation used the
EAC-stopped character-select boundary and preserved the required ten-second
Steam close grace between normal runs.

### Splash-time XR startup

- `tools/stereo/start-darktide-vr.ps1` is now the default development entry
  point. It opens the mandatory Steam/Fatshark launcher, waits for the actual
  Darktide splash window, and starts OpenXR immediately. The existing flat
  capture therefore presents splash/loading content on the spatial board and
  transitions to stereo as soon as the producer is ready.
- `run-darktide-shared-eyes.ps1` gained a bounded `-WaitForGameSeconds` mode so
  startup races do not require manual timing. It still enforces the known game
  hash and EAC-inactive boundary before starting XR.
- The first live use validated the intended transition: OpenXR began during the
  splash with flat-fallback submissions, attached the shared-eye resources when
  character select became ready, and then delivered fresh stereo pairs without
  a second XR launch.

### Billboard PSO substitution repair

- Re-analysis of the earlier blanket run found that its three successful
  substitutions were not evidence for three horizon variants: the generated
  DXIL had harmless final-register padding in reflected constant-buffer sizes,
  one output-signature order differed, and the atlas variant introduced a
  redundant base-instance CBV plus the wrong structured-element width. Those
  failures explain the four rejected PSOs.
- The validator now permits only the precise DXC round-up from an original
  partial final constant-buffer register to its 16-byte boundary. Resource
  registers, dimensions, types, signatures and constant-buffer kinds remain
  exact. The atlas replacement uses the native `SV_InstanceID` semantics and a
  four-byte structured element, matching the original interface.
- The corrected live run applied all seven observed substitutions across all
  five versioned hashes: `1/1/2/1/2` applications respectively, with zero
  validation rejects and zero creation rejects. Four spherical variants carry
  the horizon construction; the tangent-driven ribbon/beam variant remains
  intentionally unchanged. Worn smoke appearance remains the acceptance gate.
- Worn testing then falsified ownership, not merely the horizon calculation:
  with all five variants (including the tangent variant) successfully replaced
  by diagnostic shaders that forced their likely color varying to saturated
  magenta, zero purple objects or effects were visible anywhere in character
  select. The five-hash set therefore does not own the visible smoke and is
  disabled again.
- The archived vertex-shader census actually contains 268 shaders with the
  `c_billboard` reflection name among 1,907 captured shaders. The prior five
  were not exhaustive. The next bounded step ranks only shaders whose reflected
  `c_billboard` PSOs issue live draw calls in character select, then performs a
  grouped color localization on that much smaller evidence-backed set.

### Billboard ownership localization: pixel and draw evidence

- Pixel-shader capture was expanded from the original nine candidates to all
  586 pixel permutations paired with a reflected `c_billboard` vertex shader.
  Interface-matched magenta replacements still changed only one rare,
  short-lived, mostly occluded object. This falsifies the assumption that the
  visible character-select smoke can be found merely by reflecting the
  `c_billboard` name.
- A census of all alpha-blended PSOs captured 1,087 pixel shaders, of which
  1,086 were inspectable DXIL and received interface-matched magenta probes.
  The blanket set made the entire frame magenta because it included fullscreen
  composites. Pixel input signature count then provided a reproducible coarse
  split: four/five-input shaders changed splash/loading backgrounds but no
  character-select scene objects; three-input shaders changed nothing; the
  two-input bucket contained a fullscreen composite; and the >=6-input bucket
  changed small scene particles plus some emissive/light sources.
- Creation-time PSO manifests now record every substituted PSO's original
  VS/PS hashes, input layout, topology, blend/depth state, culling and formats,
  and archive the paired vertex bytecode. They exposed an actual instanced-quad
  generator layout (`POSITION1` per-vertex corners plus per-instance
  `POSITION0`, `COLOR` and size/UV fields). Its VS disassembly expands the quad
  from camera-facing basis data, directly explaining why these effects roll
  with the headset. However, probing all 86 >=6 pixel shaders paired with this
  creation-time layout produced no visible magenta. Created permutations are
  not evidence that a PSO is drawn in the observed scene.
- A bootstrap-time `darktidevr_vertex_shader_dump.flag` was added so the draw
  logger can be selected before D3D12 hooks install. Enabling it late from Lua
  returned code 1 and prevented normal XR startup; bootstrap selection fixed
  that lifecycle error. A short >=6 draw census reduced 679 active probes to
  two hashes visible in logged PASS records, but both were negative when run
  alone. The visible source therefore lives in pre-recorded/reused work not
  represented by the logger's newly recorded command lists.
- The remaining bounded localization set was 593 >=6 shaders excluding the 86
  already-negative instanced-layout permutations. One coarse split established
  that the visible particle owner was in the upper 148 hashes of the positive
  297-hash half; repeated binary yes/no splits were then abandoned because they
  throw away nearly all of the information available from a rendered frame.
- `tools/stereo/build-shader-id-probes.ps1` now assigns every candidate a
  unique constant output colour in one run. A first 148-colour lattice put the
  particles in the green/teal hue family despite lighting modulation. A
  conservative hue filter reduced this to 18 candidates, which were spread at
  20-degree intervals over a full-saturation hue wheel for a second run.
- The full-wheel run made the particles unambiguously magenta, which would map
  to index 15 and pixel shader `61fa6dde316a6313` if every observed colour came
  from that run. The user's close crop confirms the particle pixels themselves
  were magenta rather than merely teal under scene lighting. However, the first
  isolated one-shader rerun was invalidated before its
  visual result was accepted: Darktide's `shader_library.pso_lib` and
  `state_stream_library.pso_lib` had been created by the prior colour run, no
  new substitution or PSO-pair manifest entry occurred, and shutdown rewrote
  those libraries. This proves diagnostic replacement PSOs can persist across
  launches. Both exact cache files were moved (not deleted) into timestamped
  backup `pso-cache-backup-20260826-203958`. The subsequent cache-clean run has
  so far produced no `61fa6dde316a6313` substitution or PSO-pair manifest
  entry, so the index-15 identification remains provisional pending the visual
  check and is likely contaminated by an earlier colour lattice. If negative,
  rerun the 148-colour then 18-colour ID stages with a fresh PSO cache at each
  stage. `start-darktide-vr.ps1 -FreshPsoCache` now performs
  this preservation step explicitly for future shader diagnostics, while the
  default launch path leaves the normal game cache untouched.
- A cache-clean rerun of the 148-candidate A2 colour set recorded 127
  substituted PSO-pair rows covering 25 distinct candidate pixel hashes, but
  the visible particles remained uncoloured. This invalidates the earlier A2
  narrowing and the provisional `61fa6dde316a6313` identification.
- A cache-clean hue-wheel run over the complete 593-candidate complement then
  coloured the visible particles green/teal. This is the first trustworthy
  positive colour-localization result because both persistent PSO libraries
  were preserved and removed before launch. It bounds the owner to the teal
  arc of that full ordered set.
- A three-candidate follow-up selected only hashes observed in the creation
  manifest near the teal hues (`5beaae9e972f80e9`, `737f9ac41a693fd1`, and
  `862fe950e4f484a4`, rendered red/green/blue). The particles were uncoloured.
  Creation-time PSO manifests are therefore incomplete for this effect, just
  like the newly-recorded command-list logger: reused or pre-recorded work can
  render without appearing in either data source. Do not use either manifest
  as an exhaustive filter again.
- The next cache-clean validation set is already built from the full ordering:
  115 hashes spanning hue 130-200 degrees, indices 215-329, under
  `build/generated/shader_id_full593_teal_arc_hue`. The first hash is
  `63ea89ef5488e73a` and the last is `96f85d0f82313f95`. Spreading these 115
  candidates over a new full hue wheel should reduce the owner to a small
  colour neighborhood in one worn check; a final wide-palette rerun can then
  identify the exact pixel shader.

## Next action

Run the already-built 115-candidate teal-arc hue wheel with
`start-darktide-vr.ps1 -FreshPsoCache`, record the particle colour, and narrow
once more from the complete ordered candidate list without filtering through
the incomplete creation or draw manifests. After a cache-clean one-shader
positive, map that exact pixel shader back to every bound vertex shader and
draw state before attempting a cylindrical replacement. Extend pipeline-stream
and cached/pre-recorded command diagnostics as necessary. Do not optimize or
ship the falsified direct-CBV billboard candidate. Separately repair the shared-eye generation handshake so
an XR-process restart cannot remain on flat fallback. Preserve the explicit first-person
locomotion task: safety-box overflow moves the character root absolutely, while
stick movement continues through Darktide's native acceleration, collision and
platform handling. Keep the new vendor transport normal-on but avoid repeated
hub launches until a clean hub session is available. Then open a non-purchasing
vendor through its ordinary interaction, verify the board is stationary in
`LOCAL`, exercise only a tab/back control, and confirm stereo restoration.

As an immediate visibility aid after the pixel owner is confirmed, build a
diagnostic paired-vertex replacement that multiplies the particle quad extent
by 10. Size cannot be changed by the constant-colour pixel probe itself, so
apply the scale only to vertex shaders/PSOs proven to pair with the isolated
particle pixel shader. Validate that it enlarges particles without changing
fullscreen composites or emissive/light geometry, then use the enlarged
particles for easier colour and cylindrical-billboard inspection.
