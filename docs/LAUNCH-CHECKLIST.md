# Launch checklist: Darktide VR 0.1.0-alpha.1 on Nexus Mods

Written 12 September 2026. Tick items in order; each group depends on the
one before it. Where an item says "decide", it is the maintainer's call and
the page text or package must reflect the decision.

## 1. Worn acceptance on the release package

The archive to ship is the one whose name carries the final commit. Today
that is `artifacts/packages/darktidevr-0.1.0-alpha.1-8f860f65aeab.zip`
(SHA-256 `877DC95C...`), built from `8f860f6` (full-mission fixes, popups
over cutscene and loading panels, loading and video boards on the
eye-aspect panel, half-length laser with a hit marker on every menu,
F7 auspex check in the Psykhanium; documents reviewed) and installed
over the game folder in the evening. If any item below needs a code change, commit it, rebuild
(`record-component-provenance.ps1 -OutputPath ...` then
`build-runtime-package.ps1 -ReleaseVersion 0.1.0-alpha.1
-ComponentProvenancePath ... -RequireComponentProvenance`), re-run the
verifier and the batch round trip, and update the archive name and hash
here, in the handover and on the Nexus page draft.

- [x] Renamed install carries your settings, bindings and options over
  (the mod id is now `darktidevr`; profiles were migrated on disk).
  Passed 12 September evening.
- [x] Psykhanium onboarding from a fresh character: gun sits in the hand,
  grenade section advances, end-of-training question appears in the
  headset and can be answered with the pointer. Passed 12 September
  (gun placement, popup with laser and cursor, medicrate badge, marker
  step).
- [x] Enter the Psykhanium twice in one session and exit the game from
  the onboarding normally (the two crash guards in 4efe666). Passed 12
  September evening; neither guard fired in that run.
- [x] Aim-down-sights focus: vignette, tighter reticle, steadier aim while
  the sight is held; releases cleanly. Passed 12 September (worn, on
  the published archive).
- [x] Block pose on a melee weapon (shovel or sword). Passed 12 September.
- [x] Tutorial and HUD prompts show controller badges, no keyboard names.
  Passed 12 September.
- [ ] Wide markers and the NPC interaction popup converge at the far edge.
- [x] Damage-direction indicators visible in stereo when hit. Passed 12
  September.
- [x] Quick wield returns to the last weapon; badge reads "[RS Down]".
  Passed 12 September.
- [x] Third-person hub option on and off, including the onboarding hub.
  Passed 12 September.
- [x] Focus warning appears when another window takes focus and clears.
  Passed 12 September.
- [x] One Solo mission start to finish; one remote-server mission if the
  queue allows. Passed 12 September.
- [ ] Flat mode through the batch file, launch flat once, back to VR mode.
- [x] Fresh install as a new user on the maintainer's machine: first-run
  state (no mod settings, no profile directory), archive extracted, batch
  choice 1. Done 12 September 14:24; backup of the previous state kept
  under `%LOCALAPPDATA%`.
- [x] From that fresh install: launch through Steam and the launcher,
  calibration prompt appears, defaults in place, one full mission;
  capture the page's screenshots and video on the way. Done 12 September;
  media in `artifacts/media/2026-09-12/`. Found: device screens blank,
  view lowered after rescue, keyboard prompts in menus, first-person
  spectating, crash returning to the hub. All addressed in the evening
  commits; worn checks below.
- [ ] Worn on the evening fixes: device screen (F7 in the Psykhanium,
  then a real scan), view height after a rescue, third-person
  spectating, prompts in votes and end-of-round tabs, hub return after
  a mission.
- [x] Loading screens and cutscene boards at their true shape (12
  September evening). The pointer's hit marker renders as a dark square:
  shipped as a known limit, post-alpha fix in the todo.

## 2. Documents inside the package

Open the extracted package, not the repository, so what you review is
what ships.

- [x] `README.txt` (from `tools/release/package-README.txt`): install
  steps match the batch file's menu wording ("1  VR mode", "2  Flat
  mode"), paths are the game-folder layout, no dev-only launcher or
  flag-file instructions remain. Reviewed in the extracted 2993ea3
  package, 12 September evening.
- [x] `USER-GUIDE.md`: requirements, install, first run, playing,
  known limits, troubleshooting. The option names it quotes
  ("Aim-down-sights focus", "Third-person body in the hub", "In-engine
  cinematics in stereo") and the switch's status words (patched,
  installed, listed, present) match the localisation and the script.
  Known limits now include the dark-square hit marker.
- [ ] `CHANGELOG.md`: the alpha.1 entry is complete (reviewed; the
  marker entry corrected, the stale 120 Hz line replaced). The heading
  still says "(unreleased)": replace it with the release date on the
  day you publish, rebuild, and update the archive identity here. That
  rebuild also carries the user guide's Custom HUD (continued) wording,
  which postdates the 8f860f6 archive.
- [x] `LICENSE` (MIT) and `THIRD_PARTY_NOTICES.md` present; notices cover
  the OpenXR loader, MinHook, the Streamline ABI, the LuaJIT validator
  and DirectXShaderCompiler, with the DXC licence texts shipped beside
  the binaries.
- [x] The manifest reads 0.1.0-alpha.1 with the built commit;
  `darktidevr.mod` carries no version (DMF descriptors do not).
- [x] No stray files: the archive holds the mod folder only (docs, bin
  with the two feature flags the native module reads, Lua, the switch
  and the patch tool); no logs, settings copies or screenshots.

## 3. Repository and source

- [x] Source is public: the GitHub mirror
  (https://github.com/Brobert-in-aus/darktide-vr, remote `github`) was
  made public on 12 September after the mod was published.
- [x] `main` fast-forwarded to the codex branch head on both remotes
  (12 September).
- [x] Tag `v0.1.0-alpha.1` on `8f860f6`, the commit the published
  archive was built from, pushed to origin and github.
- [ ] The dev launcher, sync script and benchmark tooling stay in the
  repository, not in the package; the package's `tools/` folder holds only
  the executable patch tool that the mode switch calls.

## 4. Nexus Mods page

Draft text is in `docs/NEXUS-PAGE.md`; copy from there, do not retype.

- [ ] Create the mod under Warhammer 40,000: Darktide. Name: Darktide VR.
  Category: Gameplay (or Utilities if a VR category does not exist).
- [ ] Short description and description from the draft; mark it
  **very early alpha** in the first line.
- [ ] Requirements: Darktide Mod Loader, Darktide Mod Framework (link both
  Nexus pages), Virtual Desktop with VDXR, Quest 3, NVIDIA RTX for frame
  generation. Optional: Custom HUD (continued), linked to its Nexus
  page, not the original.
- [ ] Installation section matches the package README word for word.
- [ ] Known limits list matches the user guide.
- [ ] Planned section is on the page (from the draft), so requests for
  work already in the pipeline can be pointed at it.
- [ ] Permissions: as suggested in the draft (credit required for
  redistribution and asset use). Licence: MIT.
- [ ] Upload the archive as the main file, version `0.1.0-alpha.1`,
  file description naming the built commit and the SHA-256.
- [ ] Media: at least two headset screenshots (hub, mission) and one of
  the batch file menu. A short clip of hand-aimed firing if available;
  pull from the Quest with `adb pull /sdcard/Oculus/Screenshots/`.
- [ ] Tags: VR, Gameplay, Utilities; do not tag as "Fair and balanced" or
  similar categories that imply parity with flat play.
- [x] Published on Nexus Mods, 12 September 2026, with the 8f860f6
  archive. The page items above were done by the maintainer; the
  changelog inside that archive still reads "(unreleased)" (the dated
  heading is in the repository from the commit after the tag).

## 5. After publishing

- [ ] Post the change log entry as the first Posts tab message, with
  "very early alpha" and the support expectations.
- [ ] Bug reports: ask for `%LOCALAPPDATA%\DarktideVR\viewer-<pid>.log`,
  the game's `console-*.log` and the GPU/headset/runtime triple; pin a
  post saying so.
- [ ] Decide the update cadence for the first week (fix releases as
  `0.1.0-alpha.2` and so on; each rebuild follows section 1's rebuild
  steps).
- [ ] Watch for a Darktide patch: the executable patch is byte-exact, and
  the batch reports an unrecognised executable rather than patching. A
  game update needs a mod update before VR mode returns.
- [ ] Post-alpha work is listed in `docs/phase1/todo-2026-09-11.md`:
  broad haptics pass, proper two-hand support, remote-mission follow-ups.
