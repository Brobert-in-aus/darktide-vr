# Keyboard and mouse in VR (experimental)

13 September 2026, branch `codex/keyboard-mouse-vr-2026-09-13`. This is an
offline implementation of a requested seated mode: the headset renders the
game and the player uses keyboard and mouse instead of Touch controllers.
Status at commit: deployed to the user's install and worn through the day in
the hub and Psykhanium. The user accepted the mode, the controller cooldown,
the melee reticle and swing fix, and the hand placement and smoothness ("I'm
happy with that"). Remote-server melee roll acceptance and the items under
Not established remain unverified.

## Settings

A new **Experimental features** submenu is the last group before the combat
controller bindings. Setting ids are unchanged, so saved values carry over.

- **Keyboard and mouse in VR** (off by default). Its children appear under it:
  - **Recentre view** keybind, default `Z`, directly below the toggle. `Z` has no
    stock gameplay binding; menu views use it, and the keybind is not global.
  - **Disable controllers** (on by default). Off, the controllers keep every
    normal function, including hand aim, laser and buttons, and simply add to
    keyboard and mouse. Conflicts between the two are accepted by design.
  - **Horizontal mouselook only** (on by default).
  - **Reticle deadzone (degrees)**, 0 to 40, default 15, for both yaw and pitch.
    The first draft used 4 degrees, the HUD's head-follow threshold, while the
    HUD carried the crosshair; the user asked for a much larger, adjustable one.
- **World-surface markers** and **Online combat rules in Psykhanium** moved
  here from Hub and missions. Both describe themselves as under development.
  Third-person hub, third-person spectating, stereo cinematics and online
  mission input stayed where they were because the alpha release notes present
  them as supported features.

### Starting without controllers

The mod folder ships an empty `KeyboardMouseOff`. At launch the mod asks
Windows (`FindFirstFileA` through the mod's FFI) for `*KeyboardMouseOn*` in
`mods\darktidevr`, so any rename containing that text matches, whatever its
case or extension. Exact names `KeyboardMouseOn` and `KeyboardMouseOn.txt` are
the fallback when the search is unavailable. A match holds the mode on for the
session without saving anything. A first version also saved the mode on; worn,
disabling controllers in the menu and then renaming the file Off relaunched with
keyboard and mouse on and controllers disabled. The 12:58 console log shows
`keyboard_mouse=true controllers_disabled=true` with no switch file, and the
user's settings file held both on. Renaming the file back now always returns to
the player's own saved toggle; `keyboard_mouse` asserts that renaming the file
Off with Disable controllers left on gives working controllers, and that the
switch writes no settings. The toggle's title then reads
"Keyboard and mouse in VR (on: KeyboardMouseOn file)", and its tooltip explains
how to rename the file back. Disable controllers stays adjustable. With
controllers disabled, first-run calibration no longer opens itself at character
select, since capture needs trigger pulls; its button remains. A LuaJIT probe
against a real folder found nothing for `KeyboardMouseOff`, and found
`KeyboardMouseOn` and `keyboardmouseon.txt`.

## Aim model

`darktidevr_keyboard_mouse.lua` holds an aim yaw and signed pitch in Darktide's
convention. Stock `DefaultPlayerOrientation.pre_update` / `HubPlayerOrientation`
integrate mouse look as usual. The mod's existing `hook_safe` seam then reads
the change since its last write as the mouse delta:

1. Head movement first drags the aim to the edge of the keyhole around the
   rendered view (yaw and pitch). Looking around never turns the camera.
2. The mouse delta moves the aim. Yaw beyond the edge turns the scene anchor,
   the same `active_base_rotation` write stick turning uses, and the aim stays
   on the edge. The camera is dragged 1:1 and stops when the mouse stops. It is
   not eased toward the aim afterwards.
3. Pitch beyond the edge is discarded with horizontal-only mouselook. With it
   off, the excess becomes a camera pitch about the anchor's horizontal axis,
   bounded to 80 degrees. It is applied only to the rendered view, never to the
   published yaw-only anchor.
4. The aim is written back to the stock orientation, so firing, movement,
   targeting and the network input columns all follow it through stock code.

The seam records every orientation update. A gap (another orientation class
such as a ledge or forced view), an owner change, or more than 0.25 s without
an update resets the aim to the view instead of reading the stock yaw change as
mouse input. Menus hold the aim, and the existing modal restore writes it back.

The optional third-person hub keeps the stock mouse orbit instead of the
keyhole. A seated player cannot turn to follow the orbiting camera, so the
orbit's yaw change since the last write turns the scene anchor by the same
amount, the write stick turning already makes there. Menus, gaps and owner
changes contribute nothing. Orbit pitch still only raises and lowers the
camera around the body; the headset view stays level. A recentre there faces
the orbit, as it already did with controllers. `gameplay_heading` runs the real
orbit branch for this.

### Melee direction

Controller play rotates a weapon's authored swing by the wrist's roll, snapped
to 45 degrees, chosen while idle and held through the attack and its combo. In
this mode the same stock roll input is chosen from the mouse instead:

- The weapon's first light swing is sampled through the existing preview
  geometry, unrolled and at 45 degrees. The tip's start-to-end movement on the
  aim's right/up axes gives its on-screen direction and which way roll turns
  it, so no roll sign convention is assumed. The result is cached per weapon;
  an unsupported swing is retried each second and keeps the stock swing.
- A moving mouse (at least 0.5 degrees over the last 0.12 s) gives the
  direction. A still mouse swings from the reticle's position toward the view
  centre, so the reticle deadzone's regions choose directions. A centred still
  reticle keeps the stock swing.
- Both are read on the headset's own right/up axes, taken from the rendered
  head rotation rather than Euler angles. Left to right is 0 degrees, bottom to
  top 90. Leaning 45 degrees left and sweeping left to right therefore swings
  up and to the right. The wanted direction is then projected onto the unrolled
  aim's axes to choose the roll.
- The roll is used only while an attack runs. It is written only into that
  fixed frame's input columns, never into the player orientation. The aim is
  turned about its own look direction (`keyboard_mouse_look_roll`), and the
  engine's own rotation picks the yaw/pitch/roll branch with a level-range
  pitch (`keyboard_mouse_input_euler`). These are the columns the sweep reads
  and a server receives. The swing basis is sampled with the same look roll.
- Why: the first version wrote the roll into the stock orientation on every
  update, including idle. The 04:14 worn diagnostics
  (`console-2026-09-13-04.14.46`) showed Darktide's roll turning about the
  level forward axis outside the pitch, not about the look direction. At a
  pitched aim the simulated rotation, and the reticle raycast from it, left
  the aim: 5 degrees off at 45 degrees roll with -7 degrees pitch, pitch
  forced to 0 at 270, and pitch sign flipped at 135. With a still mouse the
  toward-centre rule kept changing that roll, so the reticle was thrown around
  a ring and held near the keyhole edge until a weapon switch cleared the
  roll. The engine decomposed the 135-degree case to 1.1425, 3.0196, 0.7854,
  which the test rotation model reproduces.
- The attack roll is applied in the single `HumanInputHandler.fixed_update`
  hook, after the online-rules capture. A first build registered a second
  hook on that function; DMF keeps one hook per function per mod, logged
  "Attempting to rehook active hook [fixed_update]", and dropped the main
  hook with its controller input and capture for that launch.
  `dmf_unique_hooks` now fails on any repeated object and method across the
  mod's Lua files.
- The choice is logged once per attack as `DARKTIDEVR_KBM melee_roll_deg`,
  with the swing basis. The applied input is logged as
  `DARKTIDEVR_KBM melee_roll_input` with its decomposition error. A frame where
  a controller ray authored the aim keeps the controller's own roll.
- Stock evidence (cached source): the first attack is chosen by the weapon's
  chain (for example the Combat Sword starts left after wield, then right).
  Chain conditions read movement state, not look or mouse input. Every input
  column, roll included, is sent in `rpc_player_input_array`. The server's
  first-person rotation uses it, and `ActionSweep` places its splines from
  that rotation. A local Psykhanium reads the local handler directly, so it
  exercises the simulation rules but not network packing. Acceptance by
  remote servers is unverified.

`keyboard_mouse` covers roll selection over every 45-degree direction for both
roll signs, the swing basis, the motion window, still-reticle directions and the
idle choice held through an attack. `keyboard_mouse_melee` runs the real
headset-relative conversion from `darktidevr.lua`, including the leaned sweep.
Whether each weapon's live swing matches, and how heavy attacks and combos read
with a roll chosen from the first light swing, are unverified.

**Recentre view** increments a request count carried to the viewer. The viewer
applies it like a runtime recentre: position and facing are rebased on the
current head. The resulting recenter generation turns the anchor so that view
looks along the unchanged aim, and levels any mouse camera pitch. A runtime
recentre in this mode does the same.

## Presentation

- The aim is shown by the existing world-depth reticle, raycast from the stock
  first-person pose (the mouse aim with recoil, sway and assist) to the surface
  it would hit. A first draft put the stock crosshair back on the HUD panel and
  moved the panel with the aim. That crosshair sat at HUD distance with vergence
  disparity against distant targets, and was replaced.
- With online rules (missions, and Psykhanium by default) the existing
  stock-pose reticle path already reads the mouse aim. In a private range with
  online rules off, the smart-targeting hook now publishes from the stock pose.
- `publish_gameplay_aim_state` always sends the anchor-relative target point in
  this mode, never the distance-only form the viewer extends along the right
  controller ray. With full mouselook the point is expressed in the pitched
  view frame. The viewer draws a target-point reticle without a tracked right
  controller in this mode; controller play keeps its tracking and reach check.
- World-space charge/hit feedback and the sight vignette follow the reticle as
  in controller play. The stock centre widget stays hidden, and the HUD panel
  keeps its normal head follow.
- In this mode, unless a controller grip is actually tracking, the gloves
  follow the stock animated first-person wrists turned onto the mouse aim, and
  the equipment is moved to them, the path stock melee already uses. This is
  the first deployed behaviour, which the user reports worked in the
  Psykhanium. With controllers disabled, controller aim and grip targets are
  also empty; with controllers enabled and in hand, tracked arms run as usual.
  The body aim constraint uses the mouse aim. The stock first-person hands
  animate around the camera, so the user saw them beside the head. They are
  now moved by one world offset: 40 cm forward along the mouse aim heading
  (never its pitch) and 40 cm down, times the calibrated character scale
  (`keyboard_mouse_hand_offset`, `follow_gameplay_hands(world, rotation,
  offset)`). The animation is unchanged, and the equipment follows the moved
  hands. Controller melee hands take no offset. The offset was worn-tuned to 30 cm forward and 20 cm down, then (with the
  anchor pivot) to 10 cm forward and 10 cm down.
  The user then saw the hands jump while moving, but not while turning. Their
  pose relative to the first-person root is now hung from the VR camera
  anchor, refreshed from the avatar at the IK seam as tracked arms do
  (`keyboard_mouse_hand_pivot`). The rendered first-person root follows the
  smoothed character position, which drifts against that anchor from frame to
  frame while moving; worn check: smooth. Turning only rotates, and the rotation already came from
  the mouse aim. Anchor and first-person
  root heights can differ by a few centimetres, so the tuned offset may need a
  small correction. Superseded attempts: fixed
  simulated grips 40 cm forward and down (placed well but locked the hands),
  and gloves on the third-person wrists (worn test ran with controllers enabled,
  so it was not observed). A report of hands either side of the head came from
  a later pass and remains unexplained; `DARKTIDEVR_IK presentation_blocked`
  reasons are not logged per state, so it is not reconstructed.
  `melee_simulation_visual` runs the real body IK branch and the real
  `keyboard_mouse_hands` gate, and articulated (non-rigid) hands are unverified.

## Input

- With controllers disabled, the gameplay adapter drains the native controller
  reader inactive, so buttons, sticks, turning, bindings, communication wheel,
  push-to-talk, spectator input and the cinematic skip trigger do nothing, and
  controller aim and grip targets are empty. Stock keyboard and mouse handle
  everything. With controllers enabled all of these run as in controller play,
  except during a cooldown. Any keyboard or mouse use in gameplay (a press, a
  held button, mouse or wheel movement, read from the stock `InputManager`
  devices after `_update_devices`) starts it. It ends 3 seconds after the last
  such input. While it runs, `presentation.controllers_suppressed()` is true,
  so the controller aim and grip targets are empty and the hands follow the
  stock animation. No controller ray reaches weapon poses, the online-rules
  input columns, the reticle, the melee preview, smart tagging or the left-hand
  movement reference, and tracked arms do not run. Buttons and sticks keep
  working. Menu frames are not sampled, because the viewer sends controller
  pointing as desktop mouse events there. Transitions log
  `DARKTIDEVR_KBM controller_aim=suppressed|active`. The first version of this
  fix removed controller aim for the whole mode; the user asked for the
  cooldown instead. The 03:24 worn session (log `console-2026-09-13-03.24.51`) showed
  why. The right controller lay idle, controllers were enabled, and it logged
  `tracking_transition right_live` flipping true and false. While it was live,
  the online-rules capture sent its ray as the stock aim
  (`DARKTIDEVR_MELEE input_roll_deg=315 source=wrist`), so the reticle jumped
  between the mouse and the controller. The user saw this with a melee weapon.
  `keyboard_mouse_aim_source` runs the real target functions with a tracked
  controller.
- Controller and menu prompt rewriting is off whenever the mode is on, even with
  controllers enabled, so menus, popups and HUD prompts show keyboard bindings.
- Viewer (`src/xr/main.cpp`): the desktop mouse works in every menu in every
  mode, so any settings state can be undone with it. Keyboard binds were never
  disabled. Whenever no controller ray owns the pointer, the mouse position is
  marked on the panel with the existing target sprite (no laser). A position read
  from the desktop is never sent back as a `SendInput` move, which would drag
  against a real mouse. Controller moves, clicks, scroll and back still dispatch
  as before. With controllers disabled they neither point, click, scroll nor go
  back. This was prompted by a worn case in which saved settings left keyboard
  and mouse on with controllers disabled for a controller player.
- Transport: `Local\DarktideVR-presentation-state-v6` appends `keyboard_mouse`,
  `recenter_request` and `controllers_disabled`. Lua sets them through the
  `dtvr_set_input_preferences_v2` export, which republishes the last
  presentation packet at once and refuses controllers disabled outside the
  mode. Heartbeats keep them current. The viewer and capture library must ship
  together; an older library leaves the mode Lua-only, where the recentre key
  turns the view onto the aim without a positional recentre.
- Packaging: `KeyboardMouseOff` is listed in `runtime-package-files.psd1` and
  required by the package verifier and its fixture.

## Validation

Commands, Windows x64, from the worktree:

```powershell
tools/stereo/test-darktide-lua-source.ps1
cmake -S . -B build/focused-kbm -G "Visual Studio 17 2022" -A x64 -DDARKTIDEVR_ENABLE_HEADSET_TESTS=OFF
cmake --build build/focused-kbm --config Release --parallel
ctest --test-dir build/focused-kbm -C Release -j 8
```

Results: all 74 Lua chunks compile; all 80 Lua tooling and gate tests pass. The
new `keyboard_mouse` fixture covers keyhole drag, head drag, the pi seam, pitch
drag and horizontal-only limits, game pitch limits, zero deadzone, invalid
input, recentre, bounded settings (15 degree default, 0-40), and the observer's
discontinuity, owner, menu and toggle handling. `hud_options` asserts the
Experimental group position and its moved settings. `online_reticle` asserts
this mode sends the world-depth target point even with online rules off. Five
slice-test stubs gained the new queries. Native `panel_pointer` covers the new
source-pixel-to-panel mapping, including a round trip through the ray mapping.
`presentation_state_transport` covers the new fields and the one-shot recentre
tracker.

The full Release suite passes 232 of 236. The four failures are environmental
in this worktree and do not touch changed code. `pipeline_probe_apply` and
`pipeline_probe_fallback` need `build/dependencies/dxc-runtime`, which was not
copied. `dispatch_bundle_reader` and `residency_unwind_index` need the Python
`pefile` module.

Built identities (SHA-256): `darktidevr_native_capture.dll`
`F7D38873F3546A30FE03030CCA650ED70286944AD7C7C61576D8E1E632D06D1B`,
`darktidevr-xr-harness.exe`
`06189BF053C77008831CF10C4F4BF5E2DB0429A515E2586ED0F1842184B2314C`
(Disable controllers and switch-file build), then
`1DCB80CFB3DDC0A758A4B56ECFCE6C48C6320AEB02E077150C8C450354C9F486` with the
mouse always available in menus (deployed; the DLL is unchanged). The fixtures also cover the
controllers-disabled rules, the switch search and its exact-name fallback,
forced mode with an adjustable controller toggle, and the locked menu title;
`presentation_state_transport` covers the new field.

## Deployment for a worn test

13 September 2026, at the user's request. The branch was first fast-forwarded
to `codex/alpha-2-2026-09-12` at `1099d1f`, which the installed mod already
matched; the changes reapplied without conflicts and 82 focused tests passed.
Copied into `D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr`:
`darktidevr.lua`, `darktidevr_controller_aim.lua`, `darktidevr_data.lua`,
`darktidevr_localization.lua`, the new `darktidevr_keyboard_mouse.lua`, and in
`bin` the capture DLL and viewer with the hashes above. Every copy was
hash-verified, and the installed Lua passes the compile gate. The replaced files
are backed up in the main checkout's ignored
`artifacts/deploy-backups/keyboard-mouse-2026-09-13/`; rolling back means
restoring them and deleting `darktidevr_keyboard_mouse.lua`. The package
manifest still names alpha.1; nothing checks it at runtime. No launch was made.

The first worn attempt (12:02 session) found the mode inert. The console log
shows the options view opened at 02:03:18 UTC but no `DARKTIDEVR_KBM` lines:
at 11:58:58 local the main checkout had redeployed `darktidevr.lua` and
`darktidevr_marker_atlas.lua` for `8935cd1`, replacing this branch's main chunk
while its settings files stayed installed. The branch was fast-forwarded to
`8935cd1`, 82 focused tests passed again, and only the combined `darktidevr.lua`
(the one file whose content differed, written with the install's LF endings) was
redeployed; its prior copy is under `redeploy-over-8935cd1/` in the backup
directory. Both checkouts deploy to the same install, so a later deploy from the
main checkout will remove this mode again until the branch is merged there.

After the user reported the mode working, the Disable controllers option and the
`KeyboardMouseOn` switch were deployed the same way. The five changed Lua files
went in with LF endings, the empty `KeyboardMouseOff` was placed, and the DLL
and viewer above were copied together. All copies were verified, and prior copies
are under `disable-controllers-switch/` in the backup directory.

Later Lua-only deployments followed the same pattern, each with its prior files
under a named step directory: controller aim ignored, controller cooldown,
hand offset, reticle diagnostics, melee roll input, single fixed_update hook,
hands on the camera anchor and hands at 10 cm. Temporary `DARKTIDEVR_KBM_DIAG`
logging (big mouse deltas, half-second aim summaries, stick turns, online
captures, melee roll changes) found the melee reticle fault. It was removed
before commit; the once-per-attack `melee_roll_deg`/`melee_roll_input` lines and
the `controller_aim=` transitions remain. At commit the full focused Release
suite passes 240 of 240 with the engine-inspection and DXC dependencies present,
including `dmf_unique_hooks`, `keyboard_mouse_melee_input` and
`keyboard_mouse_aim_source`.

## Not established

- Worn use was seated in the hub and Psykhanium with horizontal-only mouselook.
  Full mouselook pitch, remote missions, and whether remote servers honour the
  melee input roll are not worn-verified. The Psykhanium's local server reads
  the input cache without the network message.
- Hands follow the stock animation without the swing roll, so a rolled swing
  looks like the stock swing while its hit path is rotated.
- The player spawn can register as a large first mouse delta and turn the view
  (seen once at 04:16:11 in the diagnostic session, mode 2).
- The cached reticle point ages by controller-transport sequence. The viewer is
  expected to keep publishing controller samples with idle or absent
  controllers; if it does not, world charge/hit feedback and tag targeting would
  lose the point. The private-range smart-targeting branch has no dedicated
  fixture.
- Articulated (non-rigid) hands fall back to stock animation. The body weapon
  follows the stock third-person animation, not a first-person viewmodel.
- Real mouse clicks outside a windowed game window reach the desktop.
