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
   default** (`4d4c1eb` to `e133511`). Turn on Mod Options, Darktide VR,
   Experimental features, Two-hand support. In the Psykhanium, draw a
   two-handed gun and straight away put your left hand where the animation
   normally holds the gun's foregrip and press grip; there should be no wait
   after the draw. Check that:
   - as your left hand comes close to the foregrip (before you press), the
     glove quickly slides onto it, and slides back to your hand if you move
     away without pressing;
   - pressing grip there makes the gun line follow both hands, and moving your
     hands further apart or closer keeps the grip (only bringing them within
     a few centimetres or crossing them lets go);
   - letting go returns the gun to one-handed aim;
   - with Two-hand grip set to Toggle, letting go keeps the grip and the next
     grip press ends it (that press does not fire your combat ability);
   - the left grip does not fire your combat ability while holding;
   - pistols and other one-handed weapons do not offer a grip;
   - if you have other two-handed guns, each gives a grip on its first draw.

   Console: `DARKTIDEVR_TWO_HAND authored_grip template=... source=settled`,
   then `source=measured` for a gun new to this install (the galvanic rifle
   is shipped or already stored, so it logs neither);
   `held=true source=authored grip=shipped|stored|settled|measured`; and on
   each release `released ... max_steer_degrees=...` (how far your support
   hand turned the gun), `mode=hold|toggle` and `ended=released|cancelled`;
   `zone=enter` and `zone=snapped frames=N` as the glove moves on. The
   `authored_grip` lines for your other guns can be copied into the shipped
   table. Say if the grip point is off (further forward or back, higher or
   lower), and whether the slide-on is too fast, too slow or too eager.

9. **Bindings while gripping, new; changes nothing until you set one**
   (`28f9cd7`). Mod Options, Darktide VR, Controller bindings, While
   gripping: every action starts on Same as combat. Pick one to try, for
   example Reload on X, then in the Psykhanium, with Two-hand support on:
   - X crouches normally, and reloads while your left hand holds the
     foregrip;
   - holding X (crouched) as you take the grip keeps you crouched until you
     let go of X, and the same the other way round;
   - actions left on Same as combat (trigger, jump, and so on) behave as
     normal while gripping;
   - the hub and virtual holsters ignore this page.
   Known limit: button prompts on the HUD still show the normal binding while
   gripping. Set the action back to Same as combat afterwards if you do not
   want to keep it.

10. **Controller vibration, new and off by default** (`1ed5c53`, `ff2f66a`;
    plan in [haptics-2026-09-14.md](haptics-2026-09-14.md)). The capture
    library and viewer changed together (presentation state v7): if the
    headset shows nothing at all after launch, say so first. Mod Options,
    Darktide VR, Experimental features, Controller vibration:
    - **Informative:** in the Psykhanium, a light tick as your left hand
      reaches the foregrip (with Two-hand support on) or a hand reaches an
      armed holster (with Virtual holsters on); a firmer pulse as the grip
      takes hold; a strong pulse as the last round leaves the clip; a
      medium one when a reload finishes; no vibration per shot.
    - **Immersive:** the same, except low ammo, plus a pulse on every shot
      (both hands while gripping the foregrip).
    - **Both modes, from 31e1843:** a strong long pulse on both hands when
      knocked down or grabbed; pulses on both hands when you take health
      damage (stronger for bigger hits) or your toughness breaks; a pulse when
      a block takes a hit (firmer for a perfect block). Informative adds low
      health, stamina running out and your combat ability or blitz
      recharging; Immersive adds toughness hits, using your combat ability, each melee hit
      (heavy attacks stronger) and pushes (`e1f4324`). Shots now differ by gun
      (a bolter or shotgun far stronger than a lasgun, a flamer a light buzz;
      `bba5cac`). Heat and peril warn past 75 % in Informative and alert past
      90 % in both; charging a plasma gun, helbore or staff buzzes in Immersive,
      and a full charge ticks in both (`758e885`). Holding a melee attack ticks
      when it will release as a heavy; a power sword's or other melee special
      pulses as it turns on, and hums lightly in Immersive while on (`9e72cd1`). Holding an interaction
      (revive, pick up) hums lightly in Immersive and a finished one pulses in
      both; the new Controller vibration strength slider (25-200 %) scales
      everything (`fcba7a2`). The crosshair scale option's description should
      read normally (it had a stray format sign, `5d03f6e`).
      A mission or the Psykhanium's enemy spawner is needed for most of these.
    - **Off:** nothing.
    Console: `DARKTIDEVR_HAPTICS event=<kind>`; the
    viewer log: `openxr.haptic ... result=0`. Say whether the strengths feel
    right, and read the catalogue: which planned kinds matter most, and
    whether Immersive should also play the Informative-only notices.

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
- Two-hand support: grips from the weapon's animation are now per weapon
  template (every Galvanic Rifle Mk I shares one) and saved between sessions,
  following your note that they should be ready without a delay. Grips from
  `/dtvr_two_hand_calibrate` stay per item and unsaved (your call: never used).
- Toggle grip and hand spacing: with no distance limit, a toggled grip stays
  on while your off hand hangs at your side, and the gun turns to point
  towards it (110 degrees in the unattended run, when the simulated hand went
  back to rest). Should a toggled grip let go past some angle (for example
  45 degrees off the gun hand's aim), or is pressing again enough?
- Bindings while gripping (item 9): built as a layer over combat bindings
  that inherits by default, rather than a full separate layout, so nothing
  has to be rebound to start using it. Prompts do not follow it yet. Should
  the support hand's own buttons get suggested defaults while gripping?
- Haptics modes (item 10): Immersive is not a superset. It leaves out
  abstract notices (low ammo, recharged abilities, menu ticks) so that its
  pulses are always about your hands or body. Kinds in both modes: grip zone,
  grip taken, clip empty, reload finished. The full catalogue with planned
  kinds is in `haptics-2026-09-14.md`.
