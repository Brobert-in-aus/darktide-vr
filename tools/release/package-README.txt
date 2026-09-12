Darktide VR (early alpha)
=========================

Stereo VR for Warhammer 40,000: Darktide on a Quest 3 through Virtual
Desktop (VDXR). Read USER-GUIDE.md before playing; this file is the short
version.

Requirements
  - Darktide on Steam (Windows), an NVIDIA RTX GPU (frame generation needs
    DLSS Frame Generation; the mod works without it at a lower frame rate).
  - Darktide Mod Loader and Darktide Mod Framework installed and working.
  - Virtual Desktop Streamer with VDXR set as the OpenXR runtime.
  - Quest 3 connected through Virtual Desktop before you launch.

Install
  1. Extract this archive into the Darktide game folder (the folder that
     contains "binaries", "bundle" and "mods"). Afterwards
     mods\darktidevr_stereo_probe must exist beside mods\dmf.
  2. Run mods\darktidevr_stereo_probe\"Darktide VR Mode.bat" and choose
     "1  VR mode". It patches two bytes of Darktide.exe (a pristine copy is
     kept under %LOCALAPPDATA%\DarktideVR), installs the d3d12 proxy and adds
     the mod to mods\mod_load_order.txt. Darktide must be closed.
  3. Launch Darktide through Steam as usual and press Play in the launcher.
     The headset takes over once the game window is up.

Play flat again
  Run the same batch file and choose "2  Flat mode". The original executable
  is restored, the proxy is removed and the mod is taken out of the load
  order. Your other mods are untouched.

After a game update
  Steam replaces Darktide.exe. Run the batch file again and choose VR mode.
  If it reports that the build is not supported yet, wait for a mod update.

Uninstall
  Choose Flat mode, then delete mods\darktidevr_stereo_probe.

Licence: MIT (LICENSE). Third-party components: THIRD_PARTY_NOTICES.md.
