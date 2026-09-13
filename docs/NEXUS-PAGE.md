# Nexus Mods page text (12 September 2026, updated for 0.1.0-alpha.2 on 13 September)

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
- Experimental: seated keyboard and mouse play (see below).
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
- Chat on the HUD panel is small, and the HUD editor cannot move it yet.
- The game is graphically heavy; expect to lower settings and streaming
  resolution for an acceptable frame rate.
- Tested on one machine (RTX 4090, Quest 3, Virtual Desktop). Other GPUs,
  headsets, runtimes and controllers are untested; controllers other than
  Touch get only the basic OpenXR profile for now.

**Planned** (already in the pipeline, no need to request):

- Haptics pass.
- Proper two-hand weapon support with saved grips.
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

## Changelog post: 0.1.0-alpha.2

For the Nexus changelog and the Posts tab. Matches CHANGELOG.md.

- New, experimental: keyboard and mouse mode for seated play (Mod Options,
  Experimental features).
- World markers, nameplates and interaction popups now draw in world space,
  in front of the scene, at their normal size and layout.
- Chat and the other always-on messages show on the HUD panel.
- Crouch is on X and carried items on Y, so you can roll your thumb onto
  crouch to slide while sprinting. Your saved bindings swap once.
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
