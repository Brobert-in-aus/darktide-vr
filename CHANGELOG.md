# Changelog

All notable user-facing changes to Darktide VR. Versions follow
`major.minor.patch` with a pre-release suffix while the mod is in alpha; the
runtime package records the exact source revision alongside the version.

## 0.1.0-alpha.3 (unreleased)

- Menu hotkeys that only had a keyboard key now use controller buttons: E is
  Y, Q is X. On the end of mission screen the right trigger continues and Y
  votes to merge strike teams. No menu prompt shows a keyboard key any more.
- The survival-mode buff choice opens on the menu panel: point at a buff and
  hold the right trigger to pick it.
- Holding the right trigger skips cutscenes and videos again.
- Fixed a crash at the end of a mission.
- A button shared by the device (auspex scanner) and the carried-item cycle
  now brings out the device whenever one is equipped.
- Chat on the HUD panel is drawn at the HUD's size and has a box in the HUD
  editor.

## 0.1.0-alpha.2 (13 September 2026)

- Experimental keyboard and mouse mode (Mod Options, Experimental features):
  play seated with keyboard and mouse while the headset shows the game. The
  mouse aims within a deadzone and turns the view past its edge, with
  options for horizontal-only mouselook, the deadzone size, a recentre key
  and disabling the controllers.
- World markers, nameplates and interaction popups draw in world space in
  stereo, in front of the scene, at their stock size and layout (option
  "World-surface markers" under Experimental features, on by default).
- The Skitarii servo-skull companion is visible to its owner.
- Cutscenes and videos skip by holding the right trigger.
- Either trigger continues past the title screen.
- The player no longer appears twice in cutscenes.
- The menu button no longer acts as back (B does), so Virtual Desktop's
  double tap works in menus.
- Calibrated height is kept when a character is created or selected.
- HUD panel on/off option in the VR settings.
- Crouch moves to X and carried items to Y, so the thumb can roll from the
  stick onto crouch to slide while sprinting. Saved bindings follow only if
  crouch and carried items were still on their old buttons; changed layouts
  are kept.
- Chat, the notification feed and the other always-on elements show on the
  HUD panel.
- Entering the Psykhanium no longer crashes the game.
- The menu pointer shows its cyan ring-and-cross target at the laser's hit.
- In the third-person hub, opening a menu while moving no longer moves the
  camera.

## 0.1.0-alpha.1 (12 September 2026)

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
- Entering the Psykhanium a second time in one session no longer crashes
  the game, and exiting while an onboarding tutorial is active no longer
  reports a crash. Returning to the hub after a mission no longer
  crashes when the headset transport is briefly silent.
- Device screens (auspex scans, generator and decode minigames) show on
  the third-person device model. F7 opens the scanner display on the
  equipped device for a quick check.
- The view no longer stays lowered after a rescue: the body's eye
  offsets are measured standing, not hanging or knocked down.
- Every prompt the game shows, in menus, notifications and tutorials,
  carries the controller badge or reads Unbound; keyboard keys no longer
  appear. Vote notifications read Unbound: votes cannot be answered in
  VR yet.
- Spectating a teammate after death uses the third-person camera
  (option, on by default).
- Game popups that arrive over a loading screen or a cutscene (the hub's
  "summoned to the strategium" notice) now get the pointer.
- Loading screens and video cutscenes are shown at their true shape
  instead of squashed.
- The menu laser reaches halfway to the panel and a small marker sits at
  the hit on every menu, popup and loading board (the title and
  character screens no longer paint their own). The marker is meant to
  be a cyan ring and cross; in this build it shows as a plain dark
  square, and the laser can look black. Fix planned for the next
  release.

Known limits of this alpha are listed in the user guide: right-hand
dominant presentation, no independent weapon origins on mission servers,
ledge discovery following hand aim, text entry needing a physical keyboard
(the character-name Randomize button works with the pointer), movement
speed following the aim direction, votes unanswerable in VR, and the
game's own performance demands.
