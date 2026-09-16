# Changelog

All notable user-facing changes to Darktide VR. Versions follow
`major.minor.patch` with a pre-release suffix while the mod is in alpha; the
runtime package records the exact source revision alongside the version.

## Unreleased

- Worn results of 16 September, in the same evening: the item radial
  picks on the flick (a flick-and-press no longer falls through to the stock
  weapon cycle); push to talk hums faintly on the talking hand while held;
  the melee charge count moves to where the charge bars sit and one
  "Weapon charge display" option chooses count, bars or neither; "Full body
  (experimental)" is in the settings menu; the movement option reads
  "Left-hand-relative"; the flamethrower skull rests on the off-hand side
  (the medical and regular skulls on the other) and every skull follows
  with a small lag instead of sitting rigidly on the body; loading and
  menu boards are re-seated in front of you after a recenter; a sliver of a
  neighbouring cell beside the ammo count is gone.
- Experimental, opt-in, off by default: `darktidevr_gpu_process_priority.flag`
  (`above_normal`, `high` or `realtime`) asks Windows for that GPU
  scheduling class for the game's process; `darktidevr_queue_priority.flag`
  asks for the game's D3D12 queues at high priority. Measured in the Hub on
  16 September: the process class at `high` took a third off the pair's GPU
  time in one run and nothing in two repeats (no demonstrated effect);
  queue priority did nothing. Neither changes anything without its flag.

New, each an experimental option that is off until you turn it on:

- Reach to interact and inspect by bringing the weapon up were built, tried
  worn on 16 September, and withdrawn from the menu: reach is impractical
  (a hand's reach is far shorter than the interaction distance) and inspect
  is pointless with IK hands. Their saved values are ignored.
- **Push to talk with a hand at your mouth.** Bring your off hand up in front
  of your mouth to open your microphone, and take it away to close it. It
  works alongside your push to talk binding, and never while that hand is on
  the gun.
- **Tag what your off hand points at.** Hold your off hand out ahead and press
  tag: the tag leaves that hand instead of your weapon, so you can point
  something out while your gun is aimed elsewhere.

Fixes:

- The neutral eye position the view is built from is measured correctly
  wherever your character happens to be facing when you enter a level. It was
  measured against the recentred play space, so entering a level turned away
  from it lost the forward part of the offset.

## 0.2.0-alpha.1 (15 September 2026)

Fixes:

- Closing the game in VR mode no longer crashes it on the way out.
- The headset view no longer goes dark when a level finishes loading (for
  example entering the Psykhanium), and the headset viewer no longer crashes
  at level load. If the headset viewer ever fails during play, the game starts
  it again.
- Taking the headset off until it sleeps and putting it back on brings the
  view back.
- The crosshair sits closer to a gun's iron sights (it was up and to the left
  of them). Guns other than the galvanic rifle are corrected after about a
  second of aiming down their sights.
- The galvanic rifle no longer shows a stray round, cartridge case or clip at
  the grip outside reloads.
- Flamethrower streams, chain lightning, the force sword's wind slash and the
  shield's windup glow start from the weapon in your hand.
- If a crash wipes the game's settings, run `Darktide VR Mode.bat` and choose
  4 to restore the last good copy; the mod keeps one from every launch.

New option:

- "Cancel weapon sway (%)" (default 0): removes the game's artificial weapon
  sway from your shots, so only your own hands' steadiness counts. Recoil and
  spread are unchanged.

Experimental features (Mod Options, Darktide VR, Experimental features; all
off by default):

- Two-hand support: press grip with your off hand anywhere on a gun, from just
  ahead of your gun hand to the muzzle, to steady it with both hands; available
  as soon as the gun is drawn. The glove slides onto the foregrip and the
  controller ticks as soon as your hand is on the gun, grip can be a hold or a toggle, and it holds through
  reloads and bashes. The gun follows the line between your hands, so turning
  your gun wrist does not swing the barrel off your front hand. "While
  gripping" in the controller bindings gives actions their own controls while
  you hold the gun.
- Virtual stock: bring a two-handed rifle's butt to your shoulder and it rests
  there.
- Aim down sights by raising the gun: bring the sights to your eye to aim down
  them. Works for the galvanic rifle straight away, and for other guns once
  you have aimed down their sights with the button.
- Weapon hand holsters: small models of your other weapon, stim, carried item
  and device above your gun hand's forearm; reach in with the other hand and
  press grip to equip. The one your hand is in grows and ticks (and shows its
  name with "Holster labels" on), the weapon shows its ammo or charges beneath
  it, and they hide while you two-hand or aim down sights. Your hand counts as
  soon as your fingertips reach a model, a grip pressed just before your hand
  arrives or just after it has passed through still counts, and pressing grip
  on the item you are already holding gives a double tap and does nothing
  else.
- Wrist display: health, toughness and stamina bars with their numbers in your
  off-hand glove's cuff, drawn in front of everything, with a size slider. Not
  shown in the hub.
- Teammate status above teammates: each teammate's name, toughness and health
  float above their head at a readable size, with DOWNED, NETTED and similar
  when they need help; their panels leave the team HUD while it is on.
- Ammo count at the hand: clip and reserve on the gun, beside the receiver,
  instead of on the HUD panel, fading from white to red as they run down, with
  a ring that fills while reloading. It draws in front of the hand, gun and
  scene. Heat shows as a percentage, and melee
  weapons with special charges (such as the Skitarius arc maul) show their
  charges.
- Controller vibration, Informative or Immersive, with a strength slider:
  grip and holster feedback, empty clip, reload finished, low ammo, damage,
  knockdown, blocks, stamina, ability recharge, heat, peril and charge, heavy
  attack ready, melee specials, finished interactions and menu ticks, and in
  Immersive every shot (by weapon), melee hit and push.

## 0.1.0-alpha.3 (13 September 2026)

- Menu hotkeys that only had a keyboard key now use controller buttons: E is
  Y, Q is X. On the end of mission screen the right trigger continues and Y
  votes to merge strike teams. No menu prompt shows a keyboard key any more.
- The survival-mode buff choice opens on the menu panel: point at a buff and
  hold the right trigger to pick it.
- Holding the right trigger skips cutscenes and videos again.
- Fixed a crash at the end of a mission.
- A button that selects several items steps through them in turn: device
  (auspex scanner) first, then ammo crate and stim, then back to the weapon
  if quick wield is on the same button. The default Y brings out the scanner
  and cycles on to your carried items.
- Chat shows on the HUD panel at the HUD's size, including when Custom HUD
  had saved a position for it.
- Every weapon and item aims with the same pitch, so the crosshair no longer
  jumps when switching between guns, melee, staffs and blitz. The option is
  now "Aim pitch angle" (default -10).
- The auspex scan hologram sits on the scanner in your hand instead of
  floating in the air.
- Weapon charge meters (such as the Skitarii shock maul's) stay put on the HUD
  panel instead of moving against your head.

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
