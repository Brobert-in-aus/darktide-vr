# HUD follow calculation performance

The follow calculation reuses immutable quaternion component names, avoids its
per-update spring closure and temporary key arrays, and computes the shared
damping exponential once instead of four times. Result and goal tables still
belong to each update. Motion thresholds and arithmetic order are preserved.

`tools/stereo/benchmark-hud-follow.lua` compares the actual module at `feda8df`
with the candidate using 10,000 deterministic moving poses. Every returned
scalar and goal field matches exactly, including quaternion sign changes.
Same-time reuse, backwards time, long gaps and position-jump reset identities
also match. These checks describe this input set, not universal numerical proof.

Five alternating trials, Windows QPC wall time, pinned LuaJIT, 10,000 calls:

| Mode | Baseline median | Candidate median |
| --- | ---: | ---: |
| JIT enabled | 5.3158 ms | 2.1476 ms |
| Interpreter | 9.8451 ms | 5.4570 ms |

With collection paused during measurement, typical temporary heap growth fell
from 10,936.5 KiB to 6,874.4 KiB (37%). Targets are prebuilt equally for both
variants. This measures an isolated calculation, not game FPS, normal GC pauses,
or worn visual acceptance. Nothing was deployed.

Validation: all 69 mod Lua chunks compile with the pinned LuaJIT gate; benchmark
syntax passes; the existing `hud_panel` CTest passes (1/1, 0.03 seconds).
Receipts are ignored local files under `artifacts/unattended/` named
`hud-follow-performance-{benchmark,interpreter,lua-gate,syntax,tests}-20260909.log`.
The baseline copy is `hud-panel-before-follow-performance-20260909.lua` there.
