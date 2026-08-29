# 2026-08-29 development session

## Implemented

- Made range locomotion additive. Neutral VR thumbstick state leaves the
  existing Darktide movement cache untouched; active VR movement combines with
  and clamps the signed game movement vector.
- Added raw per-hand thumbstick, existing-vector, combined-vector, and ownership
  telemetry for the next live range test.
- Added runtime counters for each thumbstick action's OpenXR `isActive` and
  `changedSinceLastSync` states. Together with the new native export fixture,
  the next run can distinguish an inactive Virtual Desktop binding from a
  transport or Lua-injection failure.
- Added a normal-off, range-only headless third-person presentation seam using
  Darktide's own equipment visibility path. The visual swap shows the complete
  3P loadout, hides the 1P visual rig, then hides 3P face, facial hair, hair,
  and headgear slot units without changing gameplay/camera mode.
- Audited the visibility and attachment path after a live test exposed a curio
  at the right hand instead of the avatar. `slot_attachment_1` through `_3`
  are gadget slots explicitly configured with `hide_unit_in_slot = true`; the
  bug was our blanket visibility override, not an authored body attachment.
  Headless presentation now mirrors Darktide's computed `slot.hidden_3p` state,
  retains every stock-visible body/gear/weapon unit, preserves hidden gadgets
  and unwielded equipment, and suppresses only head-related slots.
- The first metadata-enabled live run found why the stock pass had not exposed
  the body: `active and false or self._is_in_first_person_mode` is not a valid
  Lua false-valued ternary and always selected the stock first-person mode.
  It left every live 3P slot `hidden_3p=true`. Replaced it with an explicit
  branch so the range override actually requests Darktide's 3P visibility.
  The same run confirmed all three equipped defensive gadgets explicitly use
  `attach_node=j_rightweaponattach` while their slot configuration requires
  them hidden, exactly explaining the observed hand-tracking curio.
- Confirmed that equipment is spawned at its item-authored `breed_attach_node`,
  `attach_node`, or wielded/unwielded node and linked with `World.link_unit`.
  The VR body path neither relinks nor translates any 3P attachment. Arm IK
  writes only the avatar upper-arm, forearm, and hand rotations, then updates
  their children so stock hand/weapon attachments inherit the pose.
- Added an exact parent-chain gate for each IK arm. A rig must resolve
  `j_*arm -> j_*forearm -> j_*hand`; a breed with an intermediate or unrelated
  node now fails closed rather than receiving mathematically invalid local
  rotations or dragging linked equipment through the wrong hierarchy.
- Diagnosed a violently unstable XR-camera launch as two concurrently running
  `darktidevr-xr-harness.exe` producers. The game log showed pose sequence
  numbers repeatedly moving backwards and 64 capture-tag resets in roughly
  five seconds. Both stale writers were stopped. The shared-eye runner now
  holds a named single-writer mutex for its complete session and rejects any
  already-running pre-guard harness by PID before touching the mapping.
- Added `set-headless-body-presentation.ps1`.
- Added a runtime prepared-frame versus full-second-eye A/B and
  `set-full-second-eye-probe.ps1` for the enemy-shadow investigation.
- Built Release and synchronized the Lua/native binaries into the installed
  game. The installed range flags currently enable gameplay input, controller
  aim, body IK, and headless 3P presentation; the full-second-eye probe defaults
  disabled.
- Fixed two consecutive stereo-mod load failures caused by exceeding LuaJIT's
  200 file-scope-local ceiling and then initializing `presentation` members
  before the table's declaration. New state now lives on existing tables.
- Added `test-darktide-lua-source.ps1`. It fails closed on more than 198
  file-scope locals, state-table use before declaration, and Lua syntax errors
  (using `luac` when installed or cached `pnpm dlx luaparse` otherwise).
  Development sync, normal XR launch, and unattended preflight all invoke it
  before deployment or launch.
- Added `start-darktide-vr.ps1 -EnterPsykhanium`, which arms the existing
  guarded one-shot before game startup and refuses to arm against a running
  process. This preserves the known-safe character-select-to-range ordering.
- Updated `AGENTS.md` with the Lua chunk budget, mandatory validation, stereo
  readiness acceptance gate, and early Psykhanium sequencing rule.

## Validation

```powershell
pnpm dlx luaparse --quiet --file mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua
git diff --check
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build/windows-vs2022 --config Release
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build/windows-vs2022 -C Release --output-on-failure -E '^xr_(projection|theatre|stereo_sbs)_smoke$'
```

Result: Release build passed and 27/27 non-HMD tests passed. The complete
30-test invocation produced the same 27 passes; the three strict OpenXR smoke
tests failed closed because VirtualDesktopXR returned `hmd-unavailable`.
The focused native-capture test additionally publishes asymmetric left/right
stick values through the real shared mapping and verifies Lua offsets 16/17
and 34/35. Focused harness-help and synthetic-controller tests pass after the
OpenXR action-state counters were added.

The repaired live launch loaded the stereo mod, logged
`native_capture publishing`, attached shared eyes, and advanced
`shared_ready` from 1 through more than 2,000. Arming Psykhanium only after a
populated public hub reproduced the documented base-game teardown race:
`PlayerHuskLocomotionExtension` lost `parent_unit_id` and the title access-
violated during `wait_shooting_range`. This was not a Lua-load or XR failure;
the next range run must use the new pre-start switch.

The subsequent safe pre-start run entered `shooting_range` successfully. The
first root-visibility revision removed the 1P model, but its blanket 3P slot
override exposed one hidden curio attached near/tracking the right hand while
the body was absent. Source review identified the exact override violation and
the corrected stock-state-preserving implementation still exposed no skinned
body meshes. A maximal diagnostic then forced all 12 live 3P slot units visible,
disabled culling, emitted `lua_visible`, and kept the player-visibility snapshot
shown; only the rigid curio rendered. This proves raw unit visibility is not the
missing activation seam for skinned player presentation.

The decisive follow-up set the existing
`PlayerUnitFirstPersonExtension._force_third_person_mode` field. Darktide then
rendered the complete local skinned avatar, head, gear, backpack, and weapon in
the Psykhanium, with its normal behind-character camera. The log simultaneously
reported `force_engine_3p=true`, 12/12 3P slot units visible, and a passing
Psykhanium gate. Therefore the 3P assets and skeleton are valid in this mode;
the production task is to retain the native 3P presentation while independently
returning final camera ownership to the XR head pose.

Added a separate, normal-off hub diagnostic that forces
`_update_first_person_mode` to return first-person equipment/camera intent in
the hub. This is the inverse experiment for mapping presentation/camera
coupling and is controlled by `set-hub-first-person-diagnostic.ps1`. The live
inverse run passed: the populated hub rendered the genuine 1P arms and wielded
staff while stereo XR remained active. The source census found that
`wants_first_person_camera()` is consumed by `PlayerUnitCameraExtension`, while
the visual-loadout extension separately consumes `is_in_first_person_mode()`.
That apparently clean split failed in-headset: selecting the 1P camera tree
again suppressed every skinned local-player mesh, while the forcibly exposed
rigid curio remained visible. The revised seam therefore preserves the complete
native 3P camera tree and replaces only its final render origin with the live
first-person-component head anchor before XR tracking and eye offsets are
applied.

A deterministic follow-up swept that final camera origin from Darktide's stock
third-person position to the head and back every three seconds, while toggling
the head-related loadout slots at 1 Hz. The live result established both facts
independently: head hiding works, and the complete body progressively fades as
the camera approaches it. Source tracing identified the exact owner as
`FadeSystem`, not skinned-mesh submission, culling, attachment visibility, or
backface rendering. It calculates distance from the active player camera to
`j_spine` and applies breed thresholds of 0.3-0.9 m for humans and 0.5-1.2 m
for Ogryns. A live test corrected an initially reversed interpretation of
`set_min_fade`: the scalar is a lower bound on the fade effect (stealth raises
it), so one makes the body completely invisible. The working range path keeps
that scalar at the stock zero and supplies FadeSystem a distant observation
point without deregistering any units. The repeat sweep passed: the body stayed
opaque at every camera distance and the independent head hide/show cycle kept
working. The sweep was then removed, the head slots were fixed hidden, and the
camera origin was promoted to the live head anchor.

## Next live gates

1. Validate the corrected controller coordinate-space anchor and the fixed,
   weapon-independent anatomical hand transform. The previous build's exact
   solver was often clamping a requested wrist 19-22 cm beyond the reachable
   wrist because it added a recenter-relative controller pose to the live head
   rather than to the matching clean camera anchor. Logged index/middle/ring/
   pinky landmarks also established the stable rig-axis permutation used by
   the replacement hand transform. The rig is mirrored: left wrist-to-fingers
   and little-to-index use bone +R/+U, while the right uses -R/-U. The final
   transform therefore has an evidence-backed per-hand sign rather than a
   shared guessed correction.
2. Validate HMD-driven body heading, neutral third-person look animation,
   collision-aware physical head-follow, and the raised 5 cm eye anchor. The
   first-person tracking envelope is now zero horizontally so every physical
   room-scale displacement is transferred to the character while vertical HMD
   motion remains available for crouch.

The body-heading source is now explicitly independent of gameplay weapon aim.
Darktide's first-person orientation is intentionally authored from the right
controller for projectile direction, but that controller-derived yaw had leaked
back through the live game camera and made the torso appear to follow the right
arm while defeating the HMD/body dead zone. Render-body yaw now uses the
immutable scene heading plus physical HMD yaw; the reserved future thumbstick
turn accumulator will be composed at that same seam.

The live eye diagnostic found a 60.8 mm model IPD. Its eye midpoint was 74.1 mm
forward and 64.2 mm above Darktide's first-person component in the initial
pose. Per OpenXR 6DoF practice, these eye bones are now calibration landmarks,
not a live camera parent: their initial midpoint is retained in character-root
space and the runtime-tracked HMD pose supplies every physical eye movement.
This prevents facial/head animation from adding authored bob to the XR camera.
A synthetic neck pivot is deliberately not used for 6DoF because tracked HMD
translation already includes the real eye arc around the player's neck; such a
model is appropriate only as an orientation-only fallback.

The first hand-landmark report was measured after the IK write and therefore
partly validated its own output. The replacement diagnostic captures
wrist-to-middle, little-to-index, and palm directions before any IK write,
stores them in hand-bone-local space, and evaluates the final hand against that
immutable calibration. The XR harness also logs the active interaction profile
and the exact runtime grip-to-aim relative transform. No further guessed
180-degree hand correction should be applied before those values are read.

The clean pre-write capture established the mirrored rig bases precisely. The
left hand's wrist-to-fingers, little-to-index, and palm vectors are approximately
bone +R, +U, and +F; the right hand uses -R, -U, and +F. VirtualDesktopXR reports
the Oculus Touch interaction profile and an exact 60-degree grip-to-aim
rotation about X (`aim_from_grip_q ~= 0.5,0,0,0.866025`). The old mapping put
the anatomical finger direction 150 degrees from the aim ray. The replacement
constructs a source frame from the captured palm/across vectors and maps it to
the runtime grip frame. Live headset validation passed: both hand angles are
now correct and weapon-independent. The remaining hand issue is translational:
the OpenXR grip origin currently coincides with the model wrist node, putting
the physical controller at the wrist. The next revision should place the wrist
roughly 5 cm behind the grip along the measured palm-to-knuckle axis, then tune
that single anatomical distance from headset feedback.

The shoulder feedback and existing logs falsify a root-yaw-only explanation:
visible shoulder yaw can differ by roughly 40 degrees even when the authored
root closely matches HMD yaw, and it accumulates faster than the head before
snapping to neutral. The next build logs local, world, and root-relative yaw for
the hips/spine/neck/head/arm chain both before and after the post-animation IK
seam. This is intended to identify the exact animation node/constraint that
introduces the wrap before it is neutralized.

The spine trace then showed the animation system reauthoring both the player
root and upper torso before the post-animation seam. `j_spine2` was verified at
runtime to be a common ancestor of both arm chains. A guarded post-animation
correction now measures the actual shoulder plane, rotates `j_spine2` toward
the existing dead-zoned/smoothed body heading, and solves the independent arms
afterward. The first implementation used the wrong engine yaw sign and doubled
the residual, reproducing the reported accelerated shoulder turn and snap. The
corrected sign was validated live with an immediate measured shoulder residual
of `0.000 degrees`; the visible torso sat 12.95 degrees from the head, correctly
inside the configured 30-degree dead zone. Visual headset confirmation of the
large-turn catch-up remains pending.

Headset validation subsequently passed both hand rotation and shoulder
ownership. The shoulder plane remained exact, the dead zone behaved correctly,
and the replacement hand orientation remained consistent across both hands.
The OpenXR grip origin was visibly located at the wrist, so the production
mapping now places the skeletal wrist 5 cm behind the grip along the measured
palm-to-knuckle axis. That adjustment passed visually. A hybrid body-heading
policy now retains the 30-degree comfort dead zone for brief glances, converges
slowly toward a sustained stationary head heading after a 0.75-second dwell,
and aligns more promptly during artificial locomotion.

Thumbstick testing exposed authored jog/strafe animation moving the torso under
otherwise exact world-tracked wrists. Logs proved both wrist targets followed
the character root and reached their requested positions, ruling out a stale
controller anchor. The fix captures the neutral `j_spine2`-to-`j_neck` axis in
root space and restores that pitch/roll after animation, before the exact
shoulder and arm solves. Both torso and shoulder residuals remained effectively
zero (`0.000-0.020 degrees`) during locomotion, and headset validation passed.
The initial camera/body calibration moved the viewpoint 6 cm left and 12.5 cm
forward. The lateral result passed; the forward change overshot by about 5 cm,
so the retained calibration is 6 cm left and 7.5 cm forward. Final headset
validation passed this centering together with the hand, shoulder, torso and
locomotion corrections; this is the accepted embodiment baseline for the next
IK stage.

The next arm-IK revision resolves the positional two-bone solver's remaining
axial degree of freedom. Previously, the forearm retained an arbitrary animated
roll and the hand joint absorbed the complete tracked-controller roll. A first
attempt put the recovered axial angle directly on `j_leftforearm` and
`j_rightforearm`. Although its synthetic pose/error gates passed, headset
inspection rejected it: the complete lower arm became rigidly locked to wrist
rotation and all visible deformation moved to the elbow. That result is now a
recorded false path, not an accepted implementation.

The replacement follows the conventional layered arm solve documented by
Unity's Twist Correction constraint and Epic's Full Body IK guidance: retain a
stable constrained two-bone reach solve, recover the missing axial wrist angle
with a swing/twist-style projected-basis measurement, and distribute that twist
over the rig's purpose-built deformers rather than the elbow control joint. A
Darktide bundle extraction first identified exact candidate names. A fresh live
human-player inventory then established the actual runtime hierarchy and
placement: `j_leftforearmroll1/2` and `j_rightforearmroll1/2` are direct
children of their respective forearm joint, positioned at approximately 0.332
and 0.664 of the elbow-to-wrist segment. `j_leftarmroll1` and
`j_rightarmroll1` are corresponding upper-arm deformers and are not driven by
wrist roll.

The post-animation solve now leaves the elbow-starting forearm joint at its
shortest-arc reach orientation, maps the hand joint exactly to the tracked grip,
and applies 33.2%/66.4% of the recovered axial angle to the two authored lower-
arm roll bones. The fractions are measured from the live rig positions rather
than hardcoded. The final extractor is a quaternion swing/twist decomposition;
it no longer switches between projected palm/across bases. It carries a true
signed-angle branch crossing only while raw per-frame motion remains physically
plausible, snaps to the new raw pose after an impossible >90-degree frame jump,
and clamps distributed forearm pronation/supination to +/-100 degrees. The exact
hand joint absorbs any excess. This intentionally follows the user's constraint
that a physical hand cannot execute arbitrary multi-turn rotation.

The synthetic body path supplies a complete -180 to +180 degree controller-roll
sweep through both upside-down endpoints. An intermediate temporal-unwrapping
build was correctly rejected when the diagnostic phase reset accumulated 400-
800 degree twists despite exact hand poses. The runtime validator now fails any
sample outside the anatomical limit, preventing that false success from
recurring. The corrected clean run authored both twist bones on both arms with
stable measured fractions (`0.332/0.664` left and `0.333/0.665` right); observed
twist stayed within the +/-100-degree limit while the deliberately absurd
synthetic target continued beyond it. Maximum wrist and hand-angle error remain
independent acceptance gates. The fresh XR harness must reach nonzero
`shared_ready`, and any mod script/Lua, DXGI, device-removed, or device-hung
failure rejects the run.

The final 120-second pass met those gates. The harness submitted 10,210 frames,
received 3,948 fresh shared pairs, reported zero reused frames and zero pair-
pose mismatches, and ended with `result=pass`. The runtime validator accepted
63 twist samples: every sample wrote both deformers on both arms, roll remained
inside +/-100 degrees, the fractions remained `0.332/0.664` and
`0.333/0.665`, maximum solved-wrist readback residual was 0.000384 m during a
rapid synthetic locomotion/root-update transition, and maximum hand-angle error
was 0.001687 rad. Ordinary frames returned immediately to micrometre-scale
readback. The validator allows at most 1 mm to cover this scheduling boundary
while still failing visible drift.

Validation commands for the staged arm revision:

```powershell
tools\stereo\test-darktide-lua-source.ps1
cmake --build build/windows-vs2022 --config Release --target darktidevr-synthetic-controller-tests darktidevr-xr-harness
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure -R '^synthetic_controller_path$'
tools\stereo\request-body-rig-inventory.ps1
tools\stereo\start-darktide-vr.ps1 -EnterPsykhanium -SyntheticControllerPath -SyntheticBodyPath -SyntheticGameplayInput -DurationSeconds 120
tools\stereo\test-body-twist-runtime.ps1 -MinimumSamples 20
git diff --check
```

### Physical crouch body-follow checkpoint

Physical crouch is now a render-body IK operation rather than locomotion. The
OpenXR bridge preserves up to 1.2 m of vertical head translation while keeping
the production horizontal camera envelope at zero. Lua reads the exact tracked
vertical delta, leaves the gameplay root/capsule untouched, and lowers only
`j_hips`. Both authored leg chains are then solved back to their pre-write ankle
positions and foot rotations, so the feet remain planted instead of descending
through the floor. Head and hand targets remain exact and are applied after the
pelvis write.

The provisional comfort calibration follows all but 5 cm of downward head
travel and caps pelvis descent at 60 cm. The residual permits small natural
neck/spine compression while preventing the camera from entering a stationary
torso. Ogryn uses the existing character-scale ratio. The user confirmed that
the legs bend and asked to retain this pass; the deepest crouch looks somewhat
exaggerated for the current smallest human body, so the cap/follow curve must
eventually derive from the planned body-size calibration rather than remain a
universal constant.

The harness adds `--synthetic-crouch-path` / `-SyntheticCrouchPath`, a smooth
standing-to-65-cm-crouch cycle independent of controller and locomotion paths.
The final 120-second Psykhanium run submitted 9,905 frames, received 4,471 fresh
shared pairs, reused zero frames, reported zero pair-pose mismatches, and ended
with `result=pass`. Runtime validation accepted 66 samples, reached 0.5963 m of
pelvis follow, kept maximum planted-foot error to 0.000726 m, and found no mod
script, Lua, DXGI, or device fault. Source guard remained at 198/198 file-scope
locals and both `core_math` and `synthetic_head_path` tests passed.

Validation commands for the physical-crouch checkpoint:

```powershell
tools\stereo\test-darktide-lua-source.ps1
cmake --build build/windows-vs2022 --config Release --target darktidevr-xr-harness darktidevr-synthetic-head-tests
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure -R 'synthetic_head_path|core_math'
tools\stereo\start-darktide-vr.ps1 -EnterPsykhanium -SyntheticControllerPath -SyntheticBodyPath -SyntheticGameplayInput -SyntheticCrouchPath -DurationSeconds 120
tools\stereo\test-body-crouch-runtime.ps1
git diff --check
```

Implementation references:

- Unity Animation Rigging, Twist Correction constraint:
  <https://docs.unity3d.com/ja/Packages/com.unity.animation.rigging@1.2/manual/constraints/TwistCorrection.html>
- Epic Games, Full-Body IK controls, preferred angles, stiffness and limits:
  <https://dev.epicgames.com/documentation/unreal-engine/control-rig-full-body-ik-in-unreal-engine?lang=en-US>
- CDC normal joint range-of-motion reference values for forearm pronation and
  supination:
  <https://archive.cdc.gov/www_cdc_gov/ncbddd/jointrom/index.html>
- Autodesk Stingray Unit Lua API used for runtime scene-graph verification:
  <https://help.autodesk.com/cloudhelp/2021/DEU/Max-Interactive-Help/lua_ref/obj_stingray_Unit.html>

The two newest Quest recordings were pulled without deleting the device copies
to `artifacts/phase1/quest-recordings-20260829`. The 12:02:17 capture is a
69.434-second 1920x1080 HEVC stream at 120 fps; the 12:04:24 capture is a
38.872-second 1920x1080 HEVC stream at 30 fps. Their SHA-256 hashes are
`094E96502F6EE6D55F2FECB8E778E93C0B512873C8C95BDD4157E12CB39640E1`
and `108B4C54192F333609B21AA776A34F9C94FFD3712859BDCFAC432E749CFF8F6F`.

### Engine-world menu renderer investigation

The stock SystemView UI can be redirected natively into a complete transparent
`menu_surface`; a 2496x2688 readback with crop `0,642,2496x1404` contained the
Escape menu. The older Lua resource-renderer replay remains rejected because it
does not execute all specialized SystemView draws. The intended engine-world
destination is the named `darktidevr_menu_ui` texture (runtime hash
`0xaf0f1409769cf92b`), presented by the existing two-metre, 16:9 world quad.

An external-queue copy into that texture was conclusively rejected. The first
menu open produced a black panel because Stingray cleared the destination after
the Present-time copy. Opening the menu a second time recreated the target while
the external path still retained/crossed its lifetime and caused GPU hang crash
`8504d592-1910-4c57-85f3-17b9f4fdddc4`. That experiment was immediately
reverted and the staged body-IK checkpoint was redeployed unchanged.

The next attempted visual gate targeted Stingray's own graphics command list,
immediately before an assumed named-destination publication barrier. It was
safe under repeated menu opens but never executed: the first hub panel remained
black and the native log contained no inline-copy event. A follow-up census with
copying disabled proved that `darktidevr_menu_ui` emits neither a matching
legacy nor enhanced D3D12 barrier in the active menu phase. The earlier
interpretation of its transition boundary must not be reused.

A subsequent draw-table census attempted to locate the exact draw that samples
the named texture, but the diagnostic dereferenced raw `DescriptorInfo`
resource pointers which are not lifetime-owning. It crashed at menu open and
produced dump/session `9fc3d701-4365-4873-81be-9d0e4fdc80eb`. No target copy
ran in that build. The unsafe scanner was removed and the staged known-safe
renderer, Lua and harness checkpoint was rebuilt and redeployed. Future draw
identification must propagate an immutable `named_menu_ui` tag through
descriptor creation/copy metadata while the resource is known-live; it must
never query COM through a cached raw descriptor pointer.

The user separately observed that the first black-panel run reduced tracking
from 6DoF to 3DoF, and that at least one highlighted UI primitive still leaked
to the desktop eye mirror. Those remain independent defects: menu-state camera
translation must be preserved, and the native UI shader classification is not
complete until the stock desktop overlay is absent.

Pre-live validation used for the rejected inline gate:

```powershell
tools\stereo\test-darktide-lua-source.ps1
git diff --check
cmake --build build\windows-vs2022 --config Release --target darktidevr_native_capture darktidevr-xr-harness
ctest --test-dir build\windows-vs2022 -C Release --output-on-failure
```

Result: Lua source passed at 198/198 file-scope locals and all 30 CTest tests
passed, but live evidence rejected both experimental diagnostics. This is why
runtime gates remain mandatory even when the unit suite is green.

The ownership-safe follow-up completed the descriptor-index question. The
Lua-created 2496x1404 RGBA8 target was assigned bindless descriptor index
46527, while the full-eye menu draws sampled different live indices (including
10539, 27003, 3948 and 4449). No full-eye draw sampled 46527 during the bounded
menu census. The named target is therefore not consumed by the production eye
render and is not a viable route for menu content. The census hooks and their
per-draw overhead were removed after recording this result.

The working native additive menu surface continues publishing complete menu
frames (`MENU_DIRECT_RENDER` ready values advanced continuously). The desktop
flicker was a separate swapchain ownership problem: stock fullscreen UI and the
sequential stereo mirror alternated on the same window. Native capture now
snapshots the completed left eye into a dedicated resource once per pair and
copies that stable eye to the swapchain immediately before Present. A live hub
run showed a stable one-eye mirror both before and during the open system menu,
with no `DESKTOP_EYE_MIRROR` error result, while menu publication continued.
Headset validation is still required to confirm the additive menu remains
visible and interactive and that the removed Lua panel eliminates the black
rectangle.

A tempting one-copy optimization that read the live shared left-eye surface at
Present was rejected live: successive desktop samples alternated between the
fullscreen menu and world. The capture mailbox can be updated from another
submission context before Present reads it, so same-queue ordering cannot be
assumed. Keep the dedicated completed-pair snapshot until an explicitly fenced,
multi-buffered replacement proves equivalent; correctness currently costs one
additional eye-sized allocation and copy per pair.

`start-darktide-vr.ps1 -AutoEnterHub` now starts an independent, state-gated
helper. It waits for the fresh console log's title state before sending Space,
then requires both the character-select stereo target and presentation-open
messages before sending Enter. It never moves the mouse and exits after one
pass. A full authenticated launcher run reached the hub unattended and logged
`presentation_blocked reason=not_first_person_training mode=hub` at 05:21:43.

Validation for the accepted mirror/automation revision:

```powershell
tools\stereo\test-darktide-lua-source.ps1
cmake --build build\windows-vs2022 --config Release --target darktidevr_native_capture
ctest --test-dir build\windows-vs2022 -C Release -R 'native_capture_hooks|shared_eye_surfaces|presentation_state' --output-on-failure
tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release
tools\stereo\start-darktide-vr.ps1 -AutoEnterHub
git diff --check
```

Result: Lua source passed at 198/198 locals, all three focused native tests
passed, the fresh XR session reached nonzero `shared_ready`, and the helper
reached the hub without manual splash or character-select input.

### Crafting-view renderer state diff

The guarded `crafting_view` can now be opened and closed unattended from a
clean hub. Separate focused traces were captured for the idle hub and active
crafting presentation rather than reusing the eye-A/B phase counter (the
global 250,000-record cap made the earlier phase-B half empty). The reusable
`tools/stereo/analyze-focused-state-diff.py` normalizes draw counts by captured
eye-frame and ranks application-state enrichment. The local evidence is under
`artifacts/phase1/vendor-crafting-trace-20260829` and is intentionally not a
production dependency.

Two active-only signatures initially looked like a compact crafting UI seam:

- VS `15643064314087379227`, PS `12642582357042194823`, six triangles;
- VS `16527730207467110505`, PS `16716951665136862850`, two triangles.

Both were blended, depth-disabled triangle-list draws on the full 2496x2688
surface and occurred once per crafting presentation frame. A controlled live
redirect disproved the interpretation: the shared-menu readback was opaque
black (`rgb_nonzero=0`, `alpha_nonzero=6709248`) and the run later ended in a
GPU hang. The two signatures are therefore backdrop/composition dependencies,
not a self-contained interactive widget batch. They were removed immediately;
the production seven-pair Escape-menu classifier remains unchanged. Do not add
the crafting pairs back without first identifying their upstream resource and
the complete command-list dependency chain.

This narrows the vendor work: shader presence alone is insufficient because
opening crafting replaces a substantial UI presentation world. The next trace
must follow render-target production and sampling order for the completed
interactive widget layer, then capture at that resource boundary. It must not
redirect isolated draws into a resource with different lifetime/state.

Validation before the rejected live gate:

```powershell
tools\stereo\test-darktide-lua-source.ps1
cmake --build build\windows-vs2022 --config Release --target darktidevr_native_capture
ctest --test-dir build\windows-vs2022 -C Release --output-on-failure
```

Lua remained at 198/198 locals and all 30 tests passed. The live GPU result,
not the unit suite, rejected the candidate.

### Crafting widget batch recovered

The two crafting-only draws were subsequently separated by renderer evidence
rather than tested as an undifferentiated pair. VS
`15643064314087379227` / PS `12642582357042194823` is a 180-vertex draw with
the same 76-byte GUI vertex layout as the proven stock menu widget renderer.
VS `16527730207467110505` / PS `16716951665136862850` is only 12 vertices
with the separate 48-byte compositor layout. The earlier black result came
from redirecting both layers together.

A second attempted classifier that redirected every blended, depth-free,
full-target draw while a vendor view was active was rejected immediately. It
crossed a resource-ownership boundary and caused a D3D12 page-fault/device-hung
crash, dump/session `39713a0d-e1d6-488e-9331-f5ff810bea29`. That build was
reverted and must not be restored.

Redirecting only the 180-vertex GUI-layout batch was stable across two complete
crafting-view open/close cycles. On-demand shared-menu readback contained the
full transparent Hadron interaction layer: title, description, both action
buttons, currency/status text and icons. Pixel diagnostics were repeatable
across reopen (`rgb_nonzero=294996`, then `294981`; `alpha_nonzero=510588`,
then `510610`). The desktop mirror correctly showed only the independent 3D
Hadron presentation after the UI batch moved to the additive menu surface.
The 12-vertex compositor draw remains on the game's target and the XR eye-pair
transport stayed live with zero pair-pose mismatches.

This is an accepted unattended visual gate, not final shop acceptance. A worn
test still needs to verify panel placement, stereo/6DoF continuity and XR
pointer interaction, followed by a submenu/dropdown readback. The production
classifier remains explicit and narrowly guarded by the exact shader pair,
180 vertices and one instance.

3. Verify WASD and left-thumbstick locomotion with VR input enabled.
4. At a repeatable enemy-shadow boundary, compare the default prepared-frame
   second eye with `darktidevr_full_second_eye.flag` enabled. Record whether
   the eye-specific shadow defect changes and the frame-time cost.

The later IK stages still include a two-pose body-size calibration (T-pose,
then hands at the player's sides). It must replace the accepted physical-crouch
pass's provisional human/Ogryn scale, pelvis cap and follow curve with values
derived from the selected avatar and measured player dimensions.

No Mac-only validation applies to this Windows PCVR work. The Quest is reachable
over ADB, awake, and had the temporary proximity override reapplied. Virtual
Desktop Streamer did not expose a usable Windows window or HMD during this
session, so no headset gate was claimed.

### Hub first-person presentation consolidation

The hub now deliberately uses the same presentation toolset as the
Psykhanium instead of maintaining a separate third-person exception. The
headless-body gate also selects the hub's first-person camera/equipment policy;
the local third-person skinned body remains visible with its head slots hidden,
and the established controller arm IK, torso heading, crouch/leg IK, and
controller input adapter are admitted in `hub`, `shooting_range`, and
`training_grounds` through one shared mode predicate. The old independent
`darktidevr_force_hub_first_person.flag` is no longer authoritative.

Live inventory proved the hub selects steering move method
`script_driven_hub` and calls `_update_script_driven_hub_movement`, while the
Psykhanium uses `_update_script_driven_movement`. The unified hub path now
selects ordinary `script_driven` locomotion at the shared dispatcher and also
wraps the hub sibling as a safe fallback. Both feed the same one-fixed-tick
physical body delta through `velocity_wanted`, retain the stock mover and
collision path, and restore the original stick velocity afterward. A clean
hub run emitted `body_follow mode=enabled` and 52 non-retained writes as the
headset crossed the sliding envelope.

The visible avatar previously stayed at the collision root throughout the
bounded 25 cm camera lean. The pelvis/leg pass now applies the bounded X/Z head
translation to the animated hips, alongside physical crouch, then solves both
legs back to their pre-write foot transforms. Thus the rendered torso follows
the viewer inside the envelope while only overflow moves the gameplay capsule.

An attempted shortcut that invoked `DefaultPlayerOrientation.pre_update` on a
`HubPlayerOrientation` object was rejected: the two classes do not share the
same initialized sensitivity state. It produced a nil
`sensitivity_modifier` script error and was removed. Future orientation
selection must occur at the owning first-person extension, which already owns
both initialized objects; never cross-call the class method on the wrong
instance.

The loading-screen flicker had a separate confirmed cause. The Present hook
was injecting the last completed eye mirror during presentation mode 2, while
the game simultaneously drew the flat loading view. Desktop eye-mirror
injection is now suppressed for `flat_loading_or_cinematic`; the next worn run
confirmed the hub loading flicker was gone. An intermittent variable-height
flicker remains in the desktop mirror during the live hub, while the headset
view is unaffected.

The exact 180-vertex item-picker candidate was also rejected by a worn Hadron
test. It showed a zoomed Hadron background asymmetrically in the eyes while
the landing panel remained stable. Item-picker direct capture is therefore
forced off again; the saved focused trace/readback remains useful evidence,
but that batch is not the complete submenu foreground.

Validation:

```powershell
tools\stereo\test-darktide-lua-source.ps1
cmake --build --preset windows-vs2022-release --parallel
ctest --test-dir build\windows-vs2022 -C Release --output-on-failure
git diff --check
tools\stereo\start-darktide-vr.ps1 -AutoEnterHub -EnableMenuTestControls
```

Lua remains at 198/198 file-scope locals, all 30 tests pass, fresh XR runs
reported nonzero `shared_ready`, and the clean hub log proves headless body,
IK, controller input, and collision-aware body follow are active together.

### Late-session hub and desktop-mirror evidence

The hub locomotion dispatcher substitution did not produce gameplay movement
or locomotion animation: the user still observed stock hub acceleration,
alternating hand poses while moving, and a sliding third-person body. It was
removed rather than extended with more hub-state emulation. A clean pre-spawn
test then selected the production `walking` character state. That test reached
the real walking state and proved most required hub-unit extensions exist, but
failed deterministically in `player_unit_peeking.lua:49` because the social-hub
unit has no `ledge_finder_extension`. The starting-state override was removed.
A future gameplay locomotion state for the hub must explicitly omit unsupported
combat traversal/peeking dependencies instead of selecting stock `walking` or
piecemeal driving `hub_jog`.

The remaining desktop flicker is now characterized by a user screenshot rather
than whole-frame descriptions: roughly the bottom fifth of the live mirror was
from a different eye/frame, separated by one stable horizontal boundary. This
is a partial backbuffer update (GPU ordering/Present tear), not the previously
fixed stale splash frame and not evidence that the two eyes are separate game
simulation ticks.

The mirror source is populated on the eye-capture queue and is now guarded by
the shared-eye ready fence. A second ordering flaw remained: the Present hook
submitted its backbuffer copy on the first observed direct queue, although a
D3D12 process can own multiple direct queues. The native producer now learns
the authoritative swapchain queue from the command list that transitions a
known swapchain buffer to `PRESENT`, logs `SWAPCHAIN_PRESENT_QUEUE`, and uses
that queue only for mirror backbuffer injection. This ensures the mirror copy
is ordered immediately before DXGI Present while leaving eye capture and menu
publication on their existing render queue. Focused native transport tests
pass; a motion test is still required to confirm that the horizontal tear is
gone.

The first hub compatibility variant now retains stock gameplay walking without
copying the state. `PlayerUnitPeeking.fixed_update` and
`LedgeVaulting.can_enter` return unavailable only when their optional ledge
finder argument is nil, and the hub starts in `walking` again. A clean launch
logged `starting_state=walking source=hub_first_person_no_ledge`, reached the
hub, published advancing stereo pairs, and produced no further script errors
while idle. Worn movement and animation validation remains pending.

The user also identified a full-frame replay of the old character-select scene
and dated its introduction to the crafting-menu work. Presentation logs stayed
continuously in stereo, ruling out a Lua mode transition. The direct native
menu shader redirect had defaulted enabled globally; because its retained UI
shaders can also occur outside menus, it is now disabled by default and armed
only while Lua has positively classified a mode 3/4 interactive menu. Ordinary
stereo and flat loading explicitly disarm it.

One diagnostic build additionally waits for the mirror-copy D3D12 fence before
calling DXGI Present. This intentionally reduced hub fresh-pair rate to roughly
36--39 FPS, but makes the next visual gate decisive. The synchronous wait is a
diagnostic only and must not remain in the performance path.

The worn diagnostic run showed no desktop flicker at all. The stronger causal
candidate is the newly isolated direct-menu capture path, because it had been
able to retain and replay a stale UI target during ordinary stereo. The CPU
fence wait has therefore been removed again while the menu redirect remains
default-off and presentation-gated. The current run is the controlled
asynchronous-mirror check; do not re-enable global direct-menu capture when
returning to shops.

The same run resolved the apparent controller-loss locomotion switch. Runtime
instrumentation proved that `starting_character_state_name` returned
`walking`, but the local state machine was already in `hub_jog` before the
first two-second input sample. A later tracking loss changed grip flags from
15 to 3 while thumbstick publication continued; it did not cause the state
transition. The hub is server-authoritative and its replicated correction was
overwriting the local unit-template start choice.

The local hub correction boundary now translates only the server's benign
`hub_jog` state to `walking` for the local first-person player. Interaction,
disabled, and all other authoritative states retain their original names. A
fresh run logged `server_correction mapped=hub_jog->walking` and then reported
the live state as `walking` continuously. Grip IK also retains the last fully
tracked wrist pose while a controller is temporarily merely valid/untracked,
so stock arm animation cannot reclaim that limb during a tracking dropout;
the first newly tracked sample immediately replaces the held pose. Tracking
transitions and the real character-state name are now included in runtime
diagnostics for the next worn loss/reacquisition gate.

The right controller was also proven to be authoring Darktide's gameplay
orientation. That made ordinary `walking` feel hand-relative even though the
character state never left `walking`: rolling or yawing the aiming hand changed
the same orientation frame that locomotion reads. Until independent
weapon-relative aiming is implemented, the enabled aim seam now authors yaw and
pitch from OpenXR's centre-head (cyclopean) pose and forces roll to zero. This
gives the implicit screen-centre reticle one binocular centre ray rather than
choosing either eye or hand, and leaves controller poses exclusively available
to arm IK. A future snap/smooth-turn accumulator must rotate that cyclopean ray
without coupling it back to either controller.

The remaining small hand flicker also has a concrete timing candidate. Arm IK
runs at the post-animation first-person seam, but its tracking-to-world anchor
was previously refreshed later by the stereo camera update. During locomotion,
the targets therefore used the prior avatar-root transform. The IK pass now
reconstructs the calibrated eye/body anchor from the current avatar root before
solving either arm. A clean worn run still needs to verify both the cyclopean
aim policy and this same-frame anchor refresh.

### Crafting submenu renderer ownership

The prior Hadron symptom is now explained by lifecycle and source evidence.
`CraftingView.go_to_crafting_view` passes its `_ui_renderer` to every child via
the view context, and `BaseView._create_ui_renderer` marks that renderer as
external on the child. The earlier hook disabled landing-page capture whenever
a `crafting_*` child opened, so XR correctly continued displaying the last
published landing texture while the uncaptured live child rendered only to the
desktop. The apparent top-level/submenu flicker was stale publication, not two
competing XR menu cameras.

The next build scopes native additive capture by that shared renderer during a
crafting child lifetime. Every parent, child, and element `UIRenderer` pass on
the inherited renderer is included; Hadron's independent `UIWorldSpawner`
background is excluded. Nested passes use balanced native scope depth, and the
close log reports the exact number of redirected draws. The default-off global
menu gate now also guards scoped and legacy item-picker paths, preventing a
leaked scope or rejected shader candidate from capturing outside an explicitly
active menu. Crafting children also inherit the landing view's NPC-relative
mode-3 panel pose; they no longer reclassify as a generic head-relative mode-4
menu and move the board during a tab transition. The rejected item-picker
shader-pair branch and its Lua/FFI controls were removed entirely; it is no
longer a dormant alternative to the renderer-owned path. Lua remains at
198/198 file-scope locals; the native target builds
and the focused native transport tests pass. This path is source-supported but
still requires a live landing-to-submenu readback and worn interaction gate.

The first live landing-to-submenu gate rejected that native renderer scope.
The scripted transition successfully opened
`crafting_mechanicus_modify_view` and attached to
`CraftingView_ui_renderer`, proving the ownership inference, but the user saw
the left eye and mirror alternate between eye/mono content while the right eye
alternated between a zoomed child view and the stereo world. Darktide then
crashed about ten seconds after scope activation. The top-level Hadron panel
remained correctly anchored and stereo throughout. The scope therefore found
the intended child draws but redirected them at an unsafe command-list seam;
it is not a viable presentation path.

The replacement splits at view construction instead of substituting D3D12
render targets per draw. `BaseView._create_ui_renderer` now detects a crafting
child whose context inherits the parent renderer and replaces that dependency
with a dedicated resource renderer before the child creates retained widgets.
While the child is active, native direct-menu capture is disabled and the
resource is drawn once as normal world geometry in both stereo passes. All
shops now use the same fixed, head-initialized 16:9 board: 2 m wide, 1.125 m
high and placed 2 m forward at open time. NPC-relative placement is deliberately
unused because shops can be opened remotely. The bridge returns to ordinary
stereo mode while this world-owned board is active, so the stale parent mailbox
cannot be composited over it. This construction-time route passes the
198-local Lua source gate but still needs a fresh live landing-to-submenu test.

The post-animation body-anchor refresh removed the visible hand flicker during
stick locomotion. A remaining deterministic error was isolated: changing stick
direction translated both hands to a repeatable set point in that direction,
and circular stick input traced a fixed-radius circle with the hands. The final
diagnosis and correction are recorded below.
# Deferred hybrid character-select presentation

The reliable baseline now presents character select as an interactive flat
16:9 board in a void. A later enhancement may retain the character-select 3D
background in stereo *inside the same board* while keeping its UI flat. The
intended composition is two eye-specific background quads on one fixed panel,
plus one binocular UI-only quad at the same apparent plane. The remaining hard
part is obtaining a clean transparent `MainMenuView` UI texture without its 3D
background. Keep the all-flat mode as a fail-safe while developing that hybrid;
do not revive the old full-screen character-select stereo compositor as the
menu path.

The interactive flat presentation is protocol mode 5. It releases immersive
projection like loading mode 2 but retains controller pointer, click, back, and
scroll handling. Pointer coordinates for mode 5 are crop-local (currently
1280x720), rather than normalized against the 2112x2304 eye resource; mixing
those spaces produced the measured bottom-right cursor position of roughly 61%
across and 31% down.

## Locomotion-relative hand-circle diagnosis

The hand displacement was not retained thumbstick input. Live telemetry
returned exactly to zero after release, while the user observed a repeatable
fixed-radius offset selected by travel direction.

The cause was ordering inside the post-animation body pass. Darktide's authored
root still faced the locomotion direction when `body_stable_eye_anchor()` was
sampled for the controller-to-world transform. The VR body-heading correction
then restored the root to HMD heading, and the later stereo camera sampled that
final root. Because the calibrated eye is horizontally offset from the skeleton
root, the pre-heading and post-heading samples lie on a circle around that root.
The camera and wrist targets therefore used different origins even though the
arm solver itself had micrometre-scale readback error.

`apply_body_ik()` now applies the final body heading before refreshing the
shared body anchor. A clean hub run loaded stereo with nonzero `shared_ready`,
accepted genuine Quest stick input with no synthetic path enabled, and kept arm
solver readback below 0.028 mm during the captured sweep. Visual headset
acceptance remains the final gate. `test-darktide-lua-source.ps1` now also fails
closed if this heading-before-anchor ordering is reversed.

Validation:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
ctest --test-dir build\windows-vs2022 -C Release --output-on-failure -R 'core_math|synthetic_head_path|synthetic_controller_path'
git diff --check
```

## End-of-session embodiment calibration

The hub now leaves `hub_jog` authoritative. The accepted presentation applies
the final HMD-relative visual-body heading before refreshing the calibrated
eye/body anchor, so controller targets, the camera and the avatar root all use
the same pose. Worn validation passed head position, hand stability, head-look
steering and normal hub motion after the earlier local `hub_jog -> walking`
state substitution was removed. Native horizontal head translation is again a
1.2 m moving envelope rather than the accidentally zeroed diagnostic range.

Two Quest reference screenshots were pulled without deleting the originals:

- `artifacts/phase1/quest-screenshots-20260829/VirtualDesktop.Android-20260829-214248.jpg`
- `artifacts/phase1/quest-screenshots-20260829/VirtualDesktop.Android-20260829-214250.jpg`

The controller overlay established a final translational wrist correction in
the body frame: 3 cm laterally away from the body centreline, 4 cm backward and
1 cm down. This correction is applied after the existing 5 cm anatomical
grip-to-wrist displacement and is shared by the reach estimator and final arm
solver, preventing those two stages from targeting different wrist positions.

The first shoulder-reach implementation independently translated clavicles.
It supplied extra reach but did not visibly rotate the shoulder girdle. The
second implementation converted left/right reach asymmetry into a measured
`j_spine2` shoulder-line rotation, but incorrectly translated both clavicles by
the entire shared request. This gave two fully extended arms more reach than a
single arm and was rejected in-headset.

The retained implementation treats the arms as independent opposing requests:
a far-forward left hand asks for left-shoulder-forward yaw and a far-forward
right hand asks for right-shoulder-forward yaw. Equal requests cancel to a
square shoulder line; a shoulder starting behind its tracked hand produces the
larger request and can rotate forward toward neutral. Each clavicle retains a
small independent protraction capped at 2 cm. This final revision passes the
Lua source/syntax guard but was deliberately not relaunched after the user
ended the session, so its physical behaviour is the first worn gate tomorrow.

Machine-local launcher configuration now has `SendCrashReports = false` in
`%APPDATA%\Fatshark\Darktide\launcher.config`. Installed-launcher IL inspection
showed this suppresses creation of the separate crash-report UI; Darktide's
console logs and dump files remain game-owned and available. This setting is
not repository state.

## Tomorrow's first checkpoints

1. Worn-test the independent shoulder solver in the hub: compare neutral,
   single-left, single-right and equal-bilateral full reach. A unilateral reach
   must advance that shoulder and retract the other; equal bilateral reach must
   stay square; retracting one arm must let the other gain yaw-derived reach.
2. Confirm the 3 cm out / 4 cm back / 1 cm down wrist calibration on both hands
   and across at least two weapon/default hand poses. Adjust one measured body-
   frame offset only if the residual is consistent.
3. Add bounded shoulder telemetry only if the visual gate fails: record each
   raw/smoothed reach request, resulting signed girdle yaw, per-clavicle travel
   and post-solve wrist error. Do not tune signs or limits without that trace.
4. Resume the character-select/shop flat-interactive path. Character select and
   Create Operative pass; shop construction still crashes or loses renderer
   ownership. Keep the desktop strictly an eye mirror and avoid the rejected
   per-draw crafting-renderer redirection.
5. Continue the per-eye LOD, light-edge culling and asymmetric enemy-shadow
   investigation after the embodiment gate. Preserve the one-primary-prep plus
   full second-eye A/B rather than conflating all three defects.

End-of-session validation:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build --preset windows-vs2022-release --parallel
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release --output-on-failure -E '^xr_(projection|theatre|stereo_sbs)_smoke$'
git diff --check
```

Result: Lua syntax and source invariants pass at 198/198 file-scope locals, the
Release build passes, and all 27 software/non-HMD tests pass. The three strict
OpenXR smoke tests were excluded because they require the live headset runtime.
The final independent shoulder revision still requires the worn gate above.
