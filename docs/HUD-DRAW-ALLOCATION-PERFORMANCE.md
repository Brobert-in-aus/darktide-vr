# HUD draw wrapper allocation cost

9 September 2026, offline Lua candidate, undeployed. Three protected draw wrappers
now forward return values on the Lua stack instead of packing a temporary table:
marker GUI redirection, stock crosshair suppression, and fixed-HUD scale routing.
Helpers are created once. They retain renderer/widget/scale restoration before
returning or propagating an error, including original error objects and trailing
nil return values. Drawing, visibility rules, projection and scale values are
unchanged. Other HUD paths which retain results across later work still use packs.

## Validation and measurement

All 69 source chunks pass the pinned LuaJIT gate. Existing `marker_gui` and
`hud_panel` CTests pass, 2/2 in 0.04 seconds, including resource reuse/teardown,
GUI/widget restoration and scale restoration on exceptions. The explicit
benchmark adds zero/five return-arity and table-error identity checks through
actual before/after marker and crosshair functions with small renderer doubles.
The fixed-HUD scale wrapper is covered by the existing check, not this benchmark.

`tools/stereo/benchmark-hud-draw-hooks.lua BASELINE_DIRECTORY CANDIDATE_DIRECTORY`
compares modules copied at `89c274c` with this candidate. Baselines are retained
in `artifacts/unattended/hud-draw-before-performance-20260909`. Five alternating
trials measure 100,000 calls with QPC after warm-up; GC is stopped during each
loop to expose allocation volume, then restored and collected.

Median wall milliseconds per 100,000 constructed calls:

| Mode / draw wrapper | Baseline | Candidate |
| --- | ---: | ---: |
| JIT enabled, marker | 8.7553 | 0.0967 |
| JIT enabled, crosshair | 7.9559 | 0.0223 |
| JIT disabled, marker | 18.1297 | 7.5582 |
| JIT disabled, crosshair | 15.2958 | 5.8341 |

Steady baseline heap growth is roughly 16,406 KiB (JIT) or 17,188 KiB
(interpreter) per loop. Candidate growth is about 0.047 KiB of instrumentation;
first JIT trials also create small traces. Small callbacks let JIT simplify much
of the candidate work, so its timings are not predictions for real rendering.
Allocation removal also holds without JIT. GC-paused volume does not measure
normal game GC pauses; game call frequency, FPS and visual acceptance are open.

```powershell
tools/stereo/test-darktide-lua-source.ps1
tools/lua/test-lua-syntax.ps1 -SourcePaths tools/stereo/benchmark-hud-draw-hooks.lua
build/dependencies/luajit/src/luajit.exe tools/stereo/benchmark-hud-draw-hooks.lua BASELINE_DIRECTORY CANDIDATE_DIRECTORY
build/dependencies/luajit/src/luajit.exe -joff tools/stereo/benchmark-hud-draw-hooks.lua BASELINE_DIRECTORY CANDIDATE_DIRECTORY
ctest --test-dir build/xr-frame-stage-timing -C Release -R '^(marker_gui|hud_panel)$' --output-on-failure
```

Receipts in `artifacts/unattended`: `hud-draw-performance-lua-gate-20260909.log`,
`hud-draw-performance-benchmark-syntax-20260909.log`,
`hud-draw-performance-benchmark-20260909.log`,
`hud-draw-performance-interpreter-20260909.log`, and
`hud-draw-performance-tests-20260909.log`.
No installation, game, settings or headset changes. Preserve the accepted mixed
build and require Ready before any focused deployment; retain installed Lua
compilation and fresh stereo-initialisation/shared-ready checks after Lua changes.
