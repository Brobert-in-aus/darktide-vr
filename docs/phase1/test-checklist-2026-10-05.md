# Worn test: Darktide 1.13.1 compatibility (5 October 2026)

Build under test: branch `codex/game-patch-1.13-2026-10-05`, head `110035d`,
deployed with `sync-darktide-vr-dev.ps1` (deployment
`c450678072ac4f98a0e9e5ff14fb3680`). Installed binaries match the Release
build by hash (`binaries\d3d12.dll` 81879C3A, native capture 8F2C0F7E, viewer
D2B14597); all 103 installed Lua files match the source. The mod loader was
re-patched and the 1.13.1 executable patched (`executable=patched`,
`build=1.13.1`). Nothing here has run in the game: this pass is the first
time the mod meets 1.13.1.

Launch through Steam as usual. Reply under each heading; a word is enough.

## Replies

(recorded here as they come)

## 1. Does it start in VR at all

Title screen and character select in the headset, in stereo, controllers
pointing. If the game shows flat on the desktop only, or crashes on launch,
stop here and say which: that is the Streamline 2.12 / hook question, and
the logs will say more than further testing.

## 2. Mourningstar

Walk, turn, open the inventory and one vendor, point and click. Anything
that looks different from the 19th.

## 3. Psykhanium: the world

Lights and particles. The game may have recompiled its shaders, and two of
the mod's fixes match shaders by hash: look for **lights that differ between
the eyes** (the cluster-light fix) and **smoke, muzzle flash or sparks that
turn with your head roll or sit at different depths per eye** (the billboard
substitution). Either means the hashes moved.

## 4. Psykhanium: aim and fire

A gun at the dummies: does the shot go where the controller points, and does
the reticle sit on it. Then a melee swing. The game added a raycast
"lock-down" file whose content cannot be read from outside; if aim, the
reticle or reach-to-interact are dead, this is why.

## 5. Your height

Stand straight after loading in. Is your eye height right, as it was on the
19th? The game moved where a character's height is kept and the mod now
reads the new place; if you recalibrate, the log should show
`profile_height accepted` rather than `service_unavailable`.

## 6. Flamer and zealot knives, if you have them to hand

Flamer: does the flame, and what it hits, follow your hand. Zealot throwing
knives: do they leave from your hand rather than your head. Skip either you
cannot reach quickly.

## 7. End of a mission or Psykhanium session, if you get to one

The end screen has new buttons (rate the match, session statistics). Do they
show a controller prompt rather than "[Unbound]", and does **pulling the
right trigger on one of them also skip the screen**? That last one is a
suspected clash, not yet changed.

## 8. Mode switch

After quitting: `Darktide VR Mode.bat`, Flat, then VR again. Both should
finish without an error, and your VR settings should come back.

## Afterwards

Say when the game is closed. The logs to read are the newest
`%APPDATA%\Fatshark\Darktide\console_logs\console-*.log` (DMF "trying to
hook function or method that doesn't exist" lines, `DARKTIDEVR_` lines, the
stereo initialisation and `shared_ready`), the newest
`%LOCALAPPDATA%\DarktideVR\viewer-*.log`, and
`%TEMP%\darktidevr-streamline-probe.tsv`.
