# Unattended development session — 2026-08-26

## Active scope

Execution follows `docs/phase1/unattended-development-plan-2026-08-26.md`.
The Quest remains EAC-inactive and testing is limited to synthetic OpenXR,
character select, the non-interactive hub and the single-player Psykhanium.

## Accepted checkpoints

### Preflight and runtime health

Added `tools/unattended/invoke-unattended-preflight.ps1`. It:

- requires exactly one authorized Quest and verifies its model;
- reapplies the temporary proximity override unless explicitly skipped;
- records only the Quest model/count and power state, not its serial or IP;
- verifies Virtual Desktop and the active OpenXR runtime;
- distinguishes Darktide, its launcher and its crash reporter by exact process
  name/path rather than broad process-name matches;
- records EAC state and hashes the game, deployed mod/native files and current
  source/build outputs; and
- optionally runs a bounded synthetic OpenXR smoke test.

Live validation submitted 600/600 rendered frames through VirtualDesktopXR at
approximately 117 Hz. The first `xrCreateInstance` call was retried internally
by the existing harness and the same run then completed successfully, so no
Virtual Desktop restart was justified.

### Billboard producer discovery foundation

- The retired live descriptor-table/shadow-heap billboard write mode now fails
  closed. Its bounded selector/counters and the accepted per-PSO shader fallback
  remain available.
- Diagnostic resource hooks now track buffer `Map`/`Unmap`, associate the CPU
  base with the recorded GPU virtual-address range, and expose aggregate counts.
- An exact reflected `c_billboard` observation records whether it came from a
  persistent engine mapping and exports a selected persistent CPU address only
  when that address remains valid. A temporary diagnostic `Map` is never
  exported as a writer-breakpoint target.
- Added a production-independent Z-up cylindrical basis calculation with
  deterministic vertical/invalid-input fallback.

## Validation commands

```powershell
$cmake = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
& $cmake --preset windows-vs2022
& $cmake --build --preset windows-vs2022-debug
& (Join-Path (Split-Path $cmake) 'ctest.exe') --preset windows-vs2022-debug
& .\tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 600
```

Results: all 21 CTest tests passed. The native-capture test now installs the
diagnostic hook set, creates/maps/unmaps an upload buffer and verifies exactly
one matched Map and Unmap. Core math covers cardinal headings, pitched and
vertical views, and non-finite billboard inputs.

## Next action

Build and deploy the diagnostic-only Release native DLL/mod, run a clean
character-select capture, and inspect `tracked_maps`, the selected persistent
address flag and the bounded `c_billboard` samples. If a persistent address is
found, attach a scripted data breakpoint to identify its CPU writer. If not,
move to fullscreen-menu presentation while retaining this instrumentation for
the next billboard pass.
