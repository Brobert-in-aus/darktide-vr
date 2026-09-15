# Evening checklist, 15 September 2026

Everything deployed today, on branch `codex/alpha-4-2026-09-14`. Evidence is in
the [session handover](../handoffs/2026-09-15-unattended-session.md).
Yesterday's checklist items not reached are still open in
[test-checklist-2026-09-14.md](test-checklist-2026-09-14.md) (items 1, 3, 4,
5, 7, 9).

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
11. **Weapon hand holsters** (`58d37d2`, option default off). Gun out:
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
