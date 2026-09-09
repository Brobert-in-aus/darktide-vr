# Feedback quad allocation review

10 September. Production code remains unchanged. Removing temporary default
offset/pivot tables from `Feedback.quad` did not reduce steady-state allocation
under pinned LuaJIT. Do not repeat this as an untried optimisation.

The corrected candidate matches 2,000 actual-helper geometry cases, including
partial/default offset and pivot values. An initial candidate changed the absent
offset's layer from zero to one; the comparison caught that and it was corrected
before measurement. Returned tables and default color/UV storage remain fresh;
explicit color/UV objects remain borrowed. No engine hooks or renderer run.

Five alternating trials of 100,000 calls vary the angle each iteration and
consume geometry, layer and sample style fields in a checksum. Garbage collection
is paused during timing. Explicit UV/color inputs avoid unrelated default-array
cost in the timed workload. The earlier width-only exploratory timing is not
used for this decision.

| Workload | Default LuaJIT baseline / candidate median | Interpreter baseline / candidate median |
| --- | ---: | ---: |
| Default offset/pivot | 6.2760 / 6.0157 ms | 25.1594 / 20.5994 ms |
| Explicit offset, default pivot | 7.0858 / 6.7985 ms | 21.5164 / 20.3717 ms |
| Explicit offset/pivot | 7.7482 / 6.9472 ms | 20.9829 / 21.1129 ms |

Steady default-JIT heap growth is 0.125 KiB for both versions in all workloads.
Default/offset timing ranges overlap; the explicit case improves in this run
despite having no default arrays to remove. Interpreter default-case allocation
falls by 18,750 KiB, but that does not establish a production JIT allocation win.
These are pure-helper measurements, not the engine's complete draw path or FPS.
Retain the existing implementation rather than shipping an allocation claim
unsupported by the normal-mode evidence.

Baseline: `4f77aa5`. The reproducible candidate is stored as
`tools/stereo/feedback-quad-candidate.patch`; apply it only to an isolated copy
of that baseline, not the installed mod. The explicit benchmark accepts baseline
and candidate module paths:

```powershell
& build/dependencies/luajit/src/luajit.exe tools/stereo/benchmark-feedback-quads.lua BASELINE.lua CANDIDATE.lua
& build/dependencies/luajit/src/luajit.exe -joff tools/stereo/benchmark-feedback-quads.lua BASELINE.lua CANDIDATE.lua
```

Both runs pass comparison checks. Final production module restored byte-for-byte;
all 69 Lua chunks compile. Receipts under `artifacts/unattended/`:
`feedback-quad-full-output-20260910.log`, `feedback-quad-interpreter-20260910.log`,
and `feedback-quad-final-lua-gate-20260910.log`. No deployment or staged changes.
