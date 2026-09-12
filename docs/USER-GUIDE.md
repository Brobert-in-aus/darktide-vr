# Darktide VR user guide (early alpha)

Darktide VR presents Warhammer 40,000: Darktide in stereo through OpenXR,
with controller input in menus and gameplay. It has been built and tested on
a Quest 3 through Virtual Desktop. It is an early
alpha: it works for the people who built it, on their hardware, and it will
have rough edges on yours. Read the "Known limits" section before you judge it.

## What you need

- Windows 10 or 11, x64. Darktide installed through Steam.
- A GPU that runs Darktide comfortably flat. Frame generation uses the
  game's own DLSS Frame Generation, so it needs an NVIDIA RTX 40-series or
  newer; without it the mod runs at whatever rate the GPU renders two eyes.
  Only NVIDIA GPUs have been tested.
- The Darktide Mod Loader and the Darktide Mod Framework (DMF), installed
  and working: with them alone, the game should start and show "Mods" in its
  options. Install those first, from their own Nexus pages.
- An OpenXR runtime with Direct3D 12 support and a headset with Touch-style
  controllers. The tested setup is a Quest 3 with Virtual Desktop on the
  headset, Virtual Desktop Streamer on the PC, and VDXR selected as the
  OpenXR runtime in the Streamer's settings. SteamVR, Meta Link and other
  runtimes and headsets are untested; controllers other than Touch fall back
  to the basic OpenXR profile (select and menu only) until their bindings
  are added.
- Optional: the Custom HUD mod, which the VR mod uses for HUD layout
  editing. Everything else works without it.

## Install

1. Extract the archive into the Darktide game folder, the one that contains
   `binaries`, `bundle` and `mods`. When you are done,
   `mods\darktidevr` sits beside `mods\dmf`; the archive adds
   nothing outside that folder.
2. Close Darktide. Run `mods\darktidevr\Darktide VR Mode.bat`
   and choose **1, VR mode**. The switch does three things:
   - patches two bytes of `binaries\Darktide.exe` so the game accepts the
     stereo camera (a pristine copy is kept under `%LOCALAPPDATA%\DarktideVR`);
   - places the mod's `d3d12.dll` proxy in `binaries`, which is how the VR
     module gets into the game;
   - adds `darktidevr` to `mods\mod_load_order.txt`.
   It prints a status block at the end; every line should read patched,
   installed, listed and present.
3. Put the headset on, connect it to the PC (Virtual Desktop in the tested
   setup), then launch
   Darktide through Steam and press Play in the Fatshark launcher. Nothing
   else is needed. The desktop window comes up as usual; a few seconds later
   the headset shows the game.

To play flat again, run the batch file and choose **2, Flat mode**. It
restores the original executable, removes the proxy and takes the mod out of
the load order. The mod folder and your other mods stay where they are.

After Steam updates the game, run the batch file again and choose VR mode.
After a mod update, extract the new archive over the old one and do the
same; the switch replaces the earlier proxy and keeps your settings.
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
- Turn V-Sync off and cap nothing. The game is graphically heavy: expect
  to lower the game's settings and the headset's streaming resolution to
  reach a frame rate you find acceptable, and choose the refresh rate
  yourself.

## Playing

- Movement follows the head by default (or the left hand, in the mod
  options), turning is snap or smooth on the right stick, and buttons can be
  rebound per action in Mod Options, Darktide VR.
- Default layout: right trigger fires, left trigger aims (or the weapon's
  alternate), right grip is the weapon special, left grip the combat
  ability, X cycles carried items, Y crouches, A jumps and dodges, B is the
  blitz, clicking the left stick sprints, clicking the right stick tags,
  right stick up switches weapon and right stick down interacts and
  reloads. Tutorial and HUD prompts show these badges.
- Firing follows the right hand. Aim stabilisation and the crosshair size are
  adjustable. Holding the sight dims the edges, tightens the reticle and
  steadies the aim ("Aim-down-sights focus" in the options). Melee is on a
  button, block uses the game's guard pose, and a swing preview can be
  toggled with F6.
- The hub is first person by default; "Third-person body in the hub" shows
  the stock character instead, with the right stick orbiting the camera.
- The HUD sits on a fixed panel in front of you; size, distance and text
  scale are in the options. With Custom HUD installed, the layout editor
  opens in the desktop window from the same options group.
- The game window must keep the desktop focus. If another window takes it,
  frame generation and controller input stop and the HUD shows a warning
  (it can be turned off in the HUD options). Click the Darktide window to
  continue.
- Everything works in the hub, the Psykhanium (including the onboarding
  tutorial), Solo missions and on ordinary mission servers. Game questions
  such as the end-of-training prompt open in the headset with the pointer.

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
- Movement speed follows the aim direction, not where you look: sprinting
  and the slow backward walk are judged against the hand's aim.
- Only one setup has been tested: an RTX 4090, a Quest 3 and Virtual
  Desktop.

## Planned

Already in the pipeline; no need to request these:

- A broad haptics pass: firing, melee contact, block, sight, damage taken,
  interaction and pointer hover, with per-event strength options.
- Proper two-hand weapon support with saved per-weapon grips (today's
  session-only prototype behind chat commands is not the feature).
- Left-hand dominant presentation.
- Bindings for controllers other than Touch (Index, Vive, WMR, Pico) and
  checks on other OpenXR runtimes (SteamVR, Meta Link) and other headsets.
- Verification on AMD and Intel GPUs.
- Independent weapon origins on mission servers, and coverage of the
  remaining mission actions (rescue, spectating, extraction, reconnect).
- Pointer text entry, so the character name does not need a keyboard.
- Performance work on the stereo render cost and on frame-generation
  artefacts around HUD objects.

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
