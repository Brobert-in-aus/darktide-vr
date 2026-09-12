# Nexus Mods page text (draft, 12 September 2026)

Paste-ready sections for the Nexus page of the 0.1.0-alpha.1 archive. Keep
the claims in step with USER-GUIDE.md; anything not listed under "What works"
has not been checked worn.

## Short description

Native stereo VR for Darktide on Quest 3 through Virtual Desktop: hand-aimed
weapons, controller movement and menus, frame generation, 120 Hz. Very early
alpha.

## Description

Darktide VR renders Warhammer 40,000: Darktide in true stereo on a Quest 3
through Virtual Desktop (VDXR), with motion-controller gameplay. It installs
like any other Darktide mod and is launched through Steam as usual.

**What works**

- Stereo world rendering with the game's DLSS Frame Generation (120 Hz on
  an RTX 4090 at DLSS Quality).
- Controller gameplay in the hub, the Psykhanium, Solo missions and on
  ordinary mission servers: movement (head- or hand-relative), snap or
  smooth turning, hand-aimed firing, button melee, throws, interactions,
  communication wheel, push-to-talk, per-action bindings with hub
  overrides.
- Menus on a flat panel with a controller pointer; a fixed, adjustable HUD
  panel; in-engine cutscenes in stereo with subtitles on the HUD.
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
- Tested on one machine (RTX 4090, Quest 3, Virtual Desktop). Other GPUs,
  headsets and runtimes are untested.

## Requirements

- Warhammer 40,000: Darktide on Steam, Windows 10/11 x64.
- Darktide Mod Loader and Darktide Mod Framework (hard requirement).
- Virtual Desktop Streamer with VDXR as the OpenXR runtime, Quest 3.
- NVIDIA RTX GPU for frame generation (the mod runs without it at the
  native frame rate).
- Optional: Custom HUD, for HUD layout editing.

## Installation

1. Extract the archive into the Darktide game folder (the one with
   `binaries`, `bundle` and `mods`). Everything lands in
   `mods\darktidevr_stereo_probe`.
2. With Darktide closed, run `mods\darktidevr_stereo_probe\Darktide VR Mode.bat`
   and choose VR mode. It patches two bytes of `Darktide.exe` (a pristine
   copy is kept), installs a `d3d12.dll` proxy and adds the mod to the
   load order.
3. Connect Virtual Desktop, launch Darktide through Steam, press Play.

To play flat, run the batch file and choose Flat mode. After a game update,
run it again and choose VR mode (if the executable is not recognised, wait
for a mod update).

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
