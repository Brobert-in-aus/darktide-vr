# Darktide VR user guide (early alpha)

Darktide VR presents Warhammer 40,000: Darktide in stereo on a Quest 3 through
Virtual Desktop, with controller input in menus and gameplay. It is an early
alpha: it works for the people who built it, on their hardware, and it will
have rough edges on yours. Read the "Known limits" section before you judge it.

## What you need

- Windows 10 or 11, x64. Darktide installed through Steam.
- An NVIDIA RTX GPU. Frame generation uses the game's own DLSS Frame
  Generation and is what makes 120 Hz reachable; without it the mod still
  works at whatever frame rate the GPU renders two 2112x2304 eyes.
- The Darktide Mod Loader and the Darktide Mod Framework (DMF), installed
  and working: with them alone, the game should start and show "Mods" in its
  options. Install those first, from their own Nexus pages.
- A Quest 3, Virtual Desktop on the headset, Virtual Desktop Streamer on the
  PC, and VDXR selected as the OpenXR runtime in the Streamer's settings.
- Optional: the Custom HUD mod, which the VR mod uses for HUD layout
  editing. Everything else works without it.

## Install

1. Extract the archive into the Darktide game folder, the one that contains
   `binaries`, `bundle` and `mods`. When you are done,
   `mods\darktidevr_stereo_probe` sits beside `mods\dmf`; the archive adds
   nothing outside that folder.
2. Close Darktide. Run `mods\darktidevr_stereo_probe\Darktide VR Mode.bat`
   and choose **1, VR mode**. The switch does three things:
   - patches two bytes of `binaries\Darktide.exe` so the game accepts the
     stereo camera (a pristine copy is kept under `%LOCALAPPDATA%\DarktideVR`);
   - places the mod's `d3d12.dll` proxy in `binaries`, which is how the VR
     module gets into the game;
   - adds `darktidevr_stereo_probe` to `mods\mod_load_order.txt`.
   It prints a status block at the end; every line should read patched,
   installed, listed and present.
3. Put the headset on, connect Virtual Desktop to the PC, then launch
   Darktide through Steam and press Play in the Fatshark launcher. Nothing
   else is needed. The desktop window comes up as usual; a few seconds later
   the headset shows the game.

To play flat again, run the batch file and choose **2, Flat mode**. It
restores the original executable, removes the proxy and takes the mod out of
the load order. The mod folder and your other mods stay where they are.

After Steam updates the game, run the batch file again and choose VR mode.
If it says the build is not supported yet, the executable changed and the
patch needs an update from us.

## First run

- The mod forces the game into a window and leaves its size to you; the
  headset renders at the headset's resolution regardless, and in-game menus
  are taken from the game's own canvas rather than the window. Only the
  character-select and title screens still come from the window, so keep
  it at least 1280x720 for readable text there. Fullscreen is switched off
  at every start while VR mode is on.
- On the character-select screen the **VR calibration** opens by itself the
  first time. Stand or sit as you will play, follow the two poses (arms out
  in a T, then arms at your sides) and save. Your official character height
  is set from it. Repeat it any time from the same screen's button or with
  the chat command `/dtvr_calibration`.
- Menus use the right controller as a pointer. Trigger selects, the sticks
  scroll. Text entry needs a physical keyboard; the character-name Randomize
  button works with the pointer.
- Set DLSS and Frame Generation in the game's own video options. Quality
  DLSS with Frame Generation on is the accepted setting on an RTX 4090.
  Changing DLSS quality in-game is fine; frame generation recovers.
- Turn V-Sync off and cap nothing. Virtual Desktop: 120 Hz, resolution one
  step below the top, H.264+.

## Playing

- Movement follows the head by default (or the left hand, in the mod
  options), turning is snap or smooth on the right stick, and buttons can be
  rebound per action in Mod Options, Darktide VR.
- Firing follows the right hand. Aim stabilisation and the crosshair size are
  adjustable. Melee is on a button; a swing preview can be toggled with F6.
- The hub is first person by default; "Third-person body in the hub" shows
  the stock character instead, with the right stick orbiting the camera.
- The HUD sits on a fixed panel in front of you; size, distance and text
  scale are in the options. With Custom HUD installed, the layout editor
  opens in the desktop window from the same options group.
- The game window must keep the desktop focus. If another window takes it,
  frame generation and controller input stop and the HUD shows a warning
  (it can be turned off in the HUD options). Click the Darktide window to
  continue.
- Everything works in the hub, the Psykhanium, Solo missions and on ordinary
  mission servers.

## Known limits of this alpha

- Right-hand dominant presentation only.
- Weapons on mission servers fire from the game's own firing position, not
  from an independent hand origin.
- Ledge discovery follows hand aim.
- Text entry needs a physical keyboard, including the character name on
  creation (the Randomize button works with the pointer).
- In-engine cutscenes play in stereo with the cinematic camera moving you;
  turn "In-engine cinematics in stereo" off if the cuts and camera moves
  are uncomfortable (they then show on the flat panel, without picture).
- The two onboarding hub missions after the prologue run as the
  third-person hub (the game forces that camera there); this route has had
  little testing.
- The desktop window must stay focused (see above).
- Lower-tier GPUs have not been tested; the accepted numbers come from an
  RTX 4090 at 120 Hz.

## When something goes wrong

- Logs: `%LOCALAPPDATA%\DarktideVR\viewer-<pid>.log` is the headset viewer;
  `%APPDATA%\Fatshark\Darktide\console_logs` holds the game log with lines
  starting `DARKTIDEVR_`; `binaries\darktidevr-d3d12-bootstrap.log` records
  whether the module loaded.
- The headset stays black but the desktop shows the game: check that VDXR is
  the active OpenXR runtime and Virtual Desktop was connected before launch.
  The chat command `/dtvr_viewer restart` starts the viewer again.
- The game runs flat and the mod menu is missing: DMF is not loading; fix
  the mod loader first (mods disable themselves after game updates).
- The batch file reports an unknown executable hash: the game updated, and
  the patch needs a new version of the mod.

Licence: MIT. Third-party notices in `THIRD_PARTY_NOTICES.md`.
