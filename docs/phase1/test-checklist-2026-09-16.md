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
- **Check the flags again before putting the headset on.** Six of today's
  features read a `*.flag` file in the installed mod folder and turn
  themselves on when one is there, whatever the option says:
  `darktidevr_reach_test`, `_inspect_test`, `_comms_test`, `_tag_test`,
  `_weapon_charge_test` and `darktidevr_holsters_test`, plus
  `darktidevr_body_mirror.flag` for the overlay. The unattended runner writes
  and removes them, but a run that is killed leaves them behind. Anything
  other than `darktidevr_crosshair_scale.flag` should be deleted first.
- The Lua in the install matches the branch head, checked after every
  deployment today. The native binaries are still the released ones; see the
  handover for why.

## Items

> Trimmed on the evening of 16 September to the items still untested. The
> user's results for the others (1 to 5, 7, 10 to 12, 17 to 21) and the fixes
> they led to are in
> [the handover](../handoffs/2026-09-16-session.md) ("The evening: the worn
> session"). Numbers are kept as they were, since the handover and changelog
> cite them.

6. **Viewer survives a zero field of view** (`a5a5ed5`; viewer
   `bin\darktidevr-xr-harness.exe` rebuilt, the alpha.1 package's copy kept as
   `artifacts/unattended/body-mirror-20260916/darktidevr-xr-harness.before-fov-guard.exe`).
   Nothing to do in normal play: launch as usual and confirm the headset view
   starts. Taking the headset off at the title screen and putting it back on
   should no longer leave the viewer stopped. Unit test (`core_math`) only;
   the unattended runs that hit it are recorded in the handover.

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
   In plain terms: enter a level facing across the play space rather than
   along it. Your eye should sit where it does when you enter facing along
   it: the same distance from the wall, not pulled back. Before the fix,
   entering sideways left the view about 8 cm too far back until you
   levelled your head. If nothing looks different either way, it passes.

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

22. **Frame profiler wrapping** (restart; no option, nothing should look
    different; the same "still works" family as 15 to 19). Every per-frame
    sampler in the input block and every hand display in the draw pass is now
    called through a timing wrapper. With the profiler's flag absent, which is
    every player, the wrapper is one branch and a pass-through, and the calls
    return exactly what they did. If items 1 to 14 and 20 to 21 behave, this
    is covered.

23. **Haptics sample without per-frame allocation** (restart; "Controller
    vibration" on, as it is in your saved settings; the same "nothing should
    look different" family). Every pulse should arrive exactly as it does now:
    damage, toughness broken, block, stamina, downed, peril, charge, heavy
    ready, the melee special, interactions, clip empty, reload, low ammo. A
    24-frame scripted trace of both modes is locked in a test and reproduced
    exactly; this is the worn confirmation of the same.

24. **Dev-flag polls throttled** (restart; no option, nothing should look
    different; the same "still works" family). The input-manager hook no
    longer tries to open a diagnostic flag file every frame, and the eleven
    modules with a test flag poll it every five seconds instead of two. The
    only visible effect is for the unattended tools: a flag written mid-run
    is picked up within five seconds rather than two, and every runner writes
    its flags before launch anyway. Measured in the Hub: the mod's Lua from
    0.30 to 0.18 ms a frame, no errors. If items 1 to 23 behave, this is
    covered; the one thing to notice is that nothing stutters that did not.

25. **Sampler gates** (restart; no option, nothing should look different).
    The communication wheel button, two-hand support and its capture all
    behave as they did: the wheel opens on its button, a calibrated gun
    still takes the support hand, and holding nothing costs the mod less.
    The three changes are exact reorderings, so if items 6 (two-hand) and 12
    (push to talk) behave, this is covered.

26. **Marker material values replayed once per change** (restart; no option;
    the "still works" family, but this one is worth a look rather than an
    assumption). Every world marker on the plane keeps its look: the frame
    around an interaction prompt keeps its proportions and its 9-slice edges
    (the `ui_scale` value), icon tints and progress fills update as they did
    (a value that changes replays at once), the tag wheel and the hand
    overlays are unchanged (their scaled copies replay every time, as
    before). If a marker's frame ever looks stretched or a fill sticks at an
    old value, this is the item: the atlas skips replaying a material's
    values while their revision holds.

27. **Marker head frame shared per frame** (restart; no option; the "still
    works" family, worth a look with a marker in view). World markers, the
    interaction prompt and the tag prompt sit on their planes exactly as
    they did while you turn your head and walk: no lag of the plane behind
    the head, no marker a frame behind another. The head's frame is computed
    once per frame for all markers instead of once per marker, keyed on the
    frame clock, so a stale key would show as the plane lagging the head by
    a frame. The profiler's totals also stop double-counting nested
    sections, which changes only log lines.

28. **Native module and proxy rebuilt** (restart; no option; the "still
    works" family, and the one native change of the day). The capture DLL
    and the d3d12 proxy in the installed mod are today's build; without
    `darktidevr_queue_priority.flag` and `darktidevr_gpu_process_priority.flag`
    (both absent for you) the only difference is two exported counters and
    the bootstrap log's leading fields, no hook and no OS call. Launch, reach
    the Hub, confirm the headset picture and, in
    `binaries/darktidevr-d3d12-bootstrap.log`, the line beginning
    `native_results gpu_process_priority_class=-1 applied=0 status=0x00000000
    queue_priority_requested=0 queue_priority=0`. If the
    game fails to start or the picture is missing, the first suspect is the
    proxy: `Darktide VR Mode.bat` status reports the proxy's state.

29. **Atlas cells inset by half a texel** (restart; no option; from your
    first worn observation this evening: a sliver of the wrist display's
    health, toughness and stamina bars beside the ammo count on the gun
    hand). The hand overlays and world markers share atlas cells whose quads
    sampled exactly to the cell edge, so the filter blended in the
    neighbour's edge texels. The quads now sample half a texel inside the
    cell. Check: no sliver beside the ammo count; the ammo count, holster
    labels, wrist display and world markers otherwise unchanged (a half
    texel is below what the eye can see).

30. **Boards re-seat on a recenter** (restart; no option; from your first
    worn observation: loading screens and flat menus turning against the
    head). Tonight's viewer log showed thirteen runtime recenters in the
    session against one last night, each moving the space the
    world-anchored boards live in. Every board stays a spatial board in the
    world, as intended (a first build of this item head-locked the loading
    screens; you called that out worn and it is withdrawn); whenever the
    runtime or the game recenters, the board is re-seated in front of you
    from the current head instead of being left where local space moved.
    Check: a loading screen or menu stays where it opened while you look
    around, and jumps back in front only if a recenter happens. If a board
    still drifts against the head without a recenter, the recenters
    themselves are the next question (the headset's tracking, boundary or
    Virtual Desktop; the mod requests none).

31. **Item radial picks on the flick** (restart; Experimental features,
    "Item radial"). Hold the carried-items control and flick the stick into
    a sector: the item wields the moment the stick enters the sector, not on
    release, and a flick-and-press together no longer falls through to the
    stock weapon cycle. A press mid snap-turn with the stick already hard
    over still waits for the stick to pass centre before it can pick. A
    plain tap still cycles as stock does. A second flick to another sector
    wields that one.

32. **Push to talk hums while held** (restart; "Push to talk with the off
    hand at the mouth"). While the gesture holds the talk key, the talking
    hand carries a constant very low vibration (one faint pulse every tenth
    of a second) on top of the entry pulse; it stops when you lower the
    hand.

33. **Full body in the settings menu** (restart; Experimental features,
    "Full body (experimental)", default off). The same experimental
    full-body mode the dev flag turned on, now as an option; takes effect on
    the next level. The movement direction option now reads
    "Left-hand-relative". "Reach to interact" and "Inspect by bringing the
    weapon up" are out of the menu (withdrawn after tonight's worn test;
    their saved values are ignored).

34. **Loading and menu boards** (restart; item 30 as corrected): every board
    is a spatial board in the world; a recenter re-seats it in front of you.
    The build you saw head-locked was my unattended run's, not this one.

35. **Servo skulls swapped and following smoothly** (restart; Experimental
    features, "Grab and throw the servo skull"; Skitarius with the
    flamethrower skull). The flamethrower skull now rests on your off-hand
    side, 30 cm forward, and the medical and regular skulls on the other;
    all of them follow you with a small lag, like the HUD, instead of
    sitting rigidly on the body. Grab the flamethrower skull with the off
    hand (grip near it), with Weapon hand holsters on: the grab takes the
    skull, not the forearm holster. Order it out normally: the drawn skull
    slides across to the flying one over a fraction of a second rather than
    jumping (the server's skull leaves from its own rest); on its return it
    slides back to your side. Throw as before.

36. **One weapon charge display** (restart; Experimental features, "Weapon
    charge display": count / bars / off, default count). With a melee
    weapon that has charges, the count sits where the bars sit, above the
    weapon hand's grip, not over the ranged weapon; "bars" shows the HUD's
    charge bars there instead; "off" shows neither. The count also needs
    Ammo count at the hand on.

37. **Review fixes on the evening's changes** (restart; the "still works"
    family, with two visible checks). A review found: the talk hum was a
    haptic "notice" and swallowed damage and toughness pulses while
    talking (now it never displaces one); the skull follower kept chasing
    during the flight and would have trailed two metres then snapped (now
    it bridges over a third of a second when the skull is sent, draws the
    real skull in flight, and glides back to your side on its return); the
    melee count's gate could hide a ranged weapon's ammo count under "bars"
    or "off" (now it gates on the values being charges); reach and inspect
    kept running for anyone who had turned them on (now only their test
    flags can); the boards' re-seat waits for a frame with a head and for
    the runtime's recenter to have taken effect. Check worn: while
    push to talk is held, a hit still buzzes both hands; a sent skull
    leaves your side smoothly and comes back smoothly; with the weapon
    charge display on "bars" or "off", a gun's ammo count still shows.

## Suggested order

1. First at launch: 28 (the native rebuild) and 34 (the boards), both on
   the way to anything.
2. In the Hub: 29 (no sliver beside the ammo count), 26 and 27 (a marker and
   the interaction prompt on their planes while you turn your head), 33 (the
   full-body toggle and the movement label in the menu).
3. In the Psykhanium as Robobert: 35 (the skulls), 36 (the charge display),
   31 (the radial on the flick), 32 (the hum while talking), 37 (a hit still
   buzzes while talking; a gun's ammo count with the charge display on
   "bars" or "off"), 6 (two-hand), 9 (the eye anchor, entering sideways).
4. When convenient: 8 (the calibration guidance), 22 to 25 (covered if the
   rest behaves), 14 to 16, and 13 only if you decide tag by pointing stays.
