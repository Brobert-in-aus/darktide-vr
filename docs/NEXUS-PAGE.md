# Nexus Mods page text (12 September 2026; the feature list and the draft
# notes below updated 18 September, for the release after 0.2.0-alpha.1)

Paste-ready sections for the Nexus page. Keep the claims in step with
USER-GUIDE.md; anything not listed under "What works" has not been checked
worn.

## Short description

Native stereo VR for Darktide through OpenXR, built on a Quest 3 with
Virtual Desktop: hand-aimed weapons, controller movement and menus, frame
generation. Very early alpha.

## Description

Darktide VR renders Warhammer 40,000: Darktide in true stereo through
OpenXR, with motion-controller gameplay. It was built and tested on a Quest 3
through Virtual Desktop (VDXR). It installs
like any other Darktide mod and is launched through Steam as usual.

**What works**

- Stereo world rendering, with the game's DLSS Frame Generation when the
  GPU supports it.
- Controller gameplay in the hub, the Psykhanium, Solo missions and on
  ordinary mission servers: movement (head- or hand-relative), snap or
  smooth turning, hand-aimed firing with aim-down-sights focus, button
  melee, throws, interactions, communication wheel, push-to-talk,
  per-action bindings with hub overrides.
- Menus on a flat panel with a controller pointer; a fixed, adjustable HUD
  panel with chat on it; in-engine cutscenes in stereo with subtitles on the
  HUD.
- World markers, nameplates and interaction popups in world space, drawn in
  front of the scene.
- Experimental: seated keyboard and mouse play (see below); two-hand gun
  support with a virtual stock; holsters above the gun hand's forearm;
  ammo, health and teammate status in the world; controller vibration; your
  character's own body under you, with its arms solved to your controllers;
  grabbing and throwing the flamethrower servo skull; an item radial at your
  hand; push to talk by bringing a hand to your mouth; a melee weapon's
  charges at the hand; and a small zoom while you aim down the sights.
- Optional removal of the game's artificial weapon sway, so only your own
  hands' steadiness counts.
- A two-pose calibration that also sets your character's official height.
- Optional third-person body in the hub.
- One batch file switches between VR and flat play and keeps a separate
  copy of your game settings for each.

**Known limits (alpha)**

- Right-hand dominant presentation only.
- Text entry needs a physical keyboard (the character-name Randomize
  button works with the pointer).
- Weapons on mission servers fire from the game's own firing position.
- The game window must keep the desktop focus (a HUD warning tells you).
- Character select and title screens come from the desktop window.
- Movement speed follows the aim direction, not where you look.
- Votes (kick, mission flow) cannot be answered in VR yet.
- Markers pinned to the edge of view, interaction markers and markers
  beyond the eighth on screen can double at their far edge near the edge of
  view.
- Moving chat with the HUD editor is untested; opening chat causes a brief
  stutter.
- Ground previews (such as the Skitarii flamethrower skull's) need Decals on
  in the graphics settings; weapon charge meters sit at the HUD panel's
  centre rather than around the crosshair.
- The game is graphically heavy; expect to lower settings and streaming
  resolution for an acceptable frame rate.
- Tested on one machine (RTX 4090, Quest 3, Virtual Desktop). Other GPUs,
  headsets, runtimes and controllers are untested; controllers other than
  Touch get only the basic OpenXR profile for now.

**Planned** (already in the pipeline, no need to request):

- Two-hand support for staffs and two-handed melee, and left-hand grips.
- Left-hand dominant presentation.
- Bindings for Index, Vive, WMR and Pico controllers; checks on SteamVR,
  Meta Link and other headsets; AMD and Intel verification.
- Independent weapon origins on mission servers and the remaining mission
  actions (rescue, spectating, extraction, reconnect).
- Pointer text entry.
- Performance work on the stereo render cost and frame-generation
  artefacts around HUD objects.

**Keyboard and mouse (experimental)**

Prefer to sit at the desk? Turn on "Keyboard and mouse in VR" under Mod
Options, Darktide VR, Experimental features. The headset shows the game
while keyboard and mouse play it: the mouse moves the reticle inside a
deadzone and turns the view past its edge, and your head carries the
reticle along. Options cover the deadzone size, horizontal-only mouselook
(on by default), a Recentre view key (Z) and ignoring the controllers.
Without controllers, rename the empty `KeyboardMouseOff` file in
`mods\darktidevr` to `KeyboardMouseOn` before launching. Tested in the hub,
the Psykhanium and part of a mission.

## Requirements

- Warhammer 40,000: Darktide on Steam, Windows 10/11 x64.
- Darktide Mod Loader and Darktide Mod Framework (hard requirement).
- An OpenXR runtime with Direct3D 12 support. Tested: Virtual Desktop
  Streamer with VDXR as the runtime, Quest 3.
- NVIDIA RTX 40-series or newer for frame generation (the mod runs without
  it at the native frame rate; other GPUs untested).
- Optional: Custom HUD (continued), for HUD layout editing (tested with
  2.1.6; the original Custom HUD is untested).

## Changelog post: the next release (draft, not published)

Written 18 September and brought up to date on 19 September from what has
actually changed since 0.2.0-alpha.1. Keep it in step with the Unreleased
section of `CHANGELOG.md`, which carries the same text in full; this is the
shortened form for the page.

**New, each experimental and off until you turn it on:** your character's
full body under you, scaled from your calibration, its legs running the
game's own animation and its arms solved to your controllers; grab the
flamethrower servo skull, which locks to your palm and turns with your
hand, and throw it on your own arc; an item radial at your off hand; push
to talk by bringing a hand to your mouth; a melee weapon's special charges
shown at the hand as a count or as the game's own bars; and a small zoom
while you aim down the sights.

**New shortcut:** F8 in the Psykhanium stands a mirror of your character in
front of you, fixed where you summoned it, its head on your headset, its
fingers matching yours and your weapon in its reflected hand, so you can
see what everyone else sees.

**Fixed:** your view stands at your calibrated eye height on load and after
a recenter (it stood about 27 cm high before); the view, hands and weapon
move smoothly every frame instead of stepping at the game's update rate;
loading screens and menus no longer turn or distort when Virtual Desktop's
FOV tangent is below 100 per cent; the aim-down-sights vignette appears at
all, which it never had; a stick flick with the item radial or the
communication wheel open no longer also fires the stick's own binding;
slivers of neighbouring displays beside the ammo count are gone and hand
display text is fitted to its space; the ammo count and the charge display
sit clear of the weapon; servo skulls sit on the right sides and no longer
flicker as you move; your eye is placed correctly whichever way you face on
entering a level.

**Known issues:** cloth on the full body can jiggle; its feet follow the
animation, not the floor, on slopes and steps; the mirror's legs are not
mirrored left for right; a skull thrown away from its target arrives a
moment after the attack begins there.

**Built, tried, withdrawn:** reach to interact, inspect by raising the
weapon, and tag by pointing.

## Changelog post: 0.2.0-alpha.1

For the Nexus changelog and the Posts tab. Matches CHANGELOG.md.

- Fixed: closing the game in VR no longer crashes; the headset view no longer
  goes dark after a level load and the viewer restarts itself if it fails;
  the view returns after the headset sleeps; flamer, chain lightning, wind
  slash and shield glow effects start from your weapon.
- The crosshair sits closer to the iron sights, and the galvanic rifle no
  longer shows stray rounds or parts at the grip.
- New option "Cancel weapon sway (%)": remove the game's artificial sway so
  only your own hands' steadiness counts.
- Settings wiped by a crash? `Darktide VR Mode.bat` option 4 restores the last
  good copy.
- New experimental features (all off by default, Mod Options, Experimental
  features):
  - two-hand support for guns, holding through reloads, with a virtual stock
    and aiming down sights by raising the gun;
  - small item models above your gun hand's forearm to grab from;
  - ammo count on the gun, a health, toughness and stamina display on your
    wrist, and teammate status above teammates, all drawn in front of the
    scene;
  - controller vibration, Informative or Immersive.

## Changelog post: 0.1.0-alpha.3

For the Nexus changelog and the Posts tab. Matches CHANGELOG.md.

- Menus with keyboard-only hotkeys now use controller buttons (E is Y, Q is
  X). On the end of mission screen the right trigger continues.
- The survival-mode buff choice opens on the menu panel: point and hold the
  right trigger to pick.
- The auspex scanner comes out even when its button also cycles your carried
  items; one button steps through scanner, ammo crate and stim in turn.
- Every weapon and item aims with the same pitch, so the crosshair no longer
  jumps when switching (the option is now "Aim pitch angle").
- Chat shows on the HUD panel, including when Custom HUD had saved a position
  for it.
- Fixed: a crash at the end of a mission; holding the right trigger skips
  cutscenes again; the scan hologram sits on the scanner; weapon charge
  meters no longer move against your head.

## Changelog post: 0.1.0-alpha.2

For the Nexus changelog and the Posts tab. Matches CHANGELOG.md.

- New, experimental: keyboard and mouse mode for seated play (Mod Options,
  Experimental features).
- World markers, nameplates and interaction popups now draw in world space,
  in front of the scene, at their normal size and layout.
- Chat and the other always-on messages show on the HUD panel.
- Crouch is on X and carried items on Y, so you can roll your thumb onto
  crouch to slide while sprinting. If you never moved crouch or carried
  items, your bindings switch over too; if you changed them, your layout is
  kept.
- Either trigger continues past the title screen; hold the right trigger to
  skip cutscenes and videos.
- The menu button no longer acts as back (B does), so Virtual Desktop's
  double tap works in menus.
- HUD panel on/off option.
- Fixed: the Skitarii servo-skull is visible to its owner; the player no
  longer appears twice in cutscenes; calibrated height is kept on character
  creation and selection; the menu pointer shows its ring-and-cross target;
  opening a menu while moving in the third-person hub no longer moves the
  camera; entering the Psykhanium no longer crashes.

## Installation

1. Extract the archive into the Darktide game folder (the one with
   `binaries`, `bundle` and `mods`). Everything lands in
   `mods\darktidevr`.
2. With Darktide closed, run `mods\darktidevr\Darktide VR Mode.bat`
   and choose VR mode. It patches two bytes of `Darktide.exe` (a pristine
   copy is kept), installs a `d3d12.dll` proxy and adds the mod to the
   load order.
3. Connect the headset (Virtual Desktop in the tested setup), launch
   Darktide through Steam, press Play.

To play flat, run the batch file and choose Flat mode. After a game update,
run it again and choose VR mode (if the executable is not recognised, wait
for a mod update). After a mod update, extract the new archive over the old
one and choose VR mode again.

## Permissions and licence

MIT licence (see LICENSE in the mod folder). Third-party components and
their licences are listed in THIRD_PARTY_NOTICES.md: Khronos OpenXR loader
(Apache-2.0), MinHook (BSD-2-Clause), Microsoft DirectXShaderCompiler
(LLVM/MIT/MS). No game files are redistributed; the executable patch is
applied to the user's own installed copy and can be reversed.

Suggested Nexus settings: modification and redistribution permitted with
credit; asset use in other mods permitted with credit; no restrictions on
conversion to other games (not applicable); donation points as you prefer.

## Source

Repository link and the commit the archive was built from (the archive
name carries the first twelve characters of that commit).
