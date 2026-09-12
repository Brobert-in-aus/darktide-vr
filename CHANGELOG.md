# Changelog

All notable user-facing changes to Darktide VR. Versions follow
`major.minor.patch` with a pre-release suffix while the mod is in alpha; the
runtime package records the exact source revision alongside the version.

## 0.1.0-alpha.1 (unreleased)

First public early-alpha candidate. Windows x64, Quest 3 through Virtual
Desktop (VDXR), Darktide with the Darktide Mod Framework.

- Installs like an ordinary mod: extract into the game folder, run
  `Darktide VR Mode.bat` once for VR mode (executable patch with a pristine
  backup, d3d12 proxy, load-order entry), then launch through Steam. Flat
  mode restores everything. Each mode keeps its own copy of the game's
  settings file, so VR video settings and bindings do not disturb flat play.
- The game starts the headset viewer itself; there is no launcher script,
  no automated Play press and no readiness preflight.
- Stereo rendering of the game world with the mod's own OpenXR viewer, and
  frame generation through the game's DLSS Frame Generation when it is on.
- A HUD warning while the game window has lost the desktop focus (frame
  generation and controller input pause until it is focused again); can be
  turned off in the HUD options.
- Flat panels for menus, loading and cinematics; controller pointer input
  in menus; a fixed HUD panel with size, distance and scale options.
- Controller-driven gameplay in the hub, in the Psykhanium, in SoloPlay
  missions and on remote mission servers: movement, turning, buttons,
  hand-aimed firing through the game's own firing position, button melee,
  throws, interactions, communication wheel and push-to-talk.
- Body and hand presentation following the controllers, with a two-pose
  calibration (T-pose, arms at the sides) that also sets the official
  character height.
- Recovery when the DLSS quality is changed in-game, when the engine turns
  generation off (mission intros, the in-game FG toggle) and across mission
  loads.

Known limits of this alpha are listed in the user guide: right-hand
dominant presentation, no independent weapon origins on mission servers,
ledge discovery following hand aim, text entry needing a physical keyboard
(the character-name Randomize button works with the pointer), and the
performance guidance for 120 Hz.
