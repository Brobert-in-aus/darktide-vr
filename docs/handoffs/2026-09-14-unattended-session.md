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

## Chat-close stall (queue item 2), in progress

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
update), not from the cursor. Resource-creation trace runs are next.

The Lua-side resource trace (`chat N trace`: `Renderer.create_resource` and
`destroy_resource`, world and screen GUI creation and destruction, viewport
and shading environment creation, `Gui.create_material`; 8 functions wrapped)
recorded no call around any open or close, with or without the viewer. The
game-started viewer run repeated the close stalls (247-264 ms, 275-291 ms
after close) and 62-74 ms frames 166-237 ms after each open. So no Lua code
creates or releases GPU resources at that moment; the stall is inside the
engine's present.

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