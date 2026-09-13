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

## Shutdown crash (queue item 1), in progress

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
leftover callbacks only log. Bisection of `install_hooks` by stage is next
(`darktidevr_install_bisect.flag`, dev-only).
