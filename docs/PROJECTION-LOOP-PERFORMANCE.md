# Projection loop allocation performance

Binocular visibility and HUD-width calculations now reuse immutable corner signs.
Visibility tangent values are calculated once per eye iteration. Corner order,
quaternion operations and projection bounds are unchanged; no frame-spanning
cache or engine temporary is retained.

The explicit `tools/stereo/benchmark-projection-loops.lua` harness compares the
actual baseline at `bf14ce2` with the candidate over 2,000 varying asymmetric,
pitched frusta and panel distances. Visibility scale, width and center match
exactly for this input set. Mathematical table-backed engine value doubles are
used; this is neither engine timing nor worn visual acceptance.

Five alternating trials, Windows QPC, pinned LuaJIT, 2,000 paired calculations:

| Mode | Baseline median | Candidate median |
| --- | ---: | ---: |
| JIT enabled | 2.4318 ms | 1.5641 ms |
| Interpreter | 28.7734 ms | 27.9977 ms |

The interpreter timing difference is small relative to the overlapping ranges.
One representative pair uses 10 tangent calls instead of 34. Ten short-lived
sign arrays are removed per pair; with collection paused, heap growth falls by
about 1,718.75 KiB over 2,000 pairs. Absolute allocation includes the mathematical
engine doubles and differs substantially with JIT optimisation. The useful
evidence is eliminated Lua arrays and repeated tangent calls; actual engine
performance remains unmeasured.

An initial numeric-loop rewrite regressed the JIT benchmark and was discarded.
The retained change preserves the existing `ipairs` loops and shares only the
constant sign array. All 69 mod chunks compile, benchmark syntax passes, and
existing `projection_math` CTest passes (1/1, 0.03 seconds). No deployment.

Final receipts in ignored `artifacts/unattended/`:
`projection-performance-shared-signs-20260909.log`,
`projection-performance-shared-signs-interpreter-20260909.log`,
`projection-performance-{lua-gate,syntax,tests}-20260909.log`.
Earlier `projection-performance-benchmark-20260909.log` and
`projection-performance-interpreter-20260909.log` describe the discarded variant.
