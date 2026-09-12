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
- In-game menus are taken from the game's own canvas, so the desktop window
  can be any size without changing the headset menus or the pointer.
- Optional third-person body in the hub with stick orbit; first person is
  the default. Quick wield returns to the weapon last held.
- In-engine cinematics play in stereo with subtitles on the HUD panel
  (option, on by default). The onboarding hub missions run as the
  third-person hub.
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
- Aim-down-sights focus (option, on by default): a soft vignette, a tighter
  reticle and steadier aim while the sight is held.
- Block on every melee weapon uses the game's guard pose.
- Tutorial and HUD prompts show controller badges. Game questions (for
  example at the end of the Psykhanium onboarding) open in the headset with
  the pointer.
- Wide markers and interaction popups converge per eye, and the
  damage-direction indicators draw on the HUD panel.
- Default controller layout: right trigger fire, left trigger aim or weapon
  alternate, right grip weapon special, left grip combat ability, X carried
  items, Y crouch, A jump and dodge, B blitz, left stick click sprint,
  right stick click tag, right stick up quick wield, right stick down
  interact and reload. All of it can be rebound in the mod options.
- The Psykhanium onboarding runs to completion in VR: it uses the same
  stock-input route as missions (so the gun sits in the hand), the grenade
  section advances, and the end-of-training question appears.
- Tag with nothing under the reticle places a location marker, as the
  middle mouse button does. Prompts for a carried-item slot without its
  own control show the cycle control's badge instead of "Unbound".
- The menu laser and cursor are a fixed dark green; they no longer take
  their colour from the menu image and no longer vanish over popups.

Known limits of this alpha are listed in the user guide: right-hand
dominant presentation, no independent weapon origins on mission servers,
ledge discovery following hand aim, text entry needing a physical keyboard
(the character-name Randomize button works with the pointer), and the
performance guidance for 120 Hz.
