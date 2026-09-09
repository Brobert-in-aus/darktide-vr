# HUD prompt hook allocation cost

9 September 2026, offline Lua candidate, undeployed. Existing HUD prompt scopes
packed every protected call's results into a new table; update hooks did the same
before fitting labels. They now forward results directly through two helper
functions created once at installation. Scope cleanup still runs after pcall,
restores nesting/weapon-switch state, and propagates the original error object.
Multiple returns, empty returns and trailing nils remain intact. Label layout,
bindings, aliases, fitting and refresh criteria are unchanged.

## Pinned LuaJIT validation

All 69 source chunks pass the pinned LuaJIT gate. The existing `controller_prompts`
CTest passes in 0.03 seconds, including nested/error scope restoration and nil
returns. The explicit benchmark also checks zero/five return arities and table
error identity through both hook types. No cached stock gameplay contracts were
expanded or run for this change.

`tools/stereo/benchmark-controller-prompt-hooks.lua BASELINE CANDIDATE` loads the
actual two modules with minimal engine doubles and small callbacks. Five trials
alternate order, 100,000 calls each, after warm-up. Windows QPC measures wall time;
GC is stopped only during each measured loop to expose allocation growth, then
restarted and collected. The baseline is this module at `c95bf9f`, copied to
`artifacts/unattended/controller-prompts-before-performance-20260909.lua`.

Median wall time per 100,000 calls:

| Mode / hook | Baseline | Candidate |
| --- | ---: | ---: |
| JIT enabled, protected scope | 8.6772 ms | 0.0780 ms |
| JIT enabled, update | 8.2272 ms | 0.0201 ms |
| JIT disabled, protected scope | 14.1989 ms | 4.0985 ms |
| JIT disabled, update | 15.4040 ms | 5.5474 ms |

Steady baseline heap growth is about 16,406 KiB per loop, or 17,188 KiB for the
interpreter protected scope. Candidate growth is about 0.047 KiB of measurement
overhead. First JIT trials include small trace-creation allocations.

These callbacks deliberately do little: JIT can heavily simplify candidate calls,
so its very small timings are not forecasts for real HUD work. The allocation
removal is also observed without JIT. Stopping GC exposes allocation volume, not
normal game GC pause durations. Game call frequency, total frame-time benefit
and worn acceptance remain unmeasured.

```powershell
tools/stereo/test-darktide-lua-source.ps1
tools/lua/test-lua-syntax.ps1 -SourcePaths tools/stereo/benchmark-controller-prompt-hooks.lua
build/dependencies/luajit/src/luajit.exe tools/stereo/benchmark-controller-prompt-hooks.lua BASELINE CANDIDATE
build/dependencies/luajit/src/luajit.exe -joff tools/stereo/benchmark-controller-prompt-hooks.lua BASELINE CANDIDATE
ctest --test-dir build/xr-frame-stage-timing -C Release -R '^controller_prompts$' --output-on-failure
```

Receipts in `artifacts/unattended`: `prompt-performance-lua-gate-20260909.log`,
`prompt-performance-benchmark-syntax-final-20260909.log`,
`prompt-performance-benchmark-final-20260909.log`,
`prompt-performance-interpreter-20260909.log`, and `prompt-performance-tests-20260909.log`.
The earlier coarse-clock benchmark is superseded by these QPC timings.

No deployment, game, settings or headset change. A future focused Lua deployment
must preserve the accepted baseline, pass Ready and retain the installed Lua gate
and fresh stereo-initialisation/shared-ready checks.
