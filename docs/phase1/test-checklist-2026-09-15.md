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
