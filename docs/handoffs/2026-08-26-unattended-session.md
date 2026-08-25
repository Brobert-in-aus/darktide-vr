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

### Billboard producer localized and first safe patch

- The D3D12 bootstrap now reads an explicit diagnostic sidecar before native
  hook installation. This fixes the startup-order conflict where Lua requested
  diagnostics after the proxy had already installed the non-diagnostic hook
  set. Missing diagnostics now fail the Lua stereo setup closed rather than
  dereferencing a nil native interface.
- Exact billboard resources are normally mapped, copied and unmapped before
  their draw. Their Map stacks consistently resolve through
  `Darktide.exe+0x7d589d` to the Stingray upload flush beginning at
  `Darktide.exe+0x7d5840`.
- The upload flush is enabled only when the current executable matches a
  reviewed 12-byte signature. It exposes the persistent CPU staging allocation
  corresponding to each D3D12 upload resource without changing the upload.
- A bounded write watcher hit the selected staging address 32/32 times at the
  instruction ending at `Darktide.exe+0x670395`. Disassembly identifies the
  writer as the SIMD per-instance matrix composer beginning at
  `Darktide.exe+0x66fa70`; the write itself is the 16-byte store at `+0x670390`.
- The first horizon-lock path now writes only six approved basis floats in the
  persistent staging CBV after exact reflected billboard identity is proven.
  It does not alter descriptor heaps, root tables or GPU-visible allocations.
- A 35-second clean character-select soak recorded 11,404 exact billboard CBVs
  and exactly 11,404 staging patches, with the fingerprinted upload hook active
  and no Lua, engine, D3D12 device-removal or device-hung error.

The standalone debugger watcher is diagnostic-only. It produced the needed
writer evidence, but Darktide exited after debugger detachment and opened Crash
Reporter. Do not repeat that attachment in ordinary validation; no crash report
was submitted.

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

The Release validation after producer localization also built
`darktidevr_watch_write` and passed all 21 tests. Live validation used the
EAC-stopped character-select boundary and preserved the required ten-second
Steam close grace between normal runs.

## Next action

Begin fullscreen-menu view classification and presentation-state transport.
Retain the horizon-lock build for automated soaks, but defer the final smoke,
fog and particle-orientation judgement until the user can wear the headset.
