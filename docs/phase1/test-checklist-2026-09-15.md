# Evening checklist, 15 September 2026

Everything deployed today, on branch `codex/alpha-4-2026-09-14`. Evidence is in
the [session handover](../handoffs/2026-09-15-unattended-session.md).
Yesterday's checklist items not reached are still open in
[test-checklist-2026-09-14.md](test-checklist-2026-09-14.md) (items 1, 3, 4,
5, 7, 9).

## Start here (suggested order for a short session)

Installed state: every Lua file matches branch head (audit, 15 September
afternoon). No dev flag files are left in the installed mod folder apart
from the mod's own `darktidevr_crosshair_scale.flag`.

- **Fixes, on for everyone (no option to turn on):**
  - 5, stray cartridge gone;
  - 6, crosshair on the iron sights (hold the rifle as in the 14 September
    screenshot);
  - 2, two-handing survives reload and bash;
  - 3, ammo layout;
  - 15, gloves and weapons unchanged after the hands refactor.
- **Two-handing A/B (Experimental options):**
  - 4, Two-hand steadying set to Hands line;
  - 7, Virtual stock on top of it.
- **New options, all default off, in Experimental:**
  - 11, weapon hand holsters (your request);
  - 9, aim down sights by raising the gun;
  - 12, wrist display;
  - 10, holster labels (needs Virtual holsters);
  - 13-14, peril and melee charges at the hand (need Ammo count at the hand);
  - 8, menu ticks (vibration mode Informative).
- **Nothing to do:** 1, settings backup.

Seen working in unattended game runs:
- 2, 3, 5, 6 and 10;
- 11: equipping from the forearm, and the previews (A/B render);
- 7 and 9: their measurements run, but engagement was never reached with
  synthetic hands;
- 8: a menu confirm tick reached the viewer.

- 14: the arc maul's charges (0/8 rising to 2/8 in an eye render).

Unit tested only: 13.

Also deployed, nothing to test: the full-body development work (body mirror
and overlay, `3d3d788` to `9286319`) runs only with a dev flag file that
players never have. The installed mod folder has no such flag. Item 15 covers
the part of the hands refactor that runs for everyone.

1. **Settings backup at launch** (`cd132ea`). Nothing to do in game.
   - After launching, `%LOCALAPPDATA%\DarktideVR\settings-backups` should
     hold a `user_settings.<date-time>.config`. Console:
     `DARKTIDEVR_SETTINGS backup=saved` (or `unchanged` on later launches).
   - If settings ever reset after a crash, close the game, run
     `Darktide VR Mode.bat` and choose 4.
2. **Two-handing through reload and bash** (`c83db86`). With Two-hand support
   on, hold the foregrip and:
   - reload: the grip holds;
   - bash (weapon special bash on guns that have it): the grip holds;
   - inspect, or switch weapon: the grip lets go.
3. **Ammo count at the hand: clip, dash, reserve** (`7efa0ef` to `0da004b`).
   With the option on and a gun out:
   - the clip count, a short dash and the reserve count sit stacked without
     touching, inside the reload ring;
   - the colours still fade independently.

   Say if the dash or gaps look wrong at hand distance (calibrated at
   0.5 m in front of the eye).
4. **Two-hand steadying: Classic against Hands line** (`9b1e549`, `ddaa54b`).
   Option: *Two-hand steadying* next to *Two-hand grip*. It defaults to
   Classic, which is unchanged. With Two-hand support on and the galvanic
   rifle, hold the foregrip, then:
   - with **Classic**: move and turn the **right** hand (twist the wrist, aim
     left and right with the gun hand) and note the feel;
   - switch to **Hands line** and repeat. The barrel should stay on the front
     hand when the gun wrist turns, without the short swim back.
   - Also try turning with the stick while holding (no lag in either mode)
     and fine aim on a distant target (small tremor should be smoothed).

   Say which feels better. If Hands line wins it becomes the default, and the
   virtual stock is built on it
   ([design](two-hand-aim-design-2026-09-15.md)). The console line
   `DARKTIDEVR_TWO_HAND released ... steadying=` shows which mode was active.
5. **No stray cartridge at the right glove** (`abc400b`). Galvanic rifle out,
   hands mode:
   - look at the right hand and the top of the grip from several angles: no
     round sticking up beside the glove;
   - reload: the rounds may appear during the reload animation (they go
     into the magazine), then vanish again;
   - everything else on the rifle (drum, bolt, sights) still draws.

   If another gun shows a similar stray part, say which. The scan flag can
   find its meshes the same way.
6. **Crosshair on the iron sights** (`96b13ed`). Galvanic rifle:
   - hold the rifle as in the 14 September screenshot and look at something
     5-20 m away: the crosshair should sit on the sights, where it used to be
     up and to the left of them;
   - aim down the sights: the crosshair stays on the front sight;
   - close up (a wall 1-2 m away), the gun turns a little more to keep the
     sights on the crosshair. Say if that turn is noticeable or unpleasant.

   Other guns are corrected once you have aimed down their sights for about
   a second. Say if one is still off after that.
7. **Virtual stock (experimental)** (`1222cc6`, option default off; try it
   with Two-hand steadying on Hands line). Galvanic rifle, both hands on:
   - bring the butt to your dominant shoulder, as when aiming: the gun
     should settle and small right-hand wobbles stop swinging it;
   - lower the gun away from the shoulder: normal two-handing again;
   - glance left and right while shouldered: the stock should not wander.

   Say where the shoulder feels (too high, low, far out or in) and whether
   it engages too early or late. The butt position is an estimate. The
   console line `DARKTIDEVR_TWO_HAND released ... stock_frames=
   stock_min_distance_m=` shows how close the butt got.
8. **Menu ticks** (`6e0d1a6`). Controller vibration mode Informative, in
   any menu (inventory, mission board, options):
   - moving the pointer onto a button gives a very light tick;
   - clicking, or going back, gives a slightly firmer one;
   - Immersive mode gives no menu ticks.

   Say if they are too strong, too weak, or fire on things that are not
   buttons.
9. **Aim down sights by raising the gun (experimental)** (`b2ca404`, option
   default off). Galvanic rifle:
   - raise the gun until the rear sight is in front of your aiming eye: it
     should zoom into aim-down-sights without pressing anything;
   - lower it: back to hip aim;
   - your ADS trigger still works as before, with either the hold or toggle
     ADS game setting.

   This has only been unit tested; the synthetic hands never reached the
   eye. Say if it triggers too easily (while carrying the gun high), too
   late, or not at all, and which eye you aim with.
10. **Holster labels** (`1873f49`, option default off; needs Virtual holsters
    on). Rest a hand at each holster: belt shows blitz charges (for example
    `2/3`), chest the stim or carried item, shoulder the rifle's ammo, hips
    the weapon and device names, "empty" where nothing is kept. Say if the
    labels are in the way or unreadable.
11. **Weapon hand holsters** (`58d37d2`, previews enlarged and moved toward the eye in `e71f21b`; option default off). Gun out:
    - bring your off hand up over the gun hand's forearm: small models of
      your other weapon, stim, carried item and device appear along it
      (only for items you have);
    - put the off hand on one and press grip: that item is equipped (the
      first holster swaps to the other weapon, ranged or melee);
    - move the off hand away: the models disappear.

    Say where the holsters should sit (they start 20 cm behind the grip and
    10 cm above the forearm, 5.5 cm apart), whether the models are too small
    or big, and whether reaching for one ever grabs the wrong one.
12. **Wrist display** (`661d1b6`, option default off). Turn the back of your
    off-hand wrist toward your face as if checking a watch: health (with the
    number), toughness and stamina bars appear there and go away when you
    turn the wrist back. Say if it appears on the wrong side of the hand
    (the facing direction is an assumption), too easily, or too late.
13. **Peril at the hand** (`7ef9e33`; needs "Ammo count at the hand" on). On
    the Psyker with a force staff: charging and venting shows the peril
    percentage beside your weapon hand, white turning red toward overload,
    and nothing at zero peril. Unit tested only (no staff in the unattended
    runs).
14. **Melee charges at the hand** (`6738627`; needs "Ammo count at the hand"
    on). With a melee weapon that has special charges (the arc maul, a
    two-handed force sword, or an axe, crowbar or shivs with charges), the hand readout shows
    charges as `n/max`, blue while the special is active. The Skitarius arc
    maul shows its eight charges (`629c696`): 0/8 right after wielding,
    rising over time and on hits.
15. **Gloves unchanged after the hands refactor** (`9286319`, no option).
    Hand placement now records one final pose per hand, which the weapons'
    hand joints read. With the default gloves, nothing should look or feel
    different:
    - the gun sits in the right glove and aims as before;
    - two-handing puts the left glove on the foregrip;
    - stock melee swings and blocks move the gloves;
    - with a controller switched off (keyboard and mouse), the hands follow
      the stock animation.

    Unattended evidence: wrist and gun grip error 0, and two-hand stats
    identical to before the change. Say if anything about the gloves or
    weapons changed.
16. **Evening fixes** (`76daf2d`; restart the game to load them).
    - **Sight ADS** (option on): raise the rifle's rear sight to your right
      eye. It should zoom with a tick in the gun hand, and lowering the gun
      releases it.
    - **Raising the gun:** no swing on the way up. The sights line up with
      the reticle only once they reach your eye. Say if the reticle is still
      up and left, and look with the eye you sight with.
    - **Virtual stock:** shoulder the rifle and hold still. There should be
      no wiggle, it engages a little deeper, and it releases gently.
    - **Forearm holsters:**
      - 8 cm zones in a line above the forearm, the weapon over the wrist;
      - models all the same size, always visible, staying put as you roll
        the wrist;
      - the one your off hand is in grows and ticks.
    - **Wrist display:** always shown above the off-hand wrist, clear of the
      glove. Health is white, toughness the HUD blue.
    - **Ammo counter:** 5 cm further toward the end of the hand and not
      hidden by the hand or gun.
17. **Evening, second round** (`2e6b874` to `0be5939`; restart to load).
    - **Grip grace:** throw the off hand through the foregrip or a holster
      and press grip on the tick, just after passing. It should still take
      the grip or item, not fire the special.
    - **Sight ADS:** a slightly larger area, and it holds for 0.3 s after
      the sights leave your eye.
    - **Crosshair:** aim down sights once (button or raising the gun) for
      about a second, then check whether the crosshair still sits up and
      left of the sights.
    - **In front of everything:** the ammo counter, wrist bars and holster
      labels should never be hidden by the glove, gun or walls, and should
      not flicker while you walk.
    - **Forearm miniatures:**
      - they turn to face you;
      - they vanish while in line with the reticle;
      - the weapon name shows on hover, and the gun's ammo always shows
        below the gun.
    - **Quitting** should no longer leave a crash dump. The console says
      `destroy_material_skipped` if the guard caught it.
18. **Galvanic rifle clip and case gone** (`6c06ea5`). Hold the rifle
    outside a reload:
    - no cartridge case stands above the grip;
    - no U-shaped clip shows by the drum;
    - both may appear during a reload.
19. **Teammate status above teammates** (`7acaec8`, option off by default).
    In SoloPlay with bots, or a Psykhanium or hub session with others:
    - names with toughness (blue) and health (white) bars float above each
      teammate, readable near and far and through walls;
    - DOWNED or NETTED shows when they need help;
    - their panels leave the team HUD (yours stays).
20. **Reverse grip grace** (`reverse grace` commit after `84609e7`). Press
    grip a moment before the off hand reaches the foregrip or a holster, and
    keep holding as it arrives: it should take the grip or item, and the
    class ability or special should not fire.
    - If the hand never arrives, the ability fires about a quarter second
      late.
    - A quick tap near a zone still fires as a tap.

    Say if that delay is noticeable. It only happens with the hand within
    about 12 cm of the foregrip or 1.5 holster radii.

21. **Maul miniature centred** (`bd2d3a5`). On the forearm holster, the power
    maul should now sit centred in its grab zone at the same height as the
    gun, not about 6 cm above it. Needs a game restart to load.
22. **Gun-relative ammo counter, steady forearm holsters, smaller wrist
    display** (restart the game to load).
    - The ammo counter is placed relative to the gun (beside the receiver,
      just ahead of the hand, toward your midline). It should roll and pitch
      with the gun and stay put on it. Melee charges and staff peril still sit
      beside the hand.
    - The forearm holsters anchor to the controller grip. They should no
      longer move when switching between the gun and other items, or turn and
      flicker while strafing. They hide while two-handing or in ADS (the
      aim-line hide is gone).
    - The wrist display is 25% smaller. New mod option: "Wrist display size
      (%)", 50-200, updates live.
23. **Forearm holsters off in the hub**: no weapon miniature or ammo count
    in the hub; they return in the Psykhanium and SoloPlay.
24. **Holster ammo, refused grabs, medkit grab zone** (Haptics mode on for
    the taps).
    - The gun's ammo count on the forearm holster sits just under the gun
      model.
    - Press grip on a holster whose item you are already holding (the gun at
      the shoulder, the stim while holding the stim): a double tap, and
      nothing else. The special ability must not fire.
    - The medkit's forearm grab zone fits the model (about 11-12 cm across,
      was 8 cm), and the model grows when your hand is in it. Thin items (the
      gun, the stim) keep 8 cm zones or close to it.
25. **Cancel weapon sway** (new option "Cancel weapon sway (%)", default 0).
    Set it to 100 in the Psykhanium. Hold a gun still at a target while
    walking and after sprinting (when stock sway is largest): the crosshair
    and the shots should stay where the gun points, moving only with your
    hand. Try 50 for half the stock sway. Recoil and spread are unchanged.
    The log line `DARKTIDEVR_ONLINE_RULES sway_cancel=` shows it engaged.
26. **Fingertip grabs, wrist display in the cuff, item names** (restart).
    - Reach into a forearm or body holster fingers first: the item should
      activate (grow, tick) as soon as your fingertips are in it, up to 10 cm
      ahead of the palm.
    - The wrist display sits inside the glove's cuff, just past the wrist.
    - With Holster labels on, every forearm item shows its name above it
      while your hand is in it, not just the weapon.

### Results (worn, 15 September, about 19:50)

- 18 clip and case gone: pass.
- 20 reverse grip grace: pass.
- 21 maul centred: pass.
- 22: pass (gun-relative counter, holsters steady on item switch, hidden
  while two-handing and in ADS, wrist size), except the forearm items still
  wobble while strafing. Controller-grip anchoring did not remove it; lead
  in the 16 September todo.
- 23 hub: pass. 24 holster ammo, refused grab, medkit zone: pass. 25 sway
  cancel: pass.
- 26: fingertip grabs pass. The wrist display sat below the wrist, not in the
  cuff (screenshot 19:50: the grip pose's forward tilts with the handle), and
  the stim and medkit showed no name (pocketables have no display name).
- Not yet reported: 19 teammate status, and the earlier items listed in the
  reminder (2, 4, 6, 7, 8, 10, 13, 17).

27. **Wrist display in the cuff (again), pocketable names, holstered
    charges** (restart).
    - The wrist display sits inside the glove's cuff, just past the wrist, now
      placed back along the forearm (the controller's aim).
    - With Holster labels on, the stim, medkit, ammo crate and device show
      their names on hover (from their pickup names).
    - The holstered melee weapon shows its special charges beneath it (for
      example the arc maul's), as the gun shows its ammo; a heat-only gun
      shows its heat. Peril is never shown there.

### Results (worn, 15 September, about 20:10)

- 2 two-handing through reload and bash: pass.
- 4: Hands line "infinitely better"; Classic removed as an option.
- 6 crosshair on the iron sights: pass.
- 7 virtual stock: hard to judge, fine while marked experimental.
- 8 menu ticks: pass; wanted in Immersive too.
- 10 holster labels: pass; body holsters want models too, except the
  shoulder (out of sight), whose zone should be very large.
- 13 peril: to be confirmed.
- 17 grip grace: pass; the two-hand grab should cover the whole gun.

28. **Hands line only, menu ticks in Immersive, grab along the whole gun**
    (restart).
    - "Two-hand steadying" is gone from the options; two-handing always uses
      Hands line.
    - Menu ticks play with vibration on Immersive as well as Informative.
    - With Two-hand support on, the off hand takes the two-hand grip anywhere
      it touches the gun (within 10 cm of the barrel line), from just ahead of
      the gun hand to the muzzle, not only at the foregrip. The glove still
      slides onto the foregrip only when near it. The log line
      `DARKTIDEVR_GUN_AIM muzzle_length` records each gun's length.

29. **Body holster models, extra-large shoulder holster** (Virtual holsters
    on; restart).
    - The hip and chest holsters always show a small model of their item,
      facing you, and it grows while your hand is in the holster. The item
      already in your hand has no model. With Holster labels on, the name
      shows above the hovered model and the count label sits above it.
    - No model at the shoulder or the belt.
    - The shoulder holster is much larger (25 cm radius, centred a little
      further back and out); a hand up by your face or aiming down sights must
      not enter it.

30. **Grab feedback along the whole gun** (restart). Touch the gun with the
    off hand anywhere from just ahead of the gun hand to the muzzle: the
    glove slides onto the foregrip and the controller ticks (vibration on)
    wherever a grip press would take hold, not only near the foregrip.
