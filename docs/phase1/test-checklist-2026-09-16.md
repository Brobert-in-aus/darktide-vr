# Worn checklist: 16 September 2026

Branch `codex/alpha-4-2026-09-14`, after the 0.2.0-alpha.1 release
(`d6d0e90`, tag `v0.2.0-alpha.1`). Session state and evidence:
[handover](../handoffs/2026-09-16-session.md). Each deployment adds an item
here when it is installed. Items still open from 15 September:
[test-checklist-2026-09-15.md](test-checklist-2026-09-15.md) (13 peril, 19
teammate status, 30 grab feedback along the gun, 32 body holsters from the
tracked eye).

## Start state

- Installed game: every file matches the 0.2.0-alpha.1 package
  (`artifacts/packages/darktidevr-0.2.0-alpha.1-d6d0e9081ce7`), checked at the
  start of the session. The only flag in the mod folder is the mod's own
  `darktidevr_crosshair_scale.flag`.

## Items

1. **Grab and throw the servo skull** (`c50bc04`; option "Grab
   and throw the servo skull (experimental)", default off; Skitarius with the
   flamethrower skull talented; Weapon hand holsters need not be on).
   - The flamethrower skull hovers in view: stock side and height, brought
     30 cm forward instead of 15 cm behind. The log shows
     `DARKTIDEVR_SKULL_THROW rest_forward=0.30` once. Say where it sits and
     where it should.
   - Put the off hand on the skull (12 cm grab zone around it) and hold grip:
     the flamethrower order aims as with the blitz button. Let go with a
     throwing motion: the order is issued, the skull leaves your hand at your
     throw's speed for the first 2/5 of its flight, then settles onto its
     real path and arrives at the target.
   - Log lines: `released target=valid`, `flight predicted_s=... node=<n>`
     and `arrived predicted_s=... actual_s=...`. Compare the two times at
     about 3 m and 10 m.
   - Also: a release without a valid target does nothing; without the talent
     there is no grab zone; the blitz button still works as before; turning
     the option off returns the skull to its stock place.
   - Unattended evidence: unit tests only. No run with the talent and a
     grabbing hand is possible without the user.

2. **Strafe wobble: eye from the current anchor** (restart; always on).
   Weapon hand holsters on, gun out: strafe left and right, then walk forward
   and back, looking at the forearm models. They should stay steady, no
   longer turning back and forth between two poses while strafing. Also check
   nothing else moved: the ammo counter on the gun, the wrist display, sight
   ADS by raising the gun, and the crosshair on the iron sights.
   - Evidence so far: static audit (`docs/phase1/animation-audit-2026-09-16.md`)
     and the `tracked_eye_anchor` unit test; no worn or eye-render check.

3. **Displays during melee swings** (restart; always on). With a melee
   weapon's stock swing animation playing (button melee), the forearm
   holster models, wrist display and ammo or charge count should stay with
   your hands and not jump by a step while moving: the body anchor is now
   refreshed on that path too. Unit test only (`melee_simulation_visual`).

4. **Gun-hand glove held on the grip** (restart; always on). Draw each gun
   and stand still with no action for about half a second (30 frames): the
   log gains `DARKTIDEVR_IK gun_hand_grip template=<gun> samples=30`. From
   then on the right glove stays put on the grip while strafing, running and
   idling, instead of following the character's animation.
   - Look for the glove at the wrong place on the grip. If the first capture
     happened at an odd moment, restarting the game recaptures.
   - Known trade-off: the gun hand no longer moves during reloads or
     inspects; it stays on the grip.
   - Unit test only (`gun_aim` grip capture).

5. **Melee charge count beside the controller grip** (restart; needs "Ammo
   count at the hand"). With a charge melee weapon (arc maul) out, the charge
   count sits beside the gun hand as before, now placed from the controller
   grip rather than the drawn wrist; it should not move while strafing.

6. **Viewer survives a zero field of view** (`a5a5ed5`; viewer
   `bin\darktidevr-xr-harness.exe` rebuilt, the alpha.1 package's copy kept as
   `artifacts/unattended/body-mirror-20260916/darktidevr-xr-harness.before-fov-guard.exe`).
   Nothing to do in normal play: launch as usual and confirm the headset view
   starts. Taking the headset off at the title screen and putting it back on
   should no longer leave the viewer stopped. Unit test (`core_math`) only;
   the unattended runs that hit it are recorded in the handover.

7. **Body heading seeded from the head** (restart; experimental full-body
   mode only). On entering a level with the full-body body mode on, the body
   starts facing where you look rather than where the character root faced.
   Nothing changes in the default hands mode. Static change; suite only.

8. **Calibration T-pose guidance** (restart; open the VR calibration). The
   T-pose instruction asks for arms straight out at shoulder height, fully
   extended, controllers pointing outward. After saving, the result shows
   the arm span with the span expected for your height, and names any problem
   with the T-pose (short, forward, low, uneven), saying your height is used
   for arm length instead.
   - Worth doing: recalibrate standing with arms fully out. The saved span
     (150.6 cm) is 12.6 cm short of the 163 cm expected. Does the new capture
     land near 163 cm?
   - Check the longer result text fits its box.
   - Arm lengths are not yet applied in normal play; this only records the
     capture and its checks (`expected_hand_span`, `t_pose_problems` in the
     saved result).

9. **Neutral eye anchor measured in the aim frame** (restart; deployed
   16 September, animation audit item K). The one-time model-eye offset used
   as the camera's neutral origin is now measured in the avatar's own aim yaw
   frame instead of the recenter basis, so the eye's forward depth (about
   8.5 cm) survives a spawn facing across that basis; a pitched aim (more than
   15 degrees up or down) defers the capture rather than baking a look-down
   into the height, with the first-person fallback serving until then.
   - Spawn into the Psykhanium and into a mission (SoloPlay) and check the
     view height and fore-aft placement feel the same in both, and the same as
     before this change. Entering a level looking sharply down or up should
     settle to the same place a moment later.
   - The character's turn to run at an angle must not move the view.
   - Unit test `eye_anchor_offset` and the source invariant cover the
     derivation; the placement itself is worn-only.

10. **Reach to interact** (restart; Experimental features, "Reach to
    interact", default off, new 16 September). Put a hand on a door control,
    a pickup or a downed team mate and press grip: it interacts without you
    looking at it.
    - In a mission: a door console, an ammo or health crate, a grimoire or
      scripture, a team mate to revive. Reaching with either hand.
    - The grip must keep its own binding (weapon special on the right, class
      ability on the left) whenever nothing is in reach.
    - A holster or the gun's second grip must still win the hand: with
      "Weapon hand holsters" on too, reaching into a holster equips rather
      than interacting.
    - Nothing should come into reach that you could not have used by looking
      at it: the game's own range and filters still choose.
    - The log line `DARKTIDEVR_REACH armed hand=... distance_m=...` marks each
      time something comes into reach, and `DARKTIDEVR_REACH probe found=...`
      every two seconds says what the search found along each hand, so
      "nothing was in reach" can be told from "the search never ran".
    - A pulse on the hand (with vibration on) when something comes into reach,
      the same one a foregrip or an armed holster gives.
    - Unit test `reach_interact` only; the feel is worn.
