# Turning sectors, reticle scale and binding labels

The user confirmed that melee aiming is fixed in the 09:44 UTC wrist/feedback
build. This confirms the reported aiming problem; it does not establish
remote-server damage or acceptance of the other menu/HUD changes.

The requested update is installed following the user's "Restart now" reply:

- Right-stick turning now requires abs(x) > abs(y), limiting turning to within
  45 degrees of either horizontal direction. Up/down shortcuts require the
  complementary sector. Exact diagonals belong to vertical shortcuts. Existing
  magnitude deadzones remain; a snap rearms only with both axes near centre,
  not by passing through up/down. Horizontal shortcuts when turning is off also
  use the same separate sectors. Saved bindings and turn speed/mode remain.
- Crosshair Scale is now a live numeric VR option, 25-150% in 5% steps, default
  70%. The gameplay crosshair quad is initially 70% of its old dimensions. Charge
  and hit-feedback sizes and offsets use the same factor, including near/far
  size caps. The target position, aim, menu pointer and melee sweep guide do not
  change size or position. The viewer and Lua scale changes deploy together.
  The mod publishes the validated percentage on initialization/settings changes
  to darktidevr_crosshair_scale.flag. The runner supplies its game-root-derived
  path in a scoped environment variable; the viewer reads it four times per
  second and retains the prior value on missing/partial/invalid input. Its
  fallback is 70%. This file is persistent settings transport, not a one-shot.
- VR HUD and menu binding labels use non-breaking spaces, preserving names such
  as L Grip as a single token. Ability badges fit to a width with two logical
  pixels of padding and re-fit if another update changes the applied font size.
  Font size restores outside VR. New rendering still requires worn acceptance.

## Build and validation

Windows x64: six relevant CTest fixtures pass (turning, controller_bindings,
controller_prompts, menu_prompts, scanner_stick_reference, crosshair_feedback).
The turning fixture samples 720 directions in smooth, 45-degree snap and
90-degree snap modes against the actual shortcut mapper and rejects overlap.
It checks the exact diagonal and centre-only snap rearm. Updated existing
fixtures cover sector transitions, non-breaking labels, fitting and 70% feedback
scale. Main LuaJIT gate: 56 chunks; focused gate: 49 chunks. Focused turning,
controller prompts and feedback fixtures also pass.

The crosshair quad is owned by the viewer, so a new executable is necessary.
Build ONLY the isolated reticle viewer, based on the accepted ba91dcc viewer
source with the scale multiplier and live setting reader. Its worktree is
D:/Projects/games-xr/Darktide VR reticle size, branch
codex/reticle-size-viewer-2026-09-08. The main/focused Lua branches also retain
the source change for integration, but their viewer sources are not deployment
candidates. No capture/bootstrap DLL was rebuilt or changed.

Configure the isolated viewer with VS2022 x64, using the main checkout's pinned
OpenXRSDK/minhook dependency source paths. Build command:

```powershell
cmake --build 'D:/Projects/games-xr/Darktide VR reticle size/build/reticle-size' --config Release --target darktidevr-xr-harness --parallel 4
```

Build passed. Candidate executable:
build/reticle-size/tests/xr_harness/Release/darktidevr-xr-harness.exe in that
worktree, SHA256 36D60D68E3FA70CDAF136920DAE6D044268B7A4A60851C7D2FEBF3788FA41815.
Main artifacts/unattended/reticle-size-{configure,build}-20260908.log and
reticle-size-viewer-20260908.json record the local build.

## Live deployment

The user's later request for a Crosshair Scale option was incorporated while
the game was closed. The first six-Lua transaction committed; an attempted
viewer backup inside its deployment root was correctly rejected before viewer
mutation. The final three-Lua transaction added the setting, and the viewer
was backed up using its Release folder as the deployment root. Restoring this
update requires reversing the two Lua transactions in reverse order and the
viewer transaction separately.

Local artifacts/unattended receipts: turn-size-lua-deployment-20260908.json,
crosshair-scale-lua-deployment-20260908.json,
crosshair-scale-viewer-deployment-20260908.json,
crosshair-scale-ready-20260908.json,
crosshair-scale-startup-restore-receipt-20260908.json.
The session log is turn-scale-session-20260908.log.

The candidate viewer passed Ready mode with 600 rendered frames. Installed
LuaJIT compilation passed 50 chunks; capture/bootstrap DLL hashes remained
unchanged. The existing app-local loader was preserved. Fresh preview=on
appeared at 10:08:36 UTC; Psykhanium entry passed at 10:09:27. Shared-ready
advanced to 715, with an observed interval of 44.25 fresh plus 44.25 generated
pairs/s and zero fallback or pose mismatches. No mod ERROR/WARNING, feedback,
input, preview or aim-assist fallback errors appeared in the inspected window.
The scale transport contains 70 and the one-shot preview flag is restored.
Live appearance/sector feel remain pending the user's worn observations.

## Relaunch reference

The current game is running for testing. For future approved restarts,
close the current session and wait ten seconds, run the Ready gate,
back up and transactionally install the eight changed focused Lua files plus the
isolated candidate viewer at the launcher's expected viewer path. Do not copy
the full main/focused build. Preserve the existing app-local OpenXR loader if
its hash equals the newly built pinned loader; otherwise review before copying.
Run Ready again with the newly staged viewer before launch, as the viewer has
changed. Gate the installed Lua. Launch with existing precise pair wait,
generated stereo and HUD settings, and a one-shot melee preview flag. Light
is already saved and should not need another forced settings request.

Verify fresh stereo initialization and advancing shared_ready; restore the
preview startup flag after preview=on. Check the new right-stick sectors,
crosshair/feedback size and single-line L Grip label in the headset. Record
the live result before treating this candidate as accepted.
