Darktide VR (early alpha)
=========================

Stereo VR for Warhammer 40,000: Darktide through OpenXR, built and tested
on a Quest 3 through Virtual Desktop (VDXR). Read USER-GUIDE.md before
playing; this file is the short version.

Requirements
  - Darktide on Steam (Windows). The Microsoft Store / Game Pass version is
    expected to work the same way but has not been tested; launch it from
    the Xbox app instead of Steam. Frame generation needs DLSS Frame
    Generation (NVIDIA RTX 40-series or newer); the mod works without it
    at a lower frame rate. Only NVIDIA GPUs have been tested.
  - Darktide Mod Loader and Darktide Mod Framework installed and working.
  - An OpenXR runtime with Direct3D 12 support. Tested: Virtual Desktop
    Streamer with VDXR set as the OpenXR runtime, Quest 3, connected
    before you launch. Other runtimes, headsets and controllers untested.

Install
  1. Extract this archive into the Darktide game folder (the folder that
     contains "binaries", "bundle" and "mods"). Afterwards
     mods\darktidevr must exist beside mods\dmf. Extract it; do not run
     the batch file from inside the zip, which only copies that one file.
  2. Run mods\darktidevr\"Darktide VR Mode.bat" and choose
     "1  VR mode". It patches two bytes of Darktide.exe (a pristine copy is
     kept under %LOCALAPPDATA%\DarktideVR), installs the d3d12 proxy and adds
     the mod to mods\mod_load_order.txt. Darktide must be closed.
  3. Launch Darktide as usual (Steam, or the Xbox app for the Microsoft
     Store / Game Pass version) and press Play in the launcher.
     The headset takes over once the game window is up.

Play flat again
  Run the same batch file and choose "2  Flat mode". The original executable
  is restored, the proxy is removed and the mod is taken out of the load
  order. Your other mods are untouched.

After a game update
  The update replaces Darktide.exe and switches the mod loader off. Run the
  mod loader's toggle_darktide_mods.bat, then this batch file, and choose VR
  mode. The batch file finds the two places it patches in a new executable,
  so a game update normally needs no mod update; if it reports that the
  build is not supported, wait for one. Flat mode always works.

After a mod update
  Extract the new archive over the old one, then run the batch file and
  choose VR mode again; it replaces the earlier proxy and keeps your
  settings.

Uninstall
  Choose Flat mode, then delete mods\darktidevr.

Licence: MIT (LICENSE). Third-party components: THIRD_PARTY_NOTICES.md.
