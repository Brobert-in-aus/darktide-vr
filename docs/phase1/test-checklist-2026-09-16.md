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
