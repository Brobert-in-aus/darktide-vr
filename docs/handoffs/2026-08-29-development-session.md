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

The two newest Quest recordings were pulled without deleting the device copies
to `artifacts/phase1/quest-recordings-20260829`. The 12:02:17 capture is a
69.434-second 1920x1080 HEVC stream at 120 fps; the 12:04:24 capture is a
38.872-second 1920x1080 HEVC stream at 30 fps. Their SHA-256 hashes are
`094E96502F6EE6D55F2FECB8E778E93C0B512873C8C95BDD4157E12CB39640E1`
and `108B4C54192F333609B21AA776A34F9C94FFD3712859BDCFAC432E749CFF8F6F`.
3. Verify WASD and left-thumbstick locomotion with VR input enabled.
4. At a repeatable enemy-shadow boundary, compare the default prepared-frame
   second eye with `darktidevr_full_second_eye.flag` enabled. Record whether
   the eye-specific shadow defect changes and the frame-time cost.

Later IK stages explicitly include a two-pose body-size calibration (T-pose,
then hands at the player's sides) and physical-crouch body IK. The latter must
lower the pelvis/body as tracked eye height drops so the camera does not descend
into a stationary torso; it is separate from horizontal room-scale locomotion.

No Mac-only validation applies to this Windows PCVR work. The Quest is reachable
over ADB, awake, and had the temporary proximity override reapplied. Virtual
Desktop Streamer did not expose a usable Windows window or HMD during this
session, so no headset gate was claimed.
