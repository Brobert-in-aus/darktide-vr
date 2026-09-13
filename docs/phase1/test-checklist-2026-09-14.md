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

## Assumptions and questions for the evening review

- (none yet)
