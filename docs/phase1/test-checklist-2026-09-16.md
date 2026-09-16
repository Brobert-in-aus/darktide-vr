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
    - The stock interaction prompt should follow what your hand reaches: it
      reads the interactor's target unit, which is what this changes, so no
      separate marking was built. Note that the prompt still names the stock
      interact binding rather than "grip"; say if that reads wrongly.
    - Unit test `reach_interact` only; the feel is worn.

11. **Inspect by bringing the weapon up** (restart; Experimental features,
    "Inspect by bringing the weapon up", default off, new 16 September).
    Hold the weapon up to your face, turned side on, for about a third of a
    second: the stock inspect runs until you bring it down.
    - Try it with a gun and with a melee weapon; check the animation starts and
      that lowering the weapon ends it.
    - It must not start while aiming down the sights (with "Sight to eye" on,
      bring the sights to your eye and confirm nothing inspects).
    - Swinging a weapon past your face must not inspect (the 0.35 s dwell).
    - A pulse on the gun hand (with vibration on) when it starts;
      `DARKTIDEVR_INSPECT enter` in the log.
    - Unit test `weapon_inspect` only; the thresholds are worn judgements, so
      say if it takes too much or too little to start.

12. **Push to talk with a hand at your mouth** (restart; Experimental
    features, "Push to talk with a hand at your mouth", default off, new
    16 September). Bring your off hand up in front of your mouth, hold for
    about half a second: the microphone opens until you take the hand away.
    - Check the microphone actually opens (the stock voice indicator) and
      closes on dropping the hand.
    - Your push to talk binding must still work as it does now.
    - It must not fire while that hand is on the gun (two-hand support on),
      nor from a hand passing the face.
    - A pulse on that hand (with vibration on) when it opens;
      `DARKTIDEVR_COMMS talk` in the log.
    - The zone is a 20 cm ball 16 cm forward and 12 cm below the eye: say if
      you have to hold your hand somewhere unnatural, or if it opens when you
      did not mean it to.

13. **Tag what your off hand points at** (restart; Experimental features,
    "Tag what your off hand points at", default off, new 16 September). Hold
    the off hand out ahead and press tag: the tag should land where that hand
    points, not where the weapon aims.
    - Point at an enemy, a pickup and a door while aiming the gun somewhere
      else; the tag prompt and the marker should follow the hand.
    - With the hand down, or on the gun, or up at your mouth to talk, tagging
      must follow the weapon exactly as it does now.
    - `DARKTIDEVR_TAG pointing` in the log each time the hand comes up.
    - Say whether "arm out ahead" is the right threshold: it takes the hand
      25 cm forward of and 35 cm from your eye to start, and keeps pointing
      until it comes back inside 15 cm forward or 25 cm away, then for a
      further 0.3 s after that, so a tag pressed as the arm comes down still
      goes where you pointed.

14. **The body overlay, dev flag** (write `mirror` into
    `mods/darktidevr/darktidevr_body_mirror.flag` in the installed mod folder,
    then start; delete it afterwards). This is the milestone 3 full-body
    overlay: your own character spawned as a copy, scaled so its neck reaches
    your head, its arms solved to your controllers, with the clavicle swing,
    protraction and the soft stretch all on (the `both4` result). It gates the
    next step, which is moving it out of the dev flag and into the experimental
    full-body mode, so a look is worth more than any measurement a synthetic
    run can give.
    - Look down: are the arms, gloves and gun readable, and is there one pair
      of hands rather than two?
    - Reach across your body, straight up, and out to each side: do the arms
      stay on the controllers, and do the sleeves stretch anywhere?
    - Strafe and turn: does the body follow your head rather than the running
      animation?
    - With a hooded torso, is the neck placed behind your eye?
    - Whether the copy being enlarged 17-24 % to bring its neck to your head
      is worth it, or the arms should be their calibrated length instead
      (the open question in the arm length design).

## Suggested order

Quickest first, then the ones that need a mission:

1. In the Psykhanium, from the menu: 8 (calibration T-pose guidance, worth a
   fresh calibration first, since every arm length follows it), 11 (inspect),
   12 (push to talk), 3 (melee swings), 4 (glove grip), 7 (body heading).
2. Still in the Psykhanium: 5 (melee charge count), 2 (strafe wobble),
   15 September item 30 (grab feedback along the gun), 32 (body holsters).
3. In a mission (SoloPlay is enough for most): 10 (reach to interact),
   13 (tag by pointing), 1 (servo skull, Skitarius with the flamethrower
   blitz talented), 15 September item 19 (teammate status).
4. Last, because it needs a flag written and removed: 14 (the body overlay).

15. **Hand role resolution in one place** (restart; no option, nothing should
    look different). Five modules each had their own copy of the
    right-dominant fallback table and now ask `presentation.hand_side(role)`.
    Nothing about behaviour is meant to change, so this is a "still works"
    pass rather than a new thing to try:
    - Aim, fire and melee with a gun and a melee weapon: the crosshair, the
      drawn weapon and hit feedback follow the weapon hand as before.
    - The melee preview (if on) still appears and still hides when tracking
      drops.
    - Menu haptics (with vibration on) still tick on the weapon hand.
    - Sway cancellation (if on) still applies.
    - Unit tests cover the resolution itself, including that an unknown role
      still yields no side rather than defaulting to right.

16. **The last role swaps** (restart; no option, nothing should look
    different). Four more places that meant "the weapon hand" and named the
    right one now ask for the role, including what arms the fire action.
    Another "still works" pass:
    - Shooting works at all, and stops working when the weapon hand's
      tracking drops (put that controller down) rather than when the other
      one does.
    - With keyboard and mouse: a melee swing's roll still follows the mouse,
      and a controller ray still overrides it.
    - Unit tests cover the resolution; the fire-action arming is worn-only.

17. **Off-hand-relative movement** (restart; Movement direction, the same
    "still works" family as 15 and 16). The option that was labelled
    "Left-hand-relative" now reads "Off-hand-relative" and the code behind it
    asks for the off hand rather than the left controller. While the weapon
    hand is fixed at the right these are the same hand, so nothing should
    change:
    - With it selected, walking still follows where your off hand points, and
      still falls back when that controller loses tracking.
    - A setting saved before today must still be selected when you open the
      menu (the stored value is unchanged; only the label moved).

18. **Fingers stop following the animation** (restart; full-body/rigid-hand
    drawn hands, animation audit item H). The drawn fingers take their curl
    from the stock animation once per weapon, after about half a second of
    standing still with no action, and then hold it.
    - Stand still with a gun, then move and fire: the fingers should keep the
      same grip rather than breathing with the idle or twitching through
      actions.
    - Switch weapons: each weapon should settle into its own grip.
    - Melee swings: the fingers should still follow the swing, as the hands do.
    - `DARKTIDEVR_IK finger_pose key=<weapon>/<hand> joints=N` in the log marks
      each capture.
    - Say if any weapon's held curl looks wrong for that grip: the capture
      takes whatever the animation was showing at that moment.

19. **Crosshair feedback unchanged** (restart; part of the same "still works"
    family as 15 to 17). The helper that rebuilds the crosshair's charge and
    hit pieces in the world now lets another element ask for its own passes;
    the crosshair keeps its existing filter. Charge bars and hit feedback
    around the aim point should look exactly as they do now, at whatever
    crosshair scale is set.
