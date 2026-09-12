# Launch checklist: Darktide VR 0.1.0-alpha.1 on Nexus Mods

Written 12 September 2026. Tick items in order; each group depends on the
one before it. Where an item says "decide", it is the maintainer's call and
the page text or package must reflect the decision.

## 1. Worn acceptance on the release package

The archive to ship is the one whose name carries the final commit. Today
that is `artifacts/packages/darktidevr-0.1.0-alpha.1-06b662c2b662.zip`
(SHA-256 `8C9264D1...`), built from `06b662c` and installed over the game
folder in the afternoon. If any item below needs a code change, commit it, rebuild
(`record-component-provenance.ps1 -OutputPath ...` then
`build-runtime-package.ps1 -ReleaseVersion 0.1.0-alpha.1
-ComponentProvenancePath ... -RequireComponentProvenance`), re-run the
verifier and the batch round trip, and update the archive name and hash
here, in the handover and on the Nexus page draft.

- [ ] Psykhanium onboarding from a fresh character: gun sits in the hand,
  grenade section advances, end-of-training question appears in the
  headset and can be answered with the pointer.
- [ ] Aim-down-sights focus: vignette, tighter reticle, steadier aim while
  the sight is held; releases cleanly.
- [ ] Block pose on a melee weapon (shovel or sword).
- [ ] Tutorial and HUD prompts show controller badges, no keyboard names.
- [ ] Wide markers and the NPC interaction popup converge at the far edge.
- [ ] Damage-direction indicators visible in stereo when hit.
- [ ] Quick wield returns to the last weapon; badge reads "[RS Down]".
- [ ] Third-person hub option on and off, including the onboarding hub.
- [ ] Focus warning appears when another window takes focus and clears.
- [ ] One Solo mission start to finish; one remote-server mission if the
  queue allows.
- [ ] Flat mode through the batch file, launch flat once, back to VR mode.

## 2. Documents inside the package

Open the extracted package, not the repository, so what you review is
what ships.

- [ ] `README.txt` (from `tools/release/package-README.txt`): install
  steps match the batch file's menu wording, paths are the game-folder
  layout, no dev-only launcher or flag-file instructions remain.
- [ ] `USER-GUIDE.md`: requirements, install, first run, playing,
  known limits, troubleshooting. Check every option name against the mod
  options menu as displayed in-game.
- [ ] `CHANGELOG.md`: the alpha.1 entry is complete and says "unreleased"
  nowhere once the release date is set.
- [ ] `LICENSE` (MIT) and `THIRD_PARTY_NOTICES.md` present; notices cover
  the OpenXR loader, MinHook and DirectXShaderCompiler with their texts.
- [ ] `darktidevr.mod` and the manifest name and version read
  0.1.0-alpha.1.
- [ ] No stray files: no test flags, logs, personal settings copies or
  screenshots in the archive (compare against `runtime-package-files.psd1`).

## 3. Repository and source

- [ ] Decide where the source lives publicly. The origin is a private
  Forgejo instance; the Nexus page's Source section expects a link. Either
  push a public mirror (GitHub) at the release commit and tag it
  `v0.1.0-alpha.1`, or drop the Source section and say the source is
  available on request.
- [ ] Tag the release commit in the origin repository as well.
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
  generation. Optional: Custom HUD.
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
- [ ] Set the mod page to hidden until sections 1 to 3 are ticked, then
  publish.

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
