# Wrist roll and stock melee angle

Worn follow-up: the user reports "Melee aim fixed" after the 09:44 UTC restart.
The wrist-twist aiming issue is accepted. Server damage and the separate
feedback/menu appearance are not implied by that observation.

## Live deployment, 09:44 UTC

After the user authorized restart, the seven changed focused Lua files were
installed in a backed-up transaction. Ready mode passed (600 rendered XR frames);
the installed LuaJIT gate passed all 50 chunks. Accepted capture/bootstrap/viewer
hashes remained unchanged. Fresh native stereo initialization occurred at
09:43:13, Psykhanium entry passed at 09:44:32, and Light was saved at 09:44:33.
Melee preview is on. Both startup flags were restored after confirmation.

The harness advanced to shared_ready=747 with an observed interval of 51.19
fresh plus 51.19 generated pairs per second, zero fallback and pose mismatches.
Melee input_roll_deg changes and matching first-light ActionSweep starts were
observed. No feedback_error, assist fallback, input_fallback, preview_error or
mod ERROR/WARNING appeared in the inspected launch window. These are startup
and runtime checks; the new wrist/HUD/menu visuals still need worn acceptance.
The user's pre-restart headset verification referred to the previous build.

Local receipts: artifacts/unattended/wrist-feedback-ready-20260908.json,
wrist-feedback-deployment-20260908.json, wrist-feedback-session-20260908.log,
wrist-feedback-startup-restore-receipt-20260908.json and
wrist-feedback-native-verified-20260908.json. The game remains running for tests.

## Candidate design and offline record

The user reports that twisting a forward-pointing controller makes the guide
and crosshair jump/disappear. This candidate separates forward-vector yaw/pitch
from wrist roll. It retains the existing yaw at the vertical pole and the stock
pitch limits. It has not yet been installed or visually accepted; the exact
live disappearance cause remains unconfirmed.

With a melee weapon, wrist roll selects the nearest 45-degree rotation of the
weapon's normal first-swing plane. A three-degree boundary margin prevents
sector chatter. The selected roll stays fixed while a weapon action is running,
including windup and a continuous combo, then updates again at idle. Pointing
can still move during a swing under the existing stock rules. Ranged weapons
and staves keep zero input roll. Weapon/player/tracking-generation changes
reset selection. Existing forced-look/sticky orientation ownership takes
priority and can temporarily suspend VR input authoring.

This rotates the stock action through its existing input roll field; it does
not choose a different combo action or change attack timing, damage or origin.
The preview still samples the actual action instance using the simulated
first-person rotation. Physical melee remains paused. Current policy admits
the range and locally authoritative missions, not remote online missions.

Cached stock-source audit: HumanInputHandler sends every input-cache column in
rpc_player_input_array; AuthoritativePlayerInputHandler receives the same columns
and returns yaw/pitch/roll. PlayerUnitFirstPersonExtension.fixed_update builds
its rotation from those three angles. ActionSweep uses that first-person
rotation for sweep references. This establishes the available stock route in
the cached source, not remote-server acceptance or damage verification.

Visibility transitions now report guide_state, including tracking_unavailable
and action_running, so a subsequent disappearance can be distinguished from
the orientation candidate. Selected committed melee input changes report
input_roll_deg. These diagnostics do not certify visual alignment.

Validation on Windows x64:

- Pinned LuaJIT source gate: 56 chunks pass in the integrated checkout.
- CTest in build/xr-frame-stage-timing: online_rules, online_reticle,
  weapon_stabilization, weapon_assist, crosshair_feedback, options_layout,
  gun_aim, smart_tag_marker_target, melee_preview, melee_simulation_visual,
  melee_preview_display: all 11 pass. The two changed fixtures pass again
  after adding diagnostics.
- The orientation fixture checks 14,420 forward-pointing poses through full
  wrist turns at varied yaw/pitch, poles, non-finite input, wraparound,
  hysteresis, windup/sweep latching, idle recovery and ranged exclusion.
  Engine math and worn rendering are not executed by these fixtures.

Stage with the pending hand-crosshair feedback, Light VR assist and menu-height
refresh from HAND-AIM-FEEDBACK-CONTROLS-2026-09-08.md. Use the focused worktree,
preserve accepted native/viewer binaries, and keep the current live game running
until the user's pending restart-timing question is answered. On the next
authorized launch, retain the existing readiness and Lua gates, enable the
preview with its one-shot flag, verify fresh stereo initialization/nonzero
shared_ready, and restore the startup flags after their success messages.

Required worn check: aim at one fixed point and slowly roll through horizontal,
diagonal and inverted wrist positions. The crosshair should remain on that
point and the guide should change in stable steps. Start one light attack at
each orientation and verify its path; repeat in the solo mission. Tracking-loss
and attack hiding should remain intentional. Check staff/ranged pointing after
switching weapons. Do not mark the reported disappearance resolved before this.
