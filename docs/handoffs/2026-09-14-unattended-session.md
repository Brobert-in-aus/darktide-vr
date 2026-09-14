# Unattended session: 14 September 2026

Branch `codex/alpha-4-2026-09-14`. User at work; no worn checks until the
evening. Brief: [2026-09-14-unattended-brief.md](2026-09-14-unattended-brief.md).
Evening checks: [test-checklist-2026-09-14.md](../phase1/test-checklist-2026-09-14.md).
All results below are unattended evidence, not worn acceptance.

## Start (about 05:50 local)

- Repository clean at `7360833`. Installed Lua files matched `HEAD`.
- Headset: Quest 3 over USB, authorised, awake, charging (73%). Proximity
  override applied (`-Action Disable`). Ready preflight passed
  (`readiness_verified=true`, VDXR session rendered at 118 Hz;
  `artifacts/unattended/preflight-20260914/ready.log`).
- 20-minute heartbeat scheduled (session-only cron).

## Unattended run controls (`bb10184`)

Review of the simulator and synthetic inputs against the game-started
viewer: the viewer's command line is fixed in
`src/producer/viewer_process.cpp` (no synthetic flags), a Steam-launched game
never inherits `XR_RUNTIME_JSON` (the 11 September wrappers set it only for
an externally started viewer and restored it before the Steam launch), and an
external viewer beside the game's would compete for the OpenXR session. The
11 September simulator wrappers and the dev launcher therefore predate the
current install model.

- `darktidevr_external_viewer.flag` ("external"): the mod skips its viewer.
- `darktidevr_quit_game.flag` ("quit"): quits once through the in-game Quit
  route (`multiplayer_session:leave("quit_game")` in gameplay, which
  `MechanismLeftSession` turns into `Application.quit`; `Application.quit`
  in menus).
- `tools/unattended/run-darktide-session.ps1`: Steam + launcher Play, the
  existing one-shot requests to title, hub or Psykhanium, hold, then Quit,
  CloseWindow or LeaveRunning; records exit code, the game's crash marker,
  the quit route and any Windows Application Error fault. `-NoViewer`,
  `-SyntheticControllerPath`, `-RuntimeJson` (simulator) run without or with
  an external viewer. Test: `session_control`.

Finding: with the headset unworn the game-started viewer does not survive.
In the first run the runtime moved the session to STOPPING (states 4, 3, 6)
about 90 s in; the viewer then failed `ID3D12GraphicsCommandList::Close
(theatre)` (E_INVALIDARG) and exited 1, and nothing restarts it. Stereo work
today cannot rely on the physical headset; the external-viewer path with a
synthetic controller path or the simulator runtime is the fallback. The
viewer exiting on a runtime stop is itself a defect to fix (todo).

**Correction (later the same day):** that reading was wrong; see "Viewer
exits: theatre Close failure" below. The 4, 3, 6 states are the viewer's own
exit request during cleanup after the Close failure, not a runtime stop.

## Shutdown crash (queue item 1), fixed

Evidence directory: `artifacts/unattended/shutdown-crash-20260914/`.

Two faults, both only in VR mode:

1. With the viewer attached during gameplay: the game's crash handler logs an
   access violation reading 0x0 at `Darktide.exe+0x5713e6` about 0.3 s after
   `GameplayStateRun` exits (identical 24-frame stack on every occurrence: a
   worker thread in a recursive walk). Reproduced unattended at the first
   attempt (Psykhanium, in-game Quit route).
2. Otherwise: the engine completes teardown (`[Log end]`) and the process
   then faults writing 0x0 at `Darktide.exe+0x6d1702` (Windows Application
   Error; exit code 0xC0000005). Also on a title-screen window close.
   Last night's apparently clean exit (10:21:57) left the same Windows dump.

Controls (title screen, window close):

| Configuration | Exit |
| --- | --- |
| Flat mode (no mod, proxy or native) | 0, clean |
| VR mode, d3d12 proxy removed (patched exe, DMF, mod Lua) | 0, clean |
| VR mode, proxy present, native module removed | 0, clean |
| VR mode, full | fault `+0x6d1702` |
| + Lua exit preparation (viewer stop, projection off, unload cleanup) | fault |
| + native `dtvr_prepare_process_exit` (all MinHook hooks disabled) | fault |
| + dummy swapchain released before its window | fault |

So the post-teardown fault needs the native module's installation, and is not
caused by hooks still being active at exit, the Lua presentation objects, or
the dummy swapchain order. The game's `EventManager [destroy]` warnings about
leftover callbacks only log.

Bisection (temporary `darktidevr_install_bisect.flag`, removed from the code
afterwards): install stopped before anything, after the dummy D3D12/DXGI
objects, or with every hook created but never enabled all exited clean. With
hooks enabled and then selected groups disabled at once: swapchain group
(Present, GetBuffer, GetDesc, GetDesc1, ResizeBuffers, ResizeBuffers1) off
exited clean; command-queue group off still faulted.

Cause: the native module keeps strong references to the game's swapchain
(`game_swapchain`), its present queue (`swapchain_present_queue`) and back
buffers (`camera_output_resources`, `menu_output_resources`,
`present_transition_resources`, filled by the Present path). Nothing released
them before process exit; the module's static destructors released them after
the graphics stack had shut down.

Fix (`783284b`): `dtvr_prepare_process_exit` (native) stops the viewer,
restores the game window's own window procedure, disables all hooks, clears
the back-buffer maps and releases the swapchain and queue; the mod calls it
from `presentation.prepare_game_exit` on `StateGame` exit, after destroying
the right-eye viewport in its live world and the unload cleanup. Also: the
install's dummy swapchain is released before its window.

Acceptance (unattended, final build, native SHA-256 `35AC71B5...0719`):
three consecutive clean VR-mode exits: title window close (exit 0, result
16), Psykhanium in-game Quit with the viewer attached (exit 0, result 20),
hub window close (exit 0, result 20); no crash marker, no Windows Application
Error. Before the fix every VR-mode exit faulted. Worn check: close the game
normally in the evening and confirm no crash report.

## Chat-close stall (queue item 2): stock behaviour

Evidence directory: `artifacts/unattended/chat-stutter-20260914/`. Session
control `chat N` opens chat through the stock `_start_chatting` and closes it
as Back does; the runner's `-ChatCycles` records every frame over 50 ms within
a second of each action (commits `e8d5728`, `5c7ccfc`, `d59aa50`, `115897a`).

Measured in the hub (frame time over 50 ms, time after the action):

| Run | After close | After open |
| --- | --- | --- |
| VR, game-started viewer (5 cycles) | 237-284 ms stall, 280 ms after | 62-74 ms frames |
| VR, `-NoViewer` (3 cycles) | 132-134 ms, 145-148 ms after | none |
| VR, d3d12 proxy removed (no native module, no viewer) | 139-143 ms, 150-155 ms after | none |

Every close stall is the renderer blocked in `present` with the main thread
waiting on the fence, followed by the game's "Panic ... major stall" line.
The stall is not the viewer or the native module (it persists with the proxy
removed; the viewer makes it longer). Closing chat pops the input manager's
cursor (`Window.set_clip_cursor(true)`, then `Window.set_show_cursor(false)`);
probes that toggle each of those alone, and the cursor stack alone, 3 times
each, produced no slow frame. So the stall follows from chat itself leaving
the active state (about 150 ms matches the chat window's fade and scenegraph
update), not from the cursor.

The Lua-side resource trace (`chat N trace`: `Renderer.create_resource` and
`destroy_resource`, world and screen GUI creation and destruction, viewport
and shading environment creation, `Gui.create_material`; 8 functions wrapped)
recorded no call around any open or close, with or without the viewer. The
game-started viewer run repeated the close stalls (247-264 ms, 275-291 ms
after close) and 62-74 ms frames 166-237 ms after each open. So no Lua code
creates or releases GPU resources at that moment; the stall is inside the
engine's present.

Stock control (flat mode: original executable, no mod, no proxy, no viewer;
flat settings profile; hub reached by clicking START; chat opened with the
user's binding, numpad +, and closed with Enter on empty text, key down 100
ms; 5 closes): every close was followed by a 124-126 ms renderer `present`
stall and the main thread's matching wait, 142-150 ms after the key (the
first, 28 ms), with the same "Panic ... major stall" line. No stall after any
open. (A first flat attempt with Enter to open, the stock default, opened
nothing: the user rebinds chat to numpad +.) Evidence: `flat-numpad/`; VR
mode, the VR settings profile and `decals_enabled = true` were restored
afterwards.

Conclusion: the chat-close hitch is the stock game's own, not the mod's. In
VR it is about twice as long (viewer attached) and felt as a stutter. There is
no Lua resource work at that moment to remove; the stall is inside the
engine's present. Not fixable in the mod as far as measured; recorded as a
known limit. Opens cost 62-74 ms frames only with the viewer attached.

Frame generation: DLSS Frame Generation was on in both the VR and the flat
settings profiles (`dlss_g_enabled = true`) for every run above. The user
reports (14 September) that public reports tie the chat hitch to NVIDIA frame
generation. Not measured with it off: graphics settings are not changed
unattended. Evening question: accept as a known issue with frame generation
on, or allow one flat run with frame generation off to confirm.

## Held-item effects placed before the hand pose (queue item 3)

Static read of the stock wieldable slot scripts (run by the visual loadout in
locomotion `post_update`, before the mod's hand pose):

| Script | Placed from | Displaced by the hand pose | Change |
| --- | --- | --- | --- |
| `flamer_gas_effects` | muzzle node each frame | stream origin | move the existing stream (full update would queue impacts, lerp sound) |
| `chain_lightning_hand_effects` | linked to the node | no | none |
| `chain_lightning_link_effects` | hand node to enemy node each frame | root links | `_update_fx(t)` only (full update picks targets with `math.random`) |
| `chain_lightning_ability_hand_effects` | hand, elbow, fingertips each frame | yes | stock placement at dt 0 (creates only when missing) |
| `aim_projectile_effects` | camera, offset to muzzle | near end of the arc only | none (a re-run doubles up to ~100 raycasts) |
| `force_weapon_wind_slash_activation_effects` | sword node and left hand, 1.6 s | yes | stock placement at dt 0 |
| `weapon_shout_effects` | one burst at a node | spawn point | not fixable by re-placement |
| `missile_launcher_effects` | discarded tube prop | not per frame | none |
| `riot_shield_effects` | windup loop each frame; burst once; passive linked | windup loop and burst | `_update_windup_vfx_loop` when the loop exists |

Fix (`68e4ff8`): `darktidevr_scanner_holo.lua` keeps a placer per class and
runs it after the hand pose, as for the scan hologram. Unit test covers every
placer (existing effects only, no full updates). Unattended evidence is
limited to hub runs without errors or fallback lines: the account's hub
character carries none of these weapons, and no Psykhanium weapon selection
exists to equip them without the user's loadouts. Worn check: evening item 3.

## Viewer exits when the runtime stops the session (todo item), fixed

The play loop treated STOPPING like EXITING and left the loop; with the
headset unworn the game then had no viewer until restart. Fix (`262f6df`): on
a runtime-initiated STOPPING the loop ends the session, keeps its swapchains,
waits for READY (still polling the stop file, the game window and the
duration) and begins again. An exit request of our own still ends at
STOPPING.

Reproduction without a headset: new simulator patch
(`tools/simulator/openxr-simulator-v1.5.0-runtime-stop.patch`,
`DTVR_SIMULATOR_STOP_FILE`). Viewer with the game's command line, no game,
25 s: the installed alpha.3 viewer exited at the first stop after 9 s
(`openxr.session_exit=runtime state=6`); the new build paused and resumed
twice and ran to the end (`result=pass`, 2251 frames). Full test suite 244/244.
Installed (viewer SHA-256 `2C5936E8...B5A7`, alpha.3 copy kept in
`artifacts/unattended/viewer-runtime-stop-20260914/`); the following hub run
with the physical headset awake started the game's viewer, rendered the whole
session and stopped with `result=pass`. The E_INVALIDARG `Close(theatre)` seen
this morning was logged after the old loop's exit lines (which of the two came
first is not certain from the merged log) and was not reproduced by the
simulator; worn check: evening item 4.

Not enough with the physical runtime. In a later Psykhanium run (headset awake,
unworn, viewer from `262f6df`), Virtual Desktop reported states 4, 3 and 6 in
one poll and still returned `shouldRender`. That frame failed
`ID3D12GraphicsCommandList::Close(theatre)` with E_INVALIDARG and the viewer
exited before the loop top could pause, so the morning's failure is this
frame, not the old loop exit. The simulator does not reproduce it: its
swapchain images survive a stop.

Fix (`c144f2b`): a stop seen at the poll before `xrWaitFrame` skips straight to
the pause, and layers are rendered only while the session is VISIBLE or
FOCUSED. The simulator stop test still pauses and resumes twice and passes.
Physical-runtime check: the render gate broke startup. With Virtual Desktop,
the first frames after `xrBeginSession` still read READY before events are
polled, so no views were located and the viewer exited at start with
"Invalid recentered projection inputs". Caught in the next run (viewer
`c144f2b`), and the gate was removed in `665ba15`, keeping the skip to the
pause.

With `665ba15` installed, a 6-minute Psykhanium run with the physical headset
(awake, unworn) rendered throughout at 120 Hz and stopped with `result=pass`
on the game's stop file. Virtual Desktop did not stop the session in that
run, so the physical stop and resume path is still unobserved. Worn check:
evening item 4.

## Virtual holsters (queue item 4), core and default-off wiring

Design: [virtual-holsters-2026-09-14.md](../phase1/virtual-holsters-2026-09-14.md).
Commit `baa12ee`: `darktidevr_holsters.lua` (body frame, five zones,
hysteresis, dwell, grip claim), request-only `melee`/`ranged` wield actions
and wield selectors in the bindings' contextual grip claim, option
`vr_holsters` (default off), off in the hub. Tests `holsters` and
`controller_bindings` (the input-name fixture gained the stock `wield_1` and
`wield_2`, both in the game's ephemeral action list); full suite 245/245.

Installed. Psykhanium run with the option off (viewer attached, in-game Quit):
no holster line, no error, `DARKTIDEVR_HELD_EFFECTS placed
class=ChainLightningLinkEffects` with no fallback (the character's weapon has
chain lightning links), clean exit (`native_hooks=20`, exit 0). Evidence:
`artifacts/unattended/holsters-20260914/psykhanium-option-off/`. The option
was not turned on through the option; see the synthetic run below. Worn
check: evening item 5.

Synthetic reach run (`fed373f`, `6c1a2b2`): the synthetic controller
publisher's new `--holster-path` moves the right hand to each zone centre and
squeezes grip, and `darktidevr_holsters_test.flag` turns holsters on without
the saved option. The game ran with no viewer, in the Psykhanium, with the
flag removed afterwards.
- First run: the shoulder zone armed and the ranged weapon came out
  (`wielded_slot=slot_secondary previous=slot_primary`), but no other zone
  armed.
- A trace line showed why: zones were scaled by the character's in-world eye
  height (1.90 m), while tracked hands move in physical metres, so the hip
  point (-0.58 m) was outside the hip zone (-0.72 m, radius 0.14). Fixed to
  the headset's standing eye height (1.70 m from the publisher, times the
  character scale).
- After the fix, over about 35 s:
  - right shoulder: the ranged weapon came out four times;
  - left hip: melee came out four times;
  - left and right chest and right hip: resolved (`ready`) and passed through
    with no request, because this character carries no stim, item or device;
  - the shoulder zone with the gun already out passed through.
  Clean exit. Evidence: `artifacts/unattended/holsters-20260914/synthetic-psykhanium-physical-scale/`.
  Not covered: the left hand, both hands at once, two-hand support
  interplay, zones for items the character does not carry.

## Ammo count at the hand (diegetic HUD backlog), default off

Commit `ecec404`: `darktidevr_ammo_readout.lua` draws the ranged weapon's
clip and reserve (or heat) as world-space slug text beside the dominant grip,
after the hand pose, facing the eye; amber at the stock 20 % low-ammo
threshold or 75 % heat, red when empty or past 90 % heat. The panel's
`slot_secondary` weapon element is skipped while the readout shows. GUI
released on loading, score screen, disable and unload. Option `vr_ammo_readout`
(Experimental features), default off. Test `ammo_readout`; suite 246/246.

Unattended check of the drawing: dev flag `darktidevr_ammo_readout_test.flag`
("front") places sample text 0.5 m in front of the eye regardless of the
option. Psykhanium with the game-started viewer, eye readback requested with
`%TEMP%\darktidevr-shared-eye-readback.request`: the left eye image
(`artifacts/unattended/ammo-readout-20260914/shots/eye-left.png`) shows
"12 | 180" upright, not mirrored, readable, in the stereo render; clean exit.
(The VR-mode desktop window shows a stale loading board, so screenshots of
the window cannot check world-space drawing.) The flag was removed afterwards.
Not checked: placement at a tracked hand, real ammo values (the character
held its melee weapon; no controller input), the panel element hiding. Worn
check: evening item 6.

User direction during the day (14 September), applied and checked in the eye
render with the test flag (which also cycles a 3 s reload, every other one
interrupted at 60 %):
- clip above reserve, each coloured on its own capacity, from white through
  yellow and orange to red (`a18217f`, `86f20e4`);
- a solid reload donut that fills smoothly over a dim track (`20fe0ae`);
- the pair centred in a 3 cm ring (`ded6827`, `eec0b9f`).

Captures in `artifacts/unattended/ammo-readout-20260914/ring-run6` and
`ring-run7` (`readout-*.png`): 32 of 40 near white, a reserve of 60 of 400
orange, the arc filling clockwise from the top, and no ring between reloads.
The shake is timing-based and not caught in a still. Flag removed afterwards.

## Viewer exits: theatre Close failure (reopened), mitigation

The viewer's `ID3D12GraphicsCommandList::Close(theatre)` intermittently
returns E_INVALIDARG. `check` throws, and cleanup's `request_clean_exit`
produces the FOCUSED → VISIBLE → SYNCHRONIZED → STOPPING states that were
first taken for a runtime stop. The viewer exits 1 and the headset stays dark.

Seen three times today with the physical headset:
- the first session run, about 90 s in;
- a Psykhanium run at about 08:20;
- a Psykhanium run at 08:53, 45 s after the viewer started, at the loading →
  gameplay transition.

A 6-minute run between those did not fail. The pause and resume change
(`262f6df`) is correct OpenXR handling of a real stop, but did not address
this; the skip-on-stop in `c144f2b` cannot help either, since no stop precedes
the failure.

Mitigation (`c0913f3`):
- The mod restarts a viewer that exits with an error, at most three times in
  about five minutes. A clean exit or a stop the mod asked for is left alone.
  Test: `session_control`.
- Diagnosis aid: the Close failure prints the frame and, when the viewer runs
  with `--debug-layer`, the D3D12 info queue messages.
- The runner's `-ViewerArguments` starts an external viewer with extra
  arguments.

Root cause, found and fixed (`7f790f4`). The D3D12 debug layer is not
installed (`D3D12GetDebugInterface` 0x887A002D; installing Graphics Tools is a
system change, not made), so the failure was made to describe its own frame
(`caf7a23`), and the previous viewer log is now kept on a restart (`177bd16`,
native module).

The Psykhanium reproduced it every time, about 45 s after the viewer started,
at the loading → gameplay transition (3 of 3 runs). The automatic restart
recovered each run within 2 s. The failing frame recorded only the
shared-menu copy (`shared=0 cached=0 generated=0 menu=1`): the menu copy box
is the published presentation crop, which already described the gameplay
canvas (2112x1188) while the attached menu texture was still the loading
screen's 1280x720. `CopyTextureRegion` records such a box and `Close` rejects
the list with E_INVALIDARG.

The box is now clamped to the source and the destination, and an empty copy
is skipped. After the fix, two Psykhanium runs logged
`openxr.shared_menu_crop_clamped frame=5366 crop=0,0,2112x1188 source=1280x720
destination=2112x1188` (and frame 5424) at the same moment, with no Close
failure, one viewer start each and `result=pass`. Evidence:
`artifacts/unattended/viewer-close-failure-20260914/` (repro-1 to repro-5).
The automatic restart stays as a safety net.

## Whole-body IK: design and pose trace recorder (backlog, milestone 1 part)

- Design document: [whole-body-ik-design-2026-09-14.md](../phase1/whole-body-ik-design-2026-09-14.md)
  (`26350e8`). It covers the joint map, solve order and heuristics, the
  stock-owned state table, the adapter, offline testing and milestones. It is
  based on a read of the body proxy, the IK path, calibration and the earlier
  plans.
- Pose trace recorder (`a506d9e`): `darktidevr_pose_trace.flag` "record"
  appends 30 Hz CSV rows. Test `pose_trace`; suite 247/247.
- In-game check: the synthetic holster reach run with the flag recorded 990
  rows in about 33 s. The right grip columns followed the synthetic zone
  positions (for example 0.13, 0.16, -0.38) and the floor eye height read
  1.70 (the publisher's value). `body_yaw` was empty in that no-viewer run
  (the body presentation's yaw is not published there). Evidence:
  `artifacts/unattended/holsters-20260914/synthetic-pose-trace/pose-trace.csv`.
- Not done: the rig scan (human and Ogryn joint map) and the solver itself.
  One attempt with the existing `darktidevr_body_rig_inventory.flag` ("scan")
  in the Psykhanium produced no inventory lines (the flag was apparently not
  read on that path); not pursued further today.
  Traces recorded worn tonight (evening item 7) are the input for the next
  step.

## Blitz from the belt (VR-native input backlog), default off with holsters

Commit `4571e85`: a sixth holster zone at the front of the belt requests the
stock blitz action (mask 512) for as long as the grip is held. Tests
`holsters`, `controller_bindings` and the synthetic path contract; suite
247/247.

Synthetic run (holster test flag, `--holster-path` now also visiting the belt
with a one-second squeeze): three belt visits, each showing
- `armed zone=belt` then `wield selector=blitz`;
- `delivered=grenade_ability_pressed` on the press and
  `delivered=grenade_ability_release` one second later;
- `wielded_slot=slot_grenade_ability` on the press, then back to
  `slot_primary` 0.46 s after the release, as after a stock throw.

The shoulder and hip zones kept working in the same run (`delivered=wield_2`).
Evidence: `artifacts/unattended/holsters-20260914/synthetic-belt-blitz/`. Not
shown: the projectile itself (no world check), or the aim arc while held.

## Parked with reasons

- **Two-hand support, saved grips.** Recorded grips are bound to the exact
  item object for the session; a test asserts that another item of the same
  template must not inherit a grip. Saving them means choosing a key (the
  weapon template, or the item's gear id), which changes that deliberate
  rule. Left for the user.
- **Reticle charge meter (stretch).** It needs the stock `forcesword_bar`
  material values rebuilt per bar on a world GUI, and a worn A/B before it is
  worth shipping. Not started.
- **SoloPlay survival buff and end-screen vote (optional).** Reaching them
  needs a controller-driven survival run or edits to the SoloPlay mod's
  files. Not attempted.
- **Chat-close hitch.** Measured as stock with frame generation on; waiting
  on the user (see the checklist question).

## Midday regression (installed state at `04638bf`)

Hub and Psykhanium, 90 s each, game-started viewer, all options at their
defaults (holsters and the ammo readout off, no test flags):
- in-game Quit, exit 0, no crash marker, no Windows Application Error,
  `DARKTIDEVR_EXIT prepared ... native_hooks=20`;
- no darktidevr error or warning lines and no script errors;
- one viewer start per run, `result=pass` at the stop.

Evidence: `artifacts/unattended/regression-20260914/midday-hub` and
`midday-psykhanium`.

## Review of the day's changes, and fixes (`b14ad7d`)

An independent read-only review of `7360833..HEAD` found no high-severity
defects and five real ones, all fixed:
1. A hand resting in a holster zone replaced a held (or acquiring) two-hand
   support request and dropped the rifle's support grip. `Holsters.choose`
   now keeps the support request unless a holster claim is already held.
2. The reload shake fired after completed reloads that chain early into
   aiming or firing (for example, the autogun at 3.1 of 3.3 s). A reload that
   added ammo now counts as finished.
3. The viewer's automatic restart used a sliding window, so a missing runtime
   was relaunched three times every five minutes forever. It now gives up
   after three failures in a row of viewers that ran under a minute;
   `/dtvr_viewer start` or `restart` resets the count.
4. The pose trace waited for an old gameplay clock after a level change and
   wrote a second header on a second launch. It now resamples when the clock
   restarts lower and writes one header per file.
5. `main.cpp` now includes `<functional>` and `<sstream>` itself.

Also checked and clean in the review: the holster claim lifecycle, the
request-only actions, DMF hook uniqueness, the engine calls in the readout,
the held-effect fields, viewer stop semantics, pause and resume, the crop
clamp arithmetic and log rotation. Tests 247/247.

After deployment:
- the synthetic holster run wielded ranged, melee and blitz as before;
- a Psykhanium run with the game-started viewer clamped the menu crop at the
  transition (frame 7024), ran to `result=pass` and exited cleanly.

Evidence: `artifacts/unattended/holsters-20260914/synthetic-after-review/` and
`artifacts/unattended/regression-20260914/after-review-psykhanium/`.

## Two-hand support: default grip from the weapon's animated left hand (user direction)

User direction (14 September): use the stock left hand's place on the gun as
the grip location. Commits `4d4c1eb`, `9c5c8c0`, `3bb035e`, `b7101c0`,
`a2fff7c`.

- **Source.** The hidden first-person rig is untouched by the mod, whereas
  the third-person hand bones receive tracked-pose writes. Its `j_lefthand` is
  read relative to its `j_rightweaponattach`, then expressed in the gun's aim
  frame through the weapon's attach-to-muzzle rotation. That rotation is
  sampled from the third-person weapon before gun aim rewrites the attach
  node; gun aim makes the muzzle match the aim.
- **Averaging.** Samples are averaged over 30 frames while the gun is idle,
  aiming or firing, then kept for that item. A calibrated grip for the item
  still wins, and a grip measured on another item is not borrowed.
- **Rejection.** A hand behind or on the grip, more than 25 cm to the side,
  30 cm above or below, or 90 cm away is rejected, which excludes a
  one-handed weapon's idle hand.
- **Rendering.** The support glove takes the authored wrist rotation
  unconverted.
- **Option.** "Two-hand support" (Experimental), default off; the chat
  commands still work for the session. The authored grip holds the grip only
  (no ADS), and the left grip's own action (combat ability) is suppressed
  while held.
- **Holsters.** The measured eye height is clamped to 1.23-2.13 m, because
  the unworn headset on the desk measured 0.89 m and shrank the zones.

Unattended evidence (Psykhanium, external viewer on the physical runtime with
the new `--synthetic-holster-once` path; test flags for holsters and
two-hand):
- `DARKTIDEVR_TWO_HAND authored_grip template=galvanic_rifle_p1_m1
  socket=-0.034,0.329,-0.002 samples=30`: 3.4 cm left and 32.9 cm forward of
  the grip, level.
- Preview flag, eye render (`run2/left-2-gun.png`): the left glove sits on
  the rifle's front half, left of and under the barrel, cuff toward the
  camera. The body proxy's pre-render check shows the glove moved 0.62 m from
  its tracked position to the grip.
- Grip squeeze at the measured foregrip (`run4`):
  `DARKTIDEVR_TWO_HAND held=true source=authored`, no `combat_ability`
  delivery. In the eye render the held glove lies along the barrel, while the
  un-held hand at the same spot shows its free controller orientation.

- Steering (`6dcec30`, `run6`). Each release now logs the largest aim
  correction made while held. The synthetic path lifts the support hand 5 cm
  mid-hold, which should steer about 8.6 degrees (5 cm at 32.9 cm). All 18
  holds logged `released source=authored max_steer_degrees=9.0` with 113-117
  steered frames. The game quit cleanly with no script errors.

Not shown:
- other weapons (only the Skitarius galvanic rifle was available);
- steering on screen (the correction was logged, not captured);
- left-dominant play (not supported by authored grips);
- how the grip feels.

### Grip ready on wield (user direction: "no delay between wielding and being able to grip")

Commits `8349b4f` and `cd68da2`.

- **Per template.** Grips are keyed by weapon template rather than by item,
  and come from four sources in order:
  - shipped: `Support.SHIPPED_GRIPS`, currently the galvanic rifle only;
  - stored: `vr_two_hand_grips_v1` in the mod's settings, from an earlier
    session;
  - settled: a new template gets a grip once the animated hand has stayed
    within 5 mm for 6 frames, which happens during the draw;
  - measured: the first 30 steady frames of the session. This replaces the
    earlier grip (only when not holding) and is stored if it moved by more
    than 3 mm.
- **Cost.** After that, the template is not sampled again that session.
- **One-handed weapons.** A settled grip is dropped after 120 steady frames
  with the hand off the weapon.
- **Evidence.**
  - `run7`, new template: `source=settled` 6 frames (65 ms) after the wield
    log, with the same socket and hand rotation as `source=measured` 1.4 s
    later. The grip was written to the settings file.
  - `run9`, next session: no `authored_grip` line, because the stored grip
    matched. The first hold logged `grip=stored`, and 18 holds steered
    9.0 degrees each.
  - Not shown: other templates, including whether their draw animation rests
    the left hand somewhere plausible that isn't the foregrip. The steady
    average would then replace that grip about a second later.

### Viewer crash at level load: automatic menu readback diagnostic

The viewer crashed in `run8` as the Psykhanium loaded, right after
`openxr.shared_menu_crop_clamped`: access violation 0xc0000005 at +0x235a3,
logged by WER at 12:21:29. The crash ended controller input, so there was no
wield.

- **Locating it.** Relinking the build's own objects with `/MAP` gave a
  byte-identical binary apart from timestamps. The offset falls in
  `run_theatre_lifecycle`'s cropped-menu PPM loop.
- **Cause.** Every menu attach read the menu texture back and wrote two PPMs
  to `%TEMP%`. The cropped one looped over the presentation crop (2112x1188)
  across a 1280x720 texture, past the end of the readback buffer.
  Intermittent: `run7` hit the same clamp and survived.
- **Fix (`cf62729`).** The crop is clamped to the texture, and the readback
  runs only on its request file. This saves two roughly 7 MB writes per menu
  attach in normal play.
- **After the fix (`run9`).** No diagnostic lines, a clean exit and no WER
  events. That run happened not to hit the clamp, so the crash condition is
  fixed by construction and was not reproduced.

Worn check: evening item 8.

### Grip zone slide-on, hold or toggle, any spacing (user direction)

The user decided:
- gripping never aims down sights;
- `/dtvr_two_hand_calibrate` grips are not saved;
- bindings while gripping may need their own set (todo item added).

Commits `8dbd76d` and `e133511`:
- **Slide-on.** Within the acquire radius (10 cm), left 1.5 cm further out,
  the support glove blends from the tracked hand onto the grip, eased over
  0.1 s, and back again when the hand leaves. It stays on while held. The
  body proxy blends from the glove pose already placed that frame, converting
  a calibrated rotation to the joint rotation first.
- **Two-hand grip option.** Hold (default) or Toggle. In Toggle, letting go
  keeps the claim, and the next fresh press ends it; the controller mapper
  blocks that press, so it never reaches the combat ability.
- **Any spacing.** A held grip no longer checks the 20 cm release radius. It
  ends only through the existing guards: hands within 8 cm or crossed (no gun
  direction), lost tracking, weapon or action change, or a menu.

Unattended evidence. The synthetic left hand approaches from 18 cm, lifts
5 cm, spreads 25 cm along the barrel, then lets go.
- **`run10` (hold):** `zone=enter` 0.1 s before `held=true`, and
  `zone=snapped frames=7-8` (about 90 ms).
- **`run11` (hold, with the spread):** all 7 holds logged
  `mode=hold ended=released`. Under the old release radius the spread would
  have cancelled them.
- **`run12` (toggle):** the grip stayed on after let-go while the hand went
  back to rest, and ended at the next cycle's press (`mode=toggle
  ended=released`, about 4 s later). The following press took it again. The
  resting hand dragged the gun up to 109.6 degrees, so the evening checklist
  asks whether toggle should let go past some angle.
- **Not shown:** the slide-on on screen (logged only) and how it feels.

### Bindings while gripping (heartbeat pick-up, user's backlog item)

Commit `28f9cd7`.
- **Setting.** Mod Options, Controller bindings, While gripping has one
  dropdown per action, stored as `vr_grip_action_bind_<action>`. Each
  defaults to -1 (Same as combat), and no value is written until the player
  picks one.
- **Mapper.** A grip claim carrying `layer='gripping'` (only the two-hand
  request does) switches new presses to the layered selection. The hub and
  holster claims keep the normal bindings.
- **Latching.** Every control keeps the mask it was pressed with until it is
  released, so taking or leaving the grip never swaps an action mid-press.
  Remaps and context changes clear the latch, the same way they already
  cancelled holds.

Evidence:
- **Unit test** (`controller_bindings_grip_layer`): a held crouch survives
  taking the grip, X reloads while gripping, the trigger still fires, a held
  reload survives letting go, and holster claims and the hub are unaffected.
- **`run13`** (Psykhanium, synthetic path, no grip bindings set): no script
  errors, 18 holds ended released, none cancelled, and no combat ability
  delivered.
- **Not shown:** an in-game press on a changed binding (that would need a
  saved setting changed), and HUD prompts, which do not follow the layer.

Worn check: evening item 9.
