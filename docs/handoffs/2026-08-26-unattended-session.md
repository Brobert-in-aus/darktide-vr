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

### Fullscreen menu presentation without pointer

- Added a versioned, single-writer shared presentation-state transport named
  `Local\DarktideVR-presentation-state-v1`. Its seqlock snapshot carries mode,
  transition sequence, source extent/crop and maximum panel dimensions.
- The native API publishes `stereo_world`, `flat_loading_or_cinematic`,
  `world_anchored_menu`, `flat_menu` and `disabled/error`. The legacy binary
  event remains as a compatibility fallback, but all new transitions use one
  monotonic transport-level sequence.
- The Lua UI-manager hook maintains the fullscreen-view stack, records view
  flags, recognizes loading/cinematic and explicit menu views, and waits twelve
  updates after the stack empties before restoring stereo. This avoids an old
  UI-world teardown incorrectly overriding the live lobby state.
- Flat modes now fit the captured aspect ratio within a 2 m by 2 m maximum,
  anchor approximately 2 m from the transition-time head pose, discard head
  pitch/roll, and remain fixed in LOCAL space.
- Live logs proved the exact sequence `loading` (2), `stereo_world` (3),
  `flat_menu` for `system_view` (4), then `stereo_world` (5) after close.
- A five-minute XR run recorded 5,564 flat-fallback submissions followed by
  14,744 fresh shared-eye pairs, zero reused frames and zero pair-driven
  timeouts. Only two pose-sequence mismatches occurred; maximum measured angular
  lag was 0.049 degrees.
- Quest evidence is archived at
  `artifacts/unattended/menu-xr/darktidevr-menu-panel.png` and
  `artifacts/unattended/menu-xr/darktidevr-menu-closed.png`: the first shows the
  system menu once on the spatial panel, and the second shows restored stereo.

Two early live attempts exceeded Lua 5.1's 200-local chunk limit. Presentation
state was collapsed into one table, startup then remained clean, and the final
chunk has 196 top-level locals. This was recovered before the accepted run.

### Controller, pointer and Psykhanium foundation

- Added `Local\DarktideVR-controller-state-v1`, a versioned seqlock transport
  for both hands' aim/grip poses, tracking flags, trigger/squeeze/thumbsticks,
  buttons and sample timing. Readers reject malformed and stale snapshots.
- The OpenXR harness now creates Touch-controller and Khronos-simple actions,
  publishes controller samples, and maps the tracked right-hand aim ray to the
  spatial flat panel. This stage is observation-only and cannot inject input.
- Added deterministic panel intersection/crop-to-source-pixel math plus a menu
  input edge state machine. Entering a menu cannot synthesize a click, leaving
  releases any held button, and move/down/up/scroll/back events are explicit.
- A 300-frame VDXR theatre smoke published all 300 controller samples. The
  controllers were asleep, so zero frames were marked tracked; the untracked
  fail-closed path was therefore exercised without user interaction.
- Added an explicitly gated `--enable-menu-input` Windows adapter. It converts
  captured source pixels through the current DPI-aware Darktide client rectangle
  into absolute virtual-desktop coordinates, requires exactly one matching
  foreground window, maps trigger/scroll/Back through `SendInput`, and always
  releases a synthetic left button if focus or menu ownership is lost. The
  ordinary stereo launcher keeps it disabled unless `-EnableMenuInput` is
  supplied.
- The adapter's first 10-second VDXR safety smoke generated 1,079 controller
  samples with sleeping controllers and exactly zero pointer events or injected
  inputs. Unit coverage includes a negative-origin multi-monitor desktop and
  rejects off-source/off-desktop coordinates.
- Added a test-only synthetic two-controller path for unattended runs. Its
  six-phase cycle sweeps each hand across the panel, crosses both, exits through
  both viewport edges, exceeds the 1.5 m reach envelope, invalidates tracking,
  and reacquires. It emits no buttons or triggers and requires the explicit
  `--synthetic-controller-path` flag.
- A 12-second live VDXR system-menu run completed 1,300 synthetic frames and
  every phase (240/240/240/220/180/180 frames). It evaluated 480 in-reach
  right-hand rays with 400 panel hits. Menu injection remained disabled, so it
  dispatched exactly zero OS input events.
- Head-pose transport v6 now carries runtime IPD measured from the two OpenXR
  view poses. The game uses that calibrated separation rather than a hardcoded
  population average. Ogryn scale IPD and physical head translation by
  `1.61 / 1.21` while retaining the game-native elevated clean camera; 64 mm is
  only the pre-XR initialization fallback.
- The same live runtime reported 62.81 mm calibrated eye separation. Startup,
  character-select, hub entry and the system-menu fallback remained clean with
  the matched v6 Lua/native deployment.
- Added a guarded one-shot `dtvr_enter_psykhanium` workflow derived from the
  game's own training-view and Testify path. It consumes a local flag, waits for
  hub game mode plus backend authentication, opens the training view, selects
  `option_button_3`, confirms `play_button`, and accepts either Psykhanium game
  mode (`training_grounds` or `shooting_range`).
- Live evidence proved automatic character-select -> hub -> training-menu ->
  private Psykhanium entry and `GameplayStateRun`, with
  `DARKTIDEVR_PSYKHANIUM result=pass game_mode=training_grounds`.
- That transition exposed a stereo teardown ordering bug: by the time a new
  `CameraManager` is observed, Stingray may already have destroyed the old
  world's `viewports` table. Teardown now clears mod references and leaves the
  old right-eye viewport to normal world destruction; it no longer queries the
  stale `ScriptWorld`.
- The corrected private-Psykhanium run remained clean for a 30-second game
  soak, then a 30-second VDXR projection run submitted 1,794/1,794 frames with
  1,793 fresh stereo pairs, zero reused frames or pair timeouts, one pose-pair
  mismatch, and 0.041 degrees maximum measured angular lag. Controller state
  was published on all 1,794 frames and remained safely untracked while the
  controllers slept.

## Validation commands

```powershell
$cmake = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
& $cmake --preset windows-vs2022
& $cmake --build --preset windows-vs2022-debug
& (Join-Path (Split-Path $cmake) 'ctest.exe') --preset windows-vs2022-debug
& .\tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 600
```

Results: all 26 Release CTest tests passed. The native-capture test now installs the
diagnostic hook set, creates/maps/unmaps an upload buffer and verifies exactly
one matched Map and Unmap. Core math covers cardinal headings, pitched and
vertical views, and non-finite billboard inputs. Presentation tests cover the
shared transport, horizon-locked panel pose and aspect-preserving extent. New
controller and pointer tests cover snapshot freshness/validity, finite panel
intersection, crop mapping, menu input transitions, runtime-IPD transport, and
the complete synthetic offscreen/over-reach/tracking-loss cycle.

The Release validation after producer localization also built
`darktidevr_watch_write` and passed all 21 tests. Live validation used the
EAC-stopped character-select boundary and preserved the required ten-second
Steam close grace between normal runs.

## Next action

Finish live validation of the stale-world teardown fix, then add the explicit
Windows/Lua input-injection adapter behind the tested pointer state machine.
Retain the horizon-lock billboard build for automated soaks, but defer the final
smoke, fog and particle-orientation judgement until the user can wear the
headset.
