# Turning sectors, reticle scale and binding labels

The user confirmed that melee aiming is fixed in the 09:44 UTC wrist/feedback
build. This confirms the reported aiming problem; it does not establish
remote-server damage or acceptance of the other menu/HUD changes.

The next requested update is prepared but not yet installed:

- Right-stick turning now requires abs(x) > abs(y), limiting turning to within
  45 degrees of either horizontal direction. Up/down shortcuts require the
  complementary sector. Exact diagonals belong to vertical shortcuts. Existing
  magnitude deadzones remain; a snap rearms only with both axes near centre,
  not by passing through up/down. Horizontal shortcuts when turning is off also
  use the same separate sectors. Saved bindings and turn speed/mode remain.
- The gameplay crosshair quad is 70% of its previous linear dimensions. Charge
  and hit-feedback sizes and offsets use the same factor, including near/far
  size caps. The target position, aim, menu pointer and melee sweep guide do not
  change size or position. The two scale changes must deploy together.
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
source with a one-line size multiplier. Its worktree is
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
worktree, SHA256 112EEF05CC8AD06398E64EC3552B345E3E129B946D889B3D43B29C86EFDDF90C.
Main artifacts/unattended/reticle-size-{configure,build}-20260908.log and
reticle-size-viewer-20260908.json record the local build.

## Next launch

The current game is left running. A restart-timing question is pending. On
approval, close the current session and wait ten seconds, run the Ready gate,
back up and transactionally install the six changed focused Lua files plus the
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
