# Unattended session brief: 14 September 2026

Written 13 September after the 0.1.0-alpha.3 publication. The user is at
work for the whole session and cannot answer questions or wear the headset.
Work the queue in [todo-2026-09-14.md](../phase1/todo-2026-09-14.md) in
order, as far as evidence allows, and leave a clean, documented state for
an evening worn check.

## Starting state

- Repository: branch `codex/alpha-4-2026-09-14` at `5d1e7ca` (same as
  `main` on origin and github). Tag `v0.1.0-alpha.3` on `8bc5940`.
- Installed game: the alpha.3 package
  (`artifacts/packages/darktidevr-0.1.0-alpha.3-8bc59403fcd8.zip`) extracted
  over `D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE`, VR mode,
  `settings_profile=vr`. `user_settings.config` has `decals_enabled = true`;
  the pre-change copy is `user_settings.config.before-decals.bak`.
- Custom HUD (continued) is installed and has a saved chat pin; the mod
  rewrites it on the panel only (see the chat item in the 11 September todo).
- Known: the game crashes on every shutdown (first queue item).

## Boundaries

- Stay local: hub, Psykhanium, and offline SoloPlay missions only. No
  matchmaking, public missions or strike-team joins.
- Do not publish: no changes to `main`, no tags, no GitHub releases, no
  Nexus. Commit and push only `codex/alpha-4-2026-09-14`, to origin and
  github, after each accepted change. Never force-push.
- Do not change graphics or game settings, bindings, or other mods' saved
  settings. A flat-mode control run (batch choice 2) is allowed for the
  shutdown-crash item; always finish with batch choice 1 and a status run
  reading `settings_profile=vr`, and confirm `decals_enabled = true` survived.
- Keep logs, dumps, captures and settings copies out of Git (`artifacts/` is
  ignored). The public mirror must not receive private data.
- Deploy to the installed mod only committed, test-passing changes, copying
  the changed files. Before copying, diff each installed file against the
  source (strip CR on both sides); another checkout may have written there.
- Worn acceptance is the user's. State every result with its limit
  ("unattended numeric trace, not worn visual acceptance").

## Start of session

1. `git status` clean on the branch; record `git rev-parse HEAD`.
2. Record SHA-256 of the installed `mods\darktidevr` Lua files, `bin`
   binaries and `binaries\d3d12.dll` (compare with the alpha.3 package tree
   `artifacts/packages/darktidevr-0.1.0-alpha.3-8bc59403fcd8`).
3. Offline work (static reads, Lua edits, tests) needs no headset. Before any
   game launch: `tools/quest/set-proximity-override.ps1 -Action Disable`,
   `-Action Status`, then `tools/unattended/invoke-unattended-preflight.ps1`
   (default Ready mode). If the headset is unavailable (`hmd-unavailable`),
   the OpenXR simulator fallback used by the 11 September wrappers
   (`artifacts/unattended/sim-*.ps1`, swapping the simulator DLL and
   restoring it in `finally`) is the established alternative; record which
   runtime each run used.
4. Suite: `ctest --test-dir build/windows-vs2022 -C Release -j 8
   --output-on-failure` (ctest path in the tooling memory:
   `C:/Program Files/Microsoft Visual Studio/2022/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/ctest.exe`).
   `mode_switch` fails while Darktide runs; rerun it with the game closed.

## Running the game unattended

- Standard launch: `Start-Process steam://rungameid/1361210`, then
  `tools/stereo/invoke-darktide-launcher-play.ps1`; the game starts the
  viewer itself (`%LOCALAPPDATA%\DarktideVR\viewer-<pid>.log`). Console logs:
  `%APPDATA%\Fatshark\Darktide\console_logs\`.
- Psykhanium entry: the development launcher's `-EnterPsykhanium` (armed
  while the game is closed, per AGENTS.md) predates the game-started viewer;
  confirm it still works on this install before relying on it, or add a
  test-only entry path behind a flag file that defaults off.
- In-game checks that need a scanner: `/dtvr_scan_test` in the Psykhanium
  (gives the scanning auspex and stands in for a scanning zone); F7 opens
  the device display. Chat commands cannot be typed unattended; drive test
  actions through flag files polled by the mod, default off, removed or
  documented before the session ends.
- After each run: collect the console and viewer logs into
  `artifacts/unattended/<topic>-20260914/`, close any crash dialog without
  submitting, and confirm no Darktide or viewer process remains.

## Stop conditions

- The same crash reproduced twice with matching logs: stop that experiment,
  restore the last accepted installed files, move to the next item.
- A D3D12 device removal or hang in an experiment: restore, record, do not
  retry that change unattended.
- XR readiness still failing after one clean retry and the recovery steps in
  `docs/phase1/unattended-development-plan-2026-08-26.md`: continue with
  offline work only.
- The executable is reported unrecognised (game update): stop live work and
  record it; the patch needs updating with the user.

## End of session

1. Game and viewer closed. `Darktide VR Mode.bat` status (choice 3): patched,
   installed, listed, present, `settings_profile=vr`.
2. Installed mod: either the branch head's accepted files (list each file and
   hash in the handover) or, if anything deployed is unstable, the alpha.3
   package restored (extract the zip over the game folder, batch choice 1)
   with every file matching the package.
3. Quest proximity automation restored:
   `tools/quest/set-proximity-override.ps1 -Action Enable`, then `-Action
   Status`, per AGENTS.md.
4. Write `docs/handoffs/2026-09-14-unattended-session.md`: per item, what was
   done, commits, validation commands and results, evidence paths, limits.
5. Write `docs/phase1/test-checklist-2026-09-14.md`: the specific worn checks
   for the evening, in the order they should be tried, each with what to
   look for and the log line that confirms it.
6. Update the todo, commit, push the branch to both remotes.
