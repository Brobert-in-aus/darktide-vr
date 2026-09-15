# Unattended session, 15 September 2026

Branch `codex/alpha-4-2026-09-14`. Queue:
[todo-2026-09-15.md](../phase1/todo-2026-09-15.md), under
[the 14 September brief](2026-09-14-unattended-brief.md), with the same
boundaries:
- local scenes only;
- no publishing and no `main` changes;
- no settings changes;
- new features off by default;
- an evening checklist entry for everything deployed
  ([test-checklist-2026-09-15.md](../phase1/test-checklist-2026-09-15.md)).

Start of the day:
- Quest at 96 %, awake, proximity automation on.
- VR mode with the restored settings; no crash overnight.
- Heartbeat cron every 20 minutes.

## Settings safeguard (todo item 2)

Commit `cd132ea`.
- **Backup at launch.** When the mod loads, the capture library copies
  `user_settings.config` into `%LOCALAPPDATA%\DarktideVR\settings-backups` as
  `user_settings.<stamp>.config`. It copies only when the file is sound:
  - at least 2 KB;
  - braces and brackets balanced outside strings, and never closing before
    they open;
  - no zero bytes (a crash-truncated file is often zero-filled);
  - it has a `mods_settings` block;
  - it is not identical to the newest backup;
  - it is not smaller than 70 % of the newest backup (the reset file on
    14 September was half the size).

  Five backups are kept. Logged as `DARKTIDEVR_SETTINGS
  backup=saved|unchanged|missing|invalid|shrunk|failed`.
- **Restore.** `darktidevr-mode.ps1 -Mode restore-settings` (batch option 4)
  restores the newest backup and keeps the replaced file as
  `user_settings.before-restore-<stamp>.config`. Status names the newest
  backup.
- **Tests:** `settings_backup` (plausibility, zero-fill, unchanged, shrunk,
  rotation) and `mode_switch` (refused without a backup, newest restored,
  the replaced file kept).
- **Evidence (`run26`):** `backup=saved` at launch, with a 23.6 KB backup
  written.
- **Settings file.** The only differences from the restored 07:23 profile are
  DMF's defaults for yesterday's new options (grip bindings, haptics,
  holsters, two-hand, ammo readout). No values the user had set changed.

## Two-handing through reload and bash (todo item 6)

- **Commits.** The fix `c83db86` (last night) was deployed this morning. The
  synthetic once path now presses reload during each two-hand hold
  (`ca007b0`) instead of after firing.
- **Evidence (`run26`, Informative haptics).** Every hold with a reload
  press, where `weapon_reload_pressed` was delivered 0.6 s into the hold,
  logged `released ... ended=released` at the let-go 0.9 s later. Last
  night's worn holds logged `ended=cancelled`. The reload vibration fired
  when the reload finished.
- **Not shown:** bash while holding (unit tested only), and how it feels.

## Ammo count layout (todo item 3)

Commits `7efa0ef`, `fe0277d`, `10717e5`, `0da004b`.
- **Layout.** The clip count, a dash (a bar, so it never depends on the
  font) and the reserve are stacked as separate glyph boxes with a gap above
  and below the dash, centred in the reload ring. `Readout.stack_layout` is
  unit tested for no overlap, the dash midway, the stack centred and fitting
  inside the ring.
- **Eye renders** (readout test flag `front`, 0.5 m ahead,
  `artifacts/unattended/ammo-readout-20260915/run1`..`run5`):
  - `run1` separated the numbers, but the gaps were uneven (large above the
    dash, small below).
  - `run3` and `run4` calibrated the glyph extents against the dash bar,
    which is drawn at an exact position; `run4` let the dash touch the clip.
  - `run5` gives clear, near-even gaps (about 25 and 20 px at 1.5x crop).
- **Why the worn screenshot overlapped.** At hand distance the small reserve
  font renders relatively larger (0.63 of the clip's height instead of 0.5).
  The reserve's extent is therefore taken generously (0.30-0.90 of its size).
- **Not shown:** the worn view at hand distance.

## Research and designs (todo items 7 and 8)

- **Research notes.** Two background research passes, web sources only, each
  claim tagged [S] sourced or [I] inferred, copied to `docs/phase1/research/`:
  - two-handing and virtual stocks;
  - full-body IK.
- **Two-handed aim.** [two-hand-aim-design-2026-09-15.md](../phase1/two-hand-aim-design-2026-09-15.md).
  - The mod's aim model already matches VRExpansionPlugin, FRIK and XRI: a
    minimal swing on the dominant hand's pose.
  - The difference is the filter. The swing is smoothed in controller-local
    space, so wrist rotation drags the barrel off the support hand.
  - Offline measurement: a 10° wrist yaw with still hands leaves the barrel
    8.5° off the hands line on the next frame and 2° after 10 frames.
  - Proposed fix: filter the hands line in tracking space and recompute the
    swing from the current wrist every frame. Then a virtual stock anchored
    to a shared shoulder estimate.
- **Full-body IK.** [full-body-ik-design-2026-09-15.md](../phase1/full-body-ik-design-2026-09-15.md).
  - Maps how the gameplay avatar, first-person rig, gloves, upper-body proxy,
    camera and networking relate today.
  - Chooses a full-profile proxy (all cosmetics) posed by the mod, with legs
    copied from the stock avatar (the VHVR hybrid).
  - A body frame module owns the virtual shoulder for both the stock and the
    arm IK.
  - Revises the 14 September design; milestones are listed.
- **First step implemented and deployed: the steadying option.**
  Commits `9b1e549` and `ddaa54b`. Option *Two-hand steadying*: Classic
  (default, unchanged) or Hands line.
  - *Tests:* the pure tests pass.
    - A 10° wrist turn keeps the barrel on the hands line (0.00° off, where
      Classic gives 8.5°).
    - A stick turn has no lag.
    - 1 mm support jitter shows 0.013° against 0.17° raw.
    - A fast 10 cm sweep is within 0.1° after 3 frames.
    - Roll, release and ease-in are covered.
  - *`steady1` (Psykhanium, test flag `enabled_line`):* every synthetic hold
    released cleanly, with the same 9° steering as Classic in `run26` and no
    script errors. The synthetic path has no wrist rotation, so it cannot
    show the difference; that needs the worn A/B (evening item 4).

## Stray cartridge at the right glove (todo item 5)

Fix `abc400b`, deployed (evening item 5).
- **What it is.** The galvanic rifle receiver's column of rounds. Outside a
  reload the stock animation parks it on the gun at the grip, inside the
  character's wrist and sleeve. During a reload it moves into the
  magazine, which is why it vanished then. With the avatar's arms hidden
  (tracked gloves or the upper-body proxy), nothing covers it.
- **How it was found.**
  - *Scans* (`scan3`, `scan4`, dev flag `darktidevr_attachment_scan.flag`):
    listed every mesh and node of the wielded weapon. The receiver
    (`receiver_01`, 66 meshes) has cartridge-shaped meshes, four per round.
  - *View mode* (the same flag, `view ...`): while the rifle is wielded it
    holds the right controller at a fixed pose ahead of the headset. It also
    holds the trigger, grips and right stick so ammo and weapon stay put,
    and hides chosen meshes or attachments.
  - *Eye renders by elimination* (`artifacts/unattended/stray-bullet-20260915/`:
    `view2`, `bisect1`, `units1`, `units2`, `groups1`, `sets1`):
    - hiding the receiver removes the round, and the stock, barrel,
      underbarrel or muzzle alone does not;
    - it takes meshes 27-58 *and* 63-66 together, because overlapping rounds
      cover for each other;
    - the receiver has none of the likely visibility group names.
- **Fix.** `darktidevr_weapon_parked_parts.lua` hides those meshes while the
  avatar's arms are hidden, except during reload actions. The mesh table is
  keyed by attachment unit name and currently holds the galvanic receiver
  only.
  - *Test:* `weapon_parked_parts` covers selection, reload, stock arms,
    weapon change and failure restore.
  - *Evidence (`fix1`):* no round from three angles with no dev hiding; the
    drum and the rest of the gun draw normally; `parked_hidden meshes=36`
    logged; no script errors.
- **Ruled out on the way.** Moving the rig's mapped bones to follow the
  tracked gun (built, then removed before pushing). All 20 mapped bones
  already follow the attach node (`chain1`).
- **Not shown:** the worn view, and whether other guns have parked parts.
  The same scan and view flags can check them.

## Crosshair and iron sights (todo item 4)

Fix `96b13ed`, deployed (evening item 6). The earlier ray-origin attempt
`c1ea863` was replaced the same hour.
- **Measured** (`artifacts/unattended/stray-bullet-20260915/sight2`; view
  mode with a simulated ADS hold):
  - *Stock ADS pose* (hidden first-person rig): the eye sits 3.2 cm above
    and 0.8 cm left of the bore, looking along it (within 0.3°).
  - *Drawn VR gun:* the grip sits 8.6 cm below the bore.
  - *First reading (wrong, corrected after the user's review):* I took the
    reticle ray to run along the bore from the grip, giving a reticle 0.66°
    low at 10 m. The synthetic run showed "low" only because the unworn
    headset sits low.
  - *Actual cause:* in the stock-input route the reticle ray starts at the
    head (`darktidevr_online_reticle.lua` returns the first-person camera
    position) and runs along the gun's aim. The sights are parallel to it
    but offset by the head-to-sight distance. With the gun held below and to
    the right of the eyes, the reticle sits up and to the left of the
    sights: the user's screenshot `shot-205314`, about 1.5-2° at 10 m for a
    30 cm offset. The `sight2` numbers fit a head origin: the reticle
    8-16 cm to the left of the bore with the view pose's grip 12 cm right of
    the head.
- **First attempt: start the controller ray on the sight line.** It changed
  nothing (`sight3`): the active route publishes the reticle from the
  stock first-person position (`darktidevr_online_reticle.lua`). Moving the
  simulation's shot origin is not something to do from presentation, so
  it was reverted.
- **Fix: zero the drawn gun** (`darktidevr_gun_sights.lua`, presentation
  only).
  - The drawn gun turns about the grip by the small angle that puts its
    sight line through the reticle point.
  - It works whichever side the reticle is on, so it turns the sights up and
    left in the worn case.
  - Guards: clamped to 5°, skipped for points nearer than 0.75 m, eased over
    0.08 s. The first version (`96b13ed`) dropped corrections over 5°
    instead of clamping. With a 30 cm head-to-sight offset that meant anything
    nearer than about 3.5 m got no correction, and the correction snapped off
    as the aim point came closer. Fixed to clamp, with tests for the clamp
    and for an up-left reticle.
  - The aim that shoots and the reticle itself are unchanged.
  - *Sight offset:* the stock ADS eye, measured live after 0.8 s of ADS
    (shipped for the galvanic rifle), minus the placed gun's grip, both in
    the muzzle frame. Guns without a measured eye stay as they were until
    aimed down the sights once.
- **Test:** `gun_sights` covers the offset, the zeroing geometry in general
  poses, the near and cap guards, easing, a foreign reticle and unknown
  templates.
- **Evidence (`sight4`).**
  - The reticle point in the muzzle frame is (−0.005 to −0.008, 0.020 to
    0.027) against the sight line at (−0.008, 0.032). Before: (−0.08 to
    −0.16, −0.06 to −0.12).
  - The gun turned 0.6-0.9°.
  - The live eye measurement matched the shipped value; no script errors.
- **Not shown:** the worn sight picture; up close (under 2 m) the gun visibly
  turns more.

## Virtual stock and the shared body frame (design step 2-3)

Commit `1222cc6`, deployed, option default off (evening item 7).
- **`darktidevr_body_frame.lua`** is the shared estimate from the two-hand
  and full-body designs.
  - *Body yaw:* head yaw, pitch-safe past 50°, pulled 0.7 toward hands in
    front, with a 20° dead zone and 0.15 s catch-up.
  - *Neck:* 7 cm behind and 8 cm below the eye.
  - *Shoulders:* 17 cm either side and 8 cm down.
  - Lengths scale with eye height.
  - Pure tests: pitch-safe yaw, hand bias, dead zone, turn catch-up, a head
    glance with a gun held stays within 20°, shoulders, scale.
- **Option "Virtual stock (experimental)".** While two-handing a gun, the
  dominant shoulder, 3 cm inward, is the stock anchor. A butt within 15 cm
  blends the aim to shoulder-to-front-hand through the existing
  `Pose.stock_correction`, with the primary grip never moved.
  - **Assumption:** the butt sits 30 cm behind and 6 cm above the grip in the
    aim frame. It is not measured and needs worn tuning.
  - The release log adds `virtual_stock`, `stock_frames` and
    `stock_min_distance_m`.
- **Evidence (`stock2`, test flag `enabled_line_stock`).**
  - Every hold released cleanly with `virtual_stock=true`, and no script
    errors.
  - The synthetic resting grip puts the butt 17.8 cm from the estimated
    shoulder, so it never engaged; the synthetic gun is held low. Engagement
    and the aim change are covered by `two_hand_virtual_stock` (unit).
- **Incident.** `stock1` was void: the stray-bullet view flag
  (`darktidevr_attachment_scan.flag`) was still in the installed mod folder.
  It held ADS and took over the right hand. The flag is deleted,
  `run-view.ps1` now removes it at the end, and I checked the installed
  folder: only the mod's own `darktidevr_crosshair_scale.flag` remains.

## Menu haptics (carried item)

Commit `6e0d1a6`, deployed (evening item 8).
- **What.** Informative mode only: a tick when the VR menu pointer moves
  onto a control (`menu_hover`) and a firmer tick on click, enter, back,
  confirm or select (`menu_confirm`). Both play on the dominant hand.
- **How.** The stock hotspot pass plays its hover and click sounds when a
  control reacts. A `hook_safe` on `UIManager.play_2d_sound` maps sound
  event names by whole words, so `background_music` is not `back`. It runs
  only while `using_native_menu_input()` is true. The 60 ms per-hand rate
  limit keeps fast sweeps from buzzing.
- **Tests:** `haptics` covers the name mapping, modes, the hook firing only
  in Informative mode and only with the VR pointer.
- **Evidence (`menu1`).** A startup menu confirm pulsed and the viewer played
  it (`openxr.haptic request=1 hand=right amplitude=0.35 duration_ms=15
  result=0`). No script errors.
- **Not shown:** hover ticks (the synthetic pointer did not sweep over
  buttons) and the worn feel.

## Sight-to-eye aim down sights (backlog item)

Commit `b2ca404`, deployed, option default off (evening item 9).
- **Behaviour.** Raising a gun's sight line to within 4.5 cm of the dominant
  eye holds the alternate-fire input. It lets go past 7.5 cm, or when the
  gun turns more than 35° from the view. Hold and toggle ADS settings are
  both handled, and no release is sent while the player's own trigger is
  held.
- **Scope.** Only guns whose alternate is the stock aim, and only once the
  sight offset is known (`darktidevr_gun_sights`).
- **Assumption:** the dominant eye is the headset eye on the gun hand's side,
  3.2 cm from centre.
- **Test:** `sight_ads` covers the geometry, the lateral offset, hysteresis,
  facing, behind-the-grip limits, and hold and toggle edges.
- **Evidence (`artifacts/unattended/stray-bullet-20260915/sightads1`,
  `darktidevr_sight_ads_test.flag`).**
  - The measurement runs live: 9.5 cm from the line in the view `sight=1`
    pose and 15.2 cm in the low pose, with facing 0.985 (the −10° gun
    pitch). No script errors.
  - Neither synthetic pose came within the 4.5 cm entry distance, because
    the unworn headset is not at the recenter origin. **Engagement and the
    injected ADS input have not been seen in game**, only in the unit test.

## Holster labels (diegetic HUD backlog)

Commit `1873f49`, deployed, option default off (evening item 10).
- **What.** While a hand rests in a body holster zone, a small world label at
  the zone shows what it holds: blitz charges at the belt, the stim or
  carried item's name at the chest, ranged ammo at the shoulder, the melee
  weapon and device names at the hips, and "empty" for an empty slot.
  Holsters must be on.
- **Test:** `holster_counts`.
- **Evidence (`counts1`):** `first_draw zone=shoulder_right label=8 / 49` and
  `zone=hip_left label=Brutus Arc Maul`; no script errors.

## Weapon hand holsters (user request, afternoon)

Commits `4fffc5d` to `58d37d2`, deployed, option default off (evening item 11).
- **Request (user).** "a 'weapon hand holsters' option - the gun hand has
  small holsters along its forearm that the off-hand can reach into and
  press a button to equip that item - we can also show a small preview of
  the equipment in that slot".
- **Layout.** Four zones in the gun hand's grip frame, starting values to
  tune worn:
  - 20 cm behind the grip, 5.5 cm apart, 10 cm above the forearm line,
    3.5 cm radius;
  - from the wrist: the other weapon (melee while the gun is out, and back),
    stim, carried item, device.
- **Equip.** The zones join the off hand's holster zones, so pressing grip
  there wields the item through the existing holster grip request (dwell,
  zone haptic, claim). Works with or without the body holsters.
- **Preview.** Each occupied zone shows a miniature of the actual item (the
  stock `UIWeaponSpawner` in the game world), laid across the forearm. It
  shows only while the off hand is within 30 cm.
  - Scale: 0.07 for weapons, 0.25 for other items.
  - Part boxes were unreliable right after spawning, so fitting by
    measurement was dropped.
- **Tests:** `forearm_holsters` covers slot assignment, zone centres and
  spacing, the per-hand zone override, the grip request and an empty holster.
- **Evidence** (`artifacts/unattended/stray-bullet-20260915/forearm1`..`forearm14`,
  view mode `left=N press=1 lowleft=1 far=1`):
  - `forearm1`: the off hand armed `forearm_weapon` and the press wielded the
    melee weapon (`wield hand=left selector=melee`, then
    `wielded_slot=slot_primary`).
  - `forearm6` (`front` test mode): a miniature power maul renders 50 cm
    ahead of the eye.
  - `forearm11`: the preview sat exactly at its zone (logged every 2 s).
  - `forearm12` (`big`): it rendered there but was buried in the gun hand
    glove's large gauntlet cuff, so the zones moved up and back.
  - `forearm14`: at normal scale the maul miniature shows above the cuff (seen
    end-on from the synthetic camera). No script errors in any run.
- **Not shown:**
  - how it feels and reads worn;
  - previews of stims, carried items and devices (this character carried
    none);
  - whether the zones fit a real forearm.
- **Incident.** A capture was stopped before launch. Its request flags
  stayed in the installed mod folder and were deleted by hand; only the
  mod's own `darktidevr_crosshair_scale.flag` remains.

## Wrist display (diegetic HUD backlog)

Commit `661d1b6`, deployed, option default off (evening item 12).
- **What.** Turning the back of the off-hand wrist toward the face, within
  70 cm, shows health (with its number), toughness and stamina bars at the
  wrist. It shows at a facing of 0.75 and hides below 0.6.
- **Assumption:** holding a controller, the back of the hand faces the grip
  frame's outward side (left hand −right, right hand +right).
- **Not included yet:** the mission objective and the tactical overlay on a
  held look, which the backlog item also mentions.
- **Test:** `wrist_display` covers visibility with hysteresis, reach, the bars,
  clamping and missing values.
- **Evidence (`wrist1`, test flag `front`):** the three bars and "150" render
  45 cm ahead of the eye (eye render); `first_draw bars=3`; no script errors.
  The real wrist gesture has not been seen.

Note: `run2` died because I piped the capture script through
`Select-Object -First 1`, which stopped the script and so the runner's job
(the runner force-stopped the game). The game did not fault.
