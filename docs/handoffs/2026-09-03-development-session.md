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
description-mismatch recreations and no code-89 failures. The complete
600-second run then passed with 28,125 of 28,125 submitted frames, 14,907 fresh
shared pairs, and zero reused pairs, pose mismatches, capture failures, stale
frames or pair-driven timeouts. Visual extent and laser alignment still
require a worn check.

## Tracked-hand surface visibility

The hands-only profile proxy reports four enabled body-skin meshes and four
enabled glove meshes, but those counters did not identify which resource
actually reached the render graph. A candidate `lua_visible` flow event was
tested on the body-skin slot because unit and mesh visibility can coexist with
a retained hidden equipment-flow state.

A fresh authenticated five-minute hub run initialized the module cleanly,
reached nonzero `shared_ready`, and passed with 18,002 of 18,002 submitted
frames, 11,080 fresh pairs, and zero reused pairs, pose mismatches, capture
failures, stale frames or pair-driven timeouts. Direct readback under inactive
controller tracking contained a rendered right-hand/glove surface, proving
that at least one proxy surface reaches the render graph. This did not isolate
the body-skin contribution or establish independent two-hand behavior.

The follow-up 150-second offline Psykhanium matrix exercised both tracked
hands plus repeated one-second tracking-loss/reacquisition windows. Both proxy
chains became active, equipment-hand ownership stayed on the tracked proxy for
7,200 sampled syncs, maximum positional error remained `0.000001 m`, and
maximum angular error remained `0.002058 rad`; no presentation-disable or Lua
error was logged. A concurrent direct-eye capture could not advance because
the offline producer retained readiness generation 1, so this is pose/hold
telemetry rather than new visual evidence.

A production OpenXR synthetic follow-up supplied the missing direct-eye
evidence. It made the remaining defect unambiguous: `astra_gloves_b` includes a forearm cuff
skinned across the stock elbow-to-wrist chain, and that cuff balloons into a
large detached sleeve around extended tracked poses. The hands-only proxy now
briefly retained `slot_body_arms` plus the required unarmed record only and
recursively hid all attachment units. A second production matrix proved that
the body-skin slot contributes no visible hand surface in this presentation;
all sampled phases lost the hands while the gameplay-owned weapon remained.
That failed skin-only experiment was rejected and the prior glove selection
restored, along with removal of the unproven body-slot flow change. The next implementation must use a genuinely hand-local visual
resource or controlled mesh duplicate rather than hiding the only rendering
attachment.

## Launcher Play retry

The first Play press in that run moved WPF's `Process.MainWindowHandle` to a
tiny auxiliary window but did not start Darktide. The original authenticated,
titled launcher window remained alive and accepted a second press. The launcher
helper now retains that exact window handle and retries its already-validated
Play region every three seconds while rechecking process ownership, title and
client geometry. It still succeeds only after the configured Darktide
executable appears and otherwise fails at the existing deadline.

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
.\tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 120
.\tools\stereo\test-darktide-lua-source.ps1
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 300 -GameStartTimeoutSeconds 600 -AutoEnterHub -SkipDeploymentSync
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-flow-visible-20260903 4 2496 2688
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-synthetic-controller-publisher.exe --seconds 360 --weapon-aim-matrix --neutral-body-pose
.\tools\stereo\start-darktide-vr.ps1 -OfflineDualViewBenchmark -SyntheticWeaponAimMatrix -DurationSeconds 150 -GameStartTimeoutSeconds 600 -SkipDeploymentSync
.\tools\stereo\start-darktide-vr.ps1 -SyntheticWeaponAimMatrix -DurationSeconds 180 -GameStartTimeoutSeconds 600 -SkipDeploymentSync
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-flow-production-synthetic-20260903 12 2496 2688
.\tools\stereo\start-darktide-vr.ps1 -SyntheticWeaponAimMatrix -DurationSeconds 120 -GameStartTimeoutSeconds 600 -SkipDeploymentSync
```

The Lua source gate passed at 198/198 file-scope locals throughout. The native
hook and rebuilt shared-surface tests passed. Mandatory preflight reports for
the later hand-surface work include
`artifacts/unattended/preflight-20260902T212336Z.json` and
`artifacts/unattended/preflight-20260902T213527Z.json`.

## Next work

1. Build a genuinely hand-local visual proxy or controlled glove-mesh duplicate
   that excludes the stretched forearm cuff; the body-skin-only fallback has
   been disproved by direct captures.
2. Perform the worn Options extent, cursor and representative control pass;
   do not change the proven pointer transform without contrary evidence.
3. Perform the required worn Penances clustered-light acceptance.
4. Complete worn independent-hand acceptance, then continue HUD and
   world-marker resolution/placement work.
