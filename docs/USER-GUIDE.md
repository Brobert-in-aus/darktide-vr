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
- Virtual Desktop's own settings matter more than they look. Two in
  particular:
  - **FOV tangent.** Below 100 per cent it crops the image the headset
    renders, which costs fewer pixels and gains frames: at 90 per cent the
    eye image goes from 2112x2304 to 1908x2076, about a fifth fewer pixels,
    for roughly a tenth off the time each pair of eyes takes. The mod is
    built to follow whatever you set. If you ever see something drawn in the
    wrong place or the wrong size, say what your tangent is: it has been the
    cause more than once.
  - **Streaming frame rate.** Lowering it can *raise* the game's own frame
    rate, because the compositor and the encoder take a share of the GPU for
    every frame they are given. Going from 120 to 100 took this machine from
    about 55 rendered pairs a second to about 65 to 70. Worth trying both
    ways on yours.
- Optional: Custom HUD (continued), the maintained fork of Custom HUD,
  which the VR mod uses for HUD layout editing. That is the version the
  integration was built and tested against (2.1.6); the original Custom
  HUD uses the same mod id and may work but is untested. Everything else
  works without it.

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
  is set from it, and a character you create or pick later is brought to
  that height when you select it (the creation slider does not stick).
  Repeat the calibration any time from the same screen's button or with
  the chat command `/dtvr_calibration`.
- Cutscenes and videos: hold the right trigger to skip.
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

Everything below lives under Mod Options, Darktide VR. That menu is a short
list of eight sections -- aiming and weapons, your body and hands, the world
around you, the HUD, movement and turning, hub and missions, experimental
features, and the controller bindings -- and a setting that only works while
another is on sits underneath it and appears when you switch that one on, so
the wrist display's size is under the wrist display. Nothing you have already
set has changed; the settings have only moved to where they belong.

- Movement follows the head by default (or the left hand, in Movement and
  turning), turning is snap or smooth on the right stick, and buttons can be
  rebound per action in Mod Options, Darktide VR.
- Default layout: right trigger fires, left trigger aims (or the weapon's
  alternate), right grip is the weapon special, left grip the combat
  ability, X crouches, Y cycles carried items, A jumps and dodges, B is the
  blitz, clicking the left stick sprints, clicking the right stick tags,
  right stick up switches weapon and right stick down interacts and
  reloads. Tutorial and HUD prompts show these badges.
- Firing follows the right hand. Aim stabilisation and the crosshair size are
  adjustable. "Cancel weapon sway (%)" removes the game's artificial weapon
  sway from your shots (0, the default, keeps it), so only your own hands'
  steadiness counts. Holding the sight dims the edges, tightens the reticle and
  steadies the aim ("Aim-down-sights focus" in the options). Melee is on a
  button, block uses the game's guard pose, and a swing preview can be
  toggled with F6.
- The hub is first person by default; "Third-person body in the hub" shows
  the stock character instead, with the right stick orbiting the camera.
- The HUD sits on a fixed panel in front of you; size, distance and text
  scale are in the options. With Custom HUD (continued) installed, the
  layout editor opens in the desktop window from the same options group.
- The game window must keep the desktop focus. If another window takes it,
  frame generation and controller input stop and the HUD shows a warning
  (it can be turned off in the HUD options). Click the Darktide window to
  continue.
- Everything works in the hub, the Psykhanium (including the onboarding
  tutorial), Solo missions and on ordinary mission servers. Game questions
  such as the end-of-training prompt open in the headset with the pointer.
- Either trigger continues past the title screen; hold the right trigger to
  skip a cutscene or video.

### Keyboard and mouse (experimental)

Play seated with keyboard and mouse while the headset shows the game: Mod
Options, Darktide VR, Experimental features, "Keyboard and mouse in VR".

- The mouse moves the reticle inside a deadzone (15 degrees by default);
  past its edge the view turns. Turning your head carries the reticle with
  it. Vertical mouse movement stops at the deadzone edge unless
  "Horizontal mouselook only" is turned off.
- "Recentre view" (default Z) faces the view where you aim from where you
  sit now.
- "Disable controllers" (on by default) ignores the controllers; turned
  off, controllers and keyboard and mouse work together.
- Menus take the mouse cursor, and prompts show your keyboard bindings.
- No controllers to open the options with? Before launching, rename the
  empty `KeyboardMouseOff` file in `mods\darktidevr` to `KeyboardMouseOn`.
  Rename it back to return to the setting in the options.
- Tested seated in the hub, the Psykhanium and part of a mission, with
  horizontal-only mouselook. Full mouselook and remote mission servers are
  less tested.

### Weapon hand holsters (experimental)

Your body and hands, "Weapon hand holsters". Small models of your other
weapon, stim, carried item and device float in a line above your gun hand's
forearm, the weapon nearest the wrist. Reach into one with the other hand and
press grip to equip it; the model your hand is in grows and ticks, and with
"Holster labels" on its name shows above it. The weapon shows its ammo, heat or
special charges beneath it. Your hand counts as soon as your fingertips reach a
model; a grip pressed just before your hand arrives, or just after it has
passed through, still counts; pressing grip on the item already in your hand
gives a double tap (with vibration on) and does nothing else. They hide while
you two-hand the gun or aim down its sights, and in the hub.

### Push to talk with a hand at your mouth (experimental)

The world around you, "Push to talk with a hand at your mouth". Bring your off
hand up in front of your mouth and hold it there for about half a second: your
microphone opens, as if you were speaking into a vox bead, and closes when you
take the hand away. It works alongside your push to talk binding rather than
instead of it, and never while that hand is holding the gun.

### Item radial at your hand (experimental)

Your body and hands, "Item radial at your hand". Hold the carried items
control and three choices appear at your off hand: your carried item, your stim
and your device. Flick the stick towards one to take it. Let go
without choosing and the control cycles through them as it always did, so
nothing is lost by turning this on. While the radial is open the stick picks
rather than turns you. Not in the Mourningstar.

### Full body (experimental)

Mod Options, Darktide VR, Your body and hands, "Full body". A copy of your
own character stands where you do, scaled so that its neck meets your head,
with its arms solved to your controllers: look down and you see your body,
your gear and your gloves rather than a pair of floating hands. It takes a
few seconds to appear after you turn it on, and it spawns a second copy of
your character, so expect it to cost some frames. It is not shown in the
Mourningstar.

**F8** (rebindable, Mod Options, "Body mirror shortcut") stands another copy
a few paces in front of you in the Psykhanium, posed exactly as you are and
facing you, so you can see what everyone else sees. Press it again to remove
it.

### Grab and throw the servo skull (experimental)

Mod Options, Darktide VR, The world around you, "Grab and throw the servo
skull". With the flamethrower servo skull talented, it hovers at your
off-hand side, a little forward, where you can reach it: grip it and it
comes to your hand, and letting go with a target marked sends it. All of
your skulls keep their place as you glance about, swing after you when you
turn, and move up to 30 cm ahead of you as you run, so the one you want to
grab is easier to find.

### Aim zoom (experimental)

Mod Options, Darktide VR, "Aim zoom (%)". While you aim down the sights the
world comes closer by this much, eased in and out with the aim; 12 per cent
by default, up to 30, and 0 turns it off. It needs "Aim focus" on, which
also dims the edges of your view and tightens the crosshair while you aim.

### Wrist display, teammate status (experimental)

- "Wrist display": health (white), toughness (the HUD's blue) and stamina bars
  with their numbers in your off-hand glove's cuff, drawn in front of everything.
  "Wrist display size (%)" resizes it while playing. Not shown in the hub.
- "Teammate status above teammates": each teammate's name, toughness and
  health float above their head at a readable size at any distance, with
  DOWNED, NETTED and similar when they need help. Their panels in the team HUD
  are hidden while it is on; yours stays.

### Two-hand support (experimental)

Mod Options, Darktide VR, Aiming and weapons, "Two-hand support". With a
two-handed gun out, put your off hand on the gun anywhere from just ahead of
your gun hand to the muzzle: the glove slides onto the foregrip (where the
weapon's animation holds it) and, with vibration on, the controller ticks, to
show it is safe to grip. Press grip and
the gun follows the line between your hands, however far apart you move them,
until you let go (or, with "Two-hand grip" set to Toggle, until you press grip
again). Bringing your hands together or crossing them also lets go. The grip
holds through reloads and bashes. The grip point comes from the game's own animation of
each gun, found as the draw finishes and remembered between sessions, so it is
ready as soon as the gun is in your hand; one-handed weapons offer no grip.
Gripping does not aim down sights. Controller bindings, While gripping, lets an
action use a different control while you hold the foregrip; every action
starts on Same as combat. Right-hand dominant only for now. The older
`/dtvr_two_hand_calibrate` command still records a custom grip for the
current session.

"Virtual stock (experimental)": bring a two-handed rifle's butt to your
shoulder and it rests there, aiming from the shoulder to your front hand.
"Aim down sights by raising the gun (experimental)": bring the sights to your
eye to aim down them, and move the gun away to stop. It knows the galvanic
rifle's sight height; other guns learn theirs the first time you aim down
their sights with the button.

### Controller vibration (experimental)

Mod Options, Darktide VR, Your body and hands, "Controller vibration":

- **Informative** vibrates when something happens that you need to know
  about:
  - your hand reaches a gun's foregrip or an armed holster;
  - the two-hand grip takes hold;
  - the last round leaves the clip;
  - a reload finishes;
  - ammo runs low;
  - you take damage, your toughness breaks or you are knocked down or grabbed;
  - a block takes a hit;
  - health runs low or stamina runs out;
  - your combat ability or blitz recharges;
  - weapon heat or peril passes 75 % (and again, stronger, past 90 %);
  - a charged shot is full, or a held melee attack will now release as a heavy;
  - a melee weapon's special turns on;
  - an interaction (revive, pick up, operate) finishes.
- **Immersive** is the feel of your actions: every shot (stronger for heavier
  guns), charging a shot, melee hits and pushes, a light hum while a melee
  special is on or while holding an interaction,
  using your combat ability and toughness hits, plus the grip, holster, empty-clip, reload,
  damage, knockdown and block pulses. It leaves out the low ammo, low health,
  stamina, recharge and 75 % heat or peril notices.

Both modes also tick lightly as the menu pointer moves onto a control and on
a click. "Controller vibration strength" scales every vibration (25-200 %).

### Ammo count at the hand (experimental)

Mod Options, Darktide VR, Aiming and weapons, "Ammo count at the hand".
With a ranged weapon out, the clip count shows on the gun, beside the
receiver just ahead of your hand, with the reserve beneath it, instead of on
the HUD panel. It draws in front of your hand, the gun and the scene. Each
number is white when full and turns yellow, orange and finally red as it runs
out. Reloading fills a ring around the count; if the reload is interrupted
(for example by sprinting), the count shakes and the ring disappears. Weapons
with heat show it as a percentage, and melee weapons
with special charges (such as the Skitarius arc maul) show their charges
beside the hand.

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
- Votes (kick a player, mission flow) cannot be answered in VR yet; their
  prompts read Unbound.
- Markers pinned to the edge of your view, interaction markers and any
  markers beyond the eighth on screen still use the older per-eye drawing,
  and can double at their far edge near the edge of your view.
- Moving chat with the HUD editor is untested. Closing chat causes a brief
  stutter when NVIDIA DLSS Frame Generation is on: the game does this without
  the mod too (about an eighth of a second), and in the headset it lasts
  about twice as long.
- Ground previews, such as the Skitarii flamethrower skull's target area,
  are decals: keep Decals on in the game's graphics settings or they do not
  show.
- Weapon charge meters (for example the Skitarii shock maul's) are on the HUD
  panel as the game draws them; "Weapon charge display" puts a copy at your
  weapon hand, as a count, as the HUD's own bars, or neither.
- The gun hand's glove still follows the character's animation, so it can
  shift slightly while strafing and differs a little between weapons.
- The crosshair may still sit slightly off a gun's iron sights. Stray
  magazine and cartridge parts at the grip have been fixed on the galvanic
  rifle only.
- Two-hand support is right-hand dominant, and moving the right hand while
  gripping can feel off; the virtual stock's shoulder position is an estimate.
- If a crash wipes your game settings, `Darktide VR Mode.bat` option 4
  restores the last good copy.
- Only one setup has been tested: an RTX 4090, a Quest 3 and Virtual
  Desktop.

## Planned

Already in the pipeline; no need to request these:

- Per-event vibration strength options.
- Body holsters (shoulder, hips, chest and belt), with item models showing
  where to reach.
- Fuller two-hand weapon support: staffs and two-handed melee, left-hand
  dominant grips and saved custom grips (the experimental option above
  covers two-handed guns only).
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
