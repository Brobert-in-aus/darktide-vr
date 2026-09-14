# Evening worn checklist: 14 September 2026

Built up during the unattended session as each change is installed. Try the
items in order. Everything here was installed without a headset check; the
unattended evidence for each is in
[the session handover](../handoffs/2026-09-14-unattended-session.md).

## Installed today

1. **Nothing to see: unattended run controls** (`bb10184`). Two request files players never have:
   `darktidevr_external_viewer.flag` (the game skips starting its viewer) and
   `darktidevr_quit_game.flag` (quits through the in-game Quit route).
   Check: launch normally; the headset shows the game as before (the viewer
   still starts; console log `DARKTIDEVR_VIEWER control=start accepted`, and
   no `start=skipped`). If the headset stays dark, delete
   `mods\darktidevr\darktidevr_external_viewer.flag` if it exists.

2. **Closing the game no longer crashes** (`783284b`: new native module and
   Lua). Play normally, then quit (in-game Quit, or close the window). Expect
   no crash report or "Darktide has stopped" dialog. The console log should
   end with `DARKTIDEVR_EXIT prepared ... native_hooks=16` or `=20` followed
   by `[Log end]`, and no `<<Crash>>`. If the headset view freezes for a
   moment as you quit, that is the viewer being stopped first.

3. **Held-item effects follow the hand** (`68e4ff8`, Lua). The scan
   hologram's late placement now also covers the flamer stream, chain
   lightning (hand effects and the links from the hand), the force sword's
   wind slash activation and the riot shield's windup glow. Check whichever
   of those your characters have: fire the flamer, hold the psyker's chain
   lightning or smite charge, use the force sword special, brace the shield,
   and look for the effect starting at the gun or hand rather than a little
   away from it. Console log: one `DARKTIDEVR_HELD_EFFECTS placed class=...`
   line per effect type, and no `DARKTIDEVR_SCANNER_HOLO fallback=` line. Not
   changed (cannot be fixed this way): the shout and shield-bash bursts. A
   Psykhanium run placed the chain lightning links with no fallback.

4. **Headset no longer goes dark entering the Psykhanium; the viewer restarts
   if it fails** (`7f790f4` viewer, `c0913f3` Lua, `177bd16` native). The
   viewer died at the loading → gameplay switch on every unattended
   Psykhanium entry (the menu copy box described the new canvas before the
   menu texture changed). That is fixed, and the game now also restarts a
   viewer that fails, up to three times in about five minutes.
   - Enter the Psykhanium and a mission: the view should stay up through
     loading.
   - If the headset ever goes dark mid-game, it should come back within a few
     seconds. The console log then shows
     `DARKTIDEVR_VIEWER restart=automatic`; please note when.
   - Headset off until it sleeps, then back on: the view should return
     (`openxr.session_pause=runtime_stop`, then `session_resume`). This part
     is checked only on the simulator.

5. **Virtual holsters, new and off by default** (`baa12ee`, Lua). Design and
   zone table: [virtual-holsters-2026-09-14.md](virtual-holsters-2026-09-14.md).
   First, with the option still off: the grips behave exactly as before
   (special, combat ability, two-hand support). Then turn on Mod Options >
   Darktide VR > Experimental features > Virtual holsters and, in the
   Psykhanium, reach and press grip: over the right shoulder (ranged), left
   hip (melee), left chest (stim), right hip (auspex if carried), right chest
   (carried item), and the front of the belt: hold grip to draw and aim the
   blitz, let go to throw (`4571e85`). Check nothing triggers while holding a
   gun, swinging melee or reloading. Say which zones feel too high, low, far forward or small.
   Console: `DARKTIDEVR_HOLSTER armed zone=...` and `wield ...` lines.

6. **Ammo count at the hand, new and off by default** (`ecec404` to
   `20fe0ae`, Lua). Turn on Mod Options, Darktide VR, Experimental features,
   Ammo count at the hand. In the Psykhanium with a gun out:
   - the clip count shows large just above and inside the weapon hand, facing
     you, with the reserve small beneath it;
   - the panel's weapon block for the gun is gone;
   - each number is white at its own capacity and fades through yellow and
     orange to red at 0 as you fire (the reserve on its own capacity);
   - reloading fills a solid ring around the count, smoothly, over a dim
     track;
   - sprinting or swapping mid-reload shakes the count and the ring
     disappears;
   - plasma or staff heat shows as a percentage.

   Say if it is too big, too close or in the way of the sights.

7. **Optional, five minutes: record pose traces for the body IK work**
   (`a506d9e`). Before launching, create
   `mods\darktidevr\darktidevr_pose_trace.flag` containing `record`. In the
   Psykhanium, do each for about 20 seconds:
   - stand and look around;
   - crouch and stand a few times;
   - lean over something;
   - reach high and low;
   - hold a gun two-handed;
   - swing melee;
   - walk, strafe and walk backwards;
   - turn on the spot;
   - sprint and slide.

   Then delete the flag (the recording stops within a second) and leave
   `darktidevr_pose_trace.csv` where it is for the next session.

8. **Two-hand support with the weapon's own foregrip, new and off by
   default** (`4d4c1eb` to `a2fff7c`). Turn on Mod Options, Darktide VR,
   Experimental features, Two-hand support. In the Psykhanium with a
   two-handed gun, hold for a second without firing (the grip is measured
   then), then put your left hand where the animation normally holds the
   gun's foregrip and press grip. Check that:
   - the left glove snaps onto the foregrip and the gun line follows both
     hands;
   - letting go returns the gun to one-handed aim;
   - the left grip does not fire your combat ability while holding;
   - pistols and other one-handed weapons do not offer a grip.

   Console: `DARKTIDEVR_TWO_HAND authored_grip template=... socket=...`,
   `held=true source=authored`, and on each release `released ...
   max_steer_degrees=...` (how far your support hand turned the gun). Say if the grip point is off (further forward
   or back, higher or lower), and whether gripping should also aim down
   sights.
## Assumptions and questions for the evening review

- Held-item effects (item 3) were deployed on static reading and unit tests
  only: no character with those weapons could be driven unattended. They
  only move effects that already exist; if one looks wrong, the log line
  names the class.
- Virtual holster zone positions (item 5) are first guesses from typical
  body proportions, not measured on the user. A synthetic reach run showed the
  shoulder and left hip zones wielding the ranged and melee weapons in game;
  the stim, carried-item and device zones only resolved (that character had
  none).
- Chat-close hitch: measured as the stock game's own with DLSS Frame
  Generation on (flat, no mod: 125 ms). Recorded as a known issue tied to
  frame generation on your pointer; not confirmed with frame generation off,
  because graphics settings were not touched. Want a flat run with it off?
- Two-hand support: should a recorded support grip be saved and reused for
  every weapon of the same template (for example all Lasgun Mk IIIs), or per
  item? Today it is per item and lost when the game closes, and a test keeps a
  different item from inheriting a grip.
- Two-hand authored grips never trigger ADS; the calibrated prototype did
  (grip = hold alternate) on weapons whose ADS is a plain hold. Which should
  the foregrip do?
