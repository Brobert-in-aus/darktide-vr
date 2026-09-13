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
   changed (cannot be fixed this way): the shout and shield-bash bursts.

4. **Viewer survives the headset sleeping** (`262f6df`, viewer). Take the
   headset off long enough for it to sleep (proximity sensor back on
   automatic by then), put it back on: the game view should come back without
   restarting the game. Viewer log (`%LOCALAPPDATA%\DarktideVR\viewer-<pid>.log`):
   `openxr.session_pause=runtime_stop` then `openxr.session_resume=ready`.
   Before this build the headset stayed dark until the game was restarted.

5. **Virtual holsters, new and off by default** (`baa12ee`, Lua). Design and
   zone table: [virtual-holsters-2026-09-14.md](virtual-holsters-2026-09-14.md).
   First, with the option still off: the grips behave exactly as before
   (special, combat ability, two-hand support). Then turn on Mod Options >
   Darktide VR > Experimental features > Virtual holsters and, in the
   Psykhanium, reach and press grip: over the right shoulder (ranged), left
   hip (melee), left chest (stim), right hip (auspex if carried), right chest
   (carried item). Check nothing triggers while holding a gun, swinging melee
   or reloading. Say which zones feel too high, low, far forward or small.
   Console: `DARKTIDEVR_HOLSTER armed zone=...` and `wield ...` lines.

## Assumptions and questions for the evening review

- Held-item effects (item 3) were deployed on static reading and unit tests
  only: no character with those weapons could be driven unattended. They
  only move effects that already exist; if one looks wrong, the log line
  names the class.
- Virtual holster zone positions (item 5) are first guesses from typical
  body proportions, not measured on the user; no synthetic pose trace was run,
  so only the unit tests show which zone a pose resolves to.
