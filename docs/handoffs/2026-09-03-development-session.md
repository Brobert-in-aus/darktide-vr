# Development-session handoff — 2026-09-03

This session continued from
[`2026-09-02-development-session.md`](2026-09-02-development-session.md).
Read `AGENTS.md`, both handoffs and
[`../phase1/todo-2026-09-03.md`](../phase1/todo-2026-09-03.md) before the next
edit, build, synchronization or launch.

## Session state

- Branch remains `phase0/feasibility-bootstrap`.
- The unrelated user-owned `Codex Image 25 Aug 2026, 08_53_34.jpg` remains
  untracked and untouched.
- The 20-minute development heartbeat is active.
- Worn acceptance of the clustered-light correction and visible fleshy hands
  remains pending. Unattended counters and captures are not substitutes for
  those checks.

## Unattended title transition

The first authenticated run stopped at the title screen because its one-shot
Space arrived before the title view accepted input. The hub helper now retries
Space every two seconds only until the console log proves `StateMainMenu`.
That log-owned boundary prevents retries leaking into character select or the
hub. The source gate now requires the title retry as well as the existing
character-select retry.

The follow-up launch reached `StateGameplay` without manual title input.

## Settings retained-surface format fix

New presentation telemetry recorded all three extents involved in the report:

- the physical captured Windows client is `1920x1080` (`1536x864` through the
  launching process's 125% DPI view);
- SystemView mode 5 was published as `2496x1404` after
  `RESOLUTION_LOOKUP=2496x2688`, scale `1.3`;
- OptionsView mode 4 used a `2496x2688` source with centered
  `2496x1404` crop.

A deterministic desktop activation opened the real Options row. The native
menu-resource trace then exposed the actual failure: OptionsView's completed
retained layer is `R8G8B8A8_TYPELESS` with an `R8G8B8A8_UNORM` RTV. The direct
menu surface already had the correct typed UNORM mailbox identity, but the
copy path discarded the RTV type and requested a typeless replacement. Every
capture returned code 89 because recorded direct-menu command lists correctly
prevented replacing their live shared resource. This was the repeated failure
behind the stale/partial settings surface, not a pointer-scale guess.

The copy policy now canonicalizes this exact typeless backing resource to its
typed UNORM shared surface. Unit coverage checks both the typeless conversion
and a non-typeless pass-through. In the clean deployed follow-up, the first 173
observed Options retained-layer copies all returned `result=0`, with zero
description-mismatch recreations and no code-89 failures. Visual extent and
laser alignment still require a worn check.

## Runtime evidence

The initial 30-minute hub run completed with:

- `result=pass`, 163,308/163,308 submitted OpenXR frames;
- 40,668 fresh shared pairs and zero reused shared frames;
- zero pair-pose mismatches, capture failures or stale-frame failures;
- clustered-light correction at 564,414/564,414 patches, with zero rejects,
  root misses or resource misses at the last live report.

Window and shared-eye diagnostics are under ignored
`artifacts/unattended/*-20260903*`. An accidental `--help` invocation of the
window-capture helper was moved intact to
`artifacts/unattended/accidental-eye-capture-help-20260903`; no repository
source was removed.

## Validation commands

```powershell
.\tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 120
.\tools\stereo\test-darktide-lua-source.ps1
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 1800 -GameStartTimeoutSeconds 600 -AutoEnterHub
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr_native_capture
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr-shared-eye-surfaces-tests
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release -R 'shared_eye_surfaces|native_capture_hooks' --output-on-failure
.\tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 120
.\tools\stereo\test-darktide-lua-source.ps1
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 600 -GameStartTimeoutSeconds 600 -AutoEnterHub -EnableMenuInput -EnableMenuTestControls -SkipDeploymentSync
```

The Lua source gate passed at 198/198 file-scope locals throughout. The native
hook and rebuilt shared-surface tests passed. The second mandatory preflight
report is `artifacts/unattended/preflight-20260902T204605Z.json`.

## Next work

1. Let the current bounded Options run finish and confirm its final harness
   result and absence of device-removal/Lua errors.
2. Perform the worn Options extent, cursor and representative control pass;
   do not change the proven pointer transform without contrary evidence.
3. Perform the required worn Penances clustered-light acceptance.
4. Restore independent visible default hands/gloves, then continue HUD and
   world-marker resolution/placement work.

